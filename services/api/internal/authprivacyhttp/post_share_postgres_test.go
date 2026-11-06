package authprivacyhttp

import (
	"context"
	"io"
	"net/http"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func TestRealHTTPSPostShareLifecyclePostgres(t *testing.T) {
	ctx := context.Background()
	s := e2eNewServices(t)
	owner, _ := e2ePrivacySignup(t, s, "share_owner")
	reader, readerID := e2ePrivacySignup(t, s, "share_reader")
	channel := postHTTPSChannel(t, s, owner)
	identity := postHTTPSIdentity(t, s, owner, "分享原作者", 161)
	created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 162), owner, "", posts.CreatePostInput{
		ChannelID: channel, IdentityID: identity, Title: "分享前的标题", Body: "分享前的正文",
	}, 202)
	if _, err := s.c.PublishAcceptedPosts(ctx, 100); err != nil {
		t.Fatal(err)
	}
	id := created["postId"].(string)
	sharePath := "/api/v1/posts/" + id + "/share"
	link := postShareTestOrigin + postSharePrefix + id
	for _, token := range []string{owner, reader} {
		shared := postHTTPSJSON(t, s, "GET", sharePath, token, "", nil, 200)
		postHTTPSFields(t, shared, "postId", "url", "shareText")
		if shared["postId"] != id || shared["url"] != link || shared["shareText"] != "SpeechFUL\n"+link {
			t.Fatal("link depends on sharer or includes post content")
		}
	}
	guide := func(target string) string {
		t.Helper()
		response, err := s.client.Get(s.cPublic.URL + postSharePrefix + target)
		if err != nil {
			t.Fatal("guide HTTPS transport failed")
		}
		defer response.Body.Close()
		body, err := io.ReadAll(io.LimitReader(response.Body, 16384))
		if err != nil || response.StatusCode != 200 || response.Header.Get("Content-Type") != "text/html; charset=utf-8" || response.Header.Get("Cache-Control") != "no-store" || response.Header.Get("Session-Expires-At") != "" {
			t.Fatal("guide was not a public content-free response")
		}
		if strings.Contains(string(body), "分享前的") || strings.Contains(string(body), "分享原作者") {
			t.Fatal("guide leaked original-post metadata")
		}
		return strings.ReplaceAll(string(body), target, "TARGET")
	}
	initialGuide := guide(id)
	if guide(uuid.NewString()) != initialGuide {
		t.Fatal("guide reveals post existence")
	}
	input := map[string]string{"url": link}
	resolved := postHTTPSJSON(t, s, "POST", postLinkResolvePath, reader, "", input, 200)
	current := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+id, reader, "", nil, 200)
	if !reflect.DeepEqual(resolved, current) {
		t.Fatal("resolved link does not return original current public post")
	}
	// Exercise an actual author edit: an already-issued link reads the new version.
	editor := "/api/v1/me/posts/" + id
	snapshot := postHTTPSJSON(t, s, "GET", editor+"/edit", owner, "", nil, 200)
	s.advanceC(time.Second)
	saved := postHTTPSJSON(t, s, "PUT", editor+"/edit-commands/"+httpTestEncoding(16, 163), owner, "", posts.EditInput{
		Revision: snapshot["revision"].(string), Title: "更新后的标题", Body: "更新后的正文",
	}, 200)
	if saved["state"] != "SAVED" {
		t.Fatal("author edit did not commit")
	}
	resolved = postHTTPSJSON(t, s, "POST", postLinkResolvePath, reader, "", input, 200)
	post := resolved["post"].(map[string]any)
	if post["postId"] != id || post["title"] != "更新后的标题" || post["body"] != "更新后的正文" {
		t.Fatal("old link returned a frozen content snapshot")
	}
	shared := postHTTPSJSON(t, s, "GET", sharePath, reader, "", nil, 200)
	if shared["url"] != link {
		t.Fatal("editing changed stable original-post link")
	}
	var bindings, reposts, views int
	if err := s.cp.QueryRow(ctx, `SELECT
 (SELECT count(*) FROM c_posts.post_identity_bindings WHERE account_id=$1),
 (SELECT count(*) FROM c_posts.post_reposts WHERE account_id=$1),
 (SELECT count(*) FROM c_posts.post_daily_views WHERE account_id=$1)`, readerID).Scan(&bindings, &reposts, &views); err != nil {
		t.Fatal(err)
	}
	if bindings != 0 || reposts != 0 || views != 0 {
		t.Fatal("sharing/resolve created a speaking binding, private repost or view")
	}
	// Only this fixture's disposable database is modified to model moderation.
	if _, err := s.cp.Exec(ctx, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, id); err != nil {
		t.Fatal(err)
	}
	postHTTPSJSON(t, s, "GET", sharePath, reader, "", nil, 404)
	postHTTPSJSON(t, s, "POST", postLinkResolvePath, reader, "", input, 404)
	if guide(id) != initialGuide {
		t.Fatal("guide reveals takedown status")
	}
	if _, err := s.cp.Exec(ctx, `UPDATE c_posts.posts SET moderation_hidden=false WHERE post_id=$1`, id); err != nil {
		t.Fatal(err)
	}
	postHTTPSJSON(t, s, "POST", "/api/v1/posts/"+id+"/delete", owner, httpTestEncoding(16, 164), nil, 200)
	postHTTPSJSON(t, s, "GET", sharePath, reader, "", nil, 404)
	postHTTPSJSON(t, s, "POST", postLinkResolvePath, reader, "", input, 404)
	if guide(id) != initialGuide {
		t.Fatal("guide reveals deletion status")
	}
	if err := s.gate.Freeze(ctx, "share fixture final authority regression"); err != nil {
		t.Fatal(err)
	}
	postHTTPSJSON(t, s, "GET", sharePath, reader, "", nil, 503)
	postHTTPSJSON(t, s, "POST", postLinkResolvePath, reader, "", input, 503)
	if guide(id) != initialGuide {
		t.Fatal("content-free guide depends on Gate availability")
	}
}

func TestRealHTTPSPostShareRequiresLiveSessionPostgres(t *testing.T) {
	s := e2eNewServices(t)
	reader, readerID := e2ePrivacySignup(t, s, "share_session")
	id := uuid.NewString()
	path := "/api/v1/posts/" + id + "/share"
	input := map[string]string{"url": postShareTestOrigin + postSharePrefix + id}
	for _, token := range []string{"", httpTestEncoding(32, 165)} {
		postHTTPSJSON(t, s, "GET", path, token, "", nil, http.StatusUnauthorized)
		postHTTPSJSON(t, s, "POST", postLinkResolvePath, token, "", input, http.StatusUnauthorized)
	}
	postHTTPSJSON(t, s, "GET", path, reader, "", nil, 404)
	postHTTPSJSON(t, s, "POST", postLinkResolvePath, reader, "", input, 404)
	if _, err := s.cp.Exec(context.Background(), `UPDATE c_auth.sessions SET revoked_at=clock_timestamp() WHERE account_id=$1`, readerID); err != nil {
		t.Fatal(err)
	}
	postHTTPSJSON(t, s, "GET", path, reader, "", nil, 401)
	postHTTPSJSON(t, s, "POST", postLinkResolvePath, reader, "", input, 401)
}
