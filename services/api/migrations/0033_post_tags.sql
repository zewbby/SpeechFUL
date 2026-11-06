-- +goose Up
-- +goose StatementBegin
CREATE FUNCTION c_posts.tag_keys(tags text[]) RETURNS text[]
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
    SELECT COALESCE(array_agg(lower(tag COLLATE "C") ORDER BY n), '{}'::text[])
    FROM unnest(tags) WITH ORDINALITY AS t(tag,n)
$$;
CREATE FUNCTION c_posts.valid_tags(tags text[]) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
    SELECT cardinality(tags)<=3 AND (cardinality(tags)=0 OR array_ndims(tags)=1 AND array_lower(tags,1)=1)
      AND NOT EXISTS(SELECT 1 FROM unnest(tags) t WHERE t IS NULL OR char_length(t) NOT BETWEEN 1 AND 10)
      AND cardinality(tags)=(SELECT count(DISTINCT lower(t COLLATE "C")) FROM unnest(tags) t)
$$;
ALTER TABLE c_posts.attempt_contents ADD COLUMN tags text[] NOT NULL DEFAULT '{}'
    CHECK(c_posts.valid_tags(tags) AND (erased_at IS NULL OR cardinality(tags)=0));
ALTER TABLE c_posts.posts ADD COLUMN tags text[] NOT NULL DEFAULT '{}' CHECK(c_posts.valid_tags(tags)),
    ADD COLUMN tag_keys text[] GENERATED ALWAYS AS (c_posts.tag_keys(tags)) STORED;
CREATE INDEX post_tags_lookup ON c_posts.posts USING gin(tag_keys) WHERE visibility='PUBLISHED' AND NOT moderation_hidden;
CREATE TABLE c_posts.post_tag_terms (
    post_id uuid NOT NULL REFERENCES c_posts.posts(post_id),
    tag_key text COLLATE "C" NOT NULL,
    label text NOT NULL,
    PRIMARY KEY(tag_key,post_id)
);
CREATE FUNCTION c_posts.sync_post_tag_terms() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM c_posts.post_tag_terms WHERE post_id=NEW.post_id;
    IF NEW.visibility='PUBLISHED' AND NOT NEW.moderation_hidden THEN
        INSERT INTO c_posts.post_tag_terms(post_id,tag_key,label)
        SELECT NEW.post_id,lower(t COLLATE "C"),t FROM unnest(NEW.tags) t;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER post_tag_terms_sync AFTER UPDATE OF tags,visibility,moderation_hidden ON c_posts.posts
    FOR EACH ROW EXECUTE FUNCTION c_posts.sync_post_tag_terms();

CREATE FUNCTION c_posts.fence_attempt_tags() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.erased_at IS NOT NULL THEN NEW.tags := '{}';
    ELSIF NEW.tags IS DISTINCT FROM OLD.tags THEN RAISE EXCEPTION 'attempt tags are immutable';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER attempt_tags_immutable BEFORE UPDATE ON c_posts.attempt_contents
    FOR EACH ROW EXECUTE FUNCTION c_posts.fence_attempt_tags();
CREATE FUNCTION c_posts.fence_post_tags() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.visibility='DELETED' THEN NEW.tags := '{}';
    ELSIF NEW.visibility='PUBLISHED' AND OLD.visibility IS DISTINCT FROM 'PUBLISHED' THEN
        SELECT x.tags INTO STRICT NEW.tags FROM c_posts.publication_tasks t
        JOIN c_posts.attempt_contents x ON x.task_id=t.task_id AND x.version=NEW.published_attempt_version
        WHERE t.post_id=NEW.post_id;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER post_tags_lifecycle BEFORE UPDATE OF visibility ON c_posts.posts
    FOR EACH ROW EXECUTE FUNCTION c_posts.fence_post_tags();
REVOKE ALL ON TABLE c_posts.post_tag_terms FROM PUBLIC;
REVOKE ALL ON FUNCTION c_posts.tag_keys(text[]),c_posts.valid_tags(text[]),c_posts.fence_attempt_tags(),c_posts.fence_post_tags(),c_posts.sync_post_tag_terms() FROM PUBLIC;
DO $$ BEGIN
    IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='hnuhole_c_runtime') THEN
        GRANT UPDATE(tags) ON c_posts.posts,c_posts.attempt_contents TO hnuhole_c_runtime;
        GRANT SELECT,INSERT,DELETE ON c_posts.post_tag_terms TO hnuhole_c_runtime;
        GRANT EXECUTE ON FUNCTION c_posts.tag_keys(text[]),c_posts.valid_tags(text[]) TO hnuhole_c_runtime;
    END IF;
END $$;
-- +goose StatementEnd
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'post tag command contents require forward repair'; END $$;
-- +goose StatementEnd
