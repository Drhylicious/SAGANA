import 'package:flutter/material.dart';
import '../../core/animations/app_animations.dart';

/// Animated alert dialog wrapper.
class AppDialog {
  AppDialog._();

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: AppAnimations.standard,
      pageBuilder: (_, __, ___) => Material(
        type: MaterialType.transparency,
        child: child,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
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

/// Animated bottom sheet wrapper.
///
/// Uses showGeneralDialog (not showModalBottomSheet) so the transition
/// curve can be fully customized — the default modal bottom sheet only
/// offers a flat linear slide with no public curve API. This gives a
/// fade-in scrim plus a spring-curved slide-up (slight overshoot then
/// settle), matching AppDialog's polish above instead of feeling like
/// two different UI kits stitched together.
///
/// Trade-off: native drag-to-dismiss is not available this way (unlike
/// showModalBottomSheet). Content should provide its own affordance —
/// existing sheets already include a drag-handle bar and rely on
/// tap-outside-to-dismiss (barrierDismissible), which is preserved here.
class AppBottomSheet {
  AppBottomSheet._();

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget Function(BuildContext context) builder,
    bool isDismissible = true,
    @Deprecated(
      'No longer meaningful — this implementation always sizes to content, '
      'same as isScrollControlled: true used to. Kept only so existing call '
      'sites passing this don\'t fail to compile.',
    )
    bool isScrollControlled = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: AppAnimations.standard,
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
              top: false,
              child: builder(context),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slideCurve = CurvedAnimation(
          parent: animation,
          curve: AppAnimations.spring,
          reverseCurve: AppAnimations.easeIn,
        );
        final fadeCurve = CurvedAnimation(
          parent: animation,
          curve: AppAnimations.easeOut,
          reverseCurve: AppAnimations.easeIn,
        );
        return FadeTransition(
          opacity: fadeCurve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(slideCurve),
            child: child,
          ),
        );
      },
    );
  }
}