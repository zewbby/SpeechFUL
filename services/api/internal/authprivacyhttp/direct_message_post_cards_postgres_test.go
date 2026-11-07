package authprivacyhttp

import (
	"context"
	"encoding/json"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"net/http"
	"testing"
)

func TestDMPostCardHTTPSPostgres(t *testing.T) {
	ctx := context.Background()
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		v, e := c.WithDirectMessages(ctx)
		if e != nil {
			t.Fatal(e)
		}
		return v
	})
	a, _ := e2ePrivacySignup(t, s, "card_https_a")
	b, _ := e2ePrivacySignup(t, s, "card_https_b")
	ia := postHTTPSIdentity(t, s, a, "卡片甲", 71)
	ib := postHTTPSIdentity(t, s, b, "卡片乙", 72)
	channel := postHTTPSChannel(t, s, b)
	p := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 73), b, "", map[string]any{"channelId": channel, "identityId": ib, "title": "当前卡片标题", "body": "不应进入卡片的正文"}, 202)
	if _, e := s.c.PublishAcceptedPosts(ctx, 100); e != nil {
		t.Fatal(e)
	}
	post := p["postId"].(string)
	first := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+uuid.NewString(), a, "", authprivacy.DMTextIntent{IdentityID: ia, PeerID: ib, SourcePostID: post, Text: "hello", Attempt: 1}, 200)
	in := authprivacy.DMTextIntent{Kind: "POST", IdentityID: ia, PeerID: ib, ConversationID: first["conversationId"].(string), Text: post, Attempt: 1}
	key := uuid.NewString()
	fail := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+key, a, "", in, 200)
	if fail["errorCode"] != "WAITING_FOR_REPLY" {
		t.Fatal(fail)
	}
	postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+uuid.NewString(), b, "", authprivacy.DMTextIntent{IdentityID: ib, PeerID: ia, ConversationID: in.ConversationID, Text: "reply", Attempt: 1}, 200)
	in.Attempt = 2
	sent := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+key, a, "", in, 200)
	if sent["state"] != "SENT" {
		t.Fatal(sent)
	}
	duplicate := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+key, a, "", in, 200)
	if duplicate["messageId"] != sent["messageId"] {
		t.Fatal("duplicate reference")
	}
	readVersion := func(path string, version string) map[string]any {
		t.Helper()
		req, err := http.NewRequest("GET", s.cPublic.URL+path, nil)
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Authorization", "Bearer "+b)
		if version != "" {
			req.Header.Set("X-DM-Post-Cards", version)
		}
		res, err := s.client.Do(req)
		if err != nil {
			t.Fatal("card compatibility transport")
		}
		defer res.Body.Close()
		if res.StatusCode != 200 || res.Header.Get("Cache-Control") != "no-store" {
			t.Fatal("card compatibility envelope")
		}
		var out map[string]any
		if err = json.NewDecoder(res.Body).Decode(&out); err != nil {
			t.Fatal(err)
		}
		return out
	}
	for _, version := range []string{"", "v1"} {
		page := readVersion("/api/v1/dm/chat/pending", version)
		cards := 0
		for _, v := range page["items"].([]any) {
			if v.(map[string]any)["kind"] == "POST" {
				cards++
			}
		}
		if version == "" && cards != 0 || version == "v1" && cards != 1 {
			t.Fatal("card capability ignored")
		}
		dir := readVersion("/api/v1/dm/chat/conversations?identityId="+ib, version)
		item := dir["items"].([]any)[0].(map[string]any)
		if version == "" {
			if _, ok := item["canShare"]; ok {
				t.Fatal("new field sent to legacy client")
			}
		} else if item["canShare"] != true {
			t.Fatal("mutual share eligibility missing")
		}
	}
	card := postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/posts/"+post, b, "", nil, 200)
	if len(card) != 4 || card["title"] != "当前卡片标题" || card["postId"] != post || card["channelId"] != channel {
		t.Fatal("preview contains unexpected fields", card)
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/posts/"+uuid.NewString(), b, "", nil, 404)
	postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/posts/"+post+"?includeBody=true", b, "", nil, 400)
	postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/posts/"+post, b, "", map[string]any{"body": "unexpected"}, 400)
	postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/posts/"+post, "", "", nil, 401)
	if e := s.gate.Freeze(ctx, "post card final authorization check"); e != nil {
		t.Fatal(e)
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/dm/chat/posts/"+post, b, "", nil, 503)
	postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+uuid.NewString(), a, "", in, 503)
}
