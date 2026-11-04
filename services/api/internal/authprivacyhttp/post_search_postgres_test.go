package authprivacyhttp

import (
	"context"
	"os"
	"reflect"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type postSearchFixture struct {
	owner, reader         string
	channel, otherChannel string
	exact, body, other    string
}

func seedPostSearch(t *testing.T, s *e2eServices) postSearchFixture {
	t.Helper()
	owner, _ := e2ePrivacySignup(t, s, "post_search_owner")
	reader, _ := e2ePrivacySignup(t, s, "post_search_reader")
	catalog := e2eJSON(t, s.client, "GET", s.cPublic.URL+"/api/v1/channels", nil, map[string]string{"Authorization": "Bearer " + owner}, 200)
	channels := catalog["channels"].([]any)
	channel := channels[0].(map[string]any)["id"].(string)
	otherChannel := channels[1].(map[string]any)["id"].(string)
	identity := postHTTPSIdentity(t, s, owner, "联调身份", 89)
	publish := func(key byte, channelID, title, body string) string {
		t.Helper()
		created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, key), owner, "", posts.CreatePostInput{
			ChannelID: channelID, IdentityID: identity, Title: title, Body: body,
		}, 202)
		if _, err := s.c.PublishAcceptedPosts(context.Background(), 100); err != nil {
			t.Fatal(err)
		}
		return created["postId"].(string)
	}
	return postSearchFixture{
		owner: owner, reader: reader, channel: channel, otherChannel: otherChannel,
		exact: publish(90, channel, "自习", "欢迎一起学习"),
		body:  publish(91, channel, "晚间安排", "今晚一起自习"),
		other: publish(92, otherChannel, "自习地点", "图书馆二楼"),
	}
}

func TestRealHTTPSPostSearchHistoryPostgres(t *testing.T) {
	s := e2eNewServices(t)
	f := seedPostSearch(t, s)
	input := map[string]any{"keyword": " 自习 ", "channelId": f.channel, "limit": 1, "recordHistory": true}
	page := postHTTPSJSON(t, s, "POST", postSearchPath, f.reader, "", input, 200)
	item := page["items"].([]any)[0].(map[string]any)
	postHTTPSPublic(t, item, false)
	if item["postId"] != f.exact || page["nextCursor"] == nil {
		t.Fatal("relevance did not prioritize the exact title or page within the channel")
	}
	input["cursor"], input["recordHistory"] = page["nextCursor"], false
	page = postHTTPSJSON(t, s, "POST", postSearchPath, f.reader, "", input, 200)
	if page["items"].([]any)[0].(map[string]any)["postId"] != f.body || page["nextCursor"] != nil {
		t.Fatal("continuation did not return the only remaining body match")
	}
	bad := postHTTPSJSON(t, s, "POST", postSearchPath, f.owner, "", input, 400)
	if bad["error"].(map[string]any)["code"] != "CURSOR_INVALID" {
		t.Fatal("another account used the search cursor")
	}
	detail := postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+f.body, f.reader, "", nil, 200)
	if detail["post"].(map[string]any)["body"] != "今晚一起自习" {
		t.Fatal("search result did not resolve to its canonical detail")
	}
	history := func(token, channelID string) []any {
		t.Helper()
		path := postSearchHistoryPath
		if channelID != "" {
			path += "?channelId=" + channelID
		}
		return postHTTPSJSON(t, s, "GET", path, token, "", nil, 200)["items"].([]any)
	}
	if !reflect.DeepEqual(history(f.reader, f.channel), []any{"自习"}) || len(history(f.owner, f.channel)) != 0 || len(history(f.reader, "")) != 0 {
		t.Fatal("submission history was missing or crossed account/scope boundaries")
	}
	empty := postHTTPSJSON(t, s, "POST", postSearchPath, f.reader, "", map[string]any{"keyword": "没有命中", "recordHistory": true}, 200)
	if len(empty["items"].([]any)) != 0 || empty["nextCursor"] != nil || !reflect.DeepEqual(history(f.reader, ""), []any{"没有命中"}) {
		t.Fatal("successful empty search did not have its own history")
	}
	postHTTPSJSON(t, s, "POST", "/api/v1/posts/"+f.exact+"/delete", f.owner, httpTestEncoding(16, 93), nil, 200)
	postHTTPSJSON(t, s, "PUT", "/api/v1/me/feed-preferences", f.reader, "", posts.FeedPreferences{BlockedChannelIDs: []string{f.otherChannel}}, 200)
	page = postHTTPSJSON(t, s, "POST", postSearchPath, f.reader, "", map[string]any{"keyword": "自习"}, 200)
	if items := page["items"].([]any); len(items) != 1 || items[0].(map[string]any)["postId"] != f.body {
		t.Fatal("deleted or blocked content leaked through search")
	}
	cleared := postHTTPSJSON(t, s, "POST", postSearchHistoryPath, f.reader, "", map[string]any{"action": "clear", "channelId": f.channel}, 200)
	if len(cleared["items"].([]any)) != 0 || len(history(f.reader, "")) != 1 {
		t.Fatal("clear crossed history scopes")
	}
	if err := s.gate.Freeze(context.Background(), "post search HTTPS regression"); err != nil {
		t.Fatal(err)
	}
	postHTTPSJSON(t, s, "POST", postSearchPath, f.reader, "", map[string]any{"keyword": "权限已撤销", "recordHistory": true}, 503)
	postHTTPSJSON(t, s, "GET", postSearchHistoryPath, f.reader, "", nil, 503)
}

func TestRealHTTPSPostSearchDartPostgres(t *testing.T) {
	probe := os.Getenv("POST_SEARCH_DART_PROBE")
	if probe == "" {
		t.Skip("compiled search Dart probe absent")
	}
	s := e2eNewServices(t)
	rootPEM := e2eDartPublicTLS(t, s)
	f := seedPostSearch(t, s)
	result := runLiveGovernanceProbe(t, probe, map[string]any{
		"url": s.cPublic.URL, "certificatePem": string(rootPEM),
		"readerToken": f.reader, "ownerToken": f.owner, "channelId": f.channel,
		"otherChannelId": f.otherChannel, "exactPostId": f.exact, "bodyPostId": f.body,
		"otherPostId": f.other,
	}, "post-search")
	if result["status"] != "PASS" {
		t.Fatal("search Dart transport probe did not establish success")
	}
}
