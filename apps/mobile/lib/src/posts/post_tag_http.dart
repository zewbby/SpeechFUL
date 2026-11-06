part of 'http_post_api.dart';

extension PostTagsHttp on HttpPostApi {
  Future<PostResponse<PostsPage<PostCard>>> _taggedPosts({
    required String sessionToken,
    required String tag,
    String? channelId,
    String? cursor,
    int limit = 20,
  }) => _input(() {
    HttpPostApi._pageQuery(cursor, limit);
    return _send(
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
  Future<PostResponse<List<String>>> _suggestPostTags({
    required String sessionToken,
    required String prefix,
  }) => _input(
    () => _send(
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
