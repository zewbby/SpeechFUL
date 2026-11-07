// Real HTTP adapter and strict TLS. The launcher owns the disposable lab and
// credentials; this executable never prints capabilities or private message data.
import 'dart:convert';
import 'dart:io';

import 'package:hnuhole_mobile/src/posts/http_post_api.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';

void check(bool value) {
  if (!value) throw StateError('Probe check failed');
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    exitCode = 2;
    return;
  }
  HttpPostApi? api;
  var step = 'fixture';
  try {
    final f =
        jsonDecode(await File(args[0]).readAsString()) as Map<String, dynamic>;
    check(f['acceptanceTask'] == 'ANDROID-V1-ACCEPTANCE-01');
    final uri = Uri.parse(f['url'] as String);
    check(uri.scheme == 'https' && uri.host == '127.0.0.1');
    final trust = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(utf8.encode(f['certificatePem'] as String));
    api = HttpPostApi(
      communityBaseUri: uri,
      client: HttpClient(context: trust),
    );
    final a = f['senderToken'] as String,
        b = f['recipientToken'] as String,
        id = f['postId'] as String;
    step = 'minimal_preview';
    final card = (await api.dmRequest(a, 'GET', 'chat/posts/$id')).value;
    check(
      card.length == 4 &&
          card['postId'] == id &&
          card['title'] is String &&
          card['channelName'] is String,
    );
    step = 'eligible_directory';
    final directory = (await api.dmRequest(
      a,
      'GET',
      'chat/conversations',
      query: {'identityId': f['senderIdentityId'] as String},
    )).value;
    final conv = (directory['items'] as List)
        .cast<Map>()
        .where(
          (v) =>
              v['id'] == f['conversationId'] &&
              v['identityId'] == f['senderIdentityId'],
        )
        .single;
    check(conv['canShare'] == true);
    final command = dmId();
    final body = <String, Object>{
      'kind': 'POST',
      'identityId': f['senderIdentityId'] as String,
      'peerId': f['recipientIdentityId'] as String,
      'conversationId': f['conversationId'] as String,
      'sourcePostId': '',
      'sourceCommentId': '',
      'text': id,
      'attempt': 1,
    };
    step = 'reliable_send';
    final sent = (await api.dmRequest(
      a,
      'PUT',
      'commands/$command',
      body: body,
    )).value;
    check(sent['state'] == 'SENT');
    final duplicate = (await api.dmRequest(
      a,
      'PUT',
      'commands/$command',
      body: body,
    )).value;
    check(duplicate['messageId'] == sent['messageId']);
    step = 'typed_delivery';
    final pending = (await api.dmRequest(b, 'GET', 'chat/pending')).value;
    final item = (pending['items'] as List)
        .cast<Map>()
        .where((v) => v['messageId'] == sent['messageId'])
        .single;
    check(
      item['kind'] == 'POST' && item['text'] == id && item['media'] == null,
    );
    step = 'acknowledge_only_original';
    final ack = (await api.dmRequest(
      b,
      'POST',
      'ack',
      body: {
        'messageIds': [sent['messageId'] as String],
      },
    )).value;
    check(ack['state'] == 'APPLIED');
    final after = (await api.dmRequest(b, 'GET', 'chat/pending')).value;
    check(
      !(after['items'] as List).any((v) => v['messageId'] == sent['messageId']),
    );
    final receipt = (await api.dmRequest(a, 'GET', 'commands/$command')).value;
    check(
      receipt['state'] == 'SENT' && receipt['messageId'] == sent['messageId'],
    );
    await File(args[1]).writeAsString(
      jsonEncode({
        'result': 'PASS',
        'normalProductionHTTPAdapter': true,
        'strictTaskCA': true,
        'checks': [
          'minimal_current_preview',
          'eligible_mutual_identity_pair',
          'one_reliable_command',
          'typed_reference_delivery',
          'recipient_ack',
          'immutable_original_receipt',
        ],
        'messageId': sent['messageId'],
        'postId': id,
      }),
    );
  } catch (_) {
    await File(args[1])
        .writeAsString(jsonEncode({'result': 'FAIL', 'step': step}));
    exitCode = 1;
  } finally {
    api?.close();
  }
}
