package authprivacy

import (
	"context"
	"github.com/jackc/pgx/v5/pgxpool"
)

func checkPostTagSchema(ctx context.Context, pool *pgxpool.Pool) error {
	var present, valid, runtime bool
	if err := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass('c_posts.posts') AND attname='tags' AND NOT attisdropped) OR to_regclass('c_posts.post_tag_terms') IS NOT NULL`).Scan(&present); err != nil {
		return errPostSchema
	}
	if !present {
		var tracked bool
		if err := pool.QueryRow(ctx, `SELECT to_regclass('public.goose_db_version') IS NOT NULL`).Scan(&tracked); err != nil {
			return errPostSchema
		}
		if tracked {
			if err := pool.QueryRow(ctx, `SELECT NOT EXISTS(SELECT 1 FROM public.goose_db_version WHERE version_id=33 AND is_applied)`).Scan(&valid); err != nil || !valid {
				return errPostSchema
			}
		}
		return nil
	}
	for table, names := range map[string][]string{"posts": {"tags", "tag_keys"}, "attempt_contents": {"tags"}, "post_tag_terms": {"post_id", "tag_key", "label"}} {
		if err := pool.QueryRow(ctx, `SELECT NOT EXISTS(SELECT 1 FROM unnest($2::text[]) n WHERE NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=to_regclass('c_posts.'||$1) AND a.attname=n AND NOT a.attisdropped))`, table, names).Scan(&valid); err != nil || !valid {
			return errPostSchema
		}
	}
	for _, item := range []struct{ table, name, function string }{{"posts", "post_tags_lifecycle", "fence_post_tags"}, {"posts", "post_tag_terms_sync", "sync_post_tag_terms"}, {"attempt_contents", "attempt_tags_immutable", "fence_attempt_tags"}} {
		if err := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_proc f ON f.oid=t.tgfoid WHERE t.tgrelid=to_regclass('c_posts.'||$1) AND t.tgname=$2 AND t.tgenabled='O' AND NOT t.tgisinternal AND f.oid=to_regprocedure('c_posts.'||$3||'()') AND NOT f.prosecdef)`, item.table, item.name, item.function).Scan(&valid); err != nil || !valid {
			return errPostSchema
		}
	}
	if err := pool.QueryRow(ctx, `SELECT current_user='hnuhole_c_runtime'`).Scan(&runtime); err != nil {
		return errPostSchema
	}
	if runtime {
		if err := pool.QueryRow(ctx, `SELECT has_column_privilege(current_user,'c_posts.posts','tags','UPDATE') AND has_column_privilege(current_user,'c_posts.attempt_contents','tags','UPDATE') AND has_table_privilege(current_user,'c_posts.post_tag_terms','SELECT,INSERT,DELETE') AND NOT has_table_privilege(current_user,'c_posts.post_tag_terms','UPDATE,TRUNCATE,TRIGGER') AND has_function_privilege(current_user,'c_posts.tag_keys(text[])','EXECUTE') AND has_function_privilege(current_user,'c_posts.valid_tags(text[])','EXECUTE')`).Scan(&valid); err != nil || !valid {
			return errPostSchema
		}
	}
	return nil
}
