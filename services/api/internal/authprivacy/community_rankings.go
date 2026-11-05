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
// Empty channel means directory order, not an all-channel posts leaderboard.
func (c *Community) ReadRankings(ctx context.Context, bearer [32]byte, channel string) (PostResponse, error) {
	if c.rankings == nil {
		return PostResponse{}, rankingsUnavailable()
	}
	finishForeground := c.rankings.ForegroundStarted()
	defer finishForeground()
	if channel != "" {
		if _, err := posts.ParseResourceID(channel); err != nil {
			return PostResponse{}, postError("MALFORMED_REQUEST", 400)
		}
	}
	ctx, cancel := context.WithTimeout(ctx, rankingReadBudget)
	defer cancel()
	response, err := c.readRankings(ctx, bearer, channel)
	if errors.Is(err, errRankingSnapshotInvalid) {
		return PostResponse{}, rankingsUnavailable()
	}
	if ctx.Err() != nil && err != nil {
		return PostResponse{}, rankingsUnavailable()
	}
	return response, err
}

func (c *Community) readRankings(ctx context.Context, bearer [32]byte, channel string) (PostResponse, error) {
	token := sha256.Sum256(bearer[:])
	// This checkpoint is only a private candidate lookup bound. It cannot
	// authorize a result, extend a session, or decide current time. All those
	// decisions stay in withPostSessionAt's final trusted Gate transaction.
	var account uuid.UUID
	var generation int64
	var decision AuthorizationDecision
	err := c.pool.QueryRow(ctx, `SELECT s.account_id,s.session_generation,g.authorization_generation,g.trusted_high_watermark
		FROM c_auth.sessions s CROSS JOIN c_auth.authorization_gate g
		WHERE s.token_digest=$1 AND g.singleton_id=1`, token[:]).
		Scan(&account, &generation, &decision.Generation, &decision.TrustedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return PostResponse{}, ErrSessionInvalid
	}
	if err != nil {
		return PostResponse{}, ErrAuthorizationUnavailable
	}

	candidateAt := decision.TrustedAt
	var verifiedAt *time.Time
	project := func(snapshot rankings.Snapshot, ids []string, expected int) (PostResponse, error) {
		return c.withPostSessionAt(ctx, token, account, decision, &generation,
			func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
				candidateAt = final.TrustedAt
				verifiedAt = &candidateAt
				if !snapshot.ValidAt(final.Generation, final.TrustedAt) {
					return nil, errRankingSnapshotInvalid
				}
				if channel == "" {
					return posts.ChannelRanking{AsOf: snapshot.Bucket, ChannelIDs: snapshot.Channels}, nil
				}
				page := posts.PostRanking{AsOf: snapshot.Bucket, ChannelID: channel, Items: []posts.RankedPost{}}
				if err := requirePostSearchChannel(ctx, tx, channel); err != nil {
					return nil, err
				}
				prefs, _, err := readFeedPreferences(ctx, tx, account)
				if err != nil {
					return nil, err
				}
				if slices.Contains(prefs.BlockedChannelIDs, channel) {
					return page, nil
				}
				if len(ids) > 0 {
					rows, err := tx.Query(ctx, projectRankedPostsSQL, ids, channel, final.TrustedAt)
					if err != nil {
						return nil, err
					}
					page.Items, err = pgx.CollectRows(rows, func(row pgx.CollectableRow) (item posts.RankedPost, err error) {
						err = row.Scan(&item.PostID, &item.Title, &item.ViewCount)
						return
					})
					if err != nil {
						return nil, err
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
	if useCache && channel != "" {
		if i := slices.Index(snapshot.Channels, channel); i >= 0 {
			ids, cacheErr = c.rankings.Candidates(cacheCtx, snapshot, channel, snapshot.Counts[i])
			expected = int(min(snapshot.Counts[i], posts.PostRankingLimit))
			useCache = cacheErr == nil
		} else {
			useCache = false
		}
	}
	cancel()
	if useCache {
		response, err := project(snapshot, ids, expected)
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
			return project(rankings.Snapshot{}, nil, 0)
		}
	}
	if channel == "" {
		return project(snapshot, nil, 0)
	}
	if candidateAt.Before(snapshot.Bucket) {
		candidateAt = snapshot.Bucket
	}
	for range 2 {
		rows, err := c.pool.Query(ctx, rankFallbackSQL, snapshot.Version, channel, candidateAt)
		if err != nil {
			return PostResponse{}, rankingsUnavailable()
		}
		ids, err := pgx.CollectRows(rows, pgx.RowTo[string])
		if err != nil {
			return PostResponse{}, rankingsUnavailable()
		}
		response, err := project(snapshot, ids, len(ids))
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
	err := c.pool.QueryRow(ctx, `SELECT has_table_privilege('c_posts.ranking_snapshots','SELECT')
		AND has_table_privilege('c_posts.ranking_snapshots','INSERT')
		AND has_table_privilege('c_posts.ranking_snapshots','DELETE')
		AND has_column_privilege('c_posts.ranking_snapshots','channel_ids','UPDATE')
		AND has_table_privilege('c_posts.ranking_posts','SELECT')
		AND has_table_privilege('c_posts.ranking_posts','INSERT')
		AND has_table_privilege('c_posts.ranking_channel_data','SELECT')
		AND has_table_privilege('c_posts.ranking_channel_data','INSERT')
		AND has_table_privilege('c_posts.ranking_channel_data','DELETE')
		AND has_table_privilege('c_posts.ranking_inputs','SELECT')
		AND has_column_privilege('c_posts.ranking_inputs','revision','UPDATE')`).Scan(&readable)
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
