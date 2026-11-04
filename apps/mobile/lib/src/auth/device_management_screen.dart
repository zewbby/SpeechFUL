import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';

import 'auth_session_controller.dart';
import 'device_management_controller.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({
    super.key,
    required this.controller,
    required this.sessions,
    this.onAuthenticationRequired,
  });
  final DeviceManagementController controller;
  final AuthSessionController sessions;
  final VoidCallback? onAuthenticationRequired;
  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.sessions.addListener(_changed);
    scheduleMicrotask(widget.controller.load);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.sessions.removeListener(_changed);
    super.dispose();
  }

  String _time(BuildContext context, DateTime time) {
    final local = time.toLocal(), labels = MaterialLocalizations.of(context);
    return '${labels.formatMediumDate(local)} ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, device = widget.controller.device;
    final busy = c.busy || widget.sessions.busy;
    return Scaffold(
      appBar: AppBar(title: Text(hhText(context, '设备管理'))),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (busy) const LinearProgressIndicator(),
                if (c.errorMessage != null)
                  Text(hhText(context, c.errorMessage!)),
                if (c.status == DeviceManagementStatus.ready &&
                    device != null) ...[
                  ListTile(
                    key: const ValueKey('current-device-session'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.phone_android_outlined),
                    title: Text(hhText(context, '当前设备与会话')),
                    subtitle: Text(
                      hhText(
                        context,
                        '登录：{signedIn}\n会话截止：{expiry}',
                        args: {
                          'signedIn': _time(context, device.currentSignedInAt),
                          'expiry': _time(context, device.sessionExpiresAt),
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: busy ? null : () => unawaited(c.load()),
                    child: Text(hhText(context, '刷新会话')),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => unawaited(widget.sessions.logout()),
                    child: Text(hhText(context, '退出本机')),
                  ),
                ] else if (!busy) ...[
                  Text(hhText(context, '请核对登录状态后查看当前设备与会话。')),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () async {
                      await widget.sessions.retry();
                      if (mounted) await c.load();
                    },
                    child: Text(hhText(context, '重新核对')),
                  ),
                  if (!widget.sessions.isAuthenticated &&
                      widget.onAuthenticationRequired != null)
                    TextButton(
                      onPressed: widget.onAuthenticationRequired,
                      child: Text(hhText(context, '前往登录')),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
