import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/design_system/motion.dart';
import 'package:hnuhole_mobile/src/design_system/motion_routes.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/navigation/app_navigation.dart';
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

void main() {
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
