import 'post_api.dart';
import 'post_models.dart';
import 'post_protocol.dart';

class RankedPost {
  const RankedPost(this.postId, this.title, this.viewCount);

  final String postId, title;
  final int viewCount;

  factory RankedPost.fromJson(Object? raw) {
    final item = PostJson.record(raw, {'postId', 'title', 'viewCount'});
    return RankedPost(
      PostJson.id(item, 'postId'),
      PostJson.text(item, 'title'),
      PostJson.integer(item, 'viewCount', 0, 9007199254740991),
    );
  }
}

class PostRanking {
  const PostRanking(this.channelId, this.items);

  final String channelId;
  final List<RankedPost> items;

  factory PostRanking.fromJson(Object? raw, String channelId) {
    final page = PostJson.record(raw, {'asOf', 'channelId', 'items'});
    PostJson.date(page, 'asOf');
    final values = page['items'];
    if (PostJson.id(page, 'channelId') != channelId ||
        values is! List ||
        values.length > 20) {
      throw const FormatException('Invalid hot posts scope');
    }
    final items = values.map(RankedPost.fromJson).toList(growable: false);
    if (items.map((item) => item.postId).toSet().length != items.length) {
      throw const FormatException('Duplicate hot post');
    }
    return PostRanking(channelId, List.unmodifiable(items));
  }
}

List<String> channelOrderFromJson(Object? raw) {
  final data = PostJson.record(raw, {'asOf', 'channelIds'});
  PostJson.date(data, 'asOf');
  final values = data['channelIds'];
  if (values is! List || values.isEmpty || values.length > 7) {
    throw const FormatException('Invalid channel order');
  }
  final ids = values
      .map((value) {
        if (value is! String) throw const FormatException('Invalid channel ID');
        return PostProtocol.resourceId(value);
      })
      .toList(growable: false);
  if (ids.toSet().length != ids.length) {
    throw const FormatException('Duplicate channel ID');
  }
  return List.unmodifiable(ids);
}

abstract interface class PostRankingApi {
  Future<PostResponse<PostRanking>> hotPosts({
    required String sessionToken,
    required String channelId,
  });
  Future<PostResponse<List<String>>> channelOrder({
    required String sessionToken,
  });
}
