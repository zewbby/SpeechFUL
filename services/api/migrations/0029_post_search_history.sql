-- +goose Up
-- Private, account-scoped search terms. NULL is the distinct all-channel scope.
CREATE TABLE c_posts.post_search_history (
    account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    channel_id uuid REFERENCES public.channels(id),
    keyword text NOT NULL CHECK (char_length(keyword) BETWEEN 1 AND 100),
    keyword_key text COLLATE "C" NOT NULL CHECK (char_length(keyword_key) BETWEEN 1 AND 100),
    sort_at timestamptz NOT NULL,
    CONSTRAINT post_search_history_keyword UNIQUE NULLS NOT DISTINCT (account_id, channel_id, keyword_key),
    CONSTRAINT post_search_history_order UNIQUE NULLS NOT DISTINCT (account_id, channel_id, sort_at)
);

-- +goose StatementBegin
CREATE FUNCTION c_posts.clear_closed_account_post_search_history() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
    IF NEW.state = 'CLOSED' AND OLD.state IS DISTINCT FROM NEW.state THEN
        DELETE FROM c_posts.post_search_history WHERE account_id = NEW.account_id;
    END IF;
    RETURN NEW;
END $$;
-- +goose StatementEnd
CREATE TRIGGER post_search_history_account_closed AFTER UPDATE OF state ON c_auth.accounts
    FOR EACH ROW EXECUTE FUNCTION c_posts.clear_closed_account_post_search_history();

REVOKE ALL ON c_posts.post_search_history FROM PUBLIC;
REVOKE ALL ON FUNCTION c_posts.clear_closed_account_post_search_history() FROM PUBLIC;

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN
    RAISE EXCEPTION '0029 stores private search history; freeze and repair forward instead of rolling back';
END $$;
-- +goose StatementEnd
