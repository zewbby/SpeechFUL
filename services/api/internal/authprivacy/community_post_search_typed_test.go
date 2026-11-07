package authprivacy

import (
	"context"
	"crypto/sha256"
	"errors"
	"reflect"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func TestFeedPostSearchTypedMatchesCompatiblePostgres(t *testing.T) {
	l := newPostLab(t)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "typed_search_owner")
	reader := sessionTestAccount(t, l, "typed_search_reader")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "搜索作者").IdentityID
	channels := feedTestChannels(t, l)
	var edited, tagged string
	for i, content := range []struct {
		title, body string
		tags        []string
	}{{"common 原标题", "原正文", nil}, {"只在标签命中 Σ", "正文", []string{"NBA", "篮球", "A_B"}},
		{"另一分类 common", "正文", nil}, {"待编辑", "旧正文", []string{"其他"}}} {
		intent := postTestIntent(t, l, identity)
		intent.ChannelID, intent.Title, intent.Body, intent.Tags = channels[i%2], content.title, content.body, content.tags
		created := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
		postTestPublish(t, l)
		edited = created.PostID
		if i == 1 {
			tagged = created.PostID
		}
	}
	read, err := l.c.ReadPostEdit(ctx, owner.SessionToken, edited)
	if err != nil {
		t.Fatal(err)
	}
	snapshot := read.Value.(posts.EditSnapshot)
	saved, err := l.c.SavePostEdit(ctx, owner.SessionToken, edited, postTestKey(t), posts.EditInput{
		Revision: snapshot.Revision, Title: "编辑 common", Body: "编辑正文",
	})
	if err != nil || saved.Value.(posts.EditResult).State != "SAVED" {
		t.Fatalf("edit result=%+v err=%v", saved.Value, err)
	}
	if !l.c.posts.typedSearchEnabled {
		t.Fatal("current schema did not enable checked direct-column search")
	}
	compat, service := *l.c, *l.c.posts
	service.typedSearchEnabled = false
	compat.posts = &service
	for _, keyword := range []string{"common", "nba", "σ", "_", "旧正文"} {
		for _, scope := range []string{"", channels[1]} {
			for _, sort := range []string{posts.SearchRelevance, posts.SearchLatest} {
				a := posts.SearchQuery{Keyword: keyword, ChannelID: scope, Sort: sort, Limit: 1}
				b := a
				for page := 0; ; page++ {
					if page > 4 {
						t.Fatal("search cursor did not terminate")
					}
					direct, err := l.c.SearchPosts(ctx, reader.SessionToken, a)
					if err != nil {
						t.Fatal(err)
					}
					legacy, err := compat.SearchPosts(ctx, reader.SessionToken, b)
					if err != nil {
						t.Fatal(err)
					}
					x, y := direct.Value.(posts.FeedPage), legacy.Value.(posts.FeedPage)
					if !reflect.DeepEqual(x.Items, y.Items) || (x.NextCursor == nil) != (y.NextCursor == nil) {
						t.Fatalf("typed/compatible search differs: keyword=%q scope=%q sort=%s page=%d", keyword, scope, sort, page)
					}
					if keyword == "旧正文" && len(x.Items) != 0 {
						t.Fatal("edited body still matched the original body")
					}
					for _, item := range x.Items {
						if item.PostID == edited && item.Title != "编辑 common" {
							t.Fatal("search lost the edited title")
						}
					}
					if x.NextCursor == nil {
						break
					}
					a.Cursor, b.Cursor = *x.NextCursor, *y.NextCursor
				}
			}
		}
	}
	// A tag-only hit removed after candidate preparation must be rejected at
	// the final authority point in both SQL variants, never released as stale.
	decision, err := l.c.postCandidateDecision(ctx, l.cp)
	if err != nil {
		t.Fatal(err)
	}
	query := posts.SearchQuery{Keyword: "nba", Sort: posts.SearchRelevance, Limit: 20}
	prepared, err := l.c.preparePostSearch(ctx, reader.AccountID, query, decision.TrustedAt)
	if err != nil || len(prepared.candidates) != 1 {
		t.Fatal("missing tag-only preparation", err)
	}
	read, err = l.c.ReadPostEdit(ctx, owner.SessionToken, tagged)
	if err != nil {
		t.Fatal(err)
	}
	snapshot = read.Value.(posts.EditSnapshot)
	cleared := []string{}
	saved, err = l.c.SavePostEdit(ctx, owner.SessionToken, tagged, postTestKey(t), posts.EditInput{
		Revision: snapshot.Revision, Title: snapshot.Post.Title, Body: snapshot.Post.Body, Tags: &cleared,
	})
	if err != nil || saved.Value.(posts.EditResult).State != "SAVED" {
		t.Fatalf("tag edit result=%+v err=%v", saved.Value, err)
	}
	token := sha256.Sum256(reader.SessionToken[:])
	for _, c := range []*Community{l.c, &compat} {
		_, err := c.withPostSessionAt(ctx, token, reader.AccountID, decision, nil,
			func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
				return c.finishPostSearch(ctx, tx, account, query, prepared, final.TrustedAt)
			})
		if !errors.Is(err, errPostSearchChanged) {
			t.Fatal("final search released a removed tag candidate", err)
		}
	}
}
