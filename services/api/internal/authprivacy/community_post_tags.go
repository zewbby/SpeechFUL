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

// Tag pages have their own cursor scope: an ordinary keyword cursor can never
// be reused as an exact-tag cursor. Every page rechecks the current preferences.
func (c *Community) TaggedPosts(ctx context.Context, bearer [32]byte, query posts.TagQuery) (PostResponse, error) {
	tag, err := posts.NormalizeTag(query.Tag)
	if err != nil {
		return PostResponse{}, posts.ErrInvalidIntent
	}
	if query.ChannelID != "" {
		if _, err = posts.ParseResourceID(query.ChannelID); err != nil {
			return PostResponse{}, err
		}
	}
	if query.Limit == 0 {
		query.Limit = 20
	}
	if query.Limit < 1 || query.Limit > 50 {
		return PostResponse{}, posts.ErrInvalidIntent
	}
	if !c.PostsEnabled() || !c.posts.tagsEnabled {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
		if err := requirePostSearchChannel(ctx, tx, query.ChannelID); err != nil {
			return nil, err
		}
		preferences, revision, err := readFeedPreferences(ctx, tx, account)
		if err != nil {
			return nil, err
		}
		key := sha256.Sum256([]byte(strings.ToLower(tag)))
		position := posts.CursorPosition{Scope: posts.CursorTags, AccountID: account.String(), ChannelID: query.ChannelID, Limit: query.Limit, FilterRevision: revision, SearchKey: base64.RawURLEncoding.EncodeToString(key[:])}
		var lastAt any
		var lastOrdinal any
		if query.Cursor != "" {
			position, err = c.posts.cursors.Decode(query.Cursor, position, final.TrustedAt)
			if err != nil {
				return nil, err
			}
			lastAt, lastOrdinal = position.LastAt, position.LastOrdinal
		} else if err = tx.QueryRow(ctx, `SELECT COALESCE(MAX(publication_ordinal),0) FROM c_posts.posts`).Scan(&position.Ceiling); err != nil {
			return nil, err
		}

		// One statement projects the matched public version as well as its
		// labels, so concurrent edits cannot change membership between reads.
		rows, err := tx.Query(ctx, `SELECT p.post_id,p.channel_id,COALESCE(p.edited_title,x.title),p.published_at,p.publication_ordinal,a.state,i.deleted_at,i.nickname,i.avatar,l.short_code,p.tags
         FROM c_posts.posts p JOIN c_posts.publication_tasks t USING(post_id)
         JOIN c_posts.attempt_contents x ON x.task_id=t.task_id AND x.version=p.published_attempt_version
         JOIN public.community_identities i ON i.identity_id=t.identity_id
         JOIN c_auth.accounts a ON a.account_id=p.owner_account_id
         JOIN c_posts.identity_public_labels l ON l.identity_id=i.identity_id
         WHERE p.visibility='PUBLISHED' AND NOT p.moderation_hidden AND x.erased_at IS NULL
         AND p.tag_keys @> ARRAY[$1::text] AND p.publication_ordinal<=$2
         AND ($3::uuid IS NULL OR p.channel_id=$3) AND NOT(p.channel_id=ANY($4::uuid[]))
         AND ($5::timestamptz IS NULL OR (p.published_at,p.publication_ordinal)<($5,$6::bigint))
         ORDER BY p.published_at DESC,p.publication_ordinal DESC LIMIT $7`, strings.ToLower(tag), position.Ceiling, nullablePostID(query.ChannelID), preferences.BlockedChannelIDs, lastAt, lastOrdinal, query.Limit+1)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		page := posts.FeedPage{Items: make([]posts.PublicPostCard, 0, query.Limit)}
		more := false
		for rows.Next() {
			var card posts.PublicPostCard
			var ordinal int64
			var state, short string
			var deleted *time.Time
			var nickname, avatar *string
			if err := rows.Scan(&card.PostID, &card.ChannelID, &card.Title, &card.PublishedAt, &ordinal, &state, &deleted, &nickname, &avatar, &short, &card.Tags); err != nil {
				return nil, err
			}
			if len(page.Items) == query.Limit {
				more = true
				break
			}
			card.Author, err = projectPublicPostAuthor(state, deleted, nickname, avatar, short)
			if err != nil {
				return nil, err
			}
			card.PublishedAt = card.PublishedAt.UTC()
			page.Items = append(page.Items, card)
			position.LastAt, position.LastOrdinal = card.PublishedAt, ordinal
		}
		if err := rows.Err(); err != nil {
			return nil, err
		}
		rows.Close()

		if more {
			position.ExpiresAt = final.TrustedAt.Add(posts.CursorTTL)
			next, err := c.posts.cursors.Encode(position)
			if err != nil {
				return nil, err
			}
			page.NextCursor = &next
		}
		return page, nil
	})
}

func (c *Community) SuggestPostTags(ctx context.Context, bearer [32]byte, prefix string) (PostResponse, error) {
	prefix, err := posts.NormalizeTag(prefix)
	if err != nil {
		return PostResponse{}, posts.ErrInvalidIntent
	}
	if !c.PostsEnabled() || !c.posts.tagsEnabled {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		preferences, _, err := readFeedPreferences(ctx, tx, account)
		if err != nil {
			return nil, err
		}
		escaped := strings.NewReplacer("\\", "\\\\", "%", "\\%", "_", "\\_").Replace(strings.ToLower(prefix))
		rows, err := tx.Query(ctx, `SELECT DISTINCT ON(t.tag_key) t.label FROM c_posts.post_tag_terms t
   JOIN c_posts.posts p USING(post_id) WHERE t.tag_key LIKE $1 ESCAPE '\'
   AND p.visibility='PUBLISHED' AND NOT p.moderation_hidden AND NOT(p.channel_id=ANY($2::uuid[]))
   ORDER BY t.tag_key,t.label COLLATE "C" LIMIT 10`, escaped+"%", preferences.BlockedChannelIDs)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		result := posts.TagSuggestions{Items: []string{}}
		for rows.Next() {
			var tag string
			if err := rows.Scan(&tag); err != nil {
				return nil, err
			}
			result.Items = append(result.Items, tag)
		}
		return result, rows.Err()
	})
}
