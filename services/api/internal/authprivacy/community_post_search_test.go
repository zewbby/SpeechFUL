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
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
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
	assertIDs(search(reader.SessionToken, posts.SearchQuery{Keyword: "旧", ChannelID: firstChannel}), firstTitle)
	assertIDs(search(reader.SessionToken, posts.SearchQuery{Keyword: "%", ChannelID: secondChannel}), otherTitle, otherBody)
	assertIDs(search(reader.SessionToken, posts.SearchQuery{Keyword: "_", ChannelID: secondChannel}), otherTitle, otherBody)
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

type searchCandidateTrace struct {
	start func(uint32)
	end   func()
}

type searchCandidateTraceKey struct{}

func (tr searchCandidateTrace) TraceQueryStart(ctx context.Context, conn *pgx.Conn, data pgx.TraceQueryStartData) context.Context {
	if strings.Contains(data.SQL, "WITH matched AS (") {
		if tr.start != nil {
			tr.start(conn.PgConn().PID())
		}
		return context.WithValue(ctx, searchCandidateTraceKey{}, true)
	}
	return ctx
}

func (tr searchCandidateTrace) TraceQueryEnd(ctx context.Context, _ *pgx.Conn, data pgx.TraceQueryEndData) {
	if data.Err == nil && ctx.Value(searchCandidateTraceKey{}) == true && tr.end != nil {
		tr.end()
	}
}

func tracePostSearch(t *testing.T, l *lab, trace searchCandidateTrace) *Community {
	t.Helper()
	c := *l.c
	cfg := c.pool.Config()
	cfg.ConnConfig.Tracer = trace
	pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	c.pool = pool
	return &c
}

func TestFeedPostSearchCandidateScanDoesNotHoldGatePostgres(t *testing.T) {
	l := newPostLab(t)
	searcher := sessionTestAccount(t, l, "search_slow_reader")
	other := sessionTestAccount(t, l, "search_other_reader")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	lock, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Rollback(context.Background())
	if _, err = lock.Exec(ctx, `LOCK TABLE c_posts.attempt_contents IN ACCESS EXCLUSIVE MODE`); err != nil {
		t.Fatal(err)
	}
	started := make(chan uint32, 1)
	search := tracePostSearch(t, l, searchCandidateTrace{start: func(pid uint32) { started <- pid }})
	done := make(chan error, 1)
	go func() {
		_, err := search.SearchPosts(ctx, searcher.SessionToken, posts.SearchQuery{Keyword: "blocked SQL"})
		done <- err
	}()
	var pid uint32
	select {
	case pid = <-started:
	case err := <-done:
		t.Fatalf("search stopped before candidate query: %v", err)
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	// Confirm that PostgreSQL itself is waiting for the table lock.
	for {
		var waiting bool
		err := l.cp.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_locks WHERE pid=$1 AND relation='c_posts.attempt_contents'::regclass AND NOT granted)`, int64(pid)).Scan(&waiting)
		if err != nil {
			t.Fatal(err)
		}
		if waiting {
			break
		}
		select {
		case err := <-done:
			t.Fatalf("candidate scan stopped before PostgreSQL lock wait: %v", err)
		case <-time.After(5 * time.Millisecond):
		}
	}
	readCtx, readCancel := context.WithTimeout(ctx, 2*time.Second)
	defer readCancel()
	if _, err := l.c.ReadPosts(readCtx, other.SessionToken, PostQuery{Kind: PostFeedPreferences}); err != nil {
		t.Fatalf("other account could not complete a Gate read during candidate SQL: %v", err)
	}
	select {
	case err := <-done:
		t.Fatalf("search stopped while candidate SQL was still blocked: %v", err)
	default:
	}
	if err := lock.Rollback(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatalf("search did not finish after releasing the table lock: %v", err)
	}
}

func TestFeedPostSearchFinalRevalidationPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "search_race_owner")
	reader := sessionTestAccount(t, l, "search_race_reader")
	channels := feedTestChannels(t, l)
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "搜索作者").IdentityID
	intent := postTestIntent(t, l, identity)
	publish := func(channel, title, body string) string {
		t.Helper()
		intent.ChannelID, intent.Title, intent.Body = channel, title, body
		result := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
		postTestPublish(t, l)
		return result.PostID
	}
	const term = "needle"
	first := publish(channels[0], term, "正文")
	second := publish(channels[0], "第一组正文命中", term)
	last := publish(channels[1], "第二组正文命中", term)
	third := publish(channels[2], "needle 第三组", "正文")
	leader := publish(channels[1], "needle 第二组", "正文")
	hide := func(post string) {
		t.Helper()
		mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, post)
	}
	block := func(ids []string) {
		t.Helper()
		if _, err := l.c.ReplaceFeedPreferences(ctx, reader.SessionToken, posts.FeedPreferences{BlockedChannelIDs: ids}); err != nil {
			t.Fatal(err)
		}
	}
	searchWithRace := func(t *testing.T, token [32]byte, query posts.SearchQuery, change func()) (PostResponse, error) {
		t.Helper()
		ran := false
		search := tracePostSearch(t, l, searchCandidateTrace{end: func() {
			if !ran {
				ran = true
				change()
			}
		}})
		response, err := search.SearchPosts(ctx, token, query)
		if !ran {
			t.Fatalf("search did not reach the candidate query: %v", err)
		}
		return response, err
	}
	pageFrom := func(t *testing.T, response PostResponse, err error) posts.FeedPage {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
		return response.Value.(posts.FeedPage)
	}
	assertNoHistory := func(t *testing.T, account uuid.UUID) {
		t.Helper()
		if n := count(t, l.cp, `SELECT count(*) FROM c_posts.post_search_history WHERE account_id=$1`, account); n != 0 {
			t.Fatalf("failed search committed history: %d", n)
		}
	}

	t.Run("reorders after an off-page group leader is hidden", func(t *testing.T) {
		query := posts.SearchQuery{Keyword: term, Limit: 1}
		response, err := searchWithRace(t, reader.SessionToken, query, func() { hide(leader) })
		page := pageFrom(t, response, err)
		for i, id := range []string{first, second, third, last} {
			if len(page.Items) != 1 || page.Items[0].PostID != id {
				t.Fatalf("page %d after group leader was hidden: %v", i, page.Items)
			}
			if i == 3 {
				if page.NextCursor != nil {
					t.Fatal("last visible page advertised a continuation")
				}
				break
			}
			if page.NextCursor == nil {
				t.Fatal("search lost a continuation")
			}
			query.Cursor = *page.NextCursor
			response, err = l.c.SearchPosts(ctx, reader.SessionToken, query)
			page = pageFrom(t, response, err)
		}
	})

	t.Run("refills a continuation after hide and delete", func(t *testing.T) {
		query := posts.SearchQuery{Keyword: term, Limit: 1}
		response, err := l.c.SearchPosts(ctx, reader.SessionToken, query)
		page := pageFrom(t, response, err)
		if page.NextCursor == nil {
			t.Fatal("missing fixture cursor")
		}
		query.Cursor = *page.NextCursor
		response, err = searchWithRace(t, reader.SessionToken, query, func() {
			hide(second)
			postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: third})
		})
		page = pageFrom(t, response, err)
		if len(page.Items) != 1 || page.Items[0].PostID != last || page.NextCursor != nil {
			t.Fatalf("unexpected continuation after candidate invalidation: %+v", page)
		}
	})

	t.Run("retries first page against changed blocks", func(t *testing.T) {
		query := posts.SearchQuery{Keyword: term, RecordHistory: true}
		response, err := searchWithRace(t, reader.SessionToken, query, func() { block([]string{channels[0]}) })
		page := pageFrom(t, response, err)
		if len(page.Items) != 1 || page.Items[0].PostID != last {
			t.Fatalf("search disclosed a newly blocked group: %+v", page)
		}
		history, err := l.c.ReadPostSearchHistory(ctx, reader.SessionToken, "")
		if err != nil || !slices.Equal(history.Value.(posts.SearchHistory).Items, []string{term}) {
			t.Fatalf("successful retry lost search history: %+v, %v", history, err)
		}
		block([]string{})
	})

	t.Run("rejects a continuation after block changes and reverts", func(t *testing.T) {
		query := posts.SearchQuery{Keyword: term, Limit: 1}
		response, err := l.c.SearchPosts(ctx, reader.SessionToken, query)
		page := pageFrom(t, response, err)
		if page.NextCursor == nil {
			t.Fatal("missing fixture cursor")
		}
		query.Cursor = *page.NextCursor
		response, err = searchWithRace(t, reader.SessionToken, query, func() {
			block([]string{channels[0]})
			block([]string{})
		})
		if response.Value != nil || !errors.Is(err, posts.ErrCursorInvalid) {
			t.Fatalf("stale cursor exposed a page: %+v, %v", response, err)
		}
	})

	t.Run("revoked session cannot release results or record history", func(t *testing.T) {
		revoked := sessionTestAccount(t, l, "search_race_revoked")
		query := posts.SearchQuery{Keyword: term, RecordHistory: true}
		response, err := searchWithRace(t, revoked.SessionToken, query, func() {
			if err := l.c.RevokeSession(ctx, SessionRevocationSecret(revoked.SessionToken)); err != nil {
				t.Fatal(err)
			}
		})
		if response.Value != nil || !errors.Is(err, ErrSessionInvalid) {
			t.Fatalf("revoked session completed search: %+v, %v", response, err)
		}
		assertNoHistory(t, revoked.AccountID)
		search := tracePostSearch(t, l, searchCandidateTrace{start: func(uint32) { t.Fatal("revoked session reached candidate scan") }})
		if _, err := search.SearchPosts(ctx, revoked.SessionToken, query); !errors.Is(err, ErrSessionInvalid) {
			t.Fatal(err)
		}
	})

	t.Run("recovered Gate rejects the old generation", func(t *testing.T) {
		query := posts.SearchQuery{Keyword: term, RecordHistory: true}
		previous := sessionTestAccount(t, l, "search_race_old_gate")
		response, err := searchWithRace(t, previous.SessionToken, query, func() {
			if err := l.gate.Freeze(ctx, "search race regression"); err != nil {
				t.Fatal(err)
			}
			control.recover(t, AuthorizationRecoveryBreakGlass, 3, 3)
		})
		if response.Value != nil || !errors.Is(err, ErrAuthorizationUnavailable) {
			t.Fatalf("old Gate generation completed search: %+v, %v", response, err)
		}
		assertNoHistory(t, previous.AccountID)
	})
}
