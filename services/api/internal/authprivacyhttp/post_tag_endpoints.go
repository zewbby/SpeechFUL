package authprivacyhttp

import (
	"context"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"net/http"
	"strings"
)

const postTagPath = "/api/v1/post-tags/posts"
const postTagSuggestionsPath = "/api/v1/post-tags/suggestions"
const postTagRoute authprivacy.PostReadKind = "postTag"
const postTagSuggestionsRoute authprivacy.PostReadKind = "postTagSuggestions"

type postTagBackend interface {
	TaggedPosts(context.Context, [32]byte, posts.TagQuery) (authprivacy.PostResponse, error)
	SuggestPostTags(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
}

func parsePostTags(object map[string]any) ([]string, error) {
	value, present := object["tags"]
	if !present {
		return nil, nil
	}
	raw, ok := value.([]any)
	if !ok || len(raw) > posts.MaxTags {
		return nil, errMalformed
	}
	tags := make([]string, 0, len(raw))
	for _, v := range raw {
		tag, ok := v.(string)
		if !ok {
			return nil, errMalformed
		}
		tags = append(tags, tag)
	}
	if !posts.ValidTags(tags) {
		return nil, errMalformed
	}
	return tags, nil
}

func (b *boundary) communityPostTags(w http.ResponseWriter, r *http.Request, backend PostBackend, bearer [32]byte, route postRoute) {
	tags, ok := backend.(postTagBackend)
	if !ok {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	var response authprivacy.PostResponse
	var err error
	if route.kind == postTagSuggestionsRoute {
		object, parseErr := readRequestObject(r, 1024, []string{"prefix"}, nil)
		if parseErr != nil {
			b.postBad(w, parseErr)
			return
		}
		prefix, parseErr := stringField(object, "prefix")
		if parseErr == nil {
			prefix, parseErr = posts.NormalizeTag(prefix)
		}
		if parseErr != nil {
			b.postBad(w, errMalformed)
			return
		}
		response, err = tags.SuggestPostTags(r.Context(), bearer, prefix)
	} else {
		object, parseErr := readRequestObject(r, 4096, []string{"tag"}, []string{"channelId", "cursor", "limit"})
		if parseErr != nil {
			b.postBad(w, parseErr)
			return
		}
		query := posts.TagQuery{Limit: 20}
		query.Tag, parseErr = stringField(object, "tag")
		if parseErr == nil {
			query.Tag, parseErr = posts.NormalizeTag(query.Tag)
		}
		if parseErr != nil {
			b.postBad(w, errMalformed)
			return
		}
		query.ChannelID, parseErr = postSearchChannelField(object)
		if parseErr != nil {
			b.postBad(w, parseErr)
			return
		}
		if _, present := object["limit"]; present {
			query.Limit, parseErr = integerField(object, "limit", 1, 50)
			if parseErr != nil {
				b.postBad(w, parseErr)
				return
			}
		}
		if _, present := object["cursor"]; present {
			query.Cursor, parseErr = stringField(object, "cursor")
			if parseErr != nil || !validPostCursor(query.Cursor) {
				b.postBad(w, posts.ErrCursorInvalid)
				return
			}
		}
		route.id, route.limit = query.ChannelID, query.Limit
		response, err = tags.TaggedPosts(r.Context(), bearer, query)
	}
	if err != nil {
		b.postFailure(w, err)
		return
	}
	b.writePostResponse(w, response, route, false)
}

func strictTagSuggestions(value any) (posts.TagSuggestions, error) {
	result, ok := value.(posts.TagSuggestions)
	if !ok || result.Items == nil || len(result.Items) > 10 {
		return posts.TagSuggestions{}, errMalformed
	}
	seen := map[string]bool{}
	for _, tag := range result.Items {
		if normalized, err := posts.NormalizeTag(tag); err != nil || normalized != tag || seen[strings.ToLower(tag)] {
			return posts.TagSuggestions{}, errMalformed
		}
		seen[strings.ToLower(tag)] = true
	}
	return result, nil
}
