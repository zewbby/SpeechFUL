import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_presentation.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_chrome.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_inbox.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_runtime.dart';

import 'direct_message_screen_test.dart' as chat;

class _InboxController extends ChangeNotifier implements DmController {
  @override
  bool get available => true;
  @override
  bool get chatEnabled => true;
  @override
  String get scope => 'unchanged-account-generation';
  @override
  String? get error => null;
  @override
  List<Map<String, dynamic>> conversations = [
    for (var i = 0; i < 30; i++)
      {
        'id': 'c$i',
        'identityId': 'self',
        'peerId': 'p$i',
        'peerName': 'user$i',
        'localPreviewKind': switch (i % 3) {
          0 => 'image',
          1 => 'recalled',
          _ => 'text',
        },
        'localPreview': i % 3 == 1 ? '消息已撤回' : '[图片]',
        'localOrdinal': 30 - i,
        'sourceTitle': '私信',
        'waiting': false,
        'unread': 0,
      },
  ];
  void newMessageWithSamePreview() {
    conversations.first['localOrdinal'] = 31;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InboxRuntime extends ChangeNotifier implements DmRuntime {
  _InboxRuntime(this.controller);
  @override
  final DmController controller;
  @override
  DmIdentityStatus get identityStatus => DmIdentityStatus.ready;
  @override
  List<DmIdentity> get identities => const [DmIdentity(id: 'self', name: '本人')];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('open conversation menu follows all four languages', (
    tester,
  ) async {
    final language = AuthPresentationController();
    addTearDown(language.dispose);
    var managed = 0;
    await tester.pumpWidget(
      AuthPresentationScope(
        controller: language,
        child: MaterialApp(
          home: Scaffold(
            body: HhDmHeader(
              view: chat.view(),
              onBack: () {},
              onSource: () {},
              onManage: () => managed++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('dm-conversation-menu')));
    await tester.pumpAndSettle();
    for (final (value, manage, source, copy) in [
      (AppLanguage.simplifiedChinese, '会话管理', '查看来源帖', '复制昵称'),
      (AppLanguage.traditionalChinese, '會話管理', '檢視來源帖', '複製暱稱'),
      (
        AppLanguage.english,
        'Manage conversation',
        'View source post',
        'Copy nickname',
      ),
      (AppLanguage.japanese, '会話の管理', '元の投稿を表示', 'ニックネームをコピー'),
    ]) {
      language.setLanguage(value);
      await tester.pumpAndSettle();
      expect(find.text(manage), findsOneWidget);
      expect(find.text(source), findsOneWidget);
      expect(find.text(copy), findsOneWidget);
      expect(find.text('海边的树'), findsOneWidget);
      expect(managed, 0);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('会話の管理'));
    await tester.pumpAndSettle();
    expect(managed, 1);
  });

  testWidgets(
    'open message menu changes language without changing actions or draft',
    (tester) async {
      final language = AuthPresentationController();
      addTearDown(language.dispose);
      final actions = <(DmMessageTarget, DmMessageAction)>[];
      await tester.pumpWidget(
        AuthPresentationScope(
          controller: language,
          child: chat.app(
            chat.view(
              messages: const [
                DmMessage(
                  id: 'incoming',
                  outgoing: false,
                  time: '09:40',
                  text: '用户原文 unchanged',
                ),
              ],
            ),
            action: (target, action) async => actions.add((target, action)),
          ),
        ),
      );
      final input = find.byKey(const ValueKey('dm-input'));
      await tester.enterText(input, '未发送的草稿 draft');
      await tester.longPress(find.text('用户原文 unchanged'));
      await tester.pumpAndSettle();
      for (final (value, copy, delete, report) in [
        (AppLanguage.simplifiedChinese, '复制', '删除', '举报'),
        (AppLanguage.traditionalChinese, '複製', '刪除', '舉報'),
        (AppLanguage.english, 'Copy', 'Delete', 'Report'),
        (AppLanguage.japanese, 'コピー', '削除', '通報'),
      ]) {
        language.setLanguage(value);
        await tester.pumpAndSettle();
        expect(find.text(copy), findsOneWidget);
        expect(find.text(delete), findsOneWidget);
        expect(find.text(report), findsOneWidget);
        expect(
          tester
              .widgetList<PopupMenuItem<DmMessageAction>>(
                find.byType(PopupMenuItem<DmMessageAction>),
              )
              .map((item) => item.value),
          [
            DmMessageAction.copy,
            DmMessageAction.delete,
            DmMessageAction.report,
          ],
        );
        expect(
          tester.widget<TextField>(input).controller!.text,
          '未发送的草稿 draft',
        );
        expect(find.text('用户原文 unchanged'), findsOneWidget);
        expect(actions, isEmpty);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('削除'));
      await tester.pumpAndSettle();
      expect(actions.single.$1.scopeKey, 'pair-a');
      expect(actions.single.$1.messageId, 'incoming');
      expect(actions.single.$2, DmMessageAction.delete);
    },
  );

  testWidgets(
    'inbox language changes preserve reading state without fake new messages',
    (tester) async {
      final language = AuthPresentationController();
      final controller = _InboxController();
      final runtime = _InboxRuntime(controller);
      addTearDown(() {
        runtime.dispose();
        controller.dispose();
        language.dispose();
      });
      await tester.pumpWidget(
        AuthPresentationScope(
          controller: language,
          child: MaterialApp(home: DmInboxRoute(runtime: runtime)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -550));
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(HhDmInboxScreen));
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      final offset = scroll.position.pixels;
      expect(offset, greaterThan(40));
      for (final (value, image, recalled) in [
        (AppLanguage.simplifiedChinese, '[图片]', '消息已撤回'),
        (AppLanguage.traditionalChinese, '[圖片]', '訊息已撤回'),
        (AppLanguage.english, '[Image]', 'Message recalled'),
        (AppLanguage.japanese, '[画像]', 'メッセージは取り消されました'),
      ]) {
        language.setLanguage(value);
        await tester.pumpAndSettle();
        final entries = tester
            .widget<HhDmInboxScreen>(find.byType(HhDmInboxScreen))
            .entries;
        expect(entries[0].preview, image);
        expect(entries[1].preview, recalled);
        expect(entries[2].preview, '[图片]');
        expect(entries[2].sourceTitle, '私信');
        expect(entries.map((e) => e.id), [for (var i = 0; i < 30; i++) 'c$i']);
        expect(tester.state(find.byType(HhDmInboxScreen)), same(state));
        expect(scroll.position.pixels, closeTo(offset, .1));
        expect(find.byKey(const ValueKey('dm-inbox-new')), findsNothing);
        expect(tester.takeException(), isNull);
      }
      controller.newMessageWithSamePreview();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dm-inbox-new')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dm-inbox-new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dm-inbox-new')), findsNothing);
      expect(scroll.position.pixels, 0);
    },
  );
}
