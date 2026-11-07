package authprivacy

import (
	"context"
	"errors"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// No post snapshot enters a message, local chat archive or receipt.
type DMPostCard struct {
	PostID      string `json:"postId"`
	Title       string `json:"title"`
	ChannelID   string `json:"channelId"`
	ChannelName string `json:"channelName"`
}

func (c *Community) ReadDMPostCard(ctx context.Context, bearer [32]byte, id string) (PostResponse, error) {
	if !dmUUID(id) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	return c.withDMSession(ctx, bearer, func(tx pgx.Tx, _ uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		post, _, err := readPublicPost(ctx, tx, id)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, postError("POST_NOT_FOUND", 404)
		}
		if err != nil {
			return nil, err
		}
		var name string
		if err = tx.QueryRow(ctx, `SELECT name FROM public.channels WHERE id=$1`, post.ChannelID).Scan(&name); err != nil {
			return nil, err
		}
		return DMPostCard{PostID: post.PostID, Title: post.Title, ChannelID: post.ChannelID, ChannelName: name}, nil
	})
}
