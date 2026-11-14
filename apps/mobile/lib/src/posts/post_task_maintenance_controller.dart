import 'package:flutter/foundation.dart';

import '../storage/post_store.dart';
import 'post_api.dart';
import 'post_draft_controller.dart';
import 'post_models.dart';
import 'post_protocol.dart';
import 'post_publication_context.dart';
import 'post_result_reconciler.dart';
import 'post_submission_controller.dart';
import 'post_tags.dart';
import 'post_upload_models.dart';

/// Owns deletion single-flight and durable maintenance preparation, using the
/// publication dispatcher/reconciler without replacing command or attempt IDs.
class PostTaskMaintenanceController extends ChangeNotifier {
  PostTaskMaintenanceController({
    required this._api,
    required this._drafts,
    required this._results,
    required this._submissions,
    required this._openContext,
    required this._onFailure,
    required this._newId,
    required this._clock,
    required this._isPostDeleted,
    required this._markPostDeleted,
    required this._canDelete,
  });
  final PostApi _api;
  final PostDraftController _drafts;
  final PostResultReconciler _results;
  final PostSubmissionController _submissions;
  final Future<PostPublicationContext> Function() _openContext;
  final void Function(Object) _onFailure;
  final String Function() _newId;
  final DateTime Function() _clock;
  final bool Function(String) _isPostDeleted;
  final void Function(String) _markPostDeleted;
  final Future<bool> Function(String) _canDelete;
  final _deleting = <String, Future<bool>>{};
  int _generation = 0;
  bool _disposed = false;

  void reset() {
    ++_generation;
    _deleting.clear();
  }

  bool _current(PostPublicationContext context, int generation) =>
      !_disposed && generation == _generation && context.isCurrent;
  Future<PostPublicationContext> _openScoped(int generation) async {
    if (_disposed || generation != _generation) {
      throw const StalePostPublication();
    }
    final context = await _openContext();
    if (!_current(context, generation)) throw const StalePostPublication();
    return context;
  }

  Future<T> _accept<T>(
    PostPublicationContext context,
    PostResponse<T> response,
  ) => context.accept(response);
  void _failure(Object error, PostPublicationContext? context, int generation) {
    if (_disposed || generation != _generation) return;
    if (context == null) {
      _onFailure(error);
    } else {
      context.reportFailure(error);
    }
  }

  Future<PostDraftEditor?> editFailedTask(String taskId) async {
    final generation = _generation;
    PostPublicationContext? a;
    try {
      a = await _openScoped(generation);
      final task = await _accept(
        a,
        await _api.task(sessionToken: a.token, taskId: taskId),
      );
      if (!task.canRetry ||
          task.state != PostTaskState.failed ||
          task.content == null) {
        return null;
      }
      final entry = await _entryForTask(a, task, generation);
      if (!_current(a, generation)) return null;
      if (PostResultReconciler.unresolved(entry)) {
        await _results.reconcile(entry.id);
        if (!_current(a, generation)) return null;
        a.setCommandMessage('原重试结果尚未核对完成，请先核对，不能另发新尝试。');
        _notify();
        return null;
      }
      final buffer = await a.store.findRetryBuffer(
        task.taskId,
        task.attemptVersion,
      );
      if (!_current(a, generation)) return null;
      final bufferId = buffer?.id ?? _newId();
      final images = DraftPostImage.list(
        buffer?.data['images'] ?? entry.data['images'],
      );
      if (buffer == null && images.isEmpty && task.content!.imageCount > 0) {
        a.setCommandMessage('此设备没有原草稿图片，请回原设备处理，原任务仍保留。');
        _notify();
        return null;
      }
      return PostDraftEditor(
        id: entry.id,
        channelId: task.channelId,
        accountId: a.accountId,
        authorityVersion: a.epoch,
        identityId: task.identityId,
        title: buffer?.data['title'] as String? ?? task.content!.title,
        body: buffer?.data['body'] as String? ?? task.content!.body,
        revision: entry.revision,
        persisted: buffer != null,
        isRetry: true,
        taskId: task.taskId,
        attemptVersion: task.attemptVersion,
        bufferId: bufferId,
        bufferRevision: buffer?.revision ?? 0,
        images: images,
        tags: PostTags.parse(buffer?.data['tags'] ?? task.content!.tags),
      )..saved = buffer != null;
    } catch (error) {
      _failure(error, a, generation);
      return null;
    }
  }

  Future<StoredPostEntry> _entryForTask(
    PostPublicationContext a,
    PostTask task,
    int generation,
  ) async {
    final entries = await a.store.list();
    if (!_current(a, generation)) throw const StalePostPublication();
    final match = entries.where(
      (e) =>
          !e.isDraft &&
          e.data['isRetryBuffer'] != true &&
          e.data['taskId'] == task.taskId,
    );
    if (match.isNotEmpty) return match.first;
    // 跨设备只有任务事实时，先创建本地维护锚点；它不能被恢复为普通草稿。
    final id = _newId();
    final data = <String, dynamic>{
      'channelId': task.channelId,
      'identityId': task.identityId,
      'title': task.content?.title ?? '',
      'body': task.content?.body ?? '',
      'tags': task.content?.tags ?? const <String>[],
      'editedAt': task.serverSortAt.toIso8601String(),
      'taskId': task.taskId,
      'postId': task.postId,
      'attemptVersion': task.attemptVersion,
    };
    final anchor = StoredPostIntent(
      commandId: _newId(),
      operation: 'TASK_ANCHOR',
      digest: PostProtocol.digest(
        PostProtocol.cancel(
          taskId: task.taskId,
          expectedAttemptVersion: task.attemptVersion,
        ),
      ),
      payload: {'taskId': task.taskId},
    );
    return a.store.createSubmitted(
      id,
      anchor,
      data,
      state: task.state.name.toUpperCase(),
    );
  }

  Future<void> cancelTask(String taskId) => _taskCommand(taskId, false);
  Future<void> hideTask(String taskId) => _taskCommand(taskId, true);
  Future<void> _taskCommand(String taskId, bool hide) async {
    final generation = _generation;
    PostPublicationContext? a;
    try {
      a = await _openScoped(generation);
      final task = await _accept(
        a,
        await _api.task(sessionToken: a.token, taskId: taskId),
      );
      if (hide ? !task.canHide : !task.canCancel) return;
      var entry = await _entryForTask(a, task, generation);
      if (!_current(a, generation)) return;
      if (PostResultReconciler.unresolved(entry)) {
        await _results.reconcile(entry.id);
        return;
      }
      final intent = StoredPostIntent(
        commandId: _newId(),
        operation: hide ? 'HIDE_TASK' : 'CANCEL',
        digest: PostProtocol.digest(
          hide
              ? PostProtocol.hide(
                  taskId: task.taskId,
                  expectedAttemptVersion: task.attemptVersion,
                )
              : PostProtocol.cancel(
                  taskId: task.taskId,
                  expectedAttemptVersion: task.attemptVersion,
                ),
        ),
        payload: {
          'taskId': task.taskId,
          'expectedAttemptVersion': task.attemptVersion,
        },
      );
      StoredPostEntry? next;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          next = await a.store.appendIntent(
            entry.id,
            entry.revision,
            intent,
            Map<String, dynamic>.from(entry.data)..['commandState'] = 'UNKNOWN',
          );
          break;
        } on PostStorageConflict {
          // Upload progress may update this same accepted row. Retry only the
          // unsent local CAS; never append over a newer command or attempt.
          final latest = await a.store.get(entry.id);
          if (!_current(a, generation)) return;
          if (latest == null ||
              PostResultReconciler.unresolved(latest) ||
              latest.state != entry.state ||
              latest.data['attemptVersion'] != task.attemptVersion ||
              latest.intents.last.commandId != entry.intents.last.commandId) {
            await _results.reconcile(entry.id);
            return;
          }
          entry = latest;
        }
      }
      if (next == null) throw const PostStorageConflict();
      if (!_current(a, generation)) return;
      await a.refreshLocal();
      await _submissions.send(a, next);
    } catch (error) {
      _failure(error, a, generation);
    }
  }

  Future<bool> deletePost(String postId) {
    if (_disposed) return Future.value(false);
    final pending = _deleting[postId];
    if (pending != null) return pending;
    final future = _deletePost(postId);
    _deleting[postId] = future;
    future.whenComplete(() {
      if (identical(_deleting[postId], future)) _deleting.remove(postId);
    });
    return future;
  }

  Future<bool> _deletePost(String postId) async {
    final generation = _generation;
    PostPublicationContext? a;
    try {
      a = await _openScoped(generation);
      if (_isPostDeleted(postId)) return true;
      final entries = await a.store.list();
      if (!_current(a, generation)) return false;
      final deleted = entries.any(
        (e) => e.data['postId'] == postId && e.state == 'DELETED',
      );
      if (deleted) {
        _markPostDeleted(postId);
        _notify();
        return true;
      }
      final unresolved = entries.where(
        (e) =>
            e.data['postId'] == postId &&
            e.intents.isNotEmpty &&
            e.intents.last.operation == 'DELETE_POST' &&
            PostResultReconciler.unresolved(e),
      );
      if (unresolved.isNotEmpty) {
        await _results.reconcile(unresolved.first.id);
        final resolved = await a.store.get(unresolved.first.id);
        return _current(a, generation) && resolved?.state == 'DELETED';
      }
      if (!await _canDelete(postId) || !_current(a, generation)) return false;
      final id = _newId();
      final data = <String, dynamic>{
        'postId': postId,
        'editedAt': _clock().toUtc().toIso8601String(),
        'title': '删除结果待核对',
        'body': '',
      };
      final intent = StoredPostIntent(
        commandId: _newId(),
        operation: 'DELETE_POST',
        digest: PostProtocol.digest(PostProtocol.delete(postId: postId)),
        payload: {'postId': postId},
      );
      final entry = await a.store.createSubmitted(id, intent, data);
      // Keep the durable deletion in the poll set if its first result read fails.
      await a.refreshLocal();
      if (!_current(a, generation)) return false;
      await _submissions.send(a, entry);
      final result = await a.store.get(id);
      return _current(a, generation) && result?.state == 'DELETED';
    } catch (error) {
      _failure(error, a, generation);
      return false;
    }
  }

  /// 明确未受理的 CREATE 才可复制为新编辑；原命令防重事实永久保留。
  Future<PostDraftEditor?> recoverUnaccepted(String id) async {
    final generation = _generation;
    PostPublicationContext? a;
    try {
      a = await _openScoped(generation);
      final entry = await a.store.get(id);
      if (!_current(a, generation) ||
          entry == null ||
          entry.intents.last.operation != 'CREATE' ||
          !{'NOT_ACCEPTED', 'REJECTED'}.contains(entry.state) ||
          entry.data['abandoned'] == true) {
        return null;
      }
      final editor =
          _drafts.newDraft(
              entry.data['channelId'] as String,
              accountId: a.accountId,
              authorityVersion: a.epoch,
            )
            ..title = entry.data['title'] as String? ?? ''
            ..body = entry.data['body'] as String? ?? ''
            ..tags = PostTags.parse(entry.data['tags'])
            ..identityId = entry.data['identityId'] as String?;
      editor.images.addAll(DraftPostImage.list(entry.data['images']));
      editor.mediaTouched = editor.images.isNotEmpty;
      if (!await _drafts.saveDraft(editor)) return null;
      if (!_current(a, generation)) return null;
      await a.store.compactTerminal(
        id,
        entry.revision,
        'NOT_ACCEPTED',
        Map<String, dynamic>.from(entry.data)..['abandoned'] = true,
      );
      await a.refreshLocal();
      return editor;
    } catch (error) {
      _failure(error, a, generation);
      return null;
    }
  }

  Future<void> discardUnaccepted(String id) async {
    final generation = _generation;
    PostPublicationContext? a;
    try {
      a = await _openScoped(generation);
      final entry = await a.store.get(id);
      if (!_current(a, generation) ||
          entry == null ||
          entry.intents.last.operation != 'CREATE' ||
          !{'NOT_ACCEPTED', 'REJECTED'}.contains(entry.state)) {
        return;
      }
      await a.store.compactTerminal(
        id,
        entry.revision,
        'NOT_ACCEPTED',
        Map<String, dynamic>.from(entry.data)..['abandoned'] = true,
      );
      await a.refreshLocal();
    } catch (error) {
      _failure(error, a, generation);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    reset();
    super.dispose();
  }
}
