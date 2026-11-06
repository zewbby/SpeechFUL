package rankings

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sync/atomic"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

const (
	Interval        = 5 * time.Minute
	MaxAge          = 3 * Interval
	cacheTTL        = 6 * Interval
	ReadLimit       = 64
	GlobalReadLimit = 7 * ReadLimit
	foregroundGrace = 100 * time.Millisecond
)

type Snapshot struct {
	Version    string
	Generation uint64
	Bucket     time.Time
	Channels   []string
	Counts     []int64
}

func Version(generation uint64, bucket time.Time) string {
	return fmt.Sprintf("%020d:%012d", generation, bucket.Unix())
}

func (s Snapshot) ValidAt(generation uint64, now time.Time) bool {
	if s.Generation == 0 || s.Generation != generation || s.Version != Version(generation, s.Bucket) ||
		s.Bucket.Unix() <= 0 || !s.Bucket.Equal(s.Bucket.Truncate(Interval)) ||
		s.Bucket.After(now) || !s.Bucket.After(now.Add(-MaxAge)) ||
		len(s.Channels) < 1 || len(s.Channels) > 7 || len(s.Counts) != len(s.Channels) {
		return false
	}
	seen := make(map[string]bool, len(s.Channels))
	for i, id := range s.Channels {
		if _, err := posts.ParseResourceID(id); err != nil || seen[id] || s.Counts[i] < 0 {
			return false
		}
		seen[id] = true
	}
	return true
}

type Cache struct {
	client     *redis.Client
	prefix     string
	foreground atomic.Int64
	activity   atomic.Uint64
}

func NewCache(options *redis.Options, environment string) *Cache {
	return &Cache{client: redis.NewClient(options), prefix: "hnuhole:channel-rankings:v2:" + environment + ":"}
}

func (c *Cache) Close() error { return c.client.Close() }

// ForegroundStarted never waits for background work. The revision also records
// requests that start and finish between the worker's observations.
func (c *Cache) ForegroundStarted() func() {
	c.foreground.Add(1)
	c.activity.Add(1)
	return func() {
		c.activity.Add(1)
		c.foreground.Add(-1)
	}
}

// ForegroundActivity exposes scheduling observations, never account data or
// authorization. The count includes nested HTTP/business registrations.
func (c *Cache) ForegroundActivity() (active int64, revision uint64) {
	return c.foreground.Load(), c.activity.Load()
}

// YieldToForeground prefers a quiet 20ms interval, but a continuously busy
// foreground cannot postpone the worker past its fixed grace period. A caller's
// cancellation still stops the worker; foreground requests never wait here.
func (c *Cache) YieldToForeground(ctx context.Context) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	ticker := time.NewTicker(20 * time.Millisecond)
	defer ticker.Stop()
	deadline := time.NewTimer(foregroundGrace)
	defer deadline.Stop()
	revision := c.activity.Load()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-deadline.C:
			return ctx.Err()
		case <-ticker.C:
			current := c.activity.Load()
			if c.foreground.Load() == 0 && current == revision && c.activity.Load() == current {
				return ctx.Err()
			}
			revision = current
		}
	}
}

func (c *Cache) key(version, channel string) string {
	return c.prefix + version + ":" + channel
}

func (c *Cache) Snapshot(ctx context.Context) (Snapshot, error) {
	var snapshot Snapshot
	data, err := c.client.Get(ctx, c.prefix+"active").Bytes()
	if err != nil {
		return snapshot, err
	}
	if len(data) > 2048 {
		return snapshot, errors.New("invalid ranking snapshot metadata")
	}
	err = json.Unmarshal(data, &snapshot)
	return snapshot, err
}

func (c *Cache) Candidates(ctx context.Context, snapshot Snapshot, channel string, count int64) ([]string, error) {
	limit := min(count, GlobalReadLimit)
	if limit == 0 {
		return []string{}, nil
	}
	rows, err := c.client.ZRangeWithScores(ctx, c.key(snapshot.Version, channel), 0, limit-1).Result()
	if err != nil {
		return nil, err
	}
	if int64(len(rows)) != limit {
		return nil, errors.New("ranking cache is incomplete")
	}
	ids := make([]string, len(rows))
	for i, row := range rows {
		id, ok := row.Member.(string)
		if _, err := posts.ParseResourceID(id); !ok || err != nil || row.Score != float64(i+1) {
			return nil, errors.New("invalid cached ranking order")
		}
		ids[i] = id
	}
	return ids, nil
}

type Entry struct {
	Rank   int64
	PostID string
}

// Stage the bounded hot prefix of a committed immutable snapshot.
// Each set expires even if publication is interrupted.
func (c *Cache) Stage(ctx context.Context, snapshot Snapshot, channel string, entries []Entry) error {
	key := c.key(snapshot.Version, channel)
	members := make([]redis.Z, len(entries))
	for i, entry := range entries {
		members[i] = redis.Z{Score: float64(entry.Rank), Member: entry.PostID}
	}
	_, err := c.client.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
		pipe.ZAdd(ctx, key, members...)
		pipe.Expire(ctx, key, cacheTTL+Interval)
		return nil
	})
	return err
}

// Fixed width version strings compare by authorization generation and then
// time bucket. A delayed worker cannot overwrite a newer published snapshot.
var publish = redis.NewScript(`
local old = redis.call("GET", KEYS[1])
if old and cjson.decode(old).Version > ARGV[1] then return 0 end
redis.call("SET", KEYS[1], ARGV[2], "EX", ARGV[3])
return 1
`)

func (c *Cache) Publish(ctx context.Context, snapshot Snapshot) error {
	data, err := json.Marshal(snapshot)
	if err != nil {
		return err
	}
	return publish.Run(ctx, c.client, []string{c.prefix + "active"}, snapshot.Version, data, int(cacheTTL.Seconds())).Err()
}
