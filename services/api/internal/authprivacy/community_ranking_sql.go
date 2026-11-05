package authprivacy

// Aggregate against one PostgreSQL statement snapshot. Separate interaction
// counts avoid multiplying joins, and the only grouped author data is transient.
// The deferred publication shape constraint requires retained public text;
// scoring therefore needs only the post table. Final reads still check text.
const buildRankingsSQL = `
WITH recent_posts AS MATERIALIZED (
    SELECT p.post_id, p.channel_id, p.owner_account_id, p.published_at, p.publication_ordinal
    FROM c_posts.posts p
    WHERE p.channel_id=$8 AND p.visibility='PUBLISHED' AND NOT p.moderation_hidden
      AND p.published_at > $3::timestamptz - interval '168 hours' AND p.published_at <= $3
), recent_comments AS MATERIALIZED (
    SELECT t.post_id, p.channel_id, t.owner_account_id, a.terminal_at
    FROM c_comments.attempts a
    JOIN c_comments.tasks t USING (task_id)
    JOIN c_posts.posts p ON p.post_id=t.post_id
    WHERE a.state='PUBLISHED' AND a.terminal_at > $3::timestamptz - interval '168 hours' AND a.terminal_at <= $3
      AND p.channel_id=$8 AND p.visibility='PUBLISHED' AND NOT p.moderation_hidden
      AND t.deleted_at IS NULL AND NOT t.moderation_hidden
      AND NOT EXISTS (SELECT 1 FROM c_comments.tasks root WHERE root.comment_id=t.root_comment_id
          AND (root.deleted_at IS NOT NULL OR root.moderation_hidden))
), likes AS (
    SELECT p.post_id, count(*) AS total FROM recent_posts p
    JOIN c_posts.post_likes l ON l.post_id=p.post_id AND l.account_id<>p.owner_account_id
    GROUP BY p.post_id
), favorites AS (
    SELECT p.post_id, count(*) AS total FROM recent_posts p
    JOIN c_posts.post_favorites f ON f.post_id=p.post_id AND f.account_id<>p.owner_account_id
    GROUP BY p.post_id
), discussions AS (
    SELECT p.post_id, count(DISTINCT c.owner_account_id) AS total FROM recent_posts p
    JOIN recent_comments c ON c.post_id=p.post_id AND c.owner_account_id<>p.owner_account_id
    GROUP BY p.post_id
), base_scores AS (
    SELECT p.*, COALESCE(l.total,0)*$4::bigint + COALESCE(f.total,0)*$5::bigint + COALESCE(d.total,0)*$6::bigint AS points
    FROM recent_posts p
    LEFT JOIN likes l USING (post_id)
    LEFT JOIN favorites f USING (post_id)
    LEFT JOIN discussions d USING (post_id)
), scored AS (
    -- log(score) differs between buckets only by a shared constant. Keeping
    -- the common term out allows exact reuse when inputs and the window agree.
    SELECT b.*, CASE WHEN points=0 THEN 0 ELSE round(
        ln(points::numeric) + ln(2::numeric) *
        extract(epoch FROM published_at-timestamptz '2000-01-01 00:00:00+00') / ($7::numeric*3600),
        12) END AS score
    FROM base_scores b
)
INSERT INTO c_posts.ranking_channel_data(data_version,channel_id,post_ids,participant_count,new_post_count,input_revision,next_change,policy)
SELECT $1,$8,ARRAY(SELECT post_id FROM scored ORDER BY (points>0) DESC, score DESC, published_at DESC, publication_ordinal DESC),
    (SELECT count(*) FROM (SELECT owner_account_id FROM recent_posts UNION SELECT owner_account_id FROM recent_comments) people),
    (SELECT count(*) FROM recent_posts),
    (SELECT revision FROM c_posts.ranking_inputs WHERE channel_id=$8),
    LEAST(
        COALESCE((SELECT min(published_at)+interval '168 hours' FROM recent_posts), 'infinity'),
        COALESCE((SELECT min(terminal_at)+interval '168 hours' FROM recent_comments), 'infinity'),
        COALESCE((SELECT min(published_at) FROM c_posts.posts
            WHERE channel_id=$8 AND visibility='PUBLISHED' AND NOT moderation_hidden AND published_at>$3), 'infinity'),
        COALESCE((SELECT min(a.terminal_at) FROM c_comments.attempts a
            JOIN c_comments.tasks t USING(task_id) JOIN c_posts.posts p ON p.post_id=t.post_id
            WHERE a.state='PUBLISHED' AND a.terminal_at>$3 AND p.channel_id=$8), 'infinity')
    ),$9 WHERE $2::bigint>0`

const reuseRankingChannelSQL = `
INSERT INTO c_posts.ranking_posts(version,channel_id,data_version)
SELECT $1,r.channel_id,r.data_version
FROM c_posts.ranking_snapshots s
JOIN c_posts.ranking_posts link ON link.version=s.version
JOIN c_posts.ranking_channel_data r USING(data_version,channel_id)
JOIN c_posts.ranking_inputs i ON i.channel_id=r.channel_id
WHERE s.generation=$2 AND s.bucket<$3
    AND r.channel_id=$4 AND r.input_revision=i.revision AND r.next_change>$3 AND r.policy=$5
ORDER BY s.bucket DESC LIMIT 1`

const readRankSnapshotSQL = `
SELECT s.version, s.generation, s.bucket, s.channel_ids,
       ARRAY(SELECT COALESCE((SELECT d.post_count::bigint FROM c_posts.ranking_posts r
           JOIN c_posts.ranking_channel_data d USING(data_version,channel_id)
           WHERE r.version=s.version AND r.channel_id=ch.id),0)
           FROM unnest(s.channel_ids) WITH ORDINALITY ch(id,n) ORDER BY ch.n)
FROM c_posts.ranking_snapshots s
WHERE s.generation=$1 AND ($2::timestamptz IS NULL OR s.bucket<=$2) AND s.bucket>$3
ORDER BY s.bucket DESC LIMIT 1`

// Both queries use the same live post predicate. The fallback can
// skip arbitrarily many invalid candidates outside the final authorization lock.
const rankedPostVisibleSQL = `
p.channel_id=$2 AND p.visibility='PUBLISHED' AND NOT p.moderation_hidden
AND p.published_at>$3::timestamptz - interval '168 hours' AND body.erased_at IS NULL`

const rankFallbackSQL = `
SELECT candidate.post_id::text
FROM c_posts.ranking_posts link
JOIN c_posts.ranking_channel_data r USING(data_version,channel_id)
CROSS JOIN LATERAL unnest(r.post_ids) WITH ORDINALITY candidate(post_id,position)
JOIN c_posts.posts p ON p.post_id=candidate.post_id
JOIN c_posts.publication_tasks pt ON pt.post_id=p.post_id
JOIN c_posts.attempt_contents body ON body.task_id=pt.task_id AND body.version=p.published_attempt_version
WHERE link.version=$1 AND r.channel_id=$2 AND ` + rankedPostVisibleSQL + `
ORDER BY candidate.position LIMIT 20`

const projectRankedPostsSQL = `
SELECT p.post_id::text, COALESCE(p.edited_title, body.title), COALESCE(v.view_count,0)
FROM unnest($1::uuid[]) WITH ORDINALITY candidate(id,position)
JOIN c_posts.posts p ON p.post_id=candidate.id
JOIN c_posts.publication_tasks pt ON pt.post_id=p.post_id
JOIN c_posts.attempt_contents body ON body.task_id=pt.task_id AND body.version=p.published_attempt_version
LEFT JOIN c_posts.post_view_totals v ON v.post_id=p.post_id
WHERE ` + rankedPostVisibleSQL + `
ORDER BY candidate.position LIMIT 20`
