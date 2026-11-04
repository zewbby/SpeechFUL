import 'post_api.dart';
import 'post_models.dart';
import 'post_protocol.dart';

enum PostSearchSort { relevance, latest }

String trimPostSearchKeyword(String value) {
  var start = 0;
  var end = value.length;
  while (start < end && PostContentRules.whiteSpace(value.codeUnitAt(start))) {
    ++start;
  }
  while (end > start &&
      PostContentRules.whiteSpace(value.codeUnitAt(end - 1))) {
    --end;
  }
  return value.substring(start, end);
}

String normalizePostSearchKeyword(String value) {
  PostContentRules.scalarText(value);
  final keyword = trimPostSearchKeyword(value);
  if (keyword.isEmpty ||
      keyword.runes.length > 100 ||
      keyword.runes.any((r) => r < 0x20 || r >= 0x7f && r <= 0x9f)) {
    throw const FormatException('Invalid search keyword');
  }
  return keyword;
}

abstract interface class PostSearchApi {
  Future<PostResponse<PostsPage<PostCard>>> searchPosts({
    required String sessionToken,
    required String keyword,
    String? channelId,
    PostSearchSort sort = PostSearchSort.relevance,
    String? cursor,
    int limit = 20,
    bool recordHistory = false,
  });
  Future<PostResponse<List<String>>> postSearchHistory({
    required String sessionToken,
    String? channelId,
  });
  Future<PostResponse<List<String>>> changePostSearchHistory({
    required String sessionToken,
    String? channelId,
    String? removeKeyword,
  });
}
