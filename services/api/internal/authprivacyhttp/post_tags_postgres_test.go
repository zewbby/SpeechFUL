package authprivacyhttp

import (
	"context"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"os"
	"testing"
)

func TestRealHTTPSPostTagsLifecycleAndCompatibilityPostgres(t *testing.T) {
	s := e2eNewServices(t)
	owner, _ := e2ePrivacySignup(t, s, "tags_https_owner")
	reader, _ := e2ePrivacySignup(t, s, "tags_https_reader")
	channel := postHTTPSChannel(t, s, owner)
	identity := postHTTPSIdentity(t, s, owner, "标签身份", 181)
	call := func(method, path, token, key string, input any, status int) map[string]any {
		t.Helper()
		headers := map[string]string{"Authorization": "Bearer " + token, "X-Post-Tags": "v1"}
		if key != "" {
			headers["Idempotency-Key"] = key
		}
		return e2eJSON(t, s.client, method, s.cPublic.URL+path, input, headers, status)
	}
	input := posts.CreatePostInput{ChannelID: channel, IdentityID: identity, Title: "周末安排", Body: "一起运动", Tags: []string{"篮球", "NBA"}}
	path := "/api/v1/post-commands/" + httpTestEncoding(16, 182)
	created := call("PUT", path, owner, "", input, 202)
	post := created["postId"].(string)
	replay := call("PUT", path, owner, "", input, 202)
	if replay["postId"] != post {
		t.Fatal("tagged command replay created a second post")
	}
	input.Tags = []string{"食堂"}
	call("PUT", path, owner, "", input, 409)
	if _, err := s.c.PublishAcceptedPosts(context.Background(), 100); err != nil {
		t.Fatal(err)
	}
	detail := call("GET", "/api/v1/posts/"+post, reader, "", nil, 200)["post"].(map[string]any)
	if tags := detail["tags"].([]any); len(tags) != 2 || tags[0] != "篮球" {
		t.Fatal("published labels missing", detail)
	}
	shared := call("GET", "/api/v1/posts/"+post+"/share", reader, "", nil, 200)
	resolved := call("POST", postLinkResolvePath, reader, "", map[string]any{"url": shared["url"]}, 200)
	if tags := resolved["post"].(map[string]any)["tags"].([]any); len(tags) != 2 || tags[0] != "篮球" {
		t.Fatal("resolving the original post dropped public labels")
	}
	legacy := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+post, reader, "", nil, 200)
	if _, exists := legacy["post"].(map[string]any)["tags"]; exists {
		t.Fatal("legacy DTO acquired unknown tag field")
	}
	page := call("POST", postTagPath, reader, "", map[string]any{"tag": "篮球"}, 200)
	if items := page["items"].([]any); len(items) != 1 || items[0].(map[string]any)["postId"] != post {
		t.Fatal("exact tag lookup failed")
	}
	page = call("POST", postSearchPath, reader, "", map[string]any{"keyword": "nba"}, 200)
	if len(page["items"].([]any)) != 1 {
		t.Fatal("ordinary search missed a tag-only match")
	}
	suggestions := call("POST", postTagSuggestionsPath, reader, "", map[string]any{"prefix": "n"}, 200)
	if items := suggestions["items"].([]any); len(items) != 1 || items[0] != "NBA" {
		t.Fatal("existing label suggestion missing")
	}
	for _, body := range []any{map[string]any{"tag": "篮球", "accountId": "other"}, map[string]any{"tag": "a b"}, map[string]any{"tag": "一二三四五六七八九十百"}} {
		call("POST", postTagPath, reader, "", body, 400)
	}
	snapshot := call("GET", "/api/v1/me/posts/"+post+"/edit", owner, "", nil, 200)
	call("PUT", "/api/v1/me/posts/"+post+"/edit-commands/"+httpTestEncoding(16, 183), owner, "", map[string]any{"revision": snapshot["revision"], "title": "周末安排", "body": "一起运动", "tags": []string{}}, 200)
	page = call("POST", postTagPath, reader, "", map[string]any{"tag": "篮球"}, 200)
	if len(page["items"].([]any)) != 0 {
		t.Fatal("removed tag stayed searchable")
	}
	if err := s.gate.Freeze(context.Background(), "tag HTTPS regression"); err != nil {
		t.Fatal(err)
	}
	call("POST", postTagPath, reader, "", map[string]any{"tag": "篮球"}, 503)
	call("POST", postTagSuggestionsPath, reader, "", map[string]any{"prefix": "篮"}, 503)
}

func TestRealHTTPSPostTagsDartPostgres(t *testing.T) {
	probe := os.Getenv("POST_TAGS_DART_PROBE")
	if probe == "" {
		t.Skip("compiled tag Dart probe absent")
	}
	s := e2eNewServices(t)
	root := e2eDartPublicTLS(t, s)
	owner, _ := e2ePrivacySignup(t, s, "tags_dart_owner")
	reader, _ := e2ePrivacySignup(t, s, "tags_dart_reader")
	channel := postHTTPSChannel(t, s, owner)
	identity := postHTTPSIdentity(t, s, owner, "标签联调", 184)
	created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 185), owner, "", posts.CreatePostInput{ChannelID: channel, IdentityID: identity, Title: "周末安排", Body: "一起运动", Tags: []string{"篮球", "NBA"}}, 202)
	if _, err := s.c.PublishAcceptedPosts(context.Background(), 100); err != nil {
		t.Fatal(err)
	}
	result := runLiveGovernanceProbe(t, probe, map[string]any{"url": s.cPublic.URL, "certificatePem": string(root), "readerToken": reader, "ownerToken": owner, "channelId": channel, "identityId": identity, "postId": created["postId"]}, "post-tags")
	if result["status"] != "PASS" {
		t.Fatal("tag Dart transport did not establish success")
	}
}
