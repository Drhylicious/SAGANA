import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'app_animations.dart';

/// Custom page routes for consistent navigation motion.
class AppPageTransitions {
  AppPageTransitions._();

  /// Forward drill-down: slide from right + fade.
  static CustomTransitionPage<T> slideForward<T>({
    required LocalKey key,
    required Widget child,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: AppAnimations.standard,
      reverseTransitionDuration: AppAnimations.fast,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppAnimations.easeOut,
          reverseCurve: AppAnimations.easeIn,
        );
        final offset = Tween<Offset>(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(curved);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(position: offset, child: child),
        );
      },
    );
  }

  /// Auth / splash handoff: gentle fade.
  static CustomTransitionPage<T> fadeThrough<T>({
    required LocalKey key,
    required Widget child,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: AppAnimations.slow,
      reverseTransitionDuration: AppAnimations.standard,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: AppAnimations.easeOut,
          ),
          child: child,
        );
      },
    );
  }

  /// Success / modal-style: scale + fade.
  static CustomTransitionPage<T> scaleIn<T>({
    required LocalKey key,
    required Widget child,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: AppAnimations.standard,
      reverseTransitionDuration: AppAnimations.fast,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppAnimations.spring,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

/// Navigator 1.x route for legacy Navigator.push calls.
class AppSlideRoute<T> extends PageRouteBuilder<T> {
  AppSlideRoute({required Widget page})
      : super(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: AppAnimations.standard,
          reverseTransitionDuration: AppAnimations.fast,
          transitionsBuilder: (_, animation, __, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: AppAnimations.easeOut,
              reverseCurve: AppAnimations.easeIn,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.06, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}
