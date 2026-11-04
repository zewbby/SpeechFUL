import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/navigation/home_side_menu.dart';

Future<void> _show(
  WidgetTester tester, {
  required ValueNotifier<bool> enabled,
  required ValueNotifier<int> window,
  required VoidCallback blacklist,
  required VoidCallback devices,
  required ValueChanged<double> mediaDrag,
  required ScrollController scroll,
}) => tester.pumpWidget(
  MaterialApp(
    home: ValueListenableBuilder<int>(
      valueListenable: window,
      builder: (context, generation, _) => ValueListenableBuilder<bool>(
        valueListenable: enabled,
        builder: (context, available, _) => HomeSideMenu(
          key: ValueKey(generation),
          enabled: available,
          menuBuilder: (context) => SettingsScreen(
            onClose: () => HomeSideMenuScope.maybeOf(context)?.close(),
            onManageIdentity: () {},
            onManageSecurity: devices,
            onBlacklist: blacklist,
          ),
          child: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  key: const ValueKey('open-settings'),
                  tooltip: '打开设置',
                  onPressed: () => HomeSideMenuScope.maybeOf(context)?.open(),
                  icon: const Icon(Icons.menu),
                ),
              ),
              body: ListView(
                controller: scroll,
                children: [
                  GestureDetector(
                    key: const ValueKey('horizontal-media'),
                    onHorizontalDragUpdate: (details) =>
                        mediaDrag(details.delta.dx),
                    child: const SizedBox(
                      height: 180,
                      child: Center(child: Text('帖子图片')),
                    ),
                  ),
                  for (var i = 0; i < 25; i++)
                    SizedBox(height: 80, child: Text('帖子 $i')),
                ],
              ),
              bottomNavigationBar: const SizedBox(
                key: ValueKey('home-navigation'),
                height: 64,
                child: Text('首页导航'),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'avatar opens settings directly, moves the full home surface, isolates semantics and back closes first',
    (tester) async {
      final enabled = ValueNotifier(true), window = ValueNotifier(1);
      final scroll = ScrollController();
      final semantics = tester.ensureSemantics();
      await _show(
        tester,
        enabled: enabled,
        window: window,
        blacklist: () {},
        devices: () {},
        mediaDrag: (_) {},
        scroll: scroll,
      );
      expect(find.byType(SettingsScreen), findsNothing);
      final before = tester.getTopLeft(
        find.byKey(const ValueKey('home-navigation')),
      );
      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('home-menu-settings')), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('home-navigation'))).dx,
        greaterThan(before.dx + 300),
      );
      final language = tester
          .getSemantics(find.byKey(const ValueKey('settings-language')))
          .getSemanticsData();
      expect(language.label, '语言');
      expect(language.hasAction(SemanticsAction.tap), isTrue);
      expect(
        tester
            .binding
            .renderViews
            .single
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!
            .toStringDeep(),
        isNot(contains('tooltip: "打开设置"')),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('home-navigation'))),
        before,
      );
      expect(
        tester.getSemantics(find.byTooltip('打开设置')).getSemanticsData().tooltip,
        '打开设置',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      enabled.dispose();
      window.dispose();
      scroll.dispose();
    },
  );

  testWidgets(
    'ordinary content and top navigation left swipes open directly, media and vertical scroll remain independent',
    (tester) async {
      final enabled = ValueNotifier(true), window = ValueNotifier(1);
      final scroll = ScrollController();
      var mediaTravel = 0.0;
      await _show(
        tester,
        enabled: enabled,
        window: window,
        blacklist: () {},
        devices: () {},
        mediaDrag: (delta) => mediaTravel += delta.abs(),
        scroll: scroll,
      );
      await tester.drag(
        find.byKey(const ValueKey('horizontal-media')),
        const Offset(180, 0),
      );
      await tester.pumpAndSettle();
      expect(mediaTravel, greaterThan(100));
      expect(find.byType(SettingsScreen), findsNothing);
      await tester.dragFrom(const Offset(700, 400), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('settings-list')),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      await tester.dragFrom(const Offset(700, 30), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(300, 420), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(100));
      expect(find.byType(SettingsScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      enabled.dispose();
      window.dispose();
      scroll.dispose();
    },
  );

  testWidgets(
    'rapid different settings consume once, stale pointers and a disabled drag cannot open a new window',
    (tester) async {
      final enabled = ValueNotifier(true), window = ValueNotifier(1);
      final scroll = ScrollController();
      var blacklist = 0, devices = 0;
      await _show(
        tester,
        enabled: enabled,
        window: window,
        blacklist: () => blacklist++,
        devices: () => devices++,
        mediaDrag: (_) {},
        scroll: scroll,
      );
      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-blacklist')));
      await tester.tap(find.byKey(const ValueKey('settings-devices')));
      await tester.pumpAndSettle();
      expect(blacklist, 1);
      expect(devices, 0);
      final oldTile = tester.widget<ListTile>(
        find.byKey(const ValueKey('settings-blacklist')),
      );
      final stalePointer = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('settings-blacklist'))),
      );
      window.value = 2;
      await tester.pumpAndSettle();
      await stalePointer.up();
      oldTile.onTap!();
      await tester.pumpAndSettle();
      expect(blacklist, 1);
      expect(find.byType(SettingsScreen), findsNothing);
      final drag = await tester.startGesture(const Offset(700, 400));
      await drag.moveBy(const Offset(220, 0));
      await tester.pump();
      enabled.value = false;
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(
        tester
            .widget<GestureDetector>(
              find.byKey(const ValueKey('home-menu-swipe-surface')),
            )
            .onHorizontalDragUpdate,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      enabled.dispose();
      window.dispose();
      scroll.dispose();
    },
  );
}
