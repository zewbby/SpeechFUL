package authprivacyhttp

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
)

const postShareTestOrigin = "https://share.example"

func newPostShareHTTP(t *testing.T, origin string) (*postHTTPBackend, http.Handler) {
	t.Helper()
	pki := newHTTPTestPKI(t)
	community := &httpTestCommunity{}
	backend := &postHTTPBackend{}
	endpoints, err := NewCommunityEndpoints(CommunityOptions{
		PublicOrigin: origin, Posts: backend, Backend: community, Passwords: httpTestPasswords{backend: community},
		InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots},
		Limits:       httpTestLimits(), AllowedOrigins: []string{"https://client.example"},
	})
	if err != nil {
		t.Fatal(err)
	}
	return backend, endpoints.Public
}

func TestPostShareHTTPContract(t *testing.T) {
	backend, handler := newPostShareHTTP(t, postShareTestOrigin+"/")
	path := "/api/v1/posts/" + postHTTPPost + "/share"
	link := postShareTestOrigin + postSharePrefix + postHTTPPost
	headers := postHTTPHeaders(false)
	headers.Set("X-Forwarded-Host", "attacker.invalid")
	headers.Set("Origin", "https://client.example")
	for i := 0; i < 2; i++ {
		w := postHTTPRequest(handler, "GET", path, "", headers)
		if w.Code != 200 || w.Header().Get("Session-Expires-At") == "" || w.Header().Get("Server-Time") == "" || w.Header().Get("Cache-Control") != "no-store" {
			t.Fatalf("share envelope status=%d", w.Code)
		}
		var result map[string]string
		if json.Unmarshal(w.Body.Bytes(), &result) != nil || len(result) != 3 || result["postId"] != postHTTPPost || result["url"] != link || result["shareText"] != "SpeechFUL\n"+link {
			t.Fatal("share contains unexpected fields or unstable/untrusted link")
		}
	}
	if backend.query.Kind != authprivacy.PostDetail || backend.query.ID != postHTTPPost {
		t.Fatal("share did not authorize through the existing original-post read")
	}
	w := postHTTPRequest(handler, "POST", postLinkResolvePath, `{"url":"`+link+`"}`, headers)
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"postId":"`+postHTTPPost+`"`) || !strings.Contains(w.Body.String(), `"body":`) || backend.calls != 3 {
		t.Fatal("resolve did not return the current original-post DTO")
	}
	if !strings.Contains(w.Header().Get("Access-Control-Expose-Headers"), "Post-Edited-At") {
		t.Fatal("browser client cannot read original-post edit metadata on resolve")
	}
	preflight := http.Header{"Origin": {"https://client.example"}, "Access-Control-Request-Method": {"POST"}, "Access-Control-Request-Headers": {"authorization, content-type"}}
	w = postHTTPRequest(handler, "OPTIONS", postLinkResolvePath, "", preflight)
	if w.Code != 204 || backend.calls != 3 {
		t.Fatal("resolve preflight missing or invoked backend")
	}
}

func TestPostShareRejectsUnauthenticatedAndMalformedInput(t *testing.T) {
	backend, handler := newPostShareHTTP(t, postShareTestOrigin)
	path := "/api/v1/posts/" + postHTTPPost + "/share"
	link := postShareTestOrigin + postSharePrefix + postHTTPPost
	for _, tc := range []struct{ method, path, body string }{
		{"GET", path, ""}, {"POST", postLinkResolvePath, `{"url":"` + link + `"}`},
	} {
		w := postHTTPRequest(handler, tc.method, tc.path, tc.body, http.Header{})
		postHTTPCheckError(t, w, 401, "AUTHENTICATION_FAILED")
	}
	for _, raw := range []string{
		"http://share.example" + postSharePrefix + postHTTPPost,
		"https://attacker.invalid" + postSharePrefix + postHTTPPost,
		"https://share.example.attacker.invalid" + postSharePrefix + postHTTPPost,
		"https://share.example@attacker.invalid" + postSharePrefix + postHTTPPost,
		"https://share.example:443" + postSharePrefix + postHTTPPost,
		postSharePrefix + postHTTPPost, "speechful://posts/" + postHTTPPost,
		link + "?tracking=1", link + "#fragment", link + "/", link + "/../" + postHTTPTask,
		postShareTestOrigin + postSharePrefix + "00000000-0000-0000-0000-000000000000",
		postShareTestOrigin + postSharePrefix + "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
		strings.Replace(link, "/s/", "/%73/", 1), " " + link,
	} {
		body, _ := json.Marshal(map[string]string{"url": raw})
		w := postHTTPRequest(handler, "POST", postLinkResolvePath, string(body), postHTTPHeaders(false))
		postHTTPCheckError(t, w, 400, "MALFORMED_REQUEST")
	}
	for _, tc := range []struct{ method, path, body string }{
		{"GET", path, "{}"}, {"GET", path + "?extra=1", ""},
		{"POST", postLinkResolvePath, `{"url":"` + link + `","url":"` + link + `"}`},
		{"POST", postLinkResolvePath, `{"url":"` + link + `","accountId":"` + postHTTPIdentity + `"}`},
		{"POST", postLinkResolvePath, `{"url":null}`}, {"POST", postLinkResolvePath, `{}`},
	} {
		w := postHTTPRequest(handler, tc.method, tc.path, tc.body, postHTTPHeaders(false))
		postHTTPCheckError(t, w, 400, "MALFORMED_REQUEST")
	}
	w := postHTTPRequest(handler, "POST", postLinkResolvePath, `{"url":"`+link+`"}`, postHTTPHeaders(true))
	postHTTPCheckError(t, w, 400, "MALFORMED_REQUEST")
	w = postHTTPRequest(handler, "PUT", path, "", postHTTPHeaders(false))
	postHTTPCheckError(t, w, 405, "MALFORMED_REQUEST")
	if backend.calls != 0 {
		t.Fatal("invalid share input reached original-post backend")
	}
}

func TestPostSharePreservesAuthorityAndFailsClosed(t *testing.T) {
	backend, handler := newPostShareHTTP(t, postShareTestOrigin)
	path := "/api/v1/posts/" + postHTTPPost + "/share"
	for _, tc := range []struct {
		err    error
		status int
		code   string
	}{
		{authprivacy.ErrSessionInvalid, 401, "SESSION_INVALID"},
		{authprivacy.ErrAccountUnavailable, 403, "AUTHENTICATION_FAILED"},
		{&authprivacy.PostError{Status: 404, Code: "POST_NOT_FOUND"}, 404, "POST_NOT_FOUND"},
		{authprivacy.ErrAuthorizationUnavailable, 503, "AUTHORIZATION_UNAVAILABLE"},
	} {
		backend.err = tc.err
		w := postHTTPRequest(handler, "GET", path, "", postHTTPHeaders(false))
		postHTTPCheckError(t, w, tc.status, tc.code)
	}
	backend.err = nil
	backend.value = map[string]any{"postId": postHTTPPost, "privateAccount": "must not escape"}
	w := postHTTPRequest(handler, "GET", path, "", postHTTPHeaders(false))
	postHTTPCheckError(t, w, 503, "SERVICE_UNAVAILABLE")
	backend.value = nil
	backend.expiresAt = postHTTPTime.Add(-time.Hour)
	w = postHTTPRequest(handler, "GET", path, "", postHTTPHeaders(false))
	postHTTPCheckError(t, w, 503, "SERVICE_UNAVAILABLE")
	_, disabled := newPostShareHTTP(t, "")
	w = postHTTPRequest(disabled, "GET", path, "", postHTTPHeaders(false))
	postHTTPCheckError(t, w, 503, "SERVICE_UNAVAILABLE")
}

func TestPostShareLandingIsContentFree(t *testing.T) {
	backend, handler := newPostShareHTTP(t, postShareTestOrigin)
	var baseline string
	for _, id := range []string{postHTTPPost, postHTTPTask} {
		for _, headers := range []http.Header{{}, postHTTPHeaders(false)} {
			w := postHTTPRequest(handler, "GET", postSharePrefix+id, "", headers)
			if w.Code != 200 || w.Header().Get("Content-Type") != "text/html; charset=utf-8" || w.Header().Get("Referrer-Policy") != "no-referrer" || w.Header().Get("Content-Security-Policy") == "" || w.Header().Get("Cache-Control") != "no-store" || w.Header().Get("Session-Expires-At") != "" {
				t.Fatal("public guide envelope invalid or claims session authority")
			}
			body := w.Body.String()
			if !strings.Contains(body, "speechful://posts/"+id) || !strings.Contains(body, "登录后") || strings.Contains(body, "原始标题") || strings.Contains(body, "当前身份") || strings.Contains(body, "<script") || strings.Contains(body, "<img") {
				t.Fatal("public guide leaks content or lost its original-post target")
			}
			normalized := strings.ReplaceAll(body, id, "TARGET")
			if baseline != "" && baseline != normalized {
				t.Fatal("public guide depends on account or target availability")
			}
			baseline = normalized
		}
	}
	w := postHTTPRequest(handler, "HEAD", postSharePrefix+postHTTPPost, "", http.Header{})
	if w.Code != 200 || w.Body.Len() != 0 {
		t.Fatal("HEAD should return guide headers without a body")
	}
	for _, path := range []string{"/s/posts", postSharePrefix + "invalid", postSharePrefix + postHTTPPost + "/", "/s/%70osts/" + postHTTPPost} {
		w := postHTTPRequest(handler, "GET", path, "", http.Header{})
		if w.Code == 200 {
			t.Fatal("guide accepted a noncanonical path")
		}
	}
	if backend.calls != 0 {
		t.Fatal("public guide queried post existence/content")
	}
}

func TestPostShareRejectsUntrustedConfiguredOrigin(t *testing.T) {
	pki := newHTTPTestPKI(t)
	community := &httpTestCommunity{}
	for _, origin := range []string{"http://share.example", "https://user:secret@share.example", "https://share.example/path", "https://share.example?x=1", "https://share.example#target"} {
		_, err := NewCommunityEndpoints(CommunityOptions{PublicOrigin: origin, Backend: community, Passwords: httpTestPasswords{backend: community}, InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots}, Limits: httpTestLimits()})
		if err == nil {
			t.Fatal("unsafe configured share origin accepted")
		}
	}
}
