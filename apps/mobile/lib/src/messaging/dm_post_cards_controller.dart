part of 'dm_controller.dart';

extension DmPostCardsController on DmController {
  Future<Map<String, dynamic>> _postCard(String postId) async {
    if (!available || !chatEnabled) throw StateError('DM unavailable');
    final epoch = _epoch;
    final result = await _request(epoch, _token!, 'GET', 'chat/posts/$postId');
    if (!_current(epoch)) throw StateError('DM window expired');
    return result;
  }

  Future<String> _sharePost(
    Map<String, dynamic> directory,
    String postId,
  ) async {
    if (!available ||
        !chatEnabled ||
        directory['canShare'] != true ||
        !_identities.contains(directory['identityId'])) {
      throw StateError('Sharing unavailable');
    }
    final epoch = _epoch, store = _store!;
    final id = await store.enqueue({
      'kind': 'POST',
      'identityId': directory['identityId'] as String,
      'peerId': directory['peerId'] as String,
      'conversationId': directory['id'] as String,
      'sourcePostId': '',
      'sourceCommentId': '',
      'text': postId,
      'attempt': 1,
    });
    if (!_current(epoch)) throw StateError('DM window expired');
    // Once enqueue committed, projection/network failures must not invite a
    // second command. The durable original remains visible in the conversation.
    try {
      await sync();
      if (!_current(epoch)) throw StateError('DM window expired');
      final row = await store.get(id);
      if (!_current(epoch)) throw StateError('DM window expired');
      return row?['_state'] as String? ?? 'unknown';
    } catch (_) {
      if (!_current(epoch)) rethrow;
      return 'unknown';
    }
  }
}
