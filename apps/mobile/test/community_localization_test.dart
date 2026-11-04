import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/localization/app_localizations.dart';
import 'package:hnuhole_mobile/src/posts/x_feed.dart';

import 'feed_ui_test.dart' as feed;
import 'identity_test_support.dart';
import 'login_home_test_support.dart';

class _OwnedPostApi extends HomeTestPostsApi {
  int deletes = 0;
  @override
  Future<PostResponse<PostCapabilities>> capabilities({
    required String sessionToken,
    required String postId,
  }) async => feed.reply(
    PostCapabilities(postId: postId, canDelete: true, canEdit: false),
  );
  @override
  Future<PostResponse<PostCommandResult>> delete({
    required String sessionToken,
    required String commandId,
    required String postId,
  }) async {
    deletes++;
    throw StateError('This localization test must not submit deletion');
  }
}

void main() {
  testWidgets(
    'personal sort popup translates in its own route without changing selection',
    (tester) async {
      final presentation = AuthPresentationController(
        preferences: IdentityTestVault(),
      );
      final fixture = HomeTestFixture();
      await tester.pumpWidget(await fixture.create(presentation: presentation));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('destination:personal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('帖子排序'));
      await tester.pumpAndSettle();
      final route = ModalRoute.of(
        tester.element(find.byType(CheckedPopupMenuItem<bool>).first),
      );
      for (final language in AppLanguage.values) {
        presentation.setLanguage(language);
        await tester.pumpAndSettle();
        expect(find.text(translateUi('最新', language)), findsOneWidget);
        expect(find.text(translateUi('最热', language)), findsOneWidget);
        expect(
          ModalRoute.of(
            tester.element(find.byType(CheckedPopupMenuItem<bool>).first),
          ),
          same(route),
        );
      }
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is CheckedPopupMenuItem<bool> && widget.value == false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CheckedPopupMenuItem<bool>), findsNothing);
      expect(find.byKey(const ValueKey('profile-tab-0')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'post action popup and confirmation translate live while cancellation never deletes',
    (tester) async {
      final presentation = AuthPresentationController(
        preferences: IdentityTestVault(),
      );
      final api = _OwnedPostApi()..items = [feed.post(title: '收藏')];
      final fixture = HomeTestFixture(api: api);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          await fixture.create(presentation: presentation),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('收藏'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('帖子操作'));
        await tester.pumpAndSettle();
        for (final language in AppLanguage.values) {
          presentation.setLanguage(language);
          await tester.pumpAndSettle();
          expect(find.text(translateUi('删除帖子', language)), findsOneWidget);
        }
        await tester.tap(find.text(translateUi('删除帖子', presentation.language)));
        await tester.pumpAndSettle();
        final route = ModalRoute.of(tester.element(find.byType(Dialog)));
        for (final language in AppLanguage.values) {
          presentation.setLanguage(language);
          await tester.pumpAndSettle();
          expect(find.text(translateUi('确认删除这篇帖子？', language)), findsOneWidget);
          expect(
            find.ancestor(
              of: find.byKey(const ValueKey('scoped-confirm-action')),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.label == translateUi('删除帖子', language),
              ),
            ),
            findsOneWidget,
          );
          expect(
            ModalRoute.of(tester.element(find.byType(Dialog))),
            same(route),
          );
          expect(api.deletes, 0);
        }
        await tester.tap(find.text(translateUi('取消', presentation.language)));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(find.text('收藏'), findsOneWidget);
        expect(api.deletes, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'shipped root switches locale without reloading feed or replacing routes',
    (tester) async {
      final presentation = AuthPresentationController(
        preferences: IdentityTestVault(),
      );
      final fixture = HomeTestFixture();
      fixture.postApi.items = [feed.post(title: '收藏')];
      await tester.pumpWidget(await fixture.create(presentation: presentation));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feed-latest')));
      await tester.pumpAndSettle();
      final home = tester.state(find.byType(FeedScreen));
      final calls = List.of(fixture.postApi.calls);
      final session = fixture.store.current!.session;
      final route = ModalRoute.of(tester.element(find.byType(FeedScreen)));
      for (final language in AppLanguage.values) {
        presentation.setLanguage(language);
        await tester.pumpAndSettle();
        expect(
          Localizations.localeOf(tester.element(find.byType(FeedScreen))),
          language.locale,
        );
        expect(tester.state(find.byType(FeedScreen)), same(home));
        expect(
          ModalRoute.of(tester.element(find.byType(FeedScreen))),
          same(route),
        );
        expect(fixture.postApi.calls, calls);
        expect(fixture.store.current!.session, same(session));
        expect(
          tester.widget<HhXPostFeed>(find.byType(HhXPostFeed)).latestSelected,
          isTrue,
        );
        expect(
          find.text('收藏'),
          findsOneWidget,
          reason: 'a user title equal to a UI label stays verbatim',
        );
        expect(find.byTooltip(translateUi('我的', language)), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const ValueKey('destination:personal')));
      await tester.pumpAndSettle();
      final personal = tester.state(find.byType(PersonalPostsScreen));
      for (final language in AppLanguage.values) {
        presentation.setLanguage(language);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(PersonalPostsScreen)), same(personal));
        expect(find.text(translateUi('帖子', language)), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'post UI labels translate while title body and nickname stay verbatim',
    (tester) async {
      final presentation = AuthPresentationController();
      await tester.pumpWidget(
        AnimatedBuilder(
          animation: presentation,
          builder: (context, _) => MaterialApp(
            locale: presentation.language.locale,
            supportedLocales: appSupportedLocales,
            localizationsDelegates: appLocalizationDelegates,
            builder: (context, child) =>
                AuthPresentationScope(controller: presentation, child: child!),
            home: Scaffold(
              body: HhXPostItem(
                post: const FeedPostView(
                  id: 'content',
                  authorId: 'author',
                  authorName: '回复',
                  elapsed: '2026',
                  title: '收藏',
                  body: '设置',
                  favorites: 7,
                  availableActions: {FeedAction.bookmark},
                ),
                mediaBuilder: (_, _) => const SizedBox.shrink(),
                onPost: () {},
                onAuthor: () {},
                onMenu: () {},
                onAction: (_) {},
                onMedia: (_) {},
              ),
            ),
          ),
        ),
      );
      for (final language in AppLanguage.values) {
        presentation.setLanguage(language);
        await tester.pumpAndSettle();
        for (final value in ['回复', '收藏', '设置']) {
          expect(find.text(value), findsOneWidget);
        }
        expect(find.byTooltip(translateUi('帖子更多操作', language)), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      presentation.dispose();
    },
  );
}
