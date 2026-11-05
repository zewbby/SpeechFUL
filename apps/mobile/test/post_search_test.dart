import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/posts/post_search_api.dart';
import 'package:hnuhole_mobile/src/posts/post_ranking_api.dart';
import 'package:hnuhole_mobile/src/posts/post_search_screen.dart';

import 'feed_ui_test.dart' as feed;
import 'identity_test_support.dart';

typedef _Query = ({
  String keyword,
  String? scope,
  PostSearchSort sort,
  String? cursor,
  bool record,
});

class _SearchApi extends feed.FeedTestApi implements PostSearchApi {
  final queries = <_Query>[];
  final historyReads = <String?>[];
  final historyChanges = <(String?, String?)>[];
  final histories = <String?, List<String>>{};
  FutureOr<PostsPage<PostCard>> Function(_Query)? resultFor;
  Future<List<String>>? historyWait;
  Future<void>? historyChangeWait;
  bool historyFails = false;
  int historyWrites = 0;

  @override
  Future<PostResponse<PostsPage<PostCard>>> searchPosts({
    required String sessionToken,
    required String keyword,
    String? channelId,
    PostSearchSort sort = PostSearchSort.relevance,
    String? cursor,
    int limit = 20,
    bool recordHistory = false,
  }) async {
    final query = (
      keyword: keyword,
      scope: channelId,
      sort: sort,
      cursor: cursor,
      record: recordHistory,
    );
    queries.add(query);
    final result =
        await (resultFor?.call(query) ??
            PostsPage<PostCard>(items: [], nextCursor: null));
    if (recordHistory) {
      historyWrites++;
      histories[channelId] = [
        keyword,
        for (final entry in histories[channelId] ?? [])
          if (entry.toLowerCase() != keyword.toLowerCase()) entry,
      ];
    }
    return feed.reply(result);
  }

  @override
  Future<PostResponse<List<String>>> postSearchHistory({
    required String sessionToken,
    String? channelId,
  }) async {
    historyReads.add(channelId);
    if (historyFails) {
      throw const PostFailure(kind: PostFailureKind.transport);
    }
    return feed.reply(
      await (historyWait ?? Future.value(histories[channelId] ?? [])),
    );
  }

  @override
  Future<PostResponse<List<String>>> changePostSearchHistory({
    required String sessionToken,
    String? channelId,
    String? removeKeyword,
  }) async {
    historyChanges.add((channelId, removeKeyword));
    await historyChangeWait;
    final entries = <String>[
      if (removeKeyword != null)
        for (final entry in histories[channelId] ?? [])
          if (entry != removeKeyword) entry,
    ];
    histories[channelId] = entries;
    return feed.reply(entries);
  }
}

const _input = ValueKey('post-search-input');
const _scope = ValueKey('post-search-scope');
const _latest = ValueKey('post-search-sort:latest');
const _all = ValueKey('post-search-all');
const _more = ValueKey('post-search-more');
const _results = ValueKey('post-search-results');
const _feed = ValueKey('production-feed');

String _id(int index) =>
    '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}';

Future<feed.FeedFixture> _start(
  WidgetTester tester,
  _SearchApi api, {
  AuthPresentationController? presentation,
  Size size = const Size(390, 760),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final fixture = feed.FeedFixture(await IdentityTestFixture.create(), api);
  addTearDown(fixture.dispose);
  final screen = feed.screen(fixture);
  await tester.pumpWidget(
    presentation == null
        ? screen
        : AuthPresentationScope(controller: presentation, child: screen),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('feed-search')));
  await tester.pumpAndSettle();
  expect(find.byType(PostSearchScreen), findsOneWidget);
  expect(
    tester.widget<TextField>(find.byKey(_input)).focusNode!.hasFocus,
    isTrue,
  );
}

Future<void> _submit(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(_input), text);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton).first);
  await tester.pumpAndSettle();
}

class _RankingApi extends _SearchApi implements PostRankingApi {
  final reads = <String>[];
  late Future<PostRanking> Function(String) rankingFor;
  List<String> order = feed.channels.reversed.map((c) => c.id).toList();

  @override
  Future<PostResponse<List<String>>> channelOrder({
    required String sessionToken,
  }) async => feed.reply(order);

  @override
  Future<PostResponse<PostRanking>> hotPosts({
    required String sessionToken,
    required String channelId,
  }) async {
    reads.add(channelId);
    return feed.reply(await rankingFor(channelId));
  }
}

Future<void> _pickChannel(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(const ValueKey('feed-channel-picker')));
  await tester.pumpAndSettle();
  final choice = find.byKey(ValueKey('choose-channel:$id'));
  await tester.scrollUntilVisible(
    choice,
    180,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('channel-options')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'channel ranking keeps recommended first; hot posts load alongside history',
    (tester) async {
      final channel = feed.channels.last;
      final wait = Completer<PostRanking>();
      final api = _RankingApi()..rankingFor = (_) => wait.future;
      api.histories[channel.id] = ['我搜过的关键词'];
      await _start(tester, api);
      await tester.tap(find.byKey(const ValueKey('feed-channel-picker')));
      await tester.pumpAndSettle();
      final recommended = find.byKey(
        const ValueKey('choose-channel:recommended'),
      );
      final hottest = find.byKey(ValueKey('choose-channel:${channel.id}'));
      final next = find.byKey(
        ValueKey('choose-channel:${feed.channels[5].id}'),
      );
      expect(
        tester.getTopLeft(recommended).dy,
        lessThan(tester.getTopLeft(hottest).dy),
      );
      expect(
        tester.getTopLeft(hottest).dy,
        lessThan(tester.getTopLeft(next).dy),
      );
      await tester.tap(hottest);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feed-search')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('我搜过的关键词'), findsOneWidget);
      expect(find.text('大家都在看'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(_input)).focusNode!.hasFocus,
        isTrue,
      );
      wait.complete(PostRanking(channel.id, [RankedPost(_id(1), '热门帖子', 42)]));
      await tester.pumpAndSettle();
      expect(find.text('热门帖子'), findsOneWidget);
      expect(find.text('浏览量 42'), findsOneWidget);
      for (final section in [
        find.byKey(const ValueKey('post-search-hot-posts')),
        find.byKey(ValueKey('post-search-hot:${_id(1)}')),
      ]) {
        expect(
          find.descendant(of: section, matching: find.byType(Icon)),
          findsNothing,
        );
        expect(
          find.descendant(of: section, matching: find.byType(Image)),
          findsNothing,
        );
        expect(
          find.descendant(of: section, matching: find.byType(RawImage)),
          findsNothing,
        );
      }
    },
  );

  testWidgets('a late hot list cannot replace search results', (tester) async {
    final first = feed.channels.last;
    final wait = Completer<PostRanking>();
    final api = _RankingApi()..rankingFor = (_) => wait.future;
    api.resultFor = (_) =>
        PostsPage(items: [feed.post(title: '即时搜索结果')], nextCursor: null);
    await _start(tester, api);
    await _pickChannel(tester, first.id);
    await tester.tap(find.byKey(const ValueKey('feed-search')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(_input), '关键词');
    await tester.pump(const Duration(milliseconds: 350));
    wait.complete(PostRanking(first.id, [RankedPost(_id(2), '迟到热榜', 6)]));
    await tester.pumpAndSettle();
    expect(find.text('即时搜索结果'), findsOneWidget);
    expect(find.text('迟到热榜'), findsNothing);
    expect(find.byKey(const ValueKey('post-search-hot-posts')), findsNothing);
  });

  testWidgets(
    'blocking the current category removes an already visible hot list',
    (tester) async {
      final channel = feed.channels.last;
      final api = _RankingApi()
        ..rankingFor = (scope) async =>
            PostRanking(scope, [RankedPost(_id(8), '当前可见的榜单', 8)]);
      final fixture = await _start(tester, api);
      await _pickChannel(tester, channel.id);
      await _open(tester);
      expect(find.text('当前可见的榜单'), findsOneWidget);
      await fixture.controller.saveBlockedChannels({channel.id});
      await tester.pumpAndSettle();
      expect(find.text('当前可见的榜单'), findsNothing);
      expect(find.byKey(const ValueKey('post-search-hot-posts')), findsNothing);
      expect(find.text('暂无搜索历史'), findsOneWidget);
    },
  );

  testWidgets(
    'an unavailable optional ranking keeps search and the session usable',
    (tester) async {
      final channel = feed.channels.last;
      final api = _RankingApi()
        ..rankingFor = (_) async => throw const PostFailure(
          kind: PostFailureKind.unavailable,
          code: 'RANKINGS_UNAVAILABLE',
          statusCode: 503,
        );
      api.resultFor = (_) =>
          PostsPage(items: [feed.post(title: '搜索继续可用')], nextCursor: null);
      final fixture = await _start(tester, api);
      await _pickChannel(tester, channel.id);
      await _open(tester);
      expect(find.text('暂时无法加载热榜'), findsOneWidget);
      expect(fixture.controller.available, isTrue);
      await tester.enterText(find.byKey(_input), '关键词');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('搜索继续可用'), findsOneWidget);
      expect(find.text('登录或核对会话'), findsNothing);
    },
  );

  testWidgets(
    'returning from a hot post refreshes and keeps the old list on failure',
    (tester) async {
      final channel = feed.channels.last;
      final api = _RankingApi();
      api.rankingFor = (scope) async {
        if (api.reads.length == 2) {
          throw const PostFailure(kind: PostFailureKind.transport);
        }
        return PostRanking(scope, [RankedPost(_id(3), '可继续浏览的榜单', 23)]);
      };
      await _start(tester, api);
      await _pickChannel(tester, channel.id);
      await _open(tester);
      await tester.tap(find.text('可继续浏览的榜单'));
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailScreen), findsOneWidget);
      await _back(tester);
      expect(api.reads, [channel.id, channel.id]);
      expect(find.text('热榜刷新失败，请重试'), findsOneWidget);
      expect(find.text('可继续浏览的榜单'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(api.reads, [channel.id, channel.id, channel.id]);
      expect(find.text('热榜刷新失败，请重试'), findsNothing);
    },
  );

  testWidgets('late hot posts are isolated when changing category', (
    tester,
  ) async {
    final first = feed.channels.last;
    final second = feed.channels[5];
    final wait = Completer<PostRanking>();
    final api = _RankingApi();
    api.rankingFor = (scope) => scope == first.id
        ? wait.future
        : Future.value(PostRanking(scope, [RankedPost(_id(5), '新分类的热榜', 7)]));
    await _start(tester, api);
    await _pickChannel(tester, first.id);
    await tester.tap(find.byKey(const ValueKey('feed-search')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(_scope));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text(second.name).last);
    await tester.pumpAndSettle();
    expect(find.text('新分类的热榜'), findsOneWidget);
    wait.complete(PostRanking(first.id, [RankedPost(_id(4), '旧分类的迟到热榜', 8)]));
    await tester.pumpAndSettle();
    expect(find.text('新分类的热榜'), findsOneWidget);
    expect(find.text('旧分类的迟到热榜'), findsNothing);
  });

  testWidgets('hot posts fit a narrow screen with large text and long counts', (
    tester,
  ) async {
    final api = _RankingApi();
    api.rankingFor = (scope) async => PostRanking(scope, [
      RankedPost(_id(6), '一篇包含很长标题的帖子需要在小屏幕大字号下正常换行展示', 9007199254740991),
    ]);
    final fixture = feed.FeedFixture(await IdentityTestFixture.create(), api);
    addTearDown(fixture.dispose);
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: HhTelegramTheme.create(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: PostSearchScreen(
          controller: fixture.controller,
          channels: feed.channels,
          initialChannelId: feed.channels.last.id,
          onOpenPost: (_, _) {},
          onOpenRankedPost: (_, _, _) async {},
          onAuthenticationRequired: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('post-search-hot:${_id(6)}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search follows dark appearance and reduced motion', (
    tester,
  ) async {
    final channel = feed.channels.last;
    final api = _RankingApi()
      ..rankingFor = (scope) async =>
          PostRanking(scope, [RankedPost(_id(7), '深色榜单', 10)]);
    api.histories[channel.id] = ['一条足够长的历史关键词', '另一条足够长的历史关键词', '第三条足够长的关键词'];
    final fixture = await _start(tester, api);
    await tester.pumpWidget(
      MaterialApp(
        theme: HhTelegramTheme.create(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: PostSearchScreen(
          controller: fixture.controller,
          channels: feed.channels,
          initialChannelId: channel.id,
          onOpenPost: (_, _) {},
          onOpenRankedPost: (_, _, _) async {},
          onAuthenticationRequired: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final search = find.byType(PostSearchScreen);
    final focusDecoration = tester.widget<AnimatedContainer>(
      find.descendant(of: search, matching: find.byType(AnimatedContainer)),
    );
    expect(focusDecoration.duration, Duration.zero);
    final reveal = tester.widget<TweenAnimationBuilder<double>>(
      find.byKey(ValueKey('post-search-hot:${_id(7)}')),
    );
    expect(reveal.duration, Duration.zero);
    expect(
      Theme.of(tester.element(find.byKey(_input))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.byKey(const ValueKey('post-search-history-expand')));
    await tester.pumpAndSettle();
    expect(find.text('第三条足够长的关键词'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing searches after a pause without submitting or recording', (
    tester,
  ) async {
    final api = _SearchApi()
      ..resultFor = (_) =>
          PostsPage(items: [feed.post(title: '自习室开放时间')], nextCursor: null);
    await _start(tester, api);
    await _open(tester);

    await tester.enterText(find.byKey(_input), '自');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byKey(_input), ' 自习 ');
    await tester.pump(const Duration(milliseconds: 349));
    expect(api.queries, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(api.queries.single.keyword, '自习');
    expect(api.queries.single.record, isFalse);
    expect(api.historyWrites, 0);
    expect(find.text('自习室开放时间'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(_input)).focusNode!.hasFocus,
      isTrue,
    );

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(api.queries.map((query) => query.record), [false, true]);
    expect(api.histories[null], ['自习']);
  });

  testWidgets(
    'editing retires slow results and clearing cancels pending search',
    (tester) async {
      final slow = Completer<PostsPage<PostCard>>();
      final api = _SearchApi()
        ..histories[null] = ['此前搜索']
        ..resultFor = (query) => query.keyword == '旧词'
            ? slow.future
            : PostsPage(items: [feed.post(title: '新词命中')], nextCursor: null);
      await _start(tester, api);
      await _open(tester);

      await tester.enterText(find.byKey(_input), '旧词');
      await tester.pump(const Duration(milliseconds: 350));
      expect(api.queries.single.keyword, '旧词');

      await tester.enterText(find.byKey(_input), '新词');
      slow.complete(
        PostsPage(items: [feed.post(title: '旧词命中')], nextCursor: null),
      );
      await tester.pump();
      expect(find.text('旧词命中'), findsNothing);
      expect(api.queries, hasLength(1));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('新词命中'), findsOneWidget);

      await tester.enterText(find.byKey(_input), '第三个词');
      await tester.pump();
      await tester.tap(find.byTooltip('清空关键词'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(api.queries.map((query) => query.keyword), ['旧词', '新词']);
      expect(find.text('此前搜索'), findsOneWidget);
      expect(find.text('新词命中'), findsNothing);
      expect(api.historyWrites, 0);
    },
  );

  testWidgets(
    'search labels follow the app language and keep keywords verbatim',
    (tester) async {
      final presentation = AuthPresentationController();
      addTearDown(presentation.dispose);
      presentation.setLanguage(AppLanguage.english);
      await _start(
        tester,
        _SearchApi(),
        presentation: presentation,
        size: const Size(760, 760),
      );
      expect(find.byTooltip('Search posts'), findsOneWidget);
      await _open(tester);
      expect(find.text('All categories'), findsOneWidget);
      expect(find.text('No search history'), findsOneWidget);

      await _submit(tester, '自习');
      await tester.pumpAndSettle();
      expect(find.text('No matching posts'), findsOneWidget);
      presentation.setLanguage(AppLanguage.japanese);
      await tester.pumpAndSettle();
      expect(find.text('一致する投稿がありません'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(_input)).controller!.text,
        '自习',
      );
    },
  );

  testWidgets('explicit submission records history during scope refresh', (
    tester,
  ) async {
    final refresh = Completer<PostsPage<PostCard>>();
    final submit = Completer<PostsPage<PostCard>>();
    final api = _SearchApi();
    api.resultFor = (query) {
      if (query.scope == null) return PostsPage(items: [], nextCursor: null);
      return query.record ? submit.future : refresh.future;
    };
    await _start(tester, api);
    await _open(tester);
    await _submit(tester, '自习');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_scope));
    await tester.pumpAndSettle();
    await tester.tap(find.text('避雷'));
    await tester.pump();
    await tester.tap(find.byTooltip('提交搜索'));
    await tester.pump();
    expect(api.queries, hasLength(3));
    expect(api.queries[1].record, isFalse);
    expect(api.queries[2].record, isTrue);
    expect(api.queries[2].scope, feed.otherChannelId);

    submit.complete(
      PostsPage(
        items: [
          feed.post(id: _id(1), title: '提交结果', channel: feed.otherChannelId),
        ],
        nextCursor: null,
      ),
    );
    await tester.pumpAndSettle();
    refresh.complete(PostsPage(items: [], nextCursor: null));
    await tester.pumpAndSettle();
    expect(find.text('提交结果'), findsOneWidget);
    expect(api.histories[feed.otherChannelId], ['自习']);
    expect(api.historyWrites, 2);
  });

  testWidgets(
    'coalesces button and keyboard submissions while search is pending',
    (tester) async {
      final pending = Completer<PostsPage<PostCard>>();
      final api = _SearchApi()..resultFor = (_) => pending.future;
      await _start(tester, api);
      await _open(tester);
      await tester.enterText(find.byKey(_input), '自习');
      await tester.tap(find.byTooltip('提交搜索'));
      await tester.pump();
      await tester.tap(find.byKey(_input));
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.tap(find.byTooltip('提交搜索'));
      await tester.pump();
      expect(api.queries, hasLength(1));

      pending.complete(
        PostsPage(
          items: [feed.post(id: _id(1), title: '首个响应')],
          nextCursor: null,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('首个响应'), findsOneWidget);
      expect(api.historyWrites, 1);
      expect(api.histories[null], ['自习']);
    },
  );

  testWidgets(
    'recommended opens all categories and a category presets only search',
    (tester) async {
      final api = _SearchApi();
      api.items = [
        for (var i = 0; i < 16; ++i)
          feed.post(id: _id(i), title: '通道帖子 ${i + 1}'),
      ];
      final fixture = await _start(tester, api);
      await _open(tester);
      expect(find.text('全部分类'), findsOneWidget);
      expect(api.historyReads, [null]);
      await _back(tester);

      await tester.tap(find.byKey(const ValueKey('feed-channel-picker')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('choose-channel:${feed.channelId}')),
      );
      await tester.pumpAndSettle();
      final feedScroll = tester.widget<ListView>(find.byKey(_feed)).controller!;
      feedScroll.jumpTo(300);
      await tester.pumpAndSettle();
      final offset = feedScroll.offset;
      final timelineCalls = api.calls
          .where((call) => call.startsWith('feed:'))
          .length;
      await _open(tester);
      expect(find.text('吐槽'), findsOneWidget);
      expect(api.historyReads, [null, feed.channelId]);

      await _submit(tester, ' 自习 ');
      await tester.pumpAndSettle();
      expect(find.text('暂无相关帖子'), findsOneWidget);
      expect(api.queries.single, (
        keyword: '自习',
        scope: feed.channelId,
        sort: PostSearchSort.relevance,
        cursor: null,
        record: true,
      ));
      await tester.tap(find.byKey(_latest));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_all));
      await tester.pumpAndSettle();
      expect(find.text('全部分类'), findsOneWidget);
      expect(find.byKey(_all), findsNothing);
      expect(tester.widget<ChoiceChip>(find.byKey(_latest)).selected, isTrue);
      expect(api.queries.last, (
        keyword: '自习',
        scope: null,
        sort: PostSearchSort.latest,
        cursor: null,
        record: false,
      ));

      await _back(tester);
      expect(fixture.controller.timelineChannelId, feed.channelId);
      expect(feedScroll.offset, offset);
      expect(
        api.calls.where((call) => call.startsWith('feed:')),
        hasLength(timelineCalls),
      );
      await _open(tester);
      expect(tester.widget<TextField>(find.byKey(_input)).controller!.text, '');
      expect(find.text('自习'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'grouped results append, retry, and keep offset on real detail return',
    (tester) async {
      final api = _SearchApi();
      final hits = [
        for (var i = 1; i < 12; ++i)
          feed.post(id: _id(i), title: '自习地点 ${i + 1}'),
        feed.post(id: _id(12), title: '另一分类地点', channel: feed.otherChannelId),
      ];
      api.items = hits;
      var failMore = true;
      api.resultFor = (query) {
        if (query.cursor == null) {
          return PostsPage(items: hits.take(7).toList(), nextCursor: 'next');
        }
        if (failMore) {
          failMore = false;
          throw const PostFailure(kind: PostFailureKind.transport);
        }
        return PostsPage(items: hits.skip(7).toList(), nextCursor: null);
      };
      await _start(tester, api);
      await _open(tester);
      await tester.enterText(find.byKey(_input), '自习');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('吐槽'), findsOneWidget);
      final list = find.byKey(_results);
      final scroll = tester.widget<ListView>(list).controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_more));
      await tester.pumpAndSettle();
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('暂时无法搜索帖子'), findsOneWidget);
      expect(find.text('自习地点 8'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(api.queries.map((query) => query.cursor), [null, 'next', 'next']);
      expect(api.queries.map((query) => query.record), [false, false, false]);

      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('避雷'), findsOneWidget);
      final offset = scroll.offset;
      await tester.tap(find.text('另一分类地点'));
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailScreen), findsOneWidget);
      expect(api.calls, contains('detail:${_id(12)}'));
      await _back(tester);
      expect(scroll.offset, offset);
      expect(find.text('另一分类地点'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(_input)).controller!.text,
        '自习',
      );
      expect(
        tester.widget<TextField>(find.byKey(_input)).focusNode!.hasFocus,
        isFalse,
      );
      expect(api.queries, hasLength(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expired continuation reloads first page without recording history again',
    (tester) async {
      final api = _SearchApi();
      api.resultFor = (query) {
        if (query.cursor != null) {
          throw const PostFailure(
            kind: PostFailureKind.rejected,
            code: 'CURSOR_INVALID',
          );
        }
        final initial = query.record;
        return PostsPage(
          items: [feed.post(title: initial ? '原页' : '已刷新')],
          nextCursor: initial ? 'next' : null,
        );
      };
      await _start(tester, api);
      await _open(tester);
      await _submit(tester, '自习');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_more));
      await tester.pumpAndSettle();
      expect(find.text('已刷新'), findsOneWidget);
      expect(find.text('原页'), findsNothing);
      expect(api.queries.map((query) => query.cursor), [null, 'next', null]);
      expect(api.queries.map((query) => query.record), [true, false, false]);
    },
  );

  testWidgets(
    'history retries, expands two rows, reuses, deletes, and confirms scope clear',
    (tester) async {
      final api = _SearchApi();
      final terms = [for (var i = 1; i <= 4; ++i) '一个很长的历史关键词供测试重复输入和展开 $i号'];
      api.histories[null] = terms;
      api.histories[feed.otherChannelId] = ['避雷历史'];
      api.historyFails = true;
      await _start(tester, api);
      await _open(tester);
      expect(find.text('暂时无法核对搜索历史'), findsOneWidget);
      api.historyFails = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.text(terms[2]), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('post-search-history-expand')),
      );
      await tester.pumpAndSettle();
      expect(find.text(terms[2]), findsOneWidget);
      await tester.tap(find.text(terms[2]));
      await tester.pumpAndSettle();
      expect(api.queries.single.keyword, terms[2]);
      expect(api.queries.single.record, isTrue);
      await tester.tap(find.byTooltip('清空关键词'));
      await tester.pumpAndSettle();
      final first = tester.widget<InputChip>(find.byType(InputChip).first);
      expect((first.label as Text).data, terms[2]);
      await tester.tap(find.byTooltip('删除「${terms[2]}」'));
      await tester.pumpAndSettle();
      expect(api.historyChanges, [(null, terms[2])]);
      expect(api.queries, hasLength(1));
      expect(find.text(terms[2]), findsNothing);
      await tester.tap(find.byKey(const ValueKey('post-search-history-clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(api.historyChanges, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('post-search-history-clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-search-confirm-clear')));
      await tester.pumpAndSettle();
      expect(api.historyChanges, [(null, terms[2]), (null, null)]);
      expect(find.text('暂无搜索历史'), findsOneWidget);

      await tester.tap(find.byKey(_scope));
      await tester.pumpAndSettle();
      await tester.tap(find.text('避雷'));
      await tester.pumpAndSettle();
      expect(api.historyReads.last, feed.otherChannelId);
      expect(find.text('避雷历史'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clearing input waits for recorded searches in this scope and fences scope changes',
    (tester) async {
      final api = _SearchApi();
      final first = Completer<PostsPage<PostCard>>();
      final second = Completer<PostsPage<PostCard>>();
      final beforeSwitch = Completer<PostsPage<PostCard>>();
      api.histories[null] = ['全部旧词'];
      api.histories[feed.otherChannelId] = ['避雷词'];
      api.resultFor = (query) => switch (query.keyword) {
        '第一个词' => first.future,
        '第二个词' => second.future,
        _ => beforeSwitch.future,
      };
      await _start(tester, api);
      await _open(tester);

      await _submit(tester, '第一个词');
      await tester.tap(find.byTooltip('清空关键词'));
      await tester.pump();
      expect(api.historyReads, [null]);
      expect(find.text('全部旧词'), findsNothing);

      await _submit(tester, '第二个词');
      await tester.tap(find.byTooltip('清空关键词'));
      await tester.pump();
      first.complete(PostsPage(items: [], nextCursor: null));
      await tester.pump();
      expect(api.historyReads, [null]);
      expect(find.text('第一个词'), findsNothing);

      second.completeError(const PostFailure(kind: PostFailureKind.transport));
      await tester.pumpAndSettle();
      expect(api.historyReads, [null, null]);
      expect(find.text('第一个词'), findsOneWidget);
      expect(find.text('第二个词'), findsNothing);

      await _submit(tester, '切换前输入');
      await tester.tap(find.byTooltip('清空关键词'));
      await tester.pump();
      await tester.tap(find.byKey(_scope));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('避雷'));
      await tester.pumpAndSettle();
      expect(find.text('避雷词'), findsOneWidget);

      beforeSwitch.complete(PostsPage(items: [], nextCursor: null));
      await tester.pumpAndSettle();
      expect(api.historyReads, [null, null, feed.otherChannelId]);
      expect(find.text('避雷词'), findsOneWidget);
      expect(find.text('切换前输入'), findsNothing);
    },
  );

  testWidgets('history read after clearing waits for an overlapping removal', (
    tester,
  ) async {
    final api = _SearchApi();
    final removal = Completer<void>();
    api.histories[null] = ['待删词'];
    api.historyChangeWait = removal.future;
    await _start(tester, api);
    await _open(tester);

    await tester.tap(find.byTooltip('删除「待删词」'));
    await tester.pump();
    expect(api.historyChanges, [(null, '待删词')]);
    await _submit(tester, '新词');
    await tester.tap(find.byTooltip('清空关键词'));
    await tester.pump();
    expect(api.historyReads, [null]);
    expect(find.text('待删词'), findsNothing);

    removal.complete();
    await tester.pumpAndSettle();
    expect(api.historyReads, [null, null]);
    expect(find.text('待删词'), findsNothing);
    expect(find.text('新词'), findsOneWidget);
    await tester.tap(find.byKey(_scope));
    await tester.pumpAndSettle();
    expect(find.text('避雷'), findsOneWidget);
  });

  testWidgets('late history and search cannot appear after session loss', (
    tester,
  ) async {
    final api = _SearchApi();
    final pendingHistory = Completer<List<String>>();
    final pendingResult = Completer<PostsPage<PostCard>>();
    api.historyWait = pendingHistory.future;
    api.resultFor = (_) => pendingResult.future;
    final fixture = await _start(tester, api);
    await tester.tap(find.byKey(const ValueKey('feed-search')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await _submit(tester, '私密搜索词');
    expect(api.queries, hasLength(1));
    await fixture.auth.sessions.logout();
    pendingHistory.complete(['私密历史']);
    pendingResult.complete(
      PostsPage(items: [feed.post(title: '私密结果')], nextCursor: null),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录或核对会话'), findsOneWidget);
    expect(find.byKey(_input), findsNothing);
    expect(find.text('私密搜索词'), findsNothing);
    expect(find.text('私密历史'), findsNothing);
    expect(find.text('私密结果'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
