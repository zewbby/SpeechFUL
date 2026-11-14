import 'post_api.dart';
import 'post_models.dart';

class PostTags {
  static const maxCount = 3, maxLength = 10;
  static final _word = RegExp(
    r'^[\p{Script=Han}A-Za-z0-9_]{1,10}$',
    unicode: true,
  );

  static String normalize(String value) {
    value = value.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (!_word.hasMatch(value)) {
      throw const FormatException('标签限 1–10 字，仅中文、英文、数字和下划线');
    }
    return value;
  }

  static List<String> normalizeAll(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in values) {
      final value = normalize(raw);
      if (seen.add(value.toLowerCase())) result.add(value);
    }
    if (result.length > maxCount) {
      throw const FormatException('每篇帖子最多 3 个标签');
    }
    return List.unmodifiable(result);
  }

  static List<String> read(Map<String, dynamic> object) {
    if (!object.containsKey('tags')) return const [];
    if (object['tags'] == null) throw const FormatException('Null post tags');
    return parse(object['tags']);
  }

  static List<String> parse(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List || raw.length > maxCount || raw.any((v) => v is! String)) {
      throw const FormatException('Invalid post tags');
    }
    final values = raw.cast<String>();
    final tags = normalizeAll(values);
    if (tags.length != values.length ||
        Iterable<int>.generate(tags.length).any((i) => tags[i] != values[i])) {
      throw const FormatException('Invalid canonical tags');
    }
    return tags;
  }
}

abstract interface class PostTagApi {
  Future<PostResponse<PostsPage<PostCard>>> taggedPosts({
    required String sessionToken,
    required String tag,
    String? channelId,
    String? cursor,
    int limit = 20,
  });
  Future<PostResponse<List<String>>> suggestPostTags({
    required String sessionToken,
    required String prefix,
  });
}
