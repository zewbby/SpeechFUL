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
				slog.Warn("channel_ranking_refresh_unavailable", "elapsed_ms", time.Since(start).Milliseconds())
			}
			wait = min(15*time.Second, wait)
		} else if !bucket.IsZero() {
			slog.Info("channel_ranking_ready", "bucket", bucket, "elapsed_ms", time.Since(start).Milliseconds())
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
func (c *Community) RefreshRankings(ctx context.Context, pool *pgxpool.Pool, weights RankingWeights) (time.Time, error) {
	if c == nil || c.rankings == nil || pool == nil || !weights.Valid() {
		return time.Time{}, errors.New("invalid channel ranking worker configuration")
	}
	if err := c.rankings.WaitForIdle(ctx); err != nil {
		return time.Time{}, err
	}
	decision, err := c.rankingBuildDecision(ctx, pool)
	if err != nil {
		return time.Time{}, err
	}
	bucket := decision.TrustedAt.UTC().Truncate(rankings.Interval)
	version := rankings.Version(decision.Generation, bucket)
	if err := c.buildRankingSnapshot(ctx, pool, decision, version, bucket, weights); err != nil {
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
	for i, channel := range snapshot.Channels {
		limit := min(snapshot.Counts[i], rankings.ReadLimit)
		if limit == 0 {
			continue
		}
		rows, err := pool.Query(ctx, `SELECT candidate.position,candidate.id::text
			FROM c_posts.ranking_posts link
			JOIN c_posts.ranking_channel_data r USING(data_version,channel_id)
			CROSS JOIN LATERAL unnest(r.post_ids[1:$3::int]) WITH ORDINALITY candidate(id,position)
			WHERE link.version=$1 AND r.channel_id=$2 ORDER BY candidate.position`, version, channel, limit)
		if err != nil {
			return time.Time{}, err
		}
		batch, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (entry rankings.Entry, err error) {
			err = row.Scan(&entry.Rank, &entry.PostID)
			return
		})
		if err != nil || int64(len(batch)) != limit || batch[len(batch)-1].Rank != limit {
			return time.Time{}, rankingsUnavailable()
		}
		if err := c.rankings.Stage(ctx, snapshot, channel, batch); err != nil {
			return time.Time{}, err
		}
	}
	if err := c.rankings.Publish(ctx, snapshot); err != nil {
		return time.Time{}, err
	}
	return bucket, nil
}

// Private computation needs a verified time sample, without publishing a new
// authorization checkpoint. Every public response still uses withPostSessionAt.
func (c *Community) rankingBuildDecision(ctx context.Context, pool *pgxpool.Pool) (AuthorizationDecision, error) {
	tx, err := begin(ctx, pool)
	if err != nil {
		return AuthorizationDecision{}, err
	}
	defer tx.Rollback(ctx)
	var generation uint64
	if err := tx.QueryRow(ctx, `SELECT authorization_generation FROM c_auth.authorization_gate WHERE singleton_id=1`).Scan(&generation); err != nil {
		return AuthorizationDecision{}, err
	}
	decision, err := c.gate.RecheckForCommit(ctx, tx, generation)
	if err != nil {
		// Persist an independently detected freeze after rolling back the read.
		_ = c.gate.Abort(ctx, tx)
	}
	return decision, err
}

func (c *Community) buildRankingSnapshot(ctx context.Context, pool *pgxpool.Pool, decision AuthorizationDecision, version string, bucket time.Time, weights RankingWeights) error {
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
		return errors.New("channel ranking build already in progress")
	}
	var exists bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_posts.ranking_snapshots WHERE version=$1)`, version).Scan(&exists); err != nil {
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
	if _, err := tx.Exec(ctx, `INSERT INTO c_posts.ranking_snapshots(version,generation,bucket,channel_ids) VALUES($1,$2,$3,$4)`, version, decision.Generation, bucket, channels); err != nil {
		return err
	}
	for _, channel := range channels {
		policy := fmt.Sprintf("log-v1:%d:%d:%d:%d", weights.Like, weights.Favorite, weights.Discussion, weights.HalfLifeHours)
		reused, err := tx.Exec(ctx, reuseRankingChannelSQL, version, decision.Generation, bucket, channel, policy)
		if err != nil {
			return err
		}
		if reused.RowsAffected() == 0 {
			if err := c.rankings.WaitForIdle(ctx); err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, buildRankingsSQL, version, decision.Generation, bucket, weights.Like, weights.Favorite, weights.Discussion, weights.HalfLifeHours, channel, policy); err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, `INSERT INTO c_posts.ranking_posts(version,channel_id,data_version) VALUES($1,$2,$1)`, version, channel); err != nil {
				return err
			}
		}
	}
	if _, err := tx.Exec(ctx, `UPDATE c_posts.ranking_snapshots SET channel_ids=(
		SELECT array_agg(r.channel_id ORDER BY r.participant_count DESC,r.new_post_count DESC,ch.display_order)
		FROM c_posts.ranking_posts link JOIN c_posts.ranking_channel_data r USING(data_version,channel_id)
		JOIN public.channels ch ON ch.id=r.channel_id WHERE link.version=$1)
		WHERE version=$1`, version); err != nil {
		return err
	}
	// Reuse before retention so a delayed cycle can keep unchanged data. The
	// new references protect that data when older public snapshots expire.
	if _, err := tx.Exec(ctx, `DELETE FROM c_posts.ranking_snapshots WHERE version=(
		SELECT version FROM c_posts.ranking_snapshots WHERE bucket<=$1 ORDER BY bucket LIMIT 1)`, bucket.Add(-rankings.MaxAge)); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `DELETE FROM c_posts.ranking_channel_data WHERE (data_version,channel_id) IN (
		SELECT d.data_version,d.channel_id FROM c_posts.ranking_channel_data d
		WHERE NOT EXISTS (SELECT 1 FROM c_posts.ranking_posts r WHERE r.data_version=d.data_version AND r.channel_id=d.channel_id)
		ORDER BY d.data_version LIMIT 7)`); err != nil {
		return err
	}
	// This transaction publishes only derived private candidate IDs. It must
	// not serialize foreground business on the authorization row. Every
	// public read still executes withPostSessionAt and its final Gate check.
	// A recovery racing this commit leaves an old-generation cache that no
	// reader can authorize; a later worker replaces it.
	if err := c.rankings.WaitForIdle(ctx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
