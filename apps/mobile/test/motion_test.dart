import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/design_system/motion.dart';

Widget host(
  Widget child, {
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: disableAnimations,
      accessibleNavigation: accessibleNavigation,
    ),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

double pressScale(WidgetTester tester) => tester
    .widget<Transform>(
      find
          .descendant(
            of: find.byType(HhPressFeedback),
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform
    .entry(0, 0);

void main() {
  testWidgets('system accessibility preferences reduce shared durations', (
    tester,
  ) async {
    for (final preference in [0, 1, 2]) {
      late bool reduced;
      late Duration duration;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              reduced = HhMotion.reduced(context);
              duration = HhMotion.duration(context, HhMotion.quick);
              return const SizedBox();
            },
          ),
          disableAnimations: preference == 1,
          accessibleNavigation: preference == 2,
        ),
      );
      expect(reduced, preference != 0);
      expect(duration, preference == 0 ? HhMotion.quick : Duration.zero);
    }
  });

  testWidgets('native button owns activation, press layout and hit area', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      host(
        HhPressFeedback(
          builder: (context, states) => TextButton(
            key: const Key('button'),
            statesController: states,
            onPressed: () => activations++,
            child: const Text('Like'),
          ),
        ),
      ),
    );
    expect(tester.hasRunningAnimations, isFalse);
    final finder = find.byKey(const Key('button'));
    final size = tester.getSize(finder);
    // This point lies in the original target, outside the shrunken visual.
    final edge = tester.getTopLeft(finder) + Offset(1, size.height / 2);
    final gesture = await tester.startGesture(edge);
    await tester.pump();
    await tester.pump(HhMotion.pressIn);
    expect(activations, 0);
    expect(pressScale(tester), closeTo(.96, .0001));
    expect(tester.getSize(finder), size);
    await gesture.up();
    expect(activations, 1);
    await tester.pumpAndSettle();
    expect(pressScale(tester), 1);
  });

  testWidgets('drag cancellation releases feedback without activation', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      host(
        HhPressFeedback(
          builder: (context, states) => IconButton(
            statesController: states,
            onPressed: () => activations++,
            icon: const Icon(Icons.favorite),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(IconButton)),
    );
    await tester.pump();
    await tester.pump(HhMotion.pressIn);
    expect(pressScale(tester), closeTo(.96, .0001));
    await gesture.moveBy(const Offset(200, 100));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(activations, 0);
    expect(pressScale(tester), 1);
  });

  testWidgets('disabling a pressed button releases and blocks activation', (
    tester,
  ) async {
    var enabled = true;
    var activations = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return HhPressFeedback(
              enabled: enabled,
              builder: (context, states) => TextButton(
                statesController: states,
                onPressed: enabled ? () => activations++ : null,
                child: const Text('Send'),
              ),
            );
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextButton)),
    );
    await tester.pump();
    await tester.pump(HhMotion.pressIn);
    rebuild(() => enabled = false);
    await tester.pumpAndSettle();
    expect(pressScale(tester), 1);
    await gesture.up();
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(activations, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native keyboard activation remains available', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var activations = 0;
    await tester.pumpWidget(
      host(
        HhPressFeedback(
          builder: (context, states) => TextButton(
            focusNode: focus,
            statesController: states,
            onPressed: () => activations++,
            child: const Text('Open'),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(HhMotion.pressIn);
    expect(activations, 1);
    expect(pressScale(tester), lessThan(1));
    await tester.pumpAndSettle();
    expect(pressScale(tester), 1);
  });

  testWidgets('rebuilds do not prolong press and native disabling releases', (
    tester,
  ) async {
    var enabled = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return HhPressFeedback(
              builder: (context, states) => TextButton(
                statesController: states,
                onPressed: enabled ? () {} : null,
                child: const Text('Like'),
              ),
            );
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextButton)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 35));
    rebuild(() {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 35));
    expect(pressScale(tester), closeTo(.96, .0001));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    rebuild(() {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    expect(pressScale(tester), closeTo(1, .0001));

    final cancelled = await tester.startGesture(
      tester.getCenter(find.byType(TextButton)),
    );
    await tester.pump();
    await tester.pump(HhMotion.pressIn);
    rebuild(() => enabled = false);
    await tester.pumpAndSettle();
    expect(pressScale(tester), 1);
    await cancelled.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection starts at target and reverses from visible progress', (
    tester,
  ) async {
    var selected = true;
    late StateSetter rebuild;
    var progress = -1.0;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return HhAnimatedSelection(
              selected: selected,
              builder: (context, value) {
                progress = value;
                return const Icon(Icons.favorite);
              },
            );
          },
        ),
      ),
    );
    expect(progress, 1);
    expect(tester.hasRunningAnimations, isFalse);
    rebuild(() => selected = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 65));
    final interrupted = progress;
    expect(interrupted, inExclusiveRange(0, 1));
    rebuild(() => selected = true);
    await tester.pump();
    expect(progress, interrupted);
    await tester.pump(const Duration(milliseconds: 40));
    expect(progress, greaterThan(interrupted));
    await tester.pumpAndSettle();
    expect(progress, 1);
  });

  testWidgets(
    'count has no entrance, uses one current semantics and stable height',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var value = '9';
      late StateSetter rebuild;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return HhAnimatedCount(
                text: value,
                style: const TextStyle(fontSize: 18, height: 1.3),
              );
            },
          ),
        ),
      );
      final size = tester.getSize(find.byType(HhAnimatedCount));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('9'), findsOneWidget);
      rebuild(() => value = '10');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      expect(find.bySemanticsLabel('10'), findsOneWidget);
      expect(find.bySemanticsLabel('9'), findsNothing);
      expect(tester.getSize(find.byType(HhAnimatedCount)).height, size.height);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('9'), findsNothing);
      expect(find.text('10'), findsOneWidget);
      expect(tester.getSize(find.byType(HhAnimatedCount)).height, size.height);
      semantics.dispose();
    },
  );

  testWidgets('rapid count updates preserve whole Unicode strings', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var value = '١٢';
    late StateSetter rebuild;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return HhAnimatedCount(text: value, textAlign: TextAlign.end);
          },
        ),
        direction: TextDirection.rtl,
      ),
    );
    for (final next in ['١٣ ألف', '👩🏽‍💻 ١٤', 'e\u0301 ١٥', '١٦']) {
      rebuild(() => value = next);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 15));
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(HhAnimatedCount),
          matching: find.byType(Text),
        ),
      );
      expect(texts.where((text) => text.data == next), hasLength(1));
      expect(texts.every((text) => text.textAlign == TextAlign.end), isTrue);
    }
    await tester.pumpAndSettle();
    expect(find.text('١٦'), findsOneWidget);
    expect(find.text('e\u0301 ١٥'), findsNothing);
    expect(find.bySemanticsLabel('١٦'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byType(HhAnimatedCount))
          .getSemanticsData()
          .textDirection,
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('rapid rollback preserves visible opacity and displacement', (
    tester,
  ) async {
    var count = '9';
    late StateSetter rebuild;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return HhAnimatedCount(text: count);
          },
        ),
      ),
    );
    ({double opacity, Offset position}) frame(String text) => (
      opacity: tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text(text), matching: find.byType(Opacity))
                .first,
          )
          .opacity,
      position: tester
          .widget<FractionalTranslation>(
            find
                .ancestor(
                  of: find.text(text),
                  matching: find.byType(FractionalTranslation),
                )
                .first,
          )
          .translation,
    );
    rebuild(() => count = '10');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final before9 = frame('9');
    final before10 = frame('10');
    expect(before9.position.dy, lessThan(0));
    expect(before10.position.dy, greaterThan(0));
    rebuild(() => count = '9');
    await tester.pump();
    expect(frame('9'), before9);
    expect(frame('10'), before10);
    await tester.pump(const Duration(milliseconds: 40));
    expect(frame('9').opacity, greaterThan(before9.opacity));
    expect(frame('10').opacity, lessThan(before10.opacity));
    expect(frame('9').position.dy.abs(), lessThan(before9.position.dy.abs()));
    await tester.pumpAndSettle();
    expect(find.text('10'), findsNothing);
    expect(frame('9'), (opacity: 1.0, position: Offset.zero));
  });

  testWidgets('new count targets preserve all currently visible layers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var count = '9';
    late StateSetter rebuild;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return HhAnimatedCount(text: count);
          },
        ),
      ),
    );
    Map<String, (double, Offset)> frames() => {
      for (final widget in tester.widgetList<Text>(
        find.descendant(
          of: find.byType(HhAnimatedCount),
          matching: find.byType(Text),
        ),
      ))
        widget.data!: (
          tester
              .widget<Opacity>(
                find
                    .ancestor(
                      of: find.text(widget.data!),
                      matching: find.byType(Opacity),
                    )
                    .first,
              )
              .opacity,
          tester
              .widget<FractionalTranslation>(
                find
                    .ancestor(
                      of: find.text(widget.data!),
                      matching: find.byType(FractionalTranslation),
                    )
                    .first,
              )
              .translation,
        ),
    };
    for (final target in ['10', '11', '12', '10', '13', '9']) {
      final before = frames();
      rebuild(() => count = target);
      await tester.pump();
      final after = frames();
      for (final entry in before.entries) {
        if (entry.value.$1 > .5 / 255) {
          expect(after[entry.key], entry.value, reason: entry.key);
        }
      }
      expect(find.bySemanticsLabel(target), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(frames(), {'9': (1.0, Offset.zero)});
    semantics.dispose();
  });

  for (final accessibleNavigation in [false, true]) {
    testWidgets(
      '${accessibleNavigation ? 'accessible navigation' : 'disabled animations'} snaps active and future motion',
      (tester) async {
        var reduced = false;
        var selected = false;
        var count = '9';
        late StateSetter rebuild;
        var progress = -1.0;
        Widget content() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HhAnimatedSelection(
              selected: selected,
              builder: (context, value) {
                progress = value;
                return const SizedBox(width: 20, height: 20);
              },
            ),
            HhAnimatedCount(text: count),
            HhPressFeedback(
              builder: (context, states) => TextButton(
                statesController: states,
                onPressed: () {},
                child: const Text('Like'),
              ),
            ),
          ],
        );
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return host(
                content(),
                disableAnimations: reduced && !accessibleNavigation,
                accessibleNavigation: reduced && accessibleNavigation,
              );
            },
          ),
        );
        rebuild(() {
          selected = true;
          count = '10';
        });
        await tester.pump();
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(TextButton)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(progress, inExclusiveRange(0, 1));
        rebuild(() => reduced = true);
        await tester.pump();
        expect(progress, 1);
        expect(find.text('9'), findsNothing);
        expect(pressScale(tester), closeTo(.96, .0001));
        await gesture.up();
        await tester.pump();
        expect(pressScale(tester), 1);
        rebuild(() {
          selected = false;
          count = '11';
        });
        await tester.pump();
        expect(progress, 0);
        expect(find.text('10'), findsNothing);
        expect(find.text('11'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('disposing during active transitions leaves no ticker', (
    tester,
  ) async {
    var selected = false;
    var value = '1';
    late StateSetter rebuild;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return HhAnimatedSelection(
              selected: selected,
              builder: (context, progress) => HhAnimatedCount(text: value),
            );
          },
        ),
      ),
    );
    rebuild(() {
      selected = true;
      value = '2';
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
