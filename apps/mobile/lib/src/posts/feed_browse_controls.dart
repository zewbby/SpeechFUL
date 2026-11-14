import 'package:flutter/material.dart';

import '../design_system/motion.dart';
import '../design_system/telegram_theme.dart';

/// Feed navigation keeps the current channel title and picker as separate
/// controls, while making the active label's indicator fit the text.
class FeedBrowseControls extends StatelessWidget {
  const FeedBrowseControls({
    super.key,
    required this.channelLabel,
    required this.latestLabel,
    required this.filterLabel,
    required this.channelTooltip,
    required this.latestSelected,
    required this.blockedCount,
    required this.onRecommended,
    required this.onLatest,
    required this.onChannelPicker,
    required this.onFilter,
    this.pickerOpen = false,
  });

  final String channelLabel, latestLabel, filterLabel, channelTooltip;
  final bool latestSelected, pickerOpen;
  final int blockedCount;
  final VoidCallback? onRecommended, onLatest, onChannelPicker, onFilter;

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    TextStyle label(bool selected) =>
        Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: 16,
          height: 1.3,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? p.ink : p.secondary,
        );
    Widget tab({
      required String text,
      required bool selected,
      required Key key,
      Key? indicatorKey,
      VoidCallback? onPressed,
    }) => Semantics(
      selected: selected,
      child: DecoratedBox(
        key: indicatorKey,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? p.accent : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: TextButton(
          key: key,
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: label(selected),
          ),
        ),
      ),
    );
    final channel = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: tab(
            text: channelLabel,
            selected: !latestSelected,
            key: const ValueKey('feed-recommended'),
            onPressed: onRecommended,
          ),
        ),
        IconButton(
          key: const ValueKey('feed-channel-picker'),
          tooltip: channelTooltip,
          onPressed: onChannelPicker,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 48),
          padding: EdgeInsets.zero,
          icon: AnimatedRotation(
            turns: pickerOpen ? .25 : 0,
            duration: HhMotion.duration(context, HhMotion.quick),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: p.secondary,
            ),
          ),
        ),
      ],
    );
    final latest = tab(
      text: latestLabel,
      selected: latestSelected,
      key: const ValueKey('feed-latest'),
      indicatorKey: const ValueKey('feed-latest-indicator'),
      onPressed: onLatest,
    );
    final filter = TextButton(
      key: const ValueKey('feed-block-filter'),
      onPressed: onFilter,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.tune_rounded,
            size: 19,
            color: blockedCount > 0 ? p.accent : p.secondary,
          ),
          const SizedBox(width: 4),
          Text(filterLabel, style: label(false)),
          if (blockedCount > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: p.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$blockedCount',
                style: TextStyle(
                  color: p.onAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final large =
            MediaQuery.textScalerOf(context).scale(16) > 22 ||
            constraints.maxWidth < 300;
        if (large) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: channel,
                      ),
                    ),
                    filter,
                  ],
                ),
                latest,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: channel),
                    const SizedBox(width: 8),
                    latest,
                  ],
                ),
              ),
              filter,
            ],
          ),
        );
      },
    );
  }
}
