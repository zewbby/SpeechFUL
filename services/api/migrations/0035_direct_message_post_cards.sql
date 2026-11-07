-- +goose Up
-- Reference only: body is the canonical post ID until durable recipient ACK.
ALTER TABLE c_dm.messages DROP CONSTRAINT messages_kind_check;
ALTER TABLE c_dm.messages ADD CONSTRAINT dm_post_card_kind CHECK(kind IN ('TEXT','IMAGE','POST'));
ALTER TABLE c_dm.messages ADD CONSTRAINT dm_post_card_reference CHECK(kind<>'POST' OR body IS NULL OR body ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION '0035 contains durable private post references; repair forward'; END $$;
-- +goose StatementEnd
