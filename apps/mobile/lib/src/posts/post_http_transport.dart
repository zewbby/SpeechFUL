import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../auth/auth_crypto.dart';
import '../rate_limit.dart';
import 'post_api.dart';
import 'post_media_api.dart';
import 'post_models.dart';
import 'post_protocol.dart';
import 'post_upload_diagnostics.dart';

/// Owns fixed-origin I/O, strict decoding and transport error semantics.
class PostHttpTransport {
  PostHttpTransport({
    required this.communityBaseUri,
    HttpClient? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? HttpClient() {
    if (communityBaseUri.scheme != 'https' ||
        communityBaseUri.host.isEmpty ||
        communityBaseUri.userInfo.isNotEmpty ||
        communityBaseUri.hasQuery ||
        communityBaseUri.hasFragment ||
        communityBaseUri.path.isNotEmpty && communityBaseUri.path != '/' ||
        timeout <= Duration.zero) {
      throw ArgumentError(
        'A fixed C HTTPS origin and positive timeout are required',
      );
    }
    _client.connectionTimeout = timeout;
  }
  final Uri communityBaseUri;
  final Duration timeout;
  final HttpClient _client;
  HttpClient get client => _client;
  void close() => _client.close(force: true);

  Future<PostResponse<T>> send<T>(
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
  }) async {
    AuthCrypto.decode(token, bytes: 32);
    final bytes = body == null ? uploadBytes : utf8.encode(jsonEncode(body));
    if (bytes != null && bytes.length > maxRequestBytes) {
      throw const FormatException('Post request too large');
    }
    HttpClientRequest? active;
    int? status;
    var expired = false;
    final trace = PostUploadTrace.forRequest(
      method,
      path,
      body?['images'] is List,
    );
    try {
      return await (() async {
        final uri = communityBaseUri
            .resolve(path)
            .replace(queryParameters: query);
        final request = await _client.openUrl(method, uri);
        active = request;
        if (expired) {
          request.abort();
          throw const PostFailure(
            kind: PostFailureKind.transport,
            code: 'TIMEOUT',
          );
        }
        request.followRedirects = false;
        request.maxRedirects = 0;
        request.persistentConnection = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set('X-Post-Tags', 'v1');
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        for (final entry in headers.entries) {
          request.headers.set(entry.key, entry.value);
        }
        if (bytes != null) {
          request.headers.set(
            HttpHeaders.contentTypeHeader,
            uploadMime ?? 'application/json; charset=utf-8',
          );
          request.contentLength = bytes.length;
          request.add(bytes);
        }
        trace?.stage('send_body_and_wait_response');
        final response = await request.close();
        status = response.statusCode;
        trace?.response(status!, response.headers['x-request-id']);
        final limit = status == expected ? maxResponseBytes : 32768;
        if (response.contentLength > limit) {
          throw const FormatException('Oversized post response');
        }
        final data = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (data.length + chunk.length > limit) {
            throw const FormatException('Oversized post response');
          }
          data.add(chunk);
        }
        trace?.stage('validate_response');
        final h = response.headers;
        final requestId = singleHeader(h, 'x-request-id');
        AuthCrypto.decode(requestId, bytes: 16);
        if (singleHeader(h, 'cache-control') != 'no-store' ||
            h[HttpHeaders.setCookieHeader] != null) {
          throw const FormatException('Invalid post cache or cookie policy');
        }
        final type = ContentType.parse(
          singleHeader(h, HttpHeaders.contentTypeHeader),
        );
        final responseBytes = data.takeBytes();
        final Object? payload;
        if (status == expected && binaryImage != null) {
          if (type.mimeType != binaryImage.mimeType ||
              type.parameters.isNotEmpty ||
              responseBytes.isEmpty ||
              binaryImage.exactLength &&
                  responseBytes.length != binaryImage.byteLength ||
              singleHeader(h, 'x-content-type-options') != 'nosniff' ||
              singleHeader(h, 'content-disposition') != 'attachment') {
            throw const FormatException('Invalid protected image bytes');
          }
          payload = responseBytes;
        } else {
          if (type.mimeType != 'application/json' ||
              type.charset != null && type.charset!.toLowerCase() != 'utf-8') {
            throw const FormatException('Invalid post response type');
          }
          payload = PostStrictJson(
            utf8.decode(responseBytes, allowMalformed: false),
            maxItems: maxJsonItems,
          ).decode();
        }
        if (status != expected) throw failure(status!, payload, h, requestId);
        final serverTime = PostJson.utc(singleHeader(h, 'server-time'));
        final sessionExpiry = PostJson.utc(
          singleHeader(h, 'session-expires-at'),
        );
        if (!sessionExpiry.isAfter(serverTime)) {
          throw const FormatException('Invalid post session deadline');
        }
        final interactionVersion = readInteractionVersion
            ? singleHeader(h, 'interaction-version')
            : null;
        if (interactionVersion != null &&
            !validInteractionVersion(interactionVersion)) {
          throw const FormatException('Invalid interaction version');
        }
        var value = decode(payload);
        if (withEditedAt != null && h['post-edited-at'] != null) {
          final editedAt = PostJson.utc(singleHeader(h, 'post-edited-at'));
          if (editedAt.isAfter(serverTime)) {
            throw const FormatException('Invalid last modification time');
          }
          value = withEditedAt(value, editedAt);
        }
        trace?.succeed();
        return PostResponse<T>(
          value: value,
          serverTime: serverTime,
          sessionExpiresAt: sessionExpiry,
          requestId: requestId,
          statusCode: status!,
          interactionVersion: interactionVersion,
        );
      })().timeout(requestTimeout ?? timeout);
    } on PostFailure catch (error) {
      trace?.fail(error.kind.name);
      rethrow;
    } on TimeoutException {
      trace?.fail('timeout');
      expired = true;
      active?.abort();
      throw const PostFailure(kind: PostFailureKind.transport, code: 'TIMEOUT');
    } on FormatException {
      trace?.fail('invalid_response');
      active?.abort();
      throw PostFailure(
        kind: status == 401
            ? PostFailureKind.unauthorized
            : status == 503
            ? PostFailureKind.unavailable
            : PostFailureKind.invalidResponse,
        statusCode: status,
      );
    } on IOException {
      trace?.fail('network');
      active?.abort();
      // 接口不复制异常文本；命令是否受理只能在原账号、原 command 下核对。
      throw const PostFailure(kind: PostFailureKind.transport);
    } finally {
      trace?.finish();
    }
  }

  static String singleHeader(HttpHeaders headers, String key) {
    final values = headers[key];
    if (values == null || values.length != 1 || values.single.isEmpty) {
      throw const FormatException('Missing or ambiguous post response header');
    }
    return values.single;
  }

  static PostFailure failure(
    int status,
    Object? raw,
    HttpHeaders headers,
    String requestId,
  ) {
    // HTTP 错误不得提供成功续期元数据，尤其不能续期已持久拒绝的命令。
    if (headers['session-expires-at'] != null ||
        headers['server-time'] != null) {
      throw const FormatException('Unexpected renewal on post failure');
    }
    final m = PostJson.record(raw, {'error', 'requestId'});
    if (m['requestId'] != requestId) {
      throw const FormatException('Mismatched post request ID');
    }
    final e = PostJson.record(m['error'], {'code', 'message'});
    final code = PostJson.text(e, 'code');
    PostJson.text(e, 'message', maxLength: 256);
    final allowed = switch (status) {
      400 => {'MALFORMED_REQUEST', 'CURSOR_INVALID', 'POST_CONTENT_INVALID'},
      401 => {'AUTHENTICATION_FAILED', 'SESSION_INVALID', 'session_replaced'},
      403 => {
        'AUTHENTICATION_FAILED',
        'AUTHORIZATION_UNAVAILABLE',
        'POSTING_RESTRICTED',
        'ACCOUNT_CLOSING',
        'MEDIA_UPLOAD_DENIED',
      },
      404 => {
        'TASK_NOT_FOUND',
        'POST_NOT_FOUND',
        'POST_CHANNEL_UNAVAILABLE',
        'MEDIA_NOT_FOUND',
      },
      409 => {
        'COMMAND_CONFLICT',
        'COMMAND_SEALED',
        'RESULT_EXPIRED',
        ...PostJson.businessRejections,
        'MEDIA_UPLOAD_CLOSED',
        'POST_EDIT_DELETED',
        'POST_EDIT_HIDDEN',
        'POST_EDIT_CONFLICT',
        'POST_EDIT_MEDIA_LIMIT',
        'SELF_BLOCK_REJECTED',
      },
      413 => {'PAYLOAD_TOO_LARGE'},
      412 => {'INTERACTION_VERSION_CONFLICT'},
      415 => {'UNSUPPORTED_MEDIA_TYPE'},
      429 => {'RATE_LIMITED'},
      422 => {'MEDIA_INVALID'},
      503 => {
        'RANKINGS_UNAVAILABLE',
        'SHARED_RATE_UNAVAILABLE',
        'SERVICE_UNAVAILABLE',
        'AUTHORIZATION_UNAVAILABLE',
        'MEDIA_VALIDATOR_UNAVAILABLE',
      },
      _ => const <String>{},
    };
    if (!allowed.contains(code)) {
      throw const FormatException('Invalid post error status or code');
    }
    int? retry;
    if (status == 429) {
      final value = singleHeader(headers, 'retry-after');
      retry = parseRetryAfterSeconds(value);
    } else if (headers['retry-after'] != null) {
      throw const FormatException('Unexpected post retry delay');
    }
    return PostFailure(
      kind: status == 401
          ? PostFailureKind.unauthorized
          : status == 503
          ? PostFailureKind.unavailable
          : PostFailureKind.rejected,
      code: code,
      statusCode: status,
      requestId: requestId,
      retryAfterSeconds: retry,
    );
  }

  static Map<String, String> pageQuery(String? cursor, int limit) {
    if (limit < 1 || limit > 50) {
      throw const FormatException('Invalid page limit');
    }
    PostProtocol.cursor(cursor);
    return {'limit': '$limit', if (cursor != null) 'cursor': cursor};
  }

  static Future<T> input<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on FormatException {
      throw const PostFailure(
        kind: PostFailureKind.rejected,
        code: 'CLIENT_INPUT_INVALID',
      );
    }
  }

  static bool validInteractionVersion(String version) =>
      RegExp(r'^"[0-9a-f]{64}"$').hasMatch(version);
}

/// JSON 原生 decoder 会覆盖重复键；这里先做有界严格解析再校验 DTO。
class PostStrictJson {
  PostStrictJson(this.input, {this.maxItems = defaultMaxItems}) {
    if (maxItems < 1 || maxItems > 4096) {
      throw ArgumentError.value(maxItems, 'maxItems');
    }
  }

  /// Bounds every JSON array; the blocked-author list opts into its own bound.
  static const defaultMaxItems = 50;
  final String input;
  final int maxItems;
  int at = 0;
  Object? decode() {
    final value = _value(0);
    _space();
    if (at != input.length) throw const FormatException('Trailing JSON data');
    return value;
  }

  void _space() {
    while (at < input.length && ' \t\r\n'.contains(input[at])) {
      at++;
    }
  }

  Object? _value(int depth) {
    if (depth > 16) throw const FormatException('JSON nesting too deep');
    _space();
    if (at >= input.length) throw const FormatException('Missing JSON value');
    final c = input[at];
    if (c == '{') {
      at++;
      _space();
      final result = <String, Object?>{};
      if (_consume('}')) return result;
      while (true) {
        _space();
        final key = _string();
        _space();
        if (!_consume(':') || result.containsKey(key)) {
          throw const FormatException('Invalid JSON key');
        }
        result[key] = _value(depth + 1);
        _space();
        if (_consume('}')) return result;
        if (!_consume(',')) throw const FormatException('Invalid JSON object');
      }
    }
    if (c == '[') {
      at++;
      _space();
      final result = <Object?>[];
      if (_consume(']')) return result;
      while (true) {
        if (result.length >= maxItems) {
          throw const FormatException('JSON list too large');
        }
        result.add(_value(depth + 1));
        _space();
        if (_consume(']')) return result;
        if (!_consume(',')) throw const FormatException('Invalid JSON array');
      }
    }
    if (c == '"') return _string();
    if (input.startsWith('true', at)) {
      at += 4;
      return true;
    }
    if (input.startsWith('false', at)) {
      at += 5;
      return false;
    }
    if (input.startsWith('null', at)) {
      at += 4;
      return null;
    }
    final match = RegExp(r'-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?')
        .matchAsPrefix(input, at);
    if (match == null) throw const FormatException('Invalid JSON value');
    at = match.end;
    final number = num.tryParse(match.group(0)!);
    if (number == null || !number.isFinite) {
      throw const FormatException('Invalid JSON number');
    }
    return number;
  }

  String _string() {
    if (at >= input.length || input[at] != '"') {
      throw const FormatException('Missing JSON string');
    }
    final start = at++;
    while (at < input.length) {
      final c = input[at++];
      if (c == '"') {
        final value = jsonDecode(input.substring(start, at)) as String;
        PostContentRules.scalarText(value);
        return value;
      }
      if (c == '\\') {
        if (at >= input.length) {
          throw const FormatException('Incomplete JSON escape');
        }
        at++;
      }
    }
    throw const FormatException('Incomplete JSON string');
  }

  bool _consume(String c) {
    if (at < input.length && input[at] == c) {
      at++;
      return true;
    }
    return false;
  }
}
