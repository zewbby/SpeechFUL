package authprivacyhttp

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/rankings"
)

func TestRealHTTPSFeedRankingsPostgres(t *testing.T) {
	socket := os.Getenv("RANKING_REDIS_SOCKET")
	if socket == "" {
		t.Skip("dedicated rankings Redis fixture not requested")
	}
	cache := rankings.NewCache(&redis.Options{Network: "unix", Addr: socket}, uuid.NewString())
	t.Cleanup(func() { _ = cache.Close() })
	ctx := context.Background()
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		c, err := c.WithComments(ctx, authprivacy.CommentConfig{KeyKey: e2eKey(t), FingerprintKey: e2eKey(t)})
		if err != nil {
			t.Fatal(err)
		}
		c, err = c.WithRankings(ctx, cache)
		if err != nil {
			t.Fatal(err)
		}
		return c
	})
	f := seedPostSearch(t, s)
	path := "/api/v1/channels/" + f.channel + "/hot-posts"
	postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 503)
	identity := postHTTPSIdentity(t, s, f.owner, "补位作者", 101)
	var bulk []string
	for i := range 65 {
		created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, byte(102+i)), f.owner, "", posts.CreatePostInput{
			ChannelID: f.channel, IdentityID: identity, Title: fmt.Sprintf("榜单测试 %02d", i), Body: "隔离数据库合成内容",
		}, 202)
		bulk = append(bulk, created["postId"].(string))
	}
	if _, err := s.c.PublishAcceptedPosts(ctx, 100); err != nil {
		t.Fatal(err)
	}
	s.advanceC(5 * time.Minute)
	if _, err := s.c.RefreshRankings(ctx, s.cp, authprivacy.DefaultRankingWeights()); err != nil {
		t.Fatal(err)
	}
	got := postHTTPSJSON(t, s, "GET", "/api/v1/feed/channel-order", f.reader, "", nil, 200)
	if got["channelIds"].([]any)[0] != f.channel {
		t.Fatal("channel order missing")
	}
	postHTTPSJSON(t, s, "GET", path+"?unexpected=true", f.reader, "", nil, 400)
	postHTTPSJSON(t, s, "GET", path, httpTestEncoding(32, 1), "", nil, 401)

	// Lock the durable mirror while reading. The healthy Redis path must not
	// wait for it, including final projection of current titles and views.
	tx, err := s.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, "LOCK TABLE c_posts.ranking_snapshots IN ACCESS EXCLUSIVE MODE"); err != nil {
		t.Fatal(err)
	}
	page := postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 200)
	item := page["items"].([]any)[0].(map[string]any)
	if len(page) != 3 || len(page["items"].([]any)) != 20 || len(item) != 3 ||
		item["postId"] != bulk[64] || item["title"] != "榜单测试 64" || item["viewCount"] != float64(0) {
		t.Fatal("incorrect or non-minimal ranking projection")
	}
	if err = tx.Rollback(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err = s.cp.Exec(ctx, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=ANY($1::uuid[])`, bulk); err != nil {
		t.Fatal(err)
	}
	if items := postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 200)["items"].([]any); len(items) != 2 || items[0].(map[string]any)["postId"] != f.body {
		t.Fatal("candidate outside the first Redis page did not fill the ranking")
	}
	postHTTPSJSON(t, s, "POST", "/api/v1/posts/"+f.body+"/delete", f.owner, httpTestEncoding(16, 95), nil, 200)
	if items := postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 200)["items"].([]any); len(items) != 1 || items[0].(map[string]any)["postId"] != f.exact {
		t.Fatal("a deleted candidate survived final read")
	}
	if err = cache.Close(); err != nil {
		t.Fatal(err)
	}
	if items := postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 200)["items"].([]any); len(items) != 1 || items[0].(map[string]any)["postId"] != f.exact {
		t.Fatal("SQL fallback did not retain authorized order")
	}
	postHTTPSJSON(t, s, "PUT", "/api/v1/me/feed-preferences", f.reader, "", posts.FeedPreferences{BlockedChannelIDs: []string{f.channel}}, 200)
	if items := postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 200)["items"].([]any); len(items) != 0 {
		t.Fatal("blocked channel leaked on fallback")
	}
	if err := s.gate.Freeze(ctx, "ranking recovery regression"); err != nil {
		t.Fatal(err)
	}
	postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 503)
	if err := s.recoverC(); err != nil {
		t.Fatal(err)
	}
	postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 401)
}
