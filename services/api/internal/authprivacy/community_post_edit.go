package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type postEditSubject struct {
	revision string
	blocked  string
}

// The author account is already locked by withPostSession. This row lock
// orders the edit with report capture and resource visibility changes.
func readPostEditSubject(ctx context.Context, tx pgx.Tx, account uuid.UUID, post string, mute restriction, at time.Time) (postEditSubject, error) {
	var subject postEditSubject
	var visibility string
	var hidden, identityAvailable bool
	err := tx.QueryRow(ctx, `SELECT COALESCE(p.edit_revision,p.post_id),p.visibility,p.moderation_hidden,
 i.account_id=p.owner_account_id AND i.deleted_at IS NULL
 FROM c_posts.posts p JOIN c_posts.publication_tasks t USING(post_id)
 JOIN public.community_identities i ON i.identity_id=t.identity_id
 WHERE p.post_id=$1 AND p.owner_account_id=$2 AND p.visibility IN ('PUBLISHED','DELETED')
 FOR UPDATE OF p`, post, account).Scan(&subject.revision, &visibility, &hidden, &identityAvailable)
	if errors.Is(err, pgx.ErrNoRows) {
		return subject, postError("POST_NOT_FOUND", 404)
	}
	if err != nil {
		return subject, err
	}
	switch {
	case visibility == "DELETED":
		subject.blocked = "POST_EDIT_DELETED"
	case hidden:
		subject.blocked = "POST_EDIT_HIDDEN"
	case !identityAvailable:
		subject.blocked = "POST_IDENTITY_UNAVAILABLE"
	case mutedAt(mute, at):
		subject.blocked = "POSTING_RESTRICTED"
	}
	return subject, nil
}

func (c *Community) ReadPostEdit(ctx context.Context, bearer [32]byte, post string) (PostResponse, error) {
	if _, err := posts.ParseResourceID(post); err != nil {
		return PostResponse{}, err
	}
	if !c.PostsEnabled() || !c.posts.editEnabled {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, mute restriction) (any, error) {
		subject, err := readPostEditSubject(ctx, tx, account, post, mute, final.TrustedAt)
		if err != nil {
			return nil, err
		}
		if subject.blocked != "" {
			return nil, postError(subject.blocked, 409)
		}
		current, _, err := readPublicPost(ctx, tx, post)
		snapshot := posts.EditSnapshot{Post: current, Revision: subject.revision}
		if err == nil && c.PostImagesEnabled() {
			images, err := readPostImageItems(ctx, tx, post, current.ImagesEdited, current.ImageCount)
			ids := make([]string, 0, len(images))
			for _, image := range images {
				ids = append(ids, image.ContentVersionID)
			}
			snapshot.ImageIDs = &ids
			return snapshot, err
		}
		return snapshot, err
	})
}

func readPostEditReceipt(ctx context.Context, tx pgx.Tx, post string, key [32]byte) (posts.EditResult, []byte, error) {
	var result posts.EditResult
	var fingerprint []byte
	err := tx.QueryRow(ctx, `SELECT fingerprint,COALESCE(result_revision::text,''),COALESCE(rejection,'')
 FROM c_posts.post_edit_receipts WHERE post_id=$1 AND command_digest=$2`, post, key[:]).Scan(&fingerprint, &result.Revision, &result.Code)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return posts.EditResult{State: "PENDING"}, nil, nil
	case err != nil:
		return result, nil, err
	case result.Code != "":
		result.State = "REJECTED"
	default:
		result.State = "SAVED"
	}
	return result, fingerprint, nil
}

func (c *Community) PostEditResult(ctx context.Context, bearer [32]byte, post, command string) (PostResponse, error) {
	if !c.PostsEnabled() || !c.posts.editEnabled {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	if _, err := posts.ParseResourceID(post); err != nil {
		return PostResponse{}, err
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, mute restriction) (any, error) {
		key, err := c.posts.commands.KeyDigest(account.String(), command)
		if err != nil {
			return nil, err
		}
		subject, err := readPostEditSubject(ctx, tx, account, post, mute, final.TrustedAt)
		if err != nil {
			return nil, err
		}
		result, _, err := readPostEditReceipt(ctx, tx, post, key)
		if err == nil && result.State == "PENDING" && (subject.blocked == "POST_EDIT_DELETED" || subject.blocked == "POST_EDIT_HIDDEN") {
			return nil, postError(subject.blocked, 409)
		}
		return result, err
	})
}

func (c *Community) SavePostEdit(ctx context.Context, bearer [32]byte, post, command string, input posts.EditInput) (PostResponse, error) {
	if !c.PostsEnabled() || !c.posts.editEnabled {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	if _, err := posts.ParseResourceID(post); err != nil {
		return PostResponse{}, err
	}
	if _, err := posts.ParseResourceID(input.Revision); err != nil {
		return PostResponse{}, err
	}
	if !validPostEditImageIDs(input.ImageIDs) {
		return PostResponse{}, posts.ErrInvalidIntent
	}
	if input.ImageIDs != nil && !c.PostImagesEnabled() {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	if input.Tags != nil && (!posts.ValidTags(*input.Tags) || !c.posts.tagsEnabled) {
		return PostResponse{}, posts.ErrContentInvalid
	}
	frame, err := json.Marshal(input)
	if err != nil {
		return PostResponse{}, err
	}
	fp := c.posts.commands.IntentFingerprint(sha256.Sum256(append([]byte("HNUHOLE/POST-EDIT/V1\x00"), frame...)))
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, mute restriction) (any, error) {
		key, err := c.posts.commands.KeyDigest(account.String(), command)
		if err != nil {
			return nil, err
		}
		subject, err := readPostEditSubject(ctx, tx, account, post, mute, final.TrustedAt)
		if err != nil {
			return nil, err
		}
		result, stored, err := readPostEditReceipt(ctx, tx, post, key)
		if err != nil {
			return nil, err
		}
		if stored != nil {
			if !hmac.Equal(fp[:], stored) {
				return nil, postError("COMMAND_CONFLICT", 409)
			}
			return result, nil
		}

		code := subject.blocked
		if code == "" && input.Revision != subject.revision {
			code = "POST_EDIT_CONFLICT"
		}
		if code == "" {
			current, _, err := readPublicPost(ctx, tx, post)
			if err != nil {
				return nil, err
			}
			imageCount, imageCode, err := preparePostEditImages(ctx, tx, post, key, current, input.ImageIDs, final.TrustedAt)
			if err != nil {
				return nil, err
			}
			code = imageCode
			if code == "" && posts.ValidateContentWithImages(input.Title, input.Body, imageCount) != nil {
				code = "POST_CONTENT_INVALID"
			}
		}
		result = posts.EditResult{State: "REJECTED", Code: code}
		if code == "" {
			result = posts.EditResult{State: "SAVED", Revision: uuid.NewString()}
			if input.Tags != nil {
				if _, err = tx.Exec(ctx, `UPDATE c_posts.posts SET tags=$2 WHERE post_id=$1`, post, *input.Tags); err != nil {
					return nil, err
				}
			}
			var imageIDs []string
			if input.ImageIDs != nil {
				imageIDs = *input.ImageIDs
			}
			if _, err = tx.Exec(ctx, `UPDATE c_posts.posts SET edit_revision=$2,edited_at=$3,edited_title=$4,edited_body=$5,
 edited_image_ids=COALESCE($6::uuid[],edited_image_ids) WHERE post_id=$1`,
				post, result.Revision, final.TrustedAt, input.Title, input.Body, imageIDs); err != nil {
				return nil, err
			}
		}
		var selected *[]string
		if result.State == "SAVED" {
			selected = input.ImageIDs
		}
		if err := finishPostEditImages(ctx, tx, post, key, selected); err != nil {
			return nil, err
		}
		_, err = tx.Exec(ctx, `INSERT INTO c_posts.post_edit_receipts(post_id,command_digest,fingerprint,result_revision,rejection)
 VALUES ($1,$2,$3,$4,NULLIF($5,''))`, post, key[:], fp[:], nullablePostID(result.Revision), result.Code)
		return result, err
	})
}
