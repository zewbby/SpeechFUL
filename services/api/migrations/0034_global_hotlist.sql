-- +goose Up
-- v2 does not change v1 snapshots, allowing a rolling application upgrade.
CREATE TABLE c_posts.hot_snapshots (
    version text PRIMARY KEY,
    generation bigint NOT NULL CHECK (generation > 0),
    bucket timestamptz NOT NULL,
    channel_ids uuid[] NOT NULL CHECK (cardinality(channel_ids) BETWEEN 1 AND 7),
    UNIQUE (generation,bucket)
);
CREATE TABLE c_posts.hot_shard_data (
    data_version text NOT NULL,
    channel_id uuid NOT NULL,
    post_count bigint NOT NULL CHECK (post_count >= 0),
    input_revision bigint NOT NULL CHECK (input_revision > 0),
    next_change timestamptz NOT NULL,
    policy text NOT NULL,
    PRIMARY KEY (data_version,channel_id)
);
CREATE TABLE c_posts.hot_snapshot_shards (
    version text NOT NULL REFERENCES c_posts.hot_snapshots(version) ON DELETE CASCADE,
    channel_id uuid NOT NULL,
    data_version text NOT NULL,
    PRIMARY KEY (version,channel_id),
    FOREIGN KEY (data_version,channel_id) REFERENCES c_posts.hot_shard_data(data_version,channel_id)
);
CREATE INDEX hot_data_references ON c_posts.hot_snapshot_shards(data_version,channel_id);
CREATE TABLE c_posts.hot_blocks (
    data_version text NOT NULL,
    channel_id uuid NOT NULL,
    block_number bigint NOT NULL CHECK (block_number >= 0),
    post_ids uuid[] NOT NULL CHECK (cardinality(post_ids) BETWEEN 1 AND 64 AND array_ndims(post_ids)=1 AND array_position(post_ids,NULL) IS NULL),
    positive boolean[] NOT NULL CHECK (array_ndims(positive)=1 AND array_position(positive,NULL) IS NULL),
    scores numeric[] NOT NULL CHECK (array_ndims(scores)=1 AND array_position(scores,NULL) IS NULL),
    published_at timestamptz[] NOT NULL CHECK (array_ndims(published_at)=1 AND array_position(published_at,NULL) IS NULL),
    ordinals bigint[] NOT NULL CHECK (array_ndims(ordinals)=1 AND array_position(ordinals,NULL) IS NULL),
    PRIMARY KEY (data_version,channel_id,block_number),
    FOREIGN KEY (data_version,channel_id) REFERENCES c_posts.hot_shard_data(data_version,channel_id) ON DELETE CASCADE,
    CHECK (cardinality(positive)=cardinality(post_ids) AND cardinality(scores)=cardinality(post_ids)
        AND cardinality(published_at)=cardinality(post_ids) AND cardinality(ordinals)=cardinality(post_ids))
);
REVOKE ALL ON c_posts.hot_snapshots,c_posts.hot_shard_data,c_posts.hot_snapshot_shards,c_posts.hot_blocks FROM PUBLIC;

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN
    RAISE EXCEPTION 'global hotlist deployment must be disabled and repaired forward';
END $$;
-- +goose StatementEnd
