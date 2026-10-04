class DashboardSummaryModel {
  // This calendar month only — see DashboardRepository.fetchSummary() for
  // exactly which harvest_records rows are included. Named "monthly" (not
  // "total") because it is not the farmer's overall/season yield — that
  // figure lives on the Harvest tab instead.
  final double monthlyYieldKg;
  final double previousMonthYieldKg;
  // Same harvest_records source as monthlyYieldKg, but for the whole
  // current calendar year — the same figure the Harvest tab used to show
  // under its own "Total Yield" stat before that was removed in favor of
  // this one, single source of truth.
  final double annualYieldKg;
  // This calendar month's earnings across all four income channels
  // (Marketplace, Offer to Cooperative, Informal Sales, Market Linking).
  final double monthlyEarnings;
  // Same four channels, but for the whole current calendar year —
  // shown alongside monthlyEarnings so a farmer can see both figures.
  final double annualEarnings;
  // Admin-configurable (farmer_dashboard_settings.monthly_earnings_goal),
  // never hardcoded — see DashboardRepository.fetchSummary().
  final double earningsGoal;
  final int unsyncedCount;
  // Null when this device has never completed a sync for this account yet
  // (e.g. a brand-new install that hasn't gone online once).
  final DateTime? lastSyncedAt;

  const DashboardSummaryModel({
    required this.monthlyYieldKg,
    required this.previousMonthYieldKg,
    required this.annualYieldKg,
    required this.monthlyEarnings,
    required this.annualEarnings,
    required this.earningsGoal,
    required this.unsyncedCount,
    this.lastSyncedAt,
  });

  double get yieldChangePercent {
    if (previousMonthYieldKg == 0) return 0;
    return ((monthlyYieldKg - previousMonthYieldKg) / previousMonthYieldKg) *
        100;
  }

  bool get yieldTrendUp => yieldChangePercent >= 0;

  double get earningsProgressPercent {
    if (earningsGoal == 0) return 0;
    return (monthlyEarnings / earningsGoal).clamp(0.0, 1.0);
  }

  int get earningsGoalPercent => (earningsProgressPercent * 100).round();

  static const DashboardSummaryModel empty = DashboardSummaryModel(
    monthlyYieldKg: 0,
    previousMonthYieldKg: 0,
    annualYieldKg: 0,
    monthlyEarnings: 0,
    annualEarnings: 0,
    earningsGoal: 5000,
    unsyncedCount: 0,
  );
}

// ─── Activity Item Types ──────────────────────────────────────────────────────

enum ActivityType {
  harvest,
  listing,
  orderPlaced,
  cropRequest,
  cropAdded,
  cropPhotoUpdated,
  cooperativeOffer,
  marketLinkingEnrollment,
  gingerBatchSubmission,
  informalSale,
  profile,
  addressUpdated,
  expenseAdded,
  programEnrollment,
  programPurchase,
  capitalReinvestment,
  syncCompleted,
}

class ActivityItem {
  final String id;
  final ActivityType type;
  final String title;
  final String subtitle;
  final String? valueLabel;
  final String? statusLabel;
  final bool isAlert;
  final DateTime timestamp;

  const ActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.valueLabel,
    this.statusLabel,
    this.isAlert = false,
    required this.timestamp,
  });
}

// ─── Activity Filter ──────────────────────────────────────────────────────────

// Rebuilt for the Farmer-side Recent Activity rework: filters group by
// which Farmer-side tab/module the action was performed through, not by
// what kind of event it was. "Home" now has one real source — a manual
// Sync Now that actually synced something — after previously having none.
enum ActivityFilter { all, home, harvest, listing, profile }

extension ActivityFilterExt on ActivityFilter {
  String get label {
    switch (this) {
      case ActivityFilter.all:
        return 'All';
      case ActivityFilter.home:
        return 'Home';
      case ActivityFilter.harvest:
        return 'Harvest';
      case ActivityFilter.listing:
        return 'Listing';
      case ActivityFilter.profile:
        return 'Profile';
    }
  }

  bool matches(ActivityItem item) {
    switch (this) {
      case ActivityFilter.all:
        return true;
      case ActivityFilter.home:
        return item.type == ActivityType.syncCompleted;
      case ActivityFilter.harvest:
        return item.type == ActivityType.harvest ||
            item.type == ActivityType.cropRequest ||
            item.type == ActivityType.cropAdded ||
            item.type == ActivityType.cropPhotoUpdated ||
            item.type == ActivityType.cooperativeOffer ||
            item.type == ActivityType.marketLinkingEnrollment ||
            item.type == ActivityType.gingerBatchSubmission ||
            item.type == ActivityType.informalSale;
      case ActivityFilter.listing:
        return item.type == ActivityType.listing ||
            item.type == ActivityType.orderPlaced;
      case ActivityFilter.profile:
        return item.type == ActivityType.profile ||
            item.type == ActivityType.addressUpdated ||
            item.type == ActivityType.expenseAdded ||
            item.type == ActivityType.programEnrollment ||
            item.type == ActivityType.programPurchase ||
            item.type == ActivityType.capitalReinvestment;
    }
  }
}
