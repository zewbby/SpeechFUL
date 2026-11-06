import 'dart:async';

import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../design_system/detail_components.dart';
import '../design_system/telegram_theme.dart';
import '../localization/app_localizations.dart';
import 'post_api.dart';
import 'post_controller.dart';
import 'post_models.dart';
import 'post_ranking_api.dart';
import 'post_search_api.dart';

class PostSearchScreen extends StatefulWidget {
  const PostSearchScreen({
    super.key,
    required this.controller,
    required this.channels,
    required this.initialChannelId,
    required this.onOpenPost,
    required this.onAuthenticationRequired,
    this.onOpenRankedPost,
  });

  final PostController controller;
  final List<Channel> channels;
  final String? initialChannelId;
  final void Function(BuildContext context, PostCard post) onOpenPost;
  final Future<void> Function(
    BuildContext context,
    String postId,
    String channelId,
  )?
  onOpenRankedPost;
  final VoidCallback onAuthenticationRequired;

  @override
  State<PostSearchScreen> createState() => _PostSearchScreenState();
}

class _PostSearchScreenState extends State<PostSearchScreen> {
  static const _typingDelay = Duration(milliseconds: 350);

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _discoveryScroll = ScrollController();
  final _historyWrites = <String?, Set<Future<void>>>{};
  late final int _epoch;
  late final Map<String, String> _channels = {
    for (final channel in widget.channels) channel.id: channel.name,
  };
  late String? _channelId = widget.initialChannelId;
  PostSearchSort _sort = PostSearchSort.relevance;
  Timer? _searchTimer;
  String? _keyword, _cursor;
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
  bool _inputInvalid = false;
  int _rankingRequest = 0;
  bool _rankingLoading = false, _rankingError = false;
  bool _rankedPostOpen = false;
  PostRanking? _ranking;

  PostController get _controller => widget.controller;
  bool get _current =>
      mounted &&
      _controller.available &&
      _controller.authorityVersion == _epoch;
  String get _scopeName => hhText(context, _channels[_channelId] ?? '全部分类');
  bool get _hasRanking =>
      _controller.supportsPostRankings && widget.onOpenRankedPost != null;
  bool get _discovering =>
      _keyword == null && trimPostSearchKeyword(_input.text).isEmpty;

  @override
  void initState() {
    super.initState();
    // Capture the authority before this route can dispatch any requests.
    _epoch = _controller.authorityVersion;
    _controller.addListener(_authorityChanged);
    if (_current) scheduleMicrotask(_loadDiscovery);
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _controller.removeListener(_authorityChanged);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    _discoveryScroll.dispose();
    super.dispose();
  }

  void _authorityChanged() {
    if (!_current && !_retired) {
      _retired = true;
      _focus.unfocus();
      _input.clear();
      _resetResults();
      _history = const [];
      _clearRanking();
    }
    setState(() {});
  }

  void _resetResults() {
    _searchTimer?.cancel();
    ++_searchRequest;
    _inFlight = null;
    _keyword = _cursor = null;
    _posts = const [];
    _retry = null;
    _searchLoading = false;
  }

  void _edit(String value) {
    if (!_current) return;
    final empty = trimPostSearchKeyword(value).isEmpty;
    String? keyword;
    if (!empty) {
      try {
        keyword = normalizePostSearchKeyword(value);
      } on FormatException {
        // Show the field error and wait for valid input.
      }
    }
    setState(() {
      _inputInvalid = !empty && keyword == null;
      if (!empty && (_rankingLoading || _ranking != null || _rankingError)) {
        _clearRanking();
      }
      if (_keyword == keyword) return;
      _resetResults();
      if (keyword != null) {
        _keyword = keyword;
        _searchLoading = true;
        _searchTimer = Timer(_typingDelay, () => unawaited(_loadResults()));
      }
    });
    if (empty) _loadDiscovery();
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
      setState(() => _inputInvalid = true);
      return;
    }
    _focus.unfocus();
    setState(() {
      _input.value = TextEditingValue(
        text: keyword,
        selection: TextSelection.collapsed(offset: keyword.length),
      );
      _inputInvalid = false;
      _keyword = keyword;
      _clearRanking();
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
    if (_keyword != null) {
      unawaited(_loadResults());
    } else if (trimPostSearchKeyword(_input.text).isEmpty) {
      _loadDiscovery();
    }
  }

  void _clearRanking() {
    ++_rankingRequest;
    _ranking = null;
    _rankingLoading = _rankingError = false;
  }

  void _loadDiscovery() {
    if (_discoveryScroll.hasClients) _discoveryScroll.jumpTo(0);
    unawaited(_readHistory());
    if (_ranking == null) unawaited(_readRanking());
  }

  Future<void> _readRanking() async {
    if (!_current || !_hasRanking || !_discovering || _rankingLoading) return;
    final request = ++_rankingRequest;
    setState(() {
      _rankingLoading = true;
      _rankingError = false;
    });
    bool current() => _current && request == _rankingRequest;
    try {
      final value = await _controller.hotPosts();
      if (current()) setState(() => _ranking = value);
    } on Object {
      if (current()) setState(() => _rankingError = true);
    } finally {
      if (current()) setState(() => _rankingLoading = false);
    }
  }

  Future<void> _openRankedPost(RankedPost post) async {
    if (!_current ||
        !_hasRanking ||
        _rankedPostOpen ||
        _controller.blockedChannelIds.contains(post.channelId) ||
        _controller.isPostDeleted(post.postId)) {
      return;
    }
    _rankedPostOpen = true;
    try {
      _focus.unfocus();
      await widget.onOpenRankedPost!(context, post.postId, post.channelId);
    } finally {
      _rankedPostOpen = false;
    }
    if (!_current || !_discovering) return;
    if (_discoveryScroll.hasClients) _discoveryScroll.jumpTo(0);
    if (_rankingLoading) {
      ++_rankingRequest;
      _rankingLoading = false;
    }
    await _readRanking();
  }

  void _selectSort(PostSearchSort sort) {
    if (!_current || sort == _sort || _keyword == null) return;
    setState(() => _sort = sort);
    unawaited(_loadResults());
  }

  Future<void> _loadResults({
    String? cursor,
    bool recordHistory = false,
  }) async {
    final keyword = _keyword;
    if (!_current || keyword == null) return;
    _searchTimer?.cancel();
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
                _buildSearchField(),
                if (!_discovering)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
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
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 44),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: HhTelegramPalette.of(context).selection,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.tag_rounded,
                                  size: 17,
                                  color: HhTelegramPalette.of(context).accent,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _scopeName,
                                    style: TextStyle(
                                      color: HhTelegramPalette.of(context)
                                          .accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 18,
                                  color: HhTelegramPalette.of(context).accent,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_keyword != null)
                          for (final sort in PostSearchSort.values)
                            ChoiceChip(
                              key: ValueKey('post-search-sort:${sort.name}'),
                              showCheckmark: false,
                              side: BorderSide.none,
                              shape: const StadiumBorder(),
                              selectedColor: HhTelegramPalette.of(context)
                                  .selection,
                              backgroundColor: HhTelegramPalette.of(context)
                                  .background,
                              label: Text(
                                hhText(
                                  context,
                                  sort == PostSearchSort.relevance
                                      ? '相关度'
                                      : '最新',
                                ),
                              ),
                              selected: _sort == sort,
                              onSelected: (_) => _selectSort(sort),
                            ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _keyword != null
                      ? _buildResults()
                      : trimPostSearchKeyword(_input.text).isEmpty
                      ? _buildDiscovery()
                      : const SizedBox.shrink(),
                ),
              ],
            ),
    ),
  );

  Duration _motionDuration(int milliseconds) =>
      MediaQuery.disableAnimationsOf(context) ||
          MediaQuery.accessibleNavigationOf(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);

  Widget _buildSearchField() {
    final colors = HhTelegramPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: ListenableBuilder(
        listenable: _focus,
        builder: (context, _) => AnimatedContainer(
          duration: _motionDuration(180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _focus.hasFocus ? colors.selection : colors.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _focus.hasFocus
                  ? colors.accent.withValues(alpha: .4)
                  : colors.line,
            ),
          ),
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
              errorText: _inputInvalid
                  ? hhText(context, '请输入 1–100 个字符的关键词')
                  : null,
              errorMaxLines: 2,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              prefixIcon: IconButton(
                tooltip: hhText(context, '提交搜索'),
                onPressed: () => _submit(_input.text),
                color: colors.accent,
                icon: const Icon(Icons.search_rounded),
              ),
              suffixIcon: _input.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: hhText(context, '清空关键词'),
                      onPressed: _clearInput,
                      icon: const Icon(Icons.cancel_rounded, size: 20),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reveal(Key key, Widget child) => TweenAnimationBuilder<double>(
    key: key,
    tween: Tween(begin: 0, end: 1),
    duration: _motionDuration(220),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) => Opacity(
      opacity: .55 + .45 * value,
      child: Transform.translate(
        offset: Offset(0, 6 * (1 - value)),
        child: child,
      ),
    ),
    child: child,
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
            Icon(
              Icons.manage_search_rounded,
              size: 44,
              color: HhTelegramPalette.of(context).accent,
            ),
            const SizedBox(height: 12),
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              leading: DetailAvatar(
                name: post.author.displayName,
                avatar: post.author.avatar,
                radius: 18,
              ),
              title: Text(
                post.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
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
            const Divider(height: 1, indent: 72, endIndent: 20),
          ],
        );
      },
    );
  }

  Widget _buildDiscovery() {
    final rows = _hasRanking
        ? _ranking?.items
              .where(
                (post) =>
                    !_controller.isPostDeleted(post.postId) &&
                    !_controller.blockedChannelIds.contains(post.channelId) &&
                    _channels.containsKey(post.channelId),
              )
              .toList(growable: false)
        : null;
    final scroll = CustomScrollView(
      key: const ValueKey('post-search-history'),
      controller: _discoveryScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                _buildHistory(),
                if (_hasRanking) _rankingHeader(rows),
              ],
            ),
          ),
        ),
        if (rows != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) => _rankingRow(rows[i], i + 1),
            ),
          ),
      ],
    );
    return _hasRanking
        ? RefreshIndicator(onRefresh: _readRanking, child: scroll)
        : scroll;
  }

  Widget _rankingHeader(List<RankedPost>? rows) => _reveal(
    const ValueKey('post-search-hot-heading:global'),
    SizedBox(
      width: double.infinity,
      child: Column(
        key: const ValueKey('post-search-hot-posts'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 28),
          Semantics(
            header: true,
            child: Text(
              hhText(context, '大家都在看'),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hhText(context, '全站热榜'),
            style: TextStyle(
              fontSize: 12,
              color: HhTelegramPalette.of(context).secondary,
            ),
          ),
          const SizedBox(height: 14),
          if (_rankingLoading && rows == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          if (_rankingError)
            _retryNotice(
              rows == null ? '暂时无法加载热榜' : '热榜刷新失败，请重试',
              _readRanking,
            ),
          if (!_rankingError && rows != null && rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                hhText(context, '近七天暂无可展示帖子'),
                style: TextStyle(
                  color: HhTelegramPalette.of(context).secondary,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _rankingRow(RankedPost post, int rank) {
    final colors = HhTelegramPalette.of(context);
    return _reveal(
      ValueKey('post-search-hot:${post.postId}'),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openRankedPost(post),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.selection,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        color: colors.accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          hhText(
                            context,
                            '浏览量 {count}',
                            args: {'count': '${post.viewCount}'},
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistory() {
    final colors = HhTelegramPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 19, color: colors.secondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hhText(context, '搜索历史'),
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (_history.isNotEmpty)
              TextButton(
                key: const ValueKey('post-search-history-clear'),
                onPressed: _historyChanging ? null : () => _changeHistory(),
                child: Text(hhText(context, '清空')),
              ),
          ],
        ),
        if (_historyLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (_historyError)
          _retryNotice('暂时无法核对搜索历史', _readHistory)
        else if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              hhText(context, '暂无搜索历史'),
              style: TextStyle(color: colors.secondary, fontSize: 13),
            ),
          )
        else
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
              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: gap,
                    runSpacing: 4,
                    children: [
                      for (
                        var i = 0;
                        i <
                            (_historyExpanded
                                ? _history.length
                                : collapsedCount);
                        ++i
                      )
                        SizedBox(
                          width: widths[i],
                          child: InputChip(
                            backgroundColor: colors.background,
                            side: BorderSide.none,
                            shape: const StadiumBorder(),
                            deleteIcon: const Icon(
                              Icons.close_rounded,
                              size: 16,
                            ),
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
                                : () => _changeHistory(
                                    removeKeyword: _history[i],
                                  ),
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
                    TextButton.icon(
                      key: const ValueKey('post-search-history-expand'),
                      onPressed: () =>
                          setState(() => _historyExpanded = !_historyExpanded),
                      icon: AnimatedRotation(
                        turns: _historyExpanded ? .5 : 0,
                        duration: _motionDuration(180),
                        child: const Icon(Icons.expand_more_rounded, size: 18),
                      ),
                      label: Text(
                        hhText(context, _historyExpanded ? '收起' : '展开'),
                      ),
                    ),
                ],
              );
              if (_motionDuration(180) == Duration.zero) return content;
              return AnimatedSize(
                duration: _motionDuration(180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topLeft,
                child: content,
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
