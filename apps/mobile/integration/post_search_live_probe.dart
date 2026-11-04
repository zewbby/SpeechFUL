import 'dart:convert';
import 'dart:io';

import 'package:hnuhole_mobile/src/posts/http_post_api.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';
import 'package:hnuhole_mobile/src/posts/post_search_api.dart';

void check(bool condition) {
  if (!condition) throw StateError('unexpected search result');
}

Future<void> main(List<String> args) async {
  if (args.length != 3 || args[1] != 'post-search') {
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
    final reader = fixture['readerToken'] as String;
    final owner = fixture['ownerToken'] as String;
    final channel = fixture['channelId'] as String;
    final otherChannel = fixture['otherChannelId'] as String;

    step = 'classified_relevance_page';
    final first = (await client.searchPosts(
      sessionToken: reader,
      keyword: '自习',
      channelId: channel,
      recordHistory: true,
      limit: 1,
    )).value;
    check(
      first.items.single.postId == fixture['exactPostId'] &&
          first.nextCursor != null,
    );
    final second = (await client.searchPosts(
      sessionToken: reader,
      keyword: '自习',
      channelId: channel,
      cursor: first.nextCursor,
      limit: 1,
    )).value;
    check(
      second.items.single.postId == fixture['bodyPostId'] &&
          second.nextCursor == null,
    );

    step = 'detail_and_latest';
    final detail = (await client.detail(
      sessionToken: reader,
      postId: second.items.single.postId,
    )).value;
    check(detail.body == '今晚一起自习');
    final latest = (await client.searchPosts(
      sessionToken: reader,
      keyword: '自习',
      channelId: channel,
      sort: PostSearchSort.latest,
    )).value;
    check(latest.items.first.postId == fixture['bodyPostId']);

    step = 'scope_change';
    final grouped = (await client.searchPosts(
      sessionToken: reader,
      keyword: '自习',
    )).value.items;
    check(
      grouped.length == 3 &&
          grouped[0].channelId == channel &&
          grouped[1].channelId == channel &&
          grouped[2].channelId == otherChannel &&
          grouped[2].postId == fixture['otherPostId'],
    );
    final empty = (await client.searchPosts(
      sessionToken: reader,
      keyword: '找不到的词',
      channelId: otherChannel,
    )).value;
    check(empty.items.isEmpty && empty.nextCursor == null);

    step = 'cursor_authority';
    try {
      await client.searchPosts(
        sessionToken: owner,
        keyword: '自习',
        channelId: channel,
        cursor: first.nextCursor,
        limit: 1,
      );
      throw StateError('cursor crossed account');
    } on PostFailure catch (error) {
      check(error.code == 'CURSOR_INVALID');
    }

    step = 'history_scope_and_account';
    final ownHistory = (await client.postSearchHistory(
      sessionToken: reader,
      channelId: channel,
    )).value;
    final otherHistory = (await client.postSearchHistory(
      sessionToken: owner,
      channelId: channel,
    )).value;
    final allHistory = (await client.postSearchHistory(sessionToken: reader))
        .value;
    check(
      ownHistory.single == '自习' && otherHistory.isEmpty && allHistory.isEmpty,
    );
    final removed = (await client.changePostSearchHistory(
      sessionToken: reader,
      channelId: channel,
      removeKeyword: '自习',
    )).value;
    check(removed.isEmpty);
    final after = (await client.postSearchHistory(
      sessionToken: reader,
      channelId: channel,
    )).value;
    check(after.isEmpty);

    await output.writeAsString(jsonEncode({'status': 'PASS'}));
    stdout.writeln('PASS search real C HTTPS/SQL');
  } catch (error) {
    await output.writeAsString(
      jsonEncode({
        'status': 'FAIL',
        'step': step,
        'kind': error.runtimeType.toString(),
      }),
    );
    stderr.writeln('FAIL search at $step');
    exitCode = 1;
  } finally {
    api?.close();
  }
}
