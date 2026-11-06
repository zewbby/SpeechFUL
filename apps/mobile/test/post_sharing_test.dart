import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/identity/identity_initial_gate.dart';

import 'feed_ui_test.dart' as feed;
import 'login_home_navigation_test.dart' show disposeApp;
import 'login_home_test_support.dart';

const _id = '22222222-2222-4222-8222-222222222222';
const _other = '33333333-3333-4333-8333-333333333333';
final _origin = Uri.parse('https://unused.invalid');
String _url(String id) => 'https://unused.invalid/s/posts/$id';

class SharingTestApi extends HomeTestPostsApi implements PostSharingApi {
  int shares = 0;
  final resolved = <String>[];
  Completer<PostResponse<PostShareLink>>? shareWait;
  Completer<PostResponse<PostDetail>>? resolveWait;
  PostFailure? failure;

  PostDetail detailFor(String id) => PostDetail(
    postId: id,
    channelId: items.first.channelId,
    title: id == _id ? '分享原帖甲' : '分享原帖乙',
    body: '当前公开内容',
    author: items.first.author,
    publishedAt: items.first.publishedAt,
  );

  @override
  Future<PostResponse<PostShareLink>> shareLink({
    required String sessionToken,
    required String postId,
  }) async {
    shares++;
    return shareWait?.future ??
        feed.reply(
          PostShareLink(
            postId: postId,
            url: _url(postId),
            text: 'SpeechFUL\n${_url(postId)}',
          ),
        );
  }

  @override
  Future<PostResponse<PostDetail>> resolvePostLink({
    required String sessionToken,
    required String url,
  }) async {
    resolved.add(url);
    if (failure != null) throw failure!;
    return resolveWait?.future ??
        feed.reply(detailFor(PostLinkTarget.parse(url, _origin)!.postId));
  }
}

Future<void> _login(WidgetTester tester) async {
  if (find.byKey(const ValueKey('auth-start')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const ValueKey('auth-start')));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byType(TextFormField).at(0), 'share_reader');
  await tester.enterText(
    find.byType(TextFormField).at(1),
    'valid-password-123',
  );
  await tester.tap(find.byKey(const ValueKey('login-submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'session rejection while resolving returns through login to the same original post',
    (tester) async {
      final api = SharingTestApi()
        ..failure = const PostFailure(
          kind: PostFailureKind.unauthorized,
          statusCode: 401,
          code: 'SESSION_INVALID',
        );
      final links = PostLinkInbox(_origin)..receive(_url(_id));
      final f = HomeTestFixture(api: api);
      await tester.pumpWidget(await f.create(postLinks: links));
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.text('分享原帖甲'), findsNothing);
      expect(links.pending?.target.postId, _id);
      api.failure = null;
      await _login(tester);
      expect(find.text('分享原帖甲'), findsOneWidget);
      expect(api.resolved, [_url(_id), _url(_id)]);
      expect(links.pending, isNull);
      await disposeApp(tester);
    },
  );

  testWidgets(
    'untrusted incoming links never navigate or request original content',
    (tester) async {
      final api = SharingTestApi();
      final links = PostLinkInbox(_origin);
      final f = HomeTestFixture(api: api);
      await tester.pumpWidget(await f.create(postLinks: links));
      await tester.pumpAndSettle();
      await links.didPushRouteInformation(
        RouteInformation(
          uri: Uri.parse('https://attacker.invalid/s/posts/$_id'),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.resolved, isEmpty);
      expect(find.byType(PostDetailScreen), findsNothing);
      expect(find.text('分享链接无效'), findsOneWidget);
      await disposeApp(tester);
    },
  );
  test(
    'post targets accept only the exact C origin or canonical app scheme',
    () {
      for (final raw in [_url(_id), 'speechful://posts/$_id']) {
        final target = PostLinkTarget.parse(raw, _origin)!;
        expect(target.postId, _id);
        expect(target.url, _url(_id));
      }
      for (final raw in [
        'http://unused.invalid/s/posts/$_id',
        'https://unused.invalid.attacker/s/posts/$_id',
        'https://user@unused.invalid/s/posts/$_id',
        '${_url(_id)}?a=1',
        '${_url(_id)}#preview',
        '${_url(_id)}/',
        '/s/posts/$_id',
        'speechful://posts/$_id?token=secret',
        'speechful://posts/00000000-0000-0000-0000-000000000000',
        'speechful://posts/${_id.replaceFirst('2', '%32')}',
      ]) {
        expect(PostLinkTarget.parse(raw, _origin), isNull);
      }
      expect(
        () => PostShareLink.fromJson(
          {'postId': _id, 'url': _url(_id), 'shareText': '标题\n${_url(_id)}'},
          _origin,
          _id,
        ),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'running app link preserves the previous tab and Back returns there',
    (tester) async {
      final api = SharingTestApi();
      final links = PostLinkInbox(_origin);
      final f = HomeTestFixture(api: api);
      await tester.pumpWidget(await f.create(postLinks: links));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('destination:personal')));
      await tester.pumpAndSettle();
      final previous = tester.element(find.byType(PersonalPostsScreen));
      await links.didPushRouteInformation(
        RouteInformation(uri: Uri.parse(_url(_id))),
      );
      await tester.pumpAndSettle();
      expect(find.text('分享原帖甲'), findsOneWidget);
      expect(api.resolved, [_url(_id)]);
      expect(links.pending, isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(PersonalPostsScreen)), same(previous));
      await disposeApp(tester);
    },
  );

  testWidgets(
    'cold authenticated target opens after initial identity check and returns home',
    (tester) async {
      final api = SharingTestApi();
      final links = PostLinkInbox(_origin)
        ..start(initialRoute: 'speechful://posts/$_id');
      final f = HomeTestFixture(api: api);
      await tester.pumpWidget(await f.create(postLinks: links));
      await tester.pumpAndSettle();
      expect(find.text('分享原帖甲'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(FeedScreen), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(FeedScreen))).canPop(),
        isFalse,
      );
      await disposeApp(tester);
    },
  );

  testWidgets(
    'cancel login retains target; latest link wins through actual login',
    (tester) async {
      final api = SharingTestApi();
      final links = PostLinkInbox(_origin)..receive(_url(_id));
      final f = HomeTestFixture(api: api);
      await tester.pumpWidget(
        await f.create(signedIn: false, postLinks: links),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(api.resolved, isEmpty);
      Navigator.of(tester.element(find.byType(AuthScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsNothing);
      expect(links.pending?.target.postId, _id);
      // A fresh click on the same link must allow retrying a cancelled login.
      links.receive('speechful://posts/$_id');
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(api.resolved, isEmpty);
      links.receive('speechful://posts/$_other');
      await tester.pumpAndSettle();
      await _login(tester);
      expect(find.byType(AuthScreen), findsNothing);
      expect(find.text('分享原帖乙'), findsOneWidget);
      expect(find.text('分享原帖甲'), findsNothing);
      expect(api.resolved, [_url(_other)]);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(FeedScreen), findsOneWidget);
      await disposeApp(tester);
    },
  );

  testWidgets(
    'zero identities blocks original post until required initial setup finishes',
    (tester) async {
      final api = SharingTestApi();
      final links = PostLinkInbox(_origin)..receive(_url(_id));
      final f = HomeTestFixture(api: api);
      final app = await f.create(postLinks: links, zeroIdentities: true);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.byType(IdentityInitialGate), findsOneWidget);
      expect(find.byType(PostDetailScreen), findsNothing);
      expect(api.resolved, isEmpty);
      await app.identities.create('分享读者身份');
      await tester.pumpAndSettle();
      expect(find.text('分享原帖甲'), findsOneWidget);
      expect(api.resolved, [_url(_id)]);
      await disposeApp(tester);
    },
  );

  testWidgets(
    'explicit logout clears pending target and rejects a late share response',
    (tester) async {
      final api = SharingTestApi()..shareWait = Completer();
      final links = PostLinkInbox(_origin);
      final sent = <String>[];
      final f = HomeTestFixture(api: api);
      await tester.pumpWidget(
        await f.create(
          postLinks: links,
          sharePostText: (text) async => sent.add(text),
        ),
      );
      await tester.pumpAndSettle();
      final id = api.items.first.postId;
      await tester.tap(find.byKey(ValueKey('share:$id')));
      await tester.pump();
      expect(api.shares, 1);
      // A second action cannot create another request or another system sheet.
      await tester.tap(find.byKey(ValueKey('share:$id')));
      await tester.pump();
      expect(api.shares, 1);
      links.receive(_url(_other));
      await f.sessions.logout();
      api.shareWait!.complete(
        feed.reply(
          PostShareLink(
            postId: id,
            url: _url(id),
            text: 'SpeechFUL\n${_url(id)}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(links.pending, isNull);
      await disposeApp(tester);
    },
  );

  testWidgets(
    'feed and detail share send only backend-approved text; cancellation has no success notice',
    (tester) async {
      final api = SharingTestApi();
      final sent = <String>[];
      final f = HomeTestFixture(api: api);
      await tester.pumpWidget(
        await f.create(sharePostText: (text) async => sent.add(text)),
      );
      await tester.pumpAndSettle();
      final id = api.items.first.postId;
      await tester.tap(find.byKey(ValueKey('share:$id')));
      await tester.pumpAndSettle();
      expect(sent, ['SpeechFUL\n${_url(id)}']);
      expect(find.byType(PostDetailScreen), findsNothing);
      await tester.tap(find.text('今天的校园'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ValueKey('detail-share:$id')));
      await tester.tap(find.byKey(ValueKey('detail-share:$id')));
      await tester.pumpAndSettle();
      expect(sent.length, 2);
      await tester.tap(find.byTooltip('帖子操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分享').last);
      await tester.pumpAndSettle();
      expect(sent, List.filled(3, 'SpeechFUL\n${_url(id)}'));
      expect(find.text('分享成功'), findsNothing);
      await disposeApp(tester);
    },
  );

  testWidgets(
    'unavailable original stays in a retryable detail without leaking other content',
    (tester) async {
      final api = SharingTestApi()
        ..failure = const PostFailure(
          kind: PostFailureKind.rejected,
          statusCode: 404,
          code: 'POST_NOT_FOUND',
        );
      final links = PostLinkInbox(_origin)..receive(_url(_id));
      final f = HomeTestFixture(api: api);
      await tester.pumpWidget(await f.create(postLinks: links));
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailScreen), findsOneWidget);
      expect(find.text('分享原帖甲'), findsNothing);
      expect(find.text('帖子不存在或暂时无法读取'), findsOneWidget);
      api.failure = null;
      await tester.tap(find.text('重新核对'));
      await tester.pumpAndSettle();
      expect(find.text('分享原帖甲'), findsOneWidget);
      await disposeApp(tester);
    },
  );
}
