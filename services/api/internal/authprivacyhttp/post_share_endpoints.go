package authprivacyhttp

import (
	"net/http"
	"net/url"
	"strings"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
)

const (
	postLinkResolvePath                           = "/api/v1/post-links/resolve"
	postSharePrefix                               = "/s/posts/"
	postShareRoute       authprivacy.PostReadKind = "postShare"
	postLinkResolveRoute authprivacy.PostReadKind = "postLinkResolve"
)

// PostShareLink deliberately contains no post content or sender identity.
type PostShareLink struct {
	PostID    string `json:"postId"`
	URL       string `json:"url"`
	ShareText string `json:"shareText"`
}

func (b *boundary) communityPostSharing(w http.ResponseWriter, r *http.Request, backend PostBackend, bearer [32]byte, route postRoute) {
	if b.postLinkOrigin == "" {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	if route.kind == postLinkResolveRoute {
		object, err := readRequestObject(r, 4096, []string{"url"}, nil)
		if err != nil {
			b.postBad(w, err)
			return
		}
		raw, err := stringField(object, "url")
		if err != nil {
			b.postBad(w, err)
			return
		}
		id, ok := strings.CutPrefix(raw, b.postLinkOrigin+postSharePrefix)
		if !ok || !postValidID(id) {
			b.postBad(w, errMalformed)
			return
		}
		route.id = id
	} else if noBodyOrQuery(r) != nil {
		b.postBad(w, errMalformed)
		return
	}
	// Both operations use the existing final C Gate transaction and live public
	// projection. A link conveys a target, never authority or a content snapshot.
	response, err := backend.ReadPosts(r.Context(), bearer, authprivacy.PostQuery{Kind: authprivacy.PostDetail, ID: route.id})
	if err != nil {
		b.postFailure(w, err)
		return
	}
	detailRoute := postRoute{kind: authprivacy.PostDetail, id: route.id}
	if route.kind == postLinkResolveRoute {
		b.writePostResponse(w, response, detailRoute, false)
		return
	}
	if _, err := strictPostValue(response.Value, detailRoute); err != nil {
		b.postFail(w, 503, "SERVICE_UNAVAILABLE", 0)
		return
	}
	link := b.postLinkOrigin + postSharePrefix + route.id
	response.Value = PostShareLink{PostID: route.id, URL: link, ShareText: "SpeechFUL\n" + link}
	b.writePostResponse(w, response, route, false)
}

func strictPostShareLink(value any, id string) (any, error) {
	link, ok := value.(PostShareLink)
	if !ok || link.PostID != id || !postValidID(id) || link.ShareText != "SpeechFUL\n"+link.URL {
		return nil, errMalformed
	}
	u, err := url.Parse(link.URL)
	if err != nil || u.Path != postSharePrefix+id || u.RawPath != "" || u.RawQuery != "" || u.ForceQuery || u.Fragment != "" {
		return nil, errMalformed
	}
	if _, err := fixedOrigin("https://" + u.Host); err != nil || u.Scheme != "https" || u.User != nil || u.String() != link.URL {
		return nil, errMalformed
	}
	return link, nil
}

func isPostShareLanding(path string) bool {
	return path == strings.TrimSuffix(postSharePrefix, "/") || strings.HasPrefix(path, postSharePrefix)
}

func (b *boundary) servePostShareLanding(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		b.postFail(w, 405, "MALFORMED_REQUEST", 0)
		return
	}
	id, ok := strings.CutPrefix(r.URL.Path, postSharePrefix)
	if !ok || !postValidID(id) || r.URL.RawPath != "" || noBodyOrQuery(r) != nil || hasHeader(r.Header, "Idempotency-Key") || hasHeader(r.Header, "Content-Encoding") {
		b.postBad(w, errMalformed)
		return
	}
	// No database access, including an existence check. Crawlers and logged-out
	// visitors receive the same page for every syntactically valid target.
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("X-Robots-Tag", "noindex, nofollow, noarchive")
	w.WriteHeader(http.StatusOK)
	if r.Method == http.MethodHead {
		return
	}
	// The sole substitution is a previously validated canonical UUID, which has
	// no HTML metacharacters. No request host, query or content enters this page.
	_, _ = w.Write([]byte(strings.ReplaceAll(postShareLandingHTML, "{{postId}}", id)))
}

const postShareLandingHTML = `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="在 SpeechFUL 中登录后查看分享的帖子。">
<title>SpeechFUL</title>
<style>body{font-family:system-ui,sans-serif;max-width:32rem;margin:15vh auto;padding:1.5rem;line-height:1.7;color:#17212b}a{display:inline-block;padding:.65rem 1.2rem;background:#168acd;color:white;border-radius:.6rem;text-decoration:none}small{display:block;margin-top:1.5rem;color:#536471}</style>
</head><body><main><h1>SpeechFUL</h1>
<p>在 SpeechFUL 中登录后查看分享的帖子。</p>
<a href="speechful://posts/{{postId}}" rel="noreferrer">在 App 中打开</a>
<small>尚未安装 App？请先安装 SpeechFUL，再打开此链接。</small>
</main></body></html>`
