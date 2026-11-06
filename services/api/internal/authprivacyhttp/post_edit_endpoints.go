package authprivacyhttp

import (
	"context"
	"net/http"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type PostEditBackend interface {
	ReadPostEdit(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	PostEditResult(context.Context, [32]byte, string, string) (authprivacy.PostResponse, error)
	SavePostEdit(context.Context, [32]byte, string, string, posts.EditInput) (authprivacy.PostResponse, error)
	StagePostEditImage(context.Context, [32]byte, string, string, string, string, []byte) (authprivacy.PostResponse, error)
}

func parsePostEditRoute(parts []string) (postRoute, error) {
	if !postValidID(parts[2]) {
		return postRoute{}, errMalformed
	}
	if len(parts) == 4 && parts[3] == "edit" {
		return postRoute{id: parts[2], edit: "snapshot", methods: "GET"}, nil
	}
	if len(parts) >= 5 && parts[3] == "edit-commands" {
		if _, err := posts.ParseCommandKey(parts[4]); err == nil {
			if len(parts) == 5 {
				return postRoute{id: parts[2], edit: "command", editCommand: parts[4], methods: "GET, PUT"}, nil
			}
			if len(parts) == 7 && parts[5] == "images" && postValidID(parts[6]) {
				return postRoute{id: parts[2], edit: "image", editCommand: parts[4], editImage: parts[6], methods: "PUT"}, nil
			}
		}
	}
	return postRoute{}, errMalformed
}

func (b *boundary) communityPostEdit(w http.ResponseWriter, r *http.Request, backend PostEditBackend, bearer [32]byte, route postRoute) {
	if hasHeader(r.Header, "Idempotency-Key") || hasHeader(r.Header, "X-Post-Edit") || (r.Method == http.MethodGet && noBodyOrQuery(r) != nil) {
		b.postBad(w, errMalformed)
		return
	}
	if backend == nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	var response authprivacy.PostResponse
	var err error
	switch {
	case route.edit == "snapshot":
		response, err = backend.ReadPostEdit(r.Context(), bearer, route.id)
	case route.edit == "image":
		b.stagePostEditImage(w, r, backend, bearer, route)
		return
	case r.Method == http.MethodGet:
		response, err = backend.PostEditResult(r.Context(), bearer, route.id, route.editCommand)
	default:
		object, decodeErr := readRequestObject(r, posts.MaxRequestBytes, []string{"revision", "title", "body"}, []string{"imageIds", "tags"})
		if decodeErr != nil {
			b.postBad(w, decodeErr)
			return
		}
		revision, e1 := stringField(object, "revision")
		title, e2 := stringField(object, "title")
		body, e3 := stringField(object, "body")
		if e1 != nil || e2 != nil || e3 != nil || !postValidID(revision) {
			b.postBad(w, errMalformed)
			return
		}
		input := posts.EditInput{Revision: revision, Title: title, Body: body}
		if _, present := object["tags"]; present {
			tags, err := parsePostTags(object)
			if err != nil {
				b.postBad(w, err)
				return
			}
			input.Tags = &tags
		}
		if value, exists := object["imageIds"]; exists {
			raw, ok := value.([]any)
			if !ok || len(raw) > postmedia.MaxImages {
				b.postBad(w, errMalformed)
				return
			}
			ids := make([]string, 0, len(raw))
			seen := make(map[string]bool, len(raw))
			for _, value := range raw {
				id, ok := value.(string)
				if !ok || !postValidID(id) || seen[id] {
					b.postBad(w, errMalformed)
					return
				}
				ids = append(ids, id)
				seen[id] = true
			}
			input.ImageIDs = &ids
		}
		response, err = backend.SavePostEdit(r.Context(), bearer, route.id, route.editCommand, input)
	}
	if err != nil {
		b.postFailure(w, err)
		return
	}
	b.writePostResponse(w, response, route, false)
}

func (b *boundary) stagePostEditImage(w http.ResponseWriter, r *http.Request, backend PostEditBackend, bearer [32]byte, route postRoute) {
	mime, err := singleHeader(r.Header, "Content-Type")
	if err != nil || mime != "image/jpeg" && mime != "image/png" && mime != "image/webp" && mime != "image/gif" {
		b.postBad(w, errMediaType)
		return
	}
	if r.ContentLength > postmedia.MaxBytes {
		b.postBad(w, errTooLarge)
		return
	}
	subject := ""
	if b.shared != nil {
		if b.shared.Resolver == nil {
			b.postFail(w, 503, "SHARED_RATE_UNAVAILABLE", 0)
			return
		}
		subject, err = b.shared.Resolver.ResolveSharedSubject(r.Context(), bearer)
		if err != nil {
			b.postFailure(w, err)
			return
		}
	}
	data, ok := b.readSharedBody(w, r, subject, postmedia.MaxBytes)
	if !ok {
		return
	}
	if len(data) > postmedia.MaxBytes {
		b.postBad(w, errTooLarge)
		return
	}
	response, err := backend.StagePostEditImage(r.Context(), bearer, route.id, route.editCommand, route.editImage, mime, data)
	if err != nil {
		b.imageFailure(w, err)
		return
	}
	b.writePostResponse(w, response, route, false)
}

func strictPostEditValue(value any, route postRoute) (any, error) {
	if route.edit == "image" {
		if _, ok := value.(struct{}); !ok {
			return nil, errMalformed
		}
		return value, nil
	}
	if route.edit == "snapshot" {
		snapshot, ok := value.(posts.EditSnapshot)
		if !ok || !postValidID(snapshot.Revision) {
			return nil, errMalformed
		}
		_, err := strictPostValue(posts.PublicPostResponse{Post: snapshot.Post}, postRoute{kind: authprivacy.PostDetail, id: route.id})
		if snapshot.ImageIDs != nil {
			if len(*snapshot.ImageIDs) != snapshot.Post.ImageCount || *snapshot.ImageIDs == nil {
				return nil, errMalformed
			}
			for _, id := range *snapshot.ImageIDs {
				if !postValidID(id) {
					return nil, errMalformed
				}
			}
		}
		return snapshot, err
	}
	result, ok := value.(posts.EditResult)
	if !ok {
		return nil, errMalformed
	}
	switch result.State {
	case "SAVED":
		if postValidID(result.Revision) && result.Code == "" {
			return result, nil
		}
	case "PENDING":
		if result.Revision == "" && result.Code == "" {
			return result, nil
		}
	case "REJECTED":
		if result.Revision == "" {
			switch result.Code {
			case "POST_EDIT_DELETED", "POST_EDIT_HIDDEN", "POST_EDIT_CONFLICT", "POST_IDENTITY_UNAVAILABLE", "POSTING_RESTRICTED", "POST_CONTENT_INVALID", "POST_EDIT_MEDIA_MISSING":
				return result, nil
			}
		}
	}
	return nil, errMalformed
}
