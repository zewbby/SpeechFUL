package authprivacyhttp

import (
	"encoding/json"
	"runtime"
	"testing"
	"time"
)

func TestRankingLoadWallCorrectionsPreservePerformance(t *testing.T) {
	epoch := time.Now()
	r := &rankingLoadRecorder{epoch: epoch}
	e := &rankingLoadEngine{r: r, rps: 16, started: 0, phases: []rankingLoadPhase{
		{Name: "baseline", Start: 0, End: int64(280 * time.Second)},
		{Name: "catchup", Start: int64(280 * time.Second), End: int64(400 * time.Second)},
	}}
	var samples []rankingLoadSample
	for seq := 0; seq < 400*16; seq++ {
		at := int64(seq) * int64(time.Second/16)
		phase := e.phaseFor(at)
		samples = append(samples, rankingLoadSample{At: at, End: at, Phase: phase, Kind: "arrival"}, rankingLoadSample{At: at, End: at + int64(200*time.Millisecond), Latency: int64(200 * time.Millisecond), Phase: phase, Kind: "search", Status: 200, WallAt: epoch.UnixNano() + at, WallEnd: epoch.UnixNano() + at + int64(200*time.Millisecond)})
	}
	start, end := int64(300*time.Second), int64(302*time.Second)
	events := []rankingLoadEvent{
		{At: start, WallAt: epoch.UnixNano() + start, Name: "global_hotlist_refresh_start"},
		{At: start, WallAt: epoch.UnixNano() + start, Name: "global_hotlist_aggregate_start"},
		{At: end, WallAt: epoch.UnixNano() + end, Name: "global_hotlist_aggregate_complete"},
		{At: end, WallAt: epoch.UnixNano() + end, Name: "global_hotlist_refresh"},
		{At: end + int64(25*time.Second), Name: "global_hotlist_old_quiet_span", Fields: map[string]any{"from_ns": start - int64(time.Second), "until_ns": end + int64(25*time.Second), "max_tick_gap_ns": int64(20 * time.Millisecond)}},
	}
	before, arrivalPass := e.arrivalReport(samples)
	if !arrivalPass {
		t.Fatal("synthetic fixed-rate ledger is incomplete")
	}
	windows, _ := e.matchedWindowReport(samples, events)
	encode := func(value any) string {
		b, err := json.Marshal(value)
		if err != nil {
			t.Fatal(err)
		}
		return string(b)
	}
	want := encode([]any{before, windows, rankingSummarize(samples, "catchup")})
	for _, correction := range []int64{int64(20 * time.Second), -int64(20 * time.Second)} {
		changed := append([]rankingLoadSample(nil), samples...)
		changedEvents := append([]rankingLoadEvent(nil), events...)
		for i := range changed {
			changed[i].WallAt += correction
			changed[i].WallEnd += correction
		}
		for i := range changedEvents {
			changedEvents[i].WallAt += correction
		}
		a, pass := e.arrivalReport(changed)
		if !pass {
			t.Fatal("wall correction changed the planned-arrival ledger")
		}
		w, _ := e.matchedWindowReport(changed, changedEvents)
		if got := encode([]any{a, w, rankingSummarize(changed, "catchup")}); got != want {
			t.Fatal("wall correction changed monotonic throughput, windows or P95")
		}
	}
	// Business UTC deadlines must still detect a late publication.
	bucket := time.Now().UTC().Truncate(5 * time.Minute)
	due := []rankingLoadDueBucket{{Bucket: bucket, Observed: 0}, {Bucket: bucket.Add(5 * time.Minute), Observed: int64(300 * time.Second)}}
	publication := []rankingLoadEvent{
		{At: int64(time.Second), WallAt: bucket.Add(time.Second).UnixNano(), Name: "global_hotlist_publish_complete", Fields: map[string]any{"bucket": bucket}},
		{At: int64(350 * time.Second), WallAt: bucket.Add(350 * time.Second).UnixNano(), Name: "global_hotlist_publish_complete", Fields: map[string]any{"bucket": bucket.Add(5 * time.Minute)}},
	}
	if _, pass := rankingPublicationReport(publication, due, bucket, 0); !pass {
		t.Fatal("on-time publication was rejected")
	}
	publication[1].WallAt += int64(20 * time.Second)
	if _, pass := rankingPublicationReport(publication, due, bucket, 0); pass {
		t.Fatal("wall correction hid a real UTC publication deadline violation")
	}
	publication[1].WallAt -= int64(20 * time.Second)
	publication[1].At = int64(361 * time.Second)
	if _, pass := rankingPublicationReport(publication, due, bucket, 0); pass {
		t.Fatal("UTC success hid a real RAW publication deadline violation")
	}
}

func TestRankingLoadMonotonicRawCalibration(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("formal load requires Linux CLOCK_MONOTONIC_RAW")
	}
	p := newRankingLoadClockProbe()
	p.observe()
	r := &rankingLoadRecorder{clock: p}
	start := r.now()
	if !r.waitUntil(start+int64(150*time.Millisecond), nil) || r.now()-start < int64(150*time.Millisecond) {
		t.Fatal("Go timer woke before the RAW deadline")
	}
	stopped := make(chan struct{})
	close(stopped)
	if r.waitUntil(r.now()+int64(time.Second), stopped) {
		t.Fatal("cancelled RAW wait continued")
	}
	p.observe()
	if report, valid := p.report(); !valid {
		t.Fatalf("raw calibration unavailable: %v", report)
	}
}
