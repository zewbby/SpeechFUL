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
	path := "/api/v1/feed/hot-posts"
	postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 503)
	identity := postHTTPSIdentity(t, s, f.owner, "补位作者", 101)
	var bulk []string
	for i := range 85 {
		created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, byte(102+i)), f.owner, "", posts.CreatePostInput{
			ChannelID: f.channel, IdentityID: identity, Title: fmt.Sprintf("榜单测试 %02d", i), Body: "隔离数据库合成内容",
		}, 202)
		bulk = append(bulk, created["postId"].(string))
	}
	var secondaryBulk []string
	for i := range 20 {
		created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, byte(200+i)), f.owner, "", posts.CreatePostInput{
			ChannelID: f.otherChannel, IdentityID: identity, Title: fmt.Sprintf("另类榜单 %02d", i), Body: "另一分类的低分候选",
		}, 202)
		secondaryBulk = append(secondaryBulk, created["postId"].(string))
	}
	for range 2 {
		if _, err := s.c.PublishAcceptedPosts(ctx, 100); err != nil {
			t.Fatal(err)
		}
	}
	_, voter := e2ePrivacySignup(t, s, "global_ranking_voter")
	if _, err := s.cp.Exec(ctx, `INSERT INTO c_posts.post_likes(account_id,post_id) SELECT $1,post_id FROM c_posts.posts WHERE post_id=ANY($2::uuid[])`, voter, bulk); err != nil {
		t.Fatal(err)
	}
	s.advanceC(5 * time.Minute)
	if _, err := s.c.RefreshRankings(ctx, s.cp, authprivacy.DefaultRankingWeights()); err != nil {
		t.Fatal(err)
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
	if _, err = tx.Exec(ctx, "LOCK TABLE c_posts.hot_snapshots IN ACCESS EXCLUSIVE MODE"); err != nil {
		t.Fatal(err)
	}
	page := postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 200)
	item := page["items"].([]any)[0].(map[string]any)
	if len(page) != 2 || len(page["items"].([]any)) != 20 || len(item) != 4 ||
		item["postId"] != bulk[84] || item["title"] != "榜单测试 84" || item["viewCount"] != float64(0) {
		t.Fatal("incorrect or non-minimal ranking projection")
	}
	// The global first 64 are all from one category. Its screen preference
	// must still find other categories in the cached union, without SQL mirror.
	postHTTPSJSON(t, s, "PUT", "/api/v1/me/feed-preferences", f.reader, "", posts.FeedPreferences{BlockedChannelIDs: []string{f.channel}}, 200)
	if rows := postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 200)["items"].([]any); len(rows) != 20 || rows[0].(map[string]any)["postId"] != secondaryBulk[19] {
		t.Fatal("blocked global prefix lost another category")
	}
	postHTTPSJSON(t, s, "PUT", "/api/v1/me/feed-preferences", f.reader, "", posts.FeedPreferences{BlockedChannelIDs: []string{}}, 200)
	if err = tx.Rollback(ctx); err != nil {
		t.Fatal(err)
	}
	// One high-score shard loses 63 of its first 64. Other low-score shards
	// can fill twenty cached rows, but the deeper high-score rows must win.
	if _, err = s.cp.Exec(ctx, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=ANY($1::uuid[])`, bulk[22:]); err != nil {
		t.Fatal(err)
	}
	rows := postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 200)["items"].([]any)
	if len(rows) != 20 {
		t.Fatal("partial shard prefix lost candidates")
	}
	for _, row := range rows {
		if row.(map[string]any)["channelId"] != f.channel {
			t.Fatal("low-score shard masked deeper high-score candidates")
		}
	}
	if _, err = s.cp.Exec(ctx, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=ANY($1::uuid[])`, bulk[21:]); err != nil {
		t.Fatal(err)
	}
	if rows := postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 200)["items"].([]any); len(rows) != 20 || rows[0].(map[string]any)["postId"] != bulk[20] {
		t.Fatal("deep block did not fill twenty live rows")
	}
	if _, err = s.cp.Exec(ctx, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=ANY($1::uuid[])`, secondaryBulk); err != nil {
		t.Fatal(err)
	}
	if _, err = s.cp.Exec(ctx, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=ANY($1::uuid[])`, bulk); err != nil {
		t.Fatal(err)
	}
	if items := postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 200)["items"].([]any); len(items) != 3 || items[0].(map[string]any)["postId"] != f.other {
		t.Fatal("candidate outside the first Redis page did not fill the ranking")
	}
	postHTTPSJSON(t, s, "POST", "/api/v1/posts/"+f.body+"/delete", f.owner, httpTestEncoding(16, 95), nil, 200)
	if items := postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 200)["items"].([]any); len(items) != 2 || items[0].(map[string]any)["postId"] != f.other {
		t.Fatal("a deleted candidate survived final read")
	}
	if err = cache.Close(); err != nil {
		t.Fatal(err)
	}
	if items := postHTTPSJSON(t, s, "GET", path, f.reader, "", nil, 200)["items"].([]any); len(items) != 2 || items[0].(map[string]any)["postId"] != f.other {
		t.Fatal("SQL fallback did not retain authorized order")
	}
	postHTTPSJSON(t, s, "PUT", "/api/v1/me/feed-preferences", f.reader, "", posts.FeedPreferences{BlockedChannelIDs: []string{f.channel, f.otherChannel}}, 200)
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

func TestRealHTTPSFeedRankingsDartPostgres(t *testing.T) {
	probe, socket := os.Getenv("POST_SEARCH_DART_PROBE"), os.Getenv("RANKING_REDIS_SOCKET")
	if probe == "" || socket == "" {
		t.Skip("compiled Dart probe and dedicated Redis required")
	}
	ctx := context.Background()
	cache := rankings.NewCache(&redis.Options{Network: "unix", Addr: socket}, uuid.NewString())
	defer cache.Close()
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
	s.advanceC(5 * time.Minute)
	if _, err := s.c.RefreshRankings(ctx, s.cp, authprivacy.DefaultRankingWeights()); err != nil {
		t.Fatal(err)
	}
	rootPEM := e2eDartPublicTLS(t, s)
	result := runLiveGovernanceProbe(t, probe, map[string]any{
		"url": s.cPublic.URL, "certificatePem": string(rootPEM), "readerToken": f.reader, "ownerToken": f.owner,
		"channelId": f.channel, "otherChannelId": f.otherChannel, "exactPostId": f.exact, "bodyPostId": f.body, "otherPostId": f.other, "hotTopPostId": f.other,
	}, "post-search")
	if result["status"] != "PASS" {
		t.Fatal("Dart global hotlist and scoped search did not complete")
	}
}
