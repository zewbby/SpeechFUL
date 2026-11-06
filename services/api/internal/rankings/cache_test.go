package rankings

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

func TestForegroundReadsYieldWithoutStarvingRankingWork(t *testing.T) {
	c := &Cache{}
	first := c.ForegroundStarted()
	second := c.ForegroundStarted()
	first()
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Millisecond)
	defer cancel()
	if err := c.YieldToForeground(ctx); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal("background work started during a foreground read", err)
	}
	// The second foreground read stays active throughout the next call. Work
	// must nevertheless proceed before its caller's one-second deadline.
	busy, stopBusy := context.WithTimeout(context.Background(), time.Second)
	defer stopBusy()
	if err := c.YieldToForeground(busy); err != nil {
		t.Fatal("continuous foreground traffic starved background progress", err)
	}
	second()
	if err := c.YieldToForeground(context.Background()); err != nil {
		t.Fatal(err)
	}
	cancelled, stop := context.WithCancel(context.Background())
	stop()
	if err := c.YieldToForeground(cancelled); !errors.Is(err, context.Canceled) {
		t.Fatal("cancelled worker was allowed to continue", err)
	}
}

func TestSnapshotRejectsStaleCrossGenerationAndMalformedMetadata(t *testing.T) {
	now := time.Date(2026, 11, 5, 4, 5, 30, 0, time.UTC)
	bucket := now.Truncate(Interval)
	s := Snapshot{
		Version: Version(2, bucket), Generation: 2, Bucket: bucket,
		Channels: []string{"00000000-0000-4000-8000-000000000001"}, Counts: []int64{25},
	}
	if !s.ValidAt(2, now) {
		t.Fatal("valid snapshot rejected")
	}
	if s.ValidAt(3, now) || s.ValidAt(2, bucket.Add(MaxAge)) || s.ValidAt(2, bucket.Add(-time.Second)) {
		t.Fatal("old, future or cross-generation data accepted")
	}
	bad := s
	bad.Channels = append(append([]string{}, s.Channels...), s.Channels[0])
	bad.Counts = []int64{25, 25}
	if bad.ValidAt(2, now) {
		t.Fatal("duplicate channel accepted")
	}
	if Version(3, bucket.Add(-time.Hour)) <= s.Version ||
		Version(2, bucket.Add(Interval)) <= s.Version {
		t.Fatal("version comparison does not preserve generation and bucket order")
	}
}

func TestFeedRankingCachePublicationAndEviction(t *testing.T) {
	socket := os.Getenv("RANKING_REDIS_SOCKET")
	if socket == "" {
		t.Skip("dedicated rankings Redis fixture not requested")
	}
	ctx := context.Background()
	c := NewCache(&redis.Options{Network: "unix", Addr: socket}, uuid.NewString())
	defer c.Close()
	bucket := time.Now().UTC().Truncate(Interval)
	channel := uuid.NewString()
	old := Snapshot{Generation: 2, Bucket: bucket, Channels: []string{channel}, Counts: []int64{1}}
	old.Version = Version(old.Generation, old.Bucket)
	if err := c.Stage(ctx, old, channel, []Entry{{Rank: 1, PostID: uuid.NewString()}}); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Snapshot(ctx); err == nil {
		t.Fatal("staging exposed an unpublished version")
	}
	if err := c.Publish(ctx, old); err != nil {
		t.Fatal(err)
	}
	newer := old
	newer.Generation = 3
	newer.Version = Version(newer.Generation, newer.Bucket)
	if err := c.Publish(ctx, newer); err != nil {
		t.Fatal(err)
	}
	if err := c.Publish(ctx, old); err != nil {
		t.Fatal(err)
	}
	current, err := c.Snapshot(ctx)
	if err != nil || current.Version != newer.Version {
		t.Fatal("a delayed old publisher replaced the active version")
	}
	if _, err := c.Candidates(ctx, current, channel, 1); err == nil {
		t.Fatal("evicted or incomplete set looked like an empty ranking")
	}
}

func TestFeedRankingV2ACLUpgradePostgres(t *testing.T) {
	socket := os.Getenv("RANKING_REDIS_SOCKET")
	if socket == "" {
		t.Skip("dedicated rankings Redis fixture not requested")
	}
	ctx := context.Background()
	admin := redis.NewClient(&redis.Options{Network: "unix", Addr: socket})
	defer admin.Close()
	environment, user, password := uuid.NewString(), "rank_test_"+uuid.NewString(), uuid.NewString()
	oldPrefix := "~hnuhole:channel-rankings:v1:" + environment + ":*"
	newPrefix := "~hnuhole:channel-rankings:v2:" + environment + ":*"
	if err := admin.Do(ctx, "ACL", "SETUSER", user, "on", ">"+password, oldPrefix, "+@connection", "+get", "+set", "+zadd", "+zrange", "+expire", "+multi", "+exec", "+discard", "+eval", "+evalsha").Err(); err != nil {
		t.Fatal(err)
	}
	defer admin.Do(ctx, "ACL", "DELUSER", user)
	c := NewCache(&redis.Options{Network: "unix", Addr: socket, Username: user, Password: password}, environment)
	defer c.Close()
	bucket := time.Now().UTC().Truncate(Interval)
	snapshot := Snapshot{Generation: 1, Bucket: bucket, Channels: []string{uuid.NewString()}, Counts: []int64{1}}
	snapshot.Version = Version(1, bucket)
	entry := Entry{Rank: 1, PostID: uuid.NewString()}
	if err := c.Stage(ctx, snapshot, "all", []Entry{entry}); err == nil {
		t.Fatal("v1-only ACL unexpectedly authorized v2")
	}
	if err := admin.Do(ctx, "ACL", "SETUSER", user, newPrefix).Err(); err != nil {
		t.Fatal(err)
	}
	if err := c.Stage(ctx, snapshot, "all", []Entry{entry}); err != nil {
		t.Fatal(err)
	}
	if err := c.Publish(ctx, snapshot); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Snapshot(ctx); err != nil {
		t.Fatal(err)
	}
	ids, err := c.Candidates(ctx, snapshot, "all", 1)
	if err != nil || len(ids) != 1 || ids[0] != entry.PostID {
		t.Fatal("v2 ACL did not allow full ranking lifecycle", err)
	}
}
