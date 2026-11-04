package authprivacy

import (
	"context"
	"errors"
	"fmt"
	"os"
	"slices"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func TestFeedPostSearchHistoryLifecyclePostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	owner := sessionTestAccount(t, l, "search_history_owner")
	other := sessionTestAccount(t, l, "search_history_other")
	channels := feedTestChannels(t, l)
	identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "First")
	identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "Second")

	record := func(bearer [32]byte, channel, keyword string) error {
		_, err := l.c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
			return nil, recordPostSearchHistory(ctx, tx, account, channel, keyword, final.TrustedAt)
		})
		return err
	}
	save := func(bearer [32]byte, channel, keyword string) {
		t.Helper()
		if err := record(bearer, channel, keyword); err != nil {
			t.Fatal(err)
		}
	}
	read := func(bearer [32]byte, channel string) []string {
		t.Helper()
		response, err := l.c.ReadPostSearchHistory(ctx, bearer, channel)
		if err != nil || response.ServerTime.IsZero() || !response.ExpiresAt.After(response.ServerTime) {
			t.Fatal("history omitted session authority", err)
		}
		history, ok := response.Value.(posts.SearchHistory)
		if !ok || history.Items == nil {
			t.Fatal("history did not return an array")
		}
		return history.Items
	}
	assertHistory := func(bearer [32]byte, channel string, expected ...string) {
		t.Helper()
		if actual := read(bearer, channel); !slices.Equal(actual, expected) {
			t.Fatalf("history order/content = %q, want %q", actual, expected)
		}
	}

	// Use the real least-privilege runtime for history and later account closure.
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	grant, err := os.ReadFile("../../../../infra/postgres/grant-community.sql")
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, string(grant))
	runtime, err := pgxpool.New(ctx, os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN"))
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	clone := *l.c
	clone.pool = runtime
	l.c = &clone
	if err = l.c.CheckPostSchema(ctx); err != nil {
		t.Fatal(err)
	}

	assertHistory(owner.SessionToken, "")
	save(owner.SessionToken, "", "all")
	save(owner.SessionToken, channels[1], "other channel")
	save(other.SessionToken, channels[0], "private")
	for i := 0; i < 21; i++ {
		save(owner.SessionToken, channels[0], fmt.Sprintf("Word %02d", i))
	}
	save(owner.SessionToken, channels[0], " word 01 ")
	expected := []string{"word 01"}
	for i := 20; i >= 2; i-- {
		expected = append(expected, fmt.Sprintf("Word %02d", i))
	}
	assertHistory(owner.SessionToken, channels[0], expected...)
	if got := count(t, l.cp, `SELECT count(*) FROM c_posts.post_search_history WHERE account_id=$1 AND channel_id=$2`, owner.AccountID, channels[0]); got != posts.SearchHistoryLimit {
		t.Fatalf("storage retained %d words, want %d", got, posts.SearchHistoryLimit)
	}
	assertHistory(owner.SessionToken, "", "all")
	assertHistory(owner.SessionToken, channels[1], "other channel")
	assertHistory(other.SessionToken, channels[0], "private")
	assertHistory(other.SessionToken, "")

	// The second device replaces the first under the existing session rules.
	renewed, err := l.c.CreateSession(ctx, sessionTestRequest(t, "search_history_owner"), sessionTestPasswordWorker(t, 1))
	if err != nil || renewed.AccountID != owner.AccountID {
		t.Fatal("second device login", err)
	}
	if _, err = l.c.ReadPostSearchHistory(ctx, owner.SessionToken, ""); !errors.Is(err, ErrSessionReplaced) {
		t.Fatal("replaced device read private history", err)
	}
	if err = record(owner.SessionToken, "", "stale"); !errors.Is(err, ErrSessionReplaced) {
		t.Fatal("replaced device wrote private history", err)
	}
	assertHistory(renewed.SessionToken, channels[0], expected...)
	assertHistory(renewed.SessionToken, "", "all")
	removed, err := l.c.ChangePostSearchHistory(ctx, renewed.SessionToken, posts.SearchHistoryChange{
		Action: "remove", ChannelID: channels[0], Keyword: "WORD 01",
	})
	if err != nil || !slices.Equal(removed.Value.(posts.SearchHistory).Items, expected[1:]) {
		t.Fatal("remove failed", err)
	}
	cleared, err := l.c.ChangePostSearchHistory(ctx, renewed.SessionToken, posts.SearchHistoryChange{Action: "clear", ChannelID: channels[0]})
	if err != nil || cleared.Value.(posts.SearchHistory).Items == nil || len(cleared.Value.(posts.SearchHistory).Items) != 0 {
		t.Fatal("clear failed", err)
	}
	assertHistory(renewed.SessionToken, "", "all")
	assertHistory(renewed.SessionToken, channels[1], "other channel")
	assertHistory(other.SessionToken, channels[0], "private")
	_, err = l.c.ReadPostSearchHistory(ctx, renewed.SessionToken, uuid.NewString())
	postTestError(t, err, "POST_CHANNEL_UNAVAILABLE", 404)

	// Formal closure remains active with all post HTTP features disabled.
	authOnly := *l.c
	authOnly.posts = nil
	request, _ := closureTestRequest(t, renewed.SessionToken)
	closure, err := authOnly.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
	if err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_search_history WHERE account_id=$1`, owner.AccountID) != 2 {
		t.Fatal("pending closure cleared history")
	}
	advanceClosureClock(t, control, closure.DueAt)
	if n, err := authOnly.FinalizeDueClosures(ctx, 10); err != nil || n != 1 {
		t.Fatal("formal closure", n, err)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_search_history WHERE account_id=$1`, owner.AccountID) != 0 {
		t.Fatal("formal closure retained private history")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.post_search_history WHERE account_id=$1`, other.AccountID) != 1 {
		t.Fatal("formal closure removed another account's history")
	}
}

func TestFeedPostSearchHistorySchemaAndGatePostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "search_history_guard")
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	grant, err := os.ReadFile("../../../../infra/postgres/grant-community.sql")
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, l.cp, string(grant))
	runtime, err := pgxpool.New(ctx, os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN"))
	if err != nil {
		t.Fatal(err)
	}
	defer runtime.Close()
	if err = CheckModerationLifecycleSchema(ctx, runtime); err != nil {
		t.Fatal(err)
	}
	for _, defect := range []struct{ introduce, fix string }{
		{`ALTER TABLE c_auth.accounts DISABLE TRIGGER post_search_history_account_closed`, `ALTER TABLE c_auth.accounts ENABLE TRIGGER post_search_history_account_closed`},
		{`REVOKE DELETE ON c_posts.post_search_history FROM hnuhole_c_runtime`, `GRANT DELETE ON c_posts.post_search_history TO hnuhole_c_runtime`},
		{`GRANT UPDATE(channel_id) ON c_posts.post_search_history TO hnuhole_c_runtime`, `REVOKE UPDATE(channel_id) ON c_posts.post_search_history FROM hnuhole_c_runtime`},
	} {
		mustExec(t, l.cp, defect.introduce)
		if err = CheckModerationLifecycleSchema(ctx, runtime); !errors.Is(err, errPostSchema) {
			t.Fatal("common startup accepted missing or excessive history permissions or hook", err)
		}
		mustExec(t, l.cp, defect.fix)
	}
	if err = CheckModerationLifecycleSchema(ctx, runtime); err != nil {
		t.Fatal(err)
	}
	if count(t, l.cp, `SELECT count(*) FROM (VALUES ('hnuhole_c_recovery'),('hnuhole_business')) AS role(name)
 WHERE has_table_privilege(role.name,'c_posts.post_search_history','SELECT,INSERT,UPDATE,DELETE')`) != 0 {
		t.Fatal("private history accessible to recovery or business")
	}

	rejected := errors.New("synthetic rejection after recording")
	_, err = l.c.withPostSession(ctx, owner.SessionToken, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
		if err := recordPostSearchHistory(ctx, tx, account, "", "rollback", final.TrustedAt); err != nil {
			return nil, err
		}
		return nil, rejected
	})
	if !errors.Is(err, rejected) || count(t, l.cp, `SELECT count(*) FROM c_posts.post_search_history`) != 0 {
		t.Fatal("failed search committed partial history", err)
	}
	if err = l.gate.Freeze(ctx, "search history regression"); err != nil {
		t.Fatal(err)
	}
	if _, err = l.c.ReadPostSearchHistory(ctx, owner.SessionToken, ""); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("frozen gate served history", err)
	}
	if _, err = l.c.ChangePostSearchHistory(ctx, owner.SessionToken, posts.SearchHistoryChange{Action: "clear"}); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("frozen gate accepted history mutation", err)
	}
}
