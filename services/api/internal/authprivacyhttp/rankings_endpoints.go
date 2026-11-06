package authprivacyhttp

import (
	"context"
	"net/http"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

const (
	hotPostsRoute authprivacy.PostReadKind = "hotPosts"
)

type rankingBackend interface {
	ReadRankings(context.Context, [32]byte) (authprivacy.PostResponse, error)
}

type rankingForeground interface {
	BeginRankingForeground() func()
}

func (b *boundary) communityRankings(w http.ResponseWriter, r *http.Request, backend PostBackend, bearer [32]byte, route postRoute) {
	if noBodyOrQuery(r) != nil {
		b.postBad(w, errMalformed)
		return
	}
	rankings, ok := backend.(rankingBackend)
	if !ok {
		b.postFail(w, 503, "RANKINGS_UNAVAILABLE", 0)
		return
	}
	response, err := rankings.ReadRankings(r.Context(), bearer)
	if err != nil {
		b.postFailure(w, err)
		return
	}
	b.writePostResponse(w, response, route, false)
}

func strictRankings(value any, route postRoute) (any, error) {
	seen := map[string]bool{}
	unique := func(id string) bool {
		if _, err := posts.ParseResourceID(id); err != nil || seen[id] {
			return false
		}
		seen[id] = true
		return true
	}
	page, ok := value.(posts.PostRanking)
	if !ok || !validPostTime(page.AsOf) || page.Items == nil || len(page.Items) > posts.PostRankingLimit {
		return nil, errMalformed
	}
	for _, item := range page.Items {
		if _, err := posts.ParseResourceID(item.ChannelID); err != nil {
			return nil, errMalformed
		}
		if !unique(item.PostID) || item.Title == "" || item.ViewCount < 0 {
			return nil, errMalformed
		}
	}
	return page, nil
}
