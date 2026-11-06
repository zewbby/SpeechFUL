import 'dart:typed_data';

import 'post_api.dart';
import 'post_models.dart';
import 'post_protocol.dart';

class PublishedPostEdit {
  const PublishedPostEdit({
    required this.post,
    required this.revision,
    this.imageIds,
  });
  final PostDetail post;
  final String revision;
  final List<String>? imageIds;

  static PublishedPostEdit fromJson(Object? raw) {
    final value = PostJson.record(
      raw,
      {'post', 'revision'},
      optional: {'imageIds'},
    );
    final post = PostDetail.fromJson(value['post']);
    List<String>? imageIds;
    if (value.containsKey('imageIds')) {
      final rawIds = value['imageIds'];
      if (rawIds is! List ||
          rawIds.length != post.imageCount ||
          rawIds.any((id) => id is! String) ||
          rawIds.toSet().length != rawIds.length) {
        throw const FormatException('Mismatched edit images');
      }
      imageIds = List.unmodifiable(
        rawIds.cast<String>().map(PostProtocol.resourceId),
      );
    }
    return PublishedPostEdit(
      post: post,
      revision: PostJson.id(value, 'revision'),
      imageIds: imageIds,
    );
  }
}

class PostEditResult {
  const PostEditResult(this.state, {this.code});
  final String state;
  final String? code;

  static PostEditResult fromJson(Object? raw) {
    final value = PostJson.record(
      raw,
      {'state'},
      optional: {'revision', 'code'},
    );
    switch (value['state']) {
      case 'SAVED':
        PostJson.record(raw, {'state', 'revision'});
        PostJson.id(value, 'revision');
        return const PostEditResult('SAVED');
      case 'PENDING':
        PostJson.record(raw, {'state'});
        return const PostEditResult('PENDING');
      case 'REJECTED':
        PostJson.record(raw, {'state', 'code'});
        final code = PostJson.text(value, 'code');
        if ({
          'POST_EDIT_CONFLICT',
          'POST_EDIT_DELETED',
          'POST_EDIT_HIDDEN',
          'POST_IDENTITY_UNAVAILABLE',
          'POSTING_RESTRICTED',
          'POST_CONTENT_INVALID',
          'POST_EDIT_MEDIA_MISSING',
        }.contains(code)) {
          return PostEditResult('REJECTED', code: code);
        }
    }
    throw const FormatException('Invalid post edit result');
  }
}

abstract interface class PostEditApi {
  Future<PostResponse<PublishedPostEdit>> readEdit({
    required String sessionToken,
    required String postId,
  });

  Future<PostResponse<PostEditResult>> editResult({
    required String sessionToken,
    required String postId,
    required String commandId,
  });

  Future<PostResponse<PostEditResult>> saveEdit({
    required String sessionToken,
    required String postId,
    required String commandId,
    required String revision,
    required String title,
    required String body,
    List<String>? imageIds,
    List<String>? tags,
  });

  Future<PostResponse<bool>> stageEditImage({
    required String sessionToken,
    required String postId,
    required String commandId,
    required String imageId,
    required String mimeType,
    required Uint8List bytes,
  });
}
