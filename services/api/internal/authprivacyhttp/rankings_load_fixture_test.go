package authprivacyhttp

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/rankings"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/readtiming"
)

// Only e2ePool's marker-checked disposable database and the runner-owned Redis
// may be used. This fixture never accepts a caller-provided production DSN.
type rankingLoadFixture struct {
	s                  *e2eServices
	cache              *rankings.Cache
	worker             *pgxpool.Pool
	tokens             []string
	channels, canaries []string
	sample             string
	clockMu            sync.Mutex
	traces             []rankingLoadTrace
	traceMu            sync.Mutex
}

type rankingLoadTrace struct {
	At          int64                  `json:"at_ns"`
	End         int64                  `json:"end_ns"`
	Observation readtiming.Observation `json:"observation"`
}

func newRankingLoadFixture(t *testing.T, clients int, recorder *rankingLoadRecorder) *rankingLoadFixture {
	t.Helper()
	started := time.Now()
	socket, address := os.Getenv("RANKING_REDIS_SOCKET"), os.Getenv("RANKING_REDIS_TCP_ADDRESS")
	if socket == "" || address == "" {
		t.Fatal("owned Unix control socket and loopback TCP Redis fixture required")
	}
	dsn, parseErr := url.Parse(os.Getenv("AUTHLAB_C_DSN"))
	if parseErr != nil || os.Getenv("AUTHLAB_ALLOW_SCHEMA_RESET") != "1" || !strings.HasPrefix(os.Getenv("AUTHLAB_RUNTIME_TAG"), "hnuhole_authlab_") ||
		filepath.Dir(socket) != filepath.Dir(dsn.Query().Get("host")) || filepath.Base(socket) != "rankings.sock" {
		t.Fatal("Redis control socket does not belong to the disposable PostgreSQL fixture")
	}
	admin := redis.NewClient(&redis.Options{Network: "unix", Addr: socket})
	t.Cleanup(func() { _ = admin.Close() })
	environment, password := uuid.NewString(), uuid.NewString()
	const timeout = 40 * time.Millisecond
	cache := rankings.NewCache(&redis.Options{Addr: address, Username: "c_rankings", Password: password,
		PoolSize: 8, MaxActiveConns: 8, MaxRetries: -1, ContextTimeoutEnabled: true,
		DialTimeout: timeout, PoolTimeout: timeout, ReadTimeout: timeout, WriteTimeout: timeout}, environment)
	t.Cleanup(func() { _ = cache.Close() })
	ctx := context.Background()
	s := e2eNewServicesWithTLSLifetime(t, 3*time.Hour, func(c *authprivacy.Community) *authprivacy.Community {
		var err error
		c, err = c.WithComments(ctx, authprivacy.CommentConfig{KeyKey: e2eKey(t), FingerprintKey: e2eKey(t)})
		if err != nil {
			t.Fatal(err)
		}
		c, err = c.WithRankings(ctx, cache)
		if err != nil {
			t.Fatal(err)
		}
		return c
	})
	transport := s.client.Transport.(*http.Transport)
	transport.MaxIdleConns, transport.MaxIdleConnsPerHost = 128, clients+4
	if err := admin.Do(context.Background(), "ACL", "SETUSER", "c_rankings", "reset", "on", ">"+password,
		"~hnuhole:channel-rankings:v2:"+environment+":*", "+@connection", "+get", "+set", "+zrange", "+zadd", "+expire", "+multi", "+exec", "+discard", "+eval", "+evalsha").Err(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = admin.Do(context.Background(), "ACL", "DELUSER", "c_rankings").Err() })
	config := s.cp.Config()
	config.MaxConns, config.MinConns = 1, 0
	config.ConnConfig.RuntimeParams["max_parallel_workers_per_gather"] = "0"
	config.ConnConfig.RuntimeParams["application_name"] += "_ranking_worker"
	worker, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(worker.Close)
	f := &rankingLoadFixture{s: s, cache: cache, worker: worker}
	if os.Getenv("RANKING_LOAD_TRACE") == "1" {
		var requests atomic.Uint64
		handler := s.cPublic.Config.Handler
		s.cPublic.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path != postSearchPath || requests.Add(1)%8 != 0 {
				handler.ServeHTTP(w, r)
				return
			}
			ctx, trace := readtiming.Start(r.Context())
			at := recorder.now()
			handler.ServeHTTP(w, r.WithContext(ctx))
			entry := rankingLoadTrace{At: at, End: recorder.now(), Observation: trace.Snapshot()}
			f.traceMu.Lock()
			f.traces = append(f.traces, entry)
			f.traceMu.Unlock()
		})
		t.Cleanup(func() {
			f.traceMu.Lock()
			defer f.traceMu.Unlock()
			b, err := json.MarshalIndent(f.traces, "", "  ")
			if err != nil {
				t.Error(err)
				return
			}
			if err := os.WriteFile(filepath.Join(os.Getenv("RANKING_LOAD_ARTIFACT_DIR"), "read-traces.json"), b, 0600); err != nil {
				t.Error(err)
			}
		})
	}
	if os.Getenv("RANKING_LOAD_DIAGNOSTICS") == "1" {
		startRankingLoadDiagnostics(t, f, recorder)
	}
	owner, ownerID := e2ePrivacySignup(t, s, "rank_load_owner")
	identity := postHTTPSIdentity(t, s, owner, "合成作者", 71)
	catalog := e2eJSON(t, s.client, "GET", s.cPublic.URL+"/api/v1/channels", nil, map[string]string{"Authorization": "Bearer " + owner}, 200)
	for _, value := range catalog["channels"].([]any) {
		f.channels = append(f.channels, value.(map[string]any)["id"].(string))
	}
	created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 72), owner, "", posts.CreatePostInput{ChannelID: f.channels[0], IdentityID: identity, Title: "持续流量详情", Body: "一次性合成数据"}, 202)
	if _, err := s.c.PublishAcceptedPosts(ctx, 100); err != nil {
		t.Fatal(err)
	}
	f.sample = created["postId"].(string)
	var commentAccount, commentIdentity string
	for i := 0; i < clients; i++ {
		token, account := e2ePrivacySignup(t, s, fmt.Sprintf("rank_load_reader_%02d", i))
		f.tokens = append(f.tokens, token)
		if i == 0 {
			commentAccount = account
			commentIdentity = postHTTPSIdentity(t, s, token, "合成读者", 73)
		}
		if (i+1)%16 == 0 {
			t.Logf("load_fixture_clients_ready count=%d elapsed_s=%.1f", i+1, time.Since(started).Seconds())
		}
	}
	tx, err := s.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	queries := []struct {
		sql  string
		args []any
	}{
		{`CREATE TEMP TABLE rank_seed ON COMMIT DROP AS SELECT gen_random_uuid() AS post,gen_random_uuid() AS task,
		 ($2::uuid[])[1+(i-1)%cardinality($2::uuid[])] AS channel,
		 clock_timestamp()-interval '1 day'-i*interval '1 second' AS at,
		 nextval('c_posts.publication_ordinal_seq') AS publication,nextval('c_posts.acceptance_ordinal_seq') AS acceptance,i
		 FROM generate_series(1,$1::int) i`, []any{30000, f.channels}},
		{`INSERT INTO c_posts.posts(post_id,owner_account_id,channel_id,visibility,published_attempt_version,published_at,publication_ordinal)
		 SELECT post,$1,channel,'PUBLISHED',1,at,publication FROM rank_seed`, []any{ownerID}},
		{`INSERT INTO c_posts.post_identity_bindings(account_id,post_id,identity_id,bound_at) SELECT $1,post,$2,at FROM rank_seed`, []any{ownerID, identity}},
		{`INSERT INTO c_posts.publication_tasks(task_id,post_id,owner_account_id,identity_id,channel_id,latest_attempt_version) SELECT task,post,$1,$2,channel,1 FROM rank_seed`, []any{ownerID, identity}},
		{`INSERT INTO c_posts.publication_attempts(task_id,version,accepted_stop_generation,state,accepted_at,acceptance_ordinal,terminal_at) SELECT task,1,0,'PUBLISHED',at,acceptance,at FROM rank_seed`, nil},
		{`INSERT INTO c_posts.attempt_contents(task_id,version,title,body,request_digest) SELECT task,1,'压测语料 '||i,
		 '合成语料 '||CASE WHEN i%10=0 THEN '跨页样本 ' ELSE '' END||repeat(md5(i::text)||' 独立字符 ',64),decode(repeat('00',32),'hex') FROM rank_seed`, nil},
		{`INSERT INTO c_posts.post_likes(account_id,post_id) SELECT $1,post FROM rank_seed WHERE i<=3000`, []any{commentAccount}},
		{`INSERT INTO c_posts.post_favorites(account_id,post_id,saved_at) SELECT $1,post,clock_timestamp() FROM rank_seed WHERE i>27000`, []any{commentAccount}},
		{`CREATE TEMP TABLE comment_seed ON COMMIT DROP AS SELECT gen_random_uuid() AS task,gen_random_uuid() AS comment,p.post,p.at+interval '1 hour' AS at FROM rank_seed p CROSS JOIN generate_series(1,10) n WHERE p.i<=3000`, nil},
		// Accelerate deferred fixture validation without changing the schema
		// used by measured queries. All constraints are checked before removal.
		{`CREATE INDEX ranking_load_receipt_lookup ON c_comments.receipts(task_id,version)`, nil},
		{`INSERT INTO c_posts.post_identity_bindings(account_id,post_id,identity_id,bound_at) SELECT $1,post,$2,min(at) FROM comment_seed GROUP BY post`, []any{commentAccount, commentIdentity}},
		{`INSERT INTO c_comments.tasks(task_id,comment_id,owner_account_id,post_id,identity_id) SELECT task,comment,$1,post,$2 FROM comment_seed`, []any{commentAccount, commentIdentity}},
		{`INSERT INTO c_comments.attempts(task_id,version,state,accepted_at,accepted_stop_generation,body) SELECT task,1,'ACCEPTED',at,0,'独立合成评论' FROM comment_seed`, nil},
		{`INSERT INTO c_comments.receipts(key_digest,owner_account_id,intent_fingerprint,operation,outcome,task_id,version,committed_at)
		 SELECT decode(md5(task::text)||md5(task::text),'hex'),$1,decode(repeat('00',32),'hex'),'CREATE','ACCEPTED',task,1,at FROM comment_seed`, []any{commentAccount}},
		{`UPDATE c_comments.attempts a SET state='PUBLISHED',terminal_at=s.at FROM comment_seed s WHERE a.task_id=s.task`, nil},
		{`SET CONSTRAINTS ALL IMMEDIATE`, nil},
		{`DROP INDEX c_comments.ranking_load_receipt_lookup`, nil},
	}
	for i, q := range queries {
		if _, err := tx.Exec(ctx, q.sql, q.args...); err != nil {
			t.Fatalf("synthetic ranking seed %d: %v", i, err)
		}
	}
	rows, err := tx.Query(ctx, `SELECT post::text FROM rank_seed WHERE i BETWEEN 3001 AND 3007 ORDER BY channel`)
	if err != nil {
		t.Fatal(err)
	}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			t.Fatal(err)
		}
		f.canaries = append(f.canaries, id)
	}
	rows.Close()
	if rows.Err() != nil {
		t.Fatal(rows.Err())
	}
	// Align the canary IDs to the same directory order used by input fences.
	for i, channel := range f.channels {
		if err := tx.QueryRow(ctx, `SELECT post::text FROM rank_seed WHERE i BETWEEN 3001 AND 3007 AND channel=$1`, channel).Scan(&f.canaries[i]); err != nil {
			t.Fatal(err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	for _, table := range []string{"c_posts.posts", "c_posts.publication_tasks", "c_posts.attempt_contents", "c_posts.post_likes", "c_posts.post_favorites", "c_comments.tasks", "c_comments.attempts"} {
		if _, err := s.cp.Exec(ctx, "ANALYZE "+table); err != nil {
			t.Fatal(err)
		}
	}
	t.Logf("load_fixture_ready posts=30001 comments=30000 likes=3000 favorites=3000 clients=%d elapsed_s=%.1f", clients, time.Since(started).Seconds())
	return f
}

func (f *rankingLoadFixture) advanceClock(delta time.Duration) {
	if delta != 0 {
		panic("ranking load must never accelerate the business clock")
	}
	f.clockMu.Lock()
	defer f.clockMu.Unlock()
	f.s.advanceC(delta)
}

func rankingLoadInt(t *testing.T, name string, def, min, max int) int {
	t.Helper()
	raw := os.Getenv(name)
	if raw == "" {
		return def
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n < min || n > max {
		t.Fatalf("invalid %s", name)
	}
	return n
}
