import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';
import 'package:hnuhole_mobile/src/messaging/dm_store.dart';
import 'package:hnuhole_mobile/src/messaging/dm_runtime.dart';
import 'package:hnuhole_mobile/src/messaging/dm_post_cards.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';

import 'dm_chat_test.dart' as chat;
import 'dm_reliability_test.dart' as p1;

class CardApi extends chat.ChatApi {
  String title = '当前标题';
  bool removed = false;
  Completer<void>? cardWait;
  CardApi() {
    dir = {...dir, 'canShare': true};
  }
  @override
  Future<PostResponse<Map<String, dynamic>>> dmRequest(
    String token,
    String method,
    String resource, {
    Map<String, Object>? body,
    Map<String, String>? query,
  }) async {
    if (resource.startsWith('chat/posts/')) {
      await cardWait?.future;
      if (offline) throw const PostFailure(kind: PostFailureKind.transport);
      if (removed) {
        throw const PostFailure(
          kind: PostFailureKind.rejected,
          statusCode: 404,
          code: 'POST_NOT_FOUND',
        );
      }
      final value = decodeDm({
        'postId': p1.post,
        'title': title,
        'channelId': p1.peer,
        'channelName': '科技',
      }, resource);
      final now = DateTime.now().toUtc();
      return PostResponse(
        value: value,
        serverTime: now,
        sessionExpiresAt: now.add(const Duration(hours: 1)),
        requestId: 'card-fixture',
        statusCode: 200,
      );
    }
    return super.dmRequest(token, method, resource, body: body, query: query);
  }
}

// Widget evidence uses an explicit presentation double; real encrypted storage
// and command recovery are exercised by the non-widget tests below.
class UiCardController extends DmController {
  UiCardController(this.fixture)
    : super(
        api: fixture,
        chatEnabled: true,
        openStore: (_) => throw StateError('UI double'),
      ) {
    conversations = [fixture.dir];
  }
  final CardApi fixture;
  bool active = true;
  void revoke() {
    active = false;
    notifyListeners();
  }

  @override
  bool get available => active;
  @override
  String get scope => 'ui-account:1';
  @override
  Future<void> sync() async {
    conversations = [fixture.dir];
  }

  @override
  Future<Map<String, dynamic>> postCard(String id) async =>
      (await fixture.dmRequest('token', 'GET', 'chat/posts/$id')).value;
  @override
  Future<String> sharePost(
    Map<String, dynamic> directory,
    String postId,
  ) async {
    await fixture.dmRequest(
      'token',
      'PUT',
      'commands/${dmId()}',
      body: {...chat.textIntent(postId), 'kind': 'POST'},
    );
    return 'sent';
  }
}

void main() {
  late Directory root;
  late p1.Vault vault;
  setUp(() {
    root = Directory.systemTemp.createTempSync('speechful-dm-card-');
    vault = p1.Vault();
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<DmStore> open() => DmStore.open(
    File('${root.path}/chat.sqlite'),
    'post-card-test',
    'account',
    vault,
  );
  Future<DmController> bind(CardApi api) async {
    final c = DmController(
      api: api,
      chatEnabled: true,
      openStore: (_) => open(),
    );
    await c.bind(
      account: 'account',
      token: 'token',
      identities: [p1.own],
      isCurrent: () => true,
    );
    return c;
  }

  Future<void> close(DmController c) async {
    await c.detach();
    c.dispose();
  }

  test('reference survives lost response and restart once without touching chat draft', () async {
    final api = CardApi()..loseSend = true;
    var c = await bind(api);
    await c.saveDraft(p1.own, p1.peer, 'unfinished private text');
    await c.sharePost(api.dir, p1.post);
    await c.sync();
    expect(api.accepted, 1);
    expect(c.conversations.single['localPreviewKind'], 'post');
    expect(c.conversations.single['localPreview'], isNot(p1.post));
    expect(await c.draft(p1.own, p1.peer), 'unfinished private text');
    await close(c);
    c = await bind(api);
    await c.sync();
    final rows = await c.history(p1.own, p1.peer);
    expect(rows.length, 1);
    expect(rows.single['messageType'], 'POST');
    expect((rows.single['intent'] as Map)['text'], p1.post);
    expect(rows.toString(), isNot(contains('当前标题')));
    expect(api.accepted, 1);
    await close(c);
  });
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }

  test(
    'unknown and unavailable conversations cannot be selected for a new card',
    () async {
      final api = CardApi();
      final c = await bind(api);
      await expectLater(
        c.sharePost({...api.dir, 'canShare': false}, p1.post),
        throwsStateError,
      );
      expect(api.accepted, 0);
      await close(c);
    },
  );
  test(
    'recipient durably stores a typed reference before ACK and reloads it',
    () async {
      final api = CardApi();
      final c = await bind(api);
      final now = DateTime.now().toUtc();
      api.pending.add({
        'messageId': p1.post,
        'conversationId': p1.conversation,
        'identityId': p1.own,
        'senderId': p1.peer,
        'sequence': 11,
        'text': p1.post,
        'acceptedAt': now.toIso8601String(),
        'kind': 'POST',
        'groupId': '',
        'position': 0,
        'groupSize': 0,
        'media': null,
        'evidenceVersion': 1,
      });
      await c.sync();
      final rows = await c.history(p1.own, p1.peer);
      expect(rows.single['messageType'], 'POST');
      expect(api.acknowledgments, 1);
      expect(rows.single['text'], p1.post);
      await close(c);
    },
  );
  test('post reference parser rejects snapshots, untrusted fields and malformed IDs', () {
    final preview = {
      'postId': p1.post,
      'title': 'current',
      'channelId': p1.peer,
      'channelName': '科技',
    };
    expect(decodeDm(preview, 'chat/posts/${p1.post}'), preview);
    expect(
      () => decodeDm({...preview, 'body': 'snapshot'}, 'chat/posts/${p1.post}'),
      throwsFormatException,
    );
    expect(
      () => decodeDm({...preview, 'postId': p1.peer}, 'chat/posts/${p1.post}'),
      throwsFormatException,
    );
    expect(
      () => decodeDm({
        'state': 'FAILED',
        'attempt': 1,
        'errorCode': 'POST_NOT_FOUND',
      }, 'commands/${p1.post}'),
      returnsNormally,
    );
  });
  testWidgets(
    'picker cancel sends nothing; confirmed single send keeps underlying page',
    (tester) async {
      final api = CardApi();
      final c = UiCardController(api);
      final runtime = chat.ChatRuntime(c);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });
      await tester.pumpWidget(
        DmScope(
          runtime: runtime,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => sharePostInDm(context, p1.post),
                  child: const Text('open sharing'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open sharing'));
      await tester.pump();
      await flush(tester);
      await tester.pumpAndSettle();
      expect(find.text('分享至私信'), findsOneWidget);
      await tester.tap(find.text('对方当前昵称').first);
      await tester.pumpAndSettle();
      expect(find.text('以 本人面具 发送给 对方当前昵称'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消').last);
      await tester.pumpAndSettle();
      expect(api.accepted, 0);
      await tester.tap(find.text('对方当前昵称').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '发送'));
      await flush(tester);
      await tester.pumpAndSettle();
      expect(api.accepted, 1);
      expect(find.text('open sharing'), findsOneWidget);
      expect(find.text('分享至私信'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      runtime.dispose();
    },
  );
  testWidgets(
    'visible card refreshes title, drops old title offline, hides removed target',
    (tester) async {
      final api = CardApi();
      final c = UiCardController(api);
      final runtime = chat.ChatRuntime(c);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });
      await tester.pumpWidget(
        DmScope(
          runtime: runtime,
          child: const MaterialApp(
            home: Scaffold(
              body: DmPostCardBubble(postId: p1.post, time: '12:00'),
            ),
          ),
        ),
      );
      await flush(tester);
      await tester.pump();
      expect(find.text('当前标题'), findsOneWidget);
      expect(find.text('科技'), findsOneWidget);
      api.title = '编辑后的标题';
      await tester.tap(find.byType(DmPostCardBubble));
      await flush(tester);
      await tester.pump();
      expect(find.text('编辑后的标题'), findsOneWidget);
      expect(find.text('当前标题'), findsNothing);
      api.offline = true;
      await tester.tap(find.byType(DmPostCardBubble));
      await flush(tester);
      await tester.pump();
      expect(find.text('联网后查看'), findsOneWidget);
      expect(find.text('编辑后的标题'), findsNothing);
      api.offline = false;
      api.removed = true;
      await tester.tap(find.byType(DmPostCardBubble));
      await flush(tester);
      await tester.pump();
      expect(find.text('帖子已不可用'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      runtime.dispose();
    },
  );
  testWidgets('unavailable post disables sending from a stale source page', (
    tester,
  ) async {
    final api = CardApi()..removed = true;
    final c = UiCardController(api);
    final runtime = chat.ChatRuntime(c);
    await tester.pumpWidget(
      DmScope(
        runtime: runtime,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => sharePostInDm(context, p1.post),
                child: const Text('open sharing'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open sharing'));
    await flush(tester);
    await tester.pumpAndSettle();
    expect(find.text('帖子已不可用'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '对方当前昵称')).onTap,
      isNull,
    );
    expect(api.accepted, 0);
    await tester.pumpWidget(const SizedBox());
    runtime.dispose();
    c.dispose();
  });
  testWidgets(
    'late preview cannot reveal a title after account authority closes',
    (tester) async {
      final api = CardApi()..cardWait = Completer<void>();
      final c = UiCardController(api);
      final runtime = chat.ChatRuntime(c);
      await tester.pumpWidget(
        DmScope(
          runtime: runtime,
          child: const MaterialApp(
            home: Scaffold(
              body: DmPostCardBubble(postId: p1.post, time: '12:00'),
            ),
          ),
        ),
      );
      c.revoke();
      await tester.pump();
      api.cardWait!.complete();
      await flush(tester);
      await tester.pump();
      expect(find.text('当前标题'), findsNothing);
      expect(find.text('联网后查看'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      runtime.dispose();
      c.dispose();
    },
  );
}
