package authprivacy

import (
	"context"
	"crypto/sha256"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type postSessionCommitGate struct {
	AuthorizationGate
	commits, aborts int
}

func (g *postSessionCommitGate) CommitAuthorized(ctx context.Context, tx pgx.Tx, generation uint64, checks ...func(AuthorizationDecision) error) (AuthorizationDecision, error) {
	g.commits++
	return g.AuthorizationGate.CommitAuthorized(ctx, tx, generation, checks...)
}

func (g *postSessionCommitGate) Abort(ctx context.Context, tx pgx.Tx) error {
	g.aborts++
	return g.AuthorizationGate.Abort(ctx, tx)
}

func TestFeedPostSessionCommitCleanupPostgres(t *testing.T) {
	for _, mode := range []string{"success", "rejected", "panic", "expired"} {
		t.Run(mode, func(t *testing.T) {
			control := newGateControl(t)
			l, ctx := control.lab, context.Background()
			enablePostLab(t, l)
			reader := sessionTestAccount(t, l, "post_commit_cleanup")
			token := sha256.Sum256(reader.SessionToken[:])
			// Exercise actual renewal rather than an unchanged fresh session.
			mustExec(t, l.cp, `UPDATE c_auth.sessions SET expires_at=$2 WHERE token_digest=$1`, token[:], control.clock.now().Add(time.Hour))
			var oldTime, oldExpiry time.Time
			if err := l.cp.QueryRow(ctx, `SELECT trusted_high_watermark,(SELECT expires_at FROM c_auth.sessions WHERE token_digest=$1)
				FROM c_auth.authorization_gate WHERE singleton_id=1`, token[:]).Scan(&oldTime, &oldExpiry); err != nil {
				t.Fatal(err)
			}
			advanceClosureClock(t, control, control.clock.now().Add(time.Minute))
			decision, err := l.c.postCandidateDecision(ctx, l.cp)
			if err != nil {
				t.Fatal(err)
			}
			gate := &postSessionCommitGate{AuthorizationGate: l.gate}
			l.c.gate = gate
			account := reader.AccountID
			if mode == "expired" {
				control.clock.set(control.clock.now().Add(5*time.Minute + time.Nanosecond))
			}
			called := false
			var panicValue any
			panicSentinel := errors.New("synthetic action panic")
			var response PostResponse
			rejected := errors.New("synthetic rejected action")
			func() {
				defer func() { panicValue = recover() }()
				response, err = l.c.withPostSessionAt(ctx, token, account, decision, nil,
					func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
						called = true
						if e := recordPostSearchHistory(ctx, tx, account, "", "cleanup check", final.TrustedAt); e != nil {
							return nil, e
						}
						if mode == "panic" {
							panic(panicSentinel)
						}
						if mode == "rejected" {
							return nil, rejected
						}
						return posts.SearchHistory{}, nil
					})
			}()
			wantAbort, wantHistory := 1, 0
			if mode == "success" {
				wantAbort, wantHistory = 0, 1
				if err != nil || !response.ExpiresAt.After(response.ServerTime) || response.ServerTime.Before(decision.TrustedAt) {
					t.Fatal("successful final transaction did not renew the session", err)
				}
				var highwater, expiry time.Time
				if err := l.cp.QueryRow(ctx, `SELECT trusted_high_watermark,(SELECT expires_at FROM c_auth.sessions WHERE token_digest=$1)
					FROM c_auth.authorization_gate WHERE singleton_id=1`, token[:]).Scan(&highwater, &expiry); err != nil ||
					!highwater.Equal(response.ServerTime) || !expiry.Equal(response.ExpiresAt) ||
					!highwater.After(oldTime) || !expiry.After(oldExpiry) {
					t.Fatal("successful response did not persist checkpoint and expiry", err)
				}
			} else if mode == "rejected" && !errors.Is(err, rejected) {
				t.Fatal("lost action failure", err)
			} else if mode == "expired" && (!errors.Is(err, ErrAuthorizationUnavailable) || called) {
				t.Fatal("expired final authority released business action", err)
			}
			if (mode == "panic" && panicValue != panicSentinel) || (mode != "panic" && panicValue != nil) ||
				called != (mode != "expired") || gate.commits != 1 || gate.aborts != wantAbort {
				t.Fatalf("cleanup lifecycle: panic=%v called=%t commits=%d aborts=%d", panicValue, called, gate.commits, gate.aborts)
			}
			if got := count(t, l.cp, `SELECT count(*) FROM c_posts.post_search_history`); got != wantHistory {
				t.Fatalf("history commit/rollback mismatch: got %d, want %d", got, wantHistory)
			}
			if mode == "expired" {
				if err := l.gate.anchor.withLocked(func(a *authorizationAnchor, exists bool) error {
					if !exists || !a.Frozen {
						t.Fatal("failure lost independent anchor freeze")
					}
					return nil
				}); err != nil {
					t.Fatal(err)
				}
				var state string
				if err := l.cp.QueryRow(ctx, `SELECT gate_state FROM c_auth.authorization_gate WHERE singleton_id=1`).Scan(&state); err != nil || state != "FROZEN" {
					t.Fatal("failure rollback erased durable SQL freeze", err)
				}
			} else {
				// This also acquires the Gate row again: a leaked panic/error
				// transaction would block it, and an erroneous freeze rejects it.
				assertGateCheckpointOpen(t, control)
			}
		})
	}
}
