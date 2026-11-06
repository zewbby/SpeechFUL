package authprivacy

// Shards are private computation units. Comparable keys and bounded blocks
// preserve sparse-change reuse and exact global order without full-array reads.
const buildRankingsSQL = `
WITH recent_posts AS MATERIALIZED (
    SELECT p.post_id,p.channel_id,p.owner_account_id,p.published_at,p.publication_ordinal
    FROM c_posts.posts p
    WHERE p.channel_id=$8 AND p.visibility='PUBLISHED' AND NOT p.moderation_hidden
      AND p.published_at>$3::timestamptz-interval '168 hours' AND p.published_at<=$3
), likes AS (
    SELECT p.post_id,count(*) AS total FROM recent_posts p
    JOIN c_posts.post_likes l ON l.post_id=p.post_id AND l.account_id<>p.owner_account_id GROUP BY p.post_id
), favorites AS (
    SELECT p.post_id,count(*) AS total FROM recent_posts p
    JOIN c_posts.post_favorites f ON f.post_id=p.post_id AND f.account_id<>p.owner_account_id GROUP BY p.post_id
), discussions AS (
    SELECT p.post_id,count(DISTINCT t.owner_account_id) AS total FROM recent_posts p
    JOIN c_comments.tasks t ON t.post_id=p.post_id AND t.owner_account_id<>p.owner_account_id
    JOIN c_comments.attempts a USING(task_id)
    WHERE a.state='PUBLISHED' AND a.terminal_at<=$3 AND a.terminal_at>$3::timestamptz-interval '168 hours'
      AND t.deleted_at IS NULL AND NOT t.moderation_hidden
      AND NOT EXISTS (SELECT 1 FROM c_comments.tasks root WHERE root.comment_id=t.root_comment_id
          AND (root.deleted_at IS NOT NULL OR root.moderation_hidden))
    GROUP BY p.post_id
), base_scores AS (
    SELECT p.*,COALESCE(l.total,0)*$4::bigint+COALESCE(f.total,0)*$5::bigint+COALESCE(d.total,0)*$6::bigint AS points
    FROM recent_posts p LEFT JOIN likes l USING(post_id)
    LEFT JOIN favorites f USING(post_id) LEFT JOIN discussions d USING(post_id)
), scored AS (
    SELECT b.*,CASE WHEN points=0 THEN 0 ELSE round(ln(points::numeric)+ln(2::numeric)*
        extract(epoch FROM published_at-timestamptz '2000-01-01 00:00:00+00')/($7::numeric*3600),12) END AS score
    FROM base_scores b
), numbered AS MATERIALIZED (
    SELECT *,row_number() OVER(ORDER BY (points>0) DESC,score DESC,published_at DESC,publication_ordinal DESC) AS rank
    FROM scored
), metadata AS (
    INSERT INTO c_posts.hot_shard_data(data_version,channel_id,post_count,input_revision,next_change,policy)
    SELECT $1,$8,(SELECT count(*) FROM recent_posts),
        (SELECT revision FROM c_posts.ranking_inputs WHERE channel_id=$8),
        LEAST(COALESCE((SELECT min(published_at)+interval '168 hours' FROM recent_posts),'infinity'),
            COALESCE((SELECT min(published_at) FROM c_posts.posts WHERE channel_id=$8
                AND visibility='PUBLISHED' AND NOT moderation_hidden AND published_at>$3),'infinity'),
            COALESCE((SELECT min(a.terminal_at) FROM recent_posts p JOIN c_comments.tasks t USING(post_id)
                JOIN c_comments.attempts a USING(task_id) WHERE a.state='PUBLISHED' AND a.terminal_at>$3),'infinity')),
        $9 WHERE $2::bigint>0 RETURNING data_version,channel_id
)
INSERT INTO c_posts.hot_blocks(data_version,channel_id,block_number,post_ids,positive,scores,published_at,ordinals)
SELECT m.data_version,m.channel_id,(n.rank-1)/64,
    array_agg(n.post_id ORDER BY rank),array_agg(n.points>0 ORDER BY rank),array_agg(n.score ORDER BY rank),
    array_agg(n.published_at ORDER BY rank),array_agg(n.publication_ordinal ORDER BY rank)
FROM numbered n CROSS JOIN metadata m GROUP BY m.data_version,m.channel_id,(n.rank-1)/64`

const reuseRankingChannelSQL = `
INSERT INTO c_posts.hot_snapshot_shards(version,channel_id,data_version)
SELECT $1,r.channel_id,r.data_version
FROM c_posts.hot_snapshots s JOIN c_posts.hot_snapshot_shards link ON link.version=s.version
JOIN c_posts.hot_shard_data r USING(data_version,channel_id)
JOIN c_posts.ranking_inputs i ON i.channel_id=r.channel_id
WHERE s.generation=$2 AND s.bucket<$3 AND r.channel_id=$4
    AND r.input_revision=i.revision AND r.next_change>$3 AND r.policy=$5
ORDER BY s.bucket DESC LIMIT 1`

const readRankSnapshotSQL = `
SELECT s.version,s.generation,s.bucket,s.channel_ids,
    ARRAY(SELECT d.post_count FROM unnest(s.channel_ids) WITH ORDINALITY ch(id,n)
        JOIN c_posts.hot_snapshot_shards link ON link.version=s.version AND link.channel_id=ch.id
        JOIN c_posts.hot_shard_data d USING(data_version,channel_id) ORDER BY ch.n)
FROM c_posts.hot_snapshots s
WHERE s.generation=$1 AND ($2::timestamptz IS NULL OR s.bucket<=$2) AND s.bucket>$3
ORDER BY s.bucket DESC LIMIT 1`

// One indexed block per requested shard, at most 448 candidates per round.
const rankBlockSQL = `
SELECT b.channel_id::text,c.id::text,c.positive,c.score::text,c.published,c.ordinal
FROM c_posts.hot_snapshot_shards link JOIN c_posts.hot_blocks b USING(data_version,channel_id)
CROSS JOIN LATERAL unnest(b.post_ids,b.positive,b.scores,b.published_at,b.ordinals)
    WITH ORDINALITY c(id,positive,score,published,ordinal,position)
WHERE link.version=$1 AND b.channel_id=ANY($2::uuid[]) AND b.block_number=$3
ORDER BY b.channel_id,c.position`

const rankedPostVisibleSQL = `
p.visibility='PUBLISHED' AND NOT p.moderation_hidden AND NOT(p.channel_id=ANY($2::uuid[]))
AND p.published_at>$3::timestamptz-interval '168 hours' AND p.published_at<=$3 AND body.erased_at IS NULL`

const projectRankedPostsSQL = `
WITH live AS MATERIALIZED (
SELECT p.post_id,p.channel_id,COALESCE(p.edited_title,body.title) AS title,COALESCE(v.view_count,0) AS views,candidate.position
FROM unnest($1::uuid[]) WITH ORDINALITY candidate(id,position)
JOIN c_posts.posts p ON p.post_id=candidate.id
JOIN c_posts.publication_tasks pt ON pt.post_id=p.post_id
JOIN c_posts.attempt_contents body ON body.task_id=pt.task_id AND body.version=p.published_attempt_version
LEFT JOIN c_posts.post_view_totals v ON v.post_id=p.post_id
WHERE ` + rankedPostVisibleSQL + `
), coverage AS (SELECT channel_id,count(*) AS n FROM live GROUP BY channel_id),
counts AS (SELECT array_agg(channel_id ORDER BY channel_id) AS channels,array_agg(n ORDER BY channel_id) AS counts FROM coverage)
SELECT live.post_id::text,live.channel_id::text,live.title,live.views,counts.channels,counts.counts
FROM live CROSS JOIN counts ORDER BY live.position LIMIT 20`

const liveRankCandidatesSQL = `
SELECT p.post_id::text FROM unnest($1::uuid[]) candidate(id)
JOIN c_posts.posts p ON p.post_id=candidate.id
JOIN c_posts.publication_tasks pt ON pt.post_id=p.post_id
JOIN c_posts.attempt_contents body ON body.task_id=pt.task_id AND body.version=p.published_attempt_version
WHERE ` + rankedPostVisibleSQL
