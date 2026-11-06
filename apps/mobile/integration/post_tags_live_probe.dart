import 'dart:convert';
import 'dart:io';

import 'package:hnuhole_mobile/src/posts/http_post_api.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';

void check(bool condition) {
  if (!condition) throw StateError('unexpected tag result');
}

Future<void> main(List<String> args) async {
  if (args.length != 3 || args[1] != 'post-tags') {
    exitCode = 2;
    return;
  }
  final output = File(args[2]);
  HttpPostApi? api;
  var step = 'fixture';
  try {
    final fixture =
        jsonDecode(await File(args[0]).readAsString()) as Map<String, dynamic>;
    final origin = Uri.parse(fixture['url'] as String);
    check(
      origin.scheme == 'https' &&
          {'127.0.0.1', 'localhost', '::1'}.contains(origin.host),
    );
    final trust = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(
        utf8.encode(fixture['certificatePem'] as String),
      );
    final client = HttpPostApi(
      communityBaseUri: origin,
      client: HttpClient(context: trust),
    );
    api = client;
    final owner = fixture['ownerToken'] as String,
        reader = fixture['readerToken'] as String,
        post = fixture['postId'] as String;
    step = 'public_detail_and_feed';
    final detail = (await client.detail(
      sessionToken: reader,
      postId: post,
    )).value;
    check(detail.tags.join(',') == '篮球,NBA');
    final feed = (await client.timeline(sessionToken: reader)).value;
    check(feed.items.single.tags.join(',') == '篮球,NBA');
    step = 'exact_and_keyword_search';
    check(
      (await client.taggedPosts(
            sessionToken: reader,
            tag: 'nba',
          )).value.items.single.postId ==
          post,
    );
    check(
      (await client.searchPosts(
            sessionToken: reader,
            keyword: 'NBA',
          )).value.items.single.postId ==
          post,
    );
    check(
      (await client.suggestPostTags(
            sessionToken: reader,
            prefix: 'n',
          )).value.single ==
          'NBA',
    );
    step = 'edit_and_clear';
    var snapshot = (await client.readEdit(
      sessionToken: owner,
      postId: post,
    )).value;
    final saved = (await client.saveEdit(
      sessionToken: owner,
      postId: post,
      commandId: AuthCrypto.randomEncoded(16),
      revision: snapshot.revision,
      title: detail.title,
      body: detail.body,
      tags: ['食堂'],
    )).value;
    check(saved.state == 'SAVED');
    check(
      (await client.taggedPosts(
        sessionToken: reader,
        tag: '篮球',
      )).value.items.isEmpty,
    );
    check(
      (await client.searchPosts(
            sessionToken: reader,
            keyword: '食堂',
          )).value.items.single.postId ==
          post,
    );
    snapshot = (await client.readEdit(sessionToken: owner, postId: post)).value;
    check(
      (await client.saveEdit(
            sessionToken: owner,
            postId: post,
            commandId: AuthCrypto.randomEncoded(16),
            revision: snapshot.revision,
            title: detail.title,
            body: detail.body,
            tags: [],
          )).value.state ==
          'SAVED',
    );
    check(
      (await client.taggedPosts(
        sessionToken: reader,
        tag: '食堂',
      )).value.items.isEmpty,
    );
    step = 'tagged_create_and_task_recovery';
    final created = (await client.create(
      sessionToken: owner,
      commandId: AuthCrypto.randomEncoded(16),
      channelId: fixture['channelId'],
      identityId: fixture['identityId'],
      title: '新的安排',
      body: '一起跑步',
      tags: ['跑步'],
    )).value;
    final task = (await client.task(
      sessionToken: owner,
      taskId: created.taskId!,
    )).value;
    check(task.content!.tags.single == '跑步');
    await output.writeAsString(jsonEncode({'status': 'PASS'}));
    stdout.writeln('PASS tags real C HTTPS/SQL');
  } catch (error) {
    await output.writeAsString(
      jsonEncode({
        'status': 'FAIL',
        'step': step,
        'kind': error.runtimeType.toString(),
      }),
    );
    stderr.writeln('FAIL tags at $step');
    exitCode = 1;
  } finally {
    api?.close();
  }
}
