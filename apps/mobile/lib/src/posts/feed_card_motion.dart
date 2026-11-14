import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../design_system/motion.dart';
import '../design_system/telegram_theme.dart';

/// Shares scroll activity with cards, including mouse-wheel scrolls.
class FeedCardEntranceScope extends StatefulWidget {
  const FeedCardEntranceScope({super.key, required this.child});
  final Widget child;

  @override
  State<FeedCardEntranceScope> createState() => _FeedCardEntranceScopeState();
}

class _FeedEntranceRegistry {
  bool scrollingThisFrame = false;
  int generation = 0;
}

class _FeedCardEntranceScopeState extends State<FeedCardEntranceScope> {
  final _registry = _FeedEntranceRegistry();

  bool _recordScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        notification is! ScrollUpdateNotification ||
        notification.scrollDelta == null ||
        notification.scrollDelta == 0) {
      return false;
    }
    _registry.scrollingThisFrame = true;
    final generation = ++_registry.generation;
    // Wheel scrolling can become idle before the next frame. Retain the scroll
    // direction until all visibility checks scheduled for that frame have run.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (mounted && _registry.generation == generation) {
          _registry.scrollingThisFrame = false;
        }
      });
    });
    return false;
  }

  @override
  Widget build(BuildContext context) => _FeedCardSeen(
    registry: _registry,
    child: NotificationListener<ScrollNotification>(
      onNotification: _recordScroll,
      child: widget.child,
    ),
  );
}

class _FeedCardSeen extends InheritedWidget {
  const _FeedCardSeen({required this.registry, required super.child});

  final _FeedEntranceRegistry registry;

  static _FeedEntranceRegistry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FeedCardSeen>()?.registry;

  @override
  bool updateShouldNotify(_FeedCardSeen oldWidget) =>
      registry != oldWidget.registry;
}

/// Flat feed surface that animates when a card scrolls into view.
class HhFeedPostCard extends StatefulWidget {
  const HhFeedPostCard({super.key, required this.postId, required this.child});

  final String postId;
  final Widget child;

  @override
  State<HhFeedPostCard> createState() => _HhFeedPostCardState();
}

class _HhFeedPostCardState extends State<HhFeedPostCard>
    with SingleTickerProviderStateMixin {
  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );
  ScrollPosition? _position;
  _FeedEntranceRegistry? _registry;
  bool _reducedMotion = false;
  bool _checkScheduled = false;
  bool _inViewport = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_scheduleVisibilityCheck);
      _position = position;
      _position?.addListener(_scheduleVisibilityCheck);
    }
    _registry = _FeedCardSeen.maybeOf(context);
    _reducedMotion = HhMotion.reduced(context);
    if (_reducedMotion || _registry == null) {
      _entrance.value = 1;
    }
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(HhFeedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) {
      _inViewport = false;
      _entrance.value = 1;
      _scheduleVisibilityCheck();
    }
  }

  void _scheduleVisibilityCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      _checkVisibility();
    });
  }

  void _checkVisibility() {
    final position = _position;
    final registry = _registry;
    if (position == null ||
        registry == null ||
        !position.hasContentDimensions) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final top = viewport.getOffsetToReveal(box, 0).offset;
    final viewportTop = position.pixels;
    final viewportBottom = viewportTop + position.viewportDimension;
    final visibleExtent =
        (top + box.size.height < viewportBottom
            ? top + box.size.height
            : viewportBottom) -
        (top > viewportTop ? top : viewportTop);
    if (visibleExtent <= 0) {
      _inViewport = false;
      return;
    }
    // Wait until enough of the card is on screen for the movement to be seen.
    final threshold = box.size.height < 24 ? box.size.height : 24.0;
    if (_inViewport || visibleExtent < threshold) return;
    _inViewport = true;
    if (!_reducedMotion &&
        (position.userScrollDirection != ScrollDirection.idle ||
            registry.scrollingThisFrame)) {
      _entrance.forward(from: 0);
    } else {
      _entrance.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = HhTelegramPalette.of(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _entrance,
        child: Material(
          color: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: p.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.child,
        ),
        builder: (context, child) {
          final progress = Curves.easeOutCubic.transform(_entrance.value);
          final bubble = Curves.easeOutBack.transform(_entrance.value);
          return Transform.translate(
            offset: Offset(0, 8 * (1 - progress)),
            child: Transform.scale(
              key: ValueKey('feed-card-scale:${widget.postId}'),
              scale: .94 + .06 * bubble,
              child: Opacity(opacity: .82 + .18 * progress, child: child),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _position?.removeListener(_scheduleVisibilityCheck);
    _entrance.dispose();
    super.dispose();
  }
}
