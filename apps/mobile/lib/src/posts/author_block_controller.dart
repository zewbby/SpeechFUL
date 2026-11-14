part of 'post_controller.dart';

extension AuthorBlockController on PostController {
  bool get supportsAuthorBlock => _api is AuthorBlockApi;

  bool authorBlockBusy(String postId) => _authorBlockWrites.contains(postId);
  bool authorBlockRemoving(String blockId) =>
      _authorBlockRemovals.contains(blockId);

  /// Blocks the account behind [postId] for the current account. Both sides
  /// lose posts, comments and future direct messages. Returns whether the
  /// committed state was observed; [authorBlockError] explains a failure.
  Future<bool> blockAuthor(String postId) async {
    if (!available ||
        _api is! AuthorBlockApi ||
        _authorBlockWrites.contains(postId)) {
      return false;
    }
    final api = _api as AuthorBlockApi;
    final epoch = _epoch;
    _authorBlockWrites.add(postId);
    authorBlockError = null;
    _notify();
    try {
      // Retrying the same anchor is idempotent; the anchor read deliberately
      // bypasses the new block so a lost response converges.
      await _withDiscoveryAuthority(
        (token) => api.blockPostAuthor(sessionToken: token, postId: postId),
      );
      if (epoch != _epoch) return false;
      invalidateAuthorVisibility();
      return true;
    } on PostFailure catch (error) {
      if (epoch != _epoch) return false;
      authorBlockError = switch (error.code) {
        'SELF_BLOCK_REJECTED' => '不能拉黑自己',
        'POST_NOT_FOUND' => '该作者已不可用',
        _ => '暂时无法拉黑，请重试。',
      };
      return false;
    } on _StalePostAuthority {
      return false;
    } finally {
      if (epoch == _epoch) {
        _authorBlockWrites.remove(postId);
        _notify();
      }
    }
  }

  /// Reads the private block list. A stale account window throws instead of
  /// returning another account's rows.
  Future<List<BlockedAuthor>> blockedAuthors() async {
    if (_api case final AuthorBlockApi api) {
      final page = await _withDiscoveryAuthority(
        (token) => api.blockedAuthors(sessionToken: token),
      );
      return page.items;
    }
    throw UnsupportedError('Author block is unavailable');
  }

  /// A record that no longer exists (`ABSENT`) is still a converged success;
  /// an unowned record is indistinguishable from it.
  Future<bool> unblockAuthor(String blockId) async {
    if (!available ||
        _api is! AuthorBlockApi ||
        _authorBlockRemovals.contains(blockId)) {
      return false;
    }
    final api = _api as AuthorBlockApi;
    final epoch = _epoch;
    _authorBlockRemovals.add(blockId);
    authorBlockError = null;
    _notify();
    try {
      await _withDiscoveryAuthority(
        (token) => api.unblockAuthor(sessionToken: token, blockId: blockId),
      );
      if (epoch != _epoch) return false;
      invalidateAuthorVisibility();
      return true;
    } on PostFailure {
      if (epoch != _epoch) return false;
      authorBlockError = '暂时无法解除，请重试。';
      return false;
    } on _StalePostAuthority {
      return false;
    } finally {
      if (epoch == _epoch) {
        _authorBlockRemovals.remove(blockId);
        _notify();
      }
    }
  }

  /// A committed block/unblock makes every retained page stale. Clear first so
  /// a failed refresh can never keep showing the now-invisible author.
  void invalidateAuthorVisibility() {
    ++_feedRequest;
    ++authorVisibilityEpoch;
    feedLoading = false;
    feedItems = [];
    feedCursor = null;
    feedError = null;
    _homeFeed.invalidateVisibility(notify: false);
    _notify();
  }

  /// Reloads only the surfaces that already showed content.
  Future<void> reloadVisibleFeeds() async {
    final channel = currentChannelId;
    if (channel != null) {
      await loadFeed(channel);
    }
    final home = _homeFeed;
    if (home.supportsFeed && home.available && home.timelineEverLoaded) {
      await home.loadTimeline(channelId: home.timelineChannelId);
    }
  }
}
