import 'dart:async';

import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../design_system/detail_components.dart';
import '../localization/app_localizations.dart';
import 'post_api.dart';
import 'post_controller.dart';
import 'post_models.dart';
import 'post_search_api.dart';

class PostSearchScreen extends StatefulWidget {
  const PostSearchScreen({
    super.key,
    required this.controller,
    required this.channels,
    required this.initialChannelId,
    required this.onOpenPost,
    required this.onAuthenticationRequired,
  });

  final PostController controller;
  final List<Channel> channels;
  final String? initialChannelId;
  final void Function(BuildContext context, PostCard post) onOpenPost;
  final VoidCallback onAuthenticationRequired;

  @override
  State<PostSearchScreen> createState() => _PostSearchScreenState();
}

class _PostSearchScreenState extends State<PostSearchScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _historyWrites = <String?, Set<Future<void>>>{};
  late final int _epoch;
  late final Map<String, String> _channels = {
    for (final channel in widget.channels) channel.id: channel.name,
  };
  late String? _channelId = widget.initialChannelId;
  PostSearchSort _sort = PostSearchSort.relevance;
  String? _submitted, _cursor;
  List<PostCard> _posts = const [];
  List<String> _history = const [];
  ({String? cursor, bool recordHistory})? _retry;
  ({
    String keyword,
    String? channelId,
    PostSearchSort sort,
    String? cursor,
    bool recordHistory,
  })?
  _inFlight;
  int _searchRequest = 0, _historyRequest = 0;
  bool _searchLoading = false;
  bool _historyLoading = false, _historyChanging = false, _historyError = false;
  bool _historyExpanded = false, _retired = false;
  String? _inputError;

  PostController get _controller => widget.controller;
  bool get _current =>
      mounted &&
      _controller.available &&
      _controller.authorityVersion == _epoch;
  String get _scopeName => hhText(context, _channels[_channelId] ?? '全部分类');

  @override
  void initState() {
    super.initState();
    // Capture the authority before this route can dispatch any requests.
    _epoch = _controller.authorityVersion;
    _controller.addListener(_authorityChanged);
    if (_current) scheduleMicrotask(_readHistory);
  }

  @override
  void dispose() {
    _controller.removeListener(_authorityChanged);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _authorityChanged() {
    if (!_current && !_retired) {
      _retired = true;
      _focus.unfocus();
      _input.clear();
      _submitted = _cursor = null;
      _retry = null;
      _posts = const [];
      _history = const [];
    }
    setState(() {});
  }

  void _resetResults() {
    ++_searchRequest;
    _inFlight = null;
    _submitted = _cursor = null;
    _posts = const [];
    _retry = null;
    _searchLoading = false;
  }

  void _edit(String value) {
    if (!_current) return;
    final keyword = trimPostSearchKeyword(value);
    setState(() {
      _inputError = null;
      if (_submitted != keyword) _resetResults();
    });
    if (keyword.isEmpty) unawaited(_readHistory());
  }

  void _clearInput() {
    _input.clear();
    _edit('');
    _focus.requestFocus();
  }

  void _submit(String value) {
    if (!_current) return;
    final String keyword;
    try {
      keyword = normalizePostSearchKeyword(value);
    } on FormatException {
      setState(() => _inputError = '请输入 1–100 个字符的关键词');
      return;
    }
    _focus.unfocus();
    setState(() {
      _input.value = TextEditingValue(
        text: keyword,
        selection: TextSelection.collapsed(offset: keyword.length),
      );
      _inputError = null;
      _submitted = keyword;
    });
    unawaited(_loadResults(recordHistory: true));
  }

  void _selectScope(String? channelId) {
    if (!_current || _historyChanging || channelId == _channelId) return;
    setState(() {
      ++_historyRequest;
      _history = const [];
      _historyLoading = _historyError = _historyExpanded = false;
      _channelId = channelId;
    });
    if (_submitted != null) {
      unawaited(_loadResults());
    } else if (trimPostSearchKeyword(_input.text).isEmpty) {
      unawaited(_readHistory());
    }
  }

  void _selectSort(PostSearchSort sort) {
    if (!_current || sort == _sort || _submitted == null) return;
    setState(() => _sort = sort);
    unawaited(_loadResults());
  }

  Future<void> _loadResults({
    String? cursor,
    bool recordHistory = false,
  }) async {
    final keyword = _submitted;
    if (!_current || keyword == null) return;
    final key = (
      keyword: keyword,
      channelId: _channelId,
      sort: _sort,
      cursor: cursor,
      recordHistory: recordHistory,
    );
    if (_inFlight == key) return;
    _inFlight = key;
    final request = ++_searchRequest;
    final channelId = _channelId;
    if (cursor == null && _scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _searchLoading = true;
      _retry = null;
      if (cursor == null) {
        _posts = const [];
        _cursor = null;
      }
    });
    try {
      Future<PostsPage<PostCard>> search() => _controller.searchPosts(
        keyword: keyword,
        channelId: channelId,
        sort: _sort,
        cursor: cursor,
        recordHistory: recordHistory,
      );
      final page = await (recordHistory
          ? _writeHistory(channelId, search)
          : search());
      if (!_current || request != _searchRequest) return;
      final ids = _posts.map((post) => post.postId).toSet();
      if (page.items.any(
        (post) =>
            !_channels.containsKey(post.channelId) || !ids.add(post.postId),
      )) {
        throw const FormatException('Invalid search result scope or overlap');
      }
      setState(() {
        _posts = [..._posts, ...page.items];
        _cursor = page.nextCursor;
      });
    } on Object catch (error) {
      if (!_current || request != _searchRequest) return;
      if (cursor != null &&
          error is PostFailure &&
          error.code == 'CURSOR_INVALID') {
        await _loadResults();
        return;
      }
      setState(() => _retry = (cursor: cursor, recordHistory: recordHistory));
    } finally {
      if (_current && request == _searchRequest) {
        setState(() {
          _inFlight = null;
          _searchLoading = false;
        });
      }
    }
  }

  Future<T> _writeHistory<T>(
    String? channelId,
    Future<T> Function() write,
  ) async {
    final finished = Completer<void>();
    final writes = _historyWrites.putIfAbsent(channelId, () => {});
    writes.add(finished.future);
    try {
      return await write();
    } finally {
      writes.remove(finished.future);
      if (writes.isEmpty) _historyWrites.remove(channelId);
      finished.complete();
    }
  }

  Future<void> _readHistory() async {
    if (!_current) return;
    final channelId = _channelId;
    final request = ++_historyRequest;
    setState(() {
      _historyLoading = true;
      _historyError = false;
      _historyExpanded = false;
      _history = const [];
    });
    try {
      // Clearing the field can reach here before a submitted search commits.
      // Wait for this scope's writes even when their results have been retired.
      var writes = _historyWrites[channelId];
      while (writes != null) {
        await Future.wait(writes);
        if (!_current || request != _historyRequest) return;
        writes = _historyWrites[channelId];
      }
      final entries = await _controller.postSearchHistory(channelId);
      if (_current && request == _historyRequest) {
        setState(() => _history = entries);
      }
    } on Object {
      if (_current && request == _historyRequest) {
        setState(() => _historyError = true);
      }
    } finally {
      if (_current && request == _historyRequest) {
        setState(() => _historyLoading = false);
      }
    }
  }

  Future<void> _changeHistory({String? removeKeyword}) async {
    if (!_current || _historyChanging) return;
    final channelId = _channelId;
    if (removeKeyword == null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(hhText(context, '清空搜索历史？')),
          content: Text(
            hhText(context, '将清空「{scope}」的搜索历史。', args: {'scope': _scopeName}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(hhText(context, '取消')),
            ),
            TextButton(
              key: const ValueKey('post-search-confirm-clear'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(hhText(context, '清空')),
            ),
          ],
        ),
      );
      if (confirmed != true ||
          !_current ||
          channelId != _channelId ||
          _historyChanging) {
        return;
      }
    }
    final request = ++_historyRequest;
    setState(() {
      _historyLoading = false;
      _historyChanging = true;
      _historyError = false;
    });
    try {
      final entries = await _writeHistory(
        channelId,
        () => _controller.changePostSearchHistory(
          channelId,
          removeKeyword: removeKeyword,
        ),
      );
      if (_current && request == _historyRequest) {
        setState(() => _history = entries);
      }
    } on Object {
      if (_current && request == _historyRequest) {
        setState(() {
          _history = const [];
          _historyError = true;
        });
      }
    } finally {
      if (_current) setState(() => _historyChanging = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(hhText(context, '搜索帖子'))),
    body: SafeArea(
      top: false,
      child: !_current
          ? Center(
              child: TextButton(
                onPressed: widget.onAuthenticationRequired,
                child: Text(hhText(context, '登录或核对会话')),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    key: const ValueKey('post-search-input'),
                    autofocus: true,
                    controller: _input,
                    focusNode: _focus,
                    textInputAction: TextInputAction.search,
                    onChanged: _edit,
                    onSubmitted: _submit,
                    decoration: InputDecoration(
                      hintText: hhText(context, '搜索标题或正文'),
                      errorText: _inputError == null
                          ? null
                          : hhText(context, _inputError!),
                      border: const OutlineInputBorder(),
                      prefixIcon: IconButton(
                        tooltip: hhText(context, '提交搜索'),
                        onPressed: () => _submit(_input.text),
                        icon: const Icon(Icons.search),
                      ),
                      suffixIcon: _input.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: hhText(context, '清空关键词'),
                              onPressed: _clearInput,
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PopupMenuButton<String>(
                        key: const ValueKey('post-search-scope'),
                        enabled: !_historyChanging,
                        tooltip: hhText(context, '搜索分类'),
                        initialValue: _channelId ?? '',
                        onSelected: (value) =>
                            _selectScope(value.isEmpty ? null : value),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: '',
                            child: Text(hhText(context, '全部分类')),
                          ),
                          for (final channel in widget.channels)
                            PopupMenuItem(
                              value: channel.id,
                              child: Text(hhText(context, channel.name)),
                            ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_scopeName),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ),
                      ),
                      if (_submitted != null)
                        for (final sort in PostSearchSort.values)
                          ChoiceChip(
                            key: ValueKey('post-search-sort:${sort.name}'),
                            label: Text(
                              hhText(
                                context,
                                sort == PostSearchSort.relevance ? '相关度' : '最新',
                              ),
                            ),
                            selected: _sort == sort,
                            onSelected: (_) => _selectSort(sort),
                          ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _submitted != null
                      ? _buildResults()
                      : trimPostSearchKeyword(_input.text).isEmpty
                      ? _buildHistory()
                      : Center(child: Text(hhText(context, '提交关键词以搜索帖子'))),
                ),
              ],
            ),
    ),
  );

  Widget _buildResults() {
    final retry = _retry;
    final results = _posts
        .where(
          (post) =>
              !_controller.isPostDeleted(post.postId) &&
              !_controller.blockedChannelIds.contains(post.channelId),
        )
        .toList();
    final Widget? footer;
    if (_searchLoading) {
      footer = const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (retry != null) {
      footer = _retryNotice(
        '暂时无法搜索帖子',
        () => _loadResults(
          cursor: retry.cursor,
          recordHistory: retry.recordHistory,
        ),
      );
    } else if (_cursor != null) {
      footer = TextButton(
        key: const ValueKey('post-search-more'),
        onPressed: () => _loadResults(cursor: _cursor),
        child: Text(hhText(context, '加载更多')),
      );
    } else {
      footer = null;
    }

    if (results.isEmpty && footer == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(hhText(context, '暂无相关帖子')),
            if (_channelId != null)
              TextButton(
                key: const ValueKey('post-search-all'),
                onPressed: () => _selectScope(null),
                child: Text(hhText(context, '搜索全部分类')),
              ),
          ],
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('post-search-results'),
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length + (footer == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (index == results.length) return footer!;
        final post = results[index];
        final groupStart =
            _channelId == null &&
            (index == 0 || results[index - 1].channelId != post.channelId);
        final published = post.publishedAt.toLocal();
        return Column(
          key: ValueKey('post-search-result:${post.postId}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (groupStart)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Semantics(
                  header: true,
                  child: Text(
                    hhText(context, _channels[post.channelId]!),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
            ListTile(
              leading: DetailAvatar(
                name: post.author.displayName,
                avatar: post.author.avatar,
                radius: 18,
              ),
              title: Text(
                post.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${post.author.displayName} · ${MaterialLocalizations.of(context).formatShortMonthDay(published)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                if (_current &&
                    !_controller.isPostDeleted(post.postId) &&
                    !_controller.blockedChannelIds.contains(post.channelId)) {
                  _focus.unfocus();
                  widget.onOpenPost(context, post);
                }
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        );
      },
    );
  }

  Widget _buildHistory() {
    if (_historyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_historyError) {
      return Center(child: _retryNotice('暂时无法核对搜索历史', _readHistory));
    }
    if (_history.isEmpty) return Center(child: Text(hhText(context, '暂无搜索历史')));
    return ListView(
      key: const ValueKey('post-search-history'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                hhText(context, '搜索历史'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton(
              key: const ValueKey('post-search-history-clear'),
              onPressed: _historyChanging ? null : () => _changeHistory(),
              child: Text(hhText(context, '清空')),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final style = Theme.of(context).textTheme.labelLarge;
            final widths = <double>[];
            const gap = 8.0;
            var row = 1;
            var used = 0.0;
            var collapsedCount = 0;
            for (final entry in _history) {
              final painter = TextPainter(
                text: TextSpan(text: entry, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              final width = (painter.width.ceilToDouble() + 64).clamp(
                0.0,
                constraints.maxWidth,
              );
              painter.dispose();
              widths.add(width);
              if (used + width > constraints.maxWidth) {
                ++row;
                used = 0;
              }
              if (row <= 2) ++collapsedCount;
              used += width + gap;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: gap,
                  runSpacing: 4,
                  children: [
                    for (
                      var i = 0;
                      i < (_historyExpanded ? _history.length : collapsedCount);
                      ++i
                    )
                      SizedBox(
                        width: widths[i],
                        child: InputChip(
                          label: Text(
                            _history[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          labelStyle: style,
                          onPressed: _historyChanging
                              ? null
                              : () => _submit(_history[i]),
                          onDeleted: _historyChanging
                              ? null
                              : () =>
                                    _changeHistory(removeKeyword: _history[i]),
                          deleteButtonTooltipMessage: hhText(
                            context,
                            '删除「{keyword}」',
                            args: {'keyword': _history[i]},
                          ),
                        ),
                      ),
                  ],
                ),
                if (collapsedCount < _history.length)
                  TextButton(
                    key: const ValueKey('post-search-history-expand'),
                    onPressed: () =>
                        setState(() => _historyExpanded = !_historyExpanded),
                    child: Text(
                      hhText(context, _historyExpanded ? '收起' : '展开'),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _retryNotice(String message, VoidCallback onRetry) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: 16),
      Text(hhText(context, message)),
      TextButton(onPressed: onRetry, child: Text(hhText(context, '重试'))),
    ],
  );
}
