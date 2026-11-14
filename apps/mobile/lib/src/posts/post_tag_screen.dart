import 'dart:async';

import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../localization/app_localizations.dart';
import 'post_api.dart';
import 'post_controller.dart';
import 'post_models.dart';
import 'post_images.dart';
import 'post_screens.dart';
import 'post_tag_widgets.dart';

Future<void> openPostTag(
  BuildContext context, {
  required PostController controller,
  required String tag,
  required List<Channel> channels,
  required VoidCallback onAuthenticationRequired,
  PostImagesLoader? loadImages,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => PostTagScreen(
      controller: controller,
      tag: tag,
      channels: channels,
      onAuthenticationRequired: onAuthenticationRequired,
      loadImages: loadImages,
    ),
  ),
);

class PostTagScreen extends StatefulWidget {
  const PostTagScreen({
    super.key,
    required this.controller,
    required this.tag,
    required this.channels,
    required this.onAuthenticationRequired,
    this.loadImages,
  });
  final PostController controller;
  final String tag;
  final List<Channel> channels;
  final VoidCallback onAuthenticationRequired;
  final PostImagesLoader? loadImages;
  @override
  State<PostTagScreen> createState() => _PostTagScreenState();
}

class _PostTagScreenState extends State<PostTagScreen> {
  late final int _epoch;
  final _scroll = ScrollController();
  List<PostCard> _items = const [];
  String? _channel, _cursor, _error;
  bool _loading = false, _ready = false, _restartRequired = false;
  int _version = 0;
  Set<String> _blocked = const {};
  bool get _current =>
      mounted &&
      widget.controller.available &&
      widget.controller.authorityVersion == _epoch;
  @override
  void initState() {
    super.initState();
    _epoch = widget.controller.authorityVersion;
    _blocked = Set.of(widget.controller.blockedChannelIds);
    widget.controller.addListener(_changed);
    _scroll.addListener(_nearEnd);
    scheduleMicrotask(() => _load());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final blocked = widget.controller.blockedChannelIds;
    if (blocked.length != _blocked.length || !blocked.containsAll(_blocked)) {
      _blocked = Set.of(blocked);
      unawaited(_load());
    }
    setState(
      () => _items = _items
          .where(
            (p) =>
                !widget.controller.isPostDeleted(p.postId) &&
                !blocked.contains(p.channelId),
          )
          .toList(),
    );
  }

  void _nearEnd() {
    if (_scroll.position.extentAfter < 400 && !_loading && _cursor != null) {
      unawaited(_load(more: true));
    }
  }

  Future<void> _load({bool more = false}) async {
    if (!_current || more && (_loading || _cursor == null)) return;
    final version = ++_version;
    final old = _cursor;
    setState(() {
      _loading = true;
      _error = null;
      _restartRequired = false;
      if (!more) {
        _items = const [];
        _cursor = null;
        _ready = false;
      }
    });
    try {
      final page = await widget.controller.taggedPosts(
        widget.tag,
        channelId: _channel,
        cursor: more ? old : null,
      );
      if (!_current || version != _version) return;
      setState(() {
        final seen = <String>{};
        _items = [if (more) ..._items, ...page.items]
            .where(
              (p) =>
                  seen.add(p.postId) &&
                  !widget.controller.isPostDeleted(p.postId) &&
                  !widget.controller.blockedChannelIds.contains(p.channelId),
            )
            .toList();
        _cursor = page.nextCursor;
        _ready = true;
      });
    } catch (error) {
      if (_current && version == _version) {
        setState(() {
          _restartRequired =
              error is PostFailure && error.code == 'CURSOR_INVALID';
          if (_restartRequired) _cursor = null;
          _error = _restartRequired ? '列表已变化，请刷新。' : '暂时无法加载，请重试。';
        });
      }
    } finally {
      if (mounted && version == _version) setState(() => _loading = false);
    }
  }

  Future<void> _open(PostCard post) async {
    if (!_current ||
        widget.controller.isPostDeleted(post.postId) ||
        widget.controller.blockedChannelIds.contains(post.channelId)) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          controller: widget.controller,
          postId: post.postId,
          channelName: widget.channels
              .where((c) => c.id == post.channelId)
              .firstOrNull
              ?.name,
          channelNames: {
            for (final channel in widget.channels) channel.id: channel.name,
          },
          onAuthenticationRequired: widget.onAuthenticationRequired,
          loadImages: widget.loadImages,
        ),
      ),
    );
    if (!_current) return;
    try {
      final latest = await widget.controller.readTaggedPost(post.postId);
      if (!_current) return;
      setState(
        () => _items = [
          for (final old in _items)
            if (old.postId != post.postId)
              old
            else if (latest.tags.any(
              (tag) => tag.toLowerCase() == widget.tag.toLowerCase(),
            ))
              latest,
        ],
      );
    } on PostFailure catch (error) {
      if (_current && error.statusCode == 404) {
        setState(
          () => _items = _items.where((p) => p.postId != post.postId).toList(),
        );
      }
    } catch (_) {
      /* The preserved page remains usable; refresh can retry. */
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: TextButton(
            onPressed: widget.onAuthenticationRequired,
            child: Text(hhText(context, '重新登录')),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('#${widget.tag}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String?>(
                    value: _channel,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(hhText(context, '全部分类')),
                      ),
                      for (final c in widget.channels)
                        DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(hhText(context, c.name)),
                        ),
                    ],
                    onChanged: (id) {
                      if (id == _channel) return;
                      setState(() => _channel = id);
                      if (_scroll.hasClients) _scroll.jumpTo(0);
                      unawaited(_load());
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Text(hhText(context, '最新发布')),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _items.length + 1,
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: _loading
                            ? const CircularProgressIndicator()
                            : _error != null
                            ? Column(
                                children: [
                                  Text(hhText(context, _error!)),
                                  TextButton(
                                    onPressed: () => _load(
                                      more:
                                          _items.isNotEmpty &&
                                          !_restartRequired,
                                    ),
                                    child: Text(hhText(context, '重试')),
                                  ),
                                ],
                              )
                            : _ready && _items.isEmpty
                            ? Text(hhText(context, '暂无相关帖子'))
                            : _cursor != null
                            ? TextButton(
                                onPressed: () => _load(more: true),
                                child: Text(hhText(context, '加载更多')),
                              )
                            : const SizedBox.shrink(),
                      ),
                    );
                  }
                  final post = _items[index];
                  return Column(
                    key: ValueKey('tag-result:${post.postId}'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        title: Text(post.title),
                        subtitle: Text(
                          '${hhText(context, widget.channels.where((c) => c.id == post.channelId).firstOrNull?.name ?? '')} · ${post.author.displayName}',
                        ),
                        onTap: () => _open(post),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: PostTagChips(
                          tags: post.tags,
                          onTap: (tag) {
                            if (tag.toLowerCase() != widget.tag.toLowerCase()) {
                              unawaited(
                                openPostTag(
                                  context,
                                  controller: widget.controller,
                                  tag: tag,
                                  channels: widget.channels,
                                  onAuthenticationRequired:
                                      widget.onAuthenticationRequired,
                                  loadImages: widget.loadImages,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
