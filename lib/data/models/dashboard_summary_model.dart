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

enum ActivityType { harvest, order, listing, loan }

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

enum ActivityFilter { all, harvests, orders, finance }

extension ActivityFilterExt on ActivityFilter {
  String get label {
    switch (this) {
      case ActivityFilter.all: return 'All';
      case ActivityFilter.harvests: return 'Harvests';
      case ActivityFilter.orders: return 'Orders';
      case ActivityFilter.finance: return 'Finance';
    }
  }

  bool matches(ActivityItem item) {
    switch (this) {
      case ActivityFilter.all: return true;
      case ActivityFilter.harvests: return item.type == ActivityType.harvest;
      case ActivityFilter.orders: return item.type == ActivityType.order || item.type == ActivityType.listing;
      case ActivityFilter.finance: return item.type == ActivityType.loan;
    }
  }
}
