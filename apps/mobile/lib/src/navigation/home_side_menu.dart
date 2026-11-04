import '../localization/app_localizations.dart';

import 'package:flutter/material.dart';

/// Moves the whole home surface, including navigation, to reveal settings.
/// Child horizontal recognizers keep priority over this ancestor recognizer.
class HomeSideMenu extends StatefulWidget {
  const HomeSideMenu({
    super.key,
    required this.enabled,
    required this.menuBuilder,
    required this.child,
  });
  final bool enabled;
  final WidgetBuilder menuBuilder;
  final Widget child;
  @override
  State<HomeSideMenu> createState() => HomeSideMenuState();
}

class HomeSideMenuState extends State<HomeSideMenu>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  double _width = 0;
  bool _dragging = false;

  Future<void> open() async {
    if (!widget.enabled) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await _animate(1);
  }

  Future<void> close() => _animate(0);

  Future<void> _animate(double target) async {
    if (!mounted || (target > 0 && !widget.enabled)) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = target;
      return;
    }
    try {
      await _motion.animateTo(target, curve: Curves.easeOutCubic).orCancel;
    } on TickerCanceled {
      /* A newer gesture or authority window owns the frame. */
    }
  }

  void _beginDrag(DragStartDetails details) {
    if (!widget.enabled) return;
    _dragging = true;
  }

  void _drag(DragUpdateDetails details) {
    if (!widget.enabled || _width == 0) return;
    _motion.value += details.delta.dx / _width;
  }

  void _cancelDrag() {
    // A child tap also rejects the ancestor drag. Do not animate for that tap.
    if (!_dragging || !widget.enabled) return;
    _dragging = false;
    _animate(_motion.value >= .45 ? 1 : 0);
  }

  void _settle(DragEndDetails details) {
    _dragging = false;
    if (!widget.enabled) return;
    final velocity = details.primaryVelocity ?? 0;
    _animate(
      velocity.abs() > 350
          ? (velocity > 0 ? 1 : 0)
          : (_motion.value >= .45 ? 1 : 0),
    );
  }

  @override
  void didUpdateWidget(HomeSideMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _dragging = false;
      _motion.value = 0;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HomeSideMenuScope(
    state: this,
    child: LayoutBuilder(
      builder: (context, box) {
        _width = (box.maxWidth - 32).clamp(0, double.infinity);
        return GestureDetector(
          key: const ValueKey('home-menu-swipe-surface'),
          behavior: HitTestBehavior.translucent,
          excludeFromSemantics: true,
          onHorizontalDragStart: widget.enabled ? _beginDrag : null,
          onHorizontalDragUpdate: widget.enabled ? _drag : null,
          onHorizontalDragEnd: widget.enabled ? _settle : null,
          onHorizontalDragCancel: widget.enabled ? _cancelDrag : null,
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, _) {
              final progress = _motion.value;
              final visible = progress > 0;
              return PopScope(
                canPop: !visible,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop && visible) close();
                },
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (visible)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: _width,
                          child: Transform.translate(
                            offset: Offset(-_width * .12 * (1 - progress), 0),
                            child: Semantics(
                              scopesRoute: true,
                              namesRoute: true,
                              explicitChildNodes: true,
                              label: hhText(context, '设置'),
                              child: FocusScope(
                                autofocus: true,
                                child: Builder(builder: widget.menuBuilder),
                              ),
                            ),
                          ),
                        ),
                      Transform.translate(
                        key: const ValueKey('home-menu-home-surface'),
                        offset: Offset(_width * progress, 0),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ExcludeFocus(
                              excluding: visible,
                              child: ExcludeSemantics(
                                excluding: visible,
                                child: IgnorePointer(
                                  ignoring: visible,
                                  child: widget.child,
                                ),
                              ),
                            ),
                            if (visible)
                              GestureDetector(
                                key: const ValueKey('home-menu-dismiss'),
                                behavior: HitTestBehavior.opaque,
                                onTap: close,
                                child: ColoredBox(
                                  color: Colors.black.withValues(
                                    alpha: .08 * progress,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

class HomeSideMenuScope extends InheritedWidget {
  const HomeSideMenuScope({
    super.key,
    required this.state,
    required super.child,
  });
  final HomeSideMenuState state;
  static HomeSideMenuState? maybeOf(BuildContext context) {
    final state = context
        .dependOnInheritedWidgetOfExactType<HomeSideMenuScope>()
        ?.state;
    return state?.widget.enabled == true ? state : null;
  }

  @override
  bool updateShouldNotify(HomeSideMenuScope oldWidget) =>
      state != oldWidget.state;
}
