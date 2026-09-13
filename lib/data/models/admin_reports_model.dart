import '../models/expense_model.dart' show CategoryBreakdown;

enum ReportPeriod { thisMonth, thisQuarter, thisYear, allTime }

extension ReportPeriodExt on ReportPeriod {
  String get label {
    switch (this) {
      case ReportPeriod.thisMonth:
        return 'This Month';
      case ReportPeriod.thisQuarter:
        return 'This Quarter';
      case ReportPeriod.thisYear:
        return 'This Year';
      case ReportPeriod.allTime:
        return 'All Time';
    }
  }

  DateTime? get startDate {
    final now = DateTime.now();
    switch (this) {
      case ReportPeriod.thisMonth:
        return DateTime(now.year, now.month, 1);
      case ReportPeriod.thisQuarter:
        final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        return DateTime(now.year, quarterStartMonth, 1);
      case ReportPeriod.thisYear:
        return DateTime(now.year, 1, 1);
      case ReportPeriod.allTime:
        return null;
    }
  }

  ({DateTime? startDate, DateTime? endDate}) range() {
    final now = DateTime.now();
    switch (this) {
      case ReportPeriod.thisMonth:
        return (
          startDate: DateTime(now.year, now.month, 1),
          endDate: DateTime(now.year, now.month + 1, 0),
        );
      case ReportPeriod.thisQuarter:
        final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        final start = DateTime(now.year, quarterStartMonth, 1);
        final end = DateTime(now.year, quarterStartMonth + 3, 0);
        return (startDate: start, endDate: end);
      case ReportPeriod.thisYear:
        return (
          startDate: DateTime(now.year, 1, 1),
          endDate: DateTime(now.year + 1, 1, 0),
        );
      case ReportPeriod.allTime:
        return (startDate: null, endDate: null);
    }
  }

  ({DateTime? startDate, DateTime? endDate})? previousRange() {
    final now = DateTime.now();
    switch (this) {
      case ReportPeriod.thisMonth:
        return (
          startDate: DateTime(now.year, now.month - 1, 1),
          endDate: DateTime(now.year, now.month, 0),
        );
      case ReportPeriod.thisQuarter:
        final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        final start = DateTime(now.year, quarterStartMonth - 3, 1);
        final end = DateTime(now.year, quarterStartMonth, 0);
        return (startDate: start, endDate: end);
      case ReportPeriod.thisYear:
        return (
          startDate: DateTime(now.year - 1, 1, 1),
          endDate: DateTime(now.year, 1, 0),
        );
      case ReportPeriod.allTime:
        return null;
    }
  }
}

/// Display order for period chips across every Report screen — deliberately
/// independent of ReportPeriod's declared enum order (thisMonth, thisQuarter,
/// thisYear, allTime), since other logic (sorting, previousRange()) relies
/// on that declaration order and shouldn't be touched. Matches the order
/// Operational Reports' landing page already uses; every individual report
/// screen should build its period chips from this list, not from
/// ReportPeriod.values directly, so the chip order stays consistent
/// everywhere without being duplicated per screen.
const reportPeriodChipOrder = [
  ReportPeriod.allTime,
  ReportPeriod.thisMonth,
  ReportPeriod.thisQuarter,
  ReportPeriod.thisYear,
];

class PerformanceSummary {
  final double totalHarvestKg;
  final double coopSalesAmount;
  final double marketplaceRevenue;
  final double activeLoanOutstanding;
  final double totalExpenses;
  final double memberParticipationPercent;

  const PerformanceSummary({
    required this.totalHarvestKg,
    required this.coopSalesAmount,
    required this.marketplaceRevenue,
    required this.activeLoanOutstanding,
    required this.totalExpenses,
    required this.memberParticipationPercent,
  });

  factory PerformanceSummary.empty() => const PerformanceSummary(
    totalHarvestKg: 0,
    coopSalesAmount: 0,
    marketplaceRevenue: 0,
    activeLoanOutstanding: 0,
    totalExpenses: 0,
    memberParticipationPercent: 0,
  );
}

class QuickInsights {
  final String? topCropName;
  final double topCropAmount;
  final String? topFarmerName;
  final double topFarmerAmount;
  final String? topExpenseCategory;
  final double? topExpenseAmount;

  const QuickInsights({
    this.topCropName,
    this.topCropAmount = 0,
    this.topFarmerName,
    this.topFarmerAmount = 0,
    this.topExpenseCategory,
    this.topExpenseAmount,
  });

  static QuickInsights empty() => const QuickInsights();
}

// ─── Sales Report ───────────────────────────────────────────────────────────

/// One row in Sales Report's transaction table. Reports on
/// member_sales_transactions (direct Palay/Peanut sales to SP3) per the
/// agreed data-source pivot — not the marketplace `orders` table.
class SalesTransactionRow {
  final String id;
  final String farmerName;
  final String memberId;
  final String cropType; // 'palay' | 'peanut'
  final String cropName;
  final double quantityKg;
  final double amount;
  final DateTime saleDate;
  final String? referenceNo;

  const SalesTransactionRow({
    required this.id,
    required this.farmerName,
    required this.memberId,
    required this.cropType,
    required this.cropName,
    required this.quantityKg,
    required this.amount,
    required this.saleDate,
    this.referenceNo,
  });
}

class SalesReportData {
  final double totalRevenue;
  final double marketplaceRevenue;
  final double totalQuantityKg;
  final int transactionCount;
  final double palayAmount;
  final double peanutAmount;
  final List<double> monthlyTrend;
  final List<SalesTransactionRow> transactions;

  const SalesReportData({
    required this.totalRevenue,
    required this.marketplaceRevenue,
    required this.totalQuantityKg,
    required this.transactionCount,
    required this.palayAmount,
    required this.peanutAmount,
    required this.monthlyTrend,
    required this.transactions,
  });

  double get averageSaleAmount =>
      transactionCount > 0 ? totalRevenue / transactionCount : 0;

  SalesReportData copyWithMarketplaceRevenue(double value) => SalesReportData(
    totalRevenue: totalRevenue,
    marketplaceRevenue: value,
    totalQuantityKg: totalQuantityKg,
    transactionCount: transactionCount,
    palayAmount: palayAmount,
    peanutAmount: peanutAmount,
    monthlyTrend: monthlyTrend,
    transactions: transactions,
  );

  factory SalesReportData.empty() => const SalesReportData(
    totalRevenue: 0,
    marketplaceRevenue: 0,
    totalQuantityKg: 0,
    transactionCount: 0,
    palayAmount: 0,
    peanutAmount: 0,
    monthlyTrend: [],
    transactions: [],
  );
}

class MemberContributionRow {
  final String farmerId;
  final String farmerName;
  final String memberId;
  final double palayQtyKg;
  final double palayAmount;
  final double peanutQtyKg;
  final double peanutAmount;
  final double totalAmount;
  final double sharePercent;

  const MemberContributionRow({
    required this.farmerId,
    required this.farmerName,
    required this.memberId,
    required this.palayQtyKg,
    required this.palayAmount,
    required this.peanutQtyKg,
    required this.peanutAmount,
    required this.totalAmount,
    required this.sharePercent,
  });

  bool get hasContributed => totalAmount > 0;
}

class MemberContributionReportData {
  final int year;
  final double totalCoopSales;
  final int memberCount;
  final int contributingMemberCount;
  final List<MemberContributionRow> rows;

  const MemberContributionReportData({
    required this.year,
    required this.totalCoopSales,
    required this.memberCount,
    required this.contributingMemberCount,
    required this.rows,
  });

  double get participationPercent =>
      memberCount > 0 ? (contributingMemberCount / memberCount * 100) : 0;

  factory MemberContributionReportData.empty(int year) =>
      MemberContributionReportData(
        year: year,
        totalCoopSales: 0,
        memberCount: 0,
        contributingMemberCount: 0,
        rows: const [],
      );
}

// ─── Inventory Report ───────────────────────────────────────────────────────

/// One row in Inventory Report's batch table. Available/Reserved/Sold are
/// real stored columns on inventory_batches — no cross-referencing against
/// orders needed, unlike what I originally assumed before seeing the schema.
class InventoryReportRow {
  final String batchId;
  final String farmerId;
  final String farmerName;
  final String memberId;
  final String cropName;
  final String batchNumber;
  final double quantityKg;
  final double availableKg;
  final double reservedKg;
  final double soldKg;
  final String
  status; // available | reserved | sold_out | withdrawn | low_stock
  final DateTime createdAt;

  const InventoryReportRow({
    required this.batchId,
    required this.farmerId,
    required this.farmerName,
    required this.memberId,
    required this.cropName,
    required this.batchNumber,
    required this.quantityKg,
    required this.availableKg,
    required this.reservedKg,
    required this.soldKg,
    required this.status,
    required this.createdAt,
  });

  bool get isLowStock => status == 'low_stock';
}

class CropStockBreakdown {
  final String cropName;
  final double totalKg;
  const CropStockBreakdown({required this.cropName, required this.totalKg});
}

/// Inventory is a point-in-time snapshot, not a time-series — no
/// ReportPeriod filter here, same reasoning already applied to the hub's
/// "active loan outstanding" figure.
class InventoryReportData {
  final double totalAvailableKg;
  final double totalReservedKg;
  final double totalSoldKg;
  final int lowStockCount;
  final List<CropStockBreakdown> cropBreakdown;
  final List<InventoryReportRow> batches;

  const InventoryReportData({
    required this.totalAvailableKg,
    required this.totalReservedKg,
    required this.totalSoldKg,
    required this.lowStockCount,
    required this.cropBreakdown,
    required this.batches,
  });

  factory InventoryReportData.empty() => const InventoryReportData(
    totalAvailableKg: 0,
    totalReservedKg: 0,
    totalSoldKg: 0,
    lowStockCount: 0,
    cropBreakdown: [],
    batches: [],
  );
}

// ─── Harvest Report ─────────────────────────────────────────────────────────

/// One row in Harvest Report's table. submitted_to_cooperative and
/// is_synced are both real stored columns on harvest_records — no
/// inference needed, same as the Available/Reserved/Sold columns on
/// Inventory Report.
class HarvestReportRow {
  final String id;
  final String farmerId;
  final String farmerName;
  final String memberId;
  final String cropName;
  final double quantityKg;
  final DateTime harvestDate;
  final bool submittedToCooperative;
  final bool isSynced;
  final String batchNumber; // links 1:1 to InventoryReportRow.batchNumber

  const HarvestReportRow({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    required this.memberId,
    required this.cropName,
    required this.quantityKg,
    required this.harvestDate,
    required this.submittedToCooperative,
    required this.isSynced,
    required this.batchNumber,
  });
}

class HarvestReportData {
  final double totalYieldKg;
  final int harvestCount;
  final int unsyncedCount;
  final List<double> monthlyTrend;
  final List<CropStockBreakdown> cropBreakdown;
  final List<HarvestReportRow> harvests;

  const HarvestReportData({
    required this.totalYieldKg,
    required this.harvestCount,
    required this.unsyncedCount,
    required this.monthlyTrend,
    required this.cropBreakdown,
    required this.harvests,
  });

  factory HarvestReportData.empty() => const HarvestReportData(
        totalYieldKg: 0,
        harvestCount: 0,
        unsyncedCount: 0,
        monthlyTrend: [],
        cropBreakdown: [],
        harvests: [],
      );
}

// ─── Expense Report ─────────────────────────────────────────────────────────

/// Subsidized expenses are stored with amount = 0 by design (see
/// ExpenseRepository.addExpense() on the farmer side — a subsidized item's
/// cost to the farmer is zero since the cooperative/government covered it).
/// There is therefore no meaningful peso total for "subsidized spending" —
/// only a count. Don't add a subsidizedAmount field; it would always be
/// zero and would misleadingly imply a real tracked total.
class ExpenseReportRow {
  final String farmerId;
  final String farmerName;
  final String memberId;
  final String category;
  final String description;
  final double amount;
  final bool isSubsidy;
  final DateTime expenseDate;

  const ExpenseReportRow({
    required this.farmerId,
    required this.farmerName,
    required this.memberId,
    required this.category,
    required this.description,
    required this.amount,
    required this.isSubsidy,
    required this.expenseDate,
  });
}

class CoopStockReportRow {
  final String id;
  final String itemName;
  final String category;
  final String unit;
  final double quantityOnHand;
  final double reorderLevel;
  final bool isLowStock;
  final double? unitCost;
  final DateTime? lastRestockedAt;

  const CoopStockReportRow({
    required this.id,
    required this.itemName,
    required this.category,
    required this.unit,
    required this.quantityOnHand,
    required this.reorderLevel,
    required this.isLowStock,
    this.unitCost,
    this.lastRestockedAt,
  });
}

class CoopStockReportData {
  final int totalItems;
  final int lowStockCount;
  final Map<String, int> categoryCounts;
  final List<CoopStockReportRow> items;

  const CoopStockReportData({
    required this.totalItems,
    required this.lowStockCount,
    required this.categoryCounts,
    required this.items,
  });

  static const empty = CoopStockReportData(
    totalItems: 0,
    lowStockCount: 0,
    categoryCounts: {},
    items: [],
  );
}

class ExpenseReportData {
  final double totalFarmerFundedAmount;
  final int subsidizedCount;
  final int farmerFundedCount;
  final List<CategoryBreakdown> categoryBreakdown;
  final List<double> monthlyTrend;
  final List<ExpenseReportRow> expenses;

  const ExpenseReportData({
    required this.totalFarmerFundedAmount,
    required this.subsidizedCount,
    required this.farmerFundedCount,
    required this.categoryBreakdown,
    required this.monthlyTrend,
    required this.expenses,
  });

  int get totalEntryCount => subsidizedCount + farmerFundedCount;

  factory ExpenseReportData.empty() => const ExpenseReportData(
        totalFarmerFundedAmount: 0,
        subsidizedCount: 0,
        farmerFundedCount: 0,
        categoryBreakdown: [],
        monthlyTrend: [],
        expenses: [],
      );
}