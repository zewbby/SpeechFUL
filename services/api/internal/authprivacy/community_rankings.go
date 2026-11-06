package authprivacy

import (
	"context"
	"crypto/sha256"
	"errors"
	"slices"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/rankings"
)

// The latency objective is a percentile, not a deadline for every request.
// Leave room for infrequent local I/O stalls without turning them into errors.
const rankingReadBudget = time.Second

var errRankingNeedsMore = errors.New("ranking candidates invalidated")
var errRankingSnapshotInvalid = errors.New("ranking snapshot outside final trusted window")

func rankingsUnavailable() error { return postError("RANKINGS_UNAVAILABLE", 503) }

// BeginRankingForeground keeps background work behind the full HTTP response.
// It only schedules ranking work and does not grant access to any resource.
func (c *Community) BeginRankingForeground() func() {
	if c.rankings == nil {
		return nil
	}
	return c.rankings.ForegroundStarted()
}

// ReadRankings uses Redis only before opening the final Gate transaction.
func (c *Community) ReadRankings(ctx context.Context, bearer [32]byte) (PostResponse, error) {
	if c.rankings == nil {
		return PostResponse{}, rankingsUnavailable()
	}
	finishForeground := c.rankings.ForegroundStarted()
	defer finishForeground()
	ctx, cancel := context.WithTimeout(ctx, rankingReadBudget)
	defer cancel()
	response, err := c.readRankings(ctx, bearer)
	if errors.Is(err, errRankingSnapshotInvalid) {
		return PostResponse{}, rankingsUnavailable()
	}
	if ctx.Err() != nil && err != nil {
		return PostResponse{}, rankingsUnavailable()
	}
	return response, err
}

func (c *Community) readRankings(ctx context.Context, bearer [32]byte) (PostResponse, error) {
	token := sha256.Sum256(bearer[:])
	// This checkpoint is only a private candidate lookup bound. It cannot
	// authorize a result, extend a session, or decide current time. All those
	// decisions stay in withPostSessionAt's final trusted Gate transaction.
	var account uuid.UUID
	var generation int64
	var decision AuthorizationDecision
	var blocked []string
	err := c.pool.QueryRow(ctx, `SELECT s.account_id,s.session_generation,g.authorization_generation,g.trusted_high_watermark,COALESCE(p.blocked_channel_ids,'{}'::uuid[])
		FROM c_auth.sessions s CROSS JOIN c_auth.authorization_gate g
		LEFT JOIN c_posts.feed_preferences p ON p.account_id=s.account_id
		WHERE s.token_digest=$1 AND g.singleton_id=1`, token[:]).
		Scan(&account, &generation, &decision.Generation, &decision.TrustedAt, &blocked)
	if errors.Is(err, pgx.ErrNoRows) {
		return PostResponse{}, ErrSessionInvalid
	}
	if err != nil {
		return PostResponse{}, ErrAuthorizationUnavailable
	}

	candidateAt := decision.TrustedAt
	var verifiedAt *time.Time
	project := func(snapshot rankings.Snapshot, ids []string, expected int, preparedBlocked []string, completePrefix bool) (PostResponse, error) {
		return c.withPostSessionAt(ctx, token, account, decision, &generation,
			func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
				candidateAt = final.TrustedAt
				verifiedAt = &candidateAt
				if !snapshot.ValidAt(final.Generation, final.TrustedAt) {
					return nil, errRankingSnapshotInvalid
				}
				page := posts.PostRanking{AsOf: snapshot.Bucket, Items: []posts.RankedPost{}}
				prefs, _, err := readFeedPreferences(ctx, tx, account)
				if err != nil {
					return nil, err
				}
				blocked = prefs.BlockedChannelIDs
				if preparedBlocked != nil && !slices.Equal(preparedBlocked, blocked) {
					return nil, errRankingNeedsMore
				}
				if preparedBlocked == nil {
					var count int64
					for i, ch := range snapshot.Channels {
						if !slices.Contains(blocked, ch) {
							count += snapshot.Counts[i]
						}
					}
					expected = int(min(count, posts.PostRankingLimit))
				}
				if len(ids) > 0 {
					rows, err := tx.Query(ctx, projectRankedPostsSQL, ids, blocked, final.TrustedAt)
					if err != nil {
						return nil, err
					}
					var coverageChannels []string
					var coverageCounts []int64
					page.Items, err = pgx.CollectRows(rows, func(row pgx.CollectableRow) (item posts.RankedPost, err error) {
						err = row.Scan(&item.PostID, &item.ChannelID, &item.Title, &item.ViewCount, &coverageChannels, &coverageCounts)
						return
					})
					if err != nil {
						return nil, err
					}
					if preparedBlocked == nil && !completePrefix {
						for i, ch := range snapshot.Channels {
							if slices.Contains(blocked, ch) || snapshot.Counts[i] <= rankings.ReadLimit {
								continue
							}
							j := slices.Index(coverageChannels, ch)
							if j < 0 || coverageCounts[j] < posts.PostRankingLimit {
								return nil, errRankingNeedsMore
							}
						}
					}
					if page.Items == nil {
						page.Items = []posts.RankedPost{}
					}
				}
				if len(page.Items) < expected {
					return nil, errRankingNeedsMore
				}
				return page, nil
			})
	}

	// Spend at most one small slice of the request budget on Redis, including
	// connection acquisition. A partial or evicted version uses the SQL mirror.
	cacheCtx, cancel := context.WithTimeout(ctx, 40*time.Millisecond)
	snapshot, cacheErr := c.rankings.Snapshot(cacheCtx)
	var ids []string
	var expected int
	// A private worker's verified clock can be newer than the last public
	// checkpoint. Here validate structure and generation only. The final Gate
	// above alone decides whether the snapshot is current, stale or future.
	useCache := cacheErr == nil && snapshot.ValidAt(decision.Generation, snapshot.Bucket)
	if useCache {
		var count int64
		for _, n := range snapshot.Counts {
			count += min(n, rankings.ReadLimit)
		}
		ids, cacheErr = c.rankings.Candidates(cacheCtx, snapshot, "all", count)
		useCache = cacheErr == nil
	}
	cancel()
	if useCache {
		response, err := project(snapshot, ids[:min(len(ids), rankings.ReadLimit)], expected, nil, true)
		// The first 64 of the merged union are the exact global first 64.
		// If those fill the response, deeper shard candidates cannot outrank it.
		if errors.Is(err, errRankingNeedsMore) && len(ids) > rankings.ReadLimit {
			response, err = project(snapshot, ids, expected, nil, false)
		}
		if !errors.Is(err, errRankingNeedsMore) && !errors.Is(err, errRankingSnapshotInvalid) {
			return response, err
		}
		useCache = !errors.Is(err, errRankingSnapshotInvalid)
		// Keep the original order even if a new snapshot was published during
		// this request. The mirror can scan past the cached lookahead.
	}
	if !useCache {
		snapshot, err = c.latestRankingSnapshot(ctx, decision, verifiedAt)
		if err != nil {
			// Even an unavailable board must not mask a revoked session.
			// The empty candidate cannot pass snapshot validation, but the
			// existing final Gate decides authentication first.
			return project(rankings.Snapshot{}, nil, 0, nil, true)
		}
	}
	if candidateAt.Before(snapshot.Bucket) {
		candidateAt = snapshot.Bucket
	}
	for range 2 {
		preparedBlocked := append([]string{}, blocked...)
		ids, err = c.rankingFallback(ctx, snapshot, preparedBlocked, candidateAt)
		if err != nil {
			return PostResponse{}, rankingsUnavailable()
		}
		response, err := project(snapshot, ids, len(ids), preparedBlocked, false)
		if !errors.Is(err, errRankingNeedsMore) {
			return response, err
		}
	}
	return PostResponse{}, rankingsUnavailable()
}

func (c *Community) latestRankingSnapshot(ctx context.Context, decision AuthorizationDecision, verifiedAt *time.Time) (rankings.Snapshot, error) {
	var snapshot rankings.Snapshot
	oldest := decision.TrustedAt.Add(-rankings.MaxAge)
	if verifiedAt != nil {
		oldest = verifiedAt.Add(-rankings.MaxAge)
	}
	err := c.pool.QueryRow(ctx, readRankSnapshotSQL, decision.Generation, verifiedAt,
		oldest).Scan(&snapshot.Version, &snapshot.Generation, &snapshot.Bucket, &snapshot.Channels, &snapshot.Counts)
	if err != nil || !snapshot.ValidAt(decision.Generation, snapshot.Bucket) {
		return rankings.Snapshot{}, rankingsUnavailable()
	}
	snapshot.Bucket = snapshot.Bucket.UTC()
	return snapshot, nil
}

func (c *Community) WithRankings(ctx context.Context, cache *rankings.Cache) (*Community, error) {
	if !c.PostsEnabled() || c.comments == nil || cache == nil {
		return nil, errors.New("rankings require posts, comments and dedicated Redis")
	}
	var readable bool
	err := c.pool.QueryRow(ctx, `SELECT
		(SELECT bool_and(has_table_privilege(t,p)) FROM
		 unnest(ARRAY['c_posts.hot_snapshots','c_posts.hot_shard_data']) t
		 CROSS JOIN unnest(ARRAY['SELECT','INSERT','DELETE']) p) AND
		(SELECT bool_and(has_table_privilege(t,p)) FROM
		 unnest(ARRAY['c_posts.hot_snapshot_shards','c_posts.hot_blocks']) t
		 CROSS JOIN unnest(ARRAY['SELECT','INSERT']) p) AND
		has_table_privilege('c_posts.ranking_inputs','SELECT') AND
		has_column_privilege('c_posts.ranking_inputs','revision','UPDATE')`).Scan(&readable)
	if err != nil || !readable {
		return nil, errors.New("rankings schema or runtime grants are unavailable")
	}
	var tracked bool
	err = c.pool.QueryRow(ctx, `SELECT
		(SELECT count(*) FROM c_posts.ranking_inputs)=(SELECT count(*) FROM public.channels)
		AND (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgenabled IN ('O','A')
			AND (tgrelid,tgname::text) IN (
				('c_posts.post_likes'::regclass,'ranking_likes_insert'),
				('c_posts.post_likes'::regclass,'ranking_likes_delete'),
				('c_posts.post_favorites'::regclass,'ranking_favorites_insert'),
				('c_posts.post_favorites'::regclass,'ranking_favorites_delete'),
				('c_posts.posts'::regclass,'ranking_posts_insert'),
				('c_posts.posts'::regclass,'ranking_posts_update'),
				('c_comments.tasks'::regclass,'ranking_comments_update'),
				('c_comments.attempts'::regclass,'ranking_comment_insert'),
				('c_comments.attempts'::regclass,'ranking_comment_update'))) = 9`).Scan(&tracked)
	if err != nil || !tracked {
		return nil, errors.New("ranking source change tracking is unavailable")
	}
	copy := *c
	copy.rankings = cache
	return &copy, nil
}
