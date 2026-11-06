import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/posts/post_edit_api.dart';

import 'post_upload_support.dart';

class _EditApi extends ComposerApi implements PostEditApi {
  final editReceipts = <String, PostEditResult>{};
  final commands = <String>[];
  final submittedTags = <List<String>?>[];
  final staged = <({String commandId, String imageId, Uint8List bytes})>[];
  List<String> publicImageIds = [];
  bool allowEdit = true, rejectNext = false, loseNext = false;
  bool loseSavedReply = false;
  DateTime? editedAt;
  String revision = composerPost;

  @override
  Future<PostResponse<PostCapabilities>> capabilities({
    required String sessionToken,
    required String postId,
  }) async => composerReply(
    PostCapabilities(postId: postId, canDelete: true, canEdit: allowEdit),
  );

  @override
  Future<PostResponse<PostDetail>> detail({
    required String sessionToken,
    required String postId,
  }) async {
    final read = await super.detail(sessionToken: sessionToken, postId: postId);
    final post = read.value;
    return composerReply(
      PostDetail(
        postId: post.postId,
        channelId: post.channelId,
        author: post.author,
        publishedAt: post.publishedAt,
        title: post.title,
        body: post.body,
        tags: post.tags,
        editedAt: editedAt,
        imageCount: publicImageIds.length,
      ),
    );
  }

  @override
  Future<PostResponse<PublishedPostEdit>> readEdit({
    required String sessionToken,
    required String postId,
  }) async {
    final read = await detail(sessionToken: sessionToken, postId: postId);
    return composerReply(
      PublishedPostEdit(
        post: read.value,
        revision: revision,
        imageIds: publicImageIds,
      ),
    );
  }

  @override
  Future<PostResponse<PostEditResult>> editResult({
    required String sessionToken,
    required String postId,
    required String commandId,
  }) async =>
      composerReply(editReceipts[commandId] ?? const PostEditResult('PENDING'));

  @override
  Future<PostResponse<PostEditResult>> saveEdit({
    required String sessionToken,
    required String postId,
    required String commandId,
    required String revision,
    required String title,
    required String body,
    List<String>? imageIds,
    List<String>? tags,
  }) async {
    commands.add(commandId);
    submittedTags.add(tags);
    if (rejectNext) {
      rejectNext = false;
      return composerReply(
        editReceipts[commandId] = const PostEditResult(
          'REJECTED',
          code: 'POST_CONTENT_INVALID',
        ),
      );
    }
    if (loseNext) {
      loseNext = false;
      throw const PostFailure(kind: PostFailureKind.transport);
    }
    this.title = title;
    this.body = body;
    if (tags != null) this.tags = List.of(tags);
    this.revision = composerTask;
    if (imageIds != null) publicImageIds = imageIds;
    editedAt = composerAt.add(const Duration(minutes: 1));
    const result = PostEditResult('SAVED');
    editReceipts[commandId] = result;
    if (loseSavedReply) {
      loseSavedReply = false;
      throw const PostFailure(kind: PostFailureKind.transport);
    }
    return composerReply(result);
  }

  @override
  Future<PostResponse<bool>> stageEditImage({
    required String sessionToken,
    required String postId,
    required String commandId,
    required String imageId,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    staged.add((commandId: commandId, imageId: imageId, bytes: bytes));
    return composerReply(true);
  }
}

void main() {
  test('升级前的待核对编辑不补入标签字段或改变原提交', () async {
    final api = _EditApi()..body = '原正文';
    final fixture = await MediaComposerFixture.create(api: api);
    addTearDown(fixture.close);
    await fixture.current!.writePostEdit(composerPost, null, {
      'commandId': AuthCrypto.randomEncoded(16),
      'baseRevision': composerPost,
      'title': '原标题',
      'body': '原正文',
      'imageCount': 0,
      'images': <Object>[],
    }, const {});
    final session = fixture.posts.openPostEdit(composerPost)!;
    final pending = (await session.pending())!;
    expect(pending.tags, isNull);
    await session.submit(pending);
    expect(api.submittedTags, [null]);
  });
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      if (finder.evaluate().isNotEmpty) {
        await tester.pump(const Duration(milliseconds: 350));
        return;
      }
    }
    expect(
      finder,
      findsWidgets,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join(' | '),
    );
  }

  Future<void> start(WidgetTester tester, MediaComposerFixture fixture) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PostDetailScreen(controller: fixture.posts, postId: composerPost),
      ),
    );
    await waitFor(tester, find.byTooltip('帖子操作'));
  }

  Future<void> edit(WidgetTester tester, {bool waitForFields = true}) async {
    await tester.tap(find.byTooltip('帖子操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑帖子'));
    if (waitForFields) await waitFor(tester, find.byType(TextField));
  }

  testWidgets('本人菜单进入，丢弃未提交输入，失败后重试并读回已编辑', (tester) async {
    final api = _EditApi()..body = '公开旧正文';
    final fixture = (await tester.runAsync(
      () => MediaComposerFixture.create(api: api),
    ))!;
    await start(tester, fixture);
    await edit(tester);
    final fields = find.byType(TextField);
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, '公开旧正文');
    await tester.enterText(fields.at(1), '丢弃的输入');
    await tester.pageBack();
    await waitFor(tester, find.text('公开旧正文'));
    expect(api.commands, isEmpty);
    await edit(tester);
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, '公开旧正文');
    await tester.enterText(fields.at(1), '修改后的正文');
    api.rejectNext = true;
    await tester.tap(find.text('保存'));
    await waitFor(tester, find.text('保存失败。修改保留在此页，可重试。'));
    expect(api.body, '公开旧正文');
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, '修改后的正文');
    await tester.tap(find.text('保存'));
    await waitFor(tester, find.text('已编辑'));
    await tester.pumpAndSettle();
    expect(find.text('修改后的正文'), findsOneWidget);
    await tester.tap(find.text('已编辑'));
    await tester.pumpAndSettle();
    expect(find.text('最后修改时间'), findsOneWidget);
    expect(api.commands.toSet().length, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(fixture.close);
  });

  testWidgets('重进先查结果，待核对只可原次重试，权限拒绝时无编辑菜单', (tester) async {
    final api = _EditApi()..body = '当前公开正文';
    final fixture = (await tester.runAsync(
      () => MediaComposerFixture.create(api: api),
    ))!;
    await start(tester, fixture);
    await edit(tester);
    await tester.enterText(find.byType(TextField).at(1), '需要核对的正文');
    final image = (await tester.runAsync(
      () => File(
        '../../packages/image_viewer/example/assets/fixtures/ordinary.png',
      ).readAsBytes(),
    ))!;
    fixture.picker.next = [pickedBytes(image)];
    final addImage = find.byTooltip('添加图片');
    await tester.ensureVisible(addImage);
    await tester.tap(addImage);
    await waitFor(tester, find.text('图片 1/9'));
    api.loseNext = true;
    await tester.tap(find.text('保存'));
    await waitFor(tester, find.text('保存结果待核对。'));
    final original = api.commands.single;
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(fixture.restart);
    await start(tester, fixture);
    await edit(tester);
    await waitFor(tester, find.text('重试本次提交'));
    expect(api.commands, [original]);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).readOnly,
      isTrue,
    );
    await tester.tap(find.text('重试本次提交'));
    await waitFor(tester, find.text('已编辑'));
    await tester.pumpAndSettle();
    expect(api.commands, [original, original]);
    expect(api.staged.map((item) => item.commandId), [original, original]);
    expect(api.staged.first.imageId, api.staged.last.imageId);
    expect(api.staged.last.bytes, image);
    expect(find.text('需要核对的正文'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.allowEdit = false;
    await start(tester, fixture);
    await tester.tap(find.byTooltip('帖子操作'));
    await tester.pumpAndSettle();
    expect(find.text('编辑帖子'), findsNothing);
    expect(find.text('删除帖子'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(fixture.close);
  });

  testWidgets('服务端已保存但丢失回包，重进核对后只读回公开版', (tester) async {
    final api = _EditApi()
      ..body = '旧正文'
      ..loseSavedReply = true;
    final fixture = (await tester.runAsync(
      () => MediaComposerFixture.create(api: api),
    ))!;
    await start(tester, fixture);
    await edit(tester);
    await tester.enterText(find.byType(TextField).at(1), '服务器已保存正文');
    await tester.tap(find.text('保存'));
    await waitFor(tester, find.text('保存结果待核对。'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await edit(tester, waitForFields: false);
    await waitFor(tester, find.text('已编辑'));
    await tester.pumpAndSettle();
    expect(api.commands, hasLength(1));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('服务器已保存正文'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(fixture.close);
  });
}
