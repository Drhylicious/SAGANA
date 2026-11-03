import '../../core/utils/quantity_utils.dart';

/// One calendar year of a farmer's harvest and sales, for the Profile tab's
/// Annual Yield and Annual Earnings. Each year is computed on its own from the
/// records dated inside that year, so a new year starts at zero while every
/// earlier year's records stay in the database untouched.
class AnnualFarmSummary {
  final int year;

  /// Harvest quantity per unit (`{kg: 12500.5, sack: 3}`). Units are never
  /// added together.
  final Map<String, double> yieldByUnit;

  /// Earnings per selling channel (completed sales only).
  final double marketplace;
  final double cooperative;
  final double informal;
  final double marketLinking;

  const AnnualFarmSummary({
    required this.year,
    required this.yieldByUnit,
    required this.marketplace,
    required this.cooperative,
    required this.informal,
    required this.marketLinking,
  });

  double get earnings => marketplace + cooperative + informal + marketLinking;

  bool get hasYield => yieldByUnit.values.any((v) => v > 0);

  /// `12,500.5 kg`, or `12,500.5 kg + 3 sack` when a farmer harvested in more
  /// than one unit. A year with no harvest shows `0 kg`.
  String get yieldText {
    final lines = [
      for (final e in yieldByUnit.entries)
        if (e.value > 0) (quantity: e.value, unit: e.key),
    ];
    if (lines.isEmpty) return '0 $kDefaultUnit';
    return lines
        .map((l) => '${formatQuantityGrouped(l.quantity)} ${l.unit}')
        .join(' + ');
  }

  static AnnualFarmSummary empty(int year) => AnnualFarmSummary(
    year: year,
    yieldByUnit: const {},
    marketplace: 0,
    cooperative: 0,
    informal: 0,
    marketLinking: 0,
  );
}

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

  /// Plain-map form, so a feed can be cached offline (OfflineCache keeps rows).
  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'title': title,
        'subtitle': subtitle,
        'valueLabel': valueLabel,
        'statusLabel': statusLabel,
        'isAlert': isAlert,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ActivityItem.fromMap(Map<String, dynamic> map) => ActivityItem(
        id: map['id'] as String,
        type: ActivityType.values.byName(map['type'] as String),
        title: map['title'] as String,
        subtitle: map['subtitle'] as String,
        valueLabel: map['valueLabel'] as String?,
        statusLabel: map['statusLabel'] as String?,
        isAlert: map['isAlert'] as bool? ?? false,
        timestamp: DateTime.parse(map['timestamp'] as String),
      );
}

// ─── Activity Filter ──────────────────────────────────────────────────────────

// Rebuilt for the Farmer-side Recent Activity rework: filters group by
// which Farmer-side tab/module the action was performed through, not by
// what kind of event it was. "Home" now has one real source — a manual
// Sync Now that actually synced something — after previously having none.
enum ActivityFilter { all, home, harvest, listing, profile }

extension ActivityFilterExt on ActivityFilter {
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
