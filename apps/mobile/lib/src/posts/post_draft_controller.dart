import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../storage/post_store.dart';
import 'post_protocol.dart';
import 'post_publication_context.dart';
import 'post_tags.dart';
import 'post_upload_models.dart';

/// 编辑输入只属于创建它的授权窗口；已受理重试永远保留原身份和分类。
class PostDraftEditor {
  PostDraftEditor({
    required this.id,
    required this.channelId,
    required this.accountId,
    required this.authorityVersion,
    this.identityId,
    this.title = '',
    this.body = '',
    this.revision = 0,
    this.persisted = false,
    this.isRetry = false,
    this.taskId,
    this.attemptVersion,
    this.bufferId,
    this.bufferRevision = 0,
    List<DraftPostImage>? images,
    List<String> tags = const [],
  }) : tags = PostTags.normalizeAll(tags),
       images = images ?? [];
  final String id, channelId, accountId;
  final int authorityVersion;
  final bool isRetry;
  final String? taskId;
  final int? attemptVersion;
  final String? bufferId;
  int bufferRevision;
  String? identityId;
  String title, body;
  int revision;
  bool persisted, saved = false, saving = false, submitted = false;
  String? error;
  final List<DraftPostImage> images;
  List<String> tags;
  final _originals = <String, Uint8List>{};
  bool mediaBusy = false, mediaTouched = false, pickerPending = false;
  String? mediaError;
  Map<String, Uint8List> originalsSnapshot() => Map.of(_originals);
  Uint8List? originalFor(String id) => _originals[id];
  void keepOriginal(String id, Uint8List bytes) => _originals[id] = bytes;
  void clearOriginals() => _originals.clear();
  void forgetSavedOriginals(Map<String, Uint8List> saved) {
    for (final key in saved.keys) {
      if (identical(_originals[key], saved[key])) _originals.remove(key);
    }
  }
}

/// Owns draft snapshots, revisions and serialized saves, never network commands.
class PostDraftController extends ChangeNotifier {
  PostDraftController({
    required this._openContext,
    required this._editorCurrent,
    required this._onFailure,
    required this._clock,
    required this._newId,
  });
  final Future<PostPublicationContext> Function() _openContext;
  final bool Function(PostDraftEditor) _editorCurrent;
  final void Function(Object) _onFailure;
  final DateTime Function() _clock;
  final String Function() _newId;
  final _saving = <String, Future<bool>>{};
  bool _disposed = false;
  PostDraftEditor newDraft(
    String channelId, {
    required String accountId,
    required int authorityVersion,
    String? identityId,
  }) {
    PostProtocol.resourceId(channelId);
    return PostDraftEditor(
      id: _newId(),
      channelId: channelId,
      accountId: accountId,
      authorityVersion: authorityVersion,
      identityId: identityId,
    );
  }

  Future<PostDraftEditor?> restoreDraft(String id) async {
    PostPublicationContext? a;
    try {
      a = await _openContext();
      final entry = await a.store.get(id);
      if (!a.isCurrent ||
          entry == null ||
          !entry.isDraft ||
          entry.data['isRetryBuffer'] == true) {
        return null;
      }
      return PostDraftEditor(
          id: entry.id,
          channelId: entry.data['channelId'] as String,
          accountId: a.accountId,
          authorityVersion: a.epoch,
          identityId: entry.data['identityId'] as String?,
          title: entry.data['title'] as String,
          body: entry.data['body'] as String,
          revision: entry.revision,
          persisted: true,
          images: DraftPostImage.list(entry.data['images']),
          tags: PostTags.parse(entry.data['tags']),
        )
        ..saved = true
        ..mediaError = entry.data['pickerInterrupted'] == true
            ? '上次选图被中断，请重新选择；已保存的图片仍保留。'
            : null;
    } catch (error) {
      _failure(error, a);
      return null;
    }
  }

  Map<String, dynamic> snapshot(PostDraftEditor e) => {
    'channelId': e.channelId,
    'identityId': e.identityId,
    'title': e.title,
    'body': e.body,
    'tags': e.tags,
    'editedAt': _clock().toUtc().toIso8601String(),
    if (e.taskId != null) 'taskId': e.taskId,
    if (e.attemptVersion != null) 'attemptVersion': e.attemptVersion,
    if (e.images.isNotEmpty || e.mediaTouched)
      'images': [for (final image in e.images) image.toJson()],
    if (e.pickerPending) 'pickerPending': true,
  };

  Future<bool> saveDraft(PostDraftEditor e) {
    if (e.submitted) return Future.value(false);
    final previous = _saving[e.id];
    final future = _saveDraft(e, previous);
    _saving[e.id] = future;
    future.whenComplete(() {
      if (identical(_saving[e.id], future)) _saving.remove(e.id);
    });
    return future;
  }

  Future<bool> _saveDraft(PostDraftEditor e, Future<bool>? previous) async {
    if (previous != null) await previous;
    if (!_editorCurrent(e) || e.submitted) return false;
    e.saving = true;
    e.error = null;
    final data = snapshot(e);
    try {
      final a = await _openContext();
      if (!_editorCurrent(e)) return false;
      // 空白新稿不落盘，也不能覆盖其他草稿。
      if (!e.persisted &&
          !PostContentRules.hasMeaningfulText(e.title) &&
          !PostContentRules.hasMeaningfulText(e.body) &&
          e.images.isEmpty &&
          !e.pickerPending) {
        e.saved = true;
        return true;
      }
      if (e.isRetry) data['isRetryBuffer'] = true;
      final id = e.bufferId ?? e.id;
      final revision = e.isRetry ? e.bufferRevision : e.revision;
      final originals = e.originalsSnapshot();
      final entry = e.images.isNotEmpty || e.mediaTouched || e.pickerPending
          ? await a.store.saveMediaDraft(
              id,
              e.persisted ? revision : null,
              data,
              originals,
            )
          : e.persisted
          ? await a.store.saveDraft(id, revision, data)
          : await a.store.createDraft(id, data);
      if (!a.isCurrent || !_editorCurrent(e)) return false;
      if (e.isRetry) {
        e.bufferRevision = entry.revision;
      } else {
        e.revision = entry.revision;
      }
      e.persisted = true;
      e.forgetSavedOriginals(originals);
      e.saved =
          e.title == data['title'] &&
          e.body == data['body'] &&
          listEquals(e.tags, PostTags.parse(data['tags'])) &&
          e.identityId == data['identityId'] &&
          jsonEncode(e.images.map((e) => e.toJson()).toList()) ==
              jsonEncode(data['images'] ?? []);
      await a.refreshLocal();
      return true;
    } catch (error) {
      if (_editorCurrent(e)) {
        e.error = '保存失败，请重试、复制文字，或明确放弃退出。';
        _failure(error);
      }
      return false;
    } finally {
      e.saving = false;
      _notify();
    }
  }

  Future<bool> discardDraft(PostDraftEditor e) async {
    if (!_editorCurrent(e) || e.submitted) return false;
    PostPublicationContext? a;
    try {
      final prior = _saving[e.id];
      if (prior != null) await prior;
      a = await _openContext();
      if (!_editorCurrent(e)) return false;
      if (e.persisted) {
        await a.store.deleteDraft(
          e.bufferId ?? e.id,
          e.isRetry ? e.bufferRevision : e.revision,
        );
      }
      if (!a.isCurrent) return false;
      e.persisted = false;
      e.revision = 0;
      await a.refreshLocal();
      return true;
    } catch (error) {
      _failure(error, a);
      return false;
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
