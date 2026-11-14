import 'dart:convert';

/// Device-local, bounded diagnostics. Never accepts URLs, bodies or credentials.
class PostUploadTrace {
  PostUploadTrace(this.operation) : trace = ++_sequence {
    _emit('start');
  }

  static int _sequence = 0;
  final String operation;
  final int trace;
  final Stopwatch _watch = Stopwatch()..start();
  String _stage = 'connect';
  String _outcome = 'error';
  int? _status;
  String? _requestId;
  bool _finished = false;

  static PostUploadTrace? forRequest(String method, String path, bool images) {
    if (images &&
        ((method == 'PUT' &&
                RegExp(r'^/api/v1/post-commands/[A-Za-z0-9_-]+$')
                    .hasMatch(path)) ||
            (method == 'POST' &&
                RegExp(r'^/api/v1/me/post-tasks/[0-9a-f-]+/retry$')
                    .hasMatch(path)))) {
      return PostUploadTrace('submit_images');
    }
    final imageRoute = RegExp(
      r'^/api/v1/me/post-tasks/[0-9a-f-]+/attempts/[0-9]+/images(?:/[0-9a-f-]+/upload-grant)?$',
    );
    if (!imageRoute.hasMatch(path)) return null;
    if (method == 'GET') return PostUploadTrace('check_images');
    if (method == 'POST' && path.endsWith('/upload-grant')) {
      return PostUploadTrace('upload_grant');
    }
    return null;
  }

  void stage(String value) {
    if (_finished) return;
    _stage = value;
    _emit('stage');
  }

  void response(int status, List<String>? requestIds) {
    if (_finished) return;
    _status = status;
    // Log only a canonical server-generated 16-byte request ID. A rejected
    // HTML/proxy response must not inject arbitrary header text into logs.
    if (requestIds?.length == 1) {
      final value = requestIds!.single;
      if (RegExp(r'^[A-Za-z0-9_-]{21}[AQgw]$').hasMatch(value)) {
        _requestId = value;
      }
    }
    stage('read_response');
  }

  void succeed() => _outcome = 'success';
  void fail(String category) => _outcome = category;

  void finish() {
    if (_finished) return;
    _finished = true;
    _emit('finish');
  }

  void _emit(String event) {
    try {
      // Keep this transport usable by plain Dart probes as well as Flutter.
      // Android's embedding forwards print to logcat in release builds too.
      // Never print an exception's text or a response payload.
      // ignore: avoid_print
      print(
        'POST_UPLOAD ${jsonEncode({'trace': trace, 'operation': operation, 'event': event, 'stage': _stage, 'elapsed_ms': _watch.elapsedMilliseconds, 'http_status': _status, 'request_id': _requestId, if (event == 'finish') 'outcome': _outcome})}',
      );
    } catch (_) {
      // Diagnostics must never change a publication's outcome.
    }
  }
}
