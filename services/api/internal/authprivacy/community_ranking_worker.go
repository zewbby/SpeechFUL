package authprivacy

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/rankings"
)

type RankingWeights struct {
	Like          int `json:"like"`
	Favorite      int `json:"favorite"`
	Discussion    int `json:"discussion"`
	HalfLifeHours int `json:"halfLifeHours"`
}

func DefaultRankingWeights() RankingWeights {
	return RankingWeights{Like: 1, Favorite: 2, Discussion: 3, HalfLifeHours: 48}
}

func (w RankingWeights) Valid() bool {
	return w.Like > 0 && w.Like <= 100 && w.Favorite > 0 && w.Favorite <= 100 &&
		w.Discussion > 0 && w.Discussion <= 100 && w.HalfLifeHours >= 1 && w.HalfLifeHours <= 168
}

// RunRankings has its own one-connection worker pool. Redis and aggregate SQL
// never run while holding the final C Gate lock.
func (c *Community) RunRankings(ctx context.Context, pool *pgxpool.Pool, weights RankingWeights) {
	for ctx.Err() == nil {
		start := time.Now()
		work, cancel := context.WithTimeout(ctx, 25*time.Second)
		bucket, err := c.RefreshRankings(work, pool, weights)
		cancel()
		wait := time.Until(start.Truncate(rankings.Interval).Add(rankings.Interval))
		// A concurrent builder may own this bucket, or Redis may still be
		// down. Retry publication without recalculating a committed snapshot.
		if err != nil {
			if ctx.Err() == nil {
				slog.Warn("global_hotlist_refresh_unavailable", "elapsed_ms", time.Since(start).Milliseconds())
			}
			wait = min(15*time.Second, wait)
		} else if !bucket.IsZero() {
			slog.Info("global_hotlist_ready", "bucket", bucket, "elapsed_ms", time.Since(start).Milliseconds())
		}
		timer := time.NewTimer(max(wait, time.Second))
		select {
		case <-ctx.Done():
		case <-timer.C:
		}
		timer.Stop()
	}
}

// RefreshRankings builds or republishes the current trusted time bucket.
func (c *Community) RefreshRankings(ctx context.Context, pool *pgxpool.Pool, weights RankingWeights) (bucket time.Time, resultErr error) {
	metrics := rankingRefreshMetrics{started: time.Now()}
	slog.Info("global_hotlist_refresh_start")
	defer func() {
		slog.Info("global_hotlist_refresh", "success", resultErr == nil, "bucket", bucket, "attempt_bucket", metrics.target,
			"elapsed_ms", time.Since(metrics.started).Milliseconds(), "yield_ms", metrics.yield.Milliseconds(),
			"aggregate_ms", metrics.aggregate.Milliseconds(), "commit_ms", metrics.commit.Milliseconds(),
			"computed_shards", metrics.computed, "reused_shards", metrics.reused)
	}()
	if c == nil || c.rankings == nil || pool == nil || !weights.Valid() {
		return time.Time{}, errors.New("invalid global hotlist worker configuration")
	}
	yieldAt := time.Now()
	if err := c.rankings.YieldToForeground(ctx); err != nil {
		return time.Time{}, err
	}
	metrics.yield += time.Since(yieldAt)
	decision, err := c.postCandidateDecision(ctx, pool)
	if err != nil {
		return time.Time{}, err
	}
	bucket = decision.TrustedAt.UTC().Truncate(rankings.Interval)
	metrics.target = bucket
	version := rankings.Version(decision.Generation, bucket)
	if err := c.buildRankingSnapshot(ctx, pool, decision, version, bucket, weights, &metrics); err != nil {
		return time.Time{}, err
	}

	var snapshot rankings.Snapshot
	err = pool.QueryRow(ctx, readRankSnapshotSQL, decision.Generation, bucket, bucket.Add(-rankings.Interval)).
		Scan(&snapshot.Version, &snapshot.Generation, &snapshot.Bucket, &snapshot.Channels, &snapshot.Counts)
	if err != nil || snapshot.Version != version || !snapshot.ValidAt(decision.Generation, decision.TrustedAt) {
		return time.Time{}, rankingsUnavailable()
	}
	snapshot.Bucket = snapshot.Bucket.UTC()

	current, err := c.rankings.Snapshot(ctx)
	if err == nil && current.Version == version && current.ValidAt(decision.Generation, decision.TrustedAt) {
		return time.Time{}, nil
	}
	candidates, err := readRankingBlock(ctx, pool, snapshot, snapshot.Channels, 0)
	if err != nil {
		return time.Time{}, err
	}
	sortRankingCandidates(candidates)
	var expected int64
	for _, n := range snapshot.Counts {
		expected += min(n, rankings.ReadLimit)
	}
	if int64(len(candidates)) != expected {
		return time.Time{}, rankingsUnavailable()
	}
	if len(candidates) > 0 {
		batch := make([]rankings.Entry, len(candidates))
		for i, item := range candidates {
			batch[i] = rankings.Entry{Rank: int64(i + 1), PostID: item.id}
		}
		if err := c.rankings.Stage(ctx, snapshot, "all", batch); err != nil {
			return time.Time{}, err
		}
	}
	slog.Info("global_hotlist_publish_start", "bucket", bucket, "version", snapshot.Version)
	if err := c.rankings.Publish(ctx, snapshot); err != nil {
		return time.Time{}, err
	}
	slog.Info("global_hotlist_publish_complete", "bucket", bucket, "version", snapshot.Version)
	return bucket, nil
}

type rankingRefreshMetrics struct {
	started                  time.Time
	target                   time.Time
	yield, aggregate, commit time.Duration
	computed, reused         int
}

func (c *Community) buildRankingSnapshot(ctx context.Context, pool *pgxpool.Pool, decision AuthorizationDecision, version string, bucket time.Time, weights RankingWeights, metrics *rankingRefreshMetrics) error {
	tx, err := begin(ctx, pool)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var locked bool
	if err := tx.QueryRow(ctx, `SELECT pg_try_advisory_xact_lock(1213092936,31)`).Scan(&locked); err != nil {
		return err
	}
	if !locked {
		return errors.New("global hotlist build already in progress")
	}
	var exists bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_posts.hot_snapshots WHERE version=$1)`, version).Scan(&exists); err != nil {
		return err
	}
	if exists {
		return nil
	}
	rows, err := tx.Query(ctx, `SELECT id::text FROM public.channels ORDER BY display_order`)
	if err != nil {
		return err
	}
	channels, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil || len(channels) == 0 || len(channels) > 7 {
		return errors.New("ranking channel directory unavailable")
	}
	if _, err := tx.Exec(ctx, `INSERT INTO c_posts.hot_snapshots(version,generation,bucket,channel_ids) VALUES($1,$2,$3,$4)`, version, decision.Generation, bucket, channels); err != nil {
		return err
	}
	for _, channel := range channels {
		policy := fmt.Sprintf("global-block-v2:%d:%d:%d:%d", weights.Like, weights.Favorite, weights.Discussion, weights.HalfLifeHours)
		reused, err := tx.Exec(ctx, reuseRankingChannelSQL, version, decision.Generation, bucket, channel, policy)
		if err != nil {
			return err
		}
		if reused.RowsAffected() == 0 {
			yieldAt := time.Now()
			if err := c.rankings.YieldToForeground(ctx); err != nil {
				return err
			}
			metrics.yield += time.Since(yieldAt)
			aggregateAt := time.Now()
			slog.Info("global_hotlist_aggregate_start", "bucket", bucket, "shard", channel)
			_, buildErr := tx.Exec(ctx, buildRankingsSQL, version, decision.Generation, bucket, weights.Like, weights.Favorite, weights.Discussion, weights.HalfLifeHours, channel, policy)
			slog.Info("global_hotlist_aggregate_complete", "bucket", bucket, "shard", channel, "success", buildErr == nil)
			metrics.aggregate += time.Since(aggregateAt)
			if buildErr != nil {
				return buildErr
			}
			metrics.computed++
			if _, err := tx.Exec(ctx, `INSERT INTO c_posts.hot_snapshot_shards(version,channel_id,data_version) VALUES($1,$2,$1)`, version, channel); err != nil {
				return err
			}
		} else {
			metrics.reused++
		}
	}
	// Reuse before retention so a delayed cycle can keep unchanged data. The
	// new references protect that data when older public snapshots expire.
	if _, err := tx.Exec(ctx, `DELETE FROM c_posts.hot_snapshots WHERE version=(
		SELECT version FROM c_posts.hot_snapshots WHERE bucket<=$1 ORDER BY bucket LIMIT 1)`, bucket.Add(-rankings.MaxAge)); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `DELETE FROM c_posts.hot_shard_data WHERE (data_version,channel_id) IN (
		SELECT d.data_version,d.channel_id FROM c_posts.hot_shard_data d
		WHERE NOT EXISTS (SELECT 1 FROM c_posts.hot_snapshot_shards r WHERE r.data_version=d.data_version AND r.channel_id=d.channel_id)
		ORDER BY d.data_version LIMIT 7)`); err != nil {
		return err
	}
	// This transaction publishes only derived private candidate IDs. It must
	// not serialize foreground business on the authorization row. Every
	// public read still executes withPostSessionAt and its final Gate check.
	// A recovery racing this commit leaves an old-generation cache that no
	// reader can authorize; a later worker replaces it.
	commitAt := time.Now()
	slog.Info("global_hotlist_commit_start", "bucket", bucket)
	err = tx.Commit(ctx)
	slog.Info("global_hotlist_commit_complete", "bucket", bucket, "success", err == nil)
	metrics.commit = time.Since(commitAt)
	return err
}
