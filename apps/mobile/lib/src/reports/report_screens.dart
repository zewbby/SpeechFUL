import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
import '../posts/post_photo_picker.dart';
import '../system_notifications/governance_controller.dart';
import '../system_notifications/notification_models.dart';

class GovernanceScope extends InheritedWidget {
  const GovernanceScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final GovernanceController controller;
  static GovernanceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GovernanceScope>()?.controller;
  @override
  bool updateShouldNotify(GovernanceScope oldWidget) =>
      oldWidget.controller != controller;
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    required this.controller,
    required this.postId,
    required this.title,
    this.commentId,
  });
  final GovernanceController controller;
  final String postId, title;
  final String? commentId;
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String? _reason, _identity;
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!widget.controller.available) return;
    final loaded = await widget.controller.loadIdentities();
    if (!mounted || !widget.controller.available) return;
    setState(() {
      _identity =
          widget.controller.selectedIdentityId ??
          widget.controller.identities.firstOrNull?.id;
      _ready = loaded;
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return MaterialEvidenceForm(
        controller: c,
        title: hhText(context, '举报'),
        textLimit: 200,
        imageLimit: 6,
        descriptionLabel: hhText(context, '举报说明（选填）'),
        submitLabel: hhText(context, '提交举报'),
        enabled: _ready && _reason != null,
        summary: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _reason,
              decoration: InputDecoration(labelText: hhText(context, '举报原因')),
              items: [
                for (final entry in reportReasons.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(hhText(context, entry.value)),
                  ),
              ],
              onChanged: c.busy || c.pending != null
                  ? null
                  : (value) => setState(() => _reason = value),
            ),
            if (c.identities.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _identity,
                decoration: InputDecoration(
                  labelText: hhText(context, '接收举报进度的身份'),
                ),
                items: [
                  for (final i in c.identities)
                    DropdownMenuItem(value: i.id, child: Text(i.nickname)),
                ],
                onChanged: c.busy || c.pending != null
                    ? null
                    : (v) => setState(() => _identity = v),
              ),
            ],
            if (!_ready)
              TextButton(
                onPressed: _load,
                child: Text(hhText(context, '重新读取身份')),
              ),
            const SizedBox(height: 16),
            Text(hhText(context, '举报不代表违规成立。处理进度与结果会保存在系统通知。')),
          ],
        ),
        onSubmit: (text, images) => c.submitReport(
          postId: widget.postId,
          commentId: widget.commentId,
          identityId: _identity,
          reason: _reason!,
          description: text,
          images: images,
        ),
      );
    },
  );
}

/// Shared material input, without a persistent unsubmitted draft. Once an
/// intent reaches the vault, the immutable pending panel owns reconciliation.
class MaterialEvidenceForm extends StatefulWidget {
  const MaterialEvidenceForm({
    super.key,
    required this.controller,
    required this.title,
    required this.textLimit,
    required this.imageLimit,
    required this.summary,
    required this.onSubmit,
    this.descriptionLabel = '说明',
    this.submitLabel = '提交',
    this.enabled = true,
    this.hasExtraInput = false,
  });
  final GovernanceController controller;
  final String title, descriptionLabel, submitLabel;
  final int textLimit, imageLimit;
  final Widget summary;
  final bool enabled, hasExtraInput;
  final Future<bool> Function(String, List<EvidenceImage>) onSubmit;
  @override
  State<MaterialEvidenceForm> createState() => _MaterialEvidenceFormState();
}

class _MaterialEvidenceFormState extends State<MaterialEvidenceForm> {
  final _text = TextEditingController();
  final List<EvidenceImage> _images = [];
  late final String? _account = widget.controller.accountId;
  late final int _epoch = widget.controller.authorityVersion;
  bool _leaving = false, _picking = false;
  String? _selectionError;
  bool get _current =>
      widget.controller.available &&
      _account == widget.controller.accountId &&
      _epoch == widget.controller.authorityVersion;
  bool get _hasInput =>
      _text.text.isNotEmpty || _images.isNotEmpty || widget.hasExtraInput;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving || (_current && widget.controller.busy)) return;
    if (_current && widget.controller.pending == null && _hasInput) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(hhText(context, '放弃本次材料？')),
          content: Text(hhText(context, '尚未提交的说明和图片会被清除。')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(hhText(context, '继续填写')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(hhText(context, '放弃')),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) {
      setState(() => _leaving = true);
      Navigator.pop(context);
    }
  }

  Future<void> _pick() async {
    if (!_current ||
        _picking ||
        widget.controller.busy ||
        widget.controller.pending != null) {
      return;
    }
    setState(() {
      _picking = true;
      _selectionError = null;
    });
    try {
      final files = await NativePostPhotoPicker().pick(
        widget.imageLimit - _images.length,
      );
      final additions = <EvidenceImage>[];
      for (final file in files.take(widget.imageLimit - _images.length)) {
        final inspected = await inspectPostPhoto(file, governanceId());
        additions.add(
          EvidenceImage(inspected.selection.mimeType, inspected.bytes),
        );
      }
      validateMaterials(
        _text.text,
        [..._images, ...additions],
        textLimit: widget.textLimit,
        imageLimit: widget.imageLimit,
      );
      if (mounted && _current) setState(() => _images.addAll(additions));
    } on Object {
      if (mounted && _current) {
        setState(
          () => _selectionError = '图片未添加。请选择 PNG、JPEG、GIF 或 WebP，每张不超过 2 MiB，总计不超过 8 MiB。当前平台不支持时可先提交文字。',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    if (!_current ||
        widget.controller.busy ||
        widget.controller.pending != null) {
      return;
    }
    bool ok;
    try {
      validateMaterials(
        _text.text,
        _images,
        textLimit: widget.textLimit,
        imageLimit: widget.imageLimit,
      );
      ok = await widget.onSubmit(_text.text, List.unmodifiable(_images));
    } on Object {
      if (mounted && _current) {
        setState(() => _selectionError = '说明或图片超出本次额度，请检查后重试。');
      }
      return;
    }
    if (!mounted || !_current || !ok) return;
    _finish(true);
  }

  void _finish(bool submitted) {
    if (!mounted || !_current) return;
    if (submitted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(hhText(context, '已提交'))));
    }
    setState(() => _leaving = true);
    Navigator.pop(context, submitted);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        _leaving ||
        !_current ||
        (!_hasInput && widget.controller.pending == null),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(hhText(context, widget.title)),
        leading: BackButton(onPressed: _leave),
      ),
      body: !_current
          ? Center(child: Text(hhText(context, '会话已变化，请返回后重新进入。')))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                widget.summary,
                const SizedBox(height: 24),
                if (widget.controller.pending != null)
                  PendingGovernancePanel(
                    controller: widget.controller,
                    onResolved: _finish,
                  )
                else ...[
                  TextField(
                    controller: _text,
                    maxLength: widget.textLimit,
                    minLines: 4,
                    maxLines: 8,
                    enabled: !widget.controller.busy,
                    decoration: InputDecoration(
                      labelText: hhText(context, widget.descriptionLabel),
                      alignLabelWithHint: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    hhText(
                      context,
                      '补充图片 {count}/{limit}',
                      args: {
                        'count': _images.length,
                        'limit': widget.imageLimit,
                      },
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (var i = 0; i < _images.length; i++)
                        SizedBox(
                          width: 104,
                          child: Column(
                            children: [
                              Image.memory(
                                _images[i].bytes,
                                width: 96,
                                height: 96,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => SizedBox(
                                  height: 96,
                                  child: Center(
                                    child: Text(hhText(context, '图片不可预览')),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: widget.controller.busy
                                    ? null
                                    : () => setState(() => _images.removeAt(i)),
                                child: Text(
                                  hhText(
                                    context,
                                    '移除第{index}张',
                                    args: {'index': i + 1},
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (_images.length < widget.imageLimit)
                    OutlinedButton.icon(
                      onPressed: _picking || widget.controller.busy
                          ? null
                          : _pick,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        _picking
                            ? hhText(context, '读取图片中')
                            : hhText(context, '添加图片'),
                      ),
                    ),
                  if (_selectionError != null)
                    Text(
                      hhText(context, _selectionError!),
                      semanticsLabel: hhText(context, _selectionError!),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed:
                        widget.enabled && !_picking && !widget.controller.busy
                        ? _submit
                        : null,
                    child: Text(
                      widget.controller.busy
                          ? hhText(context, '正在确认提交结果')
                          : hhText(context, widget.submitLabel),
                    ),
                  ),
                ],
                if (widget.controller.error != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(hhText(context, widget.controller.error!)),
                    ),
                  ),
              ],
            ),
    ),
  );
}

class PendingGovernancePanel extends StatelessWidget {
  const PendingGovernancePanel({
    super.key,
    required this.controller,
    this.onResolved,
  });
  final GovernanceController controller;
  final void Function(bool submitted)? onResolved;
  Future<void> _resolve({bool retry = false, bool discard = false}) async {
    final ok = await controller.reconcilePending(
      retry: retry,
      discard: discard,
    );
    if (ok && controller.pending == null) {
      onResolved?.call(controller.lastPendingSubmitted == true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = controller.pending;
    if (p == null) return const SizedBox.shrink();
    final body = p['body'] as Map;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          hhText(context, '正在确认原提交结果'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(hhText(context, '退出页面不会撤销平台已收到的任务。核对后才会使用原材料和原任务重试。')),
        if (body['description'] is String &&
            (body['description'] as String).isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(body['description'] as String),
          ),
        Text(
          hhText(
            context,
            '已保留 {count} 张图片',
            args: {'count': (body['images'] as List?)?.length ?? 0},
          ),
        ),
        TextButton(
          onPressed: controller.busy ? null : _resolve,
          child: Text(hhText(context, '核对原提交')),
        ),
        FilledButton(
          onPressed: controller.busy ? null : () => _resolve(retry: true),
          child: Text(hhText(context, '核对后重试原任务')),
        ),
        TextButton(
          onPressed: controller.busy ? null : () => _resolve(discard: true),
          child: Text(hhText(context, '确认未提交后放弃材料')),
        ),
      ],
    );
  }
}
