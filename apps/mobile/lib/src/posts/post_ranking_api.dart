import 'post_api.dart';
import 'post_models.dart';

class RankedPost {
  const RankedPost(this.postId, this.channelId, this.title, this.viewCount);
  final String postId, channelId, title;
  final int viewCount;

  factory RankedPost.fromJson(Object? raw) {
    final item = PostJson.record(raw, {
      'postId',
      'channelId',
      'title',
      'viewCount',
    });
    return RankedPost(
      PostJson.id(item, 'postId'),
      PostJson.id(item, 'channelId'),
      PostJson.text(item, 'title'),
      PostJson.integer(item, 'viewCount', 0, 9007199254740991),
    );
  }
}

class PostRanking {
  const PostRanking(this.items);
  final List<RankedPost> items;

  factory PostRanking.fromJson(Object? raw) {
    final page = PostJson.record(raw, {'asOf', 'items'});
    PostJson.date(page, 'asOf');
    final values = page['items'];
    if (values is! List || values.length > 20) {
      throw const FormatException('Invalid global hot posts');
    }
    final items = values.map(RankedPost.fromJson).toList(growable: false);
    if (items.map((item) => item.postId).toSet().length != items.length) {
      throw const FormatException('Duplicate hot post');
    }
    return PostRanking(List.unmodifiable(items));
  }
}

abstract interface class PostRankingApi {
  Future<PostResponse<PostRanking>> hotPosts({required String sessionToken});
}
