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
  });

  double get estimatedTotal => estimatedBalikTangkilik + estimatedInterest;
  double get actualTotal => (actualBalikTangkilik ?? 0) + (actualInterest ?? 0);
  bool get isPaid => status == 'paid';
}

class BalikTangkilikYearSummary {
  final int year;
  final double totalCoopSales;
  final double distributableSurplus;
  final double interestRatePercent;
  final bool afsFinalized;
  final bool isDistributed;
  final List<MemberDistributionRow> rows;

  const BalikTangkilikYearSummary({
    required this.year,
    required this.totalCoopSales,
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

  factory BalikTangkilikYearSummary.empty(int year) => BalikTangkilikYearSummary(
        year: year,
        totalCoopSales: 0,
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