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
  final int activeInventoryItems;
  final int lowStockAlertCount;
  final int pendingListings;
  final double totalRevenueThisMonth;
  final int overdueLoans;
  final DateTime? loanDataAsOf;

  const AdminKpiSummary({
    required this.activeMembers,
    required this.totalMembersTarget,
    required this.pendingMembers,
    required this.totalStockKg,
    required this.activeInventoryItems,
    required this.lowStockAlertCount,
    required this.pendingListings,
    required this.totalRevenueThisMonth,
    required this.overdueLoans,
    this.loanDataAsOf,
  });

  static const empty = AdminKpiSummary(
    activeMembers: 0,
    totalMembersTarget: 52,
    pendingMembers: 0,
    totalStockKg: 0,
    activeInventoryItems: 0,
    lowStockAlertCount: 0,
    pendingListings: 0,
    totalRevenueThisMonth: 0,
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
  final String route; // where tapping this item navigates
  final bool useGo; // true = context.go() (tab switch), false = context.push()
  final String? extra; // optional extra for context.push()

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
// Sourced from cooperative_inventory (Inventory Management's own stock) —
// see fetchInventoryAlerts() in admin_dashboard_repository.dart. Reworked
// per Phase 2 to replace the earlier inventory_batches (farmer harvest
// stock)-sourced version, which described a different table than the one
// "Inventory Management" and its "View Inventory" link actually manage.

enum InventoryAlertLevel { low, depleted }

class InventoryAlertItem {
  final String id;
  final String itemName;
  final String category;
  final double quantityOnHand;
  final String unit;
  final double reorderLevel;
  final InventoryAlertLevel alertLevel;

  const InventoryAlertItem({
    required this.id,
    required this.itemName,
    required this.category,
    required this.quantityOnHand,
    required this.unit,
    required this.reorderLevel,
    required this.alertLevel,
  });

  bool get isDepleted => alertLevel == InventoryAlertLevel.depleted;
}

// ─── Calendar Event ───────────────────────────────────────────────────────────

enum CalendarEventType { bodMeeting, loanDue, harvest, announcement, program }

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

  int get daysUntilMeeting => nextMeetingDate.difference(DateTime.now()).inDays;
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
  cropRequest,
  // Sourced from admin_activity_log rather than inferred from a domain
  // table's created_at — see AdminActivityRepository and
  // AdminDashboardRepository.fetchRecentActivity. Covers every module an
  // admin action was explicitly logged from (module identified by
  // sourceModule, e.g. 'inventory', 'programs', 'loans', 'market_linking',
  // 'offers', 'broadcast', 'profile') plus 'crops' admin CRUD alongside
  // the legacy cropRequest items. Adding a new logged module never
  // requires a new enum case — only a call to AdminActivityRepository.log.
  logged,
}

// Which message template this item renders as — distinct from
// AdminActivityType because 'listing' covers two different templates
// (submitted vs. approved) that read very differently once localized.
enum AdminActivityDescKind {
  harvest,
  listingApproved,
  listingSubmitted,
  orderPlaced,
  priceUpdated,
  newMember,
  cropRequested,
}

// description/timeLabel used to be pre-composed English strings built in
// AdminDashboardRepository (a data-layer class with no AppLocalizations
// access). Localizing them meant moving the raw values (name/crop/qty/
// amount, plus the bare timestamp) onto the model instead, so the actual
// sentence can be assembled with AppLocalizations in the presentation
// layer — see adminActivityDescription()/adminActivityTimeLabel() in
// admin_activity_screen.dart.
class AdminActivityItem {
  final String id;
  final AdminActivityType type;
  // Null only for AdminActivityType.logged items, which carry their own
  // ready-made [plainDescription] instead — see adminActivityDescription()
  // in admin_activity_screen.dart.
  final AdminActivityDescKind? descKind;
  final String? name;
  final String? cropName;
  final String? quantityKg;
  final String? amount;
  final String? highlightedName;
  final DateTime timestamp;
  final bool isPrimary;
  final String? sourceModule;
  final String? referenceId;
  // AdminActivityType.logged only — an already-composed description from
  // admin_activity_log, and the name of the admin who performed it (null
  // if that admin's profile couldn't be resolved).
  final String? plainDescription;
  final String? adminName;

  const AdminActivityItem({
    required this.id,
    required this.type,
    this.descKind,
    this.name,
    this.cropName,
    this.quantityKg,
    this.amount,
    this.highlightedName,
    required this.timestamp,
    required this.isPrimary,
    this.sourceModule,
    this.referenceId,
    this.plainDescription,
    this.adminName,
  });
}

// ─── Cooperative Performance Summary ─────────────────────────────────────────

class CoopPerformanceSummary {
  final int totalHarvests;
  final double farmerAvailableStockKg;
  final int activeListings;
  final int completedSales;
  final int activeMembersThisSeason;
  final int totalMembers;
  final double? estimatedStockValue;

  const CoopPerformanceSummary({
    required this.totalHarvests,
    required this.farmerAvailableStockKg,
    required this.activeListings,
    required this.completedSales,
    required this.activeMembersThisSeason,
    required this.totalMembers,
    this.estimatedStockValue,
  });

  double get totalStockKg => farmerAvailableStockKg;

  double get participationPercent =>
      totalMembers > 0 ? activeMembersThisSeason / totalMembers : 0;

  static const empty = CoopPerformanceSummary(
    totalHarvests: 0,
    farmerAvailableStockKg: 0,
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
  final bool
  useGo; // true = tab switch via context.go(), false = push above shell

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
