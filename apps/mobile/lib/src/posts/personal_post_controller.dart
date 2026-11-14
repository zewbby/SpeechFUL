import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_models.dart';
import '../auth/auth_store.dart';
import '../identity/active_identity_controller.dart';
import '../identity/identity_api.dart';
import '../storage/post_store.dart';
import 'post_api.dart';
import 'post_models.dart';
import 'post_publication_context.dart';
import 'post_result_reconciler.dart';

class PersonalPostItem {
  const PersonalPostItem({
    required this.id,
    required this.title,
    required this.sortAt,
    this.local,
    this.task,
    this.post,
  });
  final String id, title;
  final DateTime sortAt;
  final StoredPostEntry? local;
  final PostTask? task;
  final PostCard? post;
  bool get isDraft => local?.isDraft ?? false;
  bool get rateLimitedDraft => local?.data['rateLimitWait'] is Map;
  String get body => task != null
      ? task!.content?.body ?? ''
      : local?.data['body'] as String? ?? '';
  String get channelId =>
      post?.channelId ??
      task?.channelId ??
      local?.data['channelId'] as String? ??
      '';
  String get state => post != null
      ? 'PUBLISHED'
      : rateLimitedDraft
      ? 'RATE_LIMITED'
      : {
          'submitted',
          'UNKNOWN',
          'RESULT_EXPIRED',
          'NOT_ACCEPTED',
          'REJECTED',
        }.contains(local?.state)
      ? local!.state.toUpperCase()
      : task?.state.name.toUpperCase() ??
            (isDraft ? 'DRAFT' : local?.state ?? 'UNKNOWN');
}

/// Owns identity selection, personal pages and their local/remote projection.
/// Captured contexts keep authorization and metadata persistence in one owner.
class PersonalPostController extends ChangeNotifier {
  PersonalPostController({
    required this._api,
    required this._openContext,
    required this._readIdentities,
    required this._results,
    required this._available,
    required this._accountId,
    required this._onFailure,
    required this._isPostDeleted,
    required this._markPostDeleted,
    required this._updatePublishedFeed,
  });
  final PostApi _api;
  final Future<PostPublicationContext> Function() _openContext;
  // Returns only after directory metadata commits for this captured request.
  final Future<IdentityDirectory?> Function(
    PostPublicationContext,
    bool Function(),
  )
  _readIdentities;
  final PostResultReconciler _results;
  final bool Function() _available;
  final String? Function() _accountId;
  final void Function(Object) _onFailure;
  final bool Function(String) _isPostDeleted;
  final void Function(String) _markPostDeleted;
  final Future<void> Function(PostPublicationContext, PostDetail)
  _updatePublishedFeed;
  final _remoteTasks = <String, PostTask>{};
  List<StoredPostEntry> _local = [];
  List<OwnPostCard> _own = [];
  String? _ownCursor, _taskCursor;
  int _personalRequest = 0, _projectionRequest = 0;
  bool _disposed = false;
  bool get available => !_disposed && _available();
  String? get accountId => _accountId();
  Iterable<StoredPostEntry> get localEntries => _local;
  List<PersonalPostItem> _items = const [];
  List<PersonalPostItem> get personalItems => _items;
  ManagedIdentity? get personalIdentity => _identity;
  List<ManagedIdentity> get personalIdentities => _identities;
  String? get personalError => _error;
  bool get personalLoading => _loading;
  String? get personalProfileError => _profileError;
  bool get personalProfileLoading => _profileLoading;
  ActiveIdentityController? get activeIdentity => _activeIdentity;
  ManagedIdentity? _identity;
  List<ManagedIdentity> _identities = const [];
  String? _error;
  bool _loading = false;

  bool _current(PostPublicationContext context) =>
      !_disposed && context.isCurrent;
  Future<T> _accept<T>(
    PostPublicationContext context,
    PostResponse<T> response,
  ) => context.accept(response);
  void _failure(Object error, [PostPublicationContext? context]) {
    if (_disposed) return;
    if (context == null) {
      _onFailure(error);
    } else {
      context.reportFailure(error);
    }
  }

  void reset({bool notify = true}) {
    ++_personalRequest;
    ++_personalProfileRequest;
    ++_projectionRequest;
    _local = [];
    _own = [];
    _remoteTasks.clear();
    _ownCursor = _taskCursor = null;
    _items = const [];
    _identity = null;
    _identities = const [];
    _error = _profileError = null;
    _loading = _profileLoading = false;
    if (notify) _notify();
  }

  void replaceLocal(List<StoredPostEntry> entries, {bool notify = true}) {
    if (_disposed) return;
    _local = List.unmodifiable(entries);
    for (final entry in entries) {
      final postId = entry.data['postId'];
      if (entry.state == 'DELETED' && postId is String) {
        _markPostDeleted(postId);
      }
    }
    _mergePersonal();
    if (notify) _notify();
  }

  Future<void> refreshLocal(PostPublicationContext context) async {
    final entries = await context.store.list();
    if (_current(context)) replaceLocal(entries);
  }

  void recordTask(PostTask task) {
    if (!_disposed) _remoteTasks[task.taskId] = task;
  }

  PostTask? taskById(String id) => _remoteTasks[id];

  void removeDeletedPost(String id) {
    _own = _own.where((p) => p.post.postId != id).toList();
    _remoteTasks.removeWhere((_, task) => task.postId == id);
    _mergePersonal();
  }

  void applyEditedPost(PostDetail post) {
    ++_personalRequest;
    ++_personalProfileRequest;
    ++_projectionRequest;
    _loading = _profileLoading = false;
    _own = [
      for (final old in _own)
        if (old.post.postId == post.postId)
          OwnPostCard(post: post, serverSortAt: old.serverSortAt)
        else
          old,
    ];
    _mergePersonal();
  }

  ActiveIdentityController? _activeIdentity;
  void bindActiveIdentity(ActiveIdentityController? value) {
    _activeIdentity?.removeListener(_activeIdentityChanged);
    _activeIdentity = value;
    value?.addListener(_activeIdentityChanged);
    _activeIdentityChanged();
  }

  void _activeIdentityChanged() {
    final id = _activeIdentity?.selectedId;
    if (!available ||
        _activeIdentity?.accountId != accountId ||
        id == null ||
        _identity?.id == id) {
      return;
    }
    if (_identities.any((i) => i.id == id)) {
      unawaited(selectPersonalIdentity(id, broadcast: false));
    }
  }

  Future<void> selectPersonalIdentity(
    String id, {
    bool broadcast = true,
  }) async {
    final identity = _identities.where((i) => i.id == id).firstOrNull;
    if (!available || identity == null) return;
    if (broadcast) {
      _activeIdentity?.selectConfirmed(
        id,
        _identities.map((i) => i.id),
        account: accountId,
      );
    }
    if (_identity?.id == id) return;
    ++_personalRequest;
    ++_personalProfileRequest;
    ++_projectionRequest;
    _identity = identity;
    _own = [];
    _ownCursor = _taskCursor = null;
    _mergePersonal();
    _notify();
    await loadPersonal();
  }

  String? _profileError;
  bool _profileLoading = false;

  Future<Map<String, dynamic>> readPersonalProfileState() async {
    final a = await _openContext();
    final value = await a.store.readProfile();
    if (!_current(a)) throw const StalePostPublication();
    return value;
  }

  Future<void> savePersonalProfileState(Map<String, dynamic> value) async {
    final a = await _openContext();
    await a.store.writeProfile(value);
    if (!_current(a)) throw const StalePostPublication();
  }

  int _personalProfileRequest = 0;

  Future<void> loadPersonal({bool more = false}) async {
    if (more && _loading) return;
    // Replacing the list retires an older projection refresh; appending does not.
    if (!more) ++_projectionRequest;
    Future<void>? profile;
    final request = ++_personalRequest;
    PostPublicationContext? a;
    try {
      a = await _openContext();
      if (!_current(a) || request != _personalRequest) return;
      _loading = true;
      _error = null;
      if (!more) {
        _profileError = null;
        _profileLoading = true;
      }
      _notify();
      final scoped = a;
      if (!more) {
        profile = _loadPersonalProfile(a, ++_personalProfileRequest);
        await profile;
      }
      if (!_current(a) || request != _personalRequest) return;
      // Independent reads start together. Future.wait keeps the original typed
      // failure so 401/503 still pass through the authority gate below.
      final reads = await Future.wait<Object?>([
        if (_identity != null && (!more || _ownCursor != null))
          _api
              .ownPosts(
                sessionToken: a.token,
                cursor: more ? _ownCursor : null,
                identityId: _identity?.id,
              )
              .then((response) => scoped.accept(response))
        else
          Future<Object?>.value(),
        if (!more || _taskCursor != null)
          _api
              .tasks(sessionToken: a.token, cursor: more ? _taskCursor : null)
              .then((response) => scoped.accept(response))
        else
          Future<Object?>.value(),
        a.store.list(),
      ], eagerError: true);
      if (!_current(a) || request != _personalRequest) return;
      final posts = reads[0] as PostsPage<OwnPostCard>?;
      final tasks = reads[1] as PostsPage<PostTask>?;
      var local = reads[2] as List<StoredPostEntry>;
      final queriedTasks = <String, PostTask>{};
      // 已隐藏失败项不在分页中；点查已知任务，避免本机旧正文重新出现。
      for (final entry in local.where((e) => e.state == 'FAILED')) {
        final taskId = entry.data['taskId'] as String?;
        if (taskId == null) continue;
        final task = await _accept(
          a,
          await _api.task(sessionToken: a.token, taskId: taskId),
        );
        await _results.applyTask(a, entry, task);
        queriedTasks[task.taskId] = task;
      }
      local = await a.store.list();
      if (!_current(a) || request != _personalRequest) return;
      if (!more) {
        _own = [];
        _remoteTasks.clear();
      }
      final ids = _own.map((p) => p.post.postId).toSet();
      if (posts != null) {
        _own = [
          ..._own,
          ...posts.items.where(
            (p) => !_isPostDeleted(p.post.postId) && ids.add(p.post.postId),
          ),
        ];
        _ownCursor = posts.nextCursor;
      }
      if (tasks != null) {
        for (final task in tasks.items) {
          _remoteTasks[task.taskId] = task;
        }
        _taskCursor = tasks.nextCursor;
      }
      // 点查晚于分页快照，旧分页不能覆盖更新的终态或尝试版本。
      _remoteTasks.addAll(queriedTasks);
      replaceLocal(local, notify: false);
      for (final task in queriedTasks.values.where(
        (t) => t.state == PostTaskState.published,
      )) {
        unawaited(insertPublished(a, task.postId));
      }
      _loading = false;
      _notify();
    } catch (error) {
      if (a != null && (!_current(a) || request != _personalRequest)) return;
      _failure(error, a);
      if (a != null && _current(a)) _error = '暂时无法核对本人内容，请重试。';
    } finally {
      if (a != null && _current(a) && request == _personalRequest) {
        _loading = false;
        _notify();
      }
      // Profile selection is resolved before requesting identity-scoped posts.
      await profile;
    }
  }

  Future<void> _loadPersonalProfile(
    PostPublicationContext a,
    int request,
  ) async {
    try {
      final directory = await _readIdentities(
        a,
        () => _current(a) && request == _personalProfileRequest,
      );
      if (directory == null ||
          !_current(a) ||
          request != _personalProfileRequest) {
        return;
      }
      final originals = directory.identities.where((i) => i.isOriginal);
      final context = originals.isNotEmpty
          ? null
          : await _accept(a, await _api.composerContext(sessionToken: a.token));
      if (!_current(a) || request != _personalProfileRequest) return;
      final previousIdentity = _identity?.id;
      _identities = List.unmodifiable(directory.identities);
      _identity = directory.identities
          .where((i) => i.id == (_activeIdentity?.selectedId ?? _identity?.id))
          .firstOrNull;
      _identity ??= originals.isNotEmpty
          ? originals.first
          : directory.identities
                .where((i) => i.id == context?.defaultIdentityId)
                .firstOrNull;
      _identity ??=
          (List<ManagedIdentity>.of(directory.identities)..sort((x, y) {
                final byTime = x.createdAt.compareTo(y.createdAt);
                return byTime != 0 ? byTime : x.id.compareTo(y.id);
              }))
              .firstOrNull;
      if (previousIdentity != _identity?.id) {
        _own = [];
        _ownCursor = null;
        _mergePersonal();
      }
    } catch (error) {
      if (!_current(a) || request != _personalProfileRequest) return;
      // Access/storage failures still follow the existing failure policy; a temporary
      // profile failure leaves successfully loaded posts and empty states.
      if (error is AuthStorageFailure ||
          error is PostStorageFailure ||
          error is AuthFailure &&
              (error.unauthorized ||
                  error.kind == AuthFailureKind.unavailable) ||
          error is PostFailure &&
              {
                PostFailureKind.unauthorized,
                PostFailureKind.unavailable,
              }.contains(error.kind)) {
        _failure(error, a);
      }
      if (_current(a)) {
        _profileError = '身份资料暂时无法读取，请下拉重试。';
      }
    } finally {
      if (_current(a) && request == _personalProfileRequest) {
        _profileLoading = false;
        _notify();
      }
    }
  }

  bool get personalHasMore => _ownCursor != null || _taskCursor != null;

  void _mergePersonal() {
    // 删除后到达的旧本人页也不能把正文留回任务缓存。
    _remoteTasks.removeWhere((_, task) => _isPostDeleted(task.postId));
    _own = _own.where((post) => !_isPostDeleted(post.post.postId)).toList();
    final items = <PersonalPostItem>[];
    final knownTasks = <String>{};
    for (final entry in _local) {
      if (_identity != null && entry.data['identityId'] != _identity!.id) {
        continue;
      }
      if (entry.data['isRetryBuffer'] == true ||
          (entry.data['postId'] is String &&
              _isPostDeleted(entry.data['postId'] as String)) ||
          entry.data['abandoned'] == true ||
          {
            'PUBLISHED',
            'CANCELLED',
            'HIDDEN',
            'DELETED',
          }.contains(entry.state)) {
        continue;
      }
      final taskId = entry.data['taskId'] as String?;
      final task = taskId == null ? null : _remoteTasks[taskId];
      if (taskId != null) knownTasks.add(taskId);
      if (task != null && !task.visible) continue;
      items.add(
        PersonalPostItem(
          id: entry.id,
          title: task != null
              ? task.content?.title ?? '内容不可用'
              : entry.data['title'] as String? ?? '',
          sortAt:
              task?.serverSortAt ??
              DateTime.parse(entry.data['editedAt'] as String),
          local: entry,
          task: task,
        ),
      );
    }
    for (final task in _remoteTasks.values) {
      if ((_identity == null || task.identityId == _identity!.id) &&
          task.visible &&
          !_isPostDeleted(task.postId) &&
          !knownTasks.contains(task.taskId)) {
        items.add(
          PersonalPostItem(
            id: 'task:${task.taskId}',
            title: task.content?.title ?? '内容不可用',
            sortAt: task.serverSortAt,
            task: task,
          ),
        );
      }
    }
    for (final post in _own) {
      items.add(
        PersonalPostItem(
          id: 'post:${post.post.postId}',
          title: post.post.title,
          sortAt: post.serverSortAt,
          post: post.post,
        ),
      );
    }
    items.sort((a, b) {
      final time = b.sortAt.compareTo(a.sortAt);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
    _items = List.unmodifiable(items);
  }

  /// 身份资料变化只刷新已加载内容；保留本人分页游标和阅读位置。
  Future<void> refreshPersonalProjections() async {
    final request = ++_projectionRequest;
    bool projectionCurrent() => !_disposed && request == _projectionRequest;
    PostPublicationContext? a;
    try {
      a = await _openContext();
      if (!_current(a) || !projectionCurrent()) return;
      final ownIds = _own.map((p) => p.post.postId).toList();
      for (final id in ownIds) {
        PostDetail? post;
        try {
          post = await _accept(
            a,
            await _api.detail(sessionToken: a.token, postId: id),
          );
        } on PostFailure catch (error) {
          if (error.statusCode != 404) rethrow;
        }
        if (!_current(a) || !projectionCurrent()) return;
        _own = [
          for (final old in _own)
            if (old.post.postId != id)
              old
            else if (post != null &&
                post.author.state == PostAuthorState.active)
              OwnPostCard(post: post, serverSortAt: post.publishedAt),
        ];
      }
      for (final taskId in _remoteTasks.keys.toList()) {
        final task = await _accept(
          a,
          await _api.task(sessionToken: a.token, taskId: taskId),
        );
        final matching = (await a.store.list()).where(
          (e) => !e.isDraft && e.data['taskId'] == taskId,
        );
        if (matching.isNotEmpty &&
            !PostResultReconciler.unresolved(matching.first)) {
          await _results.applyTask(a, matching.first, task);
        } else if (_current(a) && projectionCurrent()) {
          _remoteTasks[taskId] = task;
        }
      }
      final directory = await _readIdentities(a, projectionCurrent);
      if (directory == null || !projectionCurrent()) return;
      final context = await _accept(
        a,
        await _api.composerContext(sessionToken: a.token),
      );
      if (!_current(a) || !projectionCurrent()) return;
      final originals = directory.identities.where((i) => i.isOriginal);
      final ordered = List<ManagedIdentity>.of(directory.identities)
        ..sort((x, y) {
          final byTime = x.createdAt.compareTo(y.createdAt);
          return byTime != 0 ? byTime : x.id.compareTo(y.id);
        });
      final previousIdentity = _identity?.id;
      _identities = List.unmodifiable(directory.identities);
      _identity =
          directory.identities
              .where(
                (i) => i.id == (_activeIdentity?.selectedId ?? _identity?.id),
              )
              .firstOrNull ??
          originals.firstOrNull ??
          directory.identities
              .where((i) => i.id == context.defaultIdentityId)
              .firstOrNull ??
          ordered.firstOrNull;
      if (previousIdentity != _identity?.id) {
        _own = [];
        _ownCursor = null;
        ++_personalRequest;
      }
      _mergePersonal();
      _notify();
      if (previousIdentity != _identity?.id && _identity != null) {
        await loadPersonal();
      }
    } catch (error) {
      if (!projectionCurrent()) return;
      _failure(error, a);
    }
  }

  Future<void> insertPublished(PostPublicationContext a, String postId) async {
    try {
      if (!_current(a) || _isPostDeleted(postId)) return;
      final post = await _accept(
        a,
        await _api.detail(sessionToken: a.token, postId: postId),
      );
      if (_isPostDeleted(postId)) return;
      await _updatePublishedFeed(a, post);
      if (!_current(a)) return;
      // 本人task证明归属，当前公共作者证明身份仍有效；第一页缺席不等于失去资格。
      final ownedTask = _remoteTasks.values.where(
        (task) =>
            task.postId == postId &&
            task.state == PostTaskState.published &&
            (_identity == null || task.identityId == _identity!.id),
      );
      _own = [
        if (ownedTask.isNotEmpty && post.author.state == PostAuthorState.active)
          OwnPostCard(post: post, serverSortAt: post.publishedAt),
        ..._own.where((p) => p.post.postId != postId),
      ];
      _mergePersonal();
      _notify();
    } catch (error) {
      _failure(error, a);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _activeIdentity?.removeListener(_activeIdentityChanged);
    _disposed = true;
    ++_personalRequest;
    ++_personalProfileRequest;
    ++_projectionRequest;
    super.dispose();
  }
}
