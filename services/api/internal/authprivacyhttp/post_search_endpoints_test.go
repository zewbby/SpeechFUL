package authprivacyhttp

import (
	"context"
	"net/http"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type searchHTTPBackend struct {
	postHTTPBackend
	search posts.SearchQuery
	scope  string
	change posts.SearchHistoryChange
}

func (f *searchHTTPBackend) SearchPosts(_ context.Context, bearer [32]byte, query posts.SearchQuery) (authprivacy.PostResponse, error) {
	f.calls++
	f.bearer, f.search = bearer, query
	return f.response(posts.FeedPage{Items: []posts.PublicPostCard{postHTTPCard()}})
}

func (f *searchHTTPBackend) ReadPostSearchHistory(_ context.Context, bearer [32]byte, channelID string) (authprivacy.PostResponse, error) {
	f.calls++
	f.bearer, f.scope = bearer, channelID
	return f.response(posts.SearchHistory{Items: []string{"自习"}})
}

func (f *searchHTTPBackend) ChangePostSearchHistory(_ context.Context, bearer [32]byte, input posts.SearchHistoryChange) (authprivacy.PostResponse, error) {
	f.calls++
	f.bearer, f.change = bearer, input
	return f.response(posts.SearchHistory{Items: []string{}})
}

func TestPostSearchHTTPContract(t *testing.T) {
	pki := newHTTPTestPKI(t)
	community := &httpTestCommunity{}
	backend := &searchHTTPBackend{}
	endpoints, err := NewCommunityEndpoints(CommunityOptions{
		Posts: backend, Backend: community, Passwords: httpTestPasswords{backend: community}, Limits: httpTestLimits(),
		InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots},
	})
	if err != nil {
		t.Fatal(err)
	}
	handler := endpoints.Public
	for _, tc := range []struct {
		method, path, input string
	}{
		{http.MethodPost, postSearchPath, `{"keyword":" 自习 ","channelId":"` + postHTTPChannel + `","sort":"latest","limit":1,"recordHistory":true}`},
		{http.MethodGet, postSearchHistoryPath + "?channelId=" + postHTTPChannel, ""},
		{http.MethodPost, postSearchHistoryPath, `{"action":"remove","keyword":" 自习 "}`},
	} {
		w := postHTTPRequest(handler, tc.method, tc.path, tc.input, postHTTPHeaders(false))
		if w.Code != 200 || w.Header().Get("Cache-Control") != "no-store" || w.Header().Get("Session-Expires-At") == "" || w.Header().Get("Server-Time") == "" {
			t.Fatalf("%s %s did not return an authorized private response: %d", tc.method, tc.path, w.Code)
		}
	}
	if backend.calls != 3 || backend.bearer[0] != 7 ||
		backend.search != (posts.SearchQuery{Keyword: "自习", ChannelID: postHTTPChannel, Sort: posts.SearchLatest, Limit: 1, RecordHistory: true}) ||
		backend.scope != postHTTPChannel || backend.change != (posts.SearchHistoryChange{Action: "remove", Keyword: "自习"}) {
		t.Fatal("search routing, normalization, or authority forwarding differs from the contract")
	}
	for _, tc := range []struct {
		method, path, input string
		status              int
		code                string
	}{
		{http.MethodGet, postSearchPath, "", 405, "MALFORMED_REQUEST"},
		{http.MethodPost, postSearchPath, `{"keyword":"  "}`, 400, "MALFORMED_REQUEST"},
		{http.MethodPost, postSearchPath, `{"keyword":"a","keyword":"b"}`, 400, "MALFORMED_REQUEST"},
		{http.MethodPost, postSearchPath, `{"keyword":"a","accountId":"other"}`, 400, "MALFORMED_REQUEST"},
		{http.MethodPost, postSearchPath, `{"keyword":"a","sort":"popular"}`, 400, "MALFORMED_REQUEST"},
		{http.MethodPost, postSearchPath, `{"keyword":"a","cursor":"AA","recordHistory":true}`, 400, "MALFORMED_REQUEST"},
		{http.MethodPost, postSearchPath, `{"keyword":"a","cursor":"!"}`, 400, "CURSOR_INVALID"},
		{http.MethodGet, postSearchHistoryPath + "?channelId=" + postHTTPChannel + "&", "", 400, "MALFORMED_REQUEST"},
		{http.MethodGet, postSearchHistoryPath + "?accountId=other", "", 400, "MALFORMED_REQUEST"},
		{http.MethodPost, postSearchHistoryPath, `{"action":"clear","keyword":"a"}`, 400, "MALFORMED_REQUEST"},
		{http.MethodPost, postSearchHistoryPath, `{"action":"remove"}`, 400, "MALFORMED_REQUEST"},
	} {
		w := postHTTPRequest(handler, tc.method, tc.path, tc.input, postHTTPHeaders(false))
		postHTTPCheckError(t, w, tc.status, tc.code)
	}
	headers := postHTTPHeaders(false)
	headers.Del("Authorization")
	w := postHTTPRequest(handler, http.MethodPost, postSearchPath, `{"keyword":"a"}`, headers)
	postHTTPCheckError(t, w, 401, "AUTHENTICATION_FAILED")
	w = postHTTPRequest(handler, http.MethodPost, postSearchPath, `{"keyword":"a"}`, postHTTPHeaders(true))
	postHTTPCheckError(t, w, 400, "MALFORMED_REQUEST")
	if backend.calls != 3 {
		t.Fatal("invalid request reached search backend")
	}

	backend.value = posts.SearchHistory{Items: []string{"KEY", "key"}}
	w = postHTTPRequest(handler, http.MethodGet, postSearchHistoryPath, "", postHTTPHeaders(false))
	postHTTPCheckError(t, w, 503, "SERVICE_UNAVAILABLE")
	backend.value = posts.FeedPage{Items: []posts.PublicPostCard{postHTTPCard()}}
	w = postHTTPRequest(handler, http.MethodPost, postSearchPath, `{"keyword":"a","channelId":"`+postHTTPIdentity+`"}`, postHTTPHeaders(false))
	postHTTPCheckError(t, w, 503, "SERVICE_UNAVAILABLE")
}
