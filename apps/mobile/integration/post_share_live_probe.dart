import 'dart:convert';
import 'dart:io';

import 'package:hnuhole_mobile/src/posts/http_post_api.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';

void check(bool value) {
  if (!value) throw StateError('Unexpected original-post result');
}

Future<void> main(List<String> args) async {
  if (args.length != 3 || args[1] != 'post-share') {
    exitCode = 2;
    return;
  }
  final output = File(args[2]);
  HttpPostApi? api;
  HttpClient? publicClient;
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
    api = HttpPostApi(
      communityBaseUri: origin,
      client: HttpClient(context: trust),
    );
    publicClient = HttpClient(context: trust);
    final token = fixture['readerToken'] as String;
    final id = fixture['postId'] as String;
    final url = '$origin/s/posts/$id';
    final expectedStatus = fixture['expectedStatus'] as int;
    if (expectedStatus == 200) {
      final shared = await api.shareLink(sessionToken: token, postId: id);
      check(shared.value.url == url && shared.value.text == 'SpeechFUL\n$url');
      final resolved = (await api.resolvePostLink(
        sessionToken: token,
        url: url,
      )).value;
      check(
        resolved.postId == id &&
            resolved.title == fixture['title'] &&
            resolved.body == fixture['body'] &&
            jsonEncode(resolved.tags) == jsonEncode(fixture['tags']),
      );
    } else {
      for (final read in [
        () => api!.shareLink(sessionToken: token, postId: id),
        () => api!.resolvePostLink(sessionToken: token, url: url),
      ]) {
        var rejected = false;
        try {
          await read();
        } on PostFailure catch (error) {
          rejected = error.statusCode == expectedStatus;
        }
        check(rejected);
      }
    }
    final response = await (await publicClient.getUrl(Uri.parse(url))).close();
    final page = await utf8.decoder.bind(response).join();
    check(
      response.statusCode == 200 &&
          page.contains('speechful://posts/$id') &&
          !page.contains(fixture['title'] as String) &&
          !page.contains(fixture['body'] as String) &&
          response.headers.value('Session-Expires-At') == null,
    );
    await output.writeAsString(jsonEncode({'status': 'PASS'}));
    stdout.writeln('PASS shipped Dart share/resolve and private public guide');
  } catch (error) {
    await output.writeAsString(
      jsonEncode({'status': 'FAIL', 'kind': error.runtimeType.toString()}),
    );
    stderr.writeln('FAIL shipped Dart post sharing');
    exitCode = 1;
  } finally {
    api?.close();
    publicClient?.close(force: true);
  }
}
