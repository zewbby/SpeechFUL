package authprivacy

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Private candidate preparation needs verified time but neither renews a
// session nor establishes an authorization checkpoint. The final business
// transaction still uses CommitAuthorized. Unknown Gate implementations keep
// their original Snapshot behavior and their own generation source.
func (c *Community) postCandidateDecision(ctx context.Context, pool *pgxpool.Pool) (AuthorizationDecision, error) {
	if gate, ok := c.gate.(*PostgresAuthorizationGate); !ok || gate.schema != "c_auth" {
		return c.gate.Snapshot(ctx)
	}
	tx, err := begin(ctx, pool)
	if err != nil {
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	defer tx.Rollback(ctx)
	var generation uint64
	if err := tx.QueryRow(ctx, `SELECT authorization_generation FROM c_auth.authorization_gate WHERE singleton_id=1`).Scan(&generation); err != nil {
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	decision, err := c.gate.RecheckForCommit(ctx, tx, generation)
	if err != nil {
		// A detected independent freeze must survive rollback of this read.
		_ = c.gate.Abort(ctx, tx)
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	if err := tx.Rollback(ctx); err != nil && !errors.Is(err, pgx.ErrTxClosed) {
		return AuthorizationDecision{}, ErrAuthorizationUnavailable
	}
	return decision, nil
}
