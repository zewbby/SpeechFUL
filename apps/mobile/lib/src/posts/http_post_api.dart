import 'post_discovery_http.dart';
import 'post_http_transport.dart';
import 'personal_collections_api.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../messaging/dm_protocol.dart';

import '../auth/auth_crypto.dart';
import 'post_api.dart';
import 'author_block_api.dart';
import 'post_tags.dart';
import 'post_edit_api.dart';
import 'feed_api.dart';
import 'hidden_post_api.dart';
import 'post_interactions_api.dart';
import 'post_reposts_api.dart';
import 'post_search_api.dart';
import 'post_ranking_api.dart';
import 'post_sharing_api.dart';
import 'post_models.dart';
import 'post_media_api.dart';
import 'post_protocol.dart';
import 'post_upload_api.dart';
import 'post_upload_diagnostics.dart';
import 'post_upload_models.dart';

import 'package:crypto/crypto.dart' as hashes;

part 'post_upload_http.dart';
part 'feed_http.dart';
part 'author_block_http.dart';
part 'post_interactions_http.dart';
part 'post_reposts_http.dart';

/// 仅访问构造时固定的 C HTTPS origin，不跟随重定向或自动重送命令。
class HttpPostApi
    implements
        PersonalCollectionsApi,
        PostApi,
        PostEditApi,
        PostMediaApi,
        FeedApi,
        HiddenPostApi,
        AuthorBlockApi,
        PostInteractionsApi,
        PostRepostsApi,
        PostSearchApi,
        PostRankingApi,
        PostSharingApi,
        PostTagApi,
        DmApi {
  HttpPostApi({
    required Uri communityBaseUri,
    HttpClient? client,
    Duration timeout = const Duration(seconds: 15),
  }) : _transport = PostHttpTransport(
         communityBaseUri: communityBaseUri,
         client: client,
         timeout: timeout,
       );

  final PostHttpTransport _transport;
  late final HttpPostDiscoveryApi _discovery = HttpPostDiscoveryApi(_transport);
  Uri get communityBaseUri => _transport.communityBaseUri;
  Duration get timeout => _transport.timeout;
  HttpClient get _client => _transport.client;
  void close() => _transport.close();

  @override
  Future<PostResponse<PostShareLink>> shareLink({
    required String sessionToken,
    required String postId,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/posts/${PostProtocol.resourceId(postId)}/share',
      decode: (raw) => PostShareLink.fromJson(raw, communityBaseUri, postId),
    ),
  );

  @override
  Future<PostResponse<PostDetail>> resolvePostLink({
    required String sessionToken,
    required String url,
  }) => _input(() {
    final target = PostLinkTarget.parse(url, communityBaseUri);
    if (target == null || target.url != url) {
      throw const FormatException('Invalid share URL');
    }
    return _send(
      sessionToken,
      'POST',
      '/api/v1/post-links/resolve',
      body: {'url': url},
      maxRequestBytes: 4096,
      maxResponseBytes: 512 * 1024,
      withEditedAt: (post, at) {
        if (at.isBefore(post.publishedAt)) {
          throw const FormatException('Invalid last modification time');
        }
        return post.withEditedAt(at);
      },
      decode: (raw) {
        final value = PostJson.record(raw, {'post'});
        final post = PostDetail.fromJson(value['post']);
        if (post.postId != target.postId) {
          throw const FormatException('Mismatched original post');
        }
        return post;
      },
    );
  });

  @override
  Future<PostResponse<PostsPage<PostCard>>> taggedPosts({
    required String sessionToken,
    required String tag,
    String? channelId,
    String? cursor,
    int limit = 20,
  }) => _discovery.taggedPosts(
    sessionToken: sessionToken,
    tag: tag,
    channelId: channelId,
    cursor: cursor,
    limit: limit,
  );
  @override
  Future<PostResponse<List<String>>> suggestPostTags({
    required String sessionToken,
    required String prefix,
  }) => _discovery.suggestPostTags(sessionToken: sessionToken, prefix: prefix);
  @override
  Future<PostResponse<PostRepostSnapshot>> postReposts({
    required String sessionToken,
    required String postId,
  }) => _repostRequest(sessionToken, postId);
  @override
  Future<PostResponse<PostRepostSnapshot>> setPostRepost({
    required String sessionToken,
    required String postId,
    required String identityId,
    required bool reposted,
    required String version,
  }) => _repostRequest(
    sessionToken,
    postId,
    identity: identityId,
    enabled: reposted,
    version: version,
  );
  @override
  Future<PostResponse<PostsPage<RepostedPost>>> ownReposts({
    required String sessionToken,
    String? cursor,
    int limit = 20,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/reposts',
      query: _pageQuery(cursor, limit),
      maxResponseBytes: 24 * 1024 * 1024,
      decode: (raw) {
        final page = PostsPage.fromJson(raw, RepostedPost.fromJson);
        if (page.items.length > limit ||
            page.items.map((i) => i.key).toSet().length != page.items.length) {
          throw const FormatException('Invalid repost page');
        }
        return page;
      },
    ),
  );

  @override
  Future<PostResponse<Map<String, dynamic>>> dmRequest(
    String token,
    String method,
    String resource, {
    Map<String, Object>? body,
    Map<String, String>? query,
  }) => _input(() {
    if (resource.startsWith('governance/blocks')) {
      if (resource != 'governance/blocks') {
        final parts = resource.split('/');
        if (parts.length != 3 || parts[1] != 'blocks') {
          throw const FormatException('Invalid DM governance route');
        }
        PostProtocol.resourceId(parts[2]);
      }
    } else if (resource.startsWith('chat/')) {
      final parts = resource.split('/');
      if (!{
            'pending',
            'conversations',
            'controls',
            'control-ack',
            'operations',
            'images',
            'media',
            'posts',
          }.contains(parts[1]) ||
          parts.length > 3) {
        throw const FormatException('Invalid DM chat route');
      }
      if (parts.length == 3) PostProtocol.resourceId(parts[2]);
    } else if (!{
      'pending',
      'conversations',
      'ack',
      'read',
      'contact',
    }.contains(resource)) {
      if (!resource.startsWith('commands/')) {
        throw const FormatException('Invalid DM route');
      }
      final parts = resource.split('/');
      if (parts.length != 2 &&
          !(parts.length == 3 && parts[2] == 'close' && method == 'POST')) {
        throw const FormatException('Invalid DM command route');
      }
      PostProtocol.resourceId(parts[1]);
    }
    return _send(
      token,
      method,
      '/api/v1/dm/$resource',
      headers: const {'X-DM-Post-Cards': 'v1'},
      body: body,
      query: query,
      maxRequestBytes: resource.startsWith('chat/images/')
          ? 15 * 1024 * 1024
          : 100000,
      maxResponseBytes: resource.startsWith('chat/media/')
          ? 15 * 1024 * 1024
          : 8 * 1024 * 1024,
      decode: (raw) => decodeDm(raw, resource),
    );
  });

  @override
  Future<PostResponse<List<PostInteractions>>> interactions({
    required String sessionToken,
    required List<String> postIds,
  }) => _input(() {
    if (postIds.isEmpty ||
        postIds.length > 50 ||
        postIds.toSet().length != postIds.length) {
      throw const FormatException('Invalid interaction batch');
    }
    for (final id in postIds) {
      PostProtocol.resourceId(id);
    }
    return _send(
      sessionToken,
      'POST',
      '/api/v1/feed/interactions',
      body: {'postIds': postIds},
      maxRequestBytes: 4096,
      decode: (raw) {
        final m = PostJson.record(raw, {'items'});
        final items = m['items'];
        if (items is! List || items.length != postIds.length) {
          throw const FormatException('Invalid interaction batch');
        }
        final values = items.map(PostInteractions.fromJson).toList();
        for (var i = 0; i < values.length; i++) {
          if (values[i].postId != postIds[i]) {
            throw const FormatException('Mismatched interaction batch');
          }
        }
        return values;
      },
    );
  });
  @override
  Future<PostResponse<PostInteractions>> postInteractions({
    required String sessionToken,
    required String postId,
  }) => _interactionRequest(sessionToken, postId);
  @override
  Future<PostResponse<PostInteractions>> setPostLike({
    required String sessionToken,
    required String postId,
    required bool liked,
    required String version,
  }) => _interactionRequest(
    sessionToken,
    postId,
    action: 'like',
    desired: liked,
    version: version,
  );
  @override
  Future<PostResponse<PostInteractions>> setPostFavorite({
    required String sessionToken,
    required String postId,
    required bool favorited,
    required String version,
  }) => _interactionRequest(
    sessionToken,
    postId,
    action: 'favorite',
    desired: favorited,
    version: version,
  );

  @override
  Future<PostResponse<PostsPage<FeedPost>>> timeline({
    required String sessionToken,
    String? channelId,
    String? cursor,
    int limit = 20,
  }) => _timeline(
    sessionToken: sessionToken,
    channelId: channelId,
    cursor: cursor,
    limit: limit,
  );
  @override
  Future<PostResponse<AuthorProfile>> authorProfile({
    required String sessionToken,
    required String postId,
    String? cursor,
    int limit = 20,
  }) => _authorProfile(
    sessionToken: sessionToken,
    postId: postId,
    cursor: cursor,
    limit: limit,
  );
  @override
  Future<PostResponse<FeedPreferences>> feedPreferences({
    required String sessionToken,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/feed-preferences',
      decode: FeedPreferences.fromJson,
    ),
  );
  @override
  Future<PostResponse<FeedPreferences>> saveFeedPreferences({
    required String sessionToken,
    required Set<String> blockedChannelIds,
  }) => _input(() {
    final ids = FeedPreferences(blockedChannelIds).blockedChannelIds.toList()
      ..sort();
    return _send(
      sessionToken,
      'PUT',
      '/api/v1/me/feed-preferences',
      body: {'blockedChannelIds': ids},
      decode: FeedPreferences.fromJson,
    );
  });
  @override
  Future<PostResponse<HiddenPostState>> hiddenPost({
    required String sessionToken,
    required String postId,
  }) => _hiddenPostRequest(sessionToken, postId);

  @override
  Future<PostResponse<HiddenPostState>> setHiddenPost({
    required String sessionToken,
    required String postId,
    required bool hidden,
    required String version,
  }) => _hiddenPostRequest(
    sessionToken,
    postId,
    hidden: hidden,
    version: version,
  );

  Future<PostResponse<HiddenPostState>> _hiddenPostRequest(
    String token,
    String id, {
    bool? hidden,
    String? version,
  }) => _input(() {
    if (hidden != null &&
        (version == null || !_validInteractionVersion(version))) {
      throw const FormatException('Hidden post write requires a version');
    }
    return _send(
      token,
      hidden == null ? 'GET' : 'PUT',
      '/api/v1/posts/${PostProtocol.resourceId(id)}/hidden',
      body: hidden == null ? null : {'hidden': hidden},
      headers: {if (version != null) 'If-Interaction-Version': version},
      readInteractionVersion: true,
      decode: (raw) {
        final result = HiddenPostState.fromJson(raw);
        if (result.postId != id || hidden != null && result.hidden != hidden) {
          throw const FormatException('Mismatched hidden post result');
        }
        return result;
      },
    );
  });

  @override
  Future<PostResponse<AuthorBlockReceipt>> blockPostAuthor({
    required String sessionToken,
    required String postId,
  }) => _blockPostAuthor(sessionToken: sessionToken, postId: postId);

  @override
  Future<PostResponse<BlockedAuthorPage>> blockedAuthors({
    required String sessionToken,
  }) => _blockedAuthors(sessionToken: sessionToken);

  @override
  Future<PostResponse<AuthorBlockRemoval>> unblockAuthor({
    required String sessionToken,
    required String blockId,
  }) => _unblockAuthor(sessionToken: sessionToken, blockId: blockId);

  @override
  Future<PostResponse<PostViews>> registerPostView({
    required String sessionToken,
    required String postId,
  }) => _input(
    () => _send(
      sessionToken,
      'POST',
      '/api/v1/posts/${PostProtocol.resourceId(postId)}/views',
      decode: (raw) {
        final result = PostViews.fromJson(raw);
        if (result.postId != postId) {
          throw const FormatException('Mismatched view');
        }
        return result;
      },
    ),
  );

  @override
  Future<PostResponse<PostMediaManifest>> imageManifest({
    required String sessionToken,
    required String postId,
  }) => _input(() async {
    PostProtocol.resourceId(postId);
    final response = await _send(
      sessionToken,
      'GET',
      '/api/v1/posts/$postId/images',
      headers: const {'X-Post-Preview': 'thumbnail-v1'},
      decode: (raw) => PostMediaManifest.fromJson(raw, postId),
    );
    final until = response.value.accessValidUntil;
    if (!until.isAfter(response.serverTime) ||
        until.isAfter(response.serverTime.add(const Duration(seconds: 60))) ||
        until.isAfter(response.sessionExpiresAt)) {
      throw const PostFailure(kind: PostFailureKind.invalidResponse);
    }
    return response;
  });

  @override
  Future<PostResponse<Uint8List>> imageBytes({
    required String sessionToken,
    required String postId,
    required PostMediaImage image,
  }) => _input(() {
    image.validatePost(postId);
    return _send(
      sessionToken,
      'GET',
      image.path,
      binaryImage: image,
      maxResponseBytes: image.byteLength,
      decode: (raw) => raw as Uint8List,
    );
  });

  @override
  Future<PostResponse<PostCommandResult>> create({
    required String sessionToken,
    required String commandId,
    required String channelId,
    required String identityId,
    required String title,
    required String body,
    List<String> tags = const [],
  }) => _input(() {
    PostContentRules.validate(title, body);
    return _command(
      sessionToken,
      'PUT',
      '/api/v1/post-commands/${PostProtocol.commandId(commandId)}',
      operation: PostOperation.create,
      body: {
        'channelId': PostProtocol.resourceId(channelId),
        'identityId': PostProtocol.resourceId(identityId),
        'title': title,
        'body': body,
        if (tags.isNotEmpty) 'tags': PostTags.parse(tags),
      },
      expected: 202,
      maxRequestBytes: 262144,
    );
  });
  @override
  Future<PostResponse<PostCommandResult>> commandResult({
    required String sessionToken,
    required String commandId,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/post-commands/${PostProtocol.commandId(commandId)}',
      decode: PostCommandResult.fromJson,
    ),
  );
  @override
  Future<PostResponse<PostCommandResult>> seal({
    required String sessionToken,
    required String commandId,
    required PostOperation operation,
    required String requestDigest,
  }) => _input(
    () => _send(
      sessionToken,
      'POST',
      '/api/v1/post-commands/${PostProtocol.commandId(commandId)}/seal',
      body: {
        'operation': operation.wire,
        'requestDigest': PostProtocol.digestValue(requestDigest),
      },
      decode: (raw) {
        final r = PostCommandResult.fromJson(raw);
        if (r.state == PostCommandState.unknownNotObserved ||
            r.operation != null && r.operation != operation) {
          throw const FormatException('Invalid seal operation outcome');
        }
        return r;
      },
    ),
  );
  @override
  Future<PostResponse<PostsPage<PostTask>>> tasks({
    required String sessionToken,
    String? cursor,
    int limit = 20,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/post-tasks',
      query: _pageQuery(cursor, limit),
      maxResponseBytes: 24 * 1024 * 1024,
      decode: (raw) {
        final page = PostsPage.fromJson(raw, PostTask.fromJson);
        if (page.items.length > limit ||
            page.items.any(
              (task) =>
                  !task.visible ||
                  task.state != PostTaskState.accepted &&
                      task.state != PostTaskState.failed,
            )) {
          throw const FormatException('Invalid own task page');
        }
        return page;
      },
    ),
  );
  @override
  Future<PostResponse<PostTask>> task({
    required String sessionToken,
    required String taskId,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/post-tasks/${PostProtocol.resourceId(taskId)}',
      maxResponseBytes: 512 * 1024,
      decode: (raw) {
        final task = PostTask.fromJson(raw);
        if (task.taskId != taskId) {
          throw const FormatException('Mismatched task resource');
        }
        return task;
      },
    ),
  );
  @override
  Future<PostResponse<PostCommandResult>> cancel({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
  }) => _input(
    () => _command(
      sessionToken,
      'POST',
      '/api/v1/me/post-tasks/${PostProtocol.resourceId(taskId)}/cancel',
      operation: PostOperation.cancel,
      commandId: commandId,
      taskId: taskId,
      body: {
        'expectedAttemptVersion': PostProtocol.version(expectedAttemptVersion),
      },
      expectedAttemptVersion: expectedAttemptVersion,
    ),
  );
  @override
  Future<PostResponse<PostCommandResult>> retry({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
    required String title,
    required String body,
    List<String> tags = const [],
  }) => _input(() {
    PostContentRules.validate(title, body);
    return _command(
      sessionToken,
      'POST',
      '/api/v1/me/post-tasks/${PostProtocol.resourceId(taskId)}/retry',
      operation: PostOperation.retry,
      commandId: commandId,
      taskId: taskId,
      expected: 202,
      body: {
        'expectedAttemptVersion': PostProtocol.version(expectedAttemptVersion),
        'title': title,
        'body': body,
        if (tags.isNotEmpty) 'tags': PostTags.parse(tags),
      },
      expectedAttemptVersion: expectedAttemptVersion,
      maxRequestBytes: 262144,
    );
  });
  @override
  Future<PostResponse<PostCommandResult>> hide({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
  }) => _input(
    () => _command(
      sessionToken,
      'POST',
      '/api/v1/me/post-tasks/${PostProtocol.resourceId(taskId)}/hide',
      operation: PostOperation.hideTask,
      commandId: commandId,
      taskId: taskId,
      body: {
        'expectedAttemptVersion': PostProtocol.version(expectedAttemptVersion),
      },
      expectedAttemptVersion: expectedAttemptVersion,
    ),
  );
  @override
  Future<PostResponse<PostsPage<PostCard>>> feed({
    required String sessionToken,
    required String channelId,
    String? cursor,
    int limit = 20,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/channels/${PostProtocol.resourceId(channelId)}/posts',
      query: _pageQuery(cursor, limit),
      maxResponseBytes: 2 * 1024 * 1024,
      decode: (raw) {
        final page = PostsPage.fromJson(raw, PostCard.fromJson);
        if (page.items.length > limit ||
            page.items.any((p) => p.channelId != channelId)) {
          throw const FormatException('Invalid channel feed page');
        }
        return page;
      },
    ),
  );
  @override
  Future<PostResponse<PostDetail>> detail({
    required String sessionToken,
    required String postId,
  }) => _input(
    () => _send<PostDetail>(
      sessionToken,
      'GET',
      '/api/v1/posts/${PostProtocol.resourceId(postId)}',
      maxResponseBytes: 512 * 1024,
      withEditedAt: (post, at) {
        if (at.isBefore(post.publishedAt)) {
          throw const FormatException('Invalid last modification time');
        }
        return post.withEditedAt(at);
      },
      decode: (raw) {
        final post = PostDetail.fromJson(
          PostJson.record(raw, {'post'})['post'],
        );
        if (post.postId != postId) {
          throw const FormatException('Mismatched post resource');
        }
        return post;
      },
    ),
  );

  String _postEditPath(String id) =>
      '/api/v1/me/posts/${PostProtocol.resourceId(id)}';

  String _postEditCommand(String postId, String commandId) {
    AuthCrypto.decode(commandId, bytes: 16);
    return '${_postEditPath(postId)}/edit-commands/$commandId';
  }

  @override
  Future<PostResponse<PublishedPostEdit>> readEdit({
    required String sessionToken,
    required String postId,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '${_postEditPath(postId)}/edit',
      maxResponseBytes: 512 * 1024,
      decode: (raw) {
        final edit = PublishedPostEdit.fromJson(raw);
        if (edit.post.postId != postId) {
          throw const FormatException('Mismatched post edit resource');
        }
        return edit;
      },
    ),
  );

  @override
  Future<PostResponse<PostEditResult>> editResult({
    required String sessionToken,
    required String postId,
    required String commandId,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      _postEditCommand(postId, commandId),
      decode: PostEditResult.fromJson,
    ),
  );

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
  }) => _input(
    () => _send(
      sessionToken,
      'PUT',
      _postEditCommand(postId, commandId),
      maxRequestBytes: 256 * 1024,
      body: {
        'revision': PostProtocol.resourceId(revision),
        'title': title,
        'body': body,
        if (tags != null) 'tags': PostTags.parse(tags),
        if (imageIds != null)
          'imageIds': imageIds.map(PostProtocol.resourceId).toList(),
      },
      decode: PostEditResult.fromJson,
    ),
  );

  @override
  Future<PostResponse<bool>> stageEditImage({
    required String sessionToken,
    required String postId,
    required String commandId,
    required String imageId,
    required String mimeType,
    required Uint8List bytes,
  }) => _input(
    () => _send(
      sessionToken,
      'PUT',
      '${_postEditCommand(postId, commandId)}/images/${PostProtocol.resourceId(imageId)}',
      uploadBytes: bytes,
      uploadMime: mimeType,
      maxRequestBytes: PostMediaImage.maxBytes,
      decode: (raw) {
        PostJson.record(raw, {});
        return true;
      },
    ),
  );
  @override
  Future<PostResponse<PostsPage<PostCard>>> personalCollection({
    required String sessionToken,
    required bool favorites,
    String? cursor,
    int limit = 20,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      favorites ? '/api/v1/me/favorite-posts' : '/api/v1/me/liked-posts',
      query: _pageQuery(cursor, limit),
      maxResponseBytes: 2 * 1024 * 1024,
      decode: (raw) {
        final page = PostsPage.fromJson(raw, PostCard.fromJson);
        if (page.items.length > limit) {
          throw const FormatException('Invalid collection page size');
        }
        return page;
      },
    ),
  );

  @override
  Future<PostResponse<PostsPage<OwnPostCard>>> ownPosts({
    required String sessionToken,
    String? cursor,
    String? identityId,
    int limit = 20,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/posts',
      query: {
        ..._pageQuery(cursor, limit),
        if (identityId != null)
          'identityId': PostProtocol.resourceId(identityId),
      },
      maxResponseBytes: 2 * 1024 * 1024,
      decode: (raw) {
        final page = PostsPage.fromJson(raw, OwnPostCard.fromJson);
        if (page.items.length > limit) {
          throw const FormatException('Invalid own post page size');
        }
        return page;
      },
    ),
  );
  @override
  Future<PostResponse<PostCapabilities>> capabilities({
    required String sessionToken,
    required String postId,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/posts/${PostProtocol.resourceId(postId)}/capabilities',
      headers: const {'X-Post-Edit': 'v1'},
      decode: (raw) {
        final caps = PostCapabilities.fromJson(raw);
        if (caps.postId != postId) {
          throw const FormatException('Mismatched capabilities resource');
        }
        return caps;
      },
    ),
  );
  @override
  Future<PostResponse<PostCommandResult>> delete({
    required String sessionToken,
    required String commandId,
    required String postId,
  }) => _input(
    () => _command(
      sessionToken,
      'POST',
      '/api/v1/posts/${PostProtocol.resourceId(postId)}/delete',
      operation: PostOperation.deletePost,
      commandId: commandId,
      postId: postId,
    ),
  );
  @override
  Future<PostResponse<ComposerContext>> composerContext({
    required String sessionToken,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/me/post-composer-context',
      decode: ComposerContext.fromJson,
    ),
  );

  Future<PostResponse<PostCommandResult>> _command(
    String token,
    String method,
    String path, {
    required PostOperation operation,
    String? commandId,
    String? taskId,
    String? postId,
    int? expectedAttemptVersion,
    int expected = 200,
    Map<String, Object>? body,
    int maxRequestBytes = 1024,
  }) => _send(
    token,
    method,
    path,
    expected: expected,
    body: body,
    headers: commandId == null
        ? const {}
        : {'Idempotency-Key': PostProtocol.commandId(commandId)},
    maxRequestBytes: maxRequestBytes,
    decode: (raw) {
      final result = PostCommandResult.fromJson(raw);
      if (result.operation != operation ||
          result.state !=
              (expected == 202
                  ? PostCommandState.accepted
                  : PostCommandState.committed) ||
          taskId != null && result.taskId != taskId ||
          postId != null && result.postId != postId ||
          operation == PostOperation.create && result.attemptVersion != 1 ||
          operation == PostOperation.retry &&
              result.attemptVersion != expectedAttemptVersion! + 1 ||
          (operation == PostOperation.cancel ||
                  operation == PostOperation.hideTask) &&
              result.attemptVersion != expectedAttemptVersion) {
        throw const FormatException('Mismatched command receipt');
      }
      return result;
    },
  );

  @override
  Future<PostResponse<PostsPage<PostCard>>> searchPosts({
    required String sessionToken,
    required String keyword,
    String? channelId,
    String? postId,
    PostSearchSort sort = PostSearchSort.relevance,
    String? cursor,
    int limit = 20,
    bool recordHistory = false,
  }) => _discovery.searchPosts(
    sessionToken: sessionToken,
    keyword: keyword,
    channelId: channelId,
    postId: postId,
    sort: sort,
    cursor: cursor,
    limit: limit,
    recordHistory: recordHistory,
  );

  @override
  Future<PostResponse<List<String>>> postSearchHistory({
    required String sessionToken,
    String? channelId,
  }) => _discovery.postSearchHistory(
    sessionToken: sessionToken,
    channelId: channelId,
  );

  @override
  Future<PostResponse<List<String>>> changePostSearchHistory({
    required String sessionToken,
    String? channelId,
    String? removeKeyword,
  }) => _discovery.changePostSearchHistory(
    sessionToken: sessionToken,
    channelId: channelId,
    removeKeyword: removeKeyword,
  );

  @override
  Future<PostResponse<PostRanking>> hotPosts({required String sessionToken}) =>
      _discovery.hotPosts(sessionToken: sessionToken);

  static Map<String, String> _pageQuery(String? cursor, int limit) =>
      PostHttpTransport.pageQuery(cursor, limit);

  Future<T> _input<T>(Future<T> Function() call) =>
      PostHttpTransport.input(call);

  Future<PostResponse<T>> _send<T>(
    String token,
    String method,
    String path, {
    required T Function(Object?) decode,
    Map<String, Object>? body,
    Map<String, String> headers = const {},
    Map<String, String>? query,
    int expected = 200,
    int maxRequestBytes = 1024,
    int maxResponseBytes = 32768,
    PostMediaImage? binaryImage,
    bool readInteractionVersion = false,
    T Function(T, DateTime)? withEditedAt,
    Uint8List? uploadBytes,
    String? uploadMime,
    Duration? requestTimeout,
    int maxJsonItems = PostStrictJson.defaultMaxItems,
  }) => _transport.send(
    token,
    method,
    path,
    decode: decode,
    body: body,
    headers: headers,
    query: query,
    expected: expected,
    maxRequestBytes: maxRequestBytes,
    maxResponseBytes: maxResponseBytes,
    binaryImage: binaryImage,
    readInteractionVersion: readInteractionVersion,
    withEditedAt: withEditedAt,
    uploadBytes: uploadBytes,
    uploadMime: uploadMime,
    requestTimeout: requestTimeout,
    maxJsonItems: maxJsonItems,
  );

  static String _single(HttpHeaders headers, String key) =>
      PostHttpTransport.singleHeader(headers, key);

  static PostFailure _failure(
    int status,
    Object? raw,
    HttpHeaders headers,
    String requestId,
  ) => PostHttpTransport.failure(status, raw, headers, requestId);
}
