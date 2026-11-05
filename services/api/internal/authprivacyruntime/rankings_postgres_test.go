package authprivacyruntime

import (
	"context"
	"testing"
)

func TestFeedRankingRuntimeGrantsPostgres(t *testing.T) {
	_, runtime := moderationStartupLab(t)
	ctx := context.Background()
	var valid bool
	if err := runtime.QueryRow(ctx, `SELECT
		has_table_privilege('c_posts.ranking_inputs','SELECT') AND
		has_column_privilege('c_posts.ranking_inputs','revision','UPDATE') AND
		NOT has_column_privilege('c_posts.ranking_inputs','channel_id','UPDATE') AND
		has_table_privilege('c_posts.ranking_snapshots','SELECT') AND
		has_table_privilege('c_posts.ranking_snapshots','INSERT') AND
		has_table_privilege('c_posts.ranking_snapshots','DELETE') AND
		has_column_privilege('c_posts.ranking_snapshots','channel_ids','UPDATE') AND
		NOT has_column_privilege('c_posts.ranking_snapshots','version','UPDATE') AND
		has_table_privilege('c_posts.ranking_posts','SELECT') AND
		has_table_privilege('c_posts.ranking_posts','INSERT') AND
		NOT has_table_privilege('c_posts.ranking_posts','UPDATE') AND
		has_table_privilege('c_posts.ranking_channel_data','SELECT') AND
		has_table_privilege('c_posts.ranking_channel_data','INSERT') AND
		has_table_privilege('c_posts.ranking_channel_data','DELETE') AND
		NOT has_table_privilege('c_posts.ranking_channel_data','UPDATE')`).Scan(&valid); err != nil || !valid {
		t.Fatal("rankings least-privilege grants are incomplete", err)
	}
	// Every source mutation path must be able to execute the trigger through
	// the runtime role, even when the optional ranking HTTP feature is off.
	for _, sql := range []string{
		"DELETE FROM c_posts.post_likes WHERE false",
		"DELETE FROM c_posts.post_favorites WHERE false",
		"UPDATE c_posts.posts SET visibility=visibility WHERE false",
	} {
		if _, err := runtime.Exec(ctx, sql); err != nil {
			t.Fatal("runtime could not invoke source revision trigger", err)
		}
	}
}
