import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/posts/post_tags.dart';
import 'package:hnuhole_mobile/src/posts/post_tag_widgets.dart';
import 'package:hnuhole_mobile/src/posts/post_tag_screen.dart';

import 'post_upload_support.dart';

class _TagApi extends ComposerApi implements PostTagApi {
  final queries = <({String tag, String? channel})>[];
  final waits = <String?, Completer<PostResponse<PostsPage<PostCard>>>>{};
  @override
  Future<PostResponse<PostCommandResult>> create({
    required String sessionToken,
    required String commandId,
    required String channelId,
    required String identityId,
    required String title,
    required String body,
    List<String> tags = const [],
  }) => createWithImages(
    sessionToken: sessionToken,
    commandId: commandId,
    channelId: channelId,
    identityId: identityId,
    title: title,
    body: body,
    images: const [],
    tags: tags,
  );
  @override
  Future<PostResponse<List<String>>> suggestPostTags({
    required String sessionToken,
    required String prefix,
  }) async => composerReply(['篮球'].where((v) => v.startsWith(prefix)).toList());
  @override
  Future<PostResponse<PostsPage<PostCard>>> taggedPosts({
    required String sessionToken,
    required String tag,
    String? channelId,
    String? cursor,
    int limit = 20,
  }) {
    queries.add((tag: tag, channel: channelId));
    return waits.putIfAbsent(channelId, () => Completer()).future;
  }
}

class _RotatingAuthority extends ChangeNotifier implements PostController {
  int epoch = 1;
  @override
  bool get available => true;
  @override
  int get authorityVersion => epoch;
  void rotate() {
    ++epoch;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _second = '55555555-5555-4555-8555-555555555555';
const _channels = [
  Channel(
    id: composerChannel,
    code: 'buddy',
    name: '搭子',
    initiallyVisible: true,
    displayOrder: 4,
  ),
  Channel(
    id: _second,
    code: 'technology',
    name: '科技',
    initiallyVisible: false,
    displayOrder: 7,
  ),
];
PostCard _card(String title, {String channel = composerChannel}) => PostCard(
  postId: channel == composerChannel
      ? composerPost
      : '66666666-6666-4666-8666-666666666666',
  channelId: channel,
  title: title,
  author: const PostAuthor(
    state: PostAuthorState.active,
    avatar: 'default-v1',
    nickname: '作者',
  ),
  publishedAt: composerAt,
  tags: const ['篮球'],
);

void main() {
  testWidgets('面板尚未操作时切换会话代次也立即关闭旧选择', (tester) async {
    final controller = _RotatingAuthority();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPostTagPicker(context, controller, ['篮球']),
              child: const Text('打开标签'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开标签'));
    await tester.pumpAndSettle();
    expect(find.text('#篮球'), findsOneWidget);
    controller.rotate();
    await tester.pumpAndSettle();
    expect(find.text('#篮球'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  test('带图片的新建与重试标签命令保持跨语言摘要一致', () {
    final vector = jsonDecode(
      File('../../packages/post-protocol-vectors/tags-v1.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final media = vector['mediaVectors'] as List;
    expect(media, hasLength(2));
    for (final raw in media) {
      final intent = raw['intent'] as Map<String, dynamic>;
      final text = intent['operation'] == 'CREATE'
          ? PostProtocol.create(
              channelId: intent['channelId'],
              identityId: intent['identityId'],
              title: intent['title'],
              body: intent['body'],
            )
          : PostProtocol.retry(
              taskId: intent['taskId'],
              expectedAttemptVersion: intent['expectedAttemptVersion'],
              title: intent['title'],
              body: intent['body'],
            );
      final frame = PostProtocol.withTags(
        PostProtocol.withImages(
          text,
          (intent['images'] as List).cast<Map<String, dynamic>>(),
        ),
        PostTags.parse(intent['tags']),
      );
      expect(
        frame.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        raw['frameHex'],
      );
      expect(PostProtocol.digest(frame), raw['sha256']);
    }
  });
  test('标签命令与跨语言独立向量一致，空标签保留原摘要', () {
    final vector = jsonDecode(
      File('../../packages/post-protocol-vectors/tags-v1.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final frame = PostProtocol.create(
      channelId: vector['channelId'],
      identityId: vector['identityId'],
      title: vector['title'],
      body: vector['body'],
    );
    expect(PostProtocol.withTags(frame, const []), frame);
    final tagged = PostProtocol.withTags(
      frame,
      (vector['tags'] as List).cast<String>(),
    );
    expect(
      tagged.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      vector['frameHex'],
    );
    expect(PostProtocol.digest(tagged), vector['sha256']);
  });
  test('标签长度、字符、大小写和重复规则', () {
    expect(() => PostTags.read({'tags': null}), throwsFormatException);
    expect(PostTags.normalizeAll([' #篮球 ', 'NBA', 'nba']), ['篮球', 'NBA']);
    expect(PostTags.normalize('一二三四五六七八九十'), '一二三四五六七八九十');
    for (final value in ['', '一二三四五六七八九十百', '篮球 比赛', 'emoji😀', 'a#b']) {
      expect(() => PostTags.normalize(value), throwsFormatException);
    }
    expect(
      () => PostTags.normalizeAll(['甲', '乙', '丙', '丁']),
      throwsFormatException,
    );
  });
  test('标签随草稿恢复并进入原发布内容和命令摘要', () async {
    final api = _TagApi();
    final f = await MediaComposerFixture.create(api: api);
    addTearDown(f.close);
    final editor = f.editor()
      ..body = '正文'
      ..tags = ['篮球', 'NBA'];
    expect(await f.posts.saveDraft(editor), isTrue);
    await f.restart();
    final restored = await f.posts.restoreDraft(editor.id);
    expect(restored?.tags, ['篮球', 'NBA']);
    expect(await f.posts.publish(restored!), isTrue);
    expect(api.tags, ['篮球', 'NBA']);
    expect(api.creates, 1);
  });
  testWidgets('面板保留已选、限制10字和3个，完成只返回选择', (tester) async {
    final api = _TagApi();
    final f = await tester.runAsync(
      () => MediaComposerFixture.create(api: api),
    );
    addTearDown(f!.close);
    List<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showPostTagPicker(context, f.posts, ['篮球']);
              },
              child: const Text('打开标签'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开标签'));
    await tester.pumpAndSettle();
    expect(find.text('#篮球'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '一二三四五六七八九十百');
    await tester.tap(find.byTooltip('添加'));
    await tester.pump();
    expect(find.text('标签限 1–10 字，仅中文、英文、数字和下划线'), findsOneWidget);
    for (final tag in ['NBA', '食堂']) {
      await tester.enterText(find.byType(TextField), tag);
      await tester.tap(find.byTooltip('添加'));
      await tester.pump();
    }
    await tester.enterText(find.byType(TextField), '第四个');
    await tester.tap(find.byTooltip('添加'));
    await tester.pump();
    expect(find.text('每篇帖子最多 3 个标签'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(result, ['篮球', 'NBA', '食堂']);
    expect(api.creates, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('切分类后的迟到标签结果不会覆盖选中态和当前数据', (tester) async {
    final api = _TagApi();
    final f = await tester.runAsync(
      () => MediaComposerFixture.create(api: api),
    );
    addTearDown(f!.close);
    await tester.pumpWidget(
      MaterialApp(
        home: PostTagScreen(
          controller: f.posts,
          tag: '篮球',
          channels: _channels,
          onAuthenticationRequired: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    expect(api.queries.single.channel, isNull);
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('科技').last);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    expect(api.queries.last.channel, _second);
    api.waits[_second]!.complete(
      composerReply(
        PostsPage(
          items: [_card('当前分类的帖子', channel: _second)],
          nextCursor: null,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    api.waits[null]!.complete(
      composerReply(PostsPage(items: [_card('迟到的旧结果')], nextCursor: null)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前分类的帖子'), findsOneWidget);
    expect(find.text('迟到的旧结果'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
