package authprivacy

import (
	"context"
	"errors"
	"math/big"
	"slices"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/rankings"
)

type rankingCandidate struct {
	channel, id string
	positive    bool
	score       *big.Rat
	published   time.Time
	ordinal     int64
}

func readRankingBlock(ctx context.Context, pool *pgxpool.Pool, snapshot rankings.Snapshot, channels []string, block int64) ([]rankingCandidate, error) {
	rows, err := pool.Query(ctx, rankBlockSQL, snapshot.Version, channels, block)
	if err != nil {
		return nil, err
	}
	items, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (item rankingCandidate, err error) {
		var score string
		err = row.Scan(&item.channel, &item.id, &item.positive, &score, &item.published, &item.ordinal)
		if err == nil {
			var ok bool
			item.score, ok = new(big.Rat).SetString(score)
			if !ok {
				err = errors.New("invalid ranking comparison key")
			}
		}
		return
	})
	if err != nil {
		return nil, err
	}
	counts := make(map[string]int64, len(channels))
	for _, item := range items {
		counts[item.channel]++
	}
	for _, channel := range channels {
		i := slices.Index(snapshot.Channels, channel)
		if i < 0 {
			return nil, rankingsUnavailable()
		}
		expected := min(max(snapshot.Counts[i]-block*rankings.ReadLimit, 0), rankings.ReadLimit)
		if counts[channel] != expected {
			return nil, rankingsUnavailable()
		}
	}
	return items, nil
}

func sortRankingCandidates(items []rankingCandidate) {
	slices.SortFunc(items, func(a, b rankingCandidate) int {
		if a.positive != b.positive {
			if a.positive {
				return -1
			}
			return 1
		}
		if n := b.score.Cmp(a.score); n != 0 {
			return n
		}
		if n := b.published.Compare(a.published); n != 0 {
			return n
		}
		if a.ordinal > b.ordinal {
			return -1
		}
		if a.ordinal < b.ordinal {
			return 1
		}
		return 0
	})
}

// Each permitted shard's first 20 live candidates contain the global top 20.
// A read expands only the next 64-entry blocks of shards that still need rows.
func (c *Community) rankingFallback(ctx context.Context, snapshot rankings.Snapshot, blocked []string, at time.Time) ([]string, error) {
	counts := make(map[string]int, len(snapshot.Channels))
	var candidates []rankingCandidate
	for block := int64(0); ; block++ {
		var pending []string
		for i, channel := range snapshot.Channels {
			if !slices.Contains(blocked, channel) && counts[channel] < posts.PostRankingLimit && block*rankings.ReadLimit < snapshot.Counts[i] {
				pending = append(pending, channel)
			}
		}
		if len(pending) == 0 {
			break
		}
		batch, err := readRankingBlock(ctx, c.pool, snapshot, pending, block)
		if err != nil {
			return nil, err
		}
		var ids []string
		for _, item := range batch {
			ids = append(ids, item.id)
		}
		if len(ids) == 0 {
			return nil, rankingsUnavailable()
		}
		rows, err := c.pool.Query(ctx, liveRankCandidatesSQL, ids, blocked, at)
		if err != nil {
			return nil, err
		}
		live, err := pgx.CollectRows(rows, pgx.RowTo[string])
		if err != nil {
			return nil, err
		}
		visible := make(map[string]bool, len(live))
		for _, id := range live {
			visible[id] = true
		}
		for _, item := range batch {
			if visible[item.id] && counts[item.channel] < posts.PostRankingLimit {
				candidates = append(candidates, item)
				counts[item.channel]++
			}
		}
	}
	sortRankingCandidates(candidates)
	ids := make([]string, 0, min(len(candidates), posts.PostRankingLimit))
	for _, item := range candidates[:min(len(candidates), posts.PostRankingLimit)] {
		ids = append(ids, item.id)
	}
	return ids, nil
}
