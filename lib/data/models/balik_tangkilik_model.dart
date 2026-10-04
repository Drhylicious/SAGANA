/// Per-member row for Balik-Tangkilik's distribution preview/final table.
/// Combines sales-based patronage refund with capital-based interest —
/// two separate computations on two separate bases, per the cooperative's
/// real accounting practice.
class MemberDistributionRow {
  final String farmerId;
  final String farmerName;
  final double totalSalesAmount;
  final double sharePercent;
  final int totalShares;
  final double capitalShareValue;
  final double estimatedBalikTangkilik;
  final double estimatedInterest;
  final double? actualBalikTangkilik;
  final double? actualInterest;
  final String status; // pending | paid | not_yet_computed
  final DateTime? actualPayoutDate;
  final double palaySalesKg;
  final double palaySalesAmount;
  final double peanutSalesKg;
  final double peanutSalesAmount;
  final double otherCropsQtyKg;
  final double otherCropsAmount;

  /// Option B — Product Sales Program purchases (farmer buys FROM the
  /// coop), kept structurally separate from the sales fields above
  /// (farmer sells TO the coop) at every layer. purchaseSharePercent and
  /// estimatedPurchasePatronage are computed the same way their sales-side
  /// counterparts are, but against totalProgramSales/
  /// distributableProgramSurplus instead — never the sales-side pool.
  final double programPurchasesAmount;
  final double purchaseSharePercent;
  final double estimatedPurchasePatronage;
  final double? actualPurchasePatronage;

  /// Null | 'pending_cash' | 'pending_capital' | 'cash_confirmed' | 'capital_confirmed'.
  /// Only meaningful once [isPaid] — the farmer's own choice of what to do
  /// with a finalized payout, submitted via request_payout_decision() and
  /// only taking real effect once an admin calls confirm_payout_decision().
  final String? payoutDecision;
  final double? payoutDecisionAmount;

  const MemberDistributionRow({
    required this.farmerId,
    required this.farmerName,
    required this.totalSalesAmount,
    required this.sharePercent,
    required this.totalShares,
    required this.capitalShareValue,
    required this.estimatedBalikTangkilik,
    required this.estimatedInterest,
    this.actualBalikTangkilik,
    this.actualInterest,
    required this.status,
    this.actualPayoutDate,
    this.palaySalesKg = 0,
    this.palaySalesAmount = 0,
    this.peanutSalesKg = 0,
    this.peanutSalesAmount = 0,
    this.otherCropsQtyKg = 0,
    this.otherCropsAmount = 0,
    this.programPurchasesAmount = 0,
    this.purchaseSharePercent = 0,
    this.estimatedPurchasePatronage = 0,
    this.actualPurchasePatronage,
    this.payoutDecision,
    this.payoutDecisionAmount,
  });

  double get estimatedTotal =>
      estimatedBalikTangkilik + estimatedInterest + estimatedPurchasePatronage;
  double get actualTotal =>
      (actualBalikTangkilik ?? 0) +
      (actualInterest ?? 0) +
      (actualPurchasePatronage ?? 0);
  bool get isPaid => status == 'paid';

  bool get hasPendingPayoutDecision =>
      payoutDecision == 'pending_cash' || payoutDecision == 'pending_capital';
  bool get hasConfirmedPayoutDecision =>
      payoutDecision == 'cash_confirmed' ||
      payoutDecision == 'capital_confirmed';
}

class BalikTangkilikYearSummary {
  final int year;
  final double totalCoopSales;
  final double liveTotalCoopSales;
  final double distributableSurplus;
  final double interestRatePercent;
  final bool afsFinalized;
  final bool isDistributed;
  final List<MemberDistributionRow> rows;

  /// Option B's parallel Product Sales Program year settings.
  final double totalProgramSales;
  final double liveTotalProgramSales;
  final double distributableProgramSurplus;

  const BalikTangkilikYearSummary({
    required this.year,
    required this.totalCoopSales,
    required this.liveTotalCoopSales,
    required this.distributableSurplus,
    required this.interestRatePercent,
    required this.afsFinalized,
    required this.isDistributed,
    required this.rows,
    this.totalProgramSales = 0,
    this.liveTotalProgramSales = 0,
    this.distributableProgramSurplus = 0,
  });

  double get totalEstimatedPayout =>
      rows.fold(0, (sum, r) => sum + r.estimatedTotal);

  double get totalActualPayout => rows.fold(0, (sum, r) => sum + r.actualTotal);

  int get contributingMemberCount =>
      rows.where((r) => r.totalSalesAmount > 0).length;

  /// Percent difference between the admin-entered totalCoopSales and the
  /// live sum of individual member sales transactions. Null when there's
  /// no live sales data yet to compare against — avoids a misleading
  /// ±100% reading against a zero baseline (same reasoning as
  /// ReportDeltaBadge's zero-previous guard elsewhere in Reports).
  double? get salesDivergencePercent {
    if (liveTotalCoopSales == 0) return null;
    return ((totalCoopSales - liveTotalCoopSales) / liveTotalCoopSales) * 100;
  }

  /// True when the entered total diverges from the live sales sum by
  /// more than 5%. A threshold, not an error — an audited figure is
  /// expected to differ somewhat from a raw transaction sum — but a gap
  /// this large is worth a visible check before real money is
  /// distributed on it.
  bool get hasSignificantSalesDivergence =>
      salesDivergencePercent != null && salesDivergencePercent!.abs() > 5;

  factory BalikTangkilikYearSummary.empty(int year) =>
      BalikTangkilikYearSummary(
        year: year,
        totalCoopSales: 0,
        liveTotalCoopSales: 0,
        distributableSurplus: 0,
        interestRatePercent: 7,
        afsFinalized: false,
        isDistributed: false,
        rows: const [],
      );
}

/// One year's worth of finalized distribution, for the History tab.
class DistributionHistoryYear {
  final int year;
  final double totalDistributed;
  final int memberCount;

  const DistributionHistoryYear({
    required this.year,
    required this.totalDistributed,
    required this.memberCount,
  });
}