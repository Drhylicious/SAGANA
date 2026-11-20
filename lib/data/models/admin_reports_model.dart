import '../models/expense_model.dart' show CategoryBreakdown;
import 'shelf_life_model.dart';

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
  // Revenue across all 4 real selling channels (Offer to Cooperative,
  // Marketplace, Informal Sale, DA-AMAD Market Linking) for the selected
  // period — same total Sales Report's own "Total Revenue" shows, reused
  // rather than recomputed. Replaces the old headline figure, which only
  // ever summed member_sales_transactions (Offer to Cooperative) despite
  // being labeled and shown as if it covered the whole sales ecosystem.
  final double totalSalesAmount;
  final double coopSalesAmount;
  final double marketplaceRevenue;
  final double activeLoanOutstanding;
  final double totalExpenses;
  final double memberParticipationPercent;

  /// What members paid for Cooperative Products (Product Sales programs) in the period. Kept
  /// apart from the selling channels and from the Marketplace figure.
  final double productSalesAmount;

  /// Completed orders in the period: Marketplace and Cooperative Product orders together.
  final int completedOrders;

  const PerformanceSummary({
    required this.totalHarvestKg,
    required this.totalSalesAmount,
    required this.coopSalesAmount,
    required this.marketplaceRevenue,
    required this.activeLoanOutstanding,
    required this.totalExpenses,
    required this.memberParticipationPercent,
    this.productSalesAmount = 0,
    this.completedOrders = 0,
  });

  factory PerformanceSummary.empty() => const PerformanceSummary(
    totalHarvestKg: 0,
    totalSalesAmount: 0,
    coopSalesAmount: 0,
    marketplaceRevenue: 0,
    activeLoanOutstanding: 0,
    totalExpenses: 0,
    memberParticipationPercent: 0,
  );
}

/// What members bought from the cooperative through Product Sales programs (completed orders
/// only), for a period. It is its own figure: it is not one of the four selling channels and it
/// is not Marketplace revenue. Delivery fees are not part of it.
class ProductSalesSummary {
  final double amount;
  final int orders;

  /// Different Farmers who bought.
  final int buyers;

  const ProductSalesSummary({
    required this.amount,
    required this.orders,
    required this.buyers,
  });

  double get averageOrder => orders > 0 ? amount / orders : 0;

  static const empty = ProductSalesSummary(amount: 0, orders: 0, buyers: 0);
}

/// One completed Cooperative Product order, as a line of the Cooperative Product Sales report.
class ProductSaleRow {
  final String id;
  final String orderNumber;
  final String farmerName;
  final String itemName;
  final String? programName;
  final double quantity;
  final String unit;
  final double amount;
  final DateTime saleDate;

  const ProductSaleRow({
    required this.id,
    required this.orderNumber,
    required this.farmerName,
    required this.itemName,
    this.programName,
    required this.quantity,
    required this.unit,
    required this.amount,
    required this.saleDate,
  });
}

/// The Cooperative Product Sales report of a period: the figures and every sale behind them.
class ProductSalesReportData {
  final ProductSalesSummary summary;
  final List<ProductSaleRow> rows;

  const ProductSalesReportData({required this.summary, required this.rows});

  static const empty = ProductSalesReportData(summary: ProductSalesSummary.empty, rows: []);
}

/// The Dashboard Overview: the figure of each of the six Cooperative Management areas, and the Revenue.
/// Everything follows the CURRENT YEAR and starts again each January (like the Marketplace and
/// Loans figures), so a year never piles onto the last one.
class DashboardOverview {
  /// Inventory Management: inventory items in use.
  final int inventoryItems;

  /// Crop Management: crops in use.
  final int crops;

  /// Program Management: programs of this year's season.
  final int programs;

  /// Marketplace revenue plus Cooperative Product sales, this year.
  final double revenue;

  /// Supply Chain Management: supplies tracked this year. Incoming and outgoing
  /// movements that really happened (Total Supplies = incoming + outgoing).
  final int suppliesIncoming;
  final int suppliesOutgoing;

  /// Incoming plus outgoing supplies of the year.
  int get totalSupplies => suppliesIncoming + suppliesOutgoing;

  /// Price Management: retail prices entered this year, Public Market and Cooperative Market.
  final int retailPrices;

  const DashboardOverview({
    required this.inventoryItems,
    required this.crops,
    required this.programs,
    required this.revenue,
    required this.suppliesIncoming,
    required this.suppliesOutgoing,
    required this.retailPrices,
  });

  static const empty = DashboardOverview(
    inventoryItems: 0,
    crops: 0,
    programs: 0,
    revenue: 0,
    suppliesIncoming: 0,
    suppliesOutgoing: 0,
    retailPrices: 0,
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
  final String cropType; // 'palay' | 'peanut' | other crop's lowercased name
  final String cropName;
  final double quantityKg;

  /// The unit quantityKg is measured in (the field keeps its old name).
  final String unit;
  final double amount;
  final DateTime saleDate;
  final String? referenceNo;
  final String
  sellingType; // offer_to_cooperative | marketplace | informal_sale | da_amad_market_linking
  final String?
  marketType; // 'Cooperative Market' | 'Public Market' | null (marketplace only)

  /// Populated for every channel except Offer to Cooperative (that
  /// transaction is directly with the cooperative, not an external
  /// buyer) — mirrors FarmerTransactionModel's identical field/rule.
  final String? buyerName;

  /// Marketplace only — always 'completed' today, since this channel is
  /// already filtered to completed orders only, but carried through as
  /// real data rather than a hardcoded label.
  final String? orderStatus;

  const SalesTransactionRow({
    required this.id,
    required this.farmerName,
    required this.cropType,
    required this.cropName,
    required this.quantityKg,
    this.unit = 'kg',
    required this.amount,
    required this.saleDate,
    this.referenceNo,
    required this.sellingType,
    this.marketType,
    this.buyerName,
    this.orderStatus,
    this.pricePerKg,
    this.buyerContact,
    this.buyerEmail,
    this.cropCategory,
    this.recordedBy,
    this.fromProgram = false,
  });

  /// The agreed / charged price per unit (Offer to Cooperative, Marketplace and
  /// DA-AMAD Market Linking), and — for Market Linking — the buyer's contact
  /// number and email as saved when the sale was recorded.
  final double? pricePerKg;
  final String? buyerContact;
  final String? buyerEmail;

  /// The crop's category (Vegetable, Fruit, ...), from the crop catalog.
  final String? cropCategory;

  /// The Manager / Officer who recorded the sale: who confirmed the receipt of a
  /// cooperative delivery, or recorded a Market Linking sale. Staff see this; it
  /// is never sent to a Farmer. Null when the channel has no staff step (Informal
  /// Sale) or the sale predates the record.
  final String? recordedBy;

  /// True when the batch this sale came from was produce a Cooperative Program gave the Farmer.
  final bool fromProgram;

  /// Plain-map form, so a channel's rows can be cached offline.
  Map<String, dynamic> toMap() => {
    'id': id,
    'farmerName': farmerName,
    'cropType': cropType,
    'cropName': cropName,
    'quantityKg': quantityKg,
    'unit': unit,
    'amount': amount,
    'saleDate': saleDate.toIso8601String(),
    'referenceNo': referenceNo,
    'sellingType': sellingType,
    'marketType': marketType,
    'buyerName': buyerName,
    'orderStatus': orderStatus,
    'pricePerKg': pricePerKg,
    'buyerContact': buyerContact,
    'buyerEmail': buyerEmail,
    'cropCategory': cropCategory,
    'recordedBy': recordedBy,
  };

  factory SalesTransactionRow.fromMap(Map<String, dynamic> map) =>
      SalesTransactionRow(
        id: map['id'] as String,
        farmerName: map['farmerName'] as String,
        cropType: map['cropType'] as String,
        cropName: map['cropName'] as String,
        quantityKg: (map['quantityKg'] as num).toDouble(),
        // Snapshots saved before units existed have none: they were kg.
        unit: (map['unit'] as String?)?.trim().isNotEmpty == true
            ? map['unit'] as String
            : 'kg',
        amount: (map['amount'] as num).toDouble(),
        saleDate: DateTime.parse(map['saleDate'] as String),
        referenceNo: map['referenceNo'] as String?,
        sellingType: map['sellingType'] as String,
        // Older offline snapshots stored "DA-AMAD Market" here, but DA-AMAD
        // is a selling channel and has no market type: that label is dropped.
        // The crop's real market type (Public / Cooperative) is kept.
        marketType: map['marketType'] == 'DA-AMAD Market'
            ? null
            : map['marketType'] as String?,
        buyerName: map['buyerName'] as String?,
        orderStatus: map['orderStatus'] as String?,
        pricePerKg: (map['pricePerKg'] as num?)?.toDouble(),
        buyerContact: map['buyerContact'] as String?,
        buyerEmail: map['buyerEmail'] as String?,
        cropCategory: map['cropCategory'] as String?,
        recordedBy: map['recordedBy'] as String?,
      );
}


/// Combines the four selling channels' completed sales into the Sales Report.
///
/// Pure (no database): the same rows give the same report, which is what the
/// tests rely on. Rules:
///  * Revenue and the monthly trend add each row's [SalesTransactionRow.amount]
///    — pesos are pesos whatever the unit — and are rounded to the centavo.
///  * Quantities are kg figures: a row measured in another unit (sack, piece…)
///    counts as a sale and in the revenue, but its quantity is not added to a
///    kg total. Units are never added together.
///  * Every row is counted once, under the channel it came from.
SalesReportData buildSalesReportData({
  required List<SalesTransactionRow> offerRows,
  required List<SalesTransactionRow> marketplaceRows,
  required List<SalesTransactionRow> informalRows,
  required List<SalesTransactionRow> daAmadRows,
}) {
  final allRows = [
    ...offerRows,
    ...marketplaceRows,
    ...informalRows,
    ...daAmadRows,
  ]..sort((a, b) => b.saleDate.compareTo(a.saleDate));

  double round2(double v) => (v * 100).round() / 100;
  double kgOf(SalesTransactionRow r) =>
      (r.unit.trim().isEmpty || r.unit.trim() == 'kg') ? r.quantityKg : 0;

  double totalRevenue = 0;
  double totalQtyKg = 0;
  final monthlyBuckets = <String, double>{};
  for (final row in allRows) {
    totalRevenue += row.amount;
    totalQtyKg += kgOf(row);
    final bucketKey =
        '${row.saleDate.year}-${row.saleDate.month.toString().padLeft(2, '0')}';
    monthlyBuckets[bucketKey] = (monthlyBuckets[bucketKey] ?? 0) + row.amount;
  }

  final sortedMonthKeys = monthlyBuckets.keys.toList()..sort();
  final fullTrend = sortedMonthKeys
      .map((k) => round2(monthlyBuckets[k]!))
      .toList();
  final trend = fullTrend.length > 6
      ? fullTrend.sublist(fullTrend.length - 6)
      : fullTrend;

  SalesChannelTotal channel(String type, List<SalesTransactionRow> rows) =>
      SalesChannelTotal(
        sellingType: type,
        label: sellingChannelLabel(type),
        amount: round2(rows.fold(0.0, (sum, r) => sum + r.amount)),
        quantityKg: round2(rows.fold(0.0, (sum, r) => sum + kgOf(r))),
        transactionCount: rows.length,
      );

  // The four channel cards are always present, zero-valued when a channel has
  // no sales in the period.
  return SalesReportData(
    totalRevenue: round2(totalRevenue),
    totalQuantityKg: round2(totalQtyKg),
    transactionCount: allRows.length,
    monthlyTrend: trend,
    transactions: allRows,
    channelTotals: [
      channel('offer_to_cooperative', offerRows),
      channel('marketplace', marketplaceRows),
      channel('informal_sale', informalRows),
      channel('da_amad_market_linking', daAmadRows),
    ],
  );
}

/// English display name of a selling channel key, for the exported CSV and
/// PDF files (which have no BuildContext). On-screen labels come from the
/// localization files instead; both use the same wording.
String sellingChannelLabel(String sellingType) {
  switch (sellingType) {
    case 'offer_to_cooperative':
      return 'Offer to Cooperative';
    case 'marketplace':
      return 'Marketplace';
    case 'informal_sale':
      return 'Informal Sale';
    case 'da_amad_market_linking':
      return 'DA-AMAD Market Linking';
    default:
      return sellingType;
  }
}

/// One selling channel's aggregate — Sales Report's four channel cards.
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

/// One month of a member's monthly contribution, for the year's month list.
class MemberMonthStatus {
  final DateTime month;
  final double amountDue;
  final double paid;

  /// paid | partial | unpaid | overdue | waived
  final String status;
  const MemberMonthStatus({
    required this.month,
    required this.amountDue,
    required this.paid,
    required this.status,
  });

  factory MemberMonthStatus.fromMap(Map<String, dynamic> m) =>
      MemberMonthStatus(
        month: DateTime.parse(m['month'] as String),
        amountDue: (m['due'] as num?)?.toDouble() ?? 0,
        paid: (m['paid'] as num?)?.toDouble() ?? 0,
        status: (m['status'] as String?) ?? 'unpaid',
      );
}

/// One Monthly Contribution record of the year: a payment, Starting Capital, a
/// correction or an older payout, or the cancellation of one.
class MemberCapitalRecord {
  final DateTime date;
  final String source;
  final double amount;
  final DateTime? month;
  final bool isReversal;
  const MemberCapitalRecord({
    required this.date,
    required this.source,
    required this.amount,
    this.month,
    this.isReversal = false,
  });

  factory MemberCapitalRecord.fromMap(Map<String, dynamic> m) =>
      MemberCapitalRecord(
        date: DateTime.parse(m['date'] as String),
        source: m['source'] as String,
        amount: (m['amount'] as num).toDouble(),
        month: m['month'] == null ? null : DateTime.parse(m['month'] as String),
        isReversal: m['rev'] == true,
      );
}

/// version -> [credited, base amount, discount earned], from the cached map form.
Map<int, List<double>> parseCreditSlices(Object? raw) => {
  if (raw is Map)
    for (final e in raw.entries)
      int.parse('${e.key}'): [
        for (final v in (e.value as List)) (v as num).toDouble(),
      ],
};

class MemberContributionRow {
  final String farmerId;
  final String farmerName;
  final double palayQtyKg;
  final double palayAmount;
  final double peanutQtyKg;
  final double peanutAmount;
  final double totalAmount;

  /// Any crop other than Palay/Peanut sold via Offer to Cooperative, as of
  /// Phase 9's any-crop widening (Phase 11 addition) — previously any such
  /// sale was invisible here, silently missing from the member's total.
  final double otherCropsQtyKg;
  final double otherCropsAmount;

  /// Option B — Product Sales Program purchases (farmer buys FROM the
  /// coop), kept structurally separate from totalAmount
  /// above (farmer sells TO the coop via Offer to Cooperative). Shown as
  /// its own line, never folded into the sales-based total.
  final double programPurchasesAmount;
  // For display only: the member-price purchases at the regular price and the
  // discount given (regular - discount = programPurchasesAmount).
  final double programRegularAmount;
  final double programDiscountAmount;

  /// Source 1 — monthly contributions PAID toward the year's months (the Contribution
  /// section in Farmer Details), net of cancellations. Only actual payments: an
  /// unpaid balance is never in here or in the Capital Share.
  final double monthlyContributions;

  /// The year's monthly obligation (waived months owe nothing), what is still owed
  /// (due - paid), and how many months are in each status. A month is in exactly
  /// one status, so the five counts add up to the months of the year.
  final double monthlyDue;
  final double monthlyBalance;
  final int monthsPaid;
  final int monthsPartial;
  final int monthsUnpaid;
  final int monthsOverdue;
  final int monthsWaived;

  /// Monthly payments recorded before payments were tied to a month. They stay in
  /// the Capital Share but belong to no month, so they are not in [monthlyContributions].
  final double monthlyUnassigned;

  /// Purchase discount that has been credited to this member's Capital Share in
  /// the year. Compare with [programDiscountAmount] (what was earned).
  final double discountCredited;

  /// Cooperative Purchase credits (a percentage of the net amount paid) and the
  /// amounts they were worked out from; Offer to Cooperative credits likewise.
  final double purchaseShareCredited;
  final double purchaseShareBase;
  final double offerShareCredited;
  final double offerShareBase;

  /// Starting Capital dated in the year: capital the member already had, shown
  /// beside the contributions but NOT counted in [totalContributions].
  final double startingCapital;

  /// Capital Share at the end of the year (this year: right now), as in Farmer
  /// Details: the ledger total and the whole ₱ shares it makes up.
  final double capitalBalance;

  /// The value of one full share for this member (member_capital_shares.
  /// share_value_per_unit, the cooperative's setting; 2,000 when the member has no row).
  final double capitalShareValue;

  /// The Capital Share at the start of the year (the ledger before it). The
  /// balance at the end (or now) is [capitalBalance]; what was added in between
  /// is [capitalAddedInYear].
  final double capitalAtYearStart;

  /// The year's months with their status, oldest first (what the member card lists).
  final List<MemberMonthStatus> months;

  /// The year's Monthly Contribution records, each its own entry.
  final List<MemberCapitalRecord> records;

  /// The percentage credits split by the settings version they were made under
  /// (version -> [credited, base amount, discount earned]), the latest version and
  /// how many times the settings have been changed. Newly credited = the latest
  /// version; previous = every earlier one.
  final Map<int, List<double>> purchaseByVersion;
  final Map<int, List<double>> offerByVersion;
  final int latestRateVersion;
  final int rateChanges;

  /// transaction id -> the settings version its credit was made under (to split a
  /// member's purchases / offers into newly credited and previous).
  final Map<String, int> creditVersions;
  final int capitalShares;

  const MemberContributionRow({
    required this.farmerId,
    required this.farmerName,
    required this.palayQtyKg,
    required this.palayAmount,
    required this.peanutQtyKg,
    required this.peanutAmount,
    required this.totalAmount,
    this.otherCropsQtyKg = 0,
    this.otherCropsAmount = 0,
    this.programPurchasesAmount = 0,
    this.programRegularAmount = 0,
    this.programDiscountAmount = 0,
    this.monthlyContributions = 0,
    this.monthlyDue = 0,
    this.monthlyBalance = 0,
    this.monthsPaid = 0,
    this.monthsPartial = 0,
    this.monthsUnpaid = 0,
    this.monthsOverdue = 0,
    this.monthsWaived = 0,
    this.monthlyUnassigned = 0,
    this.discountCredited = 0,
    this.purchaseShareCredited = 0,
    this.purchaseShareBase = 0,
    this.offerShareCredited = 0,
    this.offerShareBase = 0,
    this.startingCapital = 0,
    this.capitalBalance = 0,
    this.capitalShareValue = 2000,
    this.capitalAtYearStart = 0,
    this.months = const [],
    this.records = const [],
    this.purchaseByVersion = const {},
    this.offerByVersion = const {},
    this.latestRateVersion = 1,
    this.rateChanges = 0,
    this.creditVersions = const {},
    this.capitalShares = 0,
  });

  /// What the three sources ADDED to the Capital Share in the year. Total Capital
  /// Share = Monthly Contribution + Cooperative Purchase + Offer to Cooperative.
  ///  - Cooperative Purchase: [purchaseCredited], a percentage of the completed
  ///    member-price orders (and any earlier discount credit).
  ///  - Offer to Cooperative: [offersCredited], a percentage of the completed
  ///    offers' sale value.
  ///  - Monthly Contribution: [memberPaidInYear], everything the member paid in
  ///    themselves (the payments, Starting Capital, corrections).
  /// All three come from the one capital ledger, so nothing is counted twice and
  /// the three always add up to [capitalAddedInYear].
  double get purchaseCredited => discountCredited + purchaseShareCredited;
  double get offersCredited => offerShareCredited;

  /// Everything the ledger added to the Capital Share in the year (the balance
  /// now or at year end, minus the balance at the start).
  double get capitalAddedInYear => capitalBalance - capitalAtYearStart;

  /// The Monthly Contribution part of what was added: whatever the member paid
  /// in (monthly payments, Starting Capital, corrections), i.e. the rest after the
  /// two percentage credits.
  double get memberPaidInYear =>
      capitalAddedInYear - purchaseCredited - offersCredited;

  /// Of [memberPaidInYear], what is neither a monthly payment nor Starting Capital:
  /// corrections and an older payout added to capital.
  double get otherCapitalAdded =>
      memberPaidInYear - monthlyContributions - startingCapital;

  double get totalContributions => capitalAddedInYear;

  bool get hasContributed => capitalAddedInYear > 0.004;

  /// The effective discount rate on this farmer's member-price purchases:
  /// discount given as a share of the regular price (0 when there is none).
  double get programDiscountRatePercent =>
      programRegularAmount > 0 ? programDiscountAmount / programRegularAmount * 100 : 0;

  /// Anything to show for the year: a contribution, a purchase or offer, or a month.
  bool get hasAnyActivity =>
      hasContributed ||
      programPurchasesAmount > 0 ||
      totalAmount > 0 ||
      monthsCount > 0;

  /// What is still needed for the NEXT full share: the next whole share's value
  /// minus the Capital Share held. Never below zero.
  double get remainingForNextShare =>
      ((capitalShares + 1) * capitalShareValue - capitalBalance)
          .clamp(0.0, double.infinity)
          .toDouble();

  /// The member has monthly months this year (even if nothing is paid yet).
  int get monthsCount =>
      monthsPaid + monthsPartial + monthsUnpaid + monthsOverdue + monthsWaived;
}

class MemberContributionReportData {
  final int year;
  final int memberCount;
  final int contributingMemberCount;
  final List<MemberContributionRow> rows;

  const MemberContributionReportData({
    required this.year,
    required this.memberCount,
    required this.contributingMemberCount,
    required this.rows,
  });

  double _sum(double Function(MemberContributionRow r) f) =>
      rows.fold<double>(0, (t, r) => t + f(r));

  // The three sources, and what they add up to, for all active members.
  double get totalMonthly => _sum((r) => r.monthlyContributions);
  double get totalMonthlyDue => _sum((r) => r.monthlyDue);
  double get totalMonthlyBalance => _sum((r) => r.monthlyBalance);
  int get totalMonthsOverdue =>
      rows.fold<int>(0, (t, r) => t + r.monthsOverdue);
  double get totalPurchases => _sum((r) => r.programPurchasesAmount);
  double get totalOffers => _sum((r) => r.totalAmount);
  double get totalContributions => _sum((r) => r.totalContributions);
  double get totalCapitalAdded => _sum((r) => r.capitalAddedInYear);

  // Capital Share.
  double get totalPurchaseCredited => _sum((r) => r.purchaseCredited);
  double get totalOffersCredited => _sum((r) => r.offersCredited);
  double get totalMemberPaid => _sum((r) => r.memberPaidInYear);
  double get totalStartingCapital => _sum((r) => r.startingCapital);
  double get totalCapital => _sum((r) => r.capitalBalance);
  int get totalShares => rows.fold<int>(0, (t, r) => t + r.capitalShares);

  double get participationPercent =>
      memberCount > 0 ? (contributingMemberCount / memberCount * 100) : 0;

  factory MemberContributionReportData.empty(int year) =>
      MemberContributionReportData(
        year: year,
        memberCount: 0,
        contributingMemberCount: 0,
        rows: const [],
      );
}

// ─── Inventory Report ───────────────────────────────────────────────────────

/// Kilograms of a batch already committed to a Marketplace listing, a
/// cooperative offer or a sale that is not yet completed: what is left of the
/// harvested quantity after available, sold and adjusted (taken out by the
/// Farmer) stock. The database keeps `inventory_batches.reserved_kg` equal to
/// this (supabase_schema_farmer_stock_management.sql); this is the same rule
/// for rows read without that column.
double committedBatchKg({
  required double quantityKg,
  required double availableKg,
  required double soldKg,
  double adjustedKg = 0,
}) => (quantityKg - availableKg - soldKg - adjustedKg).clamp(0.0, double.infinity);

/// One row in Inventory Report's batch table. Available and Sold are real
/// stored columns on inventory_batches. [reservedKg] is the committed amount
/// (see [committedBatchKg]) and is shown to the Manager as "Committed".
class InventoryReportRow {
  final String batchId;
  final String farmerId;
  final String farmerName;
  final String cropName;
  final String batchNumber;
  final double quantityKg;
  final double availableKg;
  final double reservedKg;
  final double soldKg;

  /// The unit every quantity on this row is measured in.
  final String unit;
  final String
  status; // available | reserved | sold_out | withdrawn | low_stock
  final DateTime createdAt;

  /// Quantity of this batch the Farmer reported as rotten, in [unit].
  final double spoiledKg;

  /// Nothing of the batch is left: what remained was reported as rotten.
  bool get isLost => spoiledKg > 0 && availableKg <= 0 && reservedKg <= 0;

  /// Rotten/Lost: some or all of the batch was reported as rotten.
  bool get hasLoss => spoiledKg > 0;

  /// This batch's own shelf-life tracking (null when the crop has none set).
  final BatchShelfLife? shelfLife;

  /// Good: nothing reported rotten and stock is still on hand.
  bool get isGood => !hasLoss && (availableKg > 0 || reservedKg > 0);

  /// The condition as the reports and exports word it: "Rotten/Lost", "Good",
  /// or empty for a batch with nothing left and no loss (sold out).
  String get conditionLabel => hasLoss
      ? 'Rotten/Lost'
      : isGood
      ? 'Good'
      : '';

  /// The shelf-life standing of a Good batch, for exports: "3 days left",
  /// "Ends today", "Past shelf life", "On hold" or "Not tracked". Empty when
  /// the batch is not Good.
  String get shelfLifeExportLabel {
    if (!isGood) return '';
    final s = shelfLife;
    switch (s?.stage ?? ShelfLifeStage.untracked) {
      case ShelfLifeStage.untracked:
        return 'Not tracked';
      case ShelfLifeStage.fresh:
        return '${s!.daysLeft} days left';
      case ShelfLifeStage.nearExpiry:
        return '1 day left';
      case ShelfLifeStage.expiresToday:
        return 'Ends today';
      case ShelfLifeStage.expired:
        return 'Past shelf life';
      case ShelfLifeStage.hold:
        return 'On hold';
    }
  }

  const InventoryReportRow({
    required this.batchId,
    required this.farmerId,
    required this.farmerName,
    required this.cropName,
    required this.batchNumber,
    required this.quantityKg,
    required this.availableKg,
    required this.reservedKg,
    required this.soldKg,
    this.unit = 'kg',
    required this.status,
    required this.createdAt,
    this.spoiledKg = 0,
    this.shelfLife,
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

  /// Kilograms Farmers reported as rotten (Rotten/Lost), all batches.
  final double totalSpoiledKg;
  final int lowStockCount;
  final List<CropStockBreakdown> cropBreakdown;
  final List<InventoryReportRow> batches;

  const InventoryReportData({
    required this.totalAvailableKg,
    required this.totalReservedKg,
    required this.totalSoldKg,
    this.totalSpoiledKg = 0,
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

/// One row in Harvest Report's table. is_synced is a real stored column on
/// harvest_records — no inference needed, same as the Available/Reserved/
/// Sold columns on Inventory Report.
///
/// submitted_to_cooperative previously appeared here too, but it's dead
/// data — the column exists on harvest_records but nothing anywhere in the
/// app (Dart or SQL) ever sets it to true, so it always read as "Not
/// Submitted"/false. A harvest's produce being sold to the cooperative is
/// tracked separately, at the inventory-batch level, via
/// member_sales_transactions — not on the harvest record itself. Removed
/// rather than fixed, since no code path actually implements that
/// per-harvest signal; the DB column itself is left in place, unreferenced
/// (same precedent as InventoryRepository's removed deleteBatch()).
class HarvestReportRow {
  final String id;
  final String farmerId;
  final String farmerName;
  final String cropName;
  final double quantityKg;

  /// The unit quantityKg is measured in.
  final String unit;
  final DateTime harvestDate;
  final bool isSynced;
  final String batchNumber; // links 1:1 to InventoryReportRow.batchNumber

  /// The crop's category (Vegetable, Fruit, Grain ...), for the entry filter.
  final String cropCategory;

  /// Quantity of this harvest the Farmer reported as rotten, in [unit].
  final double spoiledKg;

  /// Nothing of this harvest is left: what remained was reported as rotten.
  final bool isLost;

  /// Rotten/Lost: some or all of the harvest was reported as rotten.
  bool get hasLoss => spoiledKg > 0;

  const HarvestReportRow({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    required this.cropName,
    required this.quantityKg,
    this.unit = 'kg',
    required this.harvestDate,
    required this.isSynced,
    required this.batchNumber,
    this.cropCategory = 'Other',
    this.spoiledKg = 0,
    this.isLost = false,
  });
}

class HarvestReportData {
  final double totalYieldKg;
  final int harvestCount;
  final int unsyncedCount;
  final List<double> monthlyTrend;
  final List<CropStockBreakdown> cropBreakdown;
  final List<HarvestReportRow> harvests;
  // Kg actually disposed of (across all 4 real selling channels — Offer to
  // Cooperative, Marketplace, Informal Sale, DA-AMAD Market Linking) within
  // the SAME period selected for totalYieldKg above. Deliberately distinct
  // from InventoryReportData.totalSoldKg, which is an all-time cumulative
  // snapshot, not period-scoped — this pairs with totalYieldKg to show
  // "harvested vs. sold" for one window, rather than duplicating the live
  // Available Stock figure shown elsewhere on the same screen.
  final double soldKgInPeriod;
  // Produce Cooperative Programs gave Farmers in the period. Listed on its own: it is not production and is
  // not in totalYieldKg or harvestCount.
  final double programReceivedKg;
  final int programReceivedCount;

  const HarvestReportData({
    required this.totalYieldKg,
    required this.harvestCount,
    required this.unsyncedCount,
    required this.monthlyTrend,
    required this.cropBreakdown,
    required this.harvests,
    required this.soldKgInPeriod,
    this.programReceivedKg = 0,
    this.programReceivedCount = 0,
  });

  factory HarvestReportData.empty() => const HarvestReportData(
    totalYieldKg: 0,
    harvestCount: 0,
    unsyncedCount: 0,
    monthlyTrend: [],
    cropBreakdown: [],
    harvests: [],
    soldKgInPeriod: 0,
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
  final String name;
  final String category;
  final String description;
  final double amount;
  final bool isSubsidy;
  final DateTime expenseDate;

  const ExpenseReportRow({
    required this.farmerId,
    required this.farmerName,
    required this.name,
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
  // 'crop' or 'non_crop', from Inventory Management.
  final String itemType;
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
    this.itemType = 'non_crop',
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
  // How many items are of each Item Type (their sum is [totalItems]).
  final int seedsItemCount;
  final int produceItemCount;
  final int nonCropItemCount;

  const CoopStockReportData({
    required this.totalItems,
    required this.lowStockCount,
    required this.categoryCounts,
    required this.items,
    this.seedsItemCount = 0,
    this.produceItemCount = 0,
    this.nonCropItemCount = 0,
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
