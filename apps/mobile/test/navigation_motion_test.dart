import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';
import 'package:hnuhole_mobile/src/design_system/motion.dart';
import 'package:hnuhole_mobile/src/design_system/motion_routes.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/navigation/app_navigation.dart';
import 'package:hnuhole_mobile/src/navigation/feed_chrome.dart';
import 'package:hnuhole_mobile/src/navigation/home_side_menu.dart';
import 'package:hnuhole_mobile/src/navigation/primary_tabs.dart';

class _RetainedPage extends StatefulWidget {
  const _RetainedPage(this.name, this.ticks);
  final String name;
  final Map<String, int> ticks;
  @override
  State<_RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<_RetainedPage>
    with SingleTickerProviderStateMixin {
  final scroll = ScrollController();
  late final ticker = createTicker((_) {
    widget.ticks.update(widget.name, (value) => value + 1, ifAbsent: () => 1);
  })..start();
  @override
  void initState() {
    super.initState();
    ticker;
  }

  @override
  void dispose() {
    ticker.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: ValueKey('list:${widget.name}'),
    controller: scroll,
    itemExtent: 56,
    itemCount: 80,
    itemBuilder: (_, index) => Text('${widget.name}:$index'),
  );
}

class _MediaBuildProbe extends StatefulWidget {
  const _MediaBuildProbe(this.name, this.builds);
  final String name;
  final Map<String, int> builds;

  @override
  State<_MediaBuildProbe> createState() => _MediaBuildProbeState();
}

class _MediaBuildProbeState extends State<_MediaBuildProbe> {
  late MediaQueryData media;

  @override
  Widget build(BuildContext context) {
    widget.builds.update(widget.name, (value) => value + 1, ifAbsent: () => 1);
    media = MediaQuery.of(context);
    return SizedBox.expand(
      key: ValueKey('media-probe:${widget.name}'),
      child: Text(widget.name),
    );
  }
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'tabs restore themed status bars after viewer and app bar ($brightness)',
      (tester) async {
        tester.view.physicalSize = const Size(400, 720);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.reset);
        final navigator = GlobalKey<NavigatorState>();
        var currentBrightness = brightness;
        late StateSetter updateTheme;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              updateTheme = setState;
              return MaterialApp(
                navigatorKey: navigator,
                theme: HhTelegramTheme.create(currentBrightness),
                home: PrimaryTabs(
                  window: ('account', 1),
                  onSelected: (_) {},
                  builders: {
                    for (final destination in AppDestination.values)
                      destination: (_) =>
                          const Scaffold(body: Text('home surface')),
                  },
                ),
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        // Match RenderView's annotation lookup at the status bar's center.
        SystemUiOverlayStyle? statusStyle() => tester
            .binding
            .renderViews
            .single
            .debugLayer!
            .find<SystemUiOverlayStyle>(const Offset(200, 12));
        final expectedIcons = brightness == Brightness.light
            ? Brightness.dark
            : Brightness.light;
        expect(statusStyle()?.statusBarIconBrightness, expectedIcons);
        expect(statusStyle()?.statusBarBrightness, brightness);
        expect(statusStyle()?.statusBarColor, Colors.transparent);
        expect(statusStyle()?.systemNavigationBarColor, isNull);
        expect(statusStyle()?.systemNavigationBarIconBrightness, isNull);
        final controller = ViewerController(
          items: [
            ViewerItem.provider(
              id: 'status-bar-fixture',
              provider: MemoryImage(
                File(
                  '../../packages/image_viewer/example/assets/fixtures/ordinary.png',
                ).readAsBytesSync(),
              ),
              pixelSize: const Size(640, 480),
              saveAllowed: false,
            ),
          ],
        );
        navigator.currentState!.push(
          HnuImageViewerRoute(
            builder: (_) => HnuImageViewer(
              controller: controller,
              enableAndroidSaving: false,
              onClosed: (_) => navigator.currentState!.pop(),
            ),
          ),
        );
        for (var frame = 0; frame < 10; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 40));
        }
        expect(find.byType(HnuImageViewer), findsOneWidget);
        expect(statusStyle()?.statusBarIconBrightness, Brightness.light);
        await tester.tap(find.byKey(const ValueKey('viewer-close')));
        await tester.pumpAndSettle();
        expect(find.byType(HnuImageViewer), findsNothing);
        expect(statusStyle()?.statusBarIconBrightness, expectedIcons);
        expect(statusStyle()?.statusBarBrightness, brightness);
        controller.dispose();
        const appBarStyle = SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: const Text('upper route'),
                systemOverlayStyle: appBarStyle,
              ),
              body: const Text('app bar surface'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(statusStyle()?.statusBarIconBrightness, Brightness.light);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(statusStyle()?.statusBarIconBrightness, expectedIcons);
        updateTheme(
          () => currentBrightness = brightness == Brightness.light
              ? Brightness.dark
              : Brightness.light,
        );
        await tester.pumpAndSettle();
        expect(statusStyle()?.statusBarIconBrightness, brightness);
        expect(statusStyle()?.statusBarBrightness, currentBrightness);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'chrome frames preserve visible and retained hidden tab widgets',
    (tester) async {
      final tabs = GlobalKey<PrimaryTabsState>();
      final builds = <String, int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: PrimaryTabs(
            key: tabs,
            window: ('account', 1),
            onSelected: (value) => tabs.currentState!.select(value),
            builders: {
              for (final destination in AppDestination.values)
                destination: (_) => _MediaBuildProbe(destination.name, builds),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      tabs.currentState!.select(AppDestination.directMessages);
      await tester.pumpAndSettle();
      tabs.currentState!.select(AppDestination.home);
      await tester.pumpAndSettle();
      final home = find.byKey(const ValueKey('media-probe:home'));
      final viewport = tester.getSize(home);
      final before = Map<String, int>.of(builds);
      final chrome = FeedChromeScope.maybeOf(tester.element(home))!;
      final navigation = find.byType(FeedNavigation);
      final barHeight = tester.getSize(navigation).height;
      chrome.scroll(40, 100);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getSize(home), viewport);
        expect(builds, before, reason: 'chrome-only frame $i');
        if (i == 5) {
          expect(
            tester.getSize(navigation).height,
            inExclusiveRange(0, barHeight),
          );
        }
      }
      expect(tester.getSize(navigation).height, 0);
      chrome.show();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getSize(home), viewport);
        expect(builds, before, reason: 'chrome return frame $i');
      }
      expect(tester.getSize(navigation).height, barHeight);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stable tab subtree still receives real media and authority changes',
    (tester) async {
      final tabs = GlobalKey<PrimaryTabsState>();
      final builds = <String, int>{};
      late StateSetter update;
      var window = ('account', 1);
      var padding = 24.0;
      var textScale = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: EdgeInsets.only(bottom: padding),
                  viewPadding: EdgeInsets.only(bottom: padding),
                  textScaler: TextScaler.linear(textScale),
                ),
                child: PrimaryTabs(
                  key: tabs,
                  window: window,
                  onSelected: (value) => tabs.currentState!.select(value),
                  builders: {
                    for (final destination in AppDestination.values)
                      destination: (_) =>
                          _MediaBuildProbe(destination.name, builds),
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final original = tester.state<_MediaBuildProbeState>(
        find.byType(_MediaBuildProbe),
      );
      tabs.currentState!.select(AppDestination.directMessages);
      await tester.pumpAndSettle();
      expect(
        tester.widget<HhAppNavigation>(find.byType(HhAppNavigation)).selected,
        AppDestination.directMessages,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.state<_MediaBuildProbeState>(find.byType(_MediaBuildProbe)),
        same(original),
      );
      update(() {
        padding = 32;
        textScale = 1.4;
      });
      await tester.pumpAndSettle();
      expect(original.media.padding.bottom, 32);
      expect(original.media.textScaler.scale(10), 14);
      final oldSize = original.media.size;
      tester.view.physicalSize = const Size(1000, 700);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(original.media.size, isNot(oldSize));
      expect(
        tester.state<_MediaBuildProbeState>(find.byType(_MediaBuildProbe)),
        same(original),
      );
      update(() => window = ('other-account', 2));
      await tester.pumpAndSettle();
      expect(
        tester.state<_MediaBuildProbeState>(find.byType(_MediaBuildProbe)),
        isNot(same(original)),
      );
      expect(
        find.byKey(
          const ValueKey('media-probe:directMessages'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(
        tester.widget<HhAppNavigation>(find.byType(HhAppNavigation)).selected,
        AppDestination.home,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'Android predictive back cancellation and commit remain available ($reduced)',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: HhTelegramTheme.create(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(accessibleNavigation: reduced),
              child: child!,
            ),
            home: const Scaffold(body: Text('predictive root')),
          ),
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('predictive detail')),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> send(
          String method, [
          Map<String, dynamic>? arguments,
        ]) async {
          await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'flutter/backgesture',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, arguments),
            ),
            (_) {},
          );
        }

        for (final commit in [false, true]) {
          await send('startBackGesture', {
            'touchOffset': <double>[5, 300],
            'progress': 0.0,
            'swipeEdge': 0,
          });
          await tester.pump();
          await send('updateBackGestureProgress', {
            'touchOffset': <double>[100, 300],
            'progress': .35,
            'swipeEdge': 0,
          });
          await tester.pumpAndSettle();
          await send(commit ? 'commitBackGesture' : 'cancelBackGesture');
          await tester.pumpAndSettle();
          expect(navigator.currentState!.canPop(), !commit);
          expect(
            find.text(commit ? 'predictive root' : 'predictive detail'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  for (final reduced in [false, true]) {
    testWidgets(
      'rapid tab switches preserve state, scroll and tickers ($reduced)',
      (tester) async {
        final tabs = GlobalKey<PrimaryTabsState>();
        final ticks = <String, int>{};
        await tester.pumpWidget(
          MaterialApp(
            theme: HhTelegramTheme.create(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(accessibleNavigation: reduced),
              child: child!,
            ),
            home: PrimaryTabs(
              key: tabs,
              window: ('account', 1),
              onSelected: (value) => tabs.currentState!.select(value),
              builders: {
                for (final destination in AppDestination.values)
                  destination: (_) => _RetainedPage(destination.name, ticks),
              },
            ),
          ),
        );
        await tester.pump();
        final home = tester.state<_RetainedPageState>(
          find.byType(_RetainedPage),
        );
        home.scroll.jumpTo(340);
        await tester.pump();
        for (final destination in [
          AppDestination.personal,
          AppDestination.messages,
          AppDestination.directMessages,
          AppDestination.personal,
        ]) {
          await tester.tap(
            find.byKey(ValueKey('destination:${destination.name}')),
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.byType(_RetainedPage), findsOneWidget);
          expect(find.byType(HhAppNavigation), findsOneWidget);
          expect(
            tester
                .widget<HhAppNavigation>(find.byType(HhAppNavigation))
                .selected,
            destination,
          );
          final page = tester.widget<_RetainedPage>(find.byType(_RetainedPage));
          expect(page.name, destination.name);
          await tester.pump(const Duration(milliseconds: 16));
          final glyph = tester
              .widgetList<CustomPaint>(
                find.descendant(
                  of: find.byKey(ValueKey('destination:${destination.name}')),
                  matching: find.byType(CustomPaint),
                ),
              )
              .map((paint) => paint.painter)
              .whereType<HhNavigationGlyph>()
              .single;
          expect(
            glyph.fillProgress,
            reduced ? 1.0 : inExclusiveRange(0.0, 1.0),
          );
          final selectedSemantics = find.ancestor(
            of: find.byKey(ValueKey('destination:${destination.name}')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.selected == true,
            ),
          );
          expect(
            tester
                .getSemantics(selectedSemantics.first)
                .getSemanticsData()
                .flagsCollection
                .isSelected
                .toBoolOrNull(),
            isTrue,
          );
        }
        final hiddenTicks = ticks['home'];
        await tester.pump(const Duration(milliseconds: 80));
        expect(ticks['home'], hiddenTicks);
        expect(home.scroll.offset, 340);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(
          tester.state<_RetainedPageState>(find.byType(_RetainedPage)),
          same(home),
        );
        expect(home.scroll.offset, 340);
        await tester.pump(const Duration(milliseconds: 20));
        expect(ticks['home'], greaterThan(hiddenTicks!));
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'side menu settles immediately when reduced motion changes mid-flight',
    (tester) async {
      final menu = GlobalKey<HomeSideMenuState>();
      final media = ValueNotifier(const MediaQueryData(size: Size(800, 600)));
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: media,
            builder: (context, value, _) => MediaQuery(
              data: value,
              child: HomeSideMenu(
                key: menu,
                enabled: true,
                menuBuilder: (_) =>
                    const Material(child: Text('settings surface')),
                child: Scaffold(body: TextField(focusNode: focus)),
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      menu.currentState!.open();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(focus.hasFocus, isFalse);
      final surface = find.byKey(const ValueKey('home-menu-home-surface'));
      final moving = tester.widget<Transform>(surface).transform.storage[12];
      expect(moving, greaterThan(0));
      expect(moving, lessThan(768));
      media.value = media.value.copyWith(accessibleNavigation: true);
      await tester.pump();
      expect(tester.widget<Transform>(surface).transform.storage[12], 768);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(tester.widget<Transform>(surface).transform.storage[12], 0);
      expect(find.text('settings surface'), findsNothing);
      media.value = media.value.copyWith(disableAnimations: true);
      menu.currentState!.open();
      await tester.pump();
      expect(tester.widget<Transform>(surface).transform.storage[12], 768);
      menu.currentState!.close();
      await tester.pump();
      expect(tester.widget<Transform>(surface).transform.storage[12], 0);
      await tester.pumpWidget(const SizedBox());
      media.dispose();
      focus.dispose();
    },
  );

  for (final reduced in [false, true]) {
    testWidgets('platform routes preserve Cupertino swipe back ($reduced)', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: HhTelegramTheme.applyAppearance(
            ThemeData(platform: TargetPlatform.iOS),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(accessibleNavigation: reduced),
            child: child!,
          ),
          home: const Scaffold(body: Text('retained root')),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('detail page'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('detail page'), findsOneWidget);
      await tester.dragFrom(const Offset(1, 280), const Offset(680, 0));
      await tester.pumpAndSettle();
      expect(find.text('retained root'), findsOneWidget);
      expect(navigator.currentState!.canPop(), isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final accessible in [false, true]) {
    testWidgets(
      'reduced pop shows its destination immediately (accessible=$accessible)',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: HhTelegramTheme.applyAppearance(
              ThemeData(platform: TargetPlatform.iOS),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: !accessible,
                accessibleNavigation: accessible,
              ),
              child: child!,
            ),
            home: const Scaffold(body: Text('return destination')),
          ),
        );
        const detail = ValueKey('reduced-pop-detail');
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(key: detail, body: Text('outgoing detail')),
          ),
        );
        await tester.pumpAndSettle();
        navigator.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          tester.getTopLeft(find.byKey(detail)).dx,
          greaterThanOrEqualTo(
            tester.view.physicalSize.width / tester.view.devicePixelRatio,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('return destination'), findsOneWidget);
        expect(navigator.currentState!.canPop(), isFalse);
      },
    );
  }

  testWidgets(
    'reduced route transitions use settled frames and keep platform durations',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final base = ThemeData(platform: TargetPlatform.iOS);
      final theme = HhTelegramTheme.applyAppearance(base);
      expect(
        theme
            .pageTransitionsTheme
            .builders[TargetPlatform.iOS]!
            .transitionDuration,
        base
            .pageTransitionsTheme
            .builders[TargetPlatform.iOS]!
            .transitionDuration,
      );
      final media = ValueNotifier(
        const MediaQueryData(accessibleNavigation: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: theme,
          builder: (context, child) => ValueListenableBuilder(
            valueListenable: media,
            builder: (context, value, _) =>
                MediaQuery(data: value, child: child!),
          ),
          home: const Scaffold(body: Text('root')),
        ),
      );
      const detailKey = ValueKey('detail-content');
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(key: detailKey, body: Text('settled detail')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.getTopLeft(find.byKey(detailKey)), Offset.zero);
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.getTopLeft(find.byKey(detailKey)), Offset.zero);
      final context = tester.element(find.byKey(detailKey));
      expect(HhMotionRoutes.popup(context).duration, Duration.zero);
      expect(HhMotionRoutes.sheet(context).reverseDuration, Duration.zero);
      media.value = const MediaQueryData();
      await tester.pumpAndSettle();
      expect(HhMotionRoutes.popup(context).duration, HhMotion.quick);
      await tester.pumpWidget(const SizedBox());
      media.dispose();
    },
  );
}
