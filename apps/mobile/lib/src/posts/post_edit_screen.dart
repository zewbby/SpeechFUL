part of 'post_screens.dart';

class _PublishedPostEditScreen extends StatefulWidget {
  const _PublishedPostEditScreen({
    required this.session,
    required this.controller,
    this.loadImages,
  });

  final PostEditSession session;
  final PostController controller;
  final PostImagesLoader? loadImages;

  @override
  State<_PublishedPostEditScreen> createState() =>
      _PublishedPostEditScreenState();
}

class _PublishedPostEditScreenState extends State<_PublishedPostEditScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  SubmittedPostEdit? _submission;
  String? _revision, _error;
  int _imageCount = 0;
  List<String> _tags = const [];
  bool _busy = true, _knownFailure = false, _conflict = false;
  bool _imagesAvailable = false;
  final _images = <({String id, DraftPostImage? local})>[];
  final _newOriginals = <String, Uint8List>{};
  PostImages? _previews;
  int _previewRequest = 0;

  PostEditSession get _session => widget.session;
  bool get _pending => _submission != null && !_knownFailure;
  bool get _editable => !_busy && !_pending && _revision != null;

  @override
  void initState() {
    super.initState();
    unawaited(_load(recover: true));
  }

  @override
  void dispose() {
    _previews?.onRelease?.call();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load({required bool recover}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (recover) {
        final previous = await _session.pending();
        if (!mounted || !_session.current) return;
        if (previous != null) {
          _submission = previous;
          _revision = previous.baseRevision;
          _title.text = previous.title;
          _body.text = previous.body;
          _tags = previous.tags ?? const [];
          _imageCount = previous.imageCount;
          _imagesAvailable = previous.imageIds != null;
          final local = {
            for (final image in previous.images) image.mediaId: image,
          };
          _images
            ..clear()
            ..addAll([
              for (final id in previous.imageIds ?? const <String>[])
                (id: id, local: local[id]),
            ]);
          await _handle(await _session.check(previous));
          if (mounted && _knownFailure) unawaited(_loadPreviews());
          return;
        }
      }
      final latest = await _session.load();
      final previous = _submission;
      if (previous != null) await _session.clear(previous);
      if (!mounted || !_session.current) return;
      _submission = null;
      _knownFailure = false;
      _conflict = false;
      _revision = latest.revision;
      _title.text = latest.post.title;
      _body.text = latest.post.body;
      _tags = latest.post.tags;
      _imageCount = latest.post.imageCount;
      _imagesAvailable = latest.imageIds != null;
      _newOriginals.clear();
      _images
        ..clear()
        ..addAll([
          for (final id in latest.imageIds ?? const <String>[])
            (id: id, local: null),
        ]);
      unawaited(_loadPreviews());
    } catch (error) {
      await _handleError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final revision = _revision;
    if (!_editable || _conflict || revision == null) return;
    if (_imagesAvailable && _images.length > PostContentRules.maxImages) {
      setState(() => _error = '每篇帖子最多添加3张图片，请先移除多余图片。');
      return;
    }
    if (_images.any((image) => image.local?.ready == false)) {
      setState(() => _error = '请移除无法读取的图片或重新选择。');
      return;
    }
    final imageCount = _imagesAvailable ? _images.length : _imageCount;
    try {
      PostContentRules.validateTitle(_title.text);
      if (_body.text.isNotEmpty || imageCount == 0) {
        PostContentRules.validateBody(_body.text);
      }
    } on FormatException {
      setState(() => _error = '请填写有效标题，并提供正文或图片。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final submission = await _session.prepare(
        baseRevision: revision,
        title: _title.text,
        body: _body.text,
        tags: _tags,
        imageCount: imageCount,
        imageIds: _imagesAvailable
            ? [for (final image in _images) image.id]
            : null,
        images: [
          for (final image in _images)
            if (image.local case final local?) local,
        ],
        originals: _newOriginals,
        replacing: _submission,
      );
      if (!mounted || !_session.current) return;
      _submission = submission;
      _newOriginals.clear();
      _knownFailure = false;
      await _handle(await _session.submit(submission));
    } catch (error) {
      await _handleError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check({required bool retry}) async {
    final submission = _submission;
    if (_busy || !_pending || submission == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var result = await _session.check(submission);
      if (retry && result.state == 'PENDING' && mounted) {
        result = await _session.submit(submission);
      }
      await _handle(result);
    } catch (error) {
      await _handleError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handle(PostEditResult result) async {
    if (!mounted || !_session.current) return;
    if (result.state == 'SAVED') {
      widget.controller.markPostMediaEdited(_session.postId);
      await _close('');
      return;
    }
    if (result.state == 'PENDING') {
      _error = '保存结果待核对。';
      return;
    }
    final reason = _postEditUnavailable(result.code);
    if (reason != null) {
      await _close(reason);
      return;
    }
    _knownFailure = true;
    _conflict = result.code == 'POST_EDIT_CONFLICT';
    _error = _conflict
        ? '帖子已有更新。可复制当前文字，载入最新版后再编辑。'
        : result.code == 'POSTING_RESTRICTED'
        ? '当前发言受限。修改保留在此页，可稍后重试。'
        : result.code == 'POST_EDIT_MEDIA_MISSING'
        ? '部分图片未能保存。修改仍保留在此页，可重试或重新选图。'
        : '保存失败。修改保留在此页，可重试。';
  }

  Future<void> _handleError(Object error) async {
    if (!mounted || !_session.current) return;
    final code = error is PostFailure ? error.code : null;
    final reason = _postEditUnavailable(code);
    if (reason != null) {
      await _close(reason);
      return;
    }
    _error = _pending
        ? '保存结果待核对。'
        : error is PostStorageFailure
        ? '本机保存失败。修改仍保留在此页，可重试。'
        : code == 'POSTING_RESTRICTED'
        ? '当前发言受限。'
        : '暂时无法读取编辑内容，请重试。';
  }

  Future<void> _close(String? outcome) async {
    final previous = _submission;
    if (previous != null) {
      try {
        await _session.clear(previous);
      } on PostStorageFailure {
        if (outcome == null) {
          if (mounted) {
            setState(() => _error = '暂时无法丢弃本机修改，请重试。');
          }
          return;
        }
        // The server receipt will resolve this anchor on next entry.
      }
    }
    if (mounted && _session.current) Navigator.pop(context, outcome);
  }

  Future<void> _loadPreviews() async {
    final loader = widget.loadImages;
    if (loader == null || !_images.any((image) => image.local == null)) return;
    final request = ++_previewRequest;
    try {
      final group = await loader(_session.postId);
      if (!mounted || !_session.current || request != _previewRequest) {
        group.onRelease?.call();
        return;
      }
      _previews?.onRelease?.call();
      setState(() => _previews = group);
      group.maintainAccessWhile?.call(
        () =>
            mounted &&
            _session.current &&
            ModalRoute.of(context)?.isCurrent == true,
      );
    } catch (_) {
      // Editing and retries still use the ordered references from the snapshot.
    }
  }

  Future<void> _pickImages({int? replace}) async {
    final remaining = replace == null
        ? PostContentRules.maxImages - _images.length
        : 1;
    if (!_editable || !_session.canPickImages || remaining < 1) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final files = await _session.pickImages(remaining);
      for (final file in files.take(remaining)) {
        final id = newPostMediaId(), blobId = newPostMediaId();
        DraftPostImage local;
        try {
          final photo = await inspectPostPhoto(
            file,
            id,
          ).timeout(const Duration(seconds: 20));
          if (!mounted || !_session.current) return;
          local = DraftPostImage(
            blobId: blobId,
            mediaId: id,
            selection: photo.selection,
          );
          _newOriginals[blobId] = photo.bytes;
        } catch (_) {
          if (!mounted || !_session.current) return;
          local = DraftPostImage(blobId: blobId, mediaId: id);
          _error = '部分图片无法读取。可以移除或重新选择。';
        }
        final image = (id: id, local: local);
        if (replace == null) {
          _images.add(image);
        } else {
          final old = _images[replace].local;
          if (old != null) _newOriginals.remove(old.blobId);
          _images[replace] = image;
        }
      }
    } catch (_) {
      if (mounted && _session.current) _error = '暂时无法选择图片，已保留当前修改。';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _moveImage(int from, int to) {
    if (!_editable || from < 0 || from == to) return;
    setState(() => _images.insert(to, _images.removeAt(from)));
  }

  Widget _photos(bool editable) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Text('图片 ${_images.length}/${PostContentRules.maxImages}'),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 16) / 3;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < _images.length; index++)
                _photoTile(context, index, width, editable),
              if (_images.length < PostContentRules.maxImages &&
                  _session.canPickImages)
                SizedBox.square(
                  dimension: width,
                  child: Material(
                    color: HhTelegramPalette.of(context).background,
                    child: IconButton(
                      tooltip: '添加图片',
                      onPressed: editable ? _pickImages : null,
                      icon: const Icon(Icons.add),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget _photoTile(
    BuildContext context,
    int index,
    double width,
    bool editable,
  ) {
    final image = _images[index], local = image.local;
    final group = _previews;
    final published = group?.images
        .where((photo) => photo.item.id == image.id)
        .firstOrNull;
    final tile = SizedBox.square(
      dimension: width,
      child: Material(
        color: HhTelegramPalette.of(context).background,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (local != null && local.ready)
              _DraftPhotoPreview(
                key: ValueKey(local.blobId),
                load: () async =>
                    _newOriginals[local.blobId] ??
                    await _session.readSelectedImage(local),
              )
            else if (local != null)
              IconButton(
                tooltip: '重新选择第${index + 1}张图片',
                onPressed: editable ? () => _pickImages(replace: index) : null,
                icon: const Icon(Icons.broken_image_outlined),
              )
            else if (group != null && published != null)
              _EditPublishedPreview(
                key: ValueKey((group, image.id)),
                group: group,
                image: published,
              )
            else
              IconButton(
                tooltip: '重载图片预览',
                icon: const Icon(Icons.image_outlined),
                onPressed: _loadPreviews,
              ),
            if (editable)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton.filledTonal(
                  tooltip: '移除第${index + 1}张图片',
                  onPressed: () => setState(() {
                    _images.removeAt(index);
                    if (local != null) _newOriginals.remove(local.blobId);
                  }),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
    return DragTarget<String>(
      key: ValueKey(image.id),
      onWillAcceptWithDetails: (drag) => editable && drag.data != image.id,
      onAcceptWithDetails: (drag) => _moveImage(
        _images.indexWhere((image) => image.id == drag.data),
        index,
      ),
      builder: (context, _, _) => Semantics(
        label: '第${index + 1}张图片',
        customSemanticsActions: {
          if (editable && index > 0)
            const CustomSemanticsAction(label: '向前移动'): () =>
                _moveImage(index, index - 1),
          if (editable && index + 1 < _images.length)
            const CustomSemanticsAction(label: '向后移动'): () =>
                _moveImage(index, index + 1),
        },
        child: LongPressDraggable<String>(
          data: image.id,
          maxSimultaneousDrags: editable ? 1 : 0,
          feedback: Material(
            elevation: 4,
            child: SizedBox.square(
              dimension: width,
              child: const Icon(Icons.image),
            ),
          ),
          childWhenDragging: Opacity(opacity: .35, child: tile),
          child: tile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: PostTheme.of(context),
    child: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final current = _session.current;
        final editable = current && _editable;
        return PopScope<String>(
          canPop: !current || !_busy && !_knownFailure,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !_busy && _knownFailure) unawaited(_close(null));
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('编辑帖子'),
              actions: [
                if (current)
                  TextButton(
                    onPressed: editable && !_conflict ? _save : null,
                    child: const Text('保存'),
                  ),
              ],
            ),
            body: !current
                ? const Center(child: Text('请重新核对登录状态。'))
                : _revision == null && _busy
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_busy) const LinearProgressIndicator(),
                      if (_error case final message?)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              message,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      if (_pending)
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _check(retry: false),
                              child: const Text('再次核对'),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _check(retry: true),
                              child: const Text('重试本次提交'),
                            ),
                          ],
                        ),
                      if (_conflict)
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => Clipboard.setData(
                                      ClipboardData(
                                        text: '${_title.text}\n${_body.text}',
                                      ),
                                    ),
                              child: const Text('复制文字'),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _load(recover: false),
                              child: const Text('载入最新版'),
                            ),
                          ],
                        ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (_revision != null) ...[
                              TextField(
                                controller: _title,
                                readOnly: !editable,
                                maxLength: 15,
                                decoration: const InputDecoration(
                                  labelText: '标题',
                                ),
                              ),
                              TextField(
                                controller: _body,
                                readOnly: !editable,
                                minLines: 5,
                                maxLines: null,
                                maxLength: 3000,
                                decoration: const InputDecoration(
                                  labelText: '正文',
                                ),
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(hhText(context, '添加标签')),
                                subtitle: Text(
                                  _tags.isEmpty
                                      ? hhText(context, '选填，最多3个')
                                      : _tags.map((t) => '#$t').join('  '),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: editable && !_conflict
                                    ? () async {
                                        final tags = await showPostTagPicker(
                                          context,
                                          widget.controller,
                                          _tags,
                                        );
                                        if (mounted &&
                                            _session.current &&
                                            tags != null) {
                                          setState(() => _tags = tags);
                                        }
                                      }
                                    : null,
                              ),
                              if (_imagesAvailable)
                                _photos(editable && !_conflict),
                            ],
                            if (_revision == null && !_busy)
                              TextButton(
                                onPressed: () => _load(recover: true),
                                child: const Text('重试读取'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    ),
  );
}

class _EditPublishedPreview extends StatefulWidget {
  const _EditPublishedPreview({
    required this.group,
    required this.image,
    super.key,
  });

  final PostImages group;
  final PostImage image;

  @override
  State<_EditPublishedPreview> createState() => _EditPublishedPreviewState();
}

class _EditPublishedPreviewState extends State<_EditPublishedPreview> {
  late final Future<ImageProvider>? _load = widget.image.loadThumbnail?.call();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.group.accessGranted,
    builder: (context, granted, _) {
      if (!granted) return const Icon(Icons.image_not_supported_outlined);
      return FutureBuilder<ImageProvider>(
        future: _load,
        initialData: widget.image.thumbnail,
        builder: (context, state) => switch (state.data) {
          final provider? => Image(
            image: provider,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
          ),
          null => Icon(
            state.hasError ? Icons.broken_image_outlined : Icons.image_outlined,
          ),
        },
      );
    },
  );
}

String? _postEditUnavailable(String? code) => switch (code) {
  'POST_EDIT_DELETED' => '帖子已删除，编辑已关闭。',
  'POST_EDIT_HIDDEN' => '帖子已下架，编辑已关闭。',
  'POST_IDENTITY_UNAVAILABLE' => '原发言身份已失效，编辑已关闭。',
  'POST_NOT_FOUND' => '帖子已不可用，编辑已关闭。',
  _ => null,
};
