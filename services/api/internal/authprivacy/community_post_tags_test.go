package authprivacy

import (
	"context"
	"errors"
	"reflect"
	"testing"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func TestFeedPostTagsReportEvidenceRetainsOriginalPostgres(t *testing.T) {
	l := moderationLab(t)
	ctx := context.Background()
	owner := moderationActor(t, l, "tag_report_owner", "")
	reader := moderationActor(t, l, "tag_report_reader", "")
	reviewer := moderationActor(t, l, "tag_report_reviewer", "REVIEWER")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "标签证据").IdentityID
	intent := postTestIntent(t, l, identity)
	intent.Tags = []string{"篮球"}
	accepted := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	postTestPublish(t, l)
	report, err := l.c.SubmitReport(ctx, reader.SessionToken, uuid.NewString(), moderation.ReportInput{PostID: accepted.PostID, Reason: "OTHER", Images: []moderation.Image{}})
	if err != nil {
		t.Fatal(err)
	}
	read, err := l.c.ReadPostEdit(ctx, owner.SessionToken, accepted.PostID)
	if err != nil {
		t.Fatal(err)
	}
	snapshot := read.Value.(posts.EditSnapshot)
	replacement := []string{"食堂"}
	saved, err := l.c.SavePostEdit(ctx, owner.SessionToken, accepted.PostID, postTestKey(t), posts.EditInput{Revision: snapshot.Revision, Title: snapshot.Post.Title, Body: snapshot.Post.Body, Tags: &replacement})
	if err != nil || saved.Value.(posts.EditResult).State != "SAVED" {
		t.Fatal(err)
	}
	detail, err := l.c.ReadModeration(ctx, reviewer.SessionToken, "case", report.Value.(moderation.ReportResult).Report.CaseID, "", "", 50)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(detail.Value.(moderation.Case).Evidence.Tags, []string{"篮球"}) {
		t.Fatal("editing changed the original report label evidence")
	}
	postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: accepted.PostID})
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_tag_terms WHERE post_id=$1`, accepted.PostID) != 0 {
		t.Fatal("deleted labels retained in suggestions")
	}
}

func TestFeedPostTagsPublishEditSearchAndPagingPostgres(t *testing.T) {
	l := newPostLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "tags_owner")
	reader := sessionTestAccount(t, l, "tags_reader")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "标签作者").IdentityID
	channels := feedTestChannels(t, l)
	publish := func(channel string, tags []string) string {
		intent := postTestIntent(t, l, identity)
		intent.ChannelID = channel
		intent.Tags = tags
		accepted := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
		if accepted.State != "ACCEPTED" {
			t.Fatal("tagged post not accepted", accepted)
		}
		postTestPublish(t, l)
		return accepted.PostID
	}
	first := publish(channels[0], []string{"篮球", "NBA"})
	second := publish(channels[1], []string{"篮球"})
	publish(channels[0], []string{"篮球比赛"})
	publish(channels[0], nil)
	publish(channels[0], []string{"A_B"})
	publish(channels[0], []string{"A8B"})
	page := func(query posts.TagQuery) posts.FeedPage {
		r, err := l.c.TaggedPosts(ctx, reader.SessionToken, query)
		if err != nil {
			t.Fatal(err)
		}
		return r.Value.(posts.FeedPage)
	}
	assertIDs := func(p posts.FeedPage, want ...string) {
		t.Helper()
		ids := []string{}
		for _, p := range p.Items {
			ids = append(ids, p.PostID)
		}
		if len(ids) != len(want) || len(ids) > 0 && !reflect.DeepEqual(ids, want) {
			t.Fatalf("tag page %v, want %v", ids, want)
		}
	}
	assertIDs(page(posts.TagQuery{Tag: "篮球"}), second, first)
	assertIDs(page(posts.TagQuery{Tag: "篮球", ChannelID: channels[0]}), first)
	firstPage := page(posts.TagQuery{Tag: "篮球", Limit: 1})
	assertIDs(firstPage, second)
	if firstPage.NextCursor == nil {
		t.Fatal("missing continuation")
	}
	publish(channels[0], []string{"篮球"})
	assertIDs(page(posts.TagQuery{Tag: "篮球", Limit: 1, Cursor: *firstPage.NextCursor}), first)
	if _, err := l.c.TaggedPosts(ctx, reader.SessionToken, posts.TagQuery{Tag: "NBA", Limit: 1, Cursor: *firstPage.NextCursor}); !errors.Is(err, posts.ErrCursorInvalid) {
		t.Fatal("cursor accepted different tag", err)
	}
	result, err := l.c.SearchPosts(ctx, reader.SessionToken, posts.SearchQuery{Keyword: "nba"})
	if err != nil {
		t.Fatal(err)
	}
	assertIDs(result.Value.(posts.FeedPage), first)
	suggestions, err := l.c.SuggestPostTags(ctx, reader.SessionToken, "n")
	if err != nil || !reflect.DeepEqual(suggestions.Value.(posts.TagSuggestions).Items, []string{"NBA"}) {
		t.Fatal("visible suggestions", suggestions, err)
	}
	literal, err := l.c.SuggestPostTags(ctx, reader.SessionToken, "a_")
	if err != nil || !reflect.DeepEqual(literal.Value.(posts.TagSuggestions).Items, []string{"A_B"}) {
		t.Fatal("underscore was treated as a wildcard", err)
	}
	_, err = l.c.ReplaceFeedPreferences(ctx, reader.SessionToken, posts.FeedPreferences{BlockedChannelIDs: []string{channels[1]}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.TaggedPosts(ctx, reader.SessionToken, posts.TagQuery{Tag: "篮球", Limit: 1, Cursor: *firstPage.NextCursor}); !errors.Is(err, posts.ErrCursorInvalid) {
		t.Fatal("cursor survived preference change", err)
	}
	assertIDs(page(posts.TagQuery{Tag: "篮球", ChannelID: channels[1]}))
	read, err := l.c.ReadPostEdit(ctx, owner.SessionToken, first)
	if err != nil {
		t.Fatal(err)
	}
	snapshot := read.Value.(posts.EditSnapshot)
	if !reflect.DeepEqual(snapshot.Post.Tags, []string{"篮球", "NBA"}) {
		t.Fatal("public tags lost", snapshot.Post.Tags)
	}
	replacement := []string{"食堂"}
	saved, err := l.c.SavePostEdit(ctx, owner.SessionToken, first, postTestKey(t), posts.EditInput{Revision: snapshot.Revision, Title: snapshot.Post.Title, Body: snapshot.Post.Body, Tags: &replacement})
	if err != nil || saved.Value.(posts.EditResult).State != "SAVED" {
		t.Fatal("tag edit", saved, err)
	}
	assertIDs(page(posts.TagQuery{Tag: "NBA"}))
	assertIDs(page(posts.TagQuery{Tag: "食堂"}), first)
	read, err = l.c.ReadPostEdit(ctx, owner.SessionToken, first)
	if err != nil {
		t.Fatal(err)
	}
	snapshot = read.Value.(posts.EditSnapshot)
	// Old clients omitting tags retain the current labels.
	saved, err = l.c.SavePostEdit(ctx, owner.SessionToken, first, postTestKey(t), posts.EditInput{Revision: snapshot.Revision, Title: snapshot.Post.Title, Body: snapshot.Post.Body})
	if err != nil || saved.Value.(posts.EditResult).State != "SAVED" {
		t.Fatal(err)
	}
	assertIDs(page(posts.TagQuery{Tag: "食堂"}), first)
	read, err = l.c.ReadPostEdit(ctx, owner.SessionToken, first)
	if err != nil {
		t.Fatal(err)
	}
	snapshot = read.Value.(posts.EditSnapshot)
	replacement = []string{}
	saved, err = l.c.SavePostEdit(ctx, owner.SessionToken, first, postTestKey(t), posts.EditInput{Revision: snapshot.Revision, Title: snapshot.Post.Title, Body: snapshot.Post.Body, Tags: &replacement})
	if err != nil || saved.Value.(posts.EditResult).State != "SAVED" {
		t.Fatal(err)
	}
	assertIDs(page(posts.TagQuery{Tag: "食堂"}))
	// Downed posts disappear from exact results and suggestions immediately.
	mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, second)
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_tag_terms WHERE post_id=$1`, second) != 0 {
		t.Fatal("hidden tag suggestion survived")
	}
	if _, err := l.c.TaggedPosts(ctx, [32]byte{}, posts.TagQuery{Tag: "篮球"}); err == nil {
		t.Fatal("unauthenticated tag read accepted")
	}
}
