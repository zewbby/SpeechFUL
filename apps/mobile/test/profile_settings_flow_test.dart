import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/localization/app_localizations.dart';
import 'package:hnuhole_mobile/src/posts/x_feed.dart';

import 'feed_ui_test.dart' as feed;
import 'login_home_navigation_test.dart' as navigation;
import 'login_home_test_support.dart';

const _render = ValueKey('profile-settings-flow-render');
const _timeline = ValueKey('production-feed');

Future<Finder> _setting(WidgetTester tester, String title) async {
  final scrollable = find.descendant(
    of: find.byKey(const ValueKey('settings-list')),
    matching: find.byType(Scrollable),
  );
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  final item = find.text(title);
  await tester.scrollUntilVisible(item, 160, scrollable: scrollable);
  await tester.pumpAndSettle();
  return item;
}

Future<void> _openSettings(WidgetTester tester, {bool swipe = false}) async {
  if (swipe) {
    await tester.drag(find.byKey(_timeline), const Offset(300, 0));
  } else {
    await tester.tap(find.byKey(const ValueKey('feed-account')));
  }
  await tester.pumpAndSettle();
  expect(find.byType(SettingsScreen), findsOneWidget);
  expect(find.byKey(const ValueKey('home-menu-settings')), findsNothing);
  expect(find.byKey(const ValueKey('settings-search')), findsNothing);
  expect(find.byType(TextField), findsNothing);
  final first = tester.widget<ListTile>(
    find.byKey(const ValueKey('settings-language')),
  );
  expect(first.subtitle, isNull);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_render),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/profile-settings-render');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _realFonts() async {
  for (final face in ['Regular', 'Medium', 'Bold']) {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-$face.ttf'))).load();
  }
  await (FontLoader(
    'HhNotoSansSC',
  )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

void main() {
  testWidgets(
    'four languages fit narrow settings and preserve support purpose',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _realFonts();
      final presentation = AuthPresentationController();
      final fixture = HomeTestFixture();
      await tester.pumpWidget(
        RepaintBoundary(
          key: _render,
          child: await fixture.create(presentation: presentation),
        ),
      );
      await tester.pumpAndSettle();
      await _openSettings(tester, swipe: true);
      for (final language in AppLanguage.values) {
        presentation.setLanguage(language);
        await tester.pumpAndSettle();
        await _setting(tester, translateUi('语言', language));
        await _capture(tester, '${language.code}-settings-narrow');
        final support = await _setting(tester, translateUi('支持我们', language));
        await tester.tap(support);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('settings-support-purpose')),
          180,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('settings-support-page')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          find.text(translateUi('您的支持将全数用于开发与维护SpeechFUL项目', language)),
          findsOneWidget,
        );
        await _capture(tester, '${language.code}-support-narrow');
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets(
    'settings round trip retains channel, latest, loaded posts and reading position',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = HomeTestFixture();
      await tester.pumpWidget(await fixture.create());
      await tester.pumpAndSettle();
      final channel = fixture.directory.channels.last.id;
      fixture.postApi.items = [
        for (var i = 0; i < 20; i++)
          feed.post(
            id: '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
            channel: channel,
            title: '设置往返阅读位置 $i',
          ),
      ];
      await navigation.pickChannel(tester, channel);
      await tester.tap(find.byKey(const ValueKey('feed-latest')));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(_timeline), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(_timeline), const Offset(0, 80));
      await tester.pumpAndSettle();
      final scroll = tester.widget<ListView>(find.byKey(_timeline)).controller!;
      final position = scroll.offset;
      expect(position, greaterThan(0));
      final home = tester.state(find.byType(FeedScreen));
      final posts = fixture.posts.timelineItems
          .map((item) => item.postId)
          .toList();
      await _openSettings(tester, swipe: true);
      final language = await _setting(tester, '语言');
      expect(language, findsOneWidget);
      expect(find.byKey(const ValueKey('settings-blacklist')), findsOneWidget);
      await tester.tap(language);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(identical(tester.state(find.byType(FeedScreen)), home), isTrue);
      expect(fixture.posts.timelineChannelId, channel);
      expect(
        tester.widget<HhXPostFeed>(find.byType(HhXPostFeed)).latestSelected,
        isTrue,
      );
      expect(fixture.posts.timelineItems.map((item) => item.postId), posts);
      expect(scroll.offset, closeTo(position, .01));
      expect(find.byKey(const ValueKey('home-side-menu')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('real-font direct settings and new frontends fit both themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _realFonts();
    for (final brightness in Brightness.values) {
      tester.view.physicalSize = const Size(393, 852);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      final fixture = HomeTestFixture();
      final root = await fixture.create();
      await tester.pumpWidget(RepaintBoundary(key: _render, child: root));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('destination:personal')));
      await tester.pumpAndSettle();
      await _capture(tester, '${brightness.name}-profile');
      await tester.tap(find.byKey(const ValueKey('destination:home')));
      await tester.pumpAndSettle();
      await _openSettings(tester);
      await _capture(tester, '${brightness.name}-settings');
      for (final title in ['语言', '黑名单', '设备管理', '账号注销', '意见反馈', '支持我们']) {
        final item = await _setting(tester, title);
        expect(item, findsOneWidget);
        final row = tester.widget<ListTile>(
          find.ancestor(of: item, matching: find.byType(ListTile)),
        );
        expect(
          row.subtitle,
          isNull,
          reason: '$title only shows its icon and name',
        );
      }
      for (final title in ['语言', '意见反馈', '支持我们']) {
        final item = await _setting(tester, title);
        await tester.tap(item);
        await tester.pumpAndSettle();
        await _capture(tester, '${brightness.name}-$title');
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('settings-list')),
        const Offset(0, 1600),
      );
      await tester.pumpAndSettle();
      await _capture(tester, '${brightness.name}-settings-large-text');
      for (final title in ['语言', '意见反馈', '支持我们']) {
        final item = await _setting(tester, title);
        await tester.tap(item);
        await tester.pumpAndSettle();
        await _capture(tester, '${brightness.name}-$title-large-text');
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
