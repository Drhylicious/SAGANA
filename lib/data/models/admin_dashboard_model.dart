// ─────────────────────────────────────────────────────────────────────────────
// admin_dashboard_model.dart
// SAGANA — Admin Dashboard Models
// ─────────────────────────────────────────────────────────────────────────────

// ─── Admin KPI Summary ────────────────────────────────────────────────────────

class AdminKpiSummary {
  final int activeMembers;
  final int totalMembersTarget;
  final int pendingMembers;
  final double totalStockKg;
  final int pendingListings;
  final int pendingOrders;
  final double totalRevenueThisMonth;
  final int activeLoans;
  final int overdueLoans;

  const AdminKpiSummary({
    required this.activeMembers,
    required this.totalMembersTarget,
    required this.pendingMembers,
    required this.totalStockKg,
    required this.pendingListings,
    required this.pendingOrders,
    required this.totalRevenueThisMonth,
    required this.activeLoans,
    required this.overdueLoans,
  });

  static const empty = AdminKpiSummary(
    activeMembers: 0,
    totalMembersTarget: 52,
    pendingMembers: 0,
    totalStockKg: 0,
    pendingListings: 0,
    pendingOrders: 0,
    totalRevenueThisMonth: 0,
    activeLoans: 0,
    overdueLoans: 0,
  );
}

// ─── Dashboard Priority Item ──────────────────────────────────────────────────
// Powers the dynamic hero card. Each item represents one cooperative concern
// that needs the admin's attention today. Ordered by severity.

enum DashboardPriorityLevel { critical, warning, info }

class DashboardPriority {
  final String id;
  final DashboardPriorityLevel level;
  final String label;
  final String value;
  final String route;           // where tapping this item navigates
  final bool useGo;             // true = context.go() (tab switch), false = context.push()
  final String? extra;          // optional extra for context.push()

  const DashboardPriority({
    required this.id,
    required this.level,
    required this.label,
    required this.value,
    required this.route,
    this.useGo = false,
    this.extra,
  });
}

// ─── Inventory Alert Item ─────────────────────────────────────────────────────

enum InventoryAlertLevel { low, depleted }

class InventoryAlertItem {
  final String id;
  final String cropName;
  final String batchNumber;
  final double availableKg;
  final double? minimumThresholdKg;
  final InventoryAlertLevel alertLevel;
  final String? lastMovementSource;

  const InventoryAlertItem({
    required this.id,
    required this.cropName,
    required this.batchNumber,
    required this.availableKg,
    this.minimumThresholdKg,
    required this.alertLevel,
    this.lastMovementSource,
  });

  bool get isDepleted => alertLevel == InventoryAlertLevel.depleted;
}

// ─── Calendar Event ───────────────────────────────────────────────────────────

enum CalendarEventType {
  bodMeeting,
  loanDue,
  harvest,
  announcement,
  program,
}

class CalendarEvent {
  final String id;
  final CalendarEventType type;
  final DateTime date;
  final String title;
  final String? subtitle;
  final String? referenceId;
  final String? sourceModule;

  const CalendarEvent({
    required this.id,
    required this.type,
    required this.date,
    required this.title,
    this.subtitle,
    this.referenceId,
    this.sourceModule,
  });
}

// ─── BOD Meeting Info ─────────────────────────────────────────────────────────

class BodMeetingInfo {
  final DateTime nextMeetingDate;
  final int farmersWithOutstandingLoans;

  const BodMeetingInfo({
    required this.nextMeetingDate,
    required this.farmersWithOutstandingLoans,
  });

  bool get isUpcoming =>
      nextMeetingDate.difference(DateTime.now()).inDays <= 7 &&
      nextMeetingDate.isAfter(DateTime.now());

  int get daysUntilMeeting =>
      nextMeetingDate.difference(DateTime.now()).inDays;
}

// ─── Admin Activity Item ──────────────────────────────────────────────────────

enum AdminActivityType {
  harvest,
  listing,
  order,
  loan,
  price,
  member,
  inventory,
  program,
}

class AdminActivityItem {
  final String id;
  final AdminActivityType type;
  final String description;
  final String? highlightedName;
  final String timeLabel;
  final DateTime timestamp;
  final bool isPrimary;
  final String? sourceModule;
  final String? referenceId;

  const AdminActivityItem({
    required this.id,
    required this.type,
    required this.description,
    this.highlightedName,
    required this.timeLabel,
    required this.timestamp,
    required this.isPrimary,
    this.sourceModule,
    this.referenceId,
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
  final double? estimatedStockValue;

  const CoopPerformanceSummary({
    required this.totalHarvests,
    required this.totalStockKg,
    required this.activeListings,
    required this.completedSales,
    required this.activeMembersThisSeason,
    required this.totalMembers,
    this.estimatedStockValue,
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

// ─── Management Module Card ───────────────────────────────────────────────────

class ManagementModuleCard {
  final String id;
  final String title;
  final String subtitle;
  final String badgeLabel;
  final bool hasBadgeAlert;
  final String route;
  final bool useGo; // true = tab switch via context.go(), false = push above shell

  const ManagementModuleCard({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badgeLabel,
    required this.hasBadgeAlert,
    required this.route,
    this.useGo = false,
  });
}