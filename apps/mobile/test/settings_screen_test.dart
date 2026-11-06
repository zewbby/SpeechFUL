import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/localization/app_localizations.dart';

import 'identity_test_support.dart';

class _DeniedGallery implements ViewerGalleryWriter {
  int requests = 0, writes = 0;
  @override
  Future<bool> hasAccess() async => false;
  @override
  Future<bool> requestAccess() async {
    requests++;
    return false;
  }

  @override
  Future<void> putImage(String path) async {
    writes++;
  }
}

Future<void> _open(WidgetTester tester, String key) async {
  final scroll = find.descendant(
    of: find.byKey(const ValueKey('settings-list')),
    matching: find.byType(Scrollable),
  );
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pump();
  final target = find.byKey(ValueKey('settings-$key'));
  await tester.scrollUntilVisible(target, 120, scrollable: scroll);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Widget _app(AuthPresentationController c, {SettingsScreen? settings}) =>
    AnimatedBuilder(
      animation: c,
      builder: (context, _) => MaterialApp(
        locale: c.language.locale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationDelegates,
        builder: (context, child) =>
            AuthPresentationScope(controller: c, child: child!),
        home:
            settings ??
            SettingsScreen(onManageIdentity: () {}, onManageSecurity: () {}),
      ),
    );

void main() {
  testWidgets(
    'settings press cancellation and keyboard activation keep one route',
    (tester) async {
      final c = AuthPresentationController();
      var activations = 0;
      await tester.pumpWidget(
        _app(
          c,
          settings: SettingsScreen(
            onManageIdentity: () {},
            onManageSecurity: () => activations++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final devices = find.byKey(const ValueKey('settings-devices'));
      final point = tester.getCenter(devices);
      final gesture = await tester.startGesture(point);
      await tester.pump(const Duration(milliseconds: 80));
      expect(activations, 0);
      await gesture.moveBy(const Offset(0, -100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(activations, 0);
      await tester.tap(devices);
      await tester.pumpAndSettle();
      expect(activations, 1);
      // A pointer activation leaves the entry focusable for native keyboard use.
      for (var step = 0; step < 12; step++) {
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused != null &&
            find
                .ancestor(
                  of: find.byElementPredicate((element) => element == focused),
                  matching: devices,
                )
                .evaluate()
                .isNotEmpty) {
          break;
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      final focusContext = FocusManager.instance.primaryFocus?.context;
      expect(focusContext, isNotNull);
      expect(
        find.ancestor(
          of: find.byElementPredicate((element) => element == focusContext),
          matching: devices,
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(activations, 2);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'support enlarges original and reports denied save without success',
    (tester) async {
      final c = AuthPresentationController();
      final gallery = _DeniedGallery();
      await tester.pumpWidget(
        _app(
          c,
          settings: SettingsScreen(
            onManageIdentity: () {},
            onManageSecurity: () {},
            supportGalleryWriter: gallery,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _open(tester, 'support');
      await tester.tap(find.byKey(const ValueKey('settings-support-code')));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(
        (tester
                    .widget<Image>(
                      find.descendant(
                        of: find.byType(InteractiveViewer),
                        matching: find.byType(Image),
                      ),
                    )
                    .image
                as AssetImage)
            .assetName,
        'assets/support/alipay-receive.jpg',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-support-save')),
        180,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('settings-support-page')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('settings-support-save')));
      await tester.pumpAndSettle();
      expect(gallery.requests, 1);
      expect(gallery.writes, 0);
      expect(find.text('请允许访问相册后重试'), findsOneWidget);
      expect(find.text('收款码已保存到相册'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'settings removes private notifications; closure has its own route',
    (tester) async {
      final c = AuthPresentationController();
      var devices = 0, account = 0, closure = 0, identities = 0, blacklist = 0;
      await tester.pumpWidget(
        _app(
          c,
          settings: SettingsScreen(
            onManageIdentity: () => identities++,
            onManageSecurity: () => devices++,
            onManageAccount: () => account++,
            onCloseAccount: () => closure++,
            onBlacklist: () => blacklist++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in [
        'devices',
        'account',
        'closure',
        'identity',
        'blacklist',
      ]) {
        await _open(tester, key);
      }
      expect(
        [devices, account, closure, identities, blacklist],
        [1, 1, 1, 1, 1],
      );
      expect(
        find.byKey(const ValueKey('settings-notifications')),
        findsNothing,
      );
      expect(find.byType(TextField), findsNothing);
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
        expect(tile.leading, isNotNull);
        expect(tile.subtitle, isNull);
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'four languages apply without replacing the route and persist locally',
    (tester) async {
      final vault = IdentityTestVault();
      final c = AuthPresentationController(preferences: vault);
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      await _open(tester, 'language');
      final route = ModalRoute.of(
        tester.element(find.byKey(const ValueKey('settings-language-page'))),
      );
      for (final language in AppLanguage.values) {
        await tester.tap(
          find.byKey(ValueKey('settings-language-${language.code}')),
        );
        await tester.pumpAndSettle();
        expect(c.language, language);
        expect(
          ModalRoute.of(
            tester.element(
              find.byKey(const ValueKey('settings-language-page')),
            ),
          ),
          same(route),
        );
        expect(
          Localizations.localeOf(
            tester.element(
              find.byKey(const ValueKey('settings-language-page')),
            ),
          ),
          language.locale,
        );
        await c.preferencesSaved;
        final restored = AuthPresentationController(preferences: vault);
        await restored.load();
        expect(restored.language, language);
        restored.dispose();
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'feedback only lists and copies the supplied email without sending',
    (tester) async {
      final c = AuthPresentationController();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      await _open(tester, 'feedback');
      expect(find.text('zewbby666@gmail.com'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-feedback-submit')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('settings-feedback-copy')));
      await tester.pumpAndSettle();
      expect(copied, 'zewbby666@gmail.com');
      expect(find.text('邮箱已复制'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'support uses original asset and the requested caption in four languages',
    (tester) async {
      final c = AuthPresentationController();
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      await _open(tester, 'support');
      expect(
        find.byKey(const ValueKey('settings-support-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-support-code')),
        findsOneWidget,
      );
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('settings-support-code')),
          matching: find.byType(Image),
        ),
      );
      expect(
        (image.image as AssetImage).assetName,
        'assets/support/alipay-receive.jpg',
      );
      for (final language in AppLanguage.values) {
        c.setLanguage(language);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('settings-support-save')),
          180,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('settings-support-page')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('settings-support-purpose')),
              )
              .data,
          translateUi('您的支持将全数用于开发与维护SpeechFUL项目', language),
        );
        expect(
          find.byKey(const ValueKey('settings-support-save')),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
