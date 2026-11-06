part of 'post_controller.dart';

class SubmittedPostEdit {
  SubmittedPostEdit._(this.entry)
    : commandId = PostJson.text(entry.data, 'commandId'),
      baseRevision = PostJson.id(entry.data, 'baseRevision'),
      title = entry.data['title'] as String,
      body = entry.data['body'] as String,
      tags = entry.data.containsKey('tags')
          ? PostTags.parse(entry.data['tags'])
          : null,
      imageCount = PostJson.integer(entry.data, 'imageCount', 0, 9),
      imageIds = (entry.data['imageIds'] as List?)?.cast<String>(),
      images = DraftPostImage.list(entry.data['images']);

  final StoredPostEntry entry;
  final String commandId, baseRevision, title, body;
  final int imageCount;
  final List<String>? imageIds;
  final List<String>? tags;
  final List<DraftPostImage> images;
}

extension PublishedPostEditing on PostController {
  int postMediaRevision(String id) => _postMediaRevisions[id] ?? 0;

  void markPostMediaEdited(String id) {
    _postMediaRevisions[id] = postMediaRevision(id) + 1;
    _notify();
  }

  PostEditSession? openPostEdit(String postId) {
    final api = _api;
    if (!available || api is! PostEditApi || isPostDeleted(postId)) return null;
    return PostEditSession._(this, api as PostEditApi, postId);
  }

  void refreshEditedPost(PostDetail post) {
    final id = post.postId;
    feedItems = [for (final old in feedItems) old.postId == id ? post : old];
    _timeline = [
      for (final old in _timeline)
        if (old.postId == id)
          FeedPost(
            postId: id,
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
    _own = [
      for (final old in _own)
        if (old.post.postId == id)
          OwnPostCard(post: post, serverSortAt: old.serverSortAt)
        else
          old,
    ];
    _mergePersonal();
    _repostItems = [
      for (final old in _repostItems)
        if (old.postId == id)
          RepostedPost(
            postId: id,
            identityId: old.identityId,
            repostedAt: old.repostedAt,
            post: post,
          )
        else
          old,
    ];
    _notify();
  }
}

class PostEditSession {
  PostEditSession._(this._controller, this._api, this.postId)
    : _epoch = _controller.authorityVersion;

  final PostController _controller;
  final PostEditApi _api;
  final String postId;
  final int _epoch;

  bool get current =>
      _controller.available && _controller.authorityVersion == _epoch;

  Future<_PostAuthority> _authority({bool storage = false}) async {
    if (!current) throw _StalePostAuthority();
    final a = await _controller._authority(storage: storage);
    if (!current || a.epoch != _epoch) throw _StalePostAuthority();
    return a;
  }

  Future<T> _request<T>(
    Future<PostResponse<T>> Function(String token) send,
  ) async {
    final a = await _authority();
    try {
      return await _controller._accept(a, await send(a.token));
    } on PostFailure catch (error) {
      if (error.kind == PostFailureKind.unauthorized ||
          error.code == 'AUTHORIZATION_UNAVAILABLE') {
        _controller._failure(error, a);
      }
      rethrow;
    }
  }

  Future<PublishedPostEdit> load() =>
      _request((token) => _api.readEdit(sessionToken: token, postId: postId));

  Future<SubmittedPostEdit?> pending() async {
    final a = await _authority(storage: true);
    final entry = await a.store!.readPostEdit(postId);
    if (!current) throw _StalePostAuthority();
    return entry == null ? null : SubmittedPostEdit._(entry);
  }

  Future<SubmittedPostEdit> prepare({
    required String baseRevision,
    required String title,
    required String body,
    required int imageCount,
    List<String> tags = const [],
    List<String>? imageIds,
    List<DraftPostImage> images = const [],
    Map<String, Uint8List> originals = const {},
    SubmittedPostEdit? replacing,
  }) async {
    final a = await _authority(storage: true);
    final entry = await a.store!.writePostEdit(
      postId,
      replacing?.entry.revision,
      {
        'commandId': _controller._newId(),
        'baseRevision': baseRevision,
        'title': title,
        'body': body,
        'tags': PostTags.parse(tags),
        'imageCount': imageCount,
        if (imageIds != null) 'imageIds': imageIds,
        'images': images.map((image) => image.toJson()).toList(),
      },
      originals,
    );
    if (!current) throw _StalePostAuthority();
    return SubmittedPostEdit._(entry);
  }

  Future<void> clear(SubmittedPostEdit submission) async {
    final a = await _authority(storage: true);
    await a.store!.clearPostEdit(postId, submission.entry.revision);
  }

  Future<PostEditResult> check(SubmittedPostEdit submission) => _request(
    (token) => _api.editResult(
      sessionToken: token,
      postId: postId,
      commandId: submission.commandId,
    ),
  );

  bool get canPickImages => _controller._photoPicker != null;

  Future<List<PostPickedFile>> pickImages(int remaining) async {
    if (!current || !canPickImages) return [];
    final files = await _controller._photoPicker!.pick(remaining);
    if (!current) throw _StalePostAuthority();
    return files;
  }

  Future<Uint8List> readSelectedImage(DraftPostImage image) async {
    final a = await _authority(storage: true);
    final selection = image.selection!;
    final bytes = await a.store!.readMedia(
      image.blobId,
      selection.byteLength,
      selection.sha256,
    );
    if (!current) throw _StalePostAuthority();
    return bytes;
  }

  Future<PostEditResult> submit(SubmittedPostEdit submission) async {
    for (final image in submission.images) {
      final bytes = await readSelectedImage(image);
      try {
        await _request(
          (token) => _api.stageEditImage(
            sessionToken: token,
            postId: postId,
            commandId: submission.commandId,
            imageId: image.mediaId,
            mimeType: image.selection!.mimeType,
            bytes: bytes,
          ),
        );
      } on PostFailure catch (error) {
        if (error.code != 'MEDIA_INVALID' &&
            error.code != 'POSTING_RESTRICTED') {
          rethrow;
        }
        // The final operation can record a missing image or a restriction
        // without publishing an incomplete selection.
        break;
      }
    }
    return _request(
      (token) => _api.saveEdit(
        sessionToken: token,
        postId: postId,
        commandId: submission.commandId,
        revision: submission.baseRevision,
        title: submission.title,
        body: submission.body,
        tags: submission.tags,
        imageIds: submission.imageIds,
      ),
    );
  }
}
