import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/auth/account_closure_screen.dart';

import 'security_settings_test_support.dart';

Future<void> _open(WidgetTester tester, SecuritySettingsFixture f) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AccountClosureScreen(sessions: f.sessions, flows: f.flows),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _phrase(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('closure-confirmation-phrase')),
    accountClosureConfirmationPhrase,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const ValueKey('closure-start-confirmation')),
  );
  await tester.tap(find.byKey(const ValueKey('closure-start-confirmation')));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester, String password) async {
  await tester.enterText(
    find.byKey(const ValueKey('closure-confirm-password')),
    password,
  );
  await tester.tap(find.byKey(const ValueKey('closure-final-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  for (final removePageOnly in [true, false]) {
    testWidgets(
      'retiring closure route closes dialog and releases password: removePageOnly=$removePageOnly',
      (tester) async {
        final f = SecuritySettingsFixture();
        await f.start();
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('home')),
          ),
        );
        final page = MaterialPageRoute<void>(
          builder: (_) =>
              AccountClosureScreen(sessions: f.sessions, flows: f.flows),
        );
        navigator.currentState!.push(page);
        await tester.pumpAndSettle();
        await _phrase(tester);
        await tester.enterText(
          find.byKey(const ValueKey('closure-confirm-password')),
          'must_not_send',
        );
        final password = tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('closure-confirm-password')),
            )
            .controller!;
        final oldConfirm = tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('closure-final-confirm')),
            )
            .onPressed!;
        if (removePageOnly) {
          navigator.currentState!.removeRoute(page);
        } else {
          navigator.currentState!.popUntil((route) => route.isFirst);
        }
        await tester.pumpAndSettle();
        oldConfirm();
        expect(
          find.byKey(const ValueKey('closure-password-dialog')),
          findsNothing,
        );
        expect(find.text('home'), findsOneWidget);
        expect(f.api.closureRequests, isEmpty);
        expect(tester.takeException(), isNull);
        expect(() => password.addListener(() {}), throwsFlutterError);
        await tester.pumpWidget(const SizedBox.shrink());
        f.dispose();
      },
    );
  }

  testWidgets(
    'removing a page with an open password dialog clears its callback without a request',
    (tester) async {
      final f = SecuritySettingsFixture();
      await f.start();
      await _open(tester, f);
      await _phrase(tester);
      final oldConfirm = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('closure-final-confirm')),
          )
          .onPressed!;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      oldConfirm();
      expect(tester.takeException(), isNull);
      expect(f.api.closureRequests, isEmpty);
      f.dispose();
    },
  );
  testWidgets(
    'only exact phrase enables red button; dialog requires password; cancel sends nothing',
    (tester) async {
      final f = SecuritySettingsFixture();
      await f.start();
      await _open(tester, f);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('closure-start-confirmation')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('closure-confirmation-phrase')),
        '确认注销账号',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('closure-start-confirmation')),
            )
            .onPressed,
        isNull,
      );
      await _phrase(tester);
      expect(
        find.byKey(const ValueKey('closure-password-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('closure-final-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('请输入当前密码'), findsOneWidget);
      expect(f.api.closureRequests, isEmpty);
      final originalConfirm = tester.widget<FilledButton>(
        find.byKey(const ValueKey('closure-final-confirm')),
      );
      final colorScheme = Theme.of(
        tester.element(find.byKey(const ValueKey('closure-final-confirm'))),
      ).colorScheme;
      expect(
        originalConfirm.style!.backgroundColor!.resolve({}),
        colorScheme.error,
      );
      await tester.enterText(
        find.byKey(const ValueKey('closure-confirm-password')),
        'not_sent_password',
      );
      await tester.tap(find.byKey(const ValueKey('closure-cancel')));
      await tester.pumpAndSettle();
      originalConfirm.onPressed!();
      await tester.pumpAndSettle();
      expect(f.api.closureRequests, isEmpty);
      expect(f.sessions.isAuthenticated, isTrue);
      await _phrase(tester);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('closure-confirm-password')),
            )
            .controller!
            .text,
        isEmpty,
      );
      await _confirm(tester, 'current_password');
      expect(f.api.closureRequests.single.password, 'current_password');
      expect(f.flows.status, AuthFlowStatus.closurePending);
      expect(f.sessions.isAuthenticated, isFalse);
      expect(f.vault.value, isNot(contains('current_password')));
      expect(find.textContaining('七天注销缓冲期'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    },
  );
  testWidgets(
    'unknown outcome checks original request and never auto-resends; retry preserves original identity',
    (tester) async {
      final f = SecuritySettingsFixture();
      await f.start();
      f.api.closureFailure = const AuthFailure(kind: AuthFailureKind.timeout);
      await _open(tester, f);
      await _phrase(tester);
      await _confirm(tester, 'password');
      expect(f.flows.status, AuthFlowStatus.closureUnknown);
      expect(f.api.closureRequests.length, 1);
      final original = f.api.closureRequests.single;
      await tester.ensureVisible(find.text('重试原注销申请'));
      await tester.tap(find.text('重试原注销申请'));
      await tester.pumpAndSettle();
      f.api.closureFailure = null;
      await _confirm(tester, 'retry_password');
      expect(f.api.closureRequests.length, 2);
      expect(f.api.closureRequests.last.id, original.id);
      expect(f.api.closureRequests.last.digest, original.digest);
      expect(f.flows.status, AuthFlowStatus.closurePending);
      await tester.tap(find.text('核对注销状态'));
      await tester.pumpAndSettle();
      expect(f.api.closureQueries, 1);
      expect(f.api.closureRequests.length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    },
  );
  testWidgets(
    'session loss dismisses password dialog and fences a retained confirmation callback',
    (tester) async {
      final f = SecuritySettingsFixture();
      await f.start();
      await _open(tester, f);
      await _phrase(tester);
      final oldConfirm = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('closure-final-confirm')),
          )
          .onPressed!;
      await tester.enterText(
        find.byKey(const ValueKey('closure-confirm-password')),
        'must_not_send',
      );
      await f.sessions.logout();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('closure-password-dialog')),
        findsNothing,
      );
      oldConfirm();
      await tester.pumpAndSettle();
      expect(f.api.closureRequests, isEmpty);
      expect(find.textContaining('登录状态已变化'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    },
  );
}
