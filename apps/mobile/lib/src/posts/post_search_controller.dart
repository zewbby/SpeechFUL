import 'post_api.dart';
import 'post_models.dart';
import 'post_search_api.dart';
import 'post_ranking_api.dart';
import 'post_tags.dart';

typedef PostDiscoveryRequest = Future<T> Function<T>(
  Future<PostResponse<T>> Function(String) request, {
  bool optional,
});

/// Search, tag and ranking use cases; authority stays with the session owner.
class PostSearchController {
  PostSearchController({required this.api, required this.request});

  final PostApi api;
  final PostDiscoveryRequest request;

  Future<List<String>> suggestPostTags(String prefix) => api is! PostTagApi
      ? Future.value(const [])
      : request(
          (token) => (api as PostTagApi).suggestPostTags(
            sessionToken: token,
            prefix: prefix,
          ),
        );
  Future<PostsPage<PostCard>> taggedPosts(
    String tag, {
    String? channelId,
    String? cursor,
  }) => request(
    (token) => (api as PostTagApi).taggedPosts(
      sessionToken: token,
      tag: tag,
      channelId: channelId,
      cursor: cursor,
    ),
  );
  Future<PostDetail> readTaggedPost(String id) =>
      request((token) => api.detail(sessionToken: token, postId: id));
  bool get supportsPostSearch => api is PostSearchApi;
  bool get supportsPostRankings => api is PostRankingApi;

  Future<PostRanking> hotPosts() => request(
    (token) => (api as PostRankingApi).hotPosts(sessionToken: token),
    optional: true,
  );

  Future<PostsPage<PostCard>> searchPosts({
    required String keyword,
    required String? channelId,
    required PostSearchSort sort,
    String? cursor,
    bool recordHistory = false,
    String? postId,
  }) => _withSearchAuthority(
    (api, token) => api.searchPosts(
      sessionToken: token,
      keyword: keyword,
      channelId: channelId,
      sort: sort,
      cursor: cursor,
      recordHistory: recordHistory,
      postId: postId,
    ),
  );

  Future<List<String>> postSearchHistory(String? channelId) =>
      _withSearchAuthority(
        (api, token) =>
            api.postSearchHistory(sessionToken: token, channelId: channelId),
      );

  Future<List<String>> changePostSearchHistory(
    String? channelId, {
    String? removeKeyword,
  }) => _withSearchAuthority(
    (api, token) => api.changePostSearchHistory(
      sessionToken: token,
      channelId: channelId,
      removeKeyword: removeKeyword,
    ),
  );

  Future<T> _withSearchAuthority<T>(
    Future<PostResponse<T>> Function(PostSearchApi, String) request,
  ) => this.request((token) => request(api as PostSearchApi, token));
}
