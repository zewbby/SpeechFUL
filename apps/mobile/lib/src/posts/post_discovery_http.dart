import 'post_api.dart';
import 'post_models.dart';
import 'post_protocol.dart';
import 'post_search_api.dart';
import 'post_ranking_api.dart';
import 'post_tags.dart';
import 'post_http_transport.dart';

/// Discovery endpoints share transport, never publication or upload state.
class HttpPostDiscoveryApi
    implements PostSearchApi, PostRankingApi, PostTagApi {
  HttpPostDiscoveryApi(this._transport);
  final PostHttpTransport _transport;

  @override
  Future<PostResponse<PostsPage<PostCard>>> searchPosts({
    required String sessionToken,
    required String keyword,
    String? channelId,
    String? postId,
    PostSearchSort sort = PostSearchSort.relevance,
    String? cursor,
    int limit = 20,
    bool recordHistory = false,
  }) => PostHttpTransport.input(() {
    PostHttpTransport.pageQuery(cursor, limit);
    if (cursor != null && recordHistory) {
      throw const FormatException('Continuation cannot record history');
    }
    return _transport.send(
      sessionToken,
      'POST',
      '/api/v1/post-search',
      body: {
        'keyword': normalizePostSearchKeyword(keyword),
        if (postId != null) 'postId': PostProtocol.resourceId(postId),
        if (channelId != null) 'channelId': PostProtocol.resourceId(channelId),
        'sort': sort.name,
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
        if (recordHistory) 'recordHistory': true,
      },
      maxRequestBytes: 2048,
      maxResponseBytes: 384 * 1024,
      decode: (raw) {
        final page = PostsPage.fromJson(raw, PostCard.fromJson);
        final ids = <String>{};
        if (page.items.length > limit ||
            page.items.isEmpty && page.nextCursor != null ||
            cursor != null && page.nextCursor == cursor ||
            page.items.any(
              (post) =>
                  !ids.add(post.postId) ||
                  channelId != null && post.channelId != channelId,
            )) {
          throw const FormatException('Invalid post search page');
        }
        return page;
      },
    );
  });

  @override
  Future<PostResponse<List<String>>> postSearchHistory({
    required String sessionToken,
    String? channelId,
  }) => PostHttpTransport.input(
    () => _transport.send(
      sessionToken,
      'GET',
      '/api/v1/me/post-search-history',
      query: channelId == null
          ? null
          : {'channelId': PostProtocol.resourceId(channelId)},
      decode: _searchHistoryFromJson,
    ),
  );

  @override
  Future<PostResponse<List<String>>> changePostSearchHistory({
    required String sessionToken,
    String? channelId,
    String? removeKeyword,
  }) => PostHttpTransport.input(
    () => _transport.send(
      sessionToken,
      'POST',
      '/api/v1/me/post-search-history',
      body: {
        'action': removeKeyword == null ? 'clear' : 'remove',
        if (channelId != null) 'channelId': PostProtocol.resourceId(channelId),
        if (removeKeyword != null)
          'keyword': normalizePostSearchKeyword(removeKeyword),
      },
      decode: _searchHistoryFromJson,
    ),
  );

  @override
  Future<PostResponse<PostRanking>> hotPosts({required String sessionToken}) =>
      _transport.send(
        sessionToken,
        'GET',
        '/api/v1/feed/hot-posts',
        requestTimeout: const Duration(seconds: 4),
        decode: PostRanking.fromJson,
      );

  static List<String> _searchHistoryFromJson(Object? raw) {
    final values = PostJson.record(raw, {'items'})['items'];
    if (values is! List || values.length > 20) {
      throw const FormatException('Invalid post search history');
    }
    final seen = <String>{};
    return List.unmodifiable(
      values.map((value) {
        if (value is! String ||
            normalizePostSearchKeyword(value) != value ||
            !seen.add(value)) {
          throw const FormatException('Invalid post search history entry');
        }
        return value;
      }),
    );
  }

  @override
  Future<PostResponse<PostsPage<PostCard>>> taggedPosts({
    required String sessionToken,
    required String tag,
    String? channelId,
    String? cursor,
    int limit = 20,
  }) => PostHttpTransport.input(() {
    PostHttpTransport.pageQuery(cursor, limit);
    return _transport.send(
      sessionToken,
      'POST',
      '/api/v1/post-tags/posts',
      body: {
        'tag': PostTags.normalize(tag),
        if (channelId != null) 'channelId': PostProtocol.resourceId(channelId),
        if (cursor != null) 'cursor': PostProtocol.cursor(cursor)!,
        'limit': limit,
      },
      decode: (raw) {
        final page = PostsPage.fromJson(raw, PostCard.fromJson);
        if (page.items.length > limit ||
            page.items.isEmpty && page.nextCursor != null ||
            page.items.map((p) => p.postId).toSet().length !=
                page.items.length ||
            page.items.any(
              (p) =>
                  channelId != null && p.channelId != channelId ||
                  !p.tags.any(
                    (t) =>
                        t.toLowerCase() ==
                        PostTags.normalize(tag).toLowerCase(),
                  ),
            )) {
          throw const FormatException('Invalid tag page');
        }
        return page;
      },
    );
  });
  @override
  Future<PostResponse<List<String>>> suggestPostTags({
    required String sessionToken,
    required String prefix,
  }) => PostHttpTransport.input(
    () => _transport.send(
      sessionToken,
      'POST',
      '/api/v1/post-tags/suggestions',
      body: {'prefix': PostTags.normalize(prefix)},
      decode: (raw) {
        final object = PostJson.record(raw, {'items'});
        final values = object['items'];
        if (values is! List ||
            values.length > 10 ||
            values.any((v) => v is! String)) {
          throw const FormatException('Invalid tag suggestions');
        }
        final tags = <String>[];
        final seen = <String>{};
        for (final raw in values) {
          final tag = raw as String;
          if (PostTags.normalize(tag) != tag ||
              !seen.add(tag.toLowerCase()) ||
              !tag.toLowerCase().startsWith(
                PostTags.normalize(prefix).toLowerCase(),
              )) {
            throw const FormatException('Invalid tag suggestion');
          }
          tags.add(tag);
        }
        return List.unmodifiable(tags);
      },
    ),
  );
}
