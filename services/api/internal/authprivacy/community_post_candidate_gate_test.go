package authprivacy

import (
	"bytes"
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type candidateCustomGate struct {
	AuthorizationGate
	called bool
}

func (g *candidateCustomGate) Snapshot(context.Context) (AuthorizationDecision, error) {
	g.called = true
	return AuthorizationDecision{Generation: 41}, nil
}

func TestPostCandidateCustomGateKeepsItsSnapshot(t *testing.T) {
	gate := &candidateCustomGate{}
	c := &Community{gate: gate}
	decision, err := c.postCandidateDecision(context.Background(), nil)
	if err != nil || !gate.called || decision.Generation != 41 {
		t.Fatal("candidate preparation replaced a custom authority source", err)
	}
}

func TestFeedPostSearchPreparationPreservesCheckpointAndFinalCommitPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	reader := sessionTestAccount(t, l, "candidate_time_reader")
	var oldTime time.Time
	var oldVersion int64
	if err := l.cp.QueryRow(ctx, `SELECT trusted_high_watermark,evidence_version FROM c_auth.authorization_gate WHERE singleton_id=1`).Scan(&oldTime, &oldVersion); err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile(l.gate.anchor.Path)
	if err != nil {
		t.Fatal(err)
	}
	advanceClosureClock(t, control, control.clock.now().Add(time.Minute))
	decision, err := l.c.postCandidateDecision(ctx, l.cp)
	if err != nil {
		t.Fatal(err)
	}
	if !decision.TrustedAt.After(oldTime) {
		t.Fatal("candidate decision did not use verified current time")
	}
	after, err := os.ReadFile(l.gate.anchor.Path)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatal("candidate read changed independent checkpoint", err)
	}
	var checkedTime time.Time
	var checkedVersion int64
	if err := l.cp.QueryRow(ctx, `SELECT trusted_high_watermark,evidence_version FROM c_auth.authorization_gate WHERE singleton_id=1`).Scan(&checkedTime, &checkedVersion); err != nil || !checkedTime.Equal(oldTime) || checkedVersion != oldVersion {
		t.Fatal("candidate read wrote the SQL checkpoint", err)
	}
	// The persisted checkpoint still precedes the end of this temporary ban.
	// Candidate preparation must use verified current time rather than that
	// stale checkpoint, or an already eligible reader would be rejected.
	mustExec(t, l.cp, `UPDATE c_auth.account_restrictions SET ban_state='BANNED',ban_ends_at=$2,version=version+1 WHERE account_id=$1`, reader.AccountID, oldTime.Add(30*time.Second))
	response, err := l.c.SearchPosts(ctx, reader.SessionToken, posts.SearchQuery{Keyword: "未命中的合成词"})
	if err != nil || response.ServerTime.Before(decision.TrustedAt) || !response.ExpiresAt.After(response.ServerTime) {
		t.Fatal("final search authority was not committed", err)
	}
	after, err = os.ReadFile(l.gate.anchor.Path)
	if err != nil || bytes.Equal(before, after) {
		t.Fatal("successful response did not advance the final checkpoint", err)
	}
	if err := l.gate.Freeze(ctx, "candidate preparation freeze regression"); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.SearchPosts(ctx, reader.SessionToken, posts.SearchQuery{Keyword: "冻结时不得返回"}); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("search ignored a frozen Gate", err)
	}
}

func TestFeedPostSearchFinalCursorUpperTimeBoundPostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	reader := sessionTestAccount(t, l, "cursor_final_clock")
	tx, err := l.cp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	// A cursor accepted at a later private sample cannot exceed the complete
	// TTL at the final authority time, even if the clock moved in between.
	at := control.clock.now()
	prepared := preparedPostSearch{position: posts.CursorPosition{ExpiresAt: at.Add(posts.CursorTTL + time.Second)}}
	_, err = l.c.finishPostSearch(ctx, tx, reader.AccountID, posts.SearchQuery{Cursor: "already-decoded", Limit: 20}, prepared, at)
	if !errors.Is(err, posts.ErrCursorInvalid) {
		t.Fatal("final time did not bound the cursor TTL", err)
	}
}

func TestFeedPostSearchPreparationPersistsDetectedFreezePostgres(t *testing.T) {
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	// Retire the setup's recovery proof, then make valid online evidence
	// expire while the persisted Gate is still OPEN.
	if _, err := l.gate.Snapshot(ctx); err != nil {
		t.Fatal(err)
	}
	control.clock.set(control.clock.now().Add(5*time.Minute + time.Nanosecond))
	if _, err := l.c.postCandidateDecision(ctx, l.cp); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("candidate preparation accepted expired evidence", err)
	}
	var state string
	if err := l.cp.QueryRow(ctx, `SELECT gate_state FROM c_auth.authorization_gate WHERE singleton_id=1`).Scan(&state); err != nil || state != "FROZEN" {
		t.Fatal("detected freeze did not survive the candidate rollback", state, err)
	}
	if err := l.gate.anchor.withLocked(func(anchor *authorizationAnchor, exists bool) error {
		if !exists || !anchor.Frozen {
			t.Fatal("independent anchor did not preserve the detected freeze")
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	restarted, err := NewPostgresAuthorizationGate(control.config)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := restarted.Snapshot(ctx); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("new Gate instance erased the detected freeze", err)
	}
}
