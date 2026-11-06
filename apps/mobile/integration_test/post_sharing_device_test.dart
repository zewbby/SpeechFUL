import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import '../test/login_home_test_support.dart';
import '../test/post_sharing_test.dart' show SharingTestApi;

const _driver = MethodChannel('hnuhole/owned_device_driver');
const _id = '22222222-2222-4222-8222-222222222222';
const _other = '33333333-3333-4333-8333-333333333333';
Future<void> _stage(String value) => _driver.invokeMethod<void>('stage', value);

// Real Android intents and system sheet; auth/data are explicitly synthetic
// host fixtures. The shipped Dart transport is verified separately over TLS.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native cold/warm links and system share retain the original target',
    (tester) async {
      try {
        final phase = await _driver.invokeMethod<String>('phase');
        expect(
          phase,
          isIn(['postshare-cold', 'postshare-login', 'postshare-history']),
        );
        final links = PostLinkInbox(Uri.parse('https://unused.invalid'))
          // TestPlatformDispatcher resets the route for each test; use the
          // actual engine startup route delivered by Android here.
          ..start(
            initialRoute: ui.PlatformDispatcher.instance.defaultRouteName,
          );
        expect(
          links.pending?.target.postId,
          phase == 'postshare-history' ? isNull : _id,
        );
        final api = SharingTestApi();
        final f = HomeTestFixture(api: api);
        await tester.pumpWidget(
          await f.create(postLinks: links, signedIn: phase == 'postshare-cold'),
        );
        await tester.pumpAndSettle();
        if (phase == 'postshare-history') {
          expect(api.resolved, isEmpty);
          expect(find.byType(AuthScreen), findsNothing);
          expect(find.byType(EntryScreen), findsOneWidget);
          await _stage('all-pass');
          await tester.pumpWidget(const SizedBox.shrink());
          return;
        }
        if (phase == 'postshare-login') {
          expect(find.byType(AuthScreen), findsOneWidget);
          expect(api.resolved, isEmpty);
          await tester.enterText(
            find.byType(TextFormField).at(0),
            'share_reader',
          );
          await tester.enterText(
            find.byType(TextFormField).at(1),
            'valid-password-123',
          );
          await tester.tap(find.byKey(const ValueKey('login-submit')));
          await tester.pumpAndSettle();
        }
        expect(find.text('分享原帖甲'), findsOneWidget);
        expect(api.resolved, ['https://unused.invalid/s/posts/$_id']);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(FeedScreen), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('destination:personal')));
        await tester.pumpAndSettle();
        await _stage('await-hot-link');
        for (var i = 0; i < 240 && find.text('分享原帖乙').evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(find.text('分享原帖乙'), findsOneWidget);
        expect(api.resolved.last, 'https://unused.invalid/s/posts/$_other');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(PersonalPostsScreen), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('destination:home')));
        await tester.pumpAndSettle();
        final id = api.items.first.postId;
        await tester.tap(find.byKey(ValueKey('share:$id')));
        await tester.pump(const Duration(milliseconds: 500));
        await _stage('native-share-open');
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 60));
          while (f.posts.sharingPost(id) && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        });
        await tester.pumpAndSettle();
        expect(f.posts.sharingPost(id), isFalse);
        expect(api.shares, 1);
        expect(find.text('分享成功'), findsNothing);
        await _stage('all-pass');
        await tester.pumpWidget(const SizedBox.shrink());
      } catch (_) {
        await _stage('failed');
        rethrow;
      }
    },
  );
}
