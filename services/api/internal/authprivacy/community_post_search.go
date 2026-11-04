package authprivacy

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

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
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
		page, err := c.listSearchPosts(ctx, tx, account, query, final.TrustedAt)
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
}

// The first page fixes the channel order by each group's top hit. On continuation
// use that order even if a top hit disappears, while rechecking row visibility.
const searchPostsSQL = `
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
		SELECT lower(x.title COLLATE pg_catalog."und-x-icu") AS title,
			lower(x.body COLLATE pg_catalog."und-x-icu") AS body,
			lower($2::text COLLATE pg_catalog."und-x-icu") AS keyword
	) words
	WHERE p.visibility = 'PUBLISHED' AND NOT p.moderation_hidden AND x.erased_at IS NULL
		AND p.publication_ordinal <= $3
		AND ($4::uuid IS NULL OR p.channel_id = $4)
		AND NOT (p.channel_id = ANY($5::uuid[]))
		AND (strpos(words.title, words.keyword) > 0 OR strpos(words.body, words.keyword) > 0)
), group_order AS (
	SELECT COALESCE($6::uuid[], ARRAY(
		SELECT channel_id FROM (
			SELECT DISTINCT ON (channel_id) channel_id, relevance, published_at, publication_ordinal
			FROM matched
			ORDER BY channel_id, relevance DESC, published_at DESC, publication_ordinal DESC
		) best
		ORDER BY relevance DESC, published_at DESC, publication_ordinal DESC
	)) AS channels
), ranked AS (
	SELECT m.*, g.channels, array_position(g.channels, m.channel_id) AS group_position
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
SELECT p.post_id, p.channel_id, x.title, p.published_at, p.publication_ordinal,
	p.group_position, p.relevance, p.channels, a.state, i.deleted_at, i.nickname, i.avatar, l.short_code
FROM page p
JOIN c_posts.posts post ON post.post_id = p.post_id
JOIN c_posts.publication_tasks t ON t.post_id = p.post_id
JOIN c_posts.attempt_contents x ON x.task_id = t.task_id AND x.version = post.published_attempt_version
JOIN public.community_identities i ON i.identity_id = t.identity_id
JOIN c_auth.accounts a ON a.account_id = post.owner_account_id
JOIN c_posts.identity_public_labels l ON l.identity_id = i.identity_id
ORDER BY p.group_position, p.relevance DESC, p.published_at DESC, p.publication_ordinal DESC`

func (c *Community) listSearchPosts(ctx context.Context, tx pgx.Tx, account uuid.UUID, query posts.SearchQuery, at time.Time) (posts.FeedPage, error) {
	page := posts.FeedPage{Items: make([]posts.PublicPostCard, 0, query.Limit)}
	var channel any
	if query.ChannelID != "" {
		channel = query.ChannelID
		var exists bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.channels WHERE id=$1)`, channel).Scan(&exists); err != nil {
			return page, err
		}
		if !exists {
			return page, postError("POST_CHANNEL_UNAVAILABLE", 404)
		}
	}
	preferences, revision, err := readFeedPreferences(ctx, tx, account)
	if err != nil {
		return page, err
	}
	digest := sha256.Sum256([]byte(query.Sort + "\x00" + query.Keyword))
	position := posts.CursorPosition{
		Scope: posts.CursorSearch, AccountID: account.String(), ChannelID: query.ChannelID,
		Limit: query.Limit, ExpiresAt: at.Add(posts.CursorTTL), FilterRevision: revision,
		SearchKey: base64.RawURLEncoding.EncodeToString(digest[:]),
	}
	var groups []string
	var lastAt *time.Time
	if query.Cursor != "" {
		position, err = c.posts.cursors.Decode(query.Cursor, position, at)
		if err != nil {
			return page, err
		}
		groups = strings.Split(position.SearchGroups, ",")
		lastAt = &position.LastAt
	} else if err := tx.QueryRow(ctx, `SELECT COALESCE(MAX(publication_ordinal),0) FROM c_posts.posts`).Scan(&position.Ceiling); err != nil {
		return page, err
	}
	rows, err := tx.Query(ctx, searchPostsSQL, query.Sort == posts.SearchRelevance, query.Keyword, position.Ceiling,
		channel, preferences.BlockedChannelIDs, groups, lastAt, position.SearchGroup, position.SearchRank, position.LastOrdinal, query.Limit+1)
	if err != nil {
		return page, err
	}
	defer rows.Close()
	for rows.Next() {
		if len(page.Items) == query.Limit {
			cursor, err := c.posts.cursors.Encode(position)
			if err != nil {
				return page, err
			}
			page.NextCursor = &cursor
			break
		}
		var card posts.PublicPostCard
		var state, short string
		var deleted *time.Time
		var nickname, avatar *string
		if err := rows.Scan(&card.PostID, &card.ChannelID, &card.Title, &card.PublishedAt, &position.LastOrdinal,
			&position.SearchGroup, &position.SearchRank, &groups, &state, &deleted, &nickname, &avatar, &short); err != nil {
			return page, err
		}
		card.Author, err = projectPublicPostAuthor(state, deleted, nickname, avatar, short)
		if err != nil {
			return page, err
		}
		card.PublishedAt = card.PublishedAt.UTC()
		position.LastAt = card.PublishedAt
		position.SearchGroups = strings.Join(groups, ",")
		page.Items = append(page.Items, card)
	}
	return page, rows.Err()
}
