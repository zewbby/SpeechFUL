import 'post_api.dart';
import 'post_models.dart';

/// Account-level author block snapshot. The server never returns the blocked
/// account or identity identifiers, only the public author projection captured
/// when the block was created.
class BlockedAuthor {
  const BlockedAuthor({
    required this.blockId,
    required this.author,
    required this.blockedAt,
  });
  final String blockId;
  final PostAuthor author;
  final DateTime blockedAt;

  static BlockedAuthor fromJson(Object? raw) {
    final m = PostJson.record(raw, {'blockId', 'author', 'blockedAt'});
    return BlockedAuthor(
      blockId: PostJson.id(m, 'blockId'),
      author: PostAuthor.fromJson(m['author']),
      blockedAt: PostJson.date(m, 'blockedAt'),
    );
  }
}

/// The list is bounded (not paginated) exactly like the DM block list.
class BlockedAuthorPage {
  BlockedAuthorPage(List<BlockedAuthor> items)
    : items = List.unmodifiable(items);
  static const maxItems = 200;
  final List<BlockedAuthor> items;

  static BlockedAuthorPage fromJson(Object? raw) {
    final m = PostJson.record(raw, {'items'});
    final items = m['items'];
    if (items is! List || items.length > maxItems) {
      throw const FormatException('Invalid blocked author page');
    }
    final page = items.map(BlockedAuthor.fromJson).toList(growable: false);
    if (page.map((item) => item.blockId).toSet().length != page.length) {
      throw const FormatException('Duplicate blocked authors');
    }
    return BlockedAuthorPage(page);
  }
}

/// A committed block is idempotent: retrying the same source post returns the
/// original record and timestamp.
class AuthorBlockReceipt {
  const AuthorBlockReceipt({
    required this.blockId,
    required this.author,
    required this.blockedAt,
  });
  final String blockId;
  final PostAuthor author;
  final DateTime blockedAt;

  static AuthorBlockReceipt fromJson(Object? raw) {
    final m = PostJson.record(raw, {'blockId', 'state', 'author', 'blockedAt'});
    if (m['state'] != 'BLOCKED') {
      throw const FormatException('Invalid author block receipt');
    }
    return AuthorBlockReceipt(
      blockId: PostJson.id(m, 'blockId'),
      author: PostAuthor.fromJson(m['author']),
      blockedAt: PostJson.date(m, 'blockedAt'),
    );
  }
}

/// [state] is `REMOVED` when a record was deleted and `ABSENT` when it no
/// longer exists, so a retried unblock converges without revealing ownership.
class AuthorBlockRemoval {
  const AuthorBlockRemoval({required this.blockId, required this.state});
  final String blockId, state;
  bool get removed => state == 'REMOVED';

  static AuthorBlockRemoval fromJson(Object? raw) {
    final m = PostJson.record(raw, {'blockId', 'state'});
    final state = m['state'];
    if (state != 'REMOVED' && state != 'ABSENT') {
      throw const FormatException('Invalid author block removal');
    }
    return AuthorBlockRemoval(
      blockId: PostJson.id(m, 'blockId'),
      state: state as String,
    );
  }
}

abstract interface class AuthorBlockApi {
  Future<PostResponse<AuthorBlockReceipt>> blockPostAuthor({
    required String sessionToken,
    required String postId,
  });
  Future<PostResponse<BlockedAuthorPage>> blockedAuthors({
    required String sessionToken,
  });
  Future<PostResponse<AuthorBlockRemoval>> unblockAuthor({
    required String sessionToken,
    required String blockId,
  });
}
