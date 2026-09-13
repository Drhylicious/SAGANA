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
  // Market Type tokens — the one shared color system for
  // Cooperative / Public Market, reused across the Home
  // carousel, Market Rate Details, and View Market screens. Never
  // define these locally in a screen file again.
  final Color marketCooperative;
  final Color marketOpenMarket;
  // DA-AMAD Market — reintroduced exclusively for Ginger (Admin Marketplace
  // review, Market Linking phase). Distinct from both Cooperative and
  // Public Market so Ginger's classification is never visually confused
  // with either.
  final Color marketDaAmad;

  const SaganaColors({
    required this.scaffoldBackground,
    required this.cardBackground,
    required this.glassBackground,
    required this.glassBorder,
    required this.navBarBackground,
    required this.gold,
    required this.harvestGold,
    required this.marketCooperative,
    required this.marketOpenMarket,
    required this.marketDaAmad,
  });

  static const light = SaganaColors(
    scaffoldBackground: AppConstants.offWhite,
    cardBackground: AppConstants.white,
    glassBackground: Color(0xB3FFFFFF),
    glassBorder: Color(0x33FFFFFF),
    navBarBackground: Color(0xB3FFFFFF),
    gold: AppConstants.gold,
    harvestGold: AppConstants.harvestGold,
    marketCooperative: AppConstants.primaryGreen,
    marketOpenMarket: Color(0xFF757575),
    marketDaAmad: AppConstants.programPurple,
  );

  static const dark = SaganaColors(
    scaffoldBackground: Color(0xFF0D1A10),
    cardBackground: Color(0xFF1E2E22),
    glassBackground: Color(0x991E2E22),
    glassBorder: Color(0x33FFFFFF),
    navBarBackground: Color(0xCC1A281E),
    gold: AppConstants.gold,
    harvestGold: AppConstants.harvestGold,
    marketCooperative: AppConstants.lightGreen,
    marketOpenMarket: Color(0xFFB0BEC5),
    marketDaAmad: AppConstants.programPurple,
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
    Color? marketCooperative,
    Color? marketOpenMarket,
    Color? marketDaAmad,
  }) {
    return SaganaColors(
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      glassBackground: glassBackground ?? this.glassBackground,
      glassBorder: glassBorder ?? this.glassBorder,
      navBarBackground: navBarBackground ?? this.navBarBackground,
      gold: gold ?? this.gold,
      harvestGold: harvestGold ?? this.harvestGold,
      marketCooperative: marketCooperative ?? this.marketCooperative,
      marketOpenMarket: marketOpenMarket ?? this.marketOpenMarket,
      marketDaAmad: marketDaAmad ?? this.marketDaAmad,
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
      marketCooperative:
          Color.lerp(marketCooperative, other.marketCooperative, t)!,
      marketOpenMarket: Color.lerp(marketOpenMarket, other.marketOpenMarket, t)!,
      marketDaAmad: Color.lerp(marketDaAmad, other.marketDaAmad, t)!,
    );
  }
}

extension SaganaColorsContext on BuildContext {
  SaganaColors get saganaColors =>
      Theme.of(this).extension<SaganaColors>() ?? SaganaColors.light;
}

/// Shared label + lookup for the two market-type classifications
/// (crop_master.crop_type / price_records.price_type). One place both
/// the color and the display text live, so Home, Market Rate Details,
/// and View Market can never drift apart on either.
class MarketTypeDisplay {
  MarketTypeDisplay._();

  static Color color(BuildContext context, String priceType) {
    final colors = context.saganaColors;
    switch (priceType) {
      case 'sp3_cooperative':
        return colors.marketCooperative;
      case 'da_amad_market':
        return colors.marketDaAmad;
      default:
        return colors.marketOpenMarket;
    }
  }

  static String label(String priceType) {
    switch (priceType) {
      case 'sp3_cooperative':
        return 'Cooperative Market';
      case 'da_amad_market':
        return 'DA-AMAD Market';
      default:
        return 'Public Market';
    }
  }
}

/// Shared color lookup for marketplace_listings.status, mirroring
/// MarketTypeDisplay's pattern above — one place the color lives, so
/// Farmer's My Listings and Admin's Listing Review can never disagree on
/// a status's color again. Previously they did: changes_required was
/// error-red-toned on the Farmer badge, amber/warning on Admin's review
/// screen. Resolved here in favor of amber/warning — changes_required is
/// an actionable-but-not-failed state, unlike rejected.
///
/// Labels are intentionally NOT unified here — Farmer's badge uses
/// descriptive text ("LIVE ON MARKET") while Admin's uses compact text
/// ("Live") for a denser review list. That's a deliberate difference
/// between two UI densities, not accidental duplication.
class ListingStatusDisplay {
  ListingStatusDisplay._();

  static Color color(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case 'pending_review':
        return AppConstants.warningAmber;
      case 'approved':
        return AppConstants.successGreen;
      case 'changes_required':
        return AppConstants.warningAmber;
      case 'sold':
        return cs.onSurfaceVariant;
      case 'rejected':
        return cs.error;
      case 'withdrawn':
        return cs.outline;
      default:
        return cs.outline;
    }
  }
}
