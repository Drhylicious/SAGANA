import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// Brand-specific tokens beyond Material [ColorScheme].
@immutable
class SaganaColors extends ThemeExtension<SaganaColors> {
  final Color scaffoldBackground;
  final Color cardBackground;
  final Color glassBackground;
  final Color glassBorder;
  final Color navBarBackground;
  final Color gold;
  final Color harvestGold;

  const SaganaColors({
    required this.scaffoldBackground,
    required this.cardBackground,
    required this.glassBackground,
    required this.glassBorder,
    required this.navBarBackground,
    required this.gold,
    required this.harvestGold,
  });

  static const light = SaganaColors(
    scaffoldBackground: AppConstants.offWhite,
    cardBackground: AppConstants.white,
    glassBackground: Color(0xB3FFFFFF),
    glassBorder: Color(0x33FFFFFF),
    navBarBackground: Color(0xB3FFFFFF),
    gold: AppConstants.gold,
    harvestGold: AppConstants.harvestGold,
  );

  static const dark = SaganaColors(
    scaffoldBackground: Color(0xFF0D1A10),
    cardBackground: Color(0xFF1E2E22),
    glassBackground: Color(0x991E2E22),
    glassBorder: Color(0x33FFFFFF),
    navBarBackground: Color(0xCC1A281E),
    gold: AppConstants.gold,
    harvestGold: AppConstants.harvestGold,
  );

  @override
  SaganaColors copyWith({
    Color? scaffoldBackground,
    Color? cardBackground,
    Color? glassBackground,
    Color? glassBorder,
    Color? navBarBackground,
    Color? gold,
    Color? harvestGold,
  }) {
    return SaganaColors(
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      glassBackground: glassBackground ?? this.glassBackground,
      glassBorder: glassBorder ?? this.glassBorder,
      navBarBackground: navBarBackground ?? this.navBarBackground,
      gold: gold ?? this.gold,
      harvestGold: harvestGold ?? this.harvestGold,
    );
  }

  @override
  SaganaColors lerp(ThemeExtension<SaganaColors>? other, double t) {
    if (other is! SaganaColors) return this;
    return SaganaColors(
      scaffoldBackground:
          Color.lerp(scaffoldBackground, other.scaffoldBackground, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      glassBackground: Color.lerp(glassBackground, other.glassBackground, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      navBarBackground:
          Color.lerp(navBarBackground, other.navBarBackground, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      harvestGold: Color.lerp(harvestGold, other.harvestGold, t)!,
    );
  }
}

extension SaganaColorsContext on BuildContext {
  SaganaColors get saganaColors =>
      Theme.of(this).extension<SaganaColors>() ?? SaganaColors.light;
}
