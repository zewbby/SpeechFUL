part of 'post_controller.dart';

extension PostSearchController on PostController {
  bool get supportsPostSearch => _api is PostSearchApi;
  bool get supportsPostRankings => _api is PostRankingApi;

  Future<PostRanking> hotPosts(String channelId) => _withDiscoveryAuthority(
    (token) => (_api as PostRankingApi).hotPosts(
      sessionToken: token,
      channelId: channelId,
    ),
    optional: true,
  );

  Future<List<String>> channelOrder() => _withDiscoveryAuthority(
    (token) => (_api as PostRankingApi).channelOrder(sessionToken: token),
    optional: true,
  );

  Future<PostsPage<PostCard>> searchPosts({
    required String keyword,
    required String? channelId,
    required PostSearchSort sort,
    String? cursor,
    bool recordHistory = false,
  }) => _withSearchAuthority(
    (api, token) => api.searchPosts(
      sessionToken: token,
      keyword: keyword,
      channelId: channelId,
      sort: sort,
      cursor: cursor,
      recordHistory: recordHistory,
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
  ) =>
      _withDiscoveryAuthority((token) => request(_api as PostSearchApi, token));

  Future<T> _withDiscoveryAuthority<T>(
    Future<PostResponse<T>> Function(String) request, {
    bool optional = false,
  }) async {
    final authority = await _authority();
    if (!_current(authority)) throw _StalePostAuthority();
    try {
      return await _accept(authority, await request(authority.token));
    } on PostFailure catch (error) {
      if (_current(authority)) {
        if (error.kind == PostFailureKind.unauthorized) {
          _sessions.sessionUnauthorized(authority.token, error.code);
        } else if (error.code == 'AUTHORIZATION_UNAVAILABLE' ||
            !optional &&
                error.kind == PostFailureKind.unavailable &&
                error.code == null ||
            error.statusCode == 403 && error.code == 'AUTHENTICATION_FAILED') {
          _sessions.sessionUnavailable(authority.token);
        }
      }
      rethrow;
    }
  }
}
