package authprivacy

import (
	"math/big"
	"testing"
	"time"
)

func TestGlobalRankingKeepsExactDecimalAndStableTieOrder(t *testing.T) {
	decimal := func(s string) *big.Rat {
		r, ok := new(big.Rat).SetString(s)
		if !ok {
			t.Fatal(s)
		}
		return r
	}
	at := time.Date(2026, 11, 6, 0, 0, 0, 0, time.UTC)
	items := []rankingCandidate{
		{id: "zero", positive: false, score: decimal("0"), published: at.Add(time.Hour), ordinal: 9},
		{id: "lower-decimal", positive: true, score: decimal("3399.123456789012"), published: at, ordinal: 3},
		{id: "higher-decimal", positive: true, score: decimal("3399.123456789013"), published: at, ordinal: 1},
		{id: "same-score-newer-ordinal", positive: true, score: decimal("3399.123456789013"), published: at, ordinal: 2},
	}
	sortRankingCandidates(items)
	want := []string{"same-score-newer-ordinal", "higher-decimal", "lower-decimal", "zero"}
	for i, item := range items {
		if item.id != want[i] {
			t.Fatalf("rank %d: %s, want %s", i, item.id, want[i])
		}
	}
}
