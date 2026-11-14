part of 'http_post_api.dart';

extension _AuthorBlockHttp on HttpPostApi {
  Future<PostResponse<AuthorBlockReceipt>> _blockPostAuthor({
    required String sessionToken,
    required String postId,
  }) => _input(
    () => _send(
      sessionToken,
      'PUT',
      '/api/v1/posts/${PostProtocol.resourceId(postId)}/author/block',
      decode: AuthorBlockReceipt.fromJson,
    ),
  );

  Future<PostResponse<BlockedAuthorPage>> _blockedAuthors({
    required String sessionToken,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/blocked-authors',
      maxResponseBytes: 512 * 1024,
      maxJsonItems: BlockedAuthorPage.maxItems,
      decode: BlockedAuthorPage.fromJson,
    ),
  );

  Future<PostResponse<AuthorBlockRemoval>> _unblockAuthor({
    required String sessionToken,
    required String blockId,
  }) => _input(
    () => _send(
      sessionToken,
      'DELETE',
      '/api/v1/me/blocked-authors/${PostProtocol.resourceId(blockId)}',
      decode: (raw) {
        final removal = AuthorBlockRemoval.fromJson(raw);
        if (removal.blockId != blockId) {
          throw const FormatException('Mismatched unblocked author');
        }
        return removal;
      },
    ),
  );
}
