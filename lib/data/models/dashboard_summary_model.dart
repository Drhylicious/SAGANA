class DashboardSummaryModel {
  final double totalYieldKg;
  final double previousMonthYieldKg;
  final double totalEarnings;
  final double earningsGoal;
  final int unsyncedCount;

  const DashboardSummaryModel({
    required this.totalYieldKg,
    required this.previousMonthYieldKg,
    required this.totalEarnings,
    required this.earningsGoal,
    required this.unsyncedCount,
  });

  double get yieldChangePercent {
    if (previousMonthYieldKg == 0) return 0;
    return ((totalYieldKg - previousMonthYieldKg) / previousMonthYieldKg) * 100;
  }

  bool get yieldTrendUp => yieldChangePercent >= 0;

  double get earningsProgressPercent {
    if (earningsGoal == 0) return 0;
    return (totalEarnings / earningsGoal).clamp(0.0, 1.0);
  }

  int get earningsGoalPercent => (earningsProgressPercent * 100).round();

  static const DashboardSummaryModel empty = DashboardSummaryModel(
    totalYieldKg: 0,
    previousMonthYieldKg: 0,
    totalEarnings: 0,
    earningsGoal: 60000,
    unsyncedCount: 0,
  );
}

// ─── Activity Item Types ──────────────────────────────────────────────────────

enum ActivityType {
  harvest,
  order,
  listing,
  loan,
  cropRequest,
  cropAdded,
  informalSale,
  cooperativeSale,
  profile,
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

// Redesigned per Farmer-side Recent Activity review (Phase 7): the old
// "Orders" filter incorrectly matched both ActivityType.order AND
// ActivityType.listing — a chip labeled "Orders" was showing listing
// approvals mixed in with actual marketplace orders. Every type now has
// exactly one unambiguous home. "Sales" groups every channel that puts
// money in the farmer's pocket (Marketplace, Informal, Cooperative),
// mirroring how Home's Total Earnings already groups these three.
// "Listings" is the submission/review process itself, not the sale.
enum ActivityFilter { all, harvests, sales, listings, crops, finance, account }

extension ActivityFilterExt on ActivityFilter {
  String get label {
    switch (this) {
      case ActivityFilter.all: return 'All';
      case ActivityFilter.harvests: return 'Harvests';
      case ActivityFilter.sales: return 'Sales';
      case ActivityFilter.listings: return 'Listings';
      case ActivityFilter.crops: return 'Crops';
      case ActivityFilter.finance: return 'Finance';
      case ActivityFilter.account: return 'Account';
    }
  }

  bool matches(ActivityItem item) {
    switch (this) {
      case ActivityFilter.all:
        return true;
      case ActivityFilter.harvests:
        return item.type == ActivityType.harvest;
      case ActivityFilter.sales:
        return item.type == ActivityType.order ||
            item.type == ActivityType.informalSale ||
            item.type == ActivityType.cooperativeSale;
      case ActivityFilter.listings:
        return item.type == ActivityType.listing;
      case ActivityFilter.crops:
        return item.type == ActivityType.cropRequest ||
            item.type == ActivityType.cropAdded;
      case ActivityFilter.finance:
        return item.type == ActivityType.loan;
      case ActivityFilter.account:
        return item.type == ActivityType.profile;
    }
  }
}
