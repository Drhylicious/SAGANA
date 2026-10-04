import 'package:flutter/material.dart';

class AppConstants {
  AppConstants._();

  // ─── App Info ───────────────────────────────────────────────────────────────
  static const String appName = 'SAGANA';
  static const String appTagline = 'Empowering the farmers of Payanas';

  static const String appSubtitle = 'Streamlined Agricultural Gateway';
  static const String cooperativeName = 'SP3 Agriculture Cooperative';
  static const String cooperativeLocation =
      'Barangay Payanas, Torrijos, Marinduque';

  // ─── Assets ─────────────────────────────────────────────────────────────────
  static const String logoPath = 'assets/images/sagana_logo.png';

  // ─── Brand Colors ────────────────────────────────────────────────────────────
  static const Color primaryGreen = Color(0xFF00450D);
  static const Color midGreen = Color(0xFF2E7D32);
  static const Color lightGreen = Color(0xFF43A047);
  static const Color limeGreen = Color(0xFFDCEDC8);
  static const Color primaryContainer = Color(0xFF1B5E20);
  static const Color onPrimaryContainer = Color(0xFF90D689);
  static const Color gold = Color(0xFFF9A825);
  static const Color amber = Color(0xFFFFB300);
  static const Color harvestGold = Color(0xFFF9A825);
  static const Color secondaryContainer = Color(0xFFFCAB28);
  static const Color white = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFF9FBF7);
  static const Color surface = Color(0xFFF3FAFF);
  static const Color charcoal = Color(0xFF263238);
  static const Color onSurface = Color(0xFF071E27);
  static const Color onSurfaceVariant = Color(0xFF41493E);
  static const Color outline = Color(0xFF717A6D);
  static const Color successGreen = Color(0xFF43A047);
  static const Color warningAmber = Color(0xFFFFB300);
  static const Color errorRed = Color(0xFFD32F2F);
  static const Color infoBlueBg = Color(0xFFDBF1FE);
  static const Color infoBlueFg = Color(0xFF455A64);
  static const Color buyerBlue = Color(0xFF1E88E5);
  static const Color onTertiaryContainer = Color(0xFF7CDB7A);
  static const Color tertiaryContainer = Color(0xFF006017);
  static const Color programPurple = Color(0xFF8E24AA);
  // Phase 11 — Withdrawn and Sold previously both rendered as muted greys
  // (cs.outline / cs.onSurfaceVariant), indistinguishable from each other
  // and from a plain "inactive" state next to the amber/green/red used by
  // every other listing status. These are still deliberately muted (both
  // statuses are less urgent than pending/changes-required), just no
  // longer visually identical.
  static const Color mutedSlate = Color(0xFF546E7A); // withdrawn
  static const Color mutedBrown = Color(0xFF8D6E63); // sold

  // ─── Gradients ───────────────────────────────────────────────────────────────
  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryGreen, primaryContainer],
  );

  static const LinearGradient primaryButtonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [midGreen, primaryGreen],
  );

  // ─── Spacing ─────────────────────────────────────────────────────────────────
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingGutter = 16.0;
  static const double spacingSectionV = 24.0;
  static const double spacingSafeH = 20.0;

  // ─── Border Radius ───────────────────────────────────────────────────────────
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusFull = 9999.0;

  // ─── Card Depth (border + shadow) ─────────────────────────────────────────────
  // A subtle hairline border ALONGSIDE a soft shadow, applied together —
  // the border keeps a card's edges legible at high screen brightness
  // (where a shadow alone becomes hard to perceive), while the shadow still
  // supplies depth at normal brightness. Used consistently across the
  // Buyer marketplace flow (Browse, Listing Details, Cart, Checkout, My
  // Addresses) so every card reads the same way regardless of viewing
  // conditions.
  static Border get cardBorder =>
      Border.all(color: outline.withValues(alpha: 0.10));
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  // ─── Animation Durations ─────────────────────────────────────────────────────
  static const Duration splashLogoDelay = Duration(milliseconds: 200);
  static const Duration splashLogoDuration = Duration(milliseconds: 800);
  static const Duration splashTextDelay = Duration(milliseconds: 600);
  static const Duration splashTextDuration = Duration(milliseconds: 600);
  static const Duration splashBarDuration = Duration(milliseconds: 1200);
  static const Duration splashNavDelay = Duration(milliseconds: 2200);

  // Address label chip options (My Addresses). Adding or renaming a label
  // means editing this one list, not the Add/Edit Address screen's widget tree.
  static const List<String> buyerAddressLabels = [
    'Home',
    'Work',
    'Farm',
    'Other',
  ];

  static const List<String> loanItemUnits = [
    'bag',
    'kg',
    'sack',
    'piece',
    'liter',
  ];

  // ─── Harvest Storage Locations ──────────────────────────────────────────────
  // Where harvested inventory is physically stored. SP3 confirmed (face to
  // face) there is currently only one storage location cooperative-wide —
  // kept as its own list, so more locations can be added later.
  static const List<String> harvestStorageLocations = ['Purok 2 – Centro'];

  // ─── User Roles ──────────────────────────────────────────────────────────────
  static const String roleAdmin = 'admin';
  static const String roleFarmer = 'farmer';
  static const String roleBuyer = 'buyer';

  // ─── Hive Box Names ──────────────────────────────────────────────────────────
  static const String hiveBoxUser = 'user_box';
  static const String hiveBoxPrices = 'prices_box';
  static const String hiveBoxSettings = 'settings_box';
  static const String hiveBoxLoanQueue =
      'loan_queue_box'; // NEW — offline loan issuance queue
  static const String hiveBoxExportHistory =
      'export_history_box'; // NEW — Export Center's Recent Exports
  static const String hiveBoxHarvestQueue =
      'harvest_queue_box'; // NEW — offline harvest submissions
  static const String hiveBoxExpenseQueue =
      'expense_queue_box'; // NEW — offline expense submissions (Phase 2 / U2)
  static const String hiveBoxCart =
      'cart_box'; // NEW — local-only buyer cart, no Supabase table

  // ─── Hive Keys ───────────────────────────────────────────────────────────────
  static const String hiveKeyUserRole = 'user_role';
  static const String hiveKeyUserId = 'user_id';
  static const String hiveKeyUserEmail = 'user_email';
  static const String hiveKeyUserName = 'user_name';
  static const String hiveKeyIsLoggedIn = 'is_logged_in';
  static const String hiveKeyBackgroundSync = 'background_sync';
  static const String hiveKeyThemeMode = 'theme_mode';
  static const String hiveKeyLocale = 'locale';

  static const String themeLight = 'light';
  static const String themeDark = 'dark';

  static const String localeEnglish = 'en';
  static const String localeTagalog = 'tl';
}