package authprivacy

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/readtiming"
)

var errPostSearchChanged = errors.New("post search candidates or preferences changed")

const postSearchColumnsSQL = `SELECT count(*)=3 FROM pg_attribute
WHERE attrelid='c_posts.posts'::regclass AND NOT attisdropped AND
((attname IN ('edited_title','edited_body') AND atttypid='text'::regtype)
 OR (attname='tags' AND atttypid='text[]'::regtype AND attnotnull))`

func (c *Community) SearchPosts(ctx context.Context, bearer [32]byte, query posts.SearchQuery) (PostResponse, error) {
	keyword, err := posts.NormalizeSearchKeyword(query.Keyword)
	if err != nil {
		return PostResponse{}, err
	}
	query.Keyword = keyword
	if query.ChannelID != "" {
		if _, err := posts.ParseResourceID(query.ChannelID); err != nil {
			return PostResponse{}, err
		}
	}
	if query.Sort == "" {
		query.Sort = posts.SearchRelevance
	}
	if query.Sort != posts.SearchRelevance && query.Sort != posts.SearchLatest {
		return PostResponse{}, posts.ErrInvalidIntent
	}
	if query.Limit == 0 {
		query.Limit = 20
	}
	if query.Limit < 1 || query.Limit > 50 || query.Cursor != "" && query.RecordHistory {
		return PostResponse{}, posts.ErrInvalidIntent
	}
	if !c.PostsEnabled() {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	if c.rankings != nil {
		finishForeground := c.rankings.ForegroundStarted()
		defer finishForeground()
	}
	decision, err := c.postCandidateDecision(ctx, c.pool)
	if err != nil {
		return PostResponse{}, err
	}
	token := sha256.Sum256(bearer[:])
	account, generation, err := c.precheckPostSearchSession(ctx, token, decision)
	if err != nil {
		return PostResponse{}, err
	}
	// A candidate can disappear between the two queries. Retry outside the
	// Gate once so invalidated rows do not create holes or a false last page.
	for attempt := 0; attempt < 2; attempt++ {
		prepared, err := c.preparePostSearch(ctx, account, query, decision.TrustedAt)
		if err != nil {
			return PostResponse{}, err
		}
		response, err := c.withPostSessionAt(ctx, token, account, decision, &generation, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
			page, err := c.finishPostSearch(ctx, tx, account, query, prepared, final.TrustedAt)
			if err != nil {
				return nil, err
			}
			if query.RecordHistory {
				if err := recordPostSearchHistory(ctx, tx, account, query.ChannelID, query.Keyword, final.TrustedAt); err != nil {
					return nil, err
				}
			}
			return page, nil
		})
		if !errors.Is(err, errPostSearchChanged) {
			return response, err
		}
	}
	return PostResponse{}, ErrAuthorizationUnavailable
}

// This unlocked read rejects invalid bearers before scanning content. The
// final transaction locks these rows, samples trusted time and checks activity.
func (c *Community) precheckPostSearchSession(ctx context.Context, token [32]byte, decision AuthorizationDecision) (uuid.UUID, int64, error) {
	var account credentialAccount
	var session credentialSession
	err := c.pool.QueryRow(ctx, `SELECT a.account_id,a.state,a.session_generation,r.ban_state,r.ban_ends_at,
	s.session_generation,s.authorization_generation,s.expires_at,s.revoked_at,s.revocation_reason
FROM c_auth.sessions s JOIN c_auth.accounts a USING(account_id)
JOIN c_auth.account_restrictions r USING(account_id)
WHERE s.token_digest=$1`, token[:]).Scan(&account.account, &account.state, &account.generation, &account.ban.state, &account.ban.ends,
		&session.generation, &session.authGeneration, &session.expires, &session.revoked, &session.reason)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, 0, ErrSessionInvalid
	}
	if err != nil {
		return uuid.Nil, 0, ErrAuthorizationUnavailable
	}
	return account.account, session.generation, session.validate(account, decision)
}

// The first page fixes the channel order by each group's top hit. On continuation
// use that order even if a top hit disappears. Only publication keys and
// ordering metadata leave this query.
const searchCandidatesSQL = `
WITH matched AS (
	SELECT p.post_id, p.channel_id, p.published_at, p.publication_ordinal,
		CASE WHEN NOT $1::boolean THEN 0
			WHEN words.title = words.keyword THEN 3
			WHEN strpos(words.title, words.keyword) > 0 THEN 2
			ELSE 1
		END AS relevance
	FROM c_posts.posts p
	JOIN c_posts.publication_tasks t ON t.post_id = p.post_id
	JOIN c_posts.attempt_contents x ON x.task_id = t.task_id AND x.version = p.published_attempt_version
	CROSS JOIN LATERAL (
		SELECT lower(COALESCE(to_jsonb(p)->>'edited_title',x.title) COLLATE pg_catalog."und-x-icu") AS title,
			lower(COALESCE(to_jsonb(p)->>'edited_body',x.body) COLLATE pg_catalog."und-x-icu") AS body,
			lower($2::text COLLATE pg_catalog."und-x-icu") AS keyword
	) words
	WHERE p.visibility = 'PUBLISHED' AND NOT p.moderation_hidden AND x.erased_at IS NULL
		AND p.publication_ordinal <= $3
		AND ($4::uuid IS NULL OR p.channel_id = $4)
		AND NOT (p.channel_id = ANY($5::uuid[]))
		AND (strpos(words.title, words.keyword) > 0 OR strpos(words.body, words.keyword) > 0
   OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(COALESCE(to_jsonb(p)->'tags','[]'::jsonb)) tag WHERE strpos(lower(tag COLLATE pg_catalog."und-x-icu"),words.keyword)>0))
), best AS (
	SELECT DISTINCT ON (channel_id) channel_id, post_id, relevance, published_at, publication_ordinal
	FROM matched
	WHERE $6::uuid[] IS NULL
	ORDER BY channel_id, relevance DESC, published_at DESC, publication_ordinal DESC
), group_order AS (
	SELECT COALESCE($6::uuid[], array_agg(channel_id ORDER BY relevance DESC, published_at DESC, publication_ordinal DESC)) AS channels,
		array_agg(post_id ORDER BY relevance DESC, published_at DESC, publication_ordinal DESC) AS leaders
	FROM best
), ranked AS (
	SELECT m.*, array_position(g.channels, m.channel_id) AS group_position
	FROM matched m CROSS JOIN group_order g
), page AS (
	SELECT *
	FROM ranked
	WHERE group_position IS NOT NULL AND (
		$7::timestamptz IS NULL OR group_position > $8 OR (
			group_position = $8 AND (relevance, published_at, publication_ordinal) < ($9, $7, $10)
		)
	)
	ORDER BY group_position, relevance DESC, published_at DESC, publication_ordinal DESC
	LIMIT $11
)
SELECT p.post_id, p.published_at, p.publication_ordinal, p.group_position, p.relevance, g.channels, g.leaders
FROM page p CROSS JOIN group_order g
ORDER BY p.group_position, p.relevance DESC, p.published_at DESC, p.publication_ordinal DESC`

// Reuse the exact predicates/order/cursor rules while avoiding repeated whole
// post JSON conversion on schemas whose edit and tag columns have been checked.
// These replacements are fixed SQL expressions, never request values.
var typedSearchExpressions = strings.NewReplacer(
	"jsonb_array_elements_text(COALESCE(to_jsonb(p)->'tags','[]'::jsonb))", "unnest(p.tags)",
	"COALESCE(to_jsonb(p)->'tags','[]'::jsonb)", "COALESCE(to_jsonb(p.tags),'[]'::jsonb)",
	"to_jsonb(p)->>'edited_title'", "p.edited_title",
	"to_jsonb(p)->>'edited_body'", "p.edited_body",
)

var typedSearchCandidatesSQL = typedSearchExpressions.Replace(searchCandidatesSQL)
var typedProjectSearchCandidatesSQL = typedSearchExpressions.Replace(projectSearchCandidatesSQL)

type searchCandidate struct {
	id          string
	publishedAt time.Time
	ordinal     int64
	group, rank int
}

type preparedPostSearch struct {
	position   posts.CursorPosition
	candidates []searchCandidate
	leaders    []string
}

func (c *Community) preparePostSearch(ctx context.Context, account uuid.UUID, query posts.SearchQuery, at time.Time) (preparedPostSearch, error) {
	defer readtiming.Span(ctx, "search_candidates")()
	var prepared preparedPostSearch
	finishBegin := readtiming.Span(ctx, "search_prepare_begin")
	tx, err := begin(ctx, c.pool)
	finishBegin()
	if err != nil {
		return prepared, err
	}
	defer tx.Rollback(ctx)
	if err := requirePostSearchChannel(ctx, tx, query.ChannelID); err != nil {
		return prepared, err
	}
	preferences, revision, err := readFeedPreferences(ctx, tx, account)
	if err != nil {
		return prepared, err
	}
	digest := sha256.Sum256([]byte(query.Sort + "\x00" + query.Keyword))
	position := posts.CursorPosition{
		Scope: posts.CursorSearch, AccountID: account.String(), ChannelID: query.ChannelID,
		Limit: query.Limit, FilterRevision: revision,
		SearchKey: base64.RawURLEncoding.EncodeToString(digest[:]),
	}
	var groups []string
	var lastAt *time.Time
	if query.Cursor != "" {
		position, err = c.posts.cursors.Decode(query.Cursor, position, at)
		if err != nil {
			return prepared, err
		}
		groups = strings.Split(position.SearchGroups, ",")
		lastAt = &position.LastAt
	} else if err := tx.QueryRow(ctx, `SELECT COALESCE(MAX(publication_ordinal),0) FROM c_posts.posts`).Scan(&position.Ceiling); err != nil {
		return prepared, err
	}
	defer readtiming.Span(ctx, "search_candidate_query")()
	candidateSQL := searchCandidatesSQL
	if c.posts.typedSearchEnabled {
		candidateSQL = typedSearchCandidatesSQL
	}
	rows, err := tx.Query(ctx, candidateSQL, query.Sort == posts.SearchRelevance, query.Keyword, position.Ceiling,
		nullablePostID(query.ChannelID), preferences.BlockedChannelIDs, groups, lastAt,
		position.SearchGroup, position.SearchRank, position.LastOrdinal, query.Limit+1)
	if err != nil {
		return prepared, err
	}
	defer rows.Close()
	prepared.candidates = make([]searchCandidate, 0, query.Limit+1)
	for rows.Next() {
		var hit searchCandidate
		if err := rows.Scan(&hit.id, &hit.publishedAt, &hit.ordinal, &hit.group, &hit.rank, &groups, &prepared.leaders); err != nil {
			return prepared, err
		}
		prepared.candidates = append(prepared.candidates, hit)
	}
	if len(prepared.leaders) > 7 {
		return prepared, ErrAuthorizationUnavailable
	}
	position.SearchGroups = strings.Join(groups, ",")
	prepared.position = position
	return prepared, rows.Err()
}

// The input is bounded by the page, one lookahead, and the seven catalog
// groups. LIMIT keeps the lookup correlated to one indexed post ID at a time.
const projectSearchCandidatesSQL = `
SELECT card.*
FROM unnest($1::uuid[]) WITH ORDINALITY AS candidate(post_id, ord)
JOIN LATERAL (
	SELECT p.post_id, p.channel_id, COALESCE(to_jsonb(p)->>'edited_title',x.title), p.published_at, a.state, i.deleted_at, i.nickname, i.avatar, l.short_code,COALESCE(to_jsonb(p)->'tags','[]'::jsonb)
	FROM c_posts.posts p
	JOIN c_posts.publication_tasks t ON t.post_id = p.post_id
	JOIN c_posts.attempt_contents x ON x.task_id = t.task_id AND x.version = p.published_attempt_version
	JOIN public.community_identities i ON i.identity_id = t.identity_id
	JOIN c_auth.accounts a ON a.account_id = p.owner_account_id
	JOIN c_posts.identity_public_labels l ON l.identity_id = i.identity_id
	WHERE p.post_id = candidate.post_id AND p.visibility = 'PUBLISHED' AND NOT p.moderation_hidden AND x.erased_at IS NULL
		AND ($2::uuid IS NULL OR p.channel_id = $2)
        AND NOT (p.channel_id = ANY($3::uuid[]))
        AND (strpos(lower(COALESCE(to_jsonb(p)->>'edited_title',x.title) COLLATE pg_catalog."und-x-icu"),lower($4::text COLLATE pg_catalog."und-x-icu"))>0
          OR strpos(lower(COALESCE(to_jsonb(p)->>'edited_body',x.body) COLLATE pg_catalog."und-x-icu"),lower($4::text COLLATE pg_catalog."und-x-icu"))>0
          OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(COALESCE(to_jsonb(p)->'tags','[]'::jsonb)) tag
             WHERE strpos(lower(tag COLLATE pg_catalog."und-x-icu"),lower($4::text COLLATE pg_catalog."und-x-icu"))>0))
 LIMIT 1
) card ON true
ORDER BY candidate.ord`

func (c *Community) finishPostSearch(ctx context.Context, tx pgx.Tx, account uuid.UUID, query posts.SearchQuery, prepared preparedPostSearch, at time.Time) (posts.FeedPage, error) {
	defer readtiming.Span(ctx, "search_projection")()
	page := posts.FeedPage{Items: make([]posts.PublicPostCard, 0, query.Limit)}
	if err := requirePostSearchChannel(ctx, tx, query.ChannelID); err != nil {
		return page, err
	}
	position := prepared.position
	preferences, revision, err := readFeedPreferences(ctx, tx, account)
	if err != nil {
		return page, err
	}
	if query.Cursor != "" {
		if revision != position.FilterRevision || !at.Before(position.ExpiresAt) || position.ExpiresAt.After(at.Add(posts.CursorTTL)) {
			return page, posts.ErrCursorInvalid
		}
	} else if revision != position.FilterRevision {
		return page, errPostSearchChanged
	} else {
		position.ExpiresAt = at.Add(posts.CursorTTL)
	}

	ids := make([]string, 0, len(prepared.candidates)+len(prepared.leaders))
	for _, hit := range prepared.candidates {
		ids = append(ids, hit.id)
	}
	// Even an undisplayed group's leader can affect first-page ordering.
	for _, leader := range prepared.leaders {
		if !slices.Contains(ids, leader) {
			ids = append(ids, leader)
		}
	}
	if len(ids) == 0 {
		return page, nil
	}
	projectionSQL := projectSearchCandidatesSQL
	if c.posts.typedSearchEnabled {
		projectionSQL = typedProjectSearchCandidatesSQL
	}
	rows, err := tx.Query(ctx, projectionSQL, ids, nullablePostID(query.ChannelID), preferences.BlockedChannelIDs, query.Keyword)
	if err != nil {
		return page, err
	}
	defer rows.Close()
	seen := 0
	for rows.Next() {
		var card posts.PublicPostCard
		var state, short string
		var deleted *time.Time
		var nickname, avatar *string
		if err := rows.Scan(&card.PostID, &card.ChannelID, &card.Title, &card.PublishedAt, &state, &deleted, &nickname, &avatar, &short, &card.Tags); err != nil {
			return page, err
		}
		if seen == len(ids) || card.PostID != ids[seen] {
			return page, errPostSearchChanged
		}
		if seen < min(len(prepared.candidates), query.Limit) {
			card.Author, err = projectPublicPostAuthor(state, deleted, nickname, avatar, short)
			if err != nil {
				return page, err
			}
			card.PublishedAt = card.PublishedAt.UTC()
			page.Items = append(page.Items, card)
		}
		seen++
	}
	if err := rows.Err(); err != nil {
		return page, err
	}
	if seen != len(ids) {
		return page, errPostSearchChanged
	}
	if len(prepared.candidates) > query.Limit {
		// Keep the checked lookahead for the next page and advance only to
		// the last card actually returned.
		last := prepared.candidates[query.Limit-1]
		position.LastAt, position.LastOrdinal = last.publishedAt, last.ordinal
		position.SearchGroup, position.SearchRank = last.group, last.rank
		cursor, err := c.posts.cursors.Encode(position)
		if err != nil {
			return page, err
		}
		page.NextCursor = &cursor
	}
	return page, nil
}
