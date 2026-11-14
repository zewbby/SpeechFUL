import 'package:flutter/material.dart';

import '../design_system/motion_routes.dart';
import '../design_system/telegram_theme.dart';

enum FeedCardMenuAction { share, repost, notInterested, report }

/// Feed card actions; business owners decide availability and handle selection.
class FeedCardMenu extends StatelessWidget {
  const FeedCardMenu({
    super.key,
    required this.postId,
    required this.tooltip,
    required this.shareLabel,
    required this.repostLabel,
    required this.notInterestedLabel,
    required this.reportLabel,
    required this.onSelected,
    this.shareEnabled = true,
    this.showRepost = true,
    this.repostEnabled = true,
    this.reposted = false,
    this.notInterestedEnabled = true,
    this.reportEnabled = true,
  });

  final String postId,
      tooltip,
      shareLabel,
      repostLabel,
      notInterestedLabel,
      reportLabel;
  final ValueChanged<FeedCardMenuAction> onSelected;
  final bool shareEnabled, showRepost, repostEnabled, reposted;
  final bool notInterestedEnabled, reportEnabled;

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    Widget row(
      IconData icon,
      String label, {
      bool enabled = true,
      bool selected = false,
    }) => Row(
      children: [
        Icon(
          icon,
          size: 21,
          color: !enabled
              ? p.line
              : selected
              ? p.accent
              : p.secondary,
        ),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: enabled ? p.ink : p.secondary)),
      ],
    );
    return PopupMenuButton<FeedCardMenuAction>(
      key: ValueKey('menu:$postId'),
      tooltip: tooltip,
      popUpAnimationStyle: HhMotionRoutes.popup(context),
      position: PopupMenuPosition.under,
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.line),
      ),
      icon: Icon(Icons.more_horiz_rounded, size: 22, color: p.secondary),
      itemBuilder: (context) => [
        PopupMenuItem(
          key: ValueKey('share-menu:$postId'),
          value: FeedCardMenuAction.share,
          enabled: shareEnabled,
          child: row(Icons.share_outlined, shareLabel, enabled: shareEnabled),
        ),
        if (showRepost)
          PopupMenuItem(
            key: ValueKey('repost-menu:$postId'),
            value: FeedCardMenuAction.repost,
            enabled: repostEnabled,
            child: row(
              Icons.repeat_rounded,
              repostLabel,
              enabled: repostEnabled,
              selected: reposted,
            ),
          ),
        PopupMenuItem(
          key: ValueKey('not-interested:$postId'),
          value: FeedCardMenuAction.notInterested,
          enabled: notInterestedEnabled,
          child: row(
            Icons.visibility_off_outlined,
            notInterestedLabel,
            enabled: notInterestedEnabled,
          ),
        ),
        PopupMenuItem(
          key: ValueKey('report:$postId'),
          value: FeedCardMenuAction.report,
          enabled: reportEnabled,
          child: row(Icons.flag_outlined, reportLabel, enabled: reportEnabled),
        ),
      ],
      onSelected: onSelected,
    );
  }
}

/// A compact in-place way to undo a hidden card during the current visit.
class FeedHiddenUndoRow extends StatelessWidget {
  const FeedHiddenUndoRow({
    super.key,
    required this.label,
    required this.onUndo,
  });
  final String label;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: Align(
      alignment: Alignment.centerRight,
      child: TextButton(onPressed: onUndo, child: Text(label)),
    ),
  );
}
