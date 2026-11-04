import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';

import 'auth_flows.dart';
import 'auth_session_controller.dart';

const accountClosureConfirmationPhrase = '确定注销账号';

/// The phrase and password dialog are UI confirmations. The existing AuthFlows
/// protocol still owns password proof, durable request identity and outcomes.
class AccountClosureScreen extends StatefulWidget {
  const AccountClosureScreen({
    super.key,
    required this.sessions,
    required this.flows,
    this.onAuthenticationRequired,
  });
  final AuthSessionController sessions;
  final AuthFlows flows;
  final VoidCallback? onAuthenticationRequired;
  @override
  State<AccountClosureScreen> createState() => _AccountClosureScreenState();
}

class _AccountClosureScreenState extends State<AccountClosureScreen>
    with WidgetsBindingObserver {
  final _phrase = TextEditingController(), _password = TextEditingController();
  late final _account = widget.sessions.currentSession?.accountId;
  late final _authority = widget.sessions.authorityVersion;
  DialogRoute<String>? _dialog;
  bool _confirming = false, _started = false, _stale = false;
  bool get _busy => widget.sessions.busy || widget.flows.busy || _confirming;
  bool get _original =>
      widget.sessions.isAuthenticated &&
      widget.sessions.currentSession?.accountId == _account &&
      widget.sessions.authorityVersion == _authority;
  bool get _hasResult => const {
    AuthFlowStatus.closureUnknown,
    AuthFlowStatus.closurePending,
    AuthFlowStatus.closureCancelled,
    AuthFlowStatus.closureFinalizing,
    AuthFlowStatus.closureClosedReleasePending,
    AuthFlowStatus.closureReleased,
  }.contains(widget.flows.status);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.sessions.addListener(_changed);
    widget.flows.addListener(_changed);
  }

  void _dismissDialog() {
    final dialog = _dialog;
    if (dialog?.isActive == true) dialog!.navigator?.removeRoute(dialog);
    _dialog = null;
    _password.clear();
  }

  void _changed() {
    if (!mounted) return;
    if ((!_started && !_original && !_hasResult) ||
        (widget.sessions.isAuthenticated && !_original)) {
      _stale = true;
      _phrase.clear();
      _dismissDialog();
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _dismissDialog();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.sessions.removeListener(_changed);
    widget.flows.removeListener(_changed);
    final dialog = _dialog;
    _dialog = null;
    _phrase.dispose();
    if (dialog == null) {
      _password.dispose();
    } else {
      // A page can be removed while its dialog is still a separate route.
      // Navigator may be locked during disposal; retire that route after the
      // frame, keeping its field controller alive until the overlay unmounts.
      final navigator = dialog.navigator;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (dialog.isActive && navigator?.mounted == true) {
          navigator!.removeRoute(dialog);
        }
      });
      unawaited(dialog.completed.then((_) => _password.dispose()));
    }
    super.dispose();
  }

  Future<void> _confirm({bool retry = false}) async {
    if (_busy ||
        _stale ||
        (!retry &&
            (!_original || _phrase.text != accountClosureConfirmationPhrase))) {
      return;
    }
    setState(() => _confirming = true);
    _password.clear();
    final form = GlobalKey<FormState>();
    late final DialogRoute<String> route;
    route = DialogRoute<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const ValueKey('closure-password-dialog'),
        title: Text(hhText(context, '确认注销')),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(hhText(context, '请输入当前密码以确认申请。申请受理后退出登录，七天缓冲期内主动登录可撤销。')),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('closure-confirm-password'),
                  controller: _password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: hhText(context, '当前密码'),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? hhText(context, '请输入当前密码')
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('closure-cancel'),
            onPressed: () {
              if (_dialog == route && route.isCurrent) Navigator.pop(context);
            },
            child: Text(hhText(context, '取消')),
          ),
          FilledButton(
            key: const ValueKey('closure-final-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () {
              if (_dialog == route &&
                  route.isCurrent &&
                  !_stale &&
                  (retry || _original) &&
                  form.currentState?.validate() == true) {
                Navigator.pop(context, _password.text);
              }
            },
            child: Text(hhText(context, '确认')),
          ),
        ],
      ),
    );
    _dialog = route;
    final password = await Navigator.of(context).push<String>(route);
    _dialog = null;
    if (!mounted) return;
    _password.clear();
    setState(() => _confirming = false);
    if (password == null || _stale || (!retry && !_original)) return;
    _started = true;
    _phrase.clear();
    if (retry) {
      await widget.flows.retryClosure(password);
    } else {
      await widget.flows.requestClosure(password);
    }
  }

  Widget _notice(String text, {Map<String, Object?> args = const {}}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Semantics(
          liveRegion: true,
          child: Text(hhText(context, text, args: args)),
        ),
      );
  Widget _action(String text, VoidCallback? action) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: OutlinedButton(
      onPressed: _busy ? null : action,
      child: Text(hhText(context, text)),
    ),
  );
  List<Widget> _result() {
    final flow = widget.flows;
    final message = switch (flow.status) {
      AuthFlowStatus.closurePending => '申请已受理，账号进入七天注销缓冲期。期间主动登录会撤销申请。',
      AuthFlowStatus.closureCancelled => '注销申请已取消，可以主动登录继续使用。',
      AuthFlowStatus.closureFinalizing => '正在正式关闭账号，已不能撤销或恢复旧账号。',
      AuthFlowStatus.closureClosedReleasePending => '账号已关闭，正在等待资格释放确认。',
      AuthFlowStatus.closureReleased => '账号已关闭，资格已释放。',
      _ => '注销申请结果未知。请核对原申请；未查到结果不代表申请失败。',
    };
    return [
      _notice(message),
      if (flow.closureStatus?.dueAt case final DateTime due)
        _notice(
          '预计完成时间：{date}',
          args: {
            'date': MaterialLocalizations.of(context)
                .formatMediumDate(due.toLocal()),
          },
        ),
      _action('核对注销状态', () => unawaited(flow.reconcileClosure())),
      if (flow.status == AuthFlowStatus.closureUnknown)
        _action('重试原注销申请', () => unawaited(_confirm(retry: true))),
      if (widget.onAuthenticationRequired != null &&
          (flow.status == AuthFlowStatus.closurePending ||
              flow.status == AuthFlowStatus.closureCancelled))
        _action(
          flow.status == AuthFlowStatus.closurePending ? '登录并撤销注销' : '前往登录',
          widget.onAuthenticationRequired,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(hhText(context, '账号注销'))),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            key: const ValueKey('account-closure-page'),
            padding: const EdgeInsets.all(24),
            children: [
              if (widget.flows.busy) const LinearProgressIndicator(),
              if (_stale || (!_original && !_hasResult)) ...[
                _notice('登录状态已变化，请重新进入账号注销。'),
                if (widget.onAuthenticationRequired != null)
                  _action('前往登录', widget.onAuthenticationRequired),
              ] else ...[
                if (widget.flows.errorMessage != null)
                  _notice(widget.flows.errorMessage!),
                if (_hasResult)
                  ..._result()
                else ...[
                  Text(
                    hhText(context, '注销流程'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _notice('1. 确认申请后，账号退出登录并进入七天缓冲期。'),
                  _notice('2. 缓冲期内主动登录可撤销注销；查看申请状态不会恢复登录。'),
                  _notice('3. 缓冲期结束后账号永久关闭。已公开内容保留，尚未公开的发送任务取消。'),
                  const SizedBox(height: 24),
                  Text(
                    hhText(
                      context,
                      '请输入「{phrase}」以继续。',
                      args: {'phrase': accountClosureConfirmationPhrase},
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('closure-confirmation-phrase'),
                    controller: _phrase,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: hhText(context, '确认短语'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const ValueKey('closure-start-confirmation'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    onPressed:
                        !_busy &&
                            _phrase.text == accountClosureConfirmationPhrase
                        ? () => unawaited(_confirm())
                        : null,
                    child: Text(hhText(context, '确认注销')),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
