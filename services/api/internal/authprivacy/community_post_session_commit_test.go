package authprivacy

import (
	"context"
	"crypto/sha256"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/readtiming"
)

type postSessionCommitGate struct {
	AuthorizationGate
	snapshots, commits, aborts int
}

func (g *postSessionCommitGate) Snapshot(ctx context.Context) (AuthorizationDecision, error) {
	g.snapshots++
	return g.AuthorizationGate.Snapshot(ctx)
}

func (g *postSessionCommitGate) CommitAuthorized(ctx context.Context, tx pgx.Tx, generation uint64, checks ...func(AuthorizationDecision) error) (AuthorizationDecision, error) {
	g.commits++
	return g.AuthorizationGate.CommitAuthorized(ctx, tx, generation, checks...)
}

func (g *postSessionCommitGate) Abort(ctx context.Context, tx pgx.Tx) error {
	g.aborts++
	return g.AuthorizationGate.Abort(ctx, tx)
}

func TestFeedPostSessionPreparationSingleCheckpointPostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	enablePostLab(t, l)
	reader := sessionTestAccount(t, l, "post_single_checkpoint")
	owner := sessionTestAccount(t, l, "post_checkpoint_owner")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "检查点作者").IdentityID
	post := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, identity)).PostID
	postTestPublish(t, l)
	advanceClosureClock(t, control, control.clock.now().Add(time.Minute))
	ctx, trace := readtiming.Start(context.Background())
	response, err := l.c.ReadPosts(ctx, reader.SessionToken, PostQuery{Kind: PostDetail, ID: post})
	if err != nil || response.Value.(posts.PublicPostResponse).Post.PostID != post {
		t.Fatal("detail read failed", err)
	}
	stages := trace.Snapshot().Stages
	if stages["anchor_write"].Calls != 1 || stages["sql_commit"].Calls != 1 {
		t.Fatalf("successful post read wrote more than its final checkpoint: %+v", stages)
	}
	assertGateCheckpointOpen(t, control)
	before, err := l.c.ReadPostInteractions(context.Background(), reader.SessionToken, []string{post})
	if err != nil {
		t.Fatal(err)
	}
	ctx, trace = readtiming.Start(context.Background())
	changed, err := l.c.SetPostInteractionConditional(ctx, reader.SessionToken, post, posts.PostLike, true, before.InteractionVersion)
	if err != nil || changed.InteractionVersion == before.InteractionVersion || !changed.Value.(posts.PostInteractions).LikedByMe {
		t.Fatal("interaction did not commit its fenced write", err)
	}
	stages = trace.Snapshot().Stages
	if stages["anchor_write"].Calls != 1 || stages["sql_commit"].Calls != 1 {
		t.Fatalf("successful interaction wrote more than its final checkpoint: %+v", stages)
	}
	assertGateCheckpointOpen(t, control)
	// Custom authorities retain their original Snapshot contract.
	gate := &postSessionCommitGate{AuthorizationGate: l.gate}
	l.c.gate = gate
	if _, err := l.c.ReadPosts(context.Background(), reader.SessionToken, PostQuery{Kind: PostDetail, ID: post}); err != nil ||
		gate.snapshots != 1 || gate.commits != 1 || gate.aborts != 0 {
		t.Fatalf("custom Gate preparation changed: snapshots=%d commits=%d aborts=%d err=%v", gate.snapshots, gate.commits, gate.aborts, err)
	}
	l.c.gate = l.gate
	if err := l.gate.Freeze(context.Background(), "post preparation regression"); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.ReadPosts(context.Background(), reader.SessionToken, PostQuery{Kind: PostDetail, ID: post}); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("private preparation bypassed a frozen Gate", err)
	}
}

func TestFeedPostSessionNativeFinalRevalidationPostgres(t *testing.T) {
	for _, change := range []string{"freeze", "recover", "revoke", "expired"} {
		for _, operation := range []string{"detail", "like"} {
			t.Run(change+"/"+operation, func(t *testing.T) {
				control := newGateControl(t)
				l, ctx := control.lab, context.Background()
				enablePostLab(t, l)
				reader := sessionTestAccount(t, l, "post_native_recheck")
				identity := identityChange(t, l.c, reader.SessionToken, "CREATE", uuid.Nil, "复验作者").IdentityID
				post := postTestCommand(t, l, reader.SessionToken, postTestKey(t), postTestIntent(t, l, identity)).PostID
				postTestPublish(t, l)
				original := *l.c
				called := false
				tracer := &gateCancellationTracer{
					match: func(sql string) bool {
						return strings.HasPrefix(sql, "SELECT account_id FROM c_auth.sessions WHERE token_digest=")
					},
					onStart: func(ctx context.Context) context.Context {
						called = true
						switch change {
						case "freeze", "recover":
							if err := l.gate.Freeze(ctx, "post native preparation regression"); err != nil {
								t.Fatal(err)
							}
							if change == "recover" {
								control.recover(t, AuthorizationRecoveryBreakGlass, 3, 3)
							}
						case "revoke":
							if err := original.RevokeSession(ctx, reader.RevokeSecret); err != nil {
								t.Fatal(err)
							}
						case "expired":
							control.clock.set(control.clock.now().Add(5*time.Minute + time.Nanosecond))
						}
						return ctx
					},
				}
				config := l.cp.Config()
				config.ConnConfig.Tracer = tracer
				pool, err := pgxpool.NewWithConfig(ctx, config)
				if err != nil {
					t.Fatal(err)
				}
				t.Cleanup(pool.Close)
				l.c.pool = pool // Keep the real, unwrapped PostgreSQL Gate.
				var response PostResponse
				if operation == "detail" {
					response, err = l.c.ReadPosts(ctx, reader.SessionToken, PostQuery{Kind: PostDetail, ID: post})
				} else {
					response, err = l.c.SetPostInteraction(ctx, reader.SessionToken, post, posts.PostLike, true)
				}
				want := ErrAuthorizationUnavailable
				if change == "revoke" {
					want = ErrSessionInvalid
				}
				if !called || response.Value != nil || !errors.Is(err, want) || count(t, l.cp, `SELECT count(*) FROM c_posts.post_likes`) != 0 {
					t.Fatalf("native final authorization failed: called=%t response=%+v err=%v", called, response, err)
				}
				if change == "expired" {
					var state string
					if err := l.cp.QueryRow(ctx, `SELECT gate_state FROM c_auth.authorization_gate WHERE singleton_id=1`).Scan(&state); err != nil || state != "FROZEN" {
						t.Fatal("expired authority freeze was not persisted", err)
					}
				}
			})
		}
	}
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
