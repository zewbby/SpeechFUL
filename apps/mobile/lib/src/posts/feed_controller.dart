import 'package:flutter/foundation.dart';

import 'feed_api.dart';
import 'post_api.dart';
import 'post_models.dart';

/// One captured account window. The session owner persists response metadata
/// and rejects stale responses before returning their values to the feed.
abstract interface class FeedReadSession {
  bool get isCurrent;
  Future<T> request<T>(
    Future<PostResponse<T>> Function(String sessionToken) send,
  );
  void reportFailure(Object error);
}

/// Owns home timeline state, pagination, preferences and observed view counts.
/// Publication, storage, sessions and shared interactions have separate owners.
class FeedController extends ChangeNotifier {
  FeedController({
    required this._api,
    required this._available,
    required this._openSession,
    required this._invalidateInteractionReads,
    required this._loadInteractions,
    required this._isPostDeleted,
  });

  final FeedApi? _api;
  final bool Function() _available;
  final Future<FeedReadSession> Function() _openSession;
  final VoidCallback _invalidateInteractionReads;
  final Future<bool> Function(List<String>) _loadInteractions;
  final bool Function(String) _isPostDeleted;
  List<FeedPost> _timeline = [];
  Set<String> _blockedChannels = {};
  final _postViews = <String, int>{};
  bool _preferencesReady = false, _disposed = false;
  int _epoch = 0, _timelineRequest = 0, _timelineGeneration = 0;
  String? _timelineChannelId,
      _timelineCursor,
      _timelineError,
      _preferencesError;
  bool _timelineLoading = false,
      _preferencesSaving = false,
      _timelineLoaded = false;
  Future<void> _preferenceWrites = Future.value();

  bool get supportsFeed => _api != null;
  bool get available => !_disposed && _available();
  bool get feedPreferencesReady => _preferencesReady;
  int get timelineGeneration => _timelineGeneration;
  String? get timelineChannelId => _timelineChannelId;
  String? get timelineCursor => _timelineCursor;
  String? get timelineError => _timelineError;
  String? get preferencesError => _preferencesError;
  bool get timelineLoading => _timelineLoading;
  bool get preferencesSaving => _preferencesSaving;

  /// Whether at least one page was accepted, so a visibility write knows this
  /// surface was already showing content.
  bool get timelineEverLoaded => _timelineLoaded;

  List<FeedPost> get timelineItems =>
      List.unmodifiable(_timeline.where((p) => !_isPostDeleted(p.postId)));
  Set<String> get blockedChannelIds => Set.unmodifiable(_blockedChannels);
  int? postViewCount(String id) => _postViews[id];

  /// The account owner can batch this reset with its other state changes.
  void reset() {
    ++_epoch;
    ++_timelineRequest;
    _timeline = [];
    _blockedChannels = {};
    _postViews.clear();
    _preferencesReady = false;
    _timelineLoaded = false;
    _timelineChannelId = _timelineCursor = _timelineError = _preferencesError =
        null;
    _timelineLoading = _preferencesSaving = false;
    // A new account never waits behind the old account's pending network request.
    _preferenceWrites = Future.value();
    _notify();
  }

  /// A confirmed hide fences the page that started before that write.
  void invalidatePendingRead({bool notify = true}) {
    if (!_timelineLoading) return;
    ++_timelineRequest;
    _timelineLoading = false;
    if (notify) _notify();
  }

  /// A committed visibility write (block/unblock) invalidates every retained
  /// page while keeping the selected channel for the next reload.
  void invalidateVisibility({bool notify = true}) {
    ++_timelineRequest;
    ++_timelineGeneration;
    _timeline = [];
    _timelineCursor = null;
    _timelineError = null;
    _timelineLoading = false;
    if (notify) _notify();
  }

  /// Apply an edit to retained rows without letting an older page restore it.
  void applyEditedPost(PostDetail post, {bool notify = true}) {
    ++_timelineRequest;
    _timelineLoading = false;
    _timeline = [
      for (final old in _timeline)
        if (old.postId == post.postId)
          FeedPost(
            postId: post.postId,
            channelId: post.channelId,
            title: post.title,
            author: post.author,
            publishedAt: post.publishedAt,
            body: post.body,
            tags: post.tags,
            viewCount: old.viewCount,
            imageCount: post.imageCount,
          )
        else
          old,
    ];
    if (notify) _notify();
  }

  Future<void> loadTimeline({
    String? channelId,
    bool more = false,
    bool recoverMissingInteractions = true,
  }) async {
    if (!supportsFeed || !available || _preferencesSaving) return;
    if (more &&
        (_timelineLoading ||
            _timelineCursor == null ||
            channelId != _timelineChannelId)) {
      return;
    }
    final request = ++_timelineRequest;
    final epoch = _epoch;
    final cursor = more ? _timelineCursor : null;
    if (!more) {
      _invalidateInteractionReads();
      if (_timelineChannelId != channelId || !_preferencesReady) {
        _timeline = [];
        _timelineCursor = null;
      }
      _timelineChannelId = channelId;
    }
    _timelineLoading = true;
    _timelineError = null;
    _notify();
    FeedReadSession? a;
    try {
      a = await _openSession();
      if (epoch != _epoch || request != _timelineRequest) return;
      if (!_preferencesReady || !more) {
        final reconciling = !_preferencesReady;
        final preferences = await a.request(
          (token) => _api!.feedPreferences(sessionToken: token),
        );
        if (request != _timelineRequest) return;
        _blockedChannels = preferences.blockedChannelIds;
        _timeline = _timeline
            .where((post) => !_blockedChannels.contains(post.channelId))
            .toList();
        _preferencesReady = true;
        _notify();
        if (reconciling) _preferencesError = null;
      }
      final page = await a.request(
        (token) => _api!.timeline(
          sessionToken: token,
          channelId: channelId,
          cursor: cursor,
        ),
      );
      if (request != _timelineRequest) return;
      if (page.items.any(
        (p) =>
            _blockedChannels.contains(p.channelId) ||
            channelId != null && p.channelId != channelId,
      )) {
        throw const PostFailure(kind: PostFailureKind.invalidResponse);
      }
      final ids = (more ? _timeline : <FeedPost>[])
          .map((p) => p.postId)
          .toSet();
      _timeline = [
        if (more) ..._timeline,
        ...page.items.where(
          (p) => !_isPostDeleted(p.postId) && ids.add(p.postId),
        ),
      ];
      for (final post in page.items) {
        final old = _postViews[post.postId] ?? 0;
        _postViews[post.postId] = post.viewCount > old ? post.viewCount : old;
      }
      _timelineCursor = page.nextCursor;
      _timelineLoaded = true;
      if (!more) _timelineGeneration++;
      _notify();
      final found = await _loadInteractions(
        page.items.map((p) => p.postId).toList(),
      );
      if (!found &&
          recoverMissingInteractions &&
          a.isCurrent &&
          request == _timelineRequest) {
        await loadTimeline(
          channelId: channelId,
          recoverMissingInteractions: false,
        );
      }
    } catch (error) {
      if (epoch != _epoch || request != _timelineRequest) return;
      a?.reportFailure(error);
      if (a != null && a.isCurrent) {
        if (error is PostFailure && error.code == 'CURSOR_INVALID') {
          // Never append another scope to the current page or treat this as EOF.
          _timelineCursor = null;
          _preferencesReady = false;
          _timelineLoading = false;
          await loadTimeline(channelId: channelId);
          return;
        }
        _timelineError = '暂时无法加载帖子，请重试。';
        if (!_preferencesReady) _preferencesError = '暂时无法核对屏蔽设置，请重试。';
      }
    } finally {
      if (epoch == _epoch && request == _timelineRequest) {
        _timelineLoading = false;
        _notify();
      }
    }
  }

  /// Serialize complete replacements; capture account at enqueue, not execution.
  Future<void> saveBlockedChannels(Set<String> ids) {
    final epoch = _epoch;
    final target = Set<String>.of(ids);
    final next = _preferenceWrites.then(
      (_) => _saveBlockedChannels(target, epoch),
    );
    _preferenceWrites = next.catchError((Object _) {});
    return next;
  }

  Future<void> _saveBlockedChannels(Set<String> target, int epoch) async {
    if (!supportsFeed || !available || epoch != _epoch) return;
    final a = await _openSession();
    if (epoch != _epoch || !a.isCurrent) return;
    _preferencesSaving = true;
    _preferencesError = null;
    ++_timelineRequest;
    _timelineLoading = false;
    _timelineCursor = null;
    _timeline = [];
    _notify();
    try {
      final result = await a.request(
        (token) => _api!.saveFeedPreferences(
          sessionToken: token,
          blockedChannelIds: target,
        ),
      );
      _blockedChannels = result.blockedChannelIds;
      _preferencesReady = true;
    } catch (error) {
      if (!a.isCurrent) return;
      a.reportFailure(error);
      _preferencesReady = false;
      if (!a.isCurrent) return;
      // Even a timeout may have committed. Read before accepting another toggle.
      try {
        final actual = await a.request(
          (token) => _api!.feedPreferences(sessionToken: token),
        );
        _blockedChannels = actual.blockedChannelIds;
        _preferencesReady = true;
        _preferencesError = setEquals(target, _blockedChannels)
            ? null
            : '屏蔽设置未保存，已恢复服务器设置。';
      } catch (readError) {
        a.reportFailure(readError);
        if (a.isCurrent) _preferencesError = '暂时无法核对屏蔽设置，请重试。';
      }
    } finally {
      if (a.isCurrent) {
        _preferencesSaving = false;
        _notify();
      }
    }
    if (a.isCurrent && _preferencesReady) {
      await loadTimeline(channelId: _timelineChannelId);
    } else if (a.isCurrent) {
      _timelineError = '请先重新加载并核对屏蔽设置。';
      _notify();
    }
  }

  /// Called by the detail only after a frame containing the visible body.
  Future<void> registerVisiblePost(String postId) async {
    if (!supportsFeed || !available || _isPostDeleted(postId)) return;
    final a = await _openSession();
    try {
      final result = await a.request(
        (token) => _api!.registerPostView(sessionToken: token, postId: postId),
      );
      if (_isPostDeleted(postId)) return;
      final old = _postViews[postId] ?? 0;
      _postViews[postId] = result.viewCount > old ? result.viewCount : old;
      _notify();
    } catch (error) {
      // Reading remains available when counting fails. No local increment.
      if (error is PostFailure &&
          (error.kind == PostFailureKind.unauthorized ||
              error.kind == PostFailureKind.unavailable)) {
        a.reportFailure(error);
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    ++_timelineRequest;
    super.dispose();
  }
}
