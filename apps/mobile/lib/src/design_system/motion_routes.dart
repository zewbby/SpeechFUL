import 'package:flutter/material.dart';

import 'motion.dart';

/// Motion for existing surfaces; page transitions keep their platform gestures.
abstract final class HhMotionRoutes {
  static AnimationStyle popup(BuildContext context) => AnimationStyle(
    duration: HhMotion.duration(context, HhMotion.quick),
    reverseDuration: HhMotion.duration(context, HhMotion.quick),
    curve: HhMotion.curve,
    reverseCurve: HhMotion.curve,
  );

  static AnimationStyle sheet(BuildContext context) => AnimationStyle(
    duration: HhMotion.duration(context, HhMotion.standard),
    reverseDuration: HhMotion.duration(context, HhMotion.quick),
    curve: HhMotion.curve,
    reverseCurve: HhMotion.curve,
  );

  static PageTransitionsTheme accessible(PageTransitionsTheme base) =>
      PageTransitionsTheme(
        builders: {
          for (final entry in base.builders.entries)
            entry.key: entry.value is _AccessiblePageTransitions
                ? entry.value
                : _AccessiblePageTransitions(entry.value),
        },
      );
}

class _AccessiblePageTransitions extends PageTransitionsBuilder {
  const _AccessiblePageTransitions(this.delegate);
  final PageTransitionsBuilder delegate;

  // Keep platform durations, predictive back, and interactive Cupertino pop.
  @override
  Duration get transitionDuration => delegate.transitionDuration;
  @override
  Duration get reverseTransitionDuration => delegate.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition {
    final transition = delegate.delegatedTransition;
    if (transition == null) return null;
    return (context, animation, secondaryAnimation, allowSnapshotting, child) =>
        HhMotion.reduced(context)
        ? child
        : transition(
            context,
            animation,
            secondaryAnimation,
            allowSnapshotting,
            child,
          );
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Keep the platform transition subtree (and its gesture recognizer), while
    // presenting the settled frame for autonomous reduced-motion transitions.
    final reduced = HhMotion.reduced(context) && !route.popGestureInProgress;
    final endpoint = animation.status == AnimationStatus.reverse ? 0.0 : 1.0;
    return delegate.buildTransitions(
      route,
      context,
      reduced ? AlwaysStoppedAnimation(endpoint) : animation,
      reduced ? const AlwaysStoppedAnimation(0.0) : secondaryAnimation,
      child,
    );
  }
}
