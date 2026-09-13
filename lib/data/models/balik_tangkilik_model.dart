/// Per-member row for Balik-Tangkilik's distribution preview/final table.
/// Combines sales-based patronage refund with capital-based interest —
/// two separate computations on two separate bases, per the cooperative's
/// real accounting practice.
class MemberDistributionRow {
  final String farmerId;
  final String farmerName;
  final String memberId;
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

  const MemberDistributionRow({
    required this.farmerId,
    required this.farmerName,
    required this.memberId,
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
  });

  double get estimatedTotal => estimatedBalikTangkilik + estimatedInterest;
  double get actualTotal => (actualBalikTangkilik ?? 0) + (actualInterest ?? 0);
  bool get isPaid => status == 'paid';
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

  const BalikTangkilikYearSummary({
    required this.year,
    required this.totalCoopSales,
    required this.liveTotalCoopSales,
    required this.distributableSurplus,
    required this.interestRatePercent,
    required this.afsFinalized,
    required this.isDistributed,
    required this.rows,
  });

  double get totalEstimatedPayout =>
      rows.fold(0, (sum, r) => sum + r.estimatedTotal);

  double get totalActualPayout =>
      rows.fold(0, (sum, r) => sum + r.actualTotal);

  int get contributingMemberCount => rows.where((r) => r.totalSalesAmount > 0).length;

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

  factory BalikTangkilikYearSummary.empty(int year) => BalikTangkilikYearSummary(
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