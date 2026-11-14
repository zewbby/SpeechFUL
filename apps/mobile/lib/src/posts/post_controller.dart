export 'post_draft_controller.dart' show PostDraftEditor;
export 'personal_post_controller.dart' show PersonalPostItem;
import 'personal_post_controller.dart';
import 'post_task_maintenance_controller.dart';
import 'post_draft_controller.dart';
import 'post_submission_controller.dart';
import 'post_result_reconciler.dart';
import 'post_publication_context.dart';
import 'post_search_controller.dart';
import 'feed_controller.dart' as feed;
import '../rate_limit.dart';
import 'personal_collections_api.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../auth/auth_crypto.dart';
import '../auth/auth_models.dart';
import '../auth/auth_session_controller.dart';
import '../auth/auth_store.dart';
import '../identity/identity_api.dart';
import '../identity/active_identity_controller.dart';
import '../storage/post_store.dart';
import 'post_api.dart';
import 'author_block_api.dart';
import 'post_edit_api.dart';
import 'feed_api.dart';
import 'hidden_post_api.dart';
import 'post_interactions_api.dart';
import 'post_reposts_api.dart';
import 'post_search_api.dart';
import 'post_ranking_api.dart';
import 'post_sharing_api.dart';
import 'post_models.dart';
import 'post_media_api.dart';

import 'post_protocol.dart';
import 'post_tags.dart';
import '../channels/channel.dart';
import 'post_upload_api.dart';
import 'post_upload_models.dart';
import 'post_photo_picker.dart';

part 'post_composer_media.dart';
part 'hidden_post_controller.dart';
part 'post_interactions_controller.dart';
part 'post_reposts_controller.dart';
part 'post_edit_controller.dart';
part 'post_sharing_controller.dart';
part 'author_block_controller.dart';

typedef PostStoreFactory = Future<PostStore> Function(String accountId);

/// 只记录本机原发布意图首次持久观察到的公开成功；不含正文或账号。
class PostPublicationNotice {
  const PostPublicationNotice({
    required this.sequence,
    required this.postId,
    required this.channelId,
  });
  final int sequence;
  final String postId, channelId;
}

class _PostAuthority {
  const _PostAuthority(this.epoch, this.token, this.accountId, this.store);
  final int epoch;
  final String token, accountId;
  final PostStore? store;
}

class _StalePostAuthority extends StalePostPublication {}

/// Binds a captured session to publication ports without exposing the owner.
class _PostPublicationContext implements PostPublicationContext {
  _PostPublicationContext(this._owner, this._authority);
  final PostController _owner;
  final _PostAuthority _authority;
  @override
  String get accountId => _authority.accountId;
  @override
  int get epoch => _authority.epoch;
  @override
  String get token => _authority.token;
  @override
  PostStore get store => _authority.store!;
  @override
  bool get isCurrent => _owner._current(_authority);
  @override
  Future<T> accept<T>(PostResponse<T> response) =>
      _owner._accept(_authority, response);
  @override
  void reportFailure(Object error, {String? commandId}) =>
      _owner._failure(error, _authority, commandId);
  @override
  Future<void> refreshLocal() => _owner._refreshLocal(_authority);
  @override
  void submissionRecorded(String id) {
    _owner._imageProgress.remove(id);
  }

  @override
  void setCommandMessage(String message) {
    _owner.errorMessage = message;
  }

  @override
  Future<void> preserveCancelledImages(StoredPostEntry entry) =>
      _owner._preserveCancelledImages(_authority, entry);
  @override
  Future<void> resumeImageUpload(String id) => _owner.resumeImageUpload(id);
  @override
  Future<void> resultRecorded(PostResultUpdate update) =>
      _owner._projectPublicationResult(_authority, update);
}

/// Adapts the shared session owner to the feed's narrow read boundary.
class _FeedReadSession implements feed.FeedReadSession {
  _FeedReadSession(this._owner, this._authority);
  final PostController _owner;
  final _PostAuthority _authority;

  @override
  bool get isCurrent => _owner._current(_authority);

  @override
  Future<T> request<T>(Future<PostResponse<T>> Function(String) send) async =>
      _owner._accept(_authority, await send(_authority.token));

  @override
  void reportFailure(Object error) =>
      _owner._propagateReadAuthorityFailure(error, _authority);
}

/// SQLite 保存先于发送；每次网络响应先持久续期，再更新原授权窗口的视图。
class PostController extends ChangeNotifier {
  PostController({
    required this._api,
    required this._sessions,
    required this._authStore,
    required this._identities,
    required this._openStore,
    DateTime Function()? clock,
    this._purgeStore,
    String Function()? newId,
    Duration pollInterval = const Duration(seconds: 5),
    this._mediaApi,
    this._uploadApi,
    this._photoPicker,
    this.channelDirectory,
  }) : _clock = clock ?? DateTime.now,
       _newId = newId ?? (() => AuthCrypto.randomEncoded(16)) {
    _homeFeed.addListener(_notify);
    _personal.addListener(_notify);
    _maintenance.addListener(_notify);
    _drafts.addListener(_notify);
    _submissions.addListener(_notify);
    _sessions.addListener(_authorityChanged);
    _authStore.addListener(_authorityChanged);
    _authorityChanged();
    _results.startPolling(pollInterval);
  }

  late final PostDraftController _drafts = PostDraftController(
    openContext: _openPublicationContext,
    editorCurrent: editorCurrent,
    onFailure: _failure,
    clock: _clock,
    newId: _newId,
  );
  late final PostResultReconciler _results = PostResultReconciler(
    api: _api,
    openContext: _openPublicationContext,
    onFailure: _failure,
    available: () => available,
    entries: () => _personal.localEntries,
  );
  late final PostSubmissionController _submissions = PostSubmissionController(
    api: _api,
    drafts: _drafts,
    results: _results,
    openContext: _openPublicationContext,
    editorCurrent: editorCurrent,
    onFailure: _failure,
    newId: _newId,
    clock: _clock,
    accountId: () => accountId,
    entries: () => _personal.localEntries,
    uploadApi: _uploadApi,
  );
  Future<PostPublicationContext> _openPublicationContext() async =>
      _PostPublicationContext(this, await _authority(storage: true));

  late final PersonalPostController _personal = PersonalPostController(
    api: _api,
    openContext: _openPublicationContext,
    readIdentities: _readPersonalIdentities,
    results: _results,
    available: () => available,
    accountId: () => accountId,
    onFailure: _failure,
    isPostDeleted: (id) => _deletedPostIds.contains(id),
    markPostDeleted: _markPostDeleted,
    updatePublishedFeed: _updatePublishedFeed,
  );
  late final PostTaskMaintenanceController _maintenance =
      PostTaskMaintenanceController(
        api: _api,
        drafts: _drafts,
        results: _results,
        submissions: _submissions,
        openContext: _openPublicationContext,
        onFailure: _failure,
        newId: _newId,
        clock: _clock,
        isPostDeleted: (id) => _deletedPostIds.contains(id),
        markPostDeleted: _markPostDeleted,
        canDelete: canDelete,
      );

  Future<IdentityDirectory?> _readPersonalIdentities(
    PostPublicationContext a,
    bool Function() requestCurrent,
  ) async {
    final directory = await _identities.identities(a.token);
    bool current() => a.isCurrent && requestCurrent();
    if (!current() ||
        !await _sessions.persistSessionMetadata(
          a.token,
          directory.sessionExpiresAt,
          current,
        ) ||
        !current()) {
      return null;
    }
    return directory;
  }

  late final PostSearchController _discovery = PostSearchController(
    api: _api,
    request: _withDiscoveryAuthority,
  );

  bool get supportsPostSearch => _discovery.supportsPostSearch;
  bool get supportsPostRankings => _discovery.supportsPostRankings;
  Future<List<String>> suggestPostTags(String prefix) =>
      _discovery.suggestPostTags(prefix);
  Future<PostsPage<PostCard>> taggedPosts(
    String tag, {
    String? channelId,
    String? cursor,
  }) => _discovery.taggedPosts(tag, channelId: channelId, cursor: cursor);
  Future<PostDetail> readTaggedPost(String id) => _discovery.readTaggedPost(id);
  Future<PostRanking> hotPosts() => _discovery.hotPosts();
  Future<PostsPage<PostCard>> searchPosts({
    required String keyword,
    required String? channelId,
    required PostSearchSort sort,
    String? cursor,
    bool recordHistory = false,
    String? postId,
  }) => _discovery.searchPosts(
    keyword: keyword,
    channelId: channelId,
    sort: sort,
    cursor: cursor,
    recordHistory: recordHistory,
    postId: postId,
  );
  Future<List<String>> postSearchHistory(String? channelId) =>
      _discovery.postSearchHistory(channelId);
  Future<List<String>> changePostSearchHistory(
    String? channelId, {
    String? removeKeyword,
  }) => _discovery.changePostSearchHistory(
    channelId,
    removeKeyword: removeKeyword,
  );

  Future<T> _withDiscoveryAuthority<T>(
    Future<PostResponse<T>> Function(String) request, {
    bool optional = false,
  }) async {
    final authority = await _authority();
    if (!_current(authority)) throw _StalePostAuthority();
    try {
      return await _accept(authority, await request(authority.token));
    } on PostFailure catch (error) {
      if (_current(authority)) {
        if (error.kind == PostFailureKind.unauthorized) {
          _sessions.sessionUnauthorized(authority.token, error.code);
        } else if (error.code == 'AUTHORIZATION_UNAVAILABLE' ||
            !optional &&
                error.kind == PostFailureKind.unavailable &&
                error.code == null ||
            error.statusCode == 403 && error.code == 'AUTHENTICATION_FAILED') {
          _sessions.sessionUnavailable(authority.token);
        }
      }
      rethrow;
    }
  }

  late final feed.FeedController _homeFeed = feed.FeedController(
    api: _api is FeedApi ? _api as FeedApi : null,
    available: () => available,
    openSession: () async => _FeedReadSession(this, await _authority()),
    invalidateInteractionReads: _invalidateInteractionReads,
    loadInteractions: loadInteractions,
    isPostDeleted: (id) => _deletedPostIds.contains(id),
  );
  feed.FeedController get homeFeed => _homeFeed;

  final _interactions = <String, PostInteractionState>{};
  final _hiddenWrites = <String>{};
  final _hiddenUncertainVersions = <String, ({bool desired, String version})>{};
  String? hiddenPostError;
  final _authorBlockWrites = <String>{};
  final _authorBlockRemovals = <String>{};
  String? authorBlockError;
  final _reposts = <String, PostRepostState>{};
  List<RepostedPost> _repostItems = [];
  String? _repostCursor, _repostListError;
  bool _repostListLoading = false, _repostListOpened = false;
  int _repostListRevision = 0;
  final List<Channel> Function()? channelDirectory;
  List<Channel> get postTagChannels =>
      available ? (channelDirectory?.call() ?? const []) : const [];
  final PostApi _api;
  final PostMediaApi? _mediaApi;
  final PostUploadApi? _uploadApi;
  final PostPhotoPicker? _photoPicker;
  bool _lostSelectionChecked = false;
  final _uploadingImages = <String>{};
  final _imageProgress = <String, PostImageUploadProgress>{};
  final AuthSessionController _sessions;
  final AuthStore _authStore;
  final IdentityApi _identities;
  final PostStoreFactory _openStore;
  final Future<void> Function(String accountId)? _purgeStore;
  final DateTime Function() _clock;
  final String Function() _newId;
  PostStore? _store;
  Future<void> _opening = Future.value();
  String? _token, _accountId;
  int _epoch = 0, _sessionVersion = -1;
  bool _disposed = false;
  bool _storageRetrying = false;
  final _sharingPosts = <String, int>{};
  final _deletedPostIds = <String>{};
  final _postMediaRevisions = <String, int>{};
  final _confirmedEdits = <String, PostDetail>{};
  int _contentVersion = 0;
  int get contentVersion => _contentVersion;
  PostDetail? confirmedEdit(String id) => _confirmedEdits[id];
  final _retired = <String, Future<void>>{};
  final _activating = <String, Future<void>>{};
  int _feedRequest = 0;

  /// Incremented whenever a committed account block changes what the current
  /// account may see. Screens that cache filtered pages compare it and drop
  /// cards loaded under an older visibility window.
  int authorVisibilityEpoch = 0;
  int _publicationSequence = 0;
  PostPublicationNotice? _latestPublicationNotice;
  String? currentChannelId, feedCursor, feedError, errorMessage;
  String? _errorCommandId;
  bool feedLoading = false;
  List<PostCard> feedItems = [];
  ActiveIdentityController? get activeIdentity => _personal.activeIdentity;
  void bindActiveIdentity(ActiveIdentityController? value) =>
      _personal.bindActiveIdentity(value);
  Future<void> selectPersonalIdentity(String id, {bool broadcast = true}) =>
      _personal.selectPersonalIdentity(id, broadcast: broadcast);
  List<PersonalPostItem> get personalItems => _personal.personalItems;
  ManagedIdentity? get personalIdentity => _personal.personalIdentity;
  List<ManagedIdentity> get personalIdentities => _personal.personalIdentities;
  String? get personalError => _personal.personalError;
  bool get personalLoading => _personal.personalLoading;
  String? get personalProfileError => _personal.personalProfileError;
  bool get personalProfileLoading => _personal.personalProfileLoading;
  bool get personalHasMore => _personal.personalHasMore;

  bool get supportsFeed => _homeFeed.supportsFeed;
  bool get supportsInteractions => _api is PostInteractionsApi;
  bool get supportsPostSharing => _api is PostSharingApi;
  bool get feedPreferencesReady => _homeFeed.feedPreferencesReady;
  String? get accountId => _accountId;
  int get authorityVersion => _epoch;
  PostPublicationNotice? get latestPublicationNotice =>
      available ? _latestPublicationNotice : null;
  bool isPostDeleted(String postId) =>
      available && _deletedPostIds.contains(postId);
  bool get busy => _submissions.busy;
  bool get available =>
      !_disposed &&
      _accountId != null &&
      _token != null &&
      _sessions.isCurrentToken(_token!);
  bool editorCurrent(PostDraftEditor editor) =>
      available &&
      editor.accountId == _accountId &&
      editor.authorityVersion == _epoch;

  void _authorityChanged() {
    if (_disposed) return;
    final record = _authStore.current?.session;
    final permitted = record != null && _sessions.isCurrentToken(record.token);
    final token = permitted ? record.token : null;
    final account = permitted ? record.accountId : null;
    if (token == _token &&
        account == _accountId &&
        (permitted || _sessionVersion == _sessions.authorityVersion)) {
      // Same-token activity renewal is metadata, not a new account window.
      _sessionVersion = _sessions.authorityVersion;
      return;
    }
    _sessionVersion = _sessions.authorityVersion;
    _token = token;
    _accountId = account;
    final epoch = ++_epoch;
    _clearReposts();
    _interactions.clear();
    _hiddenWrites.clear();
    _hiddenUncertainVersions.clear();
    hiddenPostError = null;
    _authorBlockWrites.clear();
    _authorBlockRemovals.clear();
    authorBlockError = null;
    final old = _store;
    _store = null;
    if (old != null) {
      _retired[old.accountId] = old.close();
      unawaited(_retired[old.accountId]!.catchError((Object _) {}));
    }
    _personal.reset(notify: false);
    _deletedPostIds.clear();
    _postMediaRevisions.clear();
    _confirmedEdits.clear();
    ++_contentVersion;
    _latestPublicationNotice = null;
    _imageProgress.clear();
    feedItems = [];
    currentChannelId = feedCursor = feedError = errorMessage = null;
    _errorCommandId = null;
    feedLoading = false;
    _submissions.reset();
    _maintenance.reset();
    _results.reset();
    // Publish the completed account reset to both feed and legacy listeners.
    _homeFeed.reset();
    if (account != null) {
      _opening = _activate(account, epoch);
      _activating[account] = _opening;
    } else {
      _opening = Future.value();
    }
  }

  Future<void> _activate(String account, int epoch) async {
    try {
      final store = await _openStore(account);
      if (_disposed || epoch != _epoch || account != _accountId) {
        await store.close();
        return;
      }
      _store = store;
      final entries = await store.list();
      if (epoch != _epoch) return;
      final recovered = await _restorePickerCheckpoint(store, entries, epoch);
      if (_disposed || epoch != _epoch || account != _accountId) return;
      _personal.replaceLocal(recovered);
      // 恢复只核对已有命令，不重发 CREATE，也不自动替用户重试失败任务。
      for (final entry in _personal.localEntries.where(_needsQuery)) {
        unawaited(reconcile(entry.id));
      }
    } on Object {
      if (epoch == _epoch) {
        errorMessage = '本机内容存储不可用，已保留原数据。请重试。';
        _notify();
      }
    }
  }

  static bool _needsQuery(StoredPostEntry e) =>
      PostResultReconciler.needsQuery(e);

  Future<void> retryStorage() async {
    if (!available || _store != null) return;
    if (_storageRetrying) {
      await _opening;
      return;
    }
    _storageRetrying = true;
    final account = _accountId!;
    try {
      _opening = _activate(account, _epoch);
      _activating[account] = _opening;
      await _opening;
    } finally {
      _storageRetrying = false;
    }
  }

  Future<_PostAuthority> _authority({bool storage = false}) async {
    if (storage) await _opening;
    if (storage && available && _store == null) await retryStorage();
    if (!available) throw _StalePostAuthority();
    if (storage && _store == null) throw const PostStorageFailure();
    return _PostAuthority(_epoch, _token!, _accountId!, _store);
  }

  bool _current(_PostAuthority a) =>
      available &&
      a.epoch == _epoch &&
      a.token == _token &&
      a.accountId == _accountId;

  Future<T> _accept<T>(_PostAuthority a, PostResponse<T> response) async {
    if (!_current(a) ||
        !await _sessions.persistSessionMetadata(
          a.token,
          response.sessionExpiresAt,
          () => _current(a),
        ) ||
        !_current(a)) {
      throw _StalePostAuthority();
    }
    return response.value;
  }

  void _failure(Object error, [_PostAuthority? authority, String? commandId]) {
    if (error is StalePostPublication ||
        authority != null && !_current(authority)) {
      return;
    }
    _errorCommandId = commandId;
    if (error is AuthFailure) {
      if (authority != null && error.unauthorized) {
        _sessions.sessionUnauthorized(authority.token, error.code);
      } else if (authority != null &&
          error.kind == AuthFailureKind.unavailable) {
        _sessions.sessionUnavailable(authority.token);
      } else {
        errorMessage = '暂时无法读取身份，请重试。';
        _notify();
      }
      return;
    } else if (error is PostFailure) {
      if (error.kind == PostFailureKind.unauthorized) {
        if (authority != null) {
          _sessions.sessionUnauthorized(authority.token, error.code);
        }
        return;
      }
      if (error.kind == PostFailureKind.unavailable) {
        if (error.code == 'SHARED_RATE_UNAVAILABLE') {
          errorMessage = '服务暂不可用，原内容已保存，请稍后重试。';
          _notify();
        } else if (authority != null) {
          _sessions.sessionUnavailable(authority.token);
        }
        return;
      }
      errorMessage = error.kind == PostFailureKind.rejected
          ? _rejectionMessage(error.code)
          : '暂时无法核对结果，原操作已保留，请稍后核对。';
    } else if (error is PostStorageFailure || error is AuthStorageFailure) {
      errorMessage = '本机保存失败，内容仍保留在当前页面，请重试或复制。';
    } else {
      errorMessage = '暂时无法完成操作，请重试。';
    }
    _notify();
  }

  void _propagateReadAuthorityFailure(Object error, _PostAuthority? authority) {
    // Read surfaces own their retry messages. Transient reads must not replace
    // another command's error or its clearing owner.
    if (error is PostFailure &&
            {
              PostFailureKind.unauthorized,
              PostFailureKind.unavailable,
            }.contains(error.kind) ||
        error is AuthFailure &&
            (error.unauthorized || error.kind == AuthFailureKind.unavailable)) {
      _failure(error, authority);
    }
  }

  void _clearCommandError(String commandId) {
    if (_errorCommandId != commandId) return;
    _errorCommandId = null;
    errorMessage = null;
  }

  bool get supportsAuthorProfile => _api is FeedApi;

  Future<AuthorProfile> authorProfile({
    required String postId,
    String? cursor,
    int limit = 20,
  }) {
    if (_api case final FeedApi api) {
      return _withDiscoveryAuthority(
        (token) => api.authorProfile(
          sessionToken: token,
          postId: postId,
          cursor: cursor,
          limit: limit,
        ),
      );
    }
    return Future.error(UnsupportedError('Author profile is unavailable'));
  }

  Future<void> loadFeed(String channelId, {bool more = false}) async {
    final request = ++_feedRequest;
    _PostAuthority? a;
    try {
      PostProtocol.resourceId(channelId);
      a = await _authority();
      if (more && (currentChannelId != channelId || feedCursor == null)) return;
      final cursor = more ? feedCursor : null;
      if (!more) {
        currentChannelId = channelId;
        feedItems = [];
        feedCursor = null;
      }
      feedLoading = true;
      feedError = null;
      _notify();
      final page = await _accept(
        a,
        await _api.feed(
          sessionToken: a.token,
          channelId: channelId,
          cursor: cursor,
        ),
      );
      if (request != _feedRequest || currentChannelId != channelId) return;
      if (page.items.any((p) => p.channelId != channelId)) {
        throw const PostFailure(kind: PostFailureKind.invalidResponse);
      }
      final ids = (more ? feedItems : <PostCard>[])
          .map((p) => p.postId)
          .toSet();
      feedItems = [
        if (more) ...feedItems,
        ...page.items.where(
          (p) => !_deletedPostIds.contains(p.postId) && ids.add(p.postId),
        ),
      ];
      feedCursor = page.nextCursor;
    } catch (error) {
      _failure(error, a);
      if (a != null && _current(a) && request == _feedRequest) {
        feedError = '暂时无法加载帖子，请重试。';
      }
    } finally {
      if (a != null && _current(a) && request == _feedRequest) {
        feedLoading = false;
        _notify();
      }
    }
  }

  Future<PostsPage<PostCard>> loadPersonalCollection({
    required bool favorites,
    String? cursor,
  }) async {
    final a = await _authority();
    try {
      final api = _api;
      if (api is! PersonalCollectionsApi) {
        throw StateError('Collections unavailable');
      }
      return await _accept(
        a,
        await (api as PersonalCollectionsApi).personalCollection(
          sessionToken: a.token,
          favorites: favorites,
          cursor: cursor,
        ),
      );
    } catch (error) {
      _failure(error, a);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> readPersonalProfileState() =>
      _personal.readPersonalProfileState();
  Future<void> savePersonalProfileState(Map<String, dynamic> value) =>
      _personal.savePersonalProfileState(value);

  Future<PostDetail?> loadDetail(String postId, {String? sharedUrl}) async {
    final contentVersion = _contentVersion;
    _PostAuthority? a;
    try {
      a = await _authority();
      if (_deletedPostIds.contains(postId)) return null;
      final post = await _accept(
        a,
        sharedUrl == null
            ? await _api.detail(sessionToken: a.token, postId: postId)
            : await (_api as PostSharingApi).resolvePostLink(
                sessionToken: a.token,
                url: sharedUrl,
              ),
      );
      if (post.postId != postId) {
        throw const PostFailure(kind: PostFailureKind.invalidResponse);
      }
      if (_deletedPostIds.contains(postId)) return null;
      if (contentVersion != _contentVersion &&
          _confirmedEdits.containsKey(postId)) {
        return _confirmedEdits[postId];
      }
      if (_confirmedEdits.containsKey(postId)) _confirmedEdits[postId] = post;
      return post;
    } catch (error) {
      _failure(error, a);
      return null;
    }
  }

  /// Uses the same authority capture and durable renewal as text reads.
  /// Only the host HTTP adapter sees a session token.
  Future<PostResponse<T>> _readMedia<T>(
    String postId,
    Future<PostResponse<T>> Function(PostMediaApi api, String token) read,
  ) async {
    final a = await _authority();
    try {
      PostProtocol.resourceId(postId);
      if (_deletedPostIds.contains(postId) || _mediaApi == null) {
        throw const PostFailure(kind: PostFailureKind.rejected);
      }
      final response = await read(_mediaApi, a.token);
      await _accept(a, response);
      if (!_current(a) || _deletedPostIds.contains(postId)) {
        throw _StalePostAuthority();
      }
      return response;
    } catch (error) {
      if (error is PostFailure &&
          (error.kind == PostFailureKind.unauthorized ||
              error.kind == PostFailureKind.unavailable)) {
        _failure(error, a);
      }
      // No raw transport/storage exceptions escape into an image resolver.
      if (error is PostFailure) rethrow;
      throw const PostFailure(kind: PostFailureKind.invalidResponse);
    }
  }

  Future<PostResponse<PostMediaManifest>> loadImageManifest(String postId) =>
      _readMedia(
        postId,
        (api, token) => api.imageManifest(sessionToken: token, postId: postId),
      );

  Future<PostResponse<Uint8List>> loadImageBytes(
    String postId,
    PostMediaImage image,
  ) => _readMedia(
    postId,
    (api, token) =>
        api.imageBytes(sessionToken: token, postId: postId, image: image),
  );

  /// 身份管理返回时刷新已显示的公共投影，保留当前列表顺序与分页游标。
  Future<void> refreshKnownPosts() async {
    _PostAuthority? a;
    try {
      a = await _authority();
      final ids = feedItems.map((p) => p.postId).toList();
      for (final id in ids) {
        PostDetail? post;
        try {
          post = await _accept(
            a,
            await _api.detail(sessionToken: a.token, postId: id),
          );
        } on PostFailure catch (error) {
          if (error.statusCode != 404) rethrow;
        }
        if (!_current(a)) return;
        if (post == null) {
          feedItems = feedItems.where((p) => p.postId != id).toList();
        } else {
          feedItems = [
            for (final old in feedItems) old.postId == id ? post : old,
          ];
        }
      }
      _notify();
    } catch (error) {
      _failure(error, a);
    }
  }

  Future<bool> canDelete(String postId) async =>
      (await postCapabilities(postId))?.canDelete ?? false;

  Future<PostCapabilities?> postCapabilities(String postId) async {
    _PostAuthority? a;
    try {
      a = await _authority();
      if (_deletedPostIds.contains(postId)) return null;
      return await _accept(
        a,
        await _api.capabilities(sessionToken: a.token, postId: postId),
      );
    } catch (error) {
      if (error is! PostFailure || error.statusCode != 404) _failure(error, a);
      return null;
    }
  }

  Future<void> loadPersonal({bool more = false}) =>
      _personal.loadPersonal(more: more);

  PostDraftEditor newDraft(String channelId) {
    if (!available) throw _StalePostAuthority();
    return _drafts.newDraft(
      channelId,
      accountId: _accountId!,
      authorityVersion: _epoch,
      identityId: activeIdentity?.accountId == _accountId
          ? activeIdentity?.selectedId
          : null,
    );
  }

  Future<PostDraftEditor?> restoreDraft(String id) => _drafts.restoreDraft(id);
  Future<bool> saveDraft(PostDraftEditor editor) => _drafts.saveDraft(editor);
  Future<bool> discardDraft(PostDraftEditor editor) =>
      _drafts.discardDraft(editor);

  Future<List<ManagedIdentity>> prepareComposer(PostDraftEditor e) async {
    _PostAuthority? a;
    try {
      if (!editorCurrent(e)) return [];
      a = await _authority();
      final directory = await _identities.identities(a.token);
      final scoped = a;
      if (!_current(a) ||
          !await _sessions.persistSessionMetadata(
            a.token,
            directory.sessionExpiresAt,
            () => _current(scoped),
          )) {
        return [];
      }
      final context = await _accept(
        a,
        await _api.composerContext(sessionToken: a.token),
      );
      if (!editorCurrent(e)) return [];
      if (e.isRetry) {
        if (!directory.identities.any((i) => i.id == e.identityId)) {
          e.error = '原发布身份已失效，此任务不能更换身份重试。';
          return [];
        }
      } else if (!directory.identities.any((i) => i.id == e.identityId)) {
        e.identityId = context.defaultIdentityId;
      }
      return directory.identities;
    } on AuthFailure catch (error) {
      if (a != null && _current(a)) {
        if (error.unauthorized) {
          _sessions.sessionUnauthorized(a.token, error.code);
        } else {
          _sessions.sessionUnavailable(a.token);
        }
      }
      return [];
    } catch (error) {
      _failure(error, a);
      return [];
    }
  }

  Future<bool> publish(PostDraftEditor editor) => _submissions.publish(editor);

  void _markPostDeleted(String postId) {
    _deletedPostIds.add(postId);
    if (_latestPublicationNotice?.postId == postId) {
      _latestPublicationNotice = null;
    }
    feedItems = feedItems.where((p) => p.postId != postId).toList();
    _personal.removeDeletedPost(postId);
  }

  void _noticePublication(_PostAuthority a, PostTask task) {
    if (!_current(a) || _deletedPostIds.contains(task.postId)) return;
    _latestPublicationNotice = PostPublicationNotice(
      sequence: ++_publicationSequence,
      postId: task.postId,
      channelId: task.channelId,
    );
    _notify();
  }

  Future<void> _refreshLocal(_PostAuthority a) =>
      _personal.refreshLocal(_PostPublicationContext(this, a));
  int rateLimitedSeconds(String id) => _submissions.rateLimitedSeconds(id);
  Future<void> retryRateLimited(String id) => _submissions.retryRateLimited(id);
  Future<void> _saveRateLimitedDraft(
    _PostAuthority a,
    String id,
    int seconds,
  ) => _submissions.saveRateLimitedDraft(
    _PostPublicationContext(this, a),
    id,
    seconds,
  );

  Future<void> reconcile(String id) => _results.reconcile(id);
  Future<void> seal(String id) => _results.seal(id);
  Future<void> _dropRetryBuffers(_PostAuthority a, PostTask task) =>
      _results.dropRetryBuffers(_PostPublicationContext(this, a), task);

  Future<void> _projectPublicationResult(
    _PostAuthority a,
    PostResultUpdate update,
  ) async {
    final entry = update.previous;
    final state = update.state;
    final data = update.data;
    if (update.fromTask) {
      final task = update.task!;
      _personal.recordTask(task);
      _clearCommandError(entry.intents.last.commandId);
      if (state == 'ACCEPTED' &&
          data['images'] is List &&
          (data['images'] as List).isNotEmpty) {
        unawaited(resumeImageUpload(entry.id, automatic: true));
      }
      await _refreshLocal(a);
      if (!_current(a)) return;
      if (update.announcePublication) {
        _noticePublication(a, task);
      }
      if (!_current(a)) return;
      await _dropRetryBuffers(a, task);
      if (!_current(a)) return;
      if (state == 'PUBLISHED') unawaited(_insertPublished(a, task.postId));
    } else {
      final id = entry.id;
      final intent = entry.intents.last;
      final observedTask = update.task;
      final taskId = data['taskId'] as String?;
      if (observedTask != null) {
        _personal.recordTask(observedTask);
      }
      if (update.commandState != PostCommandState.unknownNotObserved &&
          update.commandState != PostCommandState.resultExpired) {
        _clearCommandError(intent.commandId);
      }
      await _refreshLocal(a);
      if (!_current(a)) return;
      if (update.announcePublication && observedTask != null) {
        _noticePublication(a, observedTask);
      }
      if (!_current(a)) return;
      final currentTask = taskId == null ? null : _personal.taskById(taskId);
      if (state == 'ACCEPTED' &&
          data['images'] is List &&
          (data['images'] as List).isNotEmpty) {
        unawaited(resumeImageUpload(id, automatic: true));
      }
      if (currentTask != null) await _dropRetryBuffers(a, currentTask);
      if (!_current(a)) return;
      if (state == 'DELETED') {
        _markPostDeleted(data['postId'] as String);
        _notify();
      } else if (state == 'PUBLISHED') {
        unawaited(_insertPublished(a, data['postId'] as String));
      }
    }
  }

  Future<void> _insertPublished(_PostAuthority a, String postId) =>
      _personal.insertPublished(_PostPublicationContext(this, a), postId);

  Future<void> _updatePublishedFeed(
    PostPublicationContext a,
    PostDetail post,
  ) async {
    final postId = post.postId;
    if (currentChannelId == post.channelId) {
      final request = _feedRequest;
      final latest = await a.accept(
        await _api.feed(sessionToken: a.token, channelId: post.channelId),
      );
      if (_deletedPostIds.contains(postId)) return;
      if (request == _feedRequest &&
          currentChannelId == post.channelId &&
          latest.items.any((p) => p.postId == postId)) {
        // 服务器给出最新页顺序；历史回执不把旧帖顶到首位，不改变原分页游标。
        final visibleItems = latest.items
            .where((p) => !_deletedPostIds.contains(p.postId))
            .toList();
        final prefixIds = visibleItems.map((p) => p.postId).toSet();
        feedItems = [
          ...visibleItems,
          ...feedItems.where((p) => !prefixIds.contains(p.postId)),
        ];
      }
    }
  }

  Future<void> refreshPersonalProjections() =>
      _personal.refreshPersonalProjections();
  Future<PostDraftEditor?> editFailedTask(String taskId) =>
      _maintenance.editFailedTask(taskId);
  Future<void> cancelTask(String taskId) => _maintenance.cancelTask(taskId);
  Future<void> hideTask(String taskId) => _maintenance.hideTask(taskId);
  Future<bool> deletePost(String postId) => _maintenance.deletePost(postId);
  Future<PostDraftEditor?> recoverUnaccepted(String id) =>
      _maintenance.recoverUnaccepted(id);
  Future<void> discardUnaccepted(String id) =>
      _maintenance.discardUnaccepted(id);

  /// 只由认证流程持久确认正式关闭后调用；普通退出和冻结不会到这里。
  Future<void> purgeClosedAccount(String originalAccountId) async {
    await _activating[originalAccountId];
    await _retired[originalAccountId];
    final current = _store;
    if (_purgeStore != null) {
      if (current?.accountId == originalAccountId) {
        _store = null;
        await current!.close();
      }
      await _purgeStore(originalAccountId);
      return;
    }
    if (current != null && current.accountId == originalAccountId) {
      await current.purgeClosedAccount();
      _personal.reset();
    } else {
      final store = await _openStore(originalAccountId);
      try {
        await store.purgeClosedAccount();
      } finally {
        await store.close();
      }
    }
  }

  static String _rejectionMessage(String? code) => switch (code) {
    'POST_IDENTITY_UNAVAILABLE' => '原身份已失效，请核对任务或重新选择草稿身份。',
    'TASK_NOT_RETRYABLE' => '当前任务不能重试，请核对最新状态。',
    'POSTING_RESTRICTED' || 'ACCOUNT_CLOSING' => '当前暂不能发布，原操作已保留。',
    'POST_CHANNEL_UNAVAILABLE' => '当前分类不可用。',
    _ => '服务端未接受这次操作，请核对原结果。',
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _personal.removeListener(_notify);
    _maintenance.removeListener(_notify);
    _personal.dispose();
    _maintenance.dispose();
    _disposed = true;
    _results.dispose();
    _drafts.removeListener(_notify);
    _submissions.removeListener(_notify);
    _drafts.dispose();
    _submissions.dispose();
    _epoch++;
    _homeFeed.removeListener(_notify);
    _homeFeed.dispose();
    _sessions.removeListener(_authorityChanged);
    _authStore.removeListener(_authorityChanged);
    final store = _store;
    _store = null;
    if (store != null) unawaited(store.close().catchError((Object _) {}));
    super.dispose();
  }
}

/// Keeps the existing feed API available to callers importing this library.
/// Home routes use [PostController.homeFeed], which owns all timeline state.
extension FeedController on PostController {
  List<FeedPost> get timelineItems => homeFeed.timelineItems;
  Set<String> get blockedChannelIds => homeFeed.blockedChannelIds;
  int? postViewCount(String id) => homeFeed.postViewCount(id);
  int get timelineGeneration => homeFeed.timelineGeneration;
  String? get timelineChannelId => homeFeed.timelineChannelId;
  String? get timelineCursor => homeFeed.timelineCursor;
  String? get timelineError => homeFeed.timelineError;
  String? get preferencesError => homeFeed.preferencesError;
  bool get timelineLoading => homeFeed.timelineLoading;
  bool get preferencesSaving => homeFeed.preferencesSaving;
  Future<void> loadTimeline({
    String? channelId,
    bool more = false,
    bool recoverMissingInteractions = true,
  }) => homeFeed.loadTimeline(
    channelId: channelId,
    more: more,
    recoverMissingInteractions: recoverMissingInteractions,
  );
  Future<void> saveBlockedChannels(Set<String> ids) =>
      homeFeed.saveBlockedChannels(ids);
  Future<void> registerVisiblePost(String postId) =>
      homeFeed.registerVisiblePost(postId);
}
