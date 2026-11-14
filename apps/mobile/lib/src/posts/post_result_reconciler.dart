import 'dart:async';

import '../storage/post_store.dart';
import 'post_api.dart';
import 'post_models.dart';
import 'post_protocol.dart';
import 'post_publication_context.dart';

/// Owns query deduplication, polling and durable receipt/task transitions.
/// Querying UNKNOWN never dispatches a mutation.
class PostResultReconciler {
  PostResultReconciler({
    required this._api,
    required this._openContext,
    required this._onFailure,
    required this._available,
    required this._entries,
  });
  final PostApi _api;
  final Future<PostPublicationContext> Function() _openContext;
  final void Function(Object) _onFailure;
  final bool Function() _available;
  final Iterable<StoredPostEntry> Function() _entries;
  final _checking = <String, Future<void>>{};
  Timer? _poller;
  static bool needsQuery(StoredPostEntry e) =>
      !e.isDraft && {'submitted', 'UNKNOWN', 'ACCEPTED'}.contains(e.state);
  static bool unresolved(StoredPostEntry e) =>
      e.data['rateLimitWait'] is Map ||
      {'submitted', 'UNKNOWN', 'RESULT_EXPIRED'}.contains(e.state);
  void startPolling(Duration interval) {
    if (interval <= Duration.zero) return;
    _poller = Timer.periodic(interval, (_) {
      if (!_available()) return;
      for (final entry in List<StoredPostEntry>.of(_entries())) {
        if (needsQuery(entry)) unawaited(reconcile(entry.id));
      }
    });
  }

  void reset() => _checking.clear();
  void dispose() => _poller?.cancel();

  static bool _isLocalPublicationTransition(
    StoredPostEntry entry,
    PostTask task,
  ) {
    if (task.state != PostTaskState.published ||
        !{'submitted', 'UNKNOWN', 'ACCEPTED'}.contains(entry.state) ||
        entry.intents.isEmpty) {
      return false;
    }
    final intent = entry.intents.last;
    final int? version = switch (intent.operation) {
      'CREATE' => 1,
      'RETRY' =>
        (intent.payload['expectedAttemptVersion'] as int?) == null
            ? null
            : (intent.payload['expectedAttemptVersion'] as int) + 1,
      _ => null,
    };
    return version == task.attemptVersion;
  }

  Future<void> reconcile(String id) async {
    final pending = _checking[id];
    if (pending != null) return pending;
    final future = _reconcile(id);
    _checking[id] = future;
    try {
      await future;
    } finally {
      if (identical(_checking[id], future)) _checking.remove(id);
    }
  }

  Future<void> _reconcile(String id) async {
    PostPublicationContext? a;
    String? commandId;
    try {
      a = await _openContext();
      final entry = await a.store.get(id);
      if (!a.isCurrent ||
          entry == null ||
          entry.isDraft ||
          entry.data['rateLimitWait'] is Map ||
          entry.intents.isEmpty) {
        return;
      }
      if ({
        'HIDDEN',
        'DELETED',
        'CANCELLED',
        'NOT_ACCEPTED',
      }.contains(entry.state)) {
        return;
      }
      final intent = entry.intents.last;
      commandId = intent.commandId;
      if (intent.operation == 'TASK_ANCHOR') {
        await applyTask(
          a,
          entry,
          await a.accept(
            await _api.task(
              sessionToken: a.token,
              taskId: entry.data['taskId'] as String,
            ),
          ),
        );
        return;
      }
      final result = await a.accept(
        await _api.commandResult(
          sessionToken: a.token,
          commandId: intent.commandId,
        ),
      );
      await applyResult(a, id, intent, result);
    } catch (error) {
      _failure(error, a, commandId);
    }
  }

  Future<void> seal(String id) async {
    PostPublicationContext? a;
    try {
      a = await _openContext();
      final entry = await a.store.get(id);
      if (!a.isCurrent ||
          entry == null ||
          entry.isDraft ||
          entry.intents.isEmpty ||
          !{'submitted', 'UNKNOWN'}.contains(entry.state)) {
        return;
      }
      final intent = entry.intents.last;
      if (intent.operation == 'TASK_ANCHOR') return;
      final operation = PostOperation.values.firstWhere(
        (v) => v.wire == intent.operation,
      );
      final result = await a.accept(
        await _api.seal(
          sessionToken: a.token,
          commandId: intent.commandId,
          operation: operation,
          requestDigest: intent.digest,
        ),
      );
      await applyResult(a, id, intent, result);
    } catch (error) {
      _failure(error, a);
    }
  }

  Future<void> applyResult(
    PostPublicationContext a,
    String id,
    StoredPostIntent intent,
    PostCommandResult result,
  ) async {
    if (!a.isCurrent) return;
    final entry = await a.store.get(id);
    if (!a.isCurrent ||
        entry == null ||
        entry.intents.last.commandId != intent.commandId) {
      return;
    }
    if (result.operation != null &&
        result.operation!.wire != intent.operation) {
      throw const PostFailure(kind: PostFailureKind.invalidResponse);
    }
    if (result.taskId != null &&
            intent.payload['taskId'] != null &&
            result.taskId != intent.payload['taskId'] ||
        result.postId != null &&
            intent.payload['postId'] != null &&
            result.postId != intent.payload['postId']) {
      throw const PostFailure(kind: PostFailureKind.invalidResponse);
    }
    var state = switch (result.state) {
      PostCommandState.unknownNotObserved => 'UNKNOWN',
      PostCommandState.accepted => 'ACCEPTED',
      PostCommandState.committed =>
        result.taskState?.name.toUpperCase() ??
            (intent.operation == 'HIDE_TASK' ? 'HIDDEN' : 'DELETED'),
      PostCommandState.rejected => 'REJECTED',
      PostCommandState.notAccepted => 'NOT_ACCEPTED',
      PostCommandState.resultExpired => 'RESULT_EXPIRED',
    };
    var data = Map<String, dynamic>.from(entry.data)
      ..['commandState'] = result.state.name
      ..['errorCode'] = result.errorCode;
    if (result.taskId != null) data['taskId'] = result.taskId;
    if (result.postId != null) data['postId'] = result.postId;
    if (result.attemptVersion != null) {
      data['attemptVersion'] = result.attemptVersion;
    }
    // 初始ACCEPTED是历史回执；当前终态必须另读 task，不能回退已有PUBLISHED。
    final taskId = data['taskId'] as String?;
    PostTask? observedTask;
    if (taskId != null &&
        result.state != PostCommandState.unknownNotObserved &&
        result.state != PostCommandState.resultExpired) {
      final task = await a.accept(
        await _api.task(sessionToken: a.token, taskId: taskId),
      );
      if (task.postId != data['postId'] ||
          task.identityId != data['identityId'] ||
          task.channelId != data['channelId']) {
        throw const PostFailure(kind: PostFailureKind.invalidResponse);
      }
      observedTask = task;
      state = task.visible
          ? task.state.name.toUpperCase()
          : task.state == PostTaskState.published
          ? 'PUBLISHED'
          : 'HIDDEN';
      data['attemptVersion'] = task.attemptVersion;
      data['editedAt'] = task.serverSortAt.toIso8601String();
      if (!task.contentAvailable && state == 'FAILED') {
        state = 'CONTENT_UNAVAILABLE';
      }
      if (!task.contentAvailable) {
        data.remove('title');
        data.remove('body');
        data.remove('tags');
      }
    }
    if ({
      'PUBLISHED',
      'CANCELLED',
      'HIDDEN',
      'DELETED',
      'CONTENT_UNAVAILABLE',
    }.contains(state)) {
      data.remove('title');
      data.remove('body');
      data.remove('tags');
    }
    if (!a.isCurrent) return;
    // 同一命令的并发核对可遇CAS竞争；下次核对读取最新revision即可，不重发。
    if (observedTask?.state == PostTaskState.cancelled) {
      await a.preserveCancelledImages(entry);
    }
    if ({
      'PUBLISHED',
      'CANCELLED',
      'HIDDEN',
      'DELETED',
      'CONTENT_UNAVAILABLE',
    }.contains(state)) {
      await a.store.compactTerminal(id, entry.revision, state, data);
    } else {
      await a.store.recordResult(id, entry.revision, state, data);
    }
    if (!a.isCurrent) return;
    await a.resultRecorded(
      PostResultUpdate(
        previous: entry,
        state: state,
        data: data,
        task: observedTask,
        commandState: result.state,
        announcePublication:
            result.state == PostCommandState.accepted &&
            observedTask != null &&
            _isLocalPublicationTransition(entry, observedTask),
      ),
    );
  }

  Future<void> applyTask(
    PostPublicationContext a,
    StoredPostEntry entry,
    PostTask task,
  ) async {
    if (!a.isCurrent ||
        task.taskId != entry.data['taskId'] ||
        task.postId != entry.data['postId'] ||
        task.identityId != entry.data['identityId'] ||
        task.channelId != entry.data['channelId']) {
      throw const StalePostPublication();
    }
    final data = Map<String, dynamic>.from(entry.data)
      ..['attemptVersion'] = task.attemptVersion
      ..['editedAt'] = task.serverSortAt.toIso8601String();
    final state = task.visible
        ? task.state.name.toUpperCase()
        : task.state == PostTaskState.published
        ? 'PUBLISHED'
        : 'HIDDEN';
    if (task.state == PostTaskState.cancelled) {
      await a.preserveCancelledImages(entry);
    }
    if (!task.contentAvailable && state == 'FAILED') {
      await a.store.compactTerminal(
        entry.id,
        entry.revision,
        'CONTENT_UNAVAILABLE',
        data,
      );
    } else if ({'PUBLISHED', 'CANCELLED', 'HIDDEN'}.contains(state)) {
      await a.store.compactTerminal(entry.id, entry.revision, state, data);
    } else {
      await a.store.recordResult(entry.id, entry.revision, state, data);
    }
    if (!a.isCurrent) return;
    await a.resultRecorded(
      PostResultUpdate(
        previous: entry,
        state: state,
        data: data,
        task: task,
        fromTask: true,
        announcePublication:
            entry.state == 'ACCEPTED' &&
            _isLocalPublicationTransition(entry, task),
      ),
    );
  }

  Future<void> dropRetryBuffers(PostPublicationContext a, PostTask task) async {
    final buffers = (await a.store.list())
        .where(
          (e) =>
              e.isDraft &&
              e.data['isRetryBuffer'] == true &&
              e.data['taskId'] == task.taskId &&
              (!task.contentAvailable ||
                  task.state != PostTaskState.failed ||
                  e.data['attemptVersion'] != task.attemptVersion),
        )
        .toList();
    if (!a.isCurrent) return;
    for (final buffer in buffers) {
      if (!a.isCurrent) return;
      await a.store.deleteDraft(buffer.id, buffer.revision);
    }
  }

  void _failure(
    Object error, [
    PostPublicationContext? context,
    String? commandId,
  ]) {
    if (context == null) {
      _onFailure(error);
    } else {
      context.reportFailure(error, commandId: commandId);
    }
  }
}
