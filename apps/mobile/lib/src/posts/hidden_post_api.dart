import 'post_api.dart';
import 'post_models.dart';

class HiddenPostState {
  const HiddenPostState({required this.postId, required this.hidden});
  final String postId;
  final bool hidden;

  static HiddenPostState fromJson(Object? raw) {
    final object = PostJson.record(raw, {'postId', 'hidden'});
    final hidden = object['hidden'];
    if (hidden is! bool) throw const FormatException('Invalid hidden state');
    return HiddenPostState(
      postId: PostJson.id(object, 'postId'),
      hidden: hidden,
    );
  }
}

abstract interface class HiddenPostApi {
  Future<PostResponse<HiddenPostState>> hiddenPost({
    required String sessionToken,
    required String postId,
  });
  Future<PostResponse<HiddenPostState>> setHiddenPost({
    required String sessionToken,
    required String postId,
    required bool hidden,
    required String version,
  });
}
