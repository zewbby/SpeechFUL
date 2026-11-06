import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/design_system/detail_components.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/posts/x_feed.dart';

Future<List<int>> pixels(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List().toList();
  }))!;
}

void main() {
  testWidgets(
    'detail feedback follows rapid intents without delaying action or semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final boundary = GlobalKey();
      var selected = false;
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: HhTelegramTheme.create(Brightness.light),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: StatefulBuilder(
                  builder: (context, update) => DetailAction(
                    buttonKey: const ValueKey('detail-action'),
                    action: FeedAction.like,
                    label: '喜欢',
                    selected: selected,
                    count: selected ? '13' : '12',
                    onPressed: () => update(() {
                      actions++;
                      selected = !selected;
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('detail-action'));
      final size = tester.getSize(button);
      expect(size.height, greaterThanOrEqualTo(48));
      final before = await pixels(tester, boundary);
      await tester.tap(button);
      await tester.pump();
      expect(actions, 1);
      expect(find.bySemanticsLabel('喜欢，13'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 60));
      final during = await pixels(tester, boundary);
      await tester.pumpAndSettle();
      final after = await pixels(tester, boundary);
      expect(during, isNot(equals(before)));
      expect(during, isNot(equals(after)));
      expect(tester.getSize(button), size);
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(button);
      await tester.pump();
      expect(actions, 3);
      expect(find.bySemanticsLabel('喜欢，13'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(await pixels(tester, boundary), after);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'reduced-motion detail changes are immediate at large text in RTL and dark mode',
    (tester) async {
      var selected = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: HhTelegramTheme.create(Brightness.dark),
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Center(
                  child: StatefulBuilder(
                    builder: (context, update) => DetailAction(
                      buttonKey: const ValueKey('reduced-action'),
                      action: FeedAction.bookmark,
                      label: '收藏',
                      count: selected ? '١٠٠٠' : '٩٩٩',
                      selected: selected,
                      onPressed: () => update(() => selected = !selected),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('reduced-action')));
      await tester.pump();
      expect(find.text('١٠٠٠'), findsOneWidget);
      expect(find.text('٩٩٩'), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'feed action motion keeps its hit target and never opens its parent post',
    (tester) async {
      var opens = 0;
      var likes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: HhTelegramTheme.create(Brightness.light),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => HhXPostItem(
                post: FeedPostView(
                  id: 'motion-post',
                  authorId: 'author',
                  authorName: '同学',
                  elapsed: '刚刚',
                  title: '操作反馈',
                  likes: likes,
                  liked: likes.isOdd,
                  availableActions: const {FeedAction.like},
                ),
                mediaBuilder: (_, _) => const SizedBox.shrink(),
                onPost: () => opens++,
                onAuthor: () {},
                onMenu: () {},
                onMedia: (_) {},
                onAction: (_) => update(() => likes++),
              ),
            ),
          ),
        ),
      );
      final button = find.byKey(const ValueKey('like:motion-post'));
      final size = tester.getSize(button);
      final gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 80));
      expect(likes, 0);
      expect(tester.getSize(button), size);
      await gesture.up();
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      expect(likes, 2);
      expect(opens, 0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
