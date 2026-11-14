import 'dart:async';

import 'package:flutter/foundation.dart';

import '../rate_limit.dart';
import '../storage/post_store.dart';
import 'post_api.dart';
import 'post_draft_controller.dart';
import 'post_models.dart';
import 'post_protocol.dart';
import 'post_publication_context.dart';
import 'post_result_reconciler.dart';
import 'post_tags.dart';
import 'post_upload_api.dart';
import 'post_upload_models.dart';

/// Owns immutable intent preparation, single-flight publication and dispatch.
/// Receipt reconciliation belongs to PostResultReconciler.
class PostSubmissionController extends ChangeNotifier {
  PostSubmissionController({
    required this._api,
    required this._drafts,
    required this._results,
    required this._openContext,
    required this._editorCurrent,
    required this._onFailure,
    required this._newId,
    required this._clock,
    required this._accountId,
    required this._entries,
    this._uploadApi,
  });
  final PostApi _api;
  final PostDraftController _drafts;
  final PostResultReconciler _results;
  final Future<PostPublicationContext> Function() _openContext;
  final bool Function(PostDraftEditor) _editorCurrent;
  final void Function(Object) _onFailure;
  final String Function() _newId;
  final DateTime Function() _clock;
  final String? Function() _accountId;
  final Iterable<StoredPostEntry> Function() _entries;
  final PostUploadApi? _uploadApi;
  final _publishing = <String>{};
  final _sending = <String>{};
  int _pending = 0;
  bool _disposed = false;
  bool get busy => _pending > 0;
  // In-flight immutable commands retain their lifetime across account changes.
  void reset() => _publishing.clear();

  Future<bool> publish(PostDraftEditor e) async {
    if (!_editorCurrent(e) || e.submitted || !_publishing.add(e.id)) {
      return false;
    }
    PostPublicationContext? a;
    try {
      PostContentRules.validate(e.title, e.body, imageCount: e.images.length);
      if (e.mediaBusy || e.images.any((image) => !image.ready)) {
        e.error = '请移除或重新选择无法读取的图片。';
        return false;
      }
      if (e.images.isNotEmpty && _uploadApi == null) {
        e.error = '当前图片发布不可用，请稍后重试。';
        return false;
      }
      if (e.identityId == null) {
        e.error = '请先选择有效身份。';
        return false;
      }
      if (!await _drafts.saveDraft(e)) return false;
      a = await _openContext();
      if (!_editorCurrent(e)) return false;
      StoredPostEntry? retryOriginal;
      if (e.isRetry) {
        final original = await a.store.get(e.id);
        final task = await a.accept(
          await _api.task(sessionToken: a.token, taskId: e.taskId!),
        );
        if (original == null ||
            PostResultReconciler.unresolved(original) ||
            !task.canRetry ||
            task.state != PostTaskState.failed ||
            task.attemptVersion != e.attemptVersion ||
            task.channelId != e.channelId ||
            task.identityId != e.identityId) {
          e.error = '请先核对原任务；重试只能使用原身份、分类和当前失败版本。';
          return false;
        }
        e.revision = original.revision;
        retryOriginal = original;
      }
      final payload = e.isRetry
          ? <String, dynamic>{
              'taskId': e.taskId!,
              'expectedAttemptVersion': e.attemptVersion!,
              'title': e.title,
              'body': e.body,
              'tags': e.tags,
            }
          : <String, dynamic>{
              'channelId': e.channelId,
              'identityId': e.identityId!,
              'title': e.title,
              'body': e.body,
              'tags': e.tags,
            };
      final selections = [
        for (final image in e.images) image.selection!.toJson(),
      ];
      if (selections.isNotEmpty) payload['images'] = selections;
      final operation = e.isRetry ? PostOperation.retry : PostOperation.create;
      final digest = PostProtocol.digest(
        PostProtocol.withTags(
          PostProtocol.withImages(
            e.isRetry
                ? PostProtocol.retry(
                    taskId: e.taskId!,
                    expectedAttemptVersion: e.attemptVersion!,
                    title: e.title,
                    body: e.body,
                  )
                : PostProtocol.create(
                    channelId: e.channelId,
                    identityId: e.identityId!,
                    title: e.title,
                    body: e.body,
                  ),
            selections,
          ),
          e.tags,
        ),
      );
      final intent = StoredPostIntent(
        commandId: _newId(),
        operation: operation.wire,
        digest: digest,
        payload: payload,
      );
      final data = <String, dynamic>{
        if (retryOriginal != null) ...retryOriginal.data,
        ..._drafts.snapshot(e),
        'commandState': 'UNKNOWN',
      }..remove('mediaUploadPaused');
      final entry = e.isRetry
          ? await a.store.appendIntent(e.id, e.revision, intent, data)
          : await a.store.submitDraft(e.id, e.revision, intent, data);
      if (!a.isCurrent || !_editorCurrent(e)) return false;
      // A newly durable attempt must not inherit the previous upload's pause.
      // Old in-flight work still checks its original command/attempt fence.
      a.submissionRecorded(e.id);
      e.revision = entry.revision;
      e.submitted = true;
      e.saved = true;
      if (e.isRetry && e.persisted) {
        // 提交意图已落盘；旧编辑缓冲只含该尝试的副本，不能成为第二次提交。
        try {
          await a.store.deleteDraft(e.bufferId!, e.bufferRevision);
        } on PostStorageFailure {
          // 重启后以未决命令围栏阻止恢复这个缓冲；不重复发送来补偿清理失败。
        }
      }
      await a.refreshLocal();
      // 只有原提交上下文确实写入 SQLite 后，确认页才可以返回分类。
      unawaited(send(a, entry));
      return true;
    } catch (error) {
      if (_editorCurrent(e)) {
        e.error = '未能保存发布操作，内容仍保留，请重试。';
        _failure(error, a);
      }
      return false;
    } finally {
      _publishing.remove(e.id);
      _notify();
    }
  }

  Future<void> send(PostPublicationContext a, StoredPostEntry entry) async {
    final intent = entry.intents.last;
    if (!a.isCurrent || !_sending.add(intent.commandId)) return;
    _pending++;
    _notify();
    try {
      final p = intent.payload;
      final response = switch (intent.operation) {
        'CREATE' when p['images'] is List && (p['images'] as List).isNotEmpty =>
          await _uploadApi!.createWithImages(
            sessionToken: a.token,
            commandId: intent.commandId,
            channelId: p['channelId'] as String,
            identityId: p['identityId'] as String,
            title: p['title'] as String,
            body: p['body'] as String,
            tags: PostTags.parse(p['tags']),
            images: PostImageSelection.list(p['images']),
          ),
        'CREATE' => await _api.create(
          sessionToken: a.token,
          commandId: intent.commandId,
          channelId: p['channelId'] as String,
          identityId: p['identityId'] as String,
          title: p['title'] as String,
          body: p['body'] as String,
          tags: PostTags.parse(p['tags']),
        ),
        'RETRY' when p['images'] is List && (p['images'] as List).isNotEmpty =>
          await _uploadApi!.retryWithImages(
            sessionToken: a.token,
            commandId: intent.commandId,
            taskId: p['taskId'] as String,
            expectedAttemptVersion: p['expectedAttemptVersion'] as int,
            title: p['title'] as String,
            body: p['body'] as String,
            tags: PostTags.parse(p['tags']),
            images: PostImageSelection.list(p['images']),
          ),
        'RETRY' => await _api.retry(
          sessionToken: a.token,
          commandId: intent.commandId,
          taskId: p['taskId'] as String,
          expectedAttemptVersion: p['expectedAttemptVersion'] as int,
          title: p['title'] as String,
          body: p['body'] as String,
          tags: PostTags.parse(p['tags']),
        ),
        'CANCEL' => await _api.cancel(
          sessionToken: a.token,
          commandId: intent.commandId,
          taskId: p['taskId'] as String,
          expectedAttemptVersion: p['expectedAttemptVersion'] as int,
        ),
        'HIDE_TASK' => await _api.hide(
          sessionToken: a.token,
          commandId: intent.commandId,
          taskId: p['taskId'] as String,
          expectedAttemptVersion: p['expectedAttemptVersion'] as int,
        ),
        'DELETE_POST' => await _api.delete(
          sessionToken: a.token,
          commandId: intent.commandId,
          postId: p['postId'] as String,
        ),
        _ => throw const FormatException('Unknown original operation'),
      };
      await _results.applyResult(a, entry.id, intent, await a.accept(response));
    } catch (error) {
      if (error is PostFailure && error.statusCode == 429 && a.isCurrent) {
        await saveRateLimitedDraft(a, entry.id, error.retryAfterSeconds ?? 1);
        return;
      }
      // mutation 的409也先核对原回执；超时、503或写盘失败都不能变成新草稿。
      _failure(error, a, intent.commandId);
      if (a.isCurrent) unawaited(_results.reconcile(entry.id));
    } finally {
      _sending.remove(intent.commandId);
      _pending--;
      _notify();
    }
  }

  final _retryingRateLimited = <String>{};
  final _rateLimitWaits = <String, RateLimitWait>{};
  RateLimitWait _rateWait(String id, Map raw) {
    final key = '${_accountId()}:$id';
    final old = _rateLimitWaits[key];
    if (old != null &&
        old.recordedAt.toIso8601String() == raw['recordedAt'] &&
        old.seconds == raw['seconds']) {
      return old;
    }
    if (_rateLimitWaits.length >= 512) {
      _rateLimitWaits.remove(_rateLimitWaits.keys.first);
    }
    return _rateLimitWaits[key] = RateLimitWait.fromJson(raw);
  }

  int rateLimitedSeconds(String id) {
    final entry = _entries().where((e) => e.id == id).firstOrNull;
    final raw = entry?.data['rateLimitWait'];
    return raw is Map ? _rateWait(id, raw).remaining(_clock()) : 0;
  }

  int remainingRateLimit(String id, Map raw) =>
      _rateWait(id, raw).remaining(_clock());

  Future<void> saveRateLimitedDraft(
    PostPublicationContext a,
    String id,
    int seconds,
  ) async {
    final latest = await a.store.get(id);
    if (!a.isCurrent || latest == null) return;
    final data = Map<String, dynamic>.of(latest.data)
      ..['rateLimitWait'] = RateLimitWait(_clock(), seconds).toJson()
      ..['mediaUploadPaused'] = true;
    await a.store.recordResult(id, latest.revision, latest.state, data);
    if (!a.isCurrent) return;
    a.setCommandMessage(rateLimitDraftMessage(seconds));
    await a.refreshLocal();
  }

  /// A user action resumes the original immutable key. An unknown old request
  /// never turns into a fresh CREATE, even if this attempt received a 429.
  Future<void> retryRateLimited(String id) async {
    if (!_retryingRateLimited.add(id)) return;
    PostPublicationContext? a;
    try {
      a = await _openContext();
      var entry = await a.store.get(id);
      if (!a.isCurrent ||
          entry == null ||
          entry.data['rateLimitWait'] is! Map) {
        return;
      }
      final wait = _rateWait(
        id,
        entry.data['rateLimitWait'] as Map,
      ).remaining(_clock());
      if (wait > 0) {
        a.setCommandMessage(rateLimitDraftMessage(wait));
        _notify();
        return;
      }
      final intent = entry.intents.last;
      final result = await a.accept(
        await _api.commandResult(
          sessionToken: a.token,
          commandId: intent.commandId,
        ),
      );
      if (!a.isCurrent) return;
      final data = Map<String, dynamic>.of(entry.data)
        ..remove('rateLimitWait')
        ..remove('mediaUploadPaused');
      entry = await a.store.recordResult(id, entry.revision, entry.state, data);
      if (!a.isCurrent) return;
      if (result.state == PostCommandState.unknownNotObserved) {
        await send(a, entry);
      } else {
        await _results.applyResult(a, id, intent, result);
        final latest = await a.store.get(id);
        if (a.isCurrent && latest?.state == 'ACCEPTED') {
          await a.resumeImageUpload(id);
        }
      }
      if (a.isCurrent) await a.refreshLocal();
    } catch (error) {
      if (a != null &&
          a.isCurrent &&
          error is PostFailure &&
          error.statusCode == 429) {
        await saveRateLimitedDraft(a, id, error.retryAfterSeconds ?? 1);
      } else {
        _failure(error, a);
      }
    } finally {
      _retryingRateLimited.remove(id);
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

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
