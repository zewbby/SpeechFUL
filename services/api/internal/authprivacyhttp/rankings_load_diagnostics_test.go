package authprivacyhttp

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Optional diagnostics use a separate connection in the marker-checked fixture.
// No request values or query text are recorded. Keep this off in acceptance runs.
func startRankingLoadDiagnostics(t *testing.T, f *rankingLoadFixture, r *rankingLoadRecorder) {
	t.Helper()
	config := f.s.cp.Config()
	config.MaxConns, config.MinConns = 1, 0
	config.ConnConfig.RuntimeParams["application_name"] += "_ranking_observer"
	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		t.Fatal(err)
	}
	file, err := os.OpenFile(filepath.Join(os.Getenv("RANKING_LOAD_ARTIFACT_DIR"), "database-observations.jsonl"), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		pool.Close()
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	var failure error
	go func() {
		defer close(done)
		encoder := json.NewEncoder(file)
		nextStats := int64(0)
		for r.waitUntil(r.now()+int64(50*time.Millisecond), ctx.Done()) {
			var activity json.RawMessage
			err := pool.QueryRow(ctx, `SELECT COALESCE(json_agg(x),'[]') FROM (
				SELECT pid,application_name,state,wait_event_type,wait_event,pg_blocking_pids(pid) AS blockers
				FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid()) x`).Scan(&activity)
			if err != nil {
				if ctx.Err() == nil {
					failure = err
				}
				return
			}
			at := r.now()
			stats := f.s.cp.Stat()
			entry := map[string]any{"at_ns": at, "activity": activity,
				"foreground_pool": map[string]any{"acquired": stats.AcquiredConns(), "acquires": stats.AcquireCount(),
					"empty_acquires": stats.EmptyAcquireCount(), "acquire_duration_ns": stats.AcquireDuration().Nanoseconds()}}
			if at >= nextStats {
				var counters json.RawMessage
				err = pool.QueryRow(ctx, `SELECT json_build_object(
					'database',(SELECT row_to_json(d) FROM (SELECT blks_read,blks_hit,temp_files,temp_bytes,blk_read_time,blk_write_time
					 FROM pg_stat_database WHERE datname=current_database()) d),
					'wal',(SELECT row_to_json(w) FROM (SELECT wal_records,wal_fpi,wal_bytes,wal_buffers_full,wal_write,wal_sync FROM pg_stat_wal) w),
					'io',(SELECT json_agg(i) FROM (SELECT backend_type,object,context,reads,writes,writebacks,extends,op_bytes,hits,evictions,fsyncs FROM pg_stat_io) i))`).Scan(&counters)
				if err != nil {
					if ctx.Err() == nil {
						failure = err
					}
					return
				}
				entry["counters"] = counters
				nextStats = at + int64(time.Second)
			}
			if err = encoder.Encode(entry); err != nil {
				failure = err
				return
			}
		}
	}()
	t.Cleanup(func() {
		cancel()
		<-done
		pool.Close()
		if err := file.Close(); err != nil {
			t.Error(err)
		}
		if failure != nil {
			t.Errorf("ranking diagnostic evidence: %v", failure)
		}
	})
}
