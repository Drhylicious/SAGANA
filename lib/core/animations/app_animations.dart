import 'package:flutter/animation.dart';

/// Shared animation timing for consistent motion across SAGANA.
class AppAnimations {
  AppAnimations._();

  static const Duration fast = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration tabSwitch = Duration(milliseconds: 220);
  static const Duration staggerStep = Duration(milliseconds: 50);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeIn = Curves.easeInCubic;
  static const Curve spring = Curves.easeOutBack;
}
