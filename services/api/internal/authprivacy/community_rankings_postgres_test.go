package authprivacy

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"os"
	"slices"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/rankings"
)

func TestFeedRankingsRedisPostgres(t *testing.T) {
	socket := os.Getenv("RANKING_REDIS_SOCKET")
	if socket == "" {
		t.Skip("dedicated rankings Redis fixture not requested")
	}
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	l.c = withRankingTestComments(t, l.c)
	cache := rankings.NewCache(&redis.Options{Network: "unix", Addr: socket}, uuid.NewString())
	t.Cleanup(func() { _ = cache.Close() })
	var err error
	l.c, err = l.c.WithRankings(ctx, cache)
	if err != nil {
		t.Fatal(err)
	}
	a := sessionTestAccount(t, l, "ranking_author")
	b := sessionTestAccount(t, l, "ranking_reader")
	d := sessionTestAccount(t, l, "ranking_other")
	ai := identityChange(t, l.c, a.SessionToken, "CREATE", uuid.Nil, "作者甲").IdentityID
	bi := identityChange(t, l.c, b.SessionToken, "CREATE", uuid.Nil, "读者乙").IdentityID
	di := identityChange(t, l.c, d.SessionToken, "CREATE", uuid.Nil, "读者丁").IdentityID
	directory := feedTestChannels(t, l)
	channel, second := directory[1], directory[0]
	publish := func(channelID, title string) string {
		t.Helper()
		intent := postTestIntent(t, l, ai)
		intent.ChannelID, intent.Title = channelID, title
		id := postTestCommand(t, l, a.SessionToken, postTestKey(t), intent).PostID
		postTestPublish(t, l)
		return id
	}
	advance := func(delta time.Duration) { advanceClosureClock(t, control, control.clock.now().Add(delta)) }
	first := publish(channel, "重复讨论")
	advance(time.Minute)
	newer := publish(channel, "新帖子")
	publish(second, "另一通道")
	comment := func(token [32]byte, id uuid.UUID) string {
		t.Helper()
		r := commentTextSend(t, l, token, postTestKey(t), comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: first, IdentityID: id.String(), Body: "讨论"})
		commentTextPublish(t, l)
		task := commentTextOwn(t, l, token, r.TaskID)
		if task.PublishedCommentID == nil {
			t.Fatal("comment fixture was not published")
		}
		return *task.PublishedCommentID
	}
	comment(a.SessionToken, ai)
	comment(b.SessionToken, bi)
	comment(b.SessionToken, bi)

	// The interaction rows are the authoritative account-level facts.
	digestSession := func(token [32]byte) []byte {
		digest := sha256.Sum256(token[:])
		return digest[:]
	}
	mustExec(t, l.cp, `INSERT INTO c_posts.post_likes(account_id,post_id) SELECT account_id,$1 FROM c_auth.sessions WHERE token_digest=$2`, first, digestSession(a.SessionToken))
	mustExec(t, l.cp, `INSERT INTO c_posts.post_favorites(account_id,post_id,saved_at) SELECT account_id,$1,$3 FROM c_auth.sessions WHERE token_digest=$2`, first, digestSession(a.SessionToken), control.clock.now())
	mustExec(t, l.cp, `INSERT INTO c_posts.post_likes(account_id,post_id) SELECT account_id,$1 FROM c_auth.sessions WHERE token_digest=$2`, newer, digestSession(d.SessionToken))
	mustExec(t, l.cp, `INSERT INTO c_posts.post_favorites(account_id,post_id,saved_at) SELECT account_id,$1,$3 FROM c_auth.sessions WHERE token_digest=$2`, newer, digestSession(b.SessionToken), control.clock.now())
	build := func() {
		t.Helper()
		advance(5 * time.Minute)
		before, e := os.ReadFile(control.lab.gate.anchor.Path)
		if e != nil {
			t.Fatal(e)
		}
		if _, e := l.c.RefreshRankings(ctx, l.cp, DefaultRankingWeights()); e != nil {
			t.Fatal(e)
		}
		after, e := os.ReadFile(control.lab.gate.anchor.Path)
		if e != nil || !bytes.Equal(before, after) {
			t.Fatal("private ranking build changed the authorization checkpoint", e)
		}
	}
	hot := func(want ...string) {
		t.Helper()
		response, e := l.c.ReadRankings(ctx, b.SessionToken, channel)
		if e != nil {
			t.Fatal(e)
		}
		var ids []string
		for _, item := range response.Value.(posts.PostRanking).Items {
			ids = append(ids, item.PostID)
		}
		if !slices.Equal(ids, want) {
			t.Fatalf("got %v, want %v", ids, want)
		}
	}
	build()
	hot(newer, first) // equal base score; author interactions and duplicate replies count zero extra.
	locked, e := l.cp.Begin(ctx)
	if e != nil {
		t.Fatal(e)
	}
	defer locked.Rollback(ctx)
	if _, e = locked.Exec(ctx, "LOCK TABLE c_posts.post_likes IN ACCESS EXCLUSIVE MODE"); e != nil {
		t.Fatal(e)
	}
	// Even after public snapshot expiry, unchanged data remains reusable.
	advance(20 * time.Minute)
	build()
	if e = locked.Rollback(ctx); e != nil {
		t.Fatal(e)
	}
	order, e := l.c.ReadRankings(ctx, b.SessionToken, "")
	if e != nil || order.Value.(posts.ChannelRanking).ChannelIDs[0] != channel {
		t.Fatal("channel participation order", e)
	}
	otherComment := comment(d.SessionToken, di)
	build()
	hot(first, newer)
	deleted := commentTextSend(t, l, d.SessionToken, postTestKey(t), comments.Intent{Operation: comments.DeleteComment, CommentID: otherComment})
	if deleted.State != "APPLIED" {
		t.Fatal("comment delete fixture did not commit", deleted.State)
	}
	build()
	hot(newer, first)

	// SQL remains authoritative for visibility and preferences on old Redis order.
	mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id=$1`, newer)
	hot(first)
	if _, e := l.c.ReplaceFeedPreferences(ctx, b.SessionToken, posts.FeedPreferences{BlockedChannelIDs: []string{channel}}); e != nil {
		t.Fatal(e)
	}
	hot()
	if _, e := l.c.ReplaceFeedPreferences(ctx, b.SessionToken, posts.FeedPreferences{BlockedChannelIDs: []string{}}); e != nil {
		t.Fatal(e)
	}
	future, e := cache.Snapshot(ctx)
	if e != nil {
		t.Fatal(e)
	}
	future.Bucket = control.clock.now().Truncate(rankings.Interval).Add(rankings.Interval)
	future.Version = rankings.Version(future.Generation, future.Bucket)
	if e := cache.Publish(ctx, future); e != nil {
		t.Fatal(e)
	}
	// Private candidate lookup cannot authorize a future-dated public board.
	current, e := l.c.ReadRankings(ctx, b.SessionToken, "")
	if e != nil || !current.Value.(posts.ChannelRanking).AsOf.Before(future.Bucket) {
		t.Fatal("future cache did not fall back to the authorized SQL snapshot", e)
	}
	if e := cache.Close(); e != nil {
		t.Fatal(e)
	}
	hot(first)
	if e := l.gate.Freeze(ctx, "rankings authorization regression"); e != nil {
		t.Fatal(e)
	}
	if _, e := l.c.ReadRankings(ctx, b.SessionToken, channel); e == nil {
		t.Fatal("frozen Gate released a cached ranking")
	}
}

func TestFeedRankingWindowAndPendingPublicationPostgres(t *testing.T) {
	socket := os.Getenv("RANKING_REDIS_SOCKET")
	if socket == "" {
		t.Skip("dedicated rankings Redis fixture not requested")
	}
	control := newGateControl(t)
	l, ctx := control.lab, context.Background()
	enablePostLab(t, l)
	l.c = withRankingTestComments(t, l.c)
	cache := rankings.NewCache(&redis.Options{Network: "unix", Addr: socket}, uuid.NewString())
	t.Cleanup(func() { _ = cache.Close() })
	var err error
	l.c, err = l.c.WithRankings(ctx, cache)
	if err != nil {
		t.Fatal(err)
	}
	// Place publication halfway into a bucket so the first build excludes it.
	start := control.clock.now().Truncate(rankings.Interval).Add(2*rankings.Interval + time.Minute)
	owner := sessionTestAccount(t, l, "ranking_window_author")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "窗口作者").IdentityID
	advanceClosureClock(t, control, start)
	commentTextPost(t, l, owner.SessionToken, id)
	checkCount := func(want int64) {
		t.Helper()
		if _, err := l.c.RefreshRankings(ctx, l.cp, DefaultRankingWeights()); err != nil {
			t.Fatal(err)
		}
		snapshot, err := cache.Snapshot(ctx)
		var count int64
		for _, n := range snapshot.Counts {
			count += n
		}
		if err != nil || count != want {
			t.Fatalf("eligible posts=%d, want %d (%v)", count, want, err)
		}
	}
	checkCount(0)
	advanceClosureClock(t, control, start.Add(rankings.Interval))
	checkCount(1)
	advanceClosureClock(t, control, start.Add(168*time.Hour-10*time.Minute))
	checkCount(1)
	advanceClosureClock(t, control, start.Add(168*time.Hour))
	// Buckets precede the wall clock by up to one interval. The post leaves
	// the rolling window in the first bucket at or after its actual expiry.
	checkCount(1)
	advanceClosureClock(t, control, start.Add(168*time.Hour+rankings.Interval))
	checkCount(0)
	if err := l.gate.Freeze(ctx, "ranking worker final Gate regression"); err != nil {
		t.Fatal(err)
	}
	if _, err := l.c.RefreshRankings(ctx, l.cp, DefaultRankingWeights()); !errors.Is(err, ErrAuthorizationUnavailable) {
		t.Fatal("ranking worker accepted a frozen Gate", err)
	}
}

func withRankingTestComments(t *testing.T, c *Community) *Community {
	t.Helper()
	cfg := CommentConfig{}
	cfg.KeyKey, _ = random32()
	cfg.FingerprintKey, _ = random32()
	c, err := c.WithComments(context.Background(), cfg)
	if err != nil {
		t.Fatal(err)
	}
	return c
}
