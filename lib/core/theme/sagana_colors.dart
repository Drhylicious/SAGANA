import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../../data/services/market_types_service.dart';
import '../l10n/app_localizations.dart';

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

/// Shared label + colour for the market types (crop_master.crop_type /
/// price_records.price_type). SAGANA has two market types, Public and
/// Cooperative; DA-AMAD is a selling channel, not a market type.
///
/// Both come from the market_types table through [MarketTypes], never from a
/// comparison with a code: the name is the row's name (in the app's language),
/// and the colour follows whether Buyers can see that market (buyer_visible),
/// so a type added to the table later is shown correctly with no code change.
/// [l10n] is kept so existing call sites are unchanged; the language comes
/// from the app setting.
class MarketTypeDisplay {
  MarketTypeDisplay._();

  static Color color(BuildContext context, String? marketType) {
    final colors = context.saganaColors;
    return MarketTypes.instance.isBuyerVisible(marketType)
        ? colors.marketOpenMarket
        : colors.marketCooperative;
  }

  static String label(AppLocalizations l10n, String? marketType) =>
      MarketTypes.instance.label(marketType);
}

/// Shared color lookup for marketplace_listings.status, mirroring
/// MarketTypeDisplay's pattern above — one place the color lives, so
/// Farmer's My Listings and Admin's Listing Review can never disagree on
/// a status's color again.
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
      case 'sold':
        // Same grey as the Sold Out badge (listing_status_badge.dart).
        return cs.onSurfaceVariant;
      case 'rejected':
        return cs.error;
      case 'withdrawn':
        return AppConstants.mutedSlate;
      default:
        return cs.outline;
    }
  }
}
