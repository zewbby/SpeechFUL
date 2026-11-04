package authprivacy

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func (c *Community) ReadPostSearchHistory(ctx context.Context, bearer [32]byte, channelID string) (PostResponse, error) {
	if channelID != "" {
		if _, err := posts.ParseResourceID(channelID); err != nil {
			return PostResponse{}, err
		}
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		if err := requirePostSearchChannel(ctx, tx, channelID); err != nil {
			return nil, err
		}
		return readPostSearchHistory(ctx, tx, account, channelID)
	})
}

func (c *Community) ChangePostSearchHistory(ctx context.Context, bearer [32]byte, input posts.SearchHistoryChange) (PostResponse, error) {
	if input.ChannelID != "" {
		if _, err := posts.ParseResourceID(input.ChannelID); err != nil {
			return PostResponse{}, err
		}
	}
	var key string
	switch input.Action {
	case "remove":
		keyword, err := posts.NormalizeSearchKeyword(input.Keyword)
		if err != nil {
			return PostResponse{}, err
		}
		key = strings.ToLower(keyword)
	case "clear":
		if input.Keyword != "" {
			return PostResponse{}, posts.ErrInvalidIntent
		}
	default:
		return PostResponse{}, posts.ErrInvalidIntent
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		if err := requirePostSearchChannel(ctx, tx, input.ChannelID); err != nil {
			return nil, err
		}
		if _, err := tx.Exec(ctx, `DELETE FROM c_posts.post_search_history
 WHERE account_id=$1 AND channel_id IS NOT DISTINCT FROM NULLIF($2::text,'')::uuid AND ($3::text='' OR keyword_key=$3)`, account, input.ChannelID, key); err != nil {
			return nil, err
		}
		return readPostSearchHistory(ctx, tx, account, input.ChannelID)
	})
}

func requirePostSearchChannel(ctx context.Context, tx pgx.Tx, channelID string) error {
	if channelID == "" {
		return nil
	}
	var exists bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.channels WHERE id=$1)`, channelID).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return postError("POST_CHANNEL_UNAVAILABLE", 404)
	}
	return nil
}

func readPostSearchHistory(ctx context.Context, tx pgx.Tx, account uuid.UUID, channelID string) (posts.SearchHistory, error) {
	history := posts.SearchHistory{Items: make([]string, 0)}
	rows, err := tx.Query(ctx, `SELECT keyword FROM c_posts.post_search_history
 WHERE account_id=$1 AND channel_id IS NOT DISTINCT FROM NULLIF($2::text,'')::uuid
 ORDER BY sort_at DESC LIMIT $3`, account, channelID, posts.SearchHistoryLimit)
	if err != nil {
		return history, err
	}
	defer rows.Close()
	for rows.Next() {
		var keyword string
		if err = rows.Scan(&keyword); err != nil {
			return history, err
		}
		history.Items = append(history.Items, keyword)
	}
	return history, rows.Err()
}

// recordPostSearchHistory runs while withPostSession holds the account row lock.
// A logical microsecond step preserves submission order when the trusted clock ties.
func recordPostSearchHistory(ctx context.Context, tx pgx.Tx, account uuid.UUID, channelID, keyword string, at time.Time) error {
	keyword, err := posts.NormalizeSearchKeyword(keyword)
	if err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO c_posts.post_search_history(account_id,channel_id,keyword,keyword_key,sort_at)
 SELECT $1,NULLIF($2::text,'')::uuid,$3,$4,GREATEST($5::timestamptz,max(sort_at)+interval '1 microsecond')
 FROM c_posts.post_search_history WHERE account_id=$1 AND channel_id IS NOT DISTINCT FROM NULLIF($2::text,'')::uuid
 ON CONFLICT ON CONSTRAINT post_search_history_keyword
 DO UPDATE SET keyword=EXCLUDED.keyword,sort_at=EXCLUDED.sort_at`, account, channelID, keyword, strings.ToLower(keyword), at); err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `DELETE FROM c_posts.post_search_history
 WHERE account_id=$1 AND channel_id IS NOT DISTINCT FROM NULLIF($2::text,'')::uuid AND sort_at < (
  SELECT sort_at FROM c_posts.post_search_history
  WHERE account_id=$1 AND channel_id IS NOT DISTINCT FROM NULLIF($2::text,'')::uuid ORDER BY sort_at DESC LIMIT 1 OFFSET $3)`,
		account, channelID, posts.SearchHistoryLimit-1)
	return err
}
