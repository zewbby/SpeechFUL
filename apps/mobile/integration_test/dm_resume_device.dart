// Isolated, synthetic-account device entrypoint. Runs the normal app graph.
// The private fixture is injected after installation and contains no user data.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/src/development/app_transport.dart';

const driver = MethodChannel('hnuhole/owned_device_driver');
const fixtureDirectory =
    '/data/user/0/org.hnuhole.hnuhole_mobile.dmresume/files';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final phase = await driver.invokeMethod<String>('phase');
  final config = Map<String, String>.from(
    jsonDecode(
      await File('$fixtureDirectory/fixture.private.json').readAsString(),
    ),
  );
  final community = Uri.parse(
    const String.fromEnvironment('AUTH_COMMUNITY_BASE_URL'),
  );
  final verifier = Uri.parse(
    const String.fromEnvironment('AUTH_VERIFIER_BASE_URL'),
  );
  if (phase == 'prime') {
    final api = HttpAuthApi(
      communityBaseUri: community,
      verifierBaseUri: verifier,
      client: createAppHttpClient(community: community, verifier: verifier),
    );
    final session = await api.currentSession(config['DM_TOKEN_B']!);
    final environment = MobileEnvironment(
      communityBaseUri: community,
      verifierBaseUri: verifier,
    );
    final scope = environment.storageScope;
    final namespace = AuthCrypto.domainDigest(
      'HNUHOLE/MOBILE-AUTH-ENVIRONMENT/V1',
      utf8.encode(scope),
    );
    final store = AuthStore(
      FlutterAuthVault(namespace: 'hnuhole.auth.v1.$namespace'),
      scope: scope,
    );
    await store.update(
      (_) => AuthState(
        session: SessionRecord(
          token: config['DM_TOKEN_B']!,
          accountId: session.accountId,
          expiresAt: session.expiresAt,
        ),
        cInstallationId: AuthCrypto.randomEncoded(16),
        vInstallationId: AuthCrypto.randomEncoded(16),
      ),
    );
    store.dispose();
  }
  await app.main();
  var checking = false;
  Timer.periodic(const Duration(milliseconds: 500), (_) async {
    if (checking) return;
    checking = true;
    try {
      app.HnuholeApp? root;
      void visit(Element element) {
        if (element.widget is app.HnuholeApp) {
          root = element.widget as app.HnuholeApp;
        }
        element.visitChildren(visit);
      }

      final element = WidgetsBinding.instance.rootElement;
      if (element != null) visit(element);
      final controller = root?.dm?.controller;
      if (controller == null || !controller.available) return;
      final rows = await controller.history(
        config['DM_IDENTITY_B']!,
        config['DM_IDENTITY_A']!,
      );
      final conversation = controller.conversations
          .where((row) => row['id'] == config['DM_CONVERSATION'])
          .firstOrNull;
      await File('$fixtureDirectory/status.json').writeAsString(
        jsonEncode({
          'pid': pid,
          'authenticated': root!.sessions.isAuthenticated,
          'available': controller.available,
          'messages': rows.length,
          'unread': conversation?['unread'],
          'muted': conversation?['muted'],
        }),
      );
    } finally {
      checking = false;
    }
  });
}
