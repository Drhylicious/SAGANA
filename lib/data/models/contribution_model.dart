class MemberSalesTransaction {
  final String id;
  final String farmerId;
  final String cropName;
  final String cropType; // 'palay' | 'peanut'
  final double quantityKg;
  final double amount;
  final DateTime saleDate;
  final String? referenceNo;

  const MemberSalesTransaction({
    required this.id,
    required this.farmerId,
    required this.cropName,
    required this.cropType,
    required this.quantityKg,
    required this.amount,
    required this.saleDate,
    this.referenceNo,
  });

  factory MemberSalesTransaction.fromMap(Map<String, dynamic> map) {
    return MemberSalesTransaction(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      cropName: map['crop_name'] as String,
      cropType: map['crop_type'] as String? ?? 'palay',
      quantityKg: (map['quantity_kg'] as num).toDouble(),
      amount: (map['amount'] as num).toDouble(),
      saleDate: DateTime.parse(map['sale_date'] as String),
      referenceNo: map['reference_no'] as String?,
    );
  }
}

class MemberContribution {
  final String id;
  final String farmerId;
  final int year;
  final double totalSalesAmount;
  final double palaySalesKg;
  final double palaySalesAmount;
  final double peanutSalesKg;
  final double peanutSalesAmount;
  final double estimatedBalikTangkilik;
  final double estimatedInterestOnCapital;
  final double? actualBalikTangkilik;
  final double? actualInterestOnCapital;
  final DateTime? actualPayoutDate;
  final String status; // pending | paid | not_yet_computed

  const MemberContribution({
    required this.id,
    required this.farmerId,
    required this.year,
    required this.totalSalesAmount,
    required this.palaySalesKg,
    required this.palaySalesAmount,
    required this.peanutSalesKg,
    required this.peanutSalesAmount,
    required this.estimatedBalikTangkilik,
    required this.estimatedInterestOnCapital,
    this.actualBalikTangkilik,
    this.actualInterestOnCapital,
    this.actualPayoutDate,
    required this.status,
  });

  bool get isPaid => status == 'paid';

  double get estimatedTotal =>
      estimatedBalikTangkilik + estimatedInterestOnCapital;

  double get actualTotal =>
      (actualBalikTangkilik ?? 0) + (actualInterestOnCapital ?? 0);

  factory MemberContribution.fromMap(Map<String, dynamic> map) {
    return MemberContribution(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      year: map['year'] as int,
      totalSalesAmount: (map['total_sales_amount'] as num? ?? 0).toDouble(),
      palaySalesKg: (map['palay_sales_kg'] as num? ?? 0).toDouble(),
      palaySalesAmount: (map['palay_sales_amount'] as num? ?? 0).toDouble(),
      peanutSalesKg: (map['peanut_sales_kg'] as num? ?? 0).toDouble(),
      peanutSalesAmount: (map['peanut_sales_amount'] as num? ?? 0).toDouble(),
      estimatedBalikTangkilik:
          (map['estimated_balik_tangkilik'] as num? ?? 0).toDouble(),
      estimatedInterestOnCapital:
          (map['estimated_interest_on_capital'] as num? ?? 0).toDouble(),
      actualBalikTangkilik: map['actual_balik_tangkilik'] != null
          ? (map['actual_balik_tangkilik'] as num).toDouble()
          : null,
      actualInterestOnCapital: map['actual_interest_on_capital'] != null
          ? (map['actual_interest_on_capital'] as num).toDouble()
          : null,
      actualPayoutDate: map['actual_payout_date'] != null
          ? DateTime.parse(map['actual_payout_date'] as String)
          : null,
      status: map['status'] as String? ?? 'pending',
    );
  }
}

class CapitalSharesModel {
  final String farmerId;

  /// Completed whole shares — trigger-maintained as
  /// floor(totalContribution / shareValuePerUnit). Only fully-paid
  /// ₱2,000 increments count (Decision D1f).
  final int totalShares;

  /// Fixed by the BOD. ₱2,000 per share as of Phase B.
  final double shareValuePerUnit;

  /// Authoritative running ₱ total of all recorded capital
  /// contributions (from capital_contribution_events). Loan eligibility
  /// is checked against this, not [totalShares].
  final double totalContribution;

  const CapitalSharesModel({
    required this.farmerId,
    required this.totalShares,
    required this.shareValuePerUnit,
    this.totalContribution = 0,
  });

  /// Value of the completed whole shares only (interest-on-capital base).
  double get investmentValue => totalShares * shareValuePerUnit;

  /// ₱ still needed to complete the next whole share.
  double get amountToNextShare {
    if (shareValuePerUnit <= 0) return 0;
    final remainder = totalContribution % shareValuePerUnit;
    return remainder == 0 ? 0 : shareValuePerUnit - remainder;
  }

  factory CapitalSharesModel.fromMap(Map<String, dynamic> map) {
    return CapitalSharesModel(
      farmerId: map['farmer_id'] as String,
      totalShares: map['total_shares'] as int? ?? 0,
      shareValuePerUnit:
          (map['share_value_per_unit'] as num? ?? 2000).toDouble(),
      totalContribution:
          (map['total_contribution'] as num? ?? 0).toDouble(),
    );
  }
}

/// One row of the capital-contribution ledger
/// (capital_contribution_events).
class CapitalContributionEvent {
  final String id;
  final String farmerId;
  final double amount;
  final String source; // member_payment | patronage_capital | manual_adjustment | opening_balance
  final String? note;
  final DateTime createdAt;

  const CapitalContributionEvent({
    required this.id,
    required this.farmerId,
    required this.amount,
    required this.source,
    required this.createdAt,
    this.note,
  });

  factory CapitalContributionEvent.fromMap(Map<String, dynamic> map) {
    return CapitalContributionEvent(
      id: map['id'] as String,
      farmerId: map['farmer_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      source: map['source'] as String? ?? 'member_payment',
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class CoopAnnualTotal {
  final int year;
  final double totalCoopSales;
  final double distributableSurplus;
  final double interestRatePercent;
  final bool afsFinalized;

  const CoopAnnualTotal({
    required this.year,
    required this.totalCoopSales,
    required this.distributableSurplus,
    required this.interestRatePercent,
    this.afsFinalized = false,
  });

  factory CoopAnnualTotal.fromMap(Map<String, dynamic> map) {
    return CoopAnnualTotal(
      year: map['year'] as int,
      totalCoopSales: (map['total_coop_sales'] as num? ?? 0).toDouble(),
      distributableSurplus:
          (map['distributable_surplus'] as num? ?? 0).toDouble(),
      interestRatePercent:
          (map['interest_rate_percent'] as num? ?? 7).toDouble(),
      afsFinalized: map['afs_finalized'] as bool? ?? false,
    );
  }
}


