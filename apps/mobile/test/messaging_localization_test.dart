import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_presentation.dart';
import 'package:hnuhole_mobile/src/auth/auth_store.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_inbox.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_screen.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_notifications.dart';
import 'package:hnuhole_mobile/src/reports/report_screens.dart';
import 'package:hnuhole_mobile/src/system_notifications/inbox_screen.dart';
import 'package:hnuhole_mobile/src/system_notifications/notification_localizations.dart';
import 'package:hnuhole_mobile/src/system_notifications/notification_models.dart';
import 'package:hnuhole_mobile/src/system_notifications/notification_screens.dart';

import 'direct_message_screen_test.dart' as chat;
import 'identity_test_support.dart';
import 'notification_inbox_test.dart' as inbox;

Widget localizedApp(
  AuthPresentationController language,
  Widget home, {
  double scale = 1,
}) => AuthPresentationScope(
  controller: language,
  child: MaterialApp(
    theme: HhTelegramTheme.create(Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  ),
);

class _Vault implements AuthVault {
  String? value;
  int writes = 0;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    writes++;
    this.value = value;
  }
}

class _NotificationController extends ChangeNotifier implements DmController {
  @override
  bool available = true;
  @override
  String scope = 'same-session';
  @override
  String? accountId = 'account';
  @override
  List<Map<String, dynamic>> conversations = [
    {
      'identityId': 'self',
      'id': 'conversation',
      'peerName': '私信',
      'muted': false,
      'deleted': false,
    },
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'live chat language changes retain draft, media and user content',
    (tester) async {
      final language = AuthPresentationController();
      addTearDown(language.dispose);
      final screen = chat.app(
        chat.view(
          messages: const [
            DmMessage(
              id: 'incoming',
              outgoing: false,
              text: '还没有消息',
              time: '10:24',
            ),
          ],
        ),
        send: (_) async => false,
      );
      await tester.pumpWidget(
        AuthPresentationScope(controller: language, child: screen),
      );
      final state = tester.state(find.byType(HhDirectMessageScreen));
      final input = find.byKey(const ValueKey('dm-input'));
      await tester.enterText(input, '私信\nmy draft');
      await tester.tap(find.byKey(const ValueKey('dm-attach')));
      await tester.pump();
      for (final (value, hint, remove, send) in [
        (AppLanguage.simplifiedChinese, '输入消息', '移除第1张图片', '发送消息'),
        (AppLanguage.traditionalChinese, '輸入訊息', '移除第1張圖片', '傳送訊息'),
        (AppLanguage.english, 'Message', 'Remove image 1', 'Send message'),
        (AppLanguage.japanese, 'メッセージを入力', '1枚目の画像を削除', 'メッセージを送信'),
      ]) {
        language.setLanguage(value);
        await tester.pump();
        expect(tester.state(find.byType(HhDirectMessageScreen)), same(state));
        final field = tester.widget<TextField>(input);
        expect(field.controller!.text, '私信\nmy draft');
        expect(field.decoration!.hintText, hint);
        expect(find.byTooltip(remove), findsOneWidget);
        expect(find.byTooltip(send), findsOneWidget);
        expect(find.text('还没有消息'), findsOneWidget);
        expect(find.text('海边的树'), findsOneWidget);
        expect(find.text('青柠汽水'), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('dm-send')));
      await tester.pump();
      expect(find.text('メッセージはまだ保存されていません。再試行してください'), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, '私信\nmy draft');
      expect(
        find.byKey(const ValueKey('remove-image:fixture-east-gate')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'inbox labels and unread semantics change without altering previews',
    (tester) async {
      final language = AuthPresentationController();
      addTearDown(language.dispose);
      const self = DmIdentity(id: 'self', name: '本人面具');
      await tester.pumpWidget(
        localizedApp(
          language,
          HhDmInboxScreen(
            scopeKey: 'same-account:self',
            identity: self,
            identities: const [DmInboxIdentity(self)],
            entries: const [
              DmInboxEntry(
                id: 'conversation',
                selfIdentityId: 'self',
                recipient: DmIdentity(id: 'other', name: '搜索'),
                preview: '[图片]',
                time: '10:24',
                unread: 3,
              ),
            ],
            error: '操作未完成：保存失败，请保留输入并重试',
            onOpen: (_) {},
            onIdentitySelected: (_) {},
          ),
        ),
      );
      final state = tester.state(find.byType(HhDmInboxScreen));
      final semantics = tester.ensureSemantics();
      for (final (value, heading, unread, error) in [
        (AppLanguage.simplifiedChinese, '私信', '3条未读', '操作未完成：保存失败，请保留输入并重试'),
        (AppLanguage.traditionalChinese, '私信', '3條未讀', '操作未完成：儲存失敗，請保留輸入並重試'),
        (
          AppLanguage.english,
          'Direct messages',
          '3 unread',
          'Action incomplete: Saving failed. Keep your input and retry.',
        ),
        (
          AppLanguage.japanese,
          'ダイレクトメッセージ',
          '未読3件',
          '操作は未完了です：保存に失敗しました。入力を保持したまま再試行してください',
        ),
      ]) {
        language.setLanguage(value);
        await tester.pump();
        expect(tester.state(find.byType(HhDmInboxScreen)), same(state));
        expect(find.text(heading), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('conversation:conversation')),
            matching: find.text('搜索'),
          ),
          findsOneWidget,
        );
        expect(find.text('[图片]'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(unread))),
          findsOneWidget,
        );
        expect(find.text(error), findsOneWidget);
      }
      final input = find.byKey(const ValueKey('dm-search'));
      await tester.enterText(input, '搜索');
      language.setLanguage(AppLanguage.english);
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, '搜索');
      expect(find.text('[图片]'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'notification language updates labels and age without reloading data',
    (tester) async {
      final (auth, controller, api) = await inbox.fixture();
      final language = AuthPresentationController();
      addTearDown(() {
        controller.dispose();
        auth.dispose();
        language.dispose();
      });
      api.delayed = (_, _) async => {
        'items': [
          {
            ...inbox.row(identityTestId, '私信'),
            'title': '你的帖子收到了赞',
            'sourceTitle': '系统通知',
            'createdAt': DateTime.now()
                .subtract(const Duration(minutes: 4))
                .toUtc()
                .toIso8601String(),
          },
        ],
        'nextCursor': null,
      };
      await tester.pumpWidget(
        localizedApp(language, NotificationInboxScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(NotificationInboxScreen));
      final count = api.calls.length;
      for (final (value, heading, title, age) in [
        (AppLanguage.simplifiedChinese, '通知', '你的帖子收到了赞', '4 分钟前'),
        (AppLanguage.traditionalChinese, '通知', '你的帖子收到了贊', '4 分鐘前'),
        (
          AppLanguage.english,
          'Notifications',
          'Your post received likes',
          '4 min ago',
        ),
        (AppLanguage.japanese, '通知', 'あなたの投稿にいいねが付きました', '4分前'),
      ]) {
        language.setLanguage(value);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(NotificationInboxScreen)), same(state));
        expect(find.text(heading), findsOneWidget);
        expect(find.text(title), findsOneWidget);
        expect(find.text(age), findsOneWidget);
        expect(find.text('私信'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text && widget.data == '系统通知' && widget.maxLines == 1,
          ),
          findsOneWidget,
        );
        expect(find.text('发言者'), findsOneWidget);
        expect(api.calls.length, count);
      }
    },
  );

  testWidgets(
    'report language changes preserve selected reason and typed evidence',
    (tester) async {
      final (auth, controller, _) = await inbox.fixture();
      final language = AuthPresentationController();
      addTearDown(() {
        controller.dispose();
        auth.dispose();
        language.dispose();
      });
      await tester.pumpWidget(
        localizedApp(
          language,
          ReportScreen(controller: controller, postId: inbox.post, title: '私信'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('广告引流').last);
      await tester.pumpAndSettle();
      final description = find.byType(TextField).first;
      await tester.enterText(description, '举报说明原文');
      final state = tester.state(find.byType(MaterialEvidenceForm));
      for (final (value, title, reason) in [
        (AppLanguage.traditionalChinese, '舉報', '廣告引流'),
        (AppLanguage.english, 'Report', 'Advertising or spam'),
        (AppLanguage.japanese, '通報', '広告・誘導'),
      ]) {
        language.setLanguage(value);
        await tester.pump();
        expect(tester.state(find.byType(MaterialEvidenceForm)), same(state));
        expect(find.text(title), findsOneWidget);
        expect(find.text(reason), findsOneWidget);
        expect(find.text('私信'), findsOneWidget);
        expect(
          tester.widget<TextField>(description).controller!.text,
          '举报说明原文',
        );
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>).first,
              )
              .initialValue,
          'ADVERTISING',
        );
      }
    },
  );

  testWidgets('moderation values remain verbatim when labels are translated', (
    tester,
  ) async {
    final (auth, controller, _) = await inbox.fixture();
    final language = AuthPresentationController()
      ..setLanguage(AppLanguage.english);
    addTearDown(() {
      controller.dispose();
      auth.dispose();
      language.dispose();
    });
    SystemNotice notice(String kind, String body) => SystemNotice(
      id: 'notice',
      eventId: 'event',
      source: 'SERVER',
      scope: 'ACCOUNT',
      kind: kind,
      state: 'PENDING',
      title: '举报已提交，等待处理',
      body: body,
      createdAt: DateTime(2026),
      route: const NotificationRoute('REPORT', 'report'),
    );
    await tester.pumpWidget(
      localizedApp(
        language,
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                Text(
                  systemNoticeBody(
                    context,
                    notice('REPORT_PROGRESS', '提交举报不代表认定违规。'),
                  ),
                ),
                Text(
                  systemNoticeBody(context, notice('SANCTION', '提交举报不代表认定违规。')),
                ),
                GovernanceResourceView(
                  controller: controller,
                  route: const NotificationRoute('REPORT', 'report'),
                  resource: const {
                    'report': {
                      'state': 'PENDING',
                      'reason': 'ADVERTISING',
                      'description': '举报',
                      'explanation': '广告引流',
                    },
                  },
                  onRefresh: () async {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('Submitting a report does not establish a violation.'),
      findsOneWidget,
    );
    expect(find.text('提交举报不代表认定违规。'), findsOneWidget);
    expect(find.text('Report description: 举报'), findsOneWidget);
    expect(find.text('Brief explanation: 广告引流'), findsOneWidget);
    expect(find.text('Report category: Advertising or spam'), findsOneWidget);
    expect(find.text('Status: Pending'), findsOneWidget);
  });

  testWidgets(
    'translated notification tabs and chat fit 320dp at double text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (auth, controller, _) = await inbox.fixture();
      final language = AuthPresentationController();
      addTearDown(() {
        controller.dispose();
        auth.dispose();
        language.dispose();
      });
      await tester.pumpWidget(
        localizedApp(
          language,
          NotificationInboxScreen(controller: controller),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      for (final value in AppLanguage.values) {
        language.setLanguage(value);
        for (final category in ['all', 'reply', 'like', 'system']) {
          await tester.tap(find.byKey(ValueKey('notification-tab:$category')));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${value.code}:$category',
          );
        }
      }
      await tester.pumpWidget(
        AuthPresentationScope(
          controller: language,
          child: chat.app(chat.view(), scale: 2),
        ),
      );
      for (final value in AppLanguage.values) {
        language.setLanguage(value);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: value.code);
        expect(find.byKey(const ValueKey('dm-input')), findsOneWidget);
      }
    },
  );

  test(
    'notification display language never changes permissions or privacy',
    () async {
      const channel = MethodChannel('test/messaging-language');
      final calls = <MethodCall>[];
      final vault = _Vault();
      final controller = _NotificationController();
      final notifications = DmNotifications(
        environment: 'locale-test',
        preferences: vault,
        channel: channel,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        notifications.dispose();
        controller.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await notifications.start();
      await notifications.bind('account');
      await notifications.setPreview('account', true);
      final savedPrivacy = vault.value, writes = vault.writes;
      final tap = DmNotificationTarget(
        notifications.scopeFor('account'),
        'self',
        'conversation',
      );
      notifications.pending = tap;
      for (final (code, normalized, image) in [
        ('zh', 'zh-Hans', '[图片]'),
        ('zh-TW', 'zh-Hant', '[圖片]'),
        ('en-US', 'en', '[Image]'),
        ('ja', 'ja', '[画像]'),
      ]) {
        calls.clear();
        await notifications.setLanguage(code);
        expect(calls.map((c) => c.method), ['setLanguage']);
        expect(calls.single.arguments, {'language': normalized});
        expect(vault.value, savedPrivacy);
        expect(vault.writes, writes);
        expect(notifications.preview('account'), isTrue);
        expect(notifications.pending, same(tap));
        calls.clear();
        await notifications.incoming(
          [
            {
              'identityId': 'self',
              'conversationId': 'conversation',
              'kind': 'IMAGE',
            },
            {
              'identityId': 'self',
              'conversationId': 'conversation',
              'kind': 'TEXT',
              'text': '[图片]',
            },
          ],
          'account',
          controller,
        );
        expect(calls.map((c) => c.method), ['show', 'show']);
        expect((calls.first.arguments as Map)['text'], image);
        expect((calls.last.arguments as Map)['text'], '[图片]');
        expect((calls.last.arguments as Map)['sender'], '私信');
      }
      calls.clear();
      await expectLater(
        notifications.setLanguage('invalid'),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    },
  );
}
