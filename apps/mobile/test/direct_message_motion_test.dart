import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_bubble.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_timeline.dart';

import 'direct_message_screen_test.dart' as chat;

DmMessage message(
  String id, {
  bool outgoing = false,
  DmSendState state = DmSendState.sent,
}) => DmMessage(
  id: id,
  outgoing: outgoing,
  state: state,
  time: '12:30',
  text: 'Message $id',
);

Finder row(String id) => find.byKey(ValueKey('message:$id'));

double enterOffset(WidgetTester tester, String id) => tester
    .widget<Transform>(
      find.descendant(
        of: row(id),
        matching: find.byKey(const ValueKey('dm-message-enter')),
      ),
    )
    .transform
    .storage[13];

ScrollPosition position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(HhDmTimeline),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  testWidgets(
    'only a new suffix at the bottom enters; receipts and history do not',
    (tester) async {
      final old = message('old');
      final added = message('new', outgoing: true, state: DmSendState.sending);
      await tester.pumpWidget(chat.app(chat.view(messages: [old])));
      expect(enterOffset(tester, 'old'), 0);
      await tester.pumpWidget(chat.app(chat.view(messages: [old, added])));
      expect(enterOffset(tester, 'new'), 8);
      expect(position(tester).pixels, 0);
      await tester.pump(const Duration(milliseconds: 80));
      expect(enterOffset(tester, 'new'), allOf(greaterThan(0), lessThan(8)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(enterOffset(tester, 'new'), 0);
      await tester.pumpWidget(
        chat.app(
          chat.view(
            messages: [
              message('history'),
              old,
              added.copyWith(state: DmSendState.unknown),
            ],
          ),
        ),
      );
      expect(enterOffset(tester, 'history'), 0);
      expect(enterOffset(tester, 'new'), 0);
      expect(find.byKey(const ValueKey('retry:new')), findsNothing);
      await tester.pumpWidget(
        chat.app(chat.view(messages: [old, added], scope: 'new-account')),
      );
      expect(enterOffset(tester, 'new'), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('initial history loading and replacement batches do not enter', (
    tester,
  ) async {
    await tester.pumpWidget(
      chat.app(chat.view(history: DmHistoryState.loading)),
    );
    await tester.pumpWidget(chat.app(chat.view(messages: [message('loaded')])));
    expect(enterOffset(tester, 'loaded'), 0);
    await tester.pumpWidget(
      chat.app(chat.view(messages: [message('replacement')])),
    );
    expect(enterOffset(tester, 'replacement'), 0);
    await tester.pumpWidget(chat.app(chat.view(scope: 'empty')));
    await tester.pumpWidget(
      chat.app(
        chat.view(
          scope: 'empty',
          messages: [
            message(
              'restored-queue',
              outgoing: true,
              state: DmSendState.sending,
            ),
          ],
        ),
      ),
    );
    expect(enterOffset(tester, 'restored-queue'), 0);
  });

  testWidgets(
    'away from bottom preserves its anchor and never replays on scroll rebuild',
    (tester) async {
      final old = [for (var i = 0; i < 50; i++) message('$i')];
      await tester.pumpWidget(chat.app(chat.view(messages: old)));
      position(tester).jumpTo(380);
      await tester.pump();
      final anchor = old
          .firstWhere(
            (m) =>
                row(m.id).evaluate().isNotEmpty &&
                tester.getTopLeft(row(m.id)).dy > 180 &&
                tester.getBottomLeft(row(m.id)).dy < 450,
          )
          .id;
      final before = tester.getTopLeft(row(anchor)).dy;
      final next = [...old, message('added')];
      await tester.pumpWidget(chat.app(chat.view(messages: next)));
      await tester.pump();
      expect(tester.getTopLeft(row(anchor)).dy, closeTo(before, 1));
      await tester.tap(find.byTooltip('回到最新消息'));
      await tester.pumpAndSettle();
      expect(enterOffset(tester, 'added'), 0);
      position(tester).jumpTo(position(tester).maxScrollExtent);
      await tester.pump();
      position(tester).jumpTo(0);
      await tester.pump();
      expect(enterOffset(tester, 'added'), 0);
    },
  );

  testWidgets(
    'being near the bottom is not the current bottom for entrance motion',
    (tester) async {
      final old = [for (var i = 0; i < 40; i++) message('$i')];
      await tester.pumpWidget(chat.app(chat.view(messages: old)));
      position(tester).jumpTo(40);
      await tester.pump();
      await tester.pumpWidget(
        chat.app(chat.view(messages: [...old, message('near')])),
      );
      expect(enterOffset(tester, 'near'), 0);
    },
  );

  testWidgets(
    'entrance keeps incoming visibility reporting on the existing row geometry',
    (tester) async {
      final visible = <String>{};
      final old = [message('old', outgoing: true)];
      await tester.pumpWidget(
        chat.app(chat.view(messages: old), visible: visible.addAll),
      );
      await tester.pumpWidget(
        chat.app(
          chat.view(messages: [...old, message('incoming')]),
          visible: visible.addAll,
        ),
      );
      expect(enterOffset(tester, 'incoming'), 8);
      expect(visible, {'incoming'});
      await tester.pump(const Duration(milliseconds: 170));
      expect(visible, {'incoming'});
    },
  );

  for (final accessible in [false, true]) {
    testWidgets(
      '${accessible ? 'accessible navigation' : 'disabled animations'} completes all feedback immediately',
      (tester) async {
        final old = message('old');
        final added = message(
          'new',
          outgoing: true,
          state: DmSendState.unknown,
        );
        Widget app(List<DmMessage> data) => chat.app(
          chat.view(messages: data),
          disableAnimations: !accessible,
          accessibleNavigation: accessible,
        );
        await tester.pumpWidget(app([old]));
        await tester.pumpWidget(app([old, added]));
        expect(enterOffset(tester, 'new'), 0);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byIcon(Icons.timelapse_rounded), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('dm-input')), 'draft');
        await tester.pump();
        final button = tester.widget<IconButton>(
          find.byKey(const ValueKey('dm-send')),
        );
        expect(button.onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('enabling reduced motion mid-entry finishes and never restarts', (
    tester,
  ) async {
    final old = message('old'), added = message('added');
    await tester.pumpWidget(chat.app(chat.view(messages: [old])));
    await tester.pumpWidget(chat.app(chat.view(messages: [old, added])));
    expect(enterOffset(tester, 'added'), 8);
    await tester.pumpWidget(
      chat.app(chat.view(messages: [old, added]), accessibleNavigation: true),
    );
    expect(enterOffset(tester, 'added'), 0);
    await tester.pumpWidget(chat.app(chat.view(messages: [old, added])));
    expect(enterOffset(tester, 'added'), 0);
  });

  testWidgets('hidden ticker and background catch-up never create entrances', (
    tester,
  ) async {
    final data = [message('old')];
    await tester.pumpWidget(
      chat.app(chat.view(messages: List.of(data)), tickerEnabled: false),
    );
    data.add(message('hidden'));
    await tester.pumpWidget(
      chat.app(chat.view(messages: List.of(data)), tickerEnabled: false),
    );
    await tester.pumpWidget(chat.app(chat.view(messages: List.of(data))));
    expect(enterOffset(tester, 'hidden'), 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    data.add(message('catch-up'));
    await tester.pumpWidget(chat.app(chat.view(messages: List.of(data))));
    expect(enterOffset(tester, 'catch-up'), 0);
    data.add(message('live'));
    await tester.pumpWidget(chat.app(chat.view(messages: List.of(data))));
    expect(enterOffset(tester, 'live'), 0);
    await tester.pumpWidget(
      chat.app(chat.view(scope: 'reopened', messages: List.of(data))),
    );
    data.add(message('after-reopen'));
    await tester.pumpWidget(
      chat.app(chat.view(scope: 'reopened', messages: List.of(data))),
    );
    expect(enterOffset(tester, 'after-reopen'), 8);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(enterOffset(tester, 'after-reopen'), 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'outgoing failed status loses retry action and semantics immediately',
    (tester) async {
      var retries = 0;
      Widget app(DmSendState state) => chat.app(
        chat.view(messages: [message('status', outgoing: true, state: state)]),
        retry: (_) => retries++,
      );
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(app(DmSendState.failed));
      await tester.pumpWidget(app(DmSendState.unknown));
      final stale = find.byKey(const ValueKey('retry:status'));
      expect(stale.hitTestable(), findsNothing);
      expect(find.bySemanticsLabel('发送失败，选择是否重发'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('正在发送，结果尚未确认')), findsOneWidget);
      expect(retries, 0);
      await tester.pump(const Duration(milliseconds: 170));
      expect(stale, findsNothing);
      await tester.pumpWidget(app(DmSendState.failed));
      expect(stale.hitTestable(), findsOneWidget);
      await tester.tap(stale);
      await tester.pumpAndSettle();
      expect(find.text('重新发送这条消息？'), findsOneWidget);
      semantics.dispose();
    },
  );

  for (final state in [
    DmSendState.unknown,
    DmSendState.sending,
    DmSendState.sent,
  ]) {
    testWidgets(
      'fading retry loses held and traversed keyboard focus for ${state.name}',
      (tester) async {
        var retries = 0;
        Widget app(DmSendState value) => MaterialApp(
          home: Scaffold(
            body: HhDirectMessageBubble(
              message: message('status', outgoing: true, state: value),
              imageBuilder: (_, _) => const SizedBox.shrink(),
              onMenu: (_, _) {},
              onImage: (_) {},
              onRetry: () => retries++,
              onReedit: () {},
            ),
          ),
        );
        await tester.pumpWidget(app(DmSendState.failed));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        // Prove that native keyboard traversal/activation works before transition.
        expect(retries, 1);
        retries = 0;
        await tester.pumpWidget(app(state));
        expect(find.byKey(const ValueKey('retry:status')), findsOneWidget);
        // Neither retained focus nor a fresh Tab may activate the fading control.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(retries, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(retries, 0);
        await tester.pump(const Duration(milliseconds: 170));
        expect(find.byKey(const ValueKey('retry:status')), findsNothing);
      },
    );
  }

  testWidgets('fading image retry cannot retain or regain keyboard focus', (
    tester,
  ) async {
    var menus = 0;
    Widget app(DmSendState state) => MaterialApp(
      home: Scaffold(
        body: HhDirectMessageBubble(
          message: DmMessage(
            id: 'photos',
            outgoing: true,
            time: '12:30',
            images: [DmImage(id: 'photo', description: 'Photo', state: state)],
          ),
          imageBuilder: (_, _) => const SizedBox.shrink(),
          onMenu: (_, _) => menus++,
          onImage: (_) {},
          onRetry: () {},
          onReedit: () {},
        ),
      ),
    );
    await tester.pumpWidget(app(DmSendState.failed));
    // The image opens first in traversal order, followed by its retry button.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(menus, 1);
    menus = 0;
    await tester.pumpWidget(app(DmSendState.unknown));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(menus, 0);
  });

  testWidgets(
    'image failure fade cannot reopen retry actions for an unknown image',
    (tester) async {
      Widget app(DmSendState state) => chat.app(
        chat.view(
          messages: [
            DmMessage(
              id: 'photos',
              outgoing: true,
              time: '12:30',
              images: [
                DmImage(id: 'photo', description: 'Photo', state: state),
              ],
            ),
          ],
        ),
      );
      await tester.pumpWidget(app(DmSendState.failed));
      final retry = find.byKey(const ValueKey('retry-image:photo'));
      expect(retry.hitTestable(), findsOneWidget);
      await tester.pumpWidget(app(DmSendState.unknown));
      expect(retry.hitTestable(), findsNothing);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.text('重发此图片'), findsNothing);
      await tester.pump(const Duration(milliseconds: 170));
      expect(retry, findsNothing);
    },
  );

  testWidgets(
    'send press cancellation keeps the draft and local rejection remains actionable',
    (tester) async {
      final accepted = Completer<bool>();
      var sends = 0;
      await tester.pumpWidget(
        chat.app(
          chat.view(draft: 'keep draft'),
          send: (_) {
            sends++;
            return accepted.future;
          },
        ),
      );
      final send = find.byKey(const ValueKey('dm-send'));
      final start = tester.getCenter(send);
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 75));
      expect(sends, 0);
      await gesture.moveTo(start + const Offset(-180, -90));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 280));
      expect(sends, 0);
      await tester.tap(send);
      await tester.pump();
      expect(sends, 1);
      expect(tester.widget<IconButton>(send).onPressed, isNull);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('dm-input')))
            .controller!
            .text,
        'keep draft',
      );
      accepted.complete(false);
      await tester.pump();
      expect(tester.widget<IconButton>(send).onPressed, isNotNull);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('dm-input')))
            .controller!
            .text,
        'keep draft',
      );
    },
  );

  final renderDir = Platform.environment['HNUHOLE_DM_MOTION_RENDER_DIR'];
  if (renderDir != null) {
    testWidgets('render actual entry midpoint and reduced-motion endpoint', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final roboto = FontLoader('Roboto')
          ..addFont(
            File('assets/fonts/Roboto-Regular.ttf')
                .readAsBytes()
                .then((bytes) => bytes.buffer.asByteData()),
          );
        final chinese = FontLoader('HhNotoSansSC')
          ..addFont(
            File('assets/fonts/NotoSansSC-Variable.ttf')
                .readAsBytes()
                .then((bytes) => bytes.buffer.asByteData()),
          );
        await Future.wait([roboto.load(), chinese.load()]);
        final iconFont = Platform.environment['HNUHOLE_UI_RENDER_ICON_FONT'];
        if (iconFont != null) {
          final icons = FontLoader('MaterialIcons')
            ..addFont(
              File(iconFont)
                  .readAsBytes()
                  .then((bytes) => bytes.buffer.asByteData()),
            );
          await icons.load();
        }
      });
      final boundary = GlobalKey();
      final old = [message('existing', outgoing: true)];
      Widget app(List<DmMessage> data, {bool reduced = false}) =>
          RepaintBoundary(
            key: boundary,
            child: chat.app(
              chat.view(messages: data, draft: 'Draft message'),
              disableAnimations: reduced,
              fontFamily: 'Roboto',
            ),
          );
      await tester.pumpWidget(app(old));
      final next = [
        ...old,
        message('new', outgoing: true, state: DmSendState.sending),
      ];
      await tester.pumpWidget(app(next));
      await tester.pump(const Duration(milliseconds: 70));
      Future<void> capture(String name) async {
        final box =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await box.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(renderDir).create(recursive: true);
          await File('$renderDir/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('dm-entry-midpoint');
      await tester.pumpWidget(app(next, reduced: true));
      await capture('dm-reduced-endpoint');
    });
  }
}
