import 'post_api.dart';
import 'post_models.dart';
import 'post_protocol.dart';

/// An external target is public routing data, never a session or a snapshot.
class PostLinkTarget {
  const PostLinkTarget(this.postId, this.url);
  final String postId, url;

  static String origin(Uri base) =>
      base.toString().replaceFirst(RegExp(r'/$'), '');

  static PostLinkTarget? parse(String raw, Uri base) {
    if (raw.length > 4096) return null;
    final prefix = '${origin(base)}/s/posts/';
    const appPrefix = 'speechful://posts/';
    final String id;
    if (raw.startsWith(prefix)) {
      id = raw.substring(prefix.length);
    } else if (raw.startsWith(appPrefix)) {
      id = raw.substring(appPrefix.length);
    } else {
      return null;
    }
    try {
      PostProtocol.resourceId(id);
      return PostLinkTarget(id, '$prefix$id');
    } on FormatException {
      return null;
    }
  }
}

class PostShareLink {
  const PostShareLink({
    required this.postId,
    required this.url,
    required this.text,
  });
  final String postId, url, text;

  factory PostShareLink.fromJson(Object? raw, Uri base, String expectedId) {
    final value = PostJson.record(raw, {'postId', 'url', 'shareText'});
    final id = PostJson.id(value, 'postId');
    final url = PostJson.text(value, 'url');
    final text = PostJson.text(value, 'shareText');
    final target = PostLinkTarget.parse(url, base);
    if (id != expectedId ||
        target?.postId != id ||
        target?.url != url ||
        text != 'SpeechFUL\n$url') {
      throw const FormatException('Invalid content-free share link');
    }
    return PostShareLink(postId: id, url: url, text: text);
  }
}

abstract interface class PostSharingApi {
  Future<PostResponse<PostShareLink>> shareLink({
    required String sessionToken,
    required String postId,
  });
  Future<PostResponse<PostDetail>> resolvePostLink({
    required String sessionToken,
    required String url,
  });
}
