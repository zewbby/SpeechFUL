import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/posts/post_search_api.dart';
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
  bool historyFails = false;

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

Future<feed.FeedFixture> _start(WidgetTester tester, _SearchApi api) async {
  await tester.binding.setSurfaceSize(const Size(390, 760));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final fixture = feed.FeedFixture(await IdentityTestFixture.create(), api);
  addTearDown(fixture.dispose);
  await tester.pumpWidget(feed.screen(fixture));
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

void main() {
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
      await _submit(tester, '自习');
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
      expect(api.queries.map((query) => query.record), [true, false, false]);

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
