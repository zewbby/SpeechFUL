import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart'
    show
        AuthFlows,
        AuthScreen,
        AuthSessionController,
        AuthStore,
        ChannelDirectoryController;
import 'package:hnuhole_mobile/src/auth/auth_presentation.dart';
import 'package:hnuhole_mobile/src/localization/app_localizations.dart';
import 'package:hnuhole_mobile/src/localization/translations_auth.dart';
import 'package:hnuhole_mobile/src/navigation/community_material_labels.dart';

import 'identity_test_support.dart';

class _DraftPage extends StatefulWidget {
  const _DraftPage();
  @override
  State<_DraftPage> createState() => _DraftPageState();
}

class _DraftPageState extends State<_DraftPage> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        hhText(context, '欢迎回来'),
        key: const ValueKey('translated-title'),
      ),
    ),
    body: Column(
      children: [
        TextField(key: const ValueKey('user-draft'), controller: input),
        const Text('用户名', key: ValueKey('user-content')),
      ],
    ),
  );
}

void main() {
  test('explicit templates translate their own labels and preserve all argument values', () {
    const userName = '用户名 {time} 日本語 <tag>';
    expect(
      translateUi(
        '私有用户名：{username}',
        AppLanguage.english,
        args: {'username': userName},
      ),
      'Username: $userName',
    );
    expect(
      translateUi(
        '私有用户名：{username}',
        AppLanguage.japanese,
        args: {'username': userName},
      ),
      '非公開ユーザー名：$userName',
    );
    expect(translateUi('未注册的应用文字', AppLanguage.japanese), '未注册的应用文字');
    expect(
      translateUi(
        '请输入{field}',
        AppLanguage.japanese,
        args: {'field': 'メールアドレス'},
      ),
      'メールアドレスを入力してください',
    );
  });

  test('composed application templates preserve multiline values and leave unknown errors intact', () {
    const rawValue = '用户名\n日本語 {time}\n';
    expect(
      translateUi('私有用户名：$rawValue', AppLanguage.english),
      'Username: $rawValue',
    );
    expect(
      translateUi('预计完成时间：2031-01-01 08:00', AppLanguage.japanese),
      '完了予定日時：2031-01-01 08:00',
    );
    expect(
      translateUi('未知错误：$rawValue', AppLanguage.japanese),
      '未知错误：$rawValue',
    );
    expect(
      translateUi('前缀 私有用户名：$rawValue', AppLanguage.english),
      '前缀 私有用户名：$rawValue',
    );
    expect(
      translateUi('自定义标签：$rawValue', AppLanguage.english),
      '自定义标签：$rawValue',
    );
    expect(
      translateUi(
        '{label}：{value}',
        AppLanguage.english,
        args: {'label': 'Reply', 'value': rawValue},
      ),
      'Reply: $rawValue',
    );
  });

  test('authentication catalog has all three translations and matching named arguments', () {
    final placeholder = RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}');
    Set<String> names(String value) =>
        placeholder.allMatches(value).map((match) => match.group(1)!).toSet();
    for (final entry in authTranslations.entries) {
      for (final translation in [
        entry.value.$1,
        entry.value.$2,
        entry.value.$3,
      ]) {
        expect(translation.trim(), isNotEmpty, reason: entry.key);
        expect(names(translation), names(entry.key), reason: entry.key);
      }
    }
    expect(
      authTranslations.keys,
      containsAll([
        '正在核对登录状态',
        '恢复码已保存并确认',
        '暂时无法确认会话，请重试。',
        '验证码不正确，请重新输入。',
        '开始使用',
        '请输入{field}',
      ]),
    );
  });

  test('legacy auth text translates countdowns and labels without changing private values', () {
    final controller = AuthPresentationController();
    controller.setLanguage(AppLanguage.japanese);
    expect(controller.text('12 秒后可重新获取'), '12 秒後に再取得できます');
    expect(controller.text('8 秒后可核对申请'), '8 秒後に申請を確認できます');
    expect(controller.text('私有用户名：未翻译的用户名'), '非公開ユーザー名：未翻译的用户名');
    controller.setLanguage(AppLanguage.traditionalChinese);
    expect(controller.text('账号与安全'), '帳號與安全');
    controller.english = true;
    expect(controller.language, AppLanguage.english);
    expect(controller.text('恢复码'), 'Recovery code');
    controller.dispose();
  });

  testWidgets(
    'real authentication inputs survive four language changes without signing in',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final presentation = AuthPresentationController();
      final api = IdentityTestSessionApi();
      final store = AuthStore(IdentityTestVault());
      final directory = ChannelDirectoryController(
        repository: IdentityTestChannels(),
      );
      final sessions = AuthSessionController(
        api: api,
        store: store,
        directory: directory,
      );
      final flows = AuthFlows(
        api: api,
        store: store,
        acceptRegistrationSession: sessions.acceptSession,
        clearCommunityAccess: sessions.clearCommunityAccess,
      );
      await sessions.start();
      try {
        await tester.pumpWidget(
          AnimatedBuilder(
            animation: presentation,
            builder: (context, _) => MaterialApp(
              locale: presentation.language.locale,
              localizationsDelegates: appLocalizationDelegates,
              supportedLocales: appSupportedLocales,
              builder: (context, child) => AuthPresentationScope(
                controller: presentation,
                child: child!,
              ),
              home: AuthScreen(sessions: sessions, flows: flows),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final username = find.byKey(const ValueKey('login-username'));
        final password = find.byKey(const ValueKey('login-password'));
        await tester.enterText(username, 'private_name');
        await tester.enterText(password, 'my private password');
        final original = tester.state(find.byType(AuthScreen));
        for (final language in AppLanguage.values) {
          presentation.setLanguage(language);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(AuthScreen)), same(original));
          expect(
            tester.widget<TextFormField>(username).controller!.text,
            'private_name',
          );
          expect(
            tester.widget<TextFormField>(password).controller!.text,
            'my private password',
          );
          expect(find.text(translateUi('欢迎回来', language)), findsOneWidget);
          expect(
            tester
                .widget<TextField>(
                  find.descendant(
                    of: username,
                    matching: find.byType(TextField),
                  ),
                )
                .decoration!
                .labelText,
            translateUi('用户名', language),
          );
          expect(sessions.isAuthenticated, isFalse);
          expect(tester.takeException(), isNull, reason: language.code);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        presentation.dispose();
        flows.dispose();
        sessions.dispose();
        directory.dispose();
        store.dispose();
      }
    },
  );

  testWidgets(
    'four language changes preserve Navigator route, typed input and user content while updating standard labels and speech',
    (tester) async {
      final controller = AuthPresentationController();
      final navigator = GlobalKey<NavigatorState>();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) => AuthPresentationScope(
              controller: controller,
              child: MaterialApp(
                navigatorKey: navigator,
                locale: controller.language.locale,
                supportedLocales: appSupportedLocales,
                localizationsDelegates: appLocalizationDelegates,
                builder: (context, child) =>
                    CommunitySpokenLocale(child: child!),
                home: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const _DraftPage(),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('user-draft')),
          '原文 draft 日本語 {username}',
        );
        final pageState = tester.state<_DraftPageState>(
          find.byType(_DraftPage),
        );
        for (final entry in {
          AppLanguage.traditionalChinese: ('歡迎回來', '返回'),
          AppLanguage.english: ('Welcome back', 'Back'),
          AppLanguage.japanese: ('おかえりなさい', '戻る'),
          AppLanguage.simplifiedChinese: ('欢迎回来', '返回'),
        }.entries) {
          controller.setLanguage(entry.key);
          await tester.pumpAndSettle();
          expect(
            tester.state<_DraftPageState>(find.byType(_DraftPage)),
            same(pageState),
          );
          expect(pageState.input.text, '原文 draft 日本語 {username}');
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('user-content')))
                .data,
            '用户名',
          );
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('translated-title')))
                .data,
            entry.value.$1,
          );
          expect(
            MaterialLocalizations.of(tester.element(find.byType(_DraftPage)))
                .backButtonTooltip,
            entry.value.$2,
          );
          expect(
            tester
                .getSemantics(find.byKey(const ValueKey('translated-title')))
                .getSemanticsData()
                .locale,
            entry.key.locale,
          );
          expect(navigator.currentState!.canPop(), isTrue);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
        controller.dispose();
      }
    },
  );
}
