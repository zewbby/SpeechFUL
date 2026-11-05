-- +goose Up
CREATE TABLE c_posts.ranking_inputs (
    channel_id uuid PRIMARY KEY REFERENCES public.channels(id),
    revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0)
);
INSERT INTO c_posts.ranking_inputs(channel_id) SELECT id FROM public.channels;

CREATE TABLE c_posts.ranking_snapshots (
    version text PRIMARY KEY,
    generation bigint NOT NULL CHECK (generation > 0),
    bucket timestamptz NOT NULL,
    channel_ids uuid[] NOT NULL CHECK (cardinality(channel_ids) BETWEEN 1 AND 7),
    UNIQUE (generation, bucket)
);

CREATE TABLE c_posts.ranking_channel_data (
    data_version text NOT NULL,
    channel_id uuid NOT NULL,
    post_ids uuid[] NOT NULL,
    post_count integer GENERATED ALWAYS AS (cardinality(post_ids)) STORED,
    participant_count bigint NOT NULL CHECK (participant_count >= 0),
    new_post_count bigint NOT NULL CHECK (new_post_count >= 0),
    input_revision bigint NOT NULL CHECK (input_revision > 0),
    next_change timestamptz NOT NULL,
    policy text NOT NULL,
    PRIMARY KEY (data_version, channel_id)
);

CREATE TABLE c_posts.ranking_posts (
    version text NOT NULL REFERENCES c_posts.ranking_snapshots(version) ON DELETE CASCADE,
    channel_id uuid NOT NULL,
    data_version text NOT NULL,
    PRIMARY KEY (version,channel_id),
    FOREIGN KEY (data_version,channel_id) REFERENCES c_posts.ranking_channel_data(data_version,channel_id)
);
CREATE INDEX ranking_data_references ON c_posts.ranking_posts(data_version,channel_id);

CREATE INDEX ranking_recent_public_comments
    ON c_comments.attempts (terminal_at, task_id) WHERE state = 'PUBLISHED';

-- Statement-level transition tables coalesce bulk cleanup into one revision
-- update per affected channel. Revision and content changes commit together.
-- +goose StatementBegin
CREATE FUNCTION c_posts.mark_ranking_interactions() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
    UPDATE c_posts.ranking_inputs SET revision=revision+1
    WHERE channel_id IN (SELECT p.channel_id FROM c_posts.posts p JOIN changed_rows r ON r.post_id=p.post_id);
    RETURN NULL;
END $$;
-- +goose StatementEnd
CREATE TRIGGER ranking_likes_insert AFTER INSERT ON c_posts.post_likes
    REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION c_posts.mark_ranking_interactions();
CREATE TRIGGER ranking_likes_delete AFTER DELETE ON c_posts.post_likes
    REFERENCING OLD TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION c_posts.mark_ranking_interactions();
CREATE TRIGGER ranking_favorites_insert AFTER INSERT ON c_posts.post_favorites
    REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION c_posts.mark_ranking_interactions();
CREATE TRIGGER ranking_favorites_delete AFTER DELETE ON c_posts.post_favorites
    REFERENCING OLD TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION c_posts.mark_ranking_interactions();

-- +goose StatementBegin
CREATE FUNCTION c_posts.mark_ranking_posts() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
    IF TG_OP='INSERT' THEN
        UPDATE c_posts.ranking_inputs SET revision=revision+1
        WHERE channel_id IN (SELECT channel_id FROM changed_new WHERE visibility='PUBLISHED');
    ELSE
        UPDATE c_posts.ranking_inputs SET revision=revision+1
        WHERE channel_id IN (SELECT n.channel_id FROM changed_new n JOIN changed_old o USING(post_id)
            WHERE (n.visibility,n.moderation_hidden) IS DISTINCT FROM (o.visibility,o.moderation_hidden));
    END IF;
    RETURN NULL;
END $$;
-- +goose StatementEnd
CREATE TRIGGER ranking_posts_insert AFTER INSERT ON c_posts.posts
    REFERENCING NEW TABLE AS changed_new FOR EACH STATEMENT EXECUTE FUNCTION c_posts.mark_ranking_posts();
CREATE TRIGGER ranking_posts_update AFTER UPDATE ON c_posts.posts
    REFERENCING NEW TABLE AS changed_new OLD TABLE AS changed_old FOR EACH STATEMENT EXECUTE FUNCTION c_posts.mark_ranking_posts();

-- +goose StatementBegin
CREATE FUNCTION c_posts.mark_ranking_comments() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
    UPDATE c_posts.ranking_inputs SET revision=revision+1
    WHERE channel_id IN (
        SELECT p.channel_id FROM changed_new n JOIN changed_old o USING(task_id)
        JOIN c_posts.posts p ON p.post_id=n.post_id
        WHERE (n.deleted_at,n.moderation_hidden) IS DISTINCT FROM (o.deleted_at,o.moderation_hidden));
    RETURN NULL;
END $$;
-- +goose StatementEnd
CREATE TRIGGER ranking_comments_update AFTER UPDATE ON c_comments.tasks
    REFERENCING NEW TABLE AS changed_new OLD TABLE AS changed_old FOR EACH STATEMENT EXECUTE FUNCTION c_posts.mark_ranking_comments();

-- +goose StatementBegin
CREATE FUNCTION c_posts.mark_ranking_comment_publication() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
    UPDATE c_posts.ranking_inputs SET revision=revision+1
    WHERE channel_id IN (
        SELECT p.channel_id FROM changed_rows a JOIN c_comments.tasks t USING(task_id)
        JOIN c_posts.posts p ON p.post_id=t.post_id WHERE a.state='PUBLISHED');
    RETURN NULL;
END $$;
-- +goose StatementEnd
CREATE TRIGGER ranking_comment_insert AFTER INSERT ON c_comments.attempts
    REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION c_posts.mark_ranking_comment_publication();
CREATE TRIGGER ranking_comment_update AFTER UPDATE ON c_comments.attempts
    REFERENCING NEW TABLE AS changed_rows FOR EACH STATEMENT EXECUTE FUNCTION c_posts.mark_ranking_comment_publication();

REVOKE ALL ON c_posts.ranking_inputs, c_posts.ranking_snapshots, c_posts.ranking_posts, c_posts.ranking_channel_data FROM PUBLIC;
REVOKE ALL ON FUNCTION c_posts.mark_ranking_interactions(), c_posts.mark_ranking_posts(),
    c_posts.mark_ranking_comments(), c_posts.mark_ranking_comment_publication() FROM PUBLIC;

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN
    RAISE EXCEPTION 'ranking deployment must be disabled and repaired forward';
END $$;
-- +goose StatementEnd
