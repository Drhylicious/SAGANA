import 'package:flutter/material.dart';
import 'app_animations.dart';

/// Fades and slides children in with a staggered delay.
class StaggeredEntrance extends StatelessWidget {
  final int index;
  final Widget child;
  final Duration? delay;
  final Offset beginOffset;

  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
    this.delay,
    this.beginOffset = const Offset(0, 0.08),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppAnimations.standard +
          (delay ?? AppAnimations.staggerStep * index),
      curve: AppAnimations.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, beginOffset.dy * 40 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
