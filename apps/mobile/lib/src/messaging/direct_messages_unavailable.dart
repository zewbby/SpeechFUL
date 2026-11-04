import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';

/// No DM backend is deployed. The production destination contains no sample
/// contacts, messages, unread counts or controls pretending to send messages.
class DirectMessagesUnavailableScreen extends StatelessWidget {
  const DirectMessagesUnavailableScreen({super.key, this.navigation});
  final Widget? navigation;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(hhText(context, '私信'))),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(hhText(context, '私信暂未开放')),
      ),
    ),
    bottomNavigationBar: navigation,
  );
}
