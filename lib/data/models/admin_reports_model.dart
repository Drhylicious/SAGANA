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

/// One row in Sales Report's unified transaction table — as of Phase 10,
/// merged across all four real Selling Types (not just member_sales_
/// transactions): Offer to Cooperative, Marketplace, Informal Sale (F2F),
/// and DA-AMAD Market Linking. [sellingType] identifies which; [marketType]
/// is the crop's Cooperative/Public/DA-AMAD Market classification where one
/// meaningfully applies (Marketplace, DA-AMAD) and null where it doesn't
/// (Offer to Cooperative accepts any crop regardless of Market Type;
/// Informal Sale has no market-type concept at all).
class SalesTransactionRow {
  final String id;
  final String farmerName;
  final String memberId;
  final String cropType; // 'palay' | 'peanut' | other crop's lowercased name
  final String cropName;
  final double quantityKg;
  final double amount;
  final DateTime saleDate;
  final String? referenceNo;
  final String sellingType; // offer_to_cooperative | marketplace | informal_sale | da_amad_market_linking
  final String? marketType; // 'Cooperative Market' | 'Public Market' | 'DA-AMAD Market' | null

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
    required this.sellingType,
    this.marketType,
  });
}

/// One Selling Type's aggregate — Sales Report's four channel cards.
class SalesChannelTotal {
  final String sellingType;
  final String label;
  final double amount;
  final double quantityKg;
  final int transactionCount;

  const SalesChannelTotal({
    required this.sellingType,
    required this.label,
    required this.amount,
    required this.quantityKg,
    required this.transactionCount,
  });
}

class SalesReportData {
  final double totalRevenue;
  final double totalQuantityKg;
  final int transactionCount;
  final List<double> monthlyTrend;
  final List<SalesTransactionRow> transactions;
  final List<SalesChannelTotal> channelTotals;

  const SalesReportData({
    required this.totalRevenue,
    required this.totalQuantityKg,
    required this.transactionCount,
    required this.monthlyTrend,
    required this.transactions,
    this.channelTotals = const [],
  });

  double get averageSaleAmount =>
      transactionCount > 0 ? totalRevenue / transactionCount : 0;

  factory SalesReportData.empty() => const SalesReportData(
    totalRevenue: 0,
    totalQuantityKg: 0,
    transactionCount: 0,
    monthlyTrend: [],
    transactions: [],
    channelTotals: [],
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

  /// Any crop other than Palay/Peanut sold via Offer to Cooperative, as of
  /// Phase 9's any-crop widening (Phase 11 addition) — previously any such
  /// sale was invisible here, silently missing from the member's total.
  final double otherCropsQtyKg;
  final double otherCropsAmount;

  /// Option B — Product Sales Program purchases (farmer buys FROM the
  /// coop), kept structurally separate from totalAmount/sharePercent
  /// above (farmer sells TO the coop via Offer to Cooperative). Shown as
  /// its own line, never folded into the sales-based total.
  final double programPurchasesAmount;

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
    this.otherCropsQtyKg = 0,
    this.otherCropsAmount = 0,
    this.programPurchasesAmount = 0,
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
  final String? imageUrl;

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
    this.imageUrl,
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