package authprivacyhttp

import (
	"context"
	"io"
	"net/http"
	"strings"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

const (
	postSearchPath        = "/api/v1/post-search"
	postSearchHistoryPath = "/api/v1/me/post-search-history"

	postSearchRoute        authprivacy.PostReadKind = "postSearch"
	postSearchHistoryRoute authprivacy.PostReadKind = "postSearchHistory"
)

type postSearchBackend interface {
	SearchPosts(context.Context, [32]byte, posts.SearchQuery) (authprivacy.PostResponse, error)
	ReadPostSearchHistory(context.Context, [32]byte, string) (authprivacy.PostResponse, error)
	ChangePostSearchHistory(context.Context, [32]byte, posts.SearchHistoryChange) (authprivacy.PostResponse, error)
}

func isPostSearchKind(kind authprivacy.PostReadKind) bool {
	return kind == postSearchRoute || kind == postSearchHistoryRoute
}

func (b *boundary) communityPostSearch(w http.ResponseWriter, r *http.Request, backend PostBackend, bearer [32]byte, route postRoute) {
	search, ok := backend.(postSearchBackend)
	if !ok {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	var response authprivacy.PostResponse
	var err error
	switch {
	case route.kind == postSearchRoute:
		var query posts.SearchQuery
		query, err = readPostSearch(r)
		if err != nil {
			b.postBad(w, err)
			return
		}
		route.id, route.limit = query.ChannelID, query.Limit
		response, err = search.SearchPosts(r.Context(), bearer, query)
	case r.Method == http.MethodGet:
		var channelID string
		channelID, err = readPostSearchHistoryScope(r)
		if err != nil {
			b.postBad(w, err)
			return
		}
		response, err = search.ReadPostSearchHistory(r.Context(), bearer, channelID)
	default:
		var input posts.SearchHistoryChange
		input, err = readPostSearchHistoryChange(r)
		if err != nil {
			b.postBad(w, err)
			return
		}
		response, err = search.ChangePostSearchHistory(r.Context(), bearer, input)
	}
	if err != nil {
		b.postFailure(w, err)
		return
	}
	b.writePostResponse(w, response, route, false)
}

func readPostSearch(r *http.Request) (posts.SearchQuery, error) {
	query := posts.SearchQuery{Limit: 20, Sort: posts.SearchRelevance}
	object, err := readRequestObject(r, 4096, []string{"keyword"}, []string{"channelId", "sort", "cursor", "limit", "recordHistory"})
	if err != nil {
		return query, err
	}
	keyword, err := stringField(object, "keyword")
	if err != nil {
		return query, err
	}
	query.Keyword, err = posts.NormalizeSearchKeyword(keyword)
	if err != nil {
		return query, errMalformed
	}
	query.ChannelID, err = postSearchChannelField(object)
	if err != nil {
		return query, err
	}
	if _, present := object["sort"]; present {
		query.Sort, err = stringField(object, "sort")
		if err != nil || query.Sort != posts.SearchRelevance && query.Sort != posts.SearchLatest {
			return query, errMalformed
		}
	}
	if _, present := object["cursor"]; present {
		query.Cursor, err = stringField(object, "cursor")
		if err != nil || !validPostCursor(query.Cursor) {
			return query, posts.ErrCursorInvalid
		}
	}
	if _, present := object["limit"]; present {
		query.Limit, err = integerField(object, "limit", 1, 50)
		if err != nil {
			return query, err
		}
	}
	if raw, present := object["recordHistory"]; present {
		var valid bool
		query.RecordHistory, valid = raw.(bool)
		if !valid || query.RecordHistory && query.Cursor != "" {
			return query, errMalformed
		}
	}
	return query, nil
}

func postSearchChannelField(object map[string]any) (string, error) {
	if _, present := object["channelId"]; !present {
		return "", nil
	}
	id, err := stringField(object, "channelId")
	if err != nil || !postValidID(id) {
		return "", errMalformed
	}
	return id, nil
}

func readPostSearchHistoryScope(r *http.Request) (string, error) {
	if r.Body != nil {
		body, err := io.ReadAll(io.LimitReader(r.Body, 1))
		if err != nil || len(body) != 0 {
			return "", errMalformed
		}
	}
	if r.URL.ForceQuery {
		return "", errMalformed
	}
	if r.URL.RawQuery == "" {
		return "", nil
	}
	id, ok := strings.CutPrefix(r.URL.RawQuery, "channelId=")
	if !ok || !postValidID(id) {
		return "", errMalformed
	}
	return id, nil
}

func readPostSearchHistoryChange(r *http.Request) (posts.SearchHistoryChange, error) {
	var input posts.SearchHistoryChange
	object, err := readRequestObject(r, 2048, []string{"action"}, []string{"channelId", "keyword"})
	if err != nil {
		return input, err
	}
	input.Action, err = stringField(object, "action")
	if err != nil || input.Action != "remove" && input.Action != "clear" {
		return input, errMalformed
	}
	input.ChannelID, err = postSearchChannelField(object)
	if err != nil {
		return input, err
	}
	if input.Action == "clear" {
		if _, present := object["keyword"]; present {
			return input, errMalformed
		}
		return input, nil
	}
	keyword, err := stringField(object, "keyword")
	if err != nil {
		return input, err
	}
	input.Keyword, err = posts.NormalizeSearchKeyword(keyword)
	if err != nil {
		return input, errMalformed
	}
	return input, nil
}

func strictPostSearchHistory(value any) (posts.SearchHistory, error) {
	history, ok := value.(posts.SearchHistory)
	if !ok || history.Items == nil || len(history.Items) > posts.SearchHistoryLimit {
		return posts.SearchHistory{}, errMalformed
	}
	seen := make(map[string]bool, len(history.Items))
	for _, item := range history.Items {
		keyword, err := posts.NormalizeSearchKeyword(item)
		key := strings.ToLower(keyword)
		if err != nil || keyword != item || seen[key] {
			return posts.SearchHistory{}, errMalformed
		}
		seen[key] = true
	}
	return history, nil
}
