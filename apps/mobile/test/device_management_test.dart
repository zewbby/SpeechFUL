import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/auth/device_management_controller.dart';
import 'package:hnuhole_mobile/src/auth/device_management_screen.dart';

import 'security_settings_test_support.dart';

void main() {
  testWidgets(
    'account security allows logout during a credential read and after credential service failure',
    (tester) async {
      for (final loading in [false, true]) {
        final f = SecuritySettingsFixture();
        await f.start();
        if (loading) {
          f.api.credentialWait = Completer<RecoveryCredentialSummary>();
        }
        final c = SecurityManagementController(
          api: f.api,
          store: f.store,
          sessions: f.sessions,
          passkey: NativePasskeyClient(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SecurityManagementScreen(controller: c, sessions: f.sessions),
          ),
        );
        await tester.pump();
        if (!loading) await tester.pumpAndSettle();
        final signOut = find.byKey(const ValueKey('security-sign-out'));
        expect(tester.widget<OutlinedButton>(signOut).onPressed, isNotNull);
        await tester.ensureVisible(signOut);
        await tester.tap(signOut);
        await tester.pumpAndSettle();
        expect(f.sessions.isAuthenticated, isFalse);
        expect(f.store.current!.session, isNull);
        if (loading) {
          f.api.credentialWait!.complete(
            RecoveryCredentialSummary(
              passkeys: const [],
              sessionExpiresAt: securityTestExpiry,
            ),
          );
          await tester.pumpAndSettle();
          expect(c.credentials, isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        f.dispose();
      }
    },
  );

  test('device read is independent of recovery service and publishes only current session after durable metadata', () async {
    final f = SecuritySettingsFixture();
    await f.start();
    final c = DeviceManagementController(
      api: f.api,
      store: f.store,
      sessions: f.sessions,
    );
    addTearDown(f.dispose);
    addTearDown(c.dispose);
    await c.load();
    expect(c.status, DeviceManagementStatus.ready);
    expect(f.api.deviceReads, 1);
    expect(f.api.credentialReads, 0);
    expect(c.device!.lastReplacedAt, isNull);
    expect(c.device!.lastReplacedSignedInAt, isNull);
    expect(c.device!.sessionExpiresAt, f.store.current!.session!.expiresAt);
    await f.sessions.logout();
    expect(c.device, isNull);
  });
  test('late read cannot publish or extend a replacement account and secure write failure hides device data', () async {
    final f = SecuritySettingsFixture();
    await f.start();
    final c = DeviceManagementController(
      api: f.api,
      store: f.store,
      sessions: f.sessions,
    );
    addTearDown(f.dispose);
    addTearDown(c.dispose);
    f.api.deviceWait = Completer<DeviceDirectory>();
    final read = c.load();
    f.api.account = '00000000-0000-4000-8000-000000000002';
    await f.sessions.login('other_account', 'password');
    f.api.deviceWait!.complete(
      DeviceDirectory(
        currentSignedInAt: DateTime.utc(2026),
        sessionExpiresAt: DateTime.utc(2040),
      ),
    );
    await read;
    expect(c.device, isNull);
    expect(f.store.current!.session!.expiresAt, securityTestExpiry);
    f.api.deviceWait = null;
    f.vault.failNext = true;
    await c.load();
    expect(c.device, isNull);
    expect(c.status, DeviceManagementStatus.storageFailure);
  });
  testWidgets(
    'device page contains current session only and retains explicit logout',
    (tester) async {
      final f = SecuritySettingsFixture();
      await f.start();
      final c = DeviceManagementController(
        api: f.api,
        store: f.store,
        sessions: f.sessions,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceManagementScreen(controller: c, sessions: f.sessions),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('current-device-session')),
        findsOneWidget,
      );
      expect(find.text('最近被接替的设备'), findsNothing);
      expect(find.text('恢复凭据'), findsNothing);
      expect(find.text('Passkey'), findsNothing);
      expect(f.api.credentialReads, 0);
      await tester.tap(find.text('退出本机'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('current-device-session')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      f.dispose();
    },
  );
}
