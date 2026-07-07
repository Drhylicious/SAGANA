// ─── Admin KPI Summary ────────────────────────────────────────────────────────

class AdminKpiSummary {
  final int activeMembers;
  final int totalMembersTarget;
  final double totalStockKg;
  final int pendingOrders;
  final double totalRevenueThisMonth;

  const AdminKpiSummary({
    required this.activeMembers,
    required this.totalMembersTarget,
    required this.totalStockKg,
    required this.pendingOrders,
    required this.totalRevenueThisMonth,
  });

  static const empty = AdminKpiSummary(
    activeMembers: 0,
    totalMembersTarget: 52,
    totalStockKg: 0,
    pendingOrders: 0,
    totalRevenueThisMonth: 0,
  );
}

// ─── Urgent Action ────────────────────────────────────────────────────────────

enum UrgentActionType { pendingListings, overdueLoans, lowStock }

class UrgentAction {
  final UrgentActionType type;
  final String title;
  final String subtitle;
  final int count;
  final bool isCritical; // red left border

  const UrgentAction({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.isCritical,
  });

  bool get hasItems => count > 0;
}

// ─── BOD Meeting Info ─────────────────────────────────────────────────────────

class BodMeetingInfo {
  final DateTime nextMeetingDate;
  final int farmersWithOutstandingLoans;

  const BodMeetingInfo({
    required this.nextMeetingDate,
    required this.farmersWithOutstandingLoans,
  });

  /// Returns true if the meeting is within the next 7 days
  bool get isUpcoming =>
      nextMeetingDate.difference(DateTime.now()).inDays <= 7 &&
      nextMeetingDate.isAfter(DateTime.now());
}

// ─── Admin Activity Item ──────────────────────────────────────────────────────

enum AdminActivityType { harvest, listing, order, loan, price, member }

class AdminActivityItem {
  final String id;
  final AdminActivityType type;
  final String description;
  final String? highlightedName;
  final String timeLabel;
  final DateTime timestamp;
  final bool isPrimary; // green dot vs grey dot

  const AdminActivityItem({
    required this.id,
    required this.type,
    required this.description,
    this.highlightedName,
    required this.timeLabel,
    required this.timestamp,
    required this.isPrimary,
  });
}

// ─── Cooperative Performance Summary ─────────────────────────────────────────

class CoopPerformanceSummary {
  final int totalHarvests;
  final double totalStockKg;
  final int activeListings;
  final int completedSales;
  final int activeMembersThisSeason;
  final int totalMembers;

  const CoopPerformanceSummary({
    required this.totalHarvests,
    required this.totalStockKg,
    required this.activeListings,
    required this.completedSales,
    required this.activeMembersThisSeason,
    required this.totalMembers,
  });

  double get participationPercent =>
      totalMembers > 0 ? activeMembersThisSeason / totalMembers : 0;

  static const empty = CoopPerformanceSummary(
    totalHarvests: 0,
    totalStockKg: 0,
    activeListings: 0,
    completedSales: 0,
    activeMembersThisSeason: 0,
    totalMembers: 52,
  );
}
