package authprivacyhttp

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/rankings"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/readtiming"
)

type rankingLoadSample struct {
	WallAt      int64  `json:"wall_at_ns"`
	WallEnd     int64  `json:"wall_end_ns"`
	At          int64  `json:"at_ns"`
	End         int64  `json:"end_ns"`
	Latency     int64  `json:"latency_ns"`
	DispatchLag int64  `json:"dispatch_lag_ns"`
	ClockSkew   int64  `json:"clock_skew_ns"`
	Phase       string `json:"phase"`
	Kind        string `json:"kind"`
	Status      int    `json:"status"`
	Failure     string `json:"failure,omitempty"`
	Inflight    int64  `json:"inflight"`
	AgeMillis   int64  `json:"age_ms,omitempty"`
}

type rankingLoadEvent struct {
	WallAt int64          `json:"wall_at_ns"`
	At     int64          `json:"at_ns"`
	Name   string         `json:"name"`
	Fields map[string]any `json:"fields"`
}

type rankingLoadRecorder struct {
	epoch     time.Time
	clock     *rankingLoadClockProbe
	mu        sync.Mutex
	samples   []rankingLoadSample
	events    []rankingLoadEvent
	raw, logs *json.Encoder
	ioErr     error
}

func (r *rankingLoadRecorder) Enabled(context.Context, slog.Level) bool { return true }
func (r *rankingLoadRecorder) WithAttrs([]slog.Attr) slog.Handler       { return r }
func (r *rankingLoadRecorder) WithGroup(string) slog.Handler            { return r }
func (r *rankingLoadRecorder) Handle(_ context.Context, entry slog.Record) error {
	if !strings.HasPrefix(entry.Message, "global_hotlist_") {
		return nil
	}
	e := rankingLoadEvent{At: r.now(), WallAt: entry.Time.UnixNano(), Name: entry.Message, Fields: map[string]any{}}
	entry.Attrs(func(a slog.Attr) bool { e.Fields[a.Key] = a.Value.Any(); return true })
	r.mu.Lock()
	defer r.mu.Unlock()
	r.events = append(r.events, e)
	err := r.logs.Encode(e)
	if err != nil && r.ioErr == nil {
		r.ioErr = err
	}
	return err
}

// All performance and load scheduling timestamps use one RAW clock origin.
// Wall timestamps are independent business evidence, never duration operands.
func (r *rankingLoadRecorder) now() int64 { return r.clock.elapsedRaw() }

// Go timers are only bounded sleeps. Re-read RAW after every wakeup because
// this machine's Go scheduling clock can run at a different rate.
func (r *rankingLoadRecorder) waitUntil(deadline int64, stop <-chan struct{}) bool {
	for {
		remaining := deadline - r.now()
		if remaining <= 0 {
			return true
		}
		timer := time.NewTimer(max(time.Millisecond, min(time.Duration(remaining), 50*time.Millisecond)))
		select {
		case <-stop:
			timer.Stop()
			return false
		case <-timer.C:
		}
	}
}

func (r *rankingLoadRecorder) add(s rankingLoadSample) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.samples = append(r.samples, s)
	if err := r.raw.Encode(s); err != nil && r.ioErr == nil {
		r.ioErr = err
	}
}
func (r *rankingLoadRecorder) copy() ([]rankingLoadSample, []rankingLoadEvent) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.samples), slices.Clone(r.events)
}

func (r *rankingLoadRecorder) copyEvents() []rankingLoadEvent {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.events)
}

type rankingLoadClockSample struct {
	Elapsed, RawElapsed, Drift, Uncertainty, Wall int64
}

// Cross-check Go's scheduling clock against Linux CLOCK_MONOTONIC_RAW. A
// realtime clock correction is reported, but never used for phase arithmetic.
type rankingLoadClockProbe struct {
	mu                 sync.Mutex
	origin             time.Time
	initialUncertainty time.Duration
	raw                *readtiming.Trace
	samples            []rankingLoadClockSample
	valid              bool
}

func newRankingLoadClockProbe() *rankingLoadClockProbe {
	before := time.Now()
	_, raw := readtiming.Start(context.Background())
	after := time.Now()
	return &rankingLoadClockProbe{origin: before.Add(after.Sub(before) / 2), initialUncertainty: after.Sub(before), raw: raw, valid: true}
}

func (p *rankingLoadClockProbe) observe() {
	p.mu.Lock()
	defer p.mu.Unlock()
	before := time.Now()
	raw := p.raw.Snapshot()
	after := time.Now()
	uncertainty := after.Sub(before)
	elapsed := before.Add(after.Sub(before) / 2).Sub(p.origin)
	s := rankingLoadClockSample{Elapsed: elapsed.Nanoseconds(), RawElapsed: raw.ElapsedNanoseconds, Uncertainty: uncertainty.Nanoseconds(), Wall: after.UnixNano()}
	s.Drift = s.Elapsed - s.RawElapsed
	if !raw.ClockValid || raw.Clock != "CLOCK_MONOTONIC_RAW" {
		p.valid = false
		return
	}
	// An interrupted clock read is not a trustworthy calibration point.
	if uncertainty > 2*time.Millisecond {
		return
	}

	p.samples = append(p.samples, s)
}

func (p *rankingLoadClockProbe) elapsedRaw() int64 {
	sample := p.raw.Snapshot()
	if !sample.ClockValid || sample.Clock != "CLOCK_MONOTONIC_RAW" {
		panic("load measurement requires a valid Linux RAW clock")
	}
	return sample.ElapsedNanoseconds
}

func (p *rankingLoadClockProbe) report() (map[string]any, bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	var maxDrift int64
	for _, s := range p.samples {
		drift := s.Drift
		if drift < 0 {
			drift = -drift
		}
		maxDrift = max(maxDrift, drift)
	}
	coverage := len(p.samples) > 0 && len(p.samples) >= int((p.elapsedRaw()-p.samples[0].RawElapsed)/int64(2*time.Second))
	return map[string]any{"clock": "CLOCK_MONOTONIC_RAW, process-local origin", "reference": "Go monotonic and wall time, diagnostic only", "valid": p.valid && coverage, "max_go_raw_drift_ns": maxDrift, "initial_pair_uncertainty_ns": p.initialUncertainty.Nanoseconds(), "minimum_coverage_fraction": 0.5, "samples": slices.Clone(p.samples)}, p.valid && coverage
}

type rankingLoadEngine struct {
	f                   *rankingLoadFixture
	r                   *rankingLoadRecorder
	phase               atomic.Value
	phaseMu             sync.Mutex
	phases              []rankingLoadPhase
	started             int64
	startTime, stopTime time.Time
	stopAt              atomic.Int64
	active              atomic.Int64
	peak                atomic.Int64
	stop                chan struct{}
	closeOnce           sync.Once
	done                chan struct{}
	wg                  sync.WaitGroup
	rps, clients        int
	dropped             atomic.Int64
	clockErrors         atomic.Int64
	quietBlocked        atomic.Int64
}

type rankingLoadPhase struct {
	Name       string
	Start, End int64
}

func (e *rankingLoadEngine) setPhase(name string) {
	e.r.clock.observe()
	e.phaseMu.Lock()
	defer e.phaseMu.Unlock()
	at := e.r.now()
	if n := len(e.phases); n > 0 {
		e.phases[n-1].End = at
	}
	e.phases = append(e.phases, rankingLoadPhase{Name: name, Start: at})
	e.phase.Store(name)
}

func (e *rankingLoadEngine) phaseFor(at int64) string {
	e.phaseMu.Lock()
	defer e.phaseMu.Unlock()
	for i := len(e.phases) - 1; i >= 0; i-- {
		p := e.phases[i]
		if at >= p.Start && (p.End == 0 || at < p.End) {
			return p.Name
		}
	}
	return "warmup"
}

func newRankingLoadEngine(f *rankingLoadFixture, r *rankingLoadRecorder, rps, clients int) *rankingLoadEngine {
	e := &rankingLoadEngine{f: f, r: r, rps: rps, clients: clients, stop: make(chan struct{}), done: make(chan struct{})}
	e.setPhase("warmup")
	return e
}

func (e *rankingLoadEngine) request(phase, kind, method, path, token string, body any, version string, scheduled int64) (map[string]any, string, error) {
	var content io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		content = bytes.NewReader(b)
	}
	started := time.Now()
	at := e.r.now()
	s := rankingLoadSample{At: at, WallAt: started.UnixNano(), Phase: phase, Kind: kind, DispatchLag: at - scheduled}
	n := e.active.Add(1)
	s.Inflight = n
	for old := e.peak.Load(); n > old && !e.peak.CompareAndSwap(old, n); old = e.peak.Load() {
	}
	defer e.active.Add(-1)
	req, err := http.NewRequest(method, e.f.s.cPublic.URL+path, content)
	if err != nil {
		return nil, "", err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if version != "" {
		req.Header.Set("If-Interaction-Version", version)
	}
	response, err := e.f.s.client.Do(req)
	var value map[string]any
	var nextVersion string
	if err == nil {
		s.Status = response.StatusCode
		data, readErr := io.ReadAll(io.LimitReader(response.Body, 1<<20))
		_ = response.Body.Close()
		if readErr != nil {
			err = readErr
		} else {
			err = json.Unmarshal(data, &value)
		}
		if s.Status != 200 {
			s.Failure = "http_status"
			err = fmt.Errorf("HTTP %d", s.Status)
		}
		if err == nil {
			at, parseErr := time.Parse(time.RFC3339Nano, response.Header.Get("Server-Time"))
			if parseErr != nil || response.Header.Get("Session-Expires-At") == "" {
				s.Failure = "authority_headers"
				err = fmt.Errorf("missing final authority")
			} else if observed := time.Now(); at.Before(minTime(started, observed).Add(-3*time.Second)) || at.After(maxTime(started, observed).Add(3*time.Second)) {
				e.clockErrors.Add(1)
				s.Failure = "non_realtime_clock"
				err = fmt.Errorf("clock did not follow real elapsed time")
			}
			if kind == "search" {
				items, ok := value["items"].([]any)
				next, _ := value["nextCursor"].(string)
				query, _ := body.(map[string]any)
				if !ok || len(items) != 20 || next == "" {
					err = fmt.Errorf("search did not return the expected populated page")
				} else {
					for _, raw := range items {
						item, ok := raw.(map[string]any)
						if !ok || item["channelId"] != query["channelId"] {
							err = fmt.Errorf("search escaped its requested category")
							break
						}
					}
				}
				if err != nil {
					s.Failure = "search_semantics"
				}
			}
			if kind == "detail" {
				post, ok := value["post"].(map[string]any)
				if !ok || post["postId"] != e.f.sample {
					s.Failure = "detail_semantics"
					err = fmt.Errorf("detail did not resolve the requested post")
				}
			}
			if kind == "hot" {
				rawTime, _ := value["asOf"].(string)
				asOf, parseErr := time.Parse(time.RFC3339Nano, rawTime)
				if parseErr != nil {
					err = parseErr
				} else {
					s.AgeMillis = at.Sub(asOf).Milliseconds()
				}
				items, ok := value["items"].([]any)
				if !ok || len(items) != 20 {
					err = fmt.Errorf("hotlist did not return the expected populated board")
				} else {
					for _, raw := range items {
						item, ok := raw.(map[string]any)
						if !ok || len(item) != 4 || item["postId"] == nil || item["channelId"] == nil || item["title"] == nil || item["viewCount"] == nil {
							err = fmt.Errorf("hotlist did not obey the text-only contract")
							break
						}
					}
				}
				if err != nil {
					s.Failure = "hotlist_semantics"
				}
			}
		}
		nextVersion = response.Header.Get("Interaction-Version")
	}
	if err != nil && s.Failure == "" {
		s.Failure = "transport_or_decode"
	}
	ended := time.Now()
	s.End = e.r.now()
	s.WallEnd = ended.UnixNano()
	s.Latency = s.End - scheduled
	s.ClockSkew = s.WallEnd - e.r.epoch.UnixNano() - s.End
	e.r.add(s)
	return value, nextVersion, err
}

func minTime(a, b time.Time) time.Time {
	if a.UnixNano() < b.UnixNano() {
		return a
	}
	return b
}
func maxTime(a, b time.Time) time.Time {
	if a.UnixNano() > b.UnixNano() {
		return a
	}
	return b
}

func (e *rankingLoadEngine) start() {
	e.startTime = time.Now()
	e.started = e.r.now()
	go func() {
		defer close(e.done)
		available := make(chan int, e.clients)
		for i := 0; i < e.clients; i++ {
			available <- i
		}
		start := e.started
		interval := time.Second / time.Duration(e.rps)
		for seq := 0; ; seq++ {
			due := start + int64(time.Duration(seq)*interval)
			e.r.waitUntil(due, e.stop)

			// Finish dispatching every event due before the stop boundary.
			// A timer becoming runnable just before close is still a real
			// offered event, rather than an artificial shutdown drop.
			if stopAt := e.stopAt.Load(); stopAt != 0 && due >= stopAt {
				e.wg.Wait()
				return
			}
			phase := e.phaseFor(due)
			select {
			case client := <-available:
				e.r.add(rankingLoadSample{At: due, End: e.r.now(), Phase: phase, Kind: "arrival"})
				e.wg.Add(1)
				go func(seq, client int) {
					defer e.wg.Done()
					defer func() { available <- client }()
					// A fixed coprime permutation spreads every request class
					// throughout the cycle instead of batching search/read bursts.
					token := e.f.tokens[client]
					slot := (seq * 37) % 100
					switch {
					case slot < 70:
						_, _, _ = e.request(phase, "search", "POST", postSearchPath, token, map[string]any{"keyword": "跨页样本", "channelId": e.f.channels[(seq/100)%7], "limit": 20}, "", due)
					case slot < 90:
						_, _, _ = e.request(phase, "detail", "GET", "/api/v1/posts/"+e.f.sample, token, nil, "", due)
					case slot < 98:
						_, _, _ = e.request(phase, "hot", "GET", "/api/v1/feed/hot-posts", token, nil, "", due)
					default:
						path := "/api/v1/posts/" + e.f.sample
						_, version, err := e.request(phase, "interaction", "GET", path+"/interactions", token, nil, "", due)
						if err == nil {
							_, _, _ = e.request(phase, "write", "PUT", path+"/like", token, map[string]any{"liked": (seq/100)%2 == 0}, version, e.r.now())
						}
					}
				}(seq, client)
			default:
				e.dropped.Add(1)
				e.r.add(rankingLoadSample{At: due, End: e.r.now(), Phase: phase, Kind: "dropped", Failure: "client_capacity"})
			}
		}
	}()
}
func (e *rankingLoadEngine) close() {
	e.closeOnce.Do(func() {
		e.stopTime = time.Now()
		at := e.r.now()
		e.stopAt.Store(at)
		e.phaseMu.Lock()
		if n := len(e.phases); n > 0 {
			e.phases[n-1].End = at
		}
		e.phaseMu.Unlock()
		close(e.stop)
		<-e.done
	})
}

func rankingLoadPercentile(values []int64, p int) float64 {
	if len(values) == 0 {
		return 0
	}
	slices.Sort(values)
	return float64(values[(p*len(values)+99)/100-1]) / 1e6
}

type rankingLoadSummary struct {
	Phase                           string `json:"phase"`
	Requests, Errors, Dropped       int
	SearchSamples                   int
	SearchP50, SearchP95, SearchP99 float64
	PeakInflight                    int64
	MaxHotAgeMillis                 int64
}

func rankingSummarize(samples []rankingLoadSample, phase string) rankingLoadSummary {
	s := rankingLoadSummary{Phase: phase}
	var searches []int64
	for _, x := range samples {
		if x.Phase != phase || x.Kind == "arrival" {
			continue
		}
		if x.Kind == "dropped" {
			s.Dropped++
			continue
		}
		s.Requests++
		if x.Failure != "" {
			s.Errors++
		}
		if x.Kind == "search" {
			searches = append(searches, x.Latency)
		}
		s.PeakInflight = max(s.PeakInflight, x.Inflight)
		if x.Kind == "hot" {
			s.MaxHotAgeMillis = max(s.MaxHotAgeMillis, x.AgeMillis)
		}
	}
	s.SearchSamples = len(searches)
	s.SearchP50 = rankingLoadPercentile(searches, 50)
	s.SearchP95 = rankingLoadPercentile(searches, 95)
	s.SearchP99 = rankingLoadPercentile(searches, 99)
	return s
}

func (e *rankingLoadEngine) await(t *testing.T, phase string, duration time.Duration) {
	t.Helper()
	e.setPhase(phase)
	end := e.r.now() + int64(duration)
	nextLog := e.r.now() + int64(30*time.Second)
	for e.r.now() < end {
		e.r.waitUntil(min(end, e.r.now()+int64(time.Second)), nil)
		if e.r.now() >= nextLog {
			samples, _ := e.r.copy()
			data, _ := json.Marshal(rankingSummarize(samples, phase))
			t.Logf("load_progress %s active=%d", data, e.active.Load())
			nextLog += int64(30 * time.Second)
		}
	}
}

type rankingCanaryFence struct {
	At, Deadline            time.Time
	PublishedAt, VerifiedAt time.Time
	ExpectedBucket          time.Time
	Revisions               []int64
	Enabled                 bool
	Verified                bool
	DataVersions            []string
	SnapshotVersion         string
}

// This is the original scheduler's exact quiet-window condition, observed
// without registering fake foreground work or changing the production worker.
func (e *rankingLoadEngine) observeOldQuietWindow(ctx context.Context) {
	// Intentionally keep the original worker's Go 20ms timer for this
	// counterfactual observer. Evidence spans and gap limits are RAW; this
	// timer never drives offered load, performance windows or acceptance time.
	tick := time.NewTicker(20 * time.Millisecond)
	defer tick.Stop()
	started := e.r.now()
	lastReport, lastTick := started, started
	var maxGap int64
	_, previous := e.f.cache.ForegroundActivity()
	report := func(until int64) {
		if until-started < int64(25*time.Second) {
			return
		}
		e.quietBlocked.Add(1)
		r := slog.NewRecord(time.Now(), slog.LevelInfo, "global_hotlist_old_quiet_span", 0)
		r.AddAttrs(slog.Int64("from_ns", started), slog.Int64("until_ns", until), slog.Int64("max_tick_gap_ns", maxGap))
		_ = e.r.Handle(ctx, r)
		lastReport = until
	}
	defer func() { report(lastTick) }()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			now := e.r.now()
			gap := now - lastTick
			// A delayed observer cannot attest to the unobserved interval. End
			// the old span before that gap and begin a new one at this sample.
			if gap > int64(40*time.Millisecond) {
				report(lastTick)
				started = now
				lastReport = now
				maxGap = 0
			} else {
				maxGap = max(maxGap, gap)
			}
			lastTick = now
			active, revision := e.f.cache.ForegroundActivity()
			_, check := e.f.cache.ForegroundActivity()
			if active == 0 && revision == previous && check == revision {
				report(now)
				started = now
				lastReport = now
				maxGap = 0
			}
			previous = revision
			if now-lastReport >= int64(25*time.Second) {
				report(now)
			}
		}
	}
}

func (e *rankingLoadEngine) canaryFence(enabled bool) (rankingCanaryFence, error) {
	f := rankingCanaryFence{Enabled: enabled}
	var before []int64
	for _, ch := range e.f.channels {
		var revision int64
		if err := e.f.s.cp.QueryRow(context.Background(), `SELECT revision FROM c_posts.ranking_inputs WHERE channel_id=$1`, ch).Scan(&revision); err != nil {
			return f, err
		}
		before = append(before, revision)
	}
	for _, post := range e.f.canaries {
		for voter := 0; voter < 6; voter++ {
			token := e.f.tokens[voter]
			path := "/api/v1/posts/" + post
			_, version, err := e.request(e.phase.Load().(string), "canary_read", "GET", path+"/interactions", token, nil, "", e.r.now())
			if err != nil {
				return f, err
			}
			kind, field := "like", "liked"
			if voter >= 4 {
				kind, field = "favorite", "favorited"
			}
			if _, _, err = e.request(e.phase.Load().(string), "canary_write", "PUT", path+"/"+kind, token, map[string]any{field: enabled}, version, e.r.now()); err != nil {
				return f, err
			}
		}
	}
	for i, ch := range e.f.channels {
		var revision int64
		if err := e.f.s.cp.QueryRow(context.Background(), `SELECT revision FROM c_posts.ranking_inputs WHERE channel_id=$1`, ch).Scan(&revision); err != nil {
			return f, err
		}
		if revision <= before[i] {
			return f, fmt.Errorf("canary did not change a shard")
		}
		f.Revisions = append(f.Revisions, revision)
	}
	f.At = time.Now().UTC()
	f.ExpectedBucket = f.At.Truncate(rankings.Interval).Add(rankings.Interval)
	f.Deadline = f.ExpectedBucket.Add(time.Minute)
	return f, nil
}

func TestRealHTTPSRankingsSustainedLoadPostgres(t *testing.T) {
	mode := os.Getenv("RANKING_LOAD_MODE")
	if mode == "" {
		t.Skip("explicit sustained-load mode required")
	}
	if mode != "calibrate" && mode != "soak" && mode != "diagnostic" && mode != "profile" {
		t.Fatal("mode must be calibrate, diagnostic, profile or soak")
	}
	clients := rankingLoadInt(t, "RANKING_LOAD_CLIENTS", 32, 32, 64)
	dir := os.Getenv("RANKING_LOAD_ARTIFACT_DIR")
	if dir == "" {
		t.Fatal("private load artifact directory required")
	}
	// A failed restart must never truncate evidence from an earlier run.
	if err := os.MkdirAll(filepath.Dir(dir), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(dir, 0700); err != nil {
		t.Fatal(err)
	}
	rawFile, err := os.Create(filepath.Join(dir, "requests.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	logFile, err := os.Create(filepath.Join(dir, "worker-events.jsonl"))
	if err != nil {
		_ = rawFile.Close()
		t.Fatal(err)
	}
	rawBuffer, logBuffer := bufio.NewWriterSize(rawFile, 1<<20), bufio.NewWriterSize(logFile, 65536)
	clockProbe := newRankingLoadClockProbe()
	r := &rankingLoadRecorder{epoch: time.Now(), clock: clockProbe, raw: json.NewEncoder(rawBuffer), logs: json.NewEncoder(logBuffer)}
	defer func() {
		for _, err := range []error{rawBuffer.Flush(), logBuffer.Flush(), rawFile.Close(), logFile.Close()} {
			if err != nil {
				t.Errorf("load evidence I/O: %v", err)
			}
		}
		r.mu.Lock()
		defer r.mu.Unlock()
		if r.ioErr != nil {
			t.Errorf("load evidence recording: %v", r.ioErr)
		}
	}()
	prior := slog.Default()
	slog.SetDefault(slog.New(r))
	defer slog.SetDefault(prior)
	f := newRankingLoadFixture(t, clients, r)
	clockCtx, stopClock := context.WithCancel(context.Background())
	clockDone := make(chan struct{})
	defer func() { stopClock(); <-clockDone }()
	go func() {
		defer close(clockDone)
		lastRenew := r.now()
		for r.waitUntil(r.now()+int64(time.Second), clockCtx.Done()) {
			clockProbe.observe()
			if r.now()-lastRenew >= int64(time.Minute) {
				f.advanceClock(0)
				lastRenew = r.now()
			}
		}
	}()
	if _, err := f.s.c.RefreshRankings(context.Background(), f.worker, authprivacy.DefaultRankingWeights()); err != nil {
		t.Fatal(err)
	}
	if mode == "calibrate" {
		var reports []rankingLoadSummary
		var ledgers []map[string]any
		seconds := rankingLoadInt(t, "RANKING_LOAD_STAGE_SECONDS", 30, 15, 60)
		minimum := rankingLoadInt(t, "RANKING_LOAD_MIN_RPS", 8, 8, 128)
		for _, rate := range []int{8, 12, 16, 20, 24, 32, 48, 64, 96, 128} {
			if rate < minimum {
				continue
			}
			// Refresh unchanged input between stages; the next measured stage
			// keeps the worker off and cannot fall into an expired-board fast path.
			if _, err := f.s.c.RefreshRankings(context.Background(), f.worker, authprivacy.DefaultRankingWeights()); err != nil {
				t.Fatal(err)
			}
			e := newRankingLoadEngine(f, r, rate, clients)
			e.start()
			phase := fmt.Sprintf("capacity_%d", rate)
			e.await(t, phase, time.Duration(seconds)*time.Second)
			e.close()
			samples, _ := r.copy()
			report := rankingSummarize(samples, phase)
			reports = append(reports, report)
			rows, _ := e.arrivalReport(samples)
			for _, row := range rows {
				if row["phase"] == phase {
					ledgers = append(ledgers, row)
					if row["unaccounted_events"].(int64) != 0 {
						t.Error("capacity stage lost planned arrivals")
					}
				}
			}
			b, _ := json.Marshal(report)
			t.Logf("capacity_result offered_events_per_second=%d clients=%d %s", rate, clients, b)
			if report.Errors > 0 || report.Dropped > 0 {
				break
			}
		}
		b, _ := json.MarshalIndent(reports, "", "  ")
		if err := os.WriteFile(filepath.Join(dir, "capacity.json"), b, 0600); err != nil {
			t.Fatal(err)
		}
		clockProbe.observe()
		calibration, valid := clockProbe.report()
		if !valid {
			t.Error("capacity clock evidence invalid")
		}
		for name, value := range map[string]any{"capacity-ledgers.json": ledgers, "clock-calibration.json": calibration} {
			data, err := json.MarshalIndent(value, "", "  ")
			if err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dir, name), data, 0600); err != nil {
				t.Fatal(err)
			}
		}
		return
	}
	rate := rankingLoadInt(t, "RANKING_LOAD_RPS", 64, 16, 128)
	if mode == "diagnostic" || mode == "profile" {
		e := newRankingLoadEngine(f, r, rate, clients)
		e.start()
		defer e.close()
		// Same traffic before the real worker cycle provides stage-level
		// evidence. This short diagnostic never counts as long-test acceptance.
		e.await(t, "baseline", time.Minute)
		if mode == "profile" {
			e.close()
			samples, _ := r.copy()
			result := rankingSummarize(samples, "baseline")
			data, err := json.MarshalIndent(result, "", "  ")
			if err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dir, "profile.json"), data, 0600); err != nil {
				t.Fatal(err)
			}
			t.Logf("profile_result %s", data)
			if result.Errors > 0 || result.Dropped > 0 {
				t.Error("profile load had errors or dropped arrivals")
			}
			return
		}
		e.setPhase("diagnostic")
		fence, err := e.canaryFence(true)
		if err != nil {
			t.Fatal(err)
		}
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		done := make(chan struct{})
		go func() { defer close(done); f.s.c.RunRankings(ctx, f.worker, authprivacy.DefaultRankingWeights()) }()
		defer func() { cancel(); <-done }()
		for time.Now().Before(fence.Deadline) {
			snapshot, err := f.cache.Snapshot(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			if !snapshot.Bucket.Before(fence.ExpectedBucket) {
				if err := rankingVerifyFence(e, snapshot, &fence, true); err != nil {
					t.Fatal(err)
				}
				if fence.Verified {
					break
				}
			}
			r.waitUntil(r.now()+int64(time.Second), nil)
		}
		if !fence.Verified {
			t.Fatal("real diagnostic cycle failed to publish")
		}
		cancel()
		<-done
		e.close()
		samples, _ := r.copy()
		result := rankingSummarize(samples, "diagnostic")
		b, _ := json.MarshalIndent(map[string]any{"baseline": rankingSummarize(samples, "baseline"), "diagnostic": result}, "", "  ")
		if err := os.WriteFile(filepath.Join(dir, "diagnostic.json"), b, 0600); err != nil {
			t.Fatal(err)
		}
		t.Logf("diagnostic_result real_clock=true %s", b)
		if result.Errors > 0 || result.Dropped > 0 {
			t.Error("diagnostic load had errors or dropped arrivals")
		}
		return
	}
	// Start the baseline near a fresh real bucket so ten minutes without a
	// worker never crosses the fifteen-minute refusal boundary.
	if time.Since(time.Now().UTC().Truncate(rankings.Interval)) > 30*time.Second {
		wait := time.Until(time.Now().UTC().Truncate(rankings.Interval).Add(rankings.Interval).Add(time.Second))
		t.Logf("waiting_for_fresh_baseline_bucket seconds=%.1f", wait.Seconds())
		for time.Since(time.Now().UTC().Truncate(rankings.Interval)) > 30*time.Second {
			r.waitUntil(r.now()+int64(time.Second), nil)
		}
	}
	f.advanceClock(0)
	if _, err := f.s.c.RefreshRankings(context.Background(), f.worker, authprivacy.DefaultRankingWeights()); err != nil {
		t.Fatal(err)
	}
	e := newRankingLoadEngine(f, r, rate, clients)
	e.start()
	defer e.close()
	observeCtx, stopObserve := context.WithCancel(context.Background())
	defer stopObserve()
	observeDone := make(chan struct{})
	go func() { defer close(observeDone); e.observeOldQuietWindow(observeCtx) }()
	defer func() { stopObserve(); <-observeDone }()
	initialFence, err := e.canaryFence(true)
	if err != nil {
		t.Fatal(err)
	}
	initialFence, enabled, err := e.baselineWithCanaries(t, 10*time.Minute, initialFence, true)
	if err != nil {
		t.Fatal(err)
	}
	// Continue identical traffic while baseline GET+PUT pairs finish, so the
	// worker cannot contaminate the baseline's trailing in-flight requests.
	e.await(t, "transition", 10*time.Second)
	workerCtx, stopWorker := context.WithCancel(context.Background())
	defer stopWorker()
	workerDone := make(chan struct{})
	e.setPhase("catchup")
	catchupAt := time.Now()
	catchupTick := r.now()
	var dueBuckets []rankingLoadDueBucket
	observeBucket := func(now time.Time) {
		bucket := now.UTC().Truncate(rankings.Interval)
		if len(dueBuckets) == 0 {
			dueBuckets = append(dueBuckets, rankingLoadDueBucket{Bucket: bucket, Observed: e.r.now()})
			return
		}
		for next := dueBuckets[len(dueBuckets)-1].Bucket.Add(rankings.Interval); !next.After(bucket); next = next.Add(rankings.Interval) {
			dueBuckets = append(dueBuckets, rankingLoadDueBucket{Bucket: next, Observed: e.r.now()})
		}
	}
	observeBucket(catchupAt)
	go func() {
		defer close(workerDone)
		f.s.c.RunRankings(workerCtx, f.worker, authprivacy.DefaultRankingWeights())
	}()
	defer func() { stopWorker(); <-workerDone }()
	var current rankings.Snapshot
	for r.now()-catchupTick < int64(time.Minute) {
		current, err = f.cache.Snapshot(context.Background())
		if err == nil && !current.Bucket.Before(catchupAt.Truncate(rankings.Interval)) {
			break
		}
		r.waitUntil(r.now()+int64(100*time.Millisecond), nil)
	}
	if err != nil || current.Bucket.Before(catchupAt.Truncate(rankings.Interval)) {
		t.Fatal("worker did not catch up within a minute under continuous traffic")
	}
	t.Logf("catchup_completed elapsed_ms=%d", (r.now()-catchupTick)/int64(time.Millisecond))
	for !initialFence.Verified && r.now()-catchupTick < int64(time.Minute) {
		if err := rankingVerifyFence(e, current, &initialFence, false); err != nil {
			t.Fatal(err)
		}
		if !initialFence.Verified {
			r.waitUntil(r.now()+int64(20*time.Millisecond), nil)
		}
	}
	if !initialFence.Verified {
		t.Fatal("catchup publication evidence did not arrive within its deadline")
	}
	seconds := rankingLoadInt(t, "RANKING_LOAD_SOAK_SECONDS", 1800, 1800, 2400)
	e.setPhase("soak")
	soakStart := r.now()
	until := soakStart + int64(time.Duration(seconds)*time.Second)
	lastVersion := current.Version
	published := 0
	var fences []rankingCanaryFence
	var versions []map[string]any
	nextCanary := time.Now().UTC().Truncate(rankings.Interval).Add(rankings.Interval).Add(-time.Minute)
	if !nextCanary.After(time.Now()) {
		nextCanary = nextCanary.Add(rankings.Interval)
	}
	for r.now() < until || rankingPendingFence(fences) {
		r.waitUntil(r.now()+int64(time.Second), nil)
		now := time.Now()
		observeBucket(now)
		if r.now() < until && !now.Before(nextCanary) {
			enabled = !enabled
			fence, err := e.canaryFence(enabled)
			if err != nil {
				t.Fatal(err)
			}
			fences = append(fences, fence)
			nextCanary = nextCanary.Add(rankings.Interval)
			t.Logf("canary_committed next_bucket=%s enabled=%t", fence.ExpectedBucket.Format(time.RFC3339), enabled)
			now = time.Now()
			observeBucket(now)
		}
		current, err = f.cache.Snapshot(context.Background())
		if err != nil {
			t.Fatal("active Redis snapshot became unavailable")
		}
		if now.Sub(current.Bucket) >= 6*time.Minute {
			t.Fatal("active worker allowed snapshot age to reach six minutes")
		}
		if current.Version != lastVersion {
			if current.Bucket.Before(now.Truncate(rankings.Interval)) {
				t.Fatal("worker published an old bucket")
			}
			published++
			lastVersion = current.Version
			versions = append(versions, map[string]any{"observedAt": now, "bucket": current.Bucket, "version": current.Version})
			t.Logf("new_snapshot bucket=%s age_ms=%d", current.Bucket.Format(time.RFC3339), now.Sub(current.Bucket).Milliseconds())
		}
		for i := range fences {
			if fences[i].Verified {
				continue
			}
			if !current.Bucket.Before(fences[i].ExpectedBucket) {
				if err := rankingVerifyFence(e, current, &fences[i], true); err != nil {
					t.Fatal(err)
				}
			}
			if now.After(fences[i].Deadline) && !fences[i].Verified {
				t.Fatal("canary input did not reach the required snapshot within a minute of its due bucket")
			}
		}
		// Check every due cycle, including a cycle with no eligible canary yet.
		if now.Sub(now.Truncate(rankings.Interval)) > time.Minute && current.Bucket.Before(now.Truncate(rankings.Interval)) {
			t.Fatal("worker missed a due five-minute publication")
		}
		if int((r.now()-soakStart)/int64(time.Second))%30 == 0 {
			samples, _ := r.copy()
			b, _ := json.Marshal(rankingSummarize(samples, "soak"))
			t.Logf("soak_progress elapsed_s=%d old_quiet_timeouts=%d %s", int((r.now()-soakStart)/int64(time.Second)), e.quietBlocked.Load(), b)
		}
	}
	// Keep real offered traffic after the last publication, so the old
	// strategy is observed for a full forward 25-second budget from its start.
	e.await(t, "tail", 30*time.Second)
	observeBucket(time.Now())
	// Publication still has its own strict UTC/RAW 60s deadline. Allow a
	// separate observation tail for a late-but-valid round's forward witness.
	publicationDrain := r.now() + int64(2*time.Minute)
	for {
		observeBucket(time.Now())
		latest, err := f.cache.Snapshot(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		if !latest.Bucket.Before(dueBuckets[len(dueBuckets)-1].Bucket) {
			observedEvents := r.copyEvents()
			var lastRefresh int64
			for _, event := range observedEvents {
				if event.Name == "global_hotlist_refresh_start" {
					lastRefresh = max(lastRefresh, event.At)
				}
			}
			covered := false
			for _, event := range observedEvents {
				if event.Name != "global_hotlist_old_quiet_span" {
					continue
				}
				from, _ := event.Fields["from_ns"].(int64)
				to, _ := event.Fields["until_ns"].(int64)
				gap, _ := event.Fields["max_tick_gap_ns"].(int64)
				if from <= lastRefresh && to >= lastRefresh+int64(25*time.Second) && gap <= int64(40*time.Millisecond) {
					covered = true
					break
				}
			}
			if covered {
				break
			}
		}
		if r.now() >= publicationDrain {
			t.Fatal("last due publication or its forward busy evidence was not observed before shutdown")
		}
		r.waitUntil(r.now()+int64(100*time.Millisecond), nil)
	}
	stopWorker()
	<-workerDone
	// workerDone is closed; the deferred receive remains nonblocking.
	stopObserve()
	<-observeDone
	e.close()
	stopClock()
	<-clockDone
	clockProbe.observe()
	samples, events := r.copy()
	if err := rawBuffer.Flush(); err != nil {
		t.Fatal(err)
	}
	if err := logBuffer.Flush(); err != nil {
		t.Fatal(err)
	}
	r.mu.Lock()
	recordErr := r.ioErr
	r.mu.Unlock()
	if recordErr != nil {
		t.Fatal(recordErr)
	}
	baseline, soak, catchup := rankingSummarize(samples, "baseline"), rankingSummarize(samples, "soak"), rankingSummarize(samples, "catchup")
	change := 100 * (soak.SearchP95/baseline.SearchP95 - 1)
	overlap := rankingOverlapSummary(samples, events)
	windows, windowPass := e.matchedWindowReport(samples, events)
	allErrors := 0
	for _, sample := range samples {
		if sample.Failure != "" {
			allErrors++
		}
	}
	arrivals, completeArrivals := e.arrivalReport(samples)
	publications, publicationPass := rankingPublicationReport(events, dueBuckets, catchupAt, catchupTick)
	var maxSkew int64
	for _, sample := range samples {
		skew := sample.ClockSkew
		if skew < 0 {
			skew = -skew
		}
		maxSkew = max(maxSkew, skew)
	}
	clockReport, clockPass := clockProbe.report()
	report := map[string]any{"clients": clients, "offered_events_per_second": rate, "arrivals": arrivals, "baseline": baseline, "soak": soak, "catchup": catchup, "search_p95_change_percent": change, "old_quiet_25s_timeouts": e.quietBlocked.Load(), "snapshot_publications": published, "publication_deadlines": publications, "versions": versions, "canary_fences": fences, "overlap": overlap, "matched_windows": windows, "duration_seconds": seconds, "clock_errors": e.clockErrors.Load(), "clock_calibration": clockReport, "max_sample_wall_clock_correction_ns": maxSkew, "raw_elapsed_ns": e.stopAt.Load() - e.started, "go_monotonic_elapsed_ns": e.stopTime.Sub(e.startTime).Nanoseconds(), "wall_elapsed_ns": e.stopTime.UnixNano() - e.startTime.UnixNano(), "all_errors_and_drops": allErrors, "note": "Harness performance and offered-load fields use one CLOCK_MONOTONIC_RAW origin; original worker elapsed/yield/aggregate/commit duration attributes remain Go-clock diagnostics; separate UTC fields for business deadlines; TCP Redis ACL; pool8/40ms; real five-minute RunRankings; no clock acceleration"}
	b, _ := json.MarshalIndent(report, "", "  ")
	if err := os.WriteFile(filepath.Join(dir, "summary.json"), b, 0600); err != nil {
		t.Fatal(err)
	}
	t.Logf("sustained_result %s", b)
	if allErrors > 0 {
		t.Error("sustained load returned failures or reduced offered traffic")
	}
	if !completeArrivals {
		t.Error("fixed-rate generator failed to account for all planned arrivals")
	}
	if change > 5 {
		t.Errorf("search P95 regression %.3f%% exceeds 5%%", change)
	}
	if soak.MaxHotAgeMillis >= int64((6*time.Minute)/time.Millisecond) {
		t.Error("HTTP hotlist exceeded six-minute freshness")
	}
	for _, sample := range samples {
		if (sample.Phase == "soak" || sample.Phase == "tail") && sample.Kind == "hot" && sample.AgeMillis >= int64((6*time.Minute)/time.Millisecond) {
			t.Error("active HTTP hotlist exceeded six-minute freshness")
			break
		}
	}
	if published < 5 || e.quietBlocked.Load() == 0 || e.clockErrors.Load() != 0 {
		t.Error("insufficient real-time updates or no reproduction of the original busy condition")
	}
	if !windowPass {
		t.Error("matched worker-window latency or actual busy-progress evidence failed")
	}
	if !publicationPass {
		t.Error("worker did not publish each required bucket before its real deadline")
	}
	if !clockPass {
		t.Error("RAW clock failed or lacked trustworthy observation coverage")
	}
}

func (e *rankingLoadEngine) arrivalReport(samples []rankingLoadSample) ([]map[string]any, bool) {
	e.phaseMu.Lock()
	phases := slices.Clone(e.phases)
	e.phaseMu.Unlock()
	interval := int64(time.Second / time.Duration(e.rps))
	ceil := func(n int64) int64 {
		if n <= 0 {
			return 0
		}
		return (n + interval - 1) / interval
	}
	valid := true
	var rows []map[string]any
	for _, p := range phases {
		if p.End == 0 {
			continue
		}
		planned := ceil(p.End-e.started) - ceil(p.Start-e.started)
		var sent, dropped, physical, failures, occupied, completed, dispatched, completionErrors int64
		var lags []int64
		for _, s := range samples {
			if s.Phase != p.Name {
				continue
			}
			switch s.Kind {
			case "arrival":
				sent++
				lags = append(lags, s.End-s.At)
			case "dropped":
				dropped++
			default:
				physical++
				if s.Failure != "" {
					failures++
				}
			}
		}
		for _, s := range samples {
			if s.End >= p.Start && s.End < p.End {
				if s.Kind == "arrival" {
					dispatched++
				} else if s.Kind != "dropped" {
					completed++
					if s.Failure != "" {
						completionErrors++
					}
				}
			}
		}
		for _, s := range samples {
			if s.Kind != "arrival" && s.Kind != "dropped" && s.End > p.Start && s.At < p.End {
				occupied += min(s.End, p.End) - max(s.At, p.Start)
			}
		}
		missing := planned - sent - dropped
		if missing != 0 {
			valid = false
		}
		seconds := float64(p.End-p.Start) / 1e9
		rawDuration := p.End - p.Start
		if p.Name == "soak" && rawDuration < int64(30*time.Minute) {
			valid = false
		}
		rows = append(rows, map[string]any{"phase": p.Name, "from_ns": p.Start, "until_ns": p.End, "raw_elapsed_ns": rawDuration, "planned_events": planned, "dispatched_events": sent, "dropped_events": dropped, "unaccounted_events": missing, "cohort_completed_http": physical, "cohort_http_errors": failures, "completed_http": completed, "http_errors": completionErrors, "dispatched_in_window": dispatched, "scheduled_dispatched_events_per_second": float64(sent) / seconds, "actual_events_per_second": float64(dispatched) / seconds, "actual_http_per_second": float64(completed) / seconds, "mean_inflight": float64(occupied) / float64(p.End-p.Start), "dispatch_lag_p95_ms": rankingLoadPercentile(lags, 95)})
	}
	return rows, valid
}

func rankingVerifyFence(e *rankingLoadEngine, snapshot rankings.Snapshot, fence *rankingCanaryFence, checkBucket bool) error {
	if checkBucket && snapshot.Bucket.Before(fence.ExpectedBucket) {
		return nil
	}
	_, events := e.r.copy()
	var publishedAt time.Time
	for _, event := range events {
		if event.Name == "global_hotlist_publish_complete" && event.Fields["version"] == snapshot.Version {
			publishedAt = time.Unix(0, event.WallAt).UTC()
			break
		}
	}
	// Redis may become visible before the publishing goroutine records its
	// completion event. The caller retries pending evidence until its deadline.
	if publishedAt.IsZero() {
		return nil
	}
	if checkBucket && publishedAt.After(fence.Deadline) {
		return fmt.Errorf("canary snapshot was published after its bucket deadline")
	}
	for i, ch := range e.f.channels {
		var revision int64
		var dataVersion string
		if err := e.f.s.cp.QueryRow(context.Background(), `SELECT d.input_revision,d.data_version FROM c_posts.hot_snapshot_shards link JOIN c_posts.hot_shard_data d USING(data_version,channel_id) WHERE link.version=$1 AND link.channel_id=$2`, snapshot.Version, ch).Scan(&revision, &dataVersion); err != nil {
			return err
		}
		if revision < fence.Revisions[i] {
			return fmt.Errorf("published shard did not include a completed canary fence")
		}
		fence.DataVersions = append(fence.DataVersions, dataVersion)
	}
	page, _, err := e.request(e.phase.Load().(string), "hot", "GET", "/api/v1/feed/hot-posts", e.f.tokens[0], nil, "", e.r.now())
	if err != nil {
		return err
	}
	seen := map[string]bool{}
	for _, x := range page["items"].([]any) {
		seen[x.(map[string]any)["postId"].(string)] = true
	}
	for _, id := range e.f.canaries {
		if seen[id] != fence.Enabled {
			return fmt.Errorf("canary public ranking did not reflect its committed interaction state")
		}
	}
	fence.PublishedAt = publishedAt
	fence.Verified = true
	fence.VerifiedAt = time.Now().UTC()
	fence.SnapshotVersion = snapshot.Version
	return nil
}

type rankingLoadDueBucket struct {
	Bucket   time.Time
	Observed int64
}

func rankingPublicationReport(events []rankingLoadEvent, due []rankingLoadDueBucket, catchupAt time.Time, catchupTick int64) ([]map[string]any, bool) {
	if len(due) == 0 {
		return nil, false
	}
	first := map[time.Time]rankingLoadEvent{}
	for _, event := range events {
		if event.Name != "global_hotlist_publish_complete" {
			continue
		}
		bucket, ok := event.Fields["bucket"].(time.Time)
		if !ok {
			continue
		}
		bucket = bucket.UTC()
		if prior, ok := first[bucket]; !ok || event.At < prior.At {
			first[bucket] = event
		}
	}
	pass := true
	var rows []map[string]any
	add := func(kind string, bucket, deadline time.Time, monoDeadline int64) {
		event, found := first[bucket]
		at := time.Unix(0, event.WallAt).UTC()
		ok := found && !at.After(deadline) && event.At <= monoDeadline
		if !ok {
			pass = false
		}
		rows = append(rows, map[string]any{"kind": kind, "bucket": bucket, "published_at": at, "deadline": deadline, "published_mono_ns": event.At, "deadline_mono_ns": monoDeadline, "pass": ok})
	}
	add("catchup", catchupAt.UTC().Truncate(rankings.Interval), catchupAt.Add(time.Minute), catchupTick+int64(time.Minute))
	for _, observed := range due[1:] {
		add("scheduled", observed.Bucket, observed.Bucket.Add(time.Minute), observed.Observed+int64(time.Minute))
	}
	return rows, pass
}

func rankingOverlapSummary(samples []rankingLoadSample, events []rankingLoadEvent) rankingLoadSummary {
	type window struct{ a, b int64 }
	var windows []window
	var start int64
	for _, e := range events {
		if e.Name == "global_hotlist_aggregate_start" {
			start = e.At
		}
		if e.Name == "global_hotlist_aggregate_complete" && start > 0 {
			windows = append(windows, window{start, e.At})
			start = 0
		}
	}
	var selected []rankingLoadSample
	for _, s := range samples {
		if s.Phase != "soak" || s.Kind != "search" {
			continue
		}
		for _, w := range windows {
			if s.At < w.b && s.End > w.a {
				s.Phase = "aggregate_overlap"
				selected = append(selected, s)
				break
			}
		}
	}
	return rankingSummarize(selected, "aggregate_overlap")
}

func rankingPendingFence(fences []rankingCanaryFence) bool {
	for _, fence := range fences {
		if !fence.Verified {
			return true
		}
	}
	return false
}

func (e *rankingLoadEngine) matchedWindowReport(samples []rankingLoadSample, events []rankingLoadEvent) (map[string]any, bool) {
	type window struct {
		kind   string
		a, b   int64
		bucket string
	}
	var windows []window
	starts := map[string]int64{}
	for _, x := range events {
		name := strings.TrimPrefix(x.Name, "global_hotlist_")
		if strings.HasSuffix(name, "_start") {
			starts[strings.TrimSuffix(name, "_start")] = x.At
			continue
		}
		kind := ""
		if name == "refresh" {
			kind = "refresh"
		} else if strings.HasSuffix(name, "_complete") {
			kind = strings.TrimSuffix(name, "_complete")
		}
		if from := starts[kind]; from > 0 {
			windows = append(windows, window{kind, from, x.At, fmt.Sprint(x.Fields["bucket"])})
			delete(starts, kind)
		}
	}
	e.phaseMu.Lock()
	phases := slices.Clone(e.phases)
	e.phaseMu.Unlock()
	var baseline rankingLoadPhase
	for _, p := range phases {
		if p.Name == "baseline" {
			baseline = p
		}
	}
	interval := int64(time.Second / time.Duration(e.rps))
	const period = 1400
	ceil := func(n int64) int64 {
		if n <= 0 {
			return 0
		}
		return (n + interval - 1) / interval
	}
	firstBase, lastBase := ceil(baseline.Start-e.started), ceil(baseline.End-e.started)
	canaryOverlap := func(a, b int64) bool {
		for _, s := range samples {
			if (s.Kind == "canary_read" || s.Kind == "canary_write") && a < s.End+int64(5*time.Second) && b > s.At-int64(5*time.Second) {
				return true
			}
		}
		return false
	}
	groupActual, groupBase := map[string]map[int]bool{}, map[string]map[int]bool{}
	pass := true
	var rows []map[string]any
	for _, w := range windows {
		if w.b < baseline.End || (w.kind != "refresh" && w.kind != "aggregate" && w.kind != "commit" && w.kind != "publish") {
			continue
		}
		phase := e.phaseFor(w.a)
		if phase != "catchup" && phase != "soak" && phase != "tail" {
			continue
		}
		actualCanaryOverlap := canaryOverlap(w.a, w.b)
		if actualCanaryOverlap {
			pass = false
		}
		// Match baseline windows by the driver's exact query/type/channel and
		// mutation-cycle position, with identical lengths and overlap rule.
		idx := ceil(w.a - e.started)
		residue := idx % period
		first := firstBase + (residue-firstBase%period+period)%period
		var pseudo []window
		for j := first; j < lastBase; j += period {
			a := e.started + j*interval + (w.a - (e.started + idx*interval))
			b := a + w.b - w.a
			if a >= baseline.Start+int64(5*time.Second) && b <= baseline.End-int64(5*time.Second) && !canaryOverlap(a, b) {
				pseudo = append(pseudo, window{a: a, b: b})
			}
		}
		actual, control := map[int]bool{}, map[int]bool{}
		for i, s := range samples {
			if s.Kind != "search" {
				continue
			}
			if s.At < w.b && s.End > w.a {
				actual[i] = true
			}
			if s.Phase == "baseline" {
				for _, p := range pseudo {
					if s.At < p.b && s.End > p.a {
						control[i] = true
						break
					}
				}
			}
		}
		values := func(ids map[int]bool, label string) rankingLoadSummary {
			var out []rankingLoadSample
			for i := range ids {
				s := samples[i]
				s.Phase = label
				out = append(out, s)
			}
			return rankingSummarize(out, label)
		}
		a, b := values(actual, "worker_window"), values(control, "matched_baseline")
		change := 0.0
		if b.SearchP95 > 0 {
			change = 100 * (a.SearchP95/b.SearchP95 - 1)
		}
		busy := false
		for _, event := range events {
			if event.Name != "global_hotlist_old_quiet_span" {
				continue
			}
			from, ok1 := event.Fields["from_ns"].(int64)
			to, ok2 := event.Fields["until_ns"].(int64)
			gap, ok3 := event.Fields["max_tick_gap_ns"].(int64)
			if ok1 && ok2 && ok3 && gap <= int64(40*time.Millisecond) && from <= w.a && to >= max(w.b, w.a+int64(25*time.Second)) {
				busy = true
				break
			}
		}
		if w.kind == "refresh" && (!busy || w.b-w.a > int64(time.Minute)) {
			pass = false
		}
		rows = append(rows, map[string]any{"stage": w.kind, "phase": phase, "bucket": w.bucket, "from_ns": w.a, "until_ns": w.b, "duration_ms": float64(w.b-w.a) / 1e6, "worker": a, "matched_baseline": b, "p95_change_percent": change, "inside_old_starvation_span": busy, "canary_overlap": actualCanaryOverlap})
		group := w.kind
		if groupActual[group] == nil {
			groupActual[group] = map[int]bool{}
			groupBase[group] = map[int]bool{}
		}
		for i := range actual {
			groupActual[group][i] = true
		}
		for i := range control {
			groupBase[group][i] = true
		}
	}
	pooled := map[string]any{}
	for stage, ids := range groupActual {
		var actual, control []rankingLoadSample
		for i := range ids {
			s := samples[i]
			s.Phase = "worker"
			actual = append(actual, s)
		}
		for i := range groupBase[stage] {
			s := samples[i]
			s.Phase = "control"
			control = append(control, s)
		}
		a, b := rankingSummarize(actual, "worker"), rankingSummarize(control, "control")
		change := 0.0
		if b.SearchP95 > 0 {
			change = 100 * (a.SearchP95/b.SearchP95 - 1)
		}
		pooled[stage] = map[string]any{"worker": a, "matched_baseline": b, "p95_change_percent": change}
		if stage == "refresh" || stage == "aggregate" {
			if a.SearchSamples < 50 || b.SearchSamples < 50 || a.SearchP95 > b.SearchP95*1.05 {
				pass = false
			}
		}
	}
	if len(groupActual["refresh"]) == 0 || len(groupActual["aggregate"]) == 0 {
		pass = false
	}
	return map[string]any{"per_window": rows, "pooled_unique_requests": pooled, "comparison": "identical overlap rule and driver 1400-event phase; baseline requests deduplicated per stage"}, pass
}

func (e *rankingLoadEngine) baselineWithCanaries(t *testing.T, duration time.Duration, latest rankingCanaryFence, enabled bool) (rankingCanaryFence, bool, error) {
	e.setPhase("baseline")
	startWall := time.Now()
	start := e.r.now()
	end := start + int64(duration)
	next := startWall.UTC().Truncate(rankings.Interval).Add(rankings.Interval).Add(-time.Minute)
	if !next.After(startWall) {
		next = next.Add(rankings.Interval)
	}
	for e.r.now() < end {
		e.r.waitUntil(min(end, e.r.now()+int64(time.Second)), nil)
		now := time.Now()
		if !now.Before(next) {
			enabled = !enabled
			var err error
			latest, err = e.canaryFence(enabled)
			if err != nil {
				return latest, enabled, err
			}
			next = next.Add(rankings.Interval)
		}
		if int((e.r.now()-start)/int64(time.Second))%30 == 0 {
			samples, _ := e.r.copy()
			b, _ := json.Marshal(rankingSummarize(samples, "baseline"))
			t.Logf("baseline_progress elapsed_s=%d %s", int((e.r.now()-start)/int64(time.Second)), b)
		}
	}
	return latest, enabled, nil
}
