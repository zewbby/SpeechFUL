import 'post_api.dart';
import 'post_models.dart';
import 'post_protocol.dart';
import 'post_tags.dart';

/// New public feed projection; legacy PostCard/Detail remain strict and unchanged.
class FeedPost extends PostCard {
  const FeedPost({
    required super.postId,
    required super.channelId,
    required super.title,
    required super.author,
    required super.publishedAt,
    super.tags,
    required this.body,
    required this.viewCount,
    this.imageCount = 0,
    this.imageSizes,
  });
  final String body;
  final int viewCount, imageCount;
  final List<({int width, int height})>? imageSizes;
  static FeedPost fromJson(Object? raw) {
    final m = PostJson.record(
      raw,
      {
        'postId',
        'channelId',
        'title',
        'body',
        'author',
        'publishedAt',
        'viewCount',
      },
      optional: {'imageCount', 'imageSizes', 'tags'},
    );
    final title = PostJson.text(m, 'title', maxLength: 4096);
    final imageCount = PostJson.imageCount(m);
    List<({int width, int height})>? sizes;
    if (m.containsKey('imageSizes')) {
      final rawSizes = m['imageSizes'];
      if (rawSizes is! List || rawSizes.length != imageCount) {
        throw const FormatException('Mismatched feed image geometry');
      }
      sizes = List.unmodifiable(
        rawSizes.map((raw) {
          final size = PostJson.record(raw, {'width', 'height'});
          final width = PostJson.integer(size, 'width', 1, 16384);
          final height = PostJson.integer(size, 'height', 1, 16384);
          if (width * height > 12 * 1024 * 1024) {
            throw const FormatException('Invalid feed image geometry');
          }
          return (width: width, height: height);
        }),
      );
    }
    final body = PostJson.text(
      m,
      'body',
      maxLength: 65536,
      allowEmpty: imageCount > 0,
    );
    PostContentRules.validateTitle(title);
    if (body.isNotEmpty || imageCount == 0) {
      PostContentRules.validateBody(body);
    }
    return FeedPost(
      postId: PostJson.id(m, 'postId'),
      channelId: PostJson.id(m, 'channelId'),
      title: title,
      body: body,
      author: PostAuthor.fromJson(m['author']),
      publishedAt: PostJson.date(m, 'publishedAt'),
      viewCount: PostJson.integer(m, 'viewCount', 0, 9223372036854775807),
      imageCount: imageCount,
      imageSizes: sizes,
      tags: PostTags.read(m),
    );
  }
}

class FeedPreferences {
  FeedPreferences(Iterable<String> ids)
    : blockedChannelIds = Set.unmodifiable(ids) {
    if (blockedChannelIds.length > 7) {
      throw const FormatException('Too many channels');
    }
    for (final id in blockedChannelIds) {
      PostProtocol.resourceId(id);
    }
  }
  final Set<String> blockedChannelIds;
  static FeedPreferences fromJson(Object? raw) {
    final m = PostJson.record(raw, {'blockedChannelIds'});
    final ids = m['blockedChannelIds'];
    if (ids is! List ||
        ids.any((id) => id is! String) ||
        ids.toSet().length != ids.length) {
      throw const FormatException('Invalid feed preferences');
    }
    return FeedPreferences(ids.cast<String>());
  }
}

class PostViews {
  const PostViews(this.postId, this.viewCount);
  final String postId;
  final int viewCount;
  static PostViews fromJson(Object? raw) {
    final m = PostJson.record(raw, {'postId', 'viewCount'});
    return PostViews(
      PostJson.id(m, 'postId'),
      PostJson.integer(m, 'viewCount', 0, 9223372036854775807),
    );
  }
}

/// A public author header plus that identity's published posts. The source
/// post anchors the author; the payload never carries an identity selector.
class AuthorProfile {
  AuthorProfile({
    required this.author,
    required List<FeedPost> items,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);
  final PostAuthor author;
  final List<FeedPost> items;
  final String? nextCursor;
  static AuthorProfile fromJson(Object? raw) {
    final m = PostJson.record(raw, {'author', 'items', 'nextCursor'});
    final items = m['items'];
    if (items is! List ||
        items.length > 50 ||
        m['nextCursor'] != null && m['nextCursor'] is! String) {
      throw const FormatException('Invalid author profile');
    }
    final author = PostAuthor.fromJson(m['author']);
    final posts = items.map(FeedPost.fromJson).toList(growable: false);
    if (posts.map((post) => post.postId).toSet().length != posts.length ||
        posts.any((post) => !_sameAuthor(post.author, author))) {
      throw const FormatException('Invalid author profile posts');
    }
    return AuthorProfile(
      author: author,
      items: posts,
      nextCursor: PostProtocol.cursor(m['nextCursor'] as String?),
    );
  }

  static bool _sameAuthor(PostAuthor left, PostAuthor right) =>
      left.state == right.state &&
      left.avatar == right.avatar &&
      left.nickname == right.nickname &&
      left.shortCode == right.shortCode;
}

abstract interface class FeedApi {
  Future<PostResponse<PostsPage<FeedPost>>> timeline({
    required String sessionToken,
    String? channelId,
    String? cursor,
    int limit = 20,
  });
  Future<PostResponse<AuthorProfile>> authorProfile({
    required String sessionToken,
    required String postId,
    String? cursor,
    int limit = 20,
  });
  Future<PostResponse<FeedPreferences>> feedPreferences({
    required String sessionToken,
  });
  Future<PostResponse<FeedPreferences>> saveFeedPreferences({
    required String sessionToken,
    required Set<String> blockedChannelIds,
  });
  Future<PostResponse<PostViews>> registerPostView({
    required String sessionToken,
    required String postId,
  });
}
