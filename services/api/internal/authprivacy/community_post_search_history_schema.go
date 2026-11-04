package authprivacy

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

func checkPostSearchHistorySchema(ctx context.Context, pool *pgxpool.Pool, required bool) error {
	var present, tracker, valid, runtime bool
	if err := pool.QueryRow(ctx, `SELECT to_regclass('c_posts.post_search_history') IS NOT NULL,
 to_regclass('public.goose_db_version') IS NOT NULL,current_user='hnuhole_c_runtime'`).Scan(&present, &tracker, &runtime); err != nil {
		return errPostSchema
	}
	if !present && !required {
		if tracker {
			if err := pool.QueryRow(ctx, `SELECT NOT EXISTS(SELECT 1 FROM public.goose_db_version WHERE version_id>=29 AND is_applied)`).Scan(&valid); err != nil || !valid {
				return errPostSchema
			}
		}
		return nil
	}
	if err := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_class WHERE oid='c_posts.post_search_history'::regclass AND relkind='r' AND relpersistence='p')
 AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['account_id','channel_id','keyword','keyword_key','sort_at']) AS expected(name)
  WHERE NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid='c_posts.post_search_history'::regclass
   AND a.attname=expected.name AND a.attnum>0 AND NOT a.attisdropped AND a.attnotnull=(expected.name<>'channel_id')))
 AND NOT EXISTS(SELECT 1 FROM (VALUES('post_search_history_keyword','keyword_key'),('post_search_history_order','sort_at')) AS expected(name,last_column)
  WHERE NOT EXISTS(SELECT 1 FROM pg_constraint c JOIN pg_index i ON i.indexrelid=c.conindid
   WHERE c.conrelid='c_posts.post_search_history'::regclass AND c.conname=expected.name AND c.contype='u'
   AND c.convalidated AND NOT c.condeferrable AND i.indnullsnotdistinct
   AND c.conkey=ARRAY(SELECT a.attnum FROM unnest(ARRAY['account_id','channel_id',expected.last_column]) WITH ORDINALITY AS cols(name,pos)
    JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attname=cols.name AND NOT a.attisdropped ORDER BY cols.pos)))
 AND EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
  WHERE t.tgrelid='c_auth.accounts'::regclass AND t.tgname='post_search_history_account_closed'
   AND t.tgenabled='O' AND NOT t.tgisinternal AND t.tgtype=17
   AND p.oid='c_posts.clear_closed_account_post_search_history()'::regprocedure AND NOT p.prosecdef)`).Scan(&valid); err != nil || !valid {
		return errPostSchema
	}
	if !runtime {
		return nil
	}
	if err := pool.QueryRow(ctx, `SELECT has_schema_privilege(current_user,'c_posts','USAGE') AND NOT has_schema_privilege(current_user,'c_posts','CREATE')
 AND has_table_privilege(current_user,'c_posts.post_search_history','SELECT')
 AND has_table_privilege(current_user,'c_posts.post_search_history','INSERT')
 AND has_table_privilege(current_user,'c_posts.post_search_history','DELETE')
 AND NOT has_table_privilege(current_user,'c_posts.post_search_history','UPDATE,TRUNCATE,TRIGGER,REFERENCES')
 AND has_column_privilege(current_user,'c_posts.post_search_history','keyword','UPDATE')
 AND has_column_privilege(current_user,'c_posts.post_search_history','sort_at','UPDATE')
 AND NOT has_column_privilege(current_user,'c_posts.post_search_history','account_id','UPDATE')
 AND NOT has_column_privilege(current_user,'c_posts.post_search_history','channel_id','UPDATE')
 AND NOT has_column_privilege(current_user,'c_posts.post_search_history','keyword_key','UPDATE')`).Scan(&valid); err != nil || !valid {
		return errPostSchema
	}
	return nil
}
