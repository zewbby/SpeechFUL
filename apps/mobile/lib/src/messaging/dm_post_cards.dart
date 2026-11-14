import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
import '../posts/post_api.dart';
import 'dm_controller.dart';
import 'dm_runtime.dart';

/// A reference is the only durable chat content. Preview data lives only in the
/// visible widget, and is dropped whenever the authorization window closes.
class DmPostCardBubble extends StatefulWidget {
  const DmPostCardBubble({super.key, required this.postId, required this.time});
  final String postId, time;
  @override
  State<DmPostCardBubble> createState() => _DmPostCardBubbleState();
}

class _DmPostCardBubbleState extends State<DmPostCardBubble>
    with WidgetsBindingObserver {
  DmRuntime? _runtime;
  DmController? _controller;
  String? _scope;
  Map<String, dynamic>? _card;
  String _placeholder = '联网后查看';
  int _generation = 0;
  bool _opening = false;
  Future<bool>? _loadInFlight;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final runtime = DmScope.of(context);
    if (runtime == _runtime) return;
    _controller?.removeListener(_authorityChanged);
    _runtime = runtime;
    _controller = runtime?.controller;
    _scope = _controller?.scope;
    _controller?.addListener(_authorityChanged);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_load());
      }
    });
    unawaited(_load());
  }

  void _authorityChanged() {
    if (_controller?.scope != _scope || _controller?.available != true) {
      _generation++;
      if (mounted) {
        setState(() {
          _card = null;
          _placeholder = '联网后查看';
        });
      }
    }
  }

  bool get _current =>
      mounted && _controller?.available == true && _controller?.scope == _scope;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
    } else {
      _generation++;
      if (mounted) setState(() => _card = null);
    }
  }

  Future<bool> _load() {
    if (!_current) return Future.value(false);
    return _loadInFlight ??= _performLoad().whenComplete(
      () => _loadInFlight = null,
    );
  }

  Future<bool> _performLoad() async {
    final generation = ++_generation;
    if (mounted) setState(() => _card = null);
    try {
      final card = await _controller!.postCard(widget.postId);
      if (!_current || generation != _generation) return false;
      setState(() => _card = card);
      return true;
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _card = null;
          _placeholder = error is PostFailure && error.code == 'POST_NOT_FOUND'
              ? '帖子已不可用'
              : '联网后查看';
        });
      }
      return false;
    }
  }

  Future<void> _open() async {
    if (_opening || !_current) return;
    setState(() => _opening = true);
    try {
      if (await _load() && mounted && _current) {
        final open = _runtime?.openPost;
        if (open != null) {
          setState(() => _card = null);
          await open(context, widget.postId);
          if (mounted && _current) await _load();
        }
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _controller?.removeListener(_authorityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: _current ? _open : null,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.article_outlined, size: 20),
                const SizedBox(width: 6),
                Text(hhText(context, '分享')),
              ],
            ),
            const SizedBox(height: 8),
            if (_opening) const LinearProgressIndicator(),
            Text(
              _card?['title'] as String? ?? hhText(context, _placeholder),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (_card != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(hhText(context, _card!['channelName'] as String)),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                widget.time,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> sharePostInDm(BuildContext context, String postId) async {
  final runtime = DmScope.of(context);
  if (runtime == null ||
      !runtime.controller.available ||
      !runtime.controller.chatEnabled) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(hhText(context, '暂时无法加载私信'))));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PostRecipientPicker(runtime: runtime, postId: postId),
  );
}

class _PostRecipientPicker extends StatefulWidget {
  const _PostRecipientPicker({required this.runtime, required this.postId});
  final DmRuntime runtime;
  final String postId;
  @override
  State<_PostRecipientPicker> createState() => _PostRecipientPickerState();
}

class _PostRecipientPickerState extends State<_PostRecipientPicker> {
  DmController get c => widget.runtime.controller;
  late final String scope = c.scope;
  String? _identity;
  bool _loading = true, _busy = false, _sending = false;
  String? _error;
  bool get current => mounted && c.available && c.scope == scope;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    unawaited(_refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    try {
      await c.sync();
      if (!current) return;
      await c.postCard(widget.postId);
      if (current) setState(() => _error = c.error);
    } catch (error) {
      if (current) {
        setState(
          () => _error = error is PostFailure && error.code == 'POST_NOT_FOUND'
              ? '帖子已不可用'
              : '暂时无法分享，请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  Future<void> _send(Map<String, dynamic> dir) async {
    if (!current || _busy) return;
    setState(() => _busy = true);
    final own = widget.runtime.identities
        .where((i) => i.id == dir['identityId'])
        .firstOrNull;
    if (own == null) {
      setState(() => _busy = false);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(hhText(dialog, '发送帖子卡片？')),
        content: Text(
          hhText(
            dialog,
            '以 {self} 发送给 {peer}',
            args: {'self': own.name, 'peer': dir['peerName']},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(hhText(dialog, '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(hhText(dialog, '发送')),
          ),
        ],
      ),
    );
    if (!current) return;
    if (confirmed != true) {
      setState(() => _busy = false);
      return;
    }
    setState(() => _sending = true);
    try {
      // Refresh before enqueue; final authorization still belongs to the server.
      await c.sync();
      if (!current) return;
      final fresh = c.conversations
          .where(
            (v) =>
                v['id'] == dir['id'] &&
                v['identityId'] == dir['identityId'] &&
                v['canShare'] == true,
          )
          .firstOrNull;
      if (fresh == null) throw StateError('Conversation unavailable');
      final state = await c.sharePost(fresh, widget.postId);
      if (!mounted || !current) return;
      final text = switch (state) {
        'sent' => '帖子卡片已发送',
        'failed' => '发送失败，请在私信中查看并重试',
        _ => '已保存待发送，请在私信中查看结果',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(hhText(context, text))));
      Navigator.pop(context);
    } catch (_) {
      if (current) {
        setState(() {
          _error = '暂时无法分享，请重试。';
          _busy = false;
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final identities = widget.runtime.identities;
    final selected =
        identities.where((i) => i.id == _identity).firstOrNull ??
        identities.firstOrNull;
    final dirs = current
        ? c.conversations
              .where(
                (v) =>
                    v['identityId'] == selected?.id &&
                    v['canShare'] == true &&
                    v['deleted'] != true &&
                    v['hidden'] != true,
              )
              .toList()
        : <Map<String, dynamic>>[];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hhText(context, '分享至私信'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (selected != null)
              DropdownButtonFormField<String>(
                initialValue: selected.id,
                decoration: InputDecoration(
                  labelText: hhText(context, '选择发送身份'),
                ),
                items: identities
                    .map(
                      (i) => DropdownMenuItem(value: i.id, child: Text(i.name)),
                    )
                    .toList(),
                onChanged: !current || _busy
                    ? null
                    : (id) => setState(() => _identity = id),
              ),
            const SizedBox(height: 12),
            if (!current)
              Text(hhText(context, '暂时无法加载私信'))
            else if (_loading || _sending)
              const LinearProgressIndicator(),
            if (_error != null) Text(hhText(context, _error!)),
            if (!_loading && current && dirs.isEmpty)
              Text(hhText(context, '暂无可分享的会话，请先与对方互相回复')),
            Expanded(
              child: ListView(
                children: [
                  for (final dir in dirs)
                    ListTile(
                      title: Text(
                        (dir['note'] as String?)?.isNotEmpty == true
                            ? dir['note'] as String
                            : dir['peerName'] as String,
                      ),
                      subtitle: Text(
                        hhText(
                          context,
                          '收件身份：{peer}',
                          args: {'peer': dir['peerName']},
                        ),
                      ),
                      onTap: _busy || _loading || _error != null
                          ? null
                          : () => _send(dir),
                    ),
                ],
              ),
            ),
            if (_error != null && current)
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() {
                          _loading = true;
                          _error = null;
                        });
                        unawaited(_refresh());
                      },
                child: Text(hhText(context, '重试')),
              ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: Text(hhText(context, '取消')),
            ),
          ],
        ),
      ),
    );
  }
}
