import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/auth/account_closure_screen.dart';
import 'package:hnuhole_mobile/src/auth/device_management_controller.dart';
import 'package:hnuhole_mobile/src/auth/device_management_screen.dart';
import 'package:hnuhole_mobile/src/localization/app_localizations.dart';
import 'package:hnuhole_mobile/src/localization/translations_security_identity.dart';

import 'identity_test_support.dart';
import 'security_settings_test_support.dart';

Widget _localized(AuthPresentationController presentation, Widget home) =>
    AuthPresentationScope(
      controller: presentation,
      child: AnimatedBuilder(
        animation: presentation,
        builder: (context, _) => MaterialApp(
          locale: presentation.language.locale,
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: appSupportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );

void main() {
  test('all security and identity entries cover three target languages and preserve named arguments', () {
    final token = RegExp(r'\{[A-Za-z][A-Za-z0-9_]*\}');
    for (final entry in securityIdentityTranslations.entries) {
      for (final value in [entry.value.$1, entry.value.$2, entry.value.$3]) {
        expect(value.trim(), isNotEmpty, reason: entry.key);
        expect(
          token.allMatches(value).map((m) => m.group(0)).toSet(),
          token.allMatches(entry.key).map((m) => m.group(0)).toSet(),
          reason: entry.key,
        );
      }
    }
    expect(
      translateUi(
        '私有用户名：{name}',
        AppLanguage.english,
        args: {'name': '昵称保持原文'},
      ),
      'Private username: 昵称保持原文',
    );
  });

  testWidgets(
    'four-language closure dialog refreshes in place without changing phrase or password',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = SecuritySettingsFixture();
      await f.start();
      final presentation = AuthPresentationController();
      await tester.pumpWidget(
        _localized(
          presentation,
          AccountClosureScreen(sessions: f.sessions, flows: f.flows),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('closure-confirmation-phrase')),
        accountClosureConfirmationPhrase,
      );
      await tester.pumpAndSettle();
      final phraseController = tester
          .widget<TextField>(
            find.byKey(const ValueKey('closure-confirmation-phrase')),
          )
          .controller!;
      await tester.ensureVisible(
        find.byKey(const ValueKey('closure-start-confirmation')),
      );
      await tester.tap(
        find.byKey(const ValueKey('closure-start-confirmation')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('closure-confirm-password')),
        'keep_password_unchanged',
      );
      for (final language in AppLanguage.values) {
        presentation.setLanguage(language);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(translateUi('确认注销', language)),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('closure-confirm-password')),
              )
              .controller!
              .text,
          'keep_password_unchanged',
        );
        expect(phraseController.text, accountClosureConfirmationPhrase);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const ValueKey('closure-cancel')));
      await tester.pumpAndSettle();
      expect(f.api.closureRequests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      presentation.dispose();
      f.dispose();
    },
  );

  testWidgets(
    'identity UI translates while public nickname and nickname input remain unchanged',
    (tester) async {
      final f = await IdentityTestFixture.create();
      f.api.items = [identityTestItem(name: '账号与安全')];
      final presentation = AuthPresentationController();
      await tester.pumpWidget(
        _localized(
          presentation,
          IdentityManagementScreen(
            controller: f.controller,
            sessions: f.sessions,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final language in AppLanguage.values) {
        presentation.setLanguage(language);
        await tester.pumpAndSettle();
        expect(find.text(translateUi('身份管理', language)), findsOneWidget);
        expect(find.text('账号与安全'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('identity-delete:$identityTestId')),
              )
              .onPressed,
          isNull,
        );
      }
      await tester.tap(find.text('账号与安全'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('identity-nickname')),
        '昵称',
      );
      for (final language in AppLanguage.values) {
        presentation.setLanguage(language);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('identity-nickname')),
              )
              .controller!
              .text,
          '昵称',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      presentation.dispose();
      f.dispose();
    },
  );

  testWidgets(
    'device page follows four locales without reading credential service',
    (tester) async {
      final f = SecuritySettingsFixture();
      await f.start();
      final c = DeviceManagementController(
        api: f.api,
        store: f.store,
        sessions: f.sessions,
      );
      final presentation = AuthPresentationController();
      await tester.pumpWidget(
        _localized(
          presentation,
          DeviceManagementScreen(controller: c, sessions: f.sessions),
        ),
      );
      await tester.pumpAndSettle();
      for (final language in AppLanguage.values) {
        presentation.setLanguage(language);
        await tester.pumpAndSettle();
        expect(find.text(translateUi('当前设备与会话', language)), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(f.api.deviceReads, 1);
      expect(f.api.credentialReads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      presentation.dispose();
      c.dispose();
      f.dispose();
    },
  );
}
