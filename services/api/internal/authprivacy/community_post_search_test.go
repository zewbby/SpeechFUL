package authprivacy

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func TestFeedPostSearchScopeRankingAndStablePagesPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "post_search_owner")
	reader := sessionTestAccount(t, l, "post_search_reader")
	other := sessionTestAccount(t, l, "post_search_other")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "搜索作者").IdentityID
	channels := feedTestChannels(t, l)
	firstChannel, secondChannel := channels[0], channels[1]
	intent := postTestIntent(t, l, identity)
	accept := func(channel, title, body string) string {
		t.Helper()
		intent.ChannelID, intent.Title, intent.Body = channel, title, body
		accepted := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
		if accepted.State != "ACCEPTED" || accepted.PostID == "" {
			t.Fatalf("fixture post was rejected: %v", accepted)
		}
		return accepted.PostID
	}
	publish := func(channel, title, body string) string {
		t.Helper()
		id := accept(channel, title, body)
		postTestPublish(t, l)
		return id
	}
	step := func() {
		t.Helper()
		advanceClosureClock(t, control, control.clock.now().Add(time.Minute))
	}
	hide := func(id string) {
		t.Helper()
		mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, id)
	}
	remove := func(id string) {
		t.Helper()
		postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: id})
	}
	const term = "Ärger %_"
	exact := publish(firstChannel, "ÄRGER %_", "公开正文")
	step()
	firstTitle := publish(firstChannel, "关于 Ärger %_ 旧", "公开正文")
	secondTitle := publish(firstChannel, "关于 ärger %_ 新", "公开正文")
	step()
	otherTitle := publish(secondChannel, "分类 Ärger %_ 帖", "公开正文")
	step()
	firstBody := publish(firstChannel, "正文命中", "这里有 ärger %_ 字样")
	step()
	otherBody := publish(secondChannel, "最新的正文命中", "这里也有 ÄRGER %_ 字样")
	hide(publish(secondChannel, term, "下架内容"))
	remove(publish(firstChannel, term, "已删除内容"))
	publish(firstChannel, "讨论 Ärger XX", "百分号与下划线是字面字符")
	accept(secondChannel, term, "发布前不可见")

	search := func(bearer [32]byte, query posts.SearchQuery) posts.FeedPage {
		t.Helper()
		result, err := l.c.SearchPosts(ctx, bearer, query)
		if err != nil {
			t.Fatal(err)
		}
		if result.ServerTime.IsZero() || !result.ExpiresAt.After(result.ServerTime) {
			t.Fatal("missing search read authorization")
		}
		page, ok := result.Value.(posts.FeedPage)
		if !ok || page.Items == nil {
			t.Fatal("missing public search page")
		}
		return page
	}
	assertIDs := func(page posts.FeedPage, expected ...string) {
		t.Helper()
		ids := make([]string, 0, len(page.Items))
		for _, item := range page.Items {
			ids = append(ids, item.PostID)
		}
		if !slices.Equal(ids, expected) {
			t.Fatalf("post ids = %v; want %v", ids, expected)
		}
	}

	page := search(reader.SessionToken, posts.SearchQuery{Keyword: "  " + term + "　"})
	assertIDs(page, exact, secondTitle, firstTitle, firstBody, otherTitle, otherBody)
	if page.NextCursor != nil || !page.Items[1].PublishedAt.Equal(page.Items[2].PublishedAt) {
		t.Fatal("first page or same-time ordinal fixture invalid")
	}
	wire, err := json.Marshal(page)
	if err != nil {
		t.Fatal(err)
	}
	for _, private := range []string{"\"body\"", "\"accountId\"", "\"identityId\"", owner.AccountID.String(), identity.String()} {
		if strings.Contains(string(wire), private) {
			t.Fatal("non-card data escaped in search response")
		}
	}

	assertIDs(search(reader.SessionToken, posts.SearchQuery{Keyword: term, Sort: posts.SearchLatest}),
		otherBody, otherTitle, firstBody, secondTitle, firstTitle, exact)
	latest := posts.SearchQuery{Keyword: term, Sort: posts.SearchLatest, Limit: 1}
	page = search(reader.SessionToken, latest)
	assertIDs(page, otherBody)
	if page.NextCursor == nil {
		t.Fatal("missing latest cursor")
	}
	latest.Cursor = *page.NextCursor
	assertIDs(search(reader.SessionToken, latest), otherTitle)
	assertIDs(search(reader.SessionToken, posts.SearchQuery{Keyword: term, ChannelID: secondChannel}), otherTitle, otherBody)
	assertIDs(search(reader.SessionToken, posts.SearchQuery{Keyword: "没有这个词"}))
	_, err = l.c.SearchPosts(ctx, [32]byte{}, posts.SearchQuery{Keyword: term})
	if !errors.Is(err, ErrSessionInvalid) {
		t.Fatal("unauthenticated search accepted", err)
	}
	_, err = l.c.SearchPosts(ctx, reader.SessionToken, posts.SearchQuery{Keyword: term, ChannelID: uuid.NewString()})
	postTestError(t, err, "POST_CHANNEL_UNAVAILABLE", 404)

	query := posts.SearchQuery{Keyword: term, Limit: 1}
	page = search(reader.SessionToken, query)
	assertIDs(page, exact)
	if page.NextCursor == nil {
		t.Fatal("missing next search cursor")
	}
	query.Cursor = *page.NextCursor
	for name, change := range map[string]func(*posts.SearchQuery){
		"keyword": func(q *posts.SearchQuery) { q.Keyword = "其他" },
		"sort":    func(q *posts.SearchQuery) { q.Sort = posts.SearchLatest },
		"scope":   func(q *posts.SearchQuery) { q.ChannelID = firstChannel },
		"limit":   func(q *posts.SearchQuery) { q.Limit = 2 },
	} {
		wrong := query
		change(&wrong)
		if _, err := l.c.SearchPosts(ctx, reader.SessionToken, wrong); !errors.Is(err, posts.ErrCursorInvalid) {
			t.Fatalf("cursor accepted after %s changed: %v", name, err)
		}
	}
	if _, err := l.c.SearchPosts(ctx, other.SessionToken, query); !errors.Is(err, posts.ErrCursorInvalid) {
		t.Fatal("cursor crossed account", err)
	}
	if _, err := l.c.ReadPosts(ctx, reader.SessionToken, PostQuery{Kind: PostFeed, Limit: 1, Cursor: query.Cursor}); !errors.Is(err, posts.ErrCursorInvalid) {
		t.Fatal("search cursor crossed into feed", err)
	}
	replayed := query
	replayed.RecordHistory = true
	if _, err := l.c.SearchPosts(ctx, reader.SessionToken, replayed); !errors.Is(err, posts.ErrInvalidIntent) {
		t.Fatal("cursor accepted with history recording", err)
	}

	// A new exact hit and the pending post both publish above the initial ceiling.
	// Once the leading exact hit is hidden, the first group would rank below
	// the second if group order were recomputed. An unseen deletion creates no gap.
	step()
	publish(secondChannel, term, "后来发布的帖子")
	hide(exact)
	remove(secondTitle)
	continuation := query
	expected := []string{firstTitle, firstBody, otherTitle, otherBody}
	for i, id := range expected {
		page = search(reader.SessionToken, continuation)
		assertIDs(page, id)
		if i < len(expected)-1 {
			if page.NextCursor == nil {
				t.Fatal("continuation lost eligible posts")
			}
			continuation.Cursor = *page.NextCursor
		} else if page.NextCursor != nil {
			t.Fatal("unexpected post beyond the original snapshot")
		}
	}
	if _, err := l.c.ReplaceFeedPreferences(ctx, reader.SessionToken, posts.FeedPreferences{
		BlockedChannelIDs: []string{secondChannel},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.SearchPosts(ctx, reader.SessionToken, query); !errors.Is(err, posts.ErrCursorInvalid) {
		t.Fatal("cursor survived changed account visibility preferences", err)
	}
	assertIDs(search(reader.SessionToken, posts.SearchQuery{Keyword: term}), firstTitle, firstBody)
	assertIDs(search(reader.SessionToken, posts.SearchQuery{Keyword: term, ChannelID: secondChannel}))
}
