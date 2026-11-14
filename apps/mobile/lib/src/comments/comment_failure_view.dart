import '../localization/app_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../posts/post_photo_picker.dart';
import 'comment_http.dart';
import 'comment_models.dart';
import 'comment_runtime.dart';

/// A resource view inside the existing system notification detail. Every open
/// re-reads the real owner task, including its current permissions and target.
class CommentFailureView extends StatefulWidget {
  const CommentFailureView({
    super.key,
    required this.runtime,
    required this.taskId,
    this.identityId,
    this.onResolved,
  });
  final CommentRuntime runtime;
  final String taskId;
  final String? identityId;
  final VoidCallback? onResolved;
  @override
  State<CommentFailureView> createState() => _CommentFailureViewState();
}

class _CommentFailureViewState extends State<CommentFailureView> {
  late final int epoch = widget.runtime.authorityVersion;
  final text = TextEditingController();
  CommentTask? task;
  CommentImage? image;
  bool busy = false, missingImage = false;
  String? error, identityLabel, _targetNickname, _targetBody;
  bool _targetReply = false, _targetMissing = false, _identityMissing = false;
  final pickedBlobs = <String>{};
  bool get current => mounted && widget.runtime.current(epoch);

  CommentJournalEntry? get localEntry => widget.runtime.core.entries
      .where((e) => e.localId == widget.taskId)
      .firstOrNull;

  bool confirmedFailure(CommentTask t) {
    final entry = localEntry;
    // A fresh owner read also supports recovery on a second installation. An
    // existing command must first settle through the core's original receipt;
    // an old FAILED snapshot cannot resolve an unknown RETRY or ABANDON.
    if (entry == null) return true;
    final local = entry.task;
    return entry.transport == CommentTransportState.settled &&
        !entry.identityDeleted &&
        local?.state == CommentTaskState.failed &&
        local!.attemptVersion == t.attemptVersion &&
        local.binding.sameAs(t.binding);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!current) return;
    setState(() => busy = true);
    try {
      if (localEntry != null) {
        await widget.runtime.core.reconcile(widget.taskId);
        if (!current) return;
      }
      final raw = await widget.runtime.request(
        'GET',
        '/api/v1/me/comment-tasks/${widget.taskId}',
      );
      final t = HttpCommentApi.parseTask(raw);
      if (t.taskId != widget.taskId) {
        throw const FormatException('Wrong failure task');
      }
      final directory = await widget.runtime.directory();
      final identity = directory.identities
          .where((i) => i.id == t.binding.identityId)
          .firstOrNull;
      final label = identity?.nickname;
      String? targetNickname, targetBody;
      var targetMissing = false;
      if (t.binding.targetCommentId != null) {
        try {
          final row = await widget.runtime.request(
            'GET',
            '/api/v1/posts/${t.binding.postId}/comments/${t.binding.targetCommentId}',
          );
          targetNickname = (row['author'] as Map)['nickname'] as String?;
          targetBody = row['body'] as String?;
        } catch (_) {
          targetMissing = true;
        }
      }

      if (widget.identityId != null &&
          t.binding.identityId != widget.identityId) {
        throw const FormatException('Wrong failure identity');
      }
      final content = raw['content'] as Map?;
      final entry = widget.runtime.core.entries
          .where((e) => e.localId == t.taskId)
          .firstOrNull;
      if (!current) return;
      setState(() {
        task = t;
        text.text = entry?.content?.body ?? content?['body'] as String? ?? '';
        image = entry?.content?.image;
        missingImage = image == null && content?['image'] != null;
        _targetReply = t.binding.targetCommentId != null;
        _targetNickname = targetNickname;
        _targetBody = targetBody;
        _targetMissing = targetMissing;
        _identityMissing = identity == null;
        identityLabel = label;
        error = null;
      });
    } catch (_) {
      if (current) setState(() => error = '任务已移除或暂时无法读取，请重新核对。');
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  Future<void> _pick() async {
    try {
      final files = await NativePostPhotoPicker().pick(1);
      if (files.isEmpty) return;
      final result = await inspectPostPhoto(files.single, commentUUID());
      if (!current) return;
      final next = CommentImage(
        blobId: commentUUID(),
        selection: result.selection,
      );
      for (final id in pickedBlobs) {
        widget.runtime.journal.staged.remove(id);
      }
      pickedBlobs
        ..clear()
        ..add(next.blobId);
      widget.runtime.journal.staged[next.blobId] = result.bytes;
      setState(() {
        image = next;
        missingImage = false;
      });
    } catch (_) {
      if (current) setState(() => error = '图片无法读取，请重选；原文字和对象已保留。');
    }
  }

  Future<void> _act(bool abandon) async {
    if (!current || busy || task == null || !confirmedFailure(task!)) return;
    if (abandon) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(hhText(c, '放弃这份失败任务？')),
          content: Text(hhText(c, '将删除保留内容并移除失败通知。')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(hhText(c, '取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(hhText(c, '放弃任务')),
            ),
          ],
        ),
      );
      if (yes != true || !current) return;
    }
    setState(() => busy = true);
    try {
      final t = task!,
          entry = widget.runtime.core.entries
              .where((e) => e.localId == task!.taskId)
              .firstOrNull;
      final content = abandon
          ? null
          : CommentContent(body: text.text, image: image);
      if (entry != null) {
        if (abandon) {
          await widget.runtime.core.abandon(
            localId: t.taskId,
            commandId: commentKey(),
          );
        } else {
          await widget.runtime.core.retry(
            localId: t.taskId,
            commandId: commentKey(),
            content: content!,
          );
        }
      } else {
        await widget.runtime.core.recoverFailed(
          task: t,
          commandId: commentKey(),
          content: content,
          abandon: abandon,
        );
      }
      if (!current) return;
      await _load();
      if (!current) return;
      widget.onResolved?.call();
    } catch (_) {
      if (current) setState(() => error = '请核对任务结果后再操作。');
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  Future<void> _retarget() async {
    final t = task;
    if (!current ||
        busy ||
        t == null ||
        !confirmedFailure(t) ||
        !t.canAbandon ||
        widget.runtime.openRetarget == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(hhText(c, '保留内容并重新选择回复对象？')),
        content: Text(hhText(c, '先结束原失败任务，再返回原帖选择有效对象。不会自动发布。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(hhText(c, '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(hhText(c, '重新选择')),
          ),
        ],
      ),
    );
    if (!mounted || !current || confirmed != true) return;
    setState(() => busy = true);
    try {
      final content = CommentContent(body: text.text, image: image);
      final account = widget.runtime.accountId!;
      final bytes = image == null
          ? null
          : widget.runtime.journal.staged[image!.blobId] ??
                await widget.runtime.journal.bytes(account, image!);
      if (!current || !confirmedFailure(t)) return;
      final old = widget.runtime.core.entries
          .where((e) => e.localId == t.taskId)
          .firstOrNull;
      if (old != null) {
        await widget.runtime.core.abandon(
          localId: t.taskId,
          commandId: commentKey(),
        );
      } else {
        await widget.runtime.core.recoverFailed(
          task: t,
          commandId: commentKey(),
          abandon: true,
        );
      }
      if (!mounted || !current) return;
      if (!widget.runtime.core.resolvedTasks.any(
        (r) => r.taskId == t.taskId && r.state == CommentTaskState.abandoned,
      )) {
        setState(() => error = '原任务结果待核对，暂不更换对象。');
        return;
      }
      widget.onResolved?.call();
      await widget.runtime.openRetarget!(
        context,
        CommentRejectedInput(binding: t.binding, content: content),
        bytes,
      );
      if (current) await _load();
    } catch (_) {
      if (current) setState(() => error = '请先核对原任务结果，内容和对象已保留。');
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final id in pickedBlobs) {
      widget.runtime.journal.staged.remove(id);
    }
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return Text(hhText(context, '会话已变化，请返回。'));
    final t = task;
    final confirmed = t != null && confirmedFailure(t);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Semantics(liveRegion: true, child: Text(hhText(context, error!))),
        if (t != null) ...[
          Text(
            t.state == CommentTaskState.failed
                ? hhText(context, '发送失败')
                : hhText(
                    context,
                    '当前状态：{v0}',
                    args: {
                      'v0': hhText(context, switch (t.state) {
                        CommentTaskState.accepted => '处理中',
                        CommentTaskState.published => '已发布',
                        CommentTaskState.failed => '发送失败',
                        CommentTaskState.abandoned => '已放弃',
                      }),
                    },
                  ),
          ),
          Text(
            _targetReply && !_targetMissing
                ? '${hhText(context, '回复给 ')}${_targetNickname ?? ''}\n${_targetBody ?? ''}'
                : hhText(context, _targetMissing ? '原回复对象已删除或暂时无法读取' : '原帖子'),
          ),
          Text(
            hhText(
              context,
              '发言身份：{v0}',
              args: {
                'v0': _identityMissing
                    ? hhText(context, '原身份已失效')
                    : identityLabel ?? '',
              },
            ),
          ),
          if (t.state == CommentTaskState.failed) ...[
            if (!confirmed) Text(hhText(context, '任务结果待核对，请核对最新状态。')),
            TextField(
              controller: text,
              minLines: 3,
              maxLines: 8,
              enabled: !busy,
              decoration: InputDecoration(labelText: hhText(context, '保留内容')),
            ),
            if (image != null || missingImage)
              ListTile(
                title: Text(
                  missingImage
                      ? hhText(context, '本机缺少原图，请重选或移除后重试')
                      : hhText(context, '已保留 1 张图片'),
                ),
                trailing: IconButton(
                  tooltip: hhText(context, '移除图片'),
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          image = null;
                          missingImage = false;
                        }),
                  icon: const Icon(Icons.close),
                ),
              ),
            TextButton.icon(
              onPressed: busy ? null : _pick,
              icon: const Icon(Icons.image_outlined),
              label: Text(hhText(context, '选择一张图片')),
            ),
            if (t.failureCode == 'COMMENT_TARGET_DELETED' &&
                widget.runtime.openRetarget != null)
              TextButton(
                onPressed: busy || missingImage || !confirmed
                    ? null
                    : _retarget,
                child: Text(hhText(context, '保留内容，重新选择回复对象')),
              ),
            Wrap(
              children: [
                FilledButton(
                  onPressed: busy || missingImage || !confirmed || !t.canRetry
                      ? null
                      : () => _act(false),
                  child: Text(hhText(context, '按原身份和对象重试')),
                ),
                TextButton(
                  onPressed: busy || !confirmed || !t.canAbandon
                      ? null
                      : () => _act(true),
                  child: Text(hhText(context, '放弃任务')),
                ),
              ],
            ),
          ],
        ],
        TextButton(
          onPressed: busy ? null : _load,
          child: Text(hhText(context, '核对最新状态')),
        ),
      ],
    );
  }
}

/// Unknown submitted operations live in the unified notifications page. They
/// are labelled as unknown and never offered failure retry/abandon actions.
class CommentPendingView extends StatelessWidget {
  const CommentPendingView({
    super.key,
    required this.runtime,
    required this.identityId,
  });
  final CommentRuntime runtime;
  final String? identityId;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: runtime,
    builder: (context, _) => Column(
      children: [
        if (runtime.error != null) Text(hhText(context, runtime.error!)),
        for (final e in runtime.core.entries.where(
          (e) =>
              e.intent.binding.identityId == identityId &&
              (e.transport != CommentTransportState.settled ||
                  e.task?.state == CommentTaskState.accepted ||
                  e.rejectionCode != null),
        ))
          ListTile(
            title: Text(
              e.rejectionCode != null
                  ? hhText(context, '评论未受理')
                  : hhText(context, '评论结果待核对'),
            ),
            subtitle: Text(e.content?.body ?? hhText(context, '原任务内容已隔离')),
            trailing: TextButton(
              onPressed: () async {
                try {
                  if (e.transport == CommentTransportState.unknown) {
                    await runtime.sealUnknown(e.localId);
                  } else {
                    await runtime.core.reconcile(e.localId);
                  }
                } catch (_) {}
              },
              child: Text(hhText(context, '核对并停止迟到发送')),
            ),
          ),
        // Account-scoped mutation recovery is shown only in the account tab.
        for (final e in runtime.mutations.entries.where(
          (_) => identityId == null,
        ))
          ListTile(
            title: Text(
              e.value['operation'] == 'DELETE'
                  ? hhText(context, '删除结果待核对')
                  : hhText(context, '点赞结果待核对'),
            ),
            trailing: TextButton(
              onPressed: () => runtime.sealMutation(e.key),
              child: Text(hhText(context, '核对原操作')),
            ),
          ),
      ],
    ),
  );
}
