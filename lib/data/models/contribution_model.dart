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
  final int totalShares;
  final double shareValuePerUnit;

  const CapitalSharesModel({
    required this.farmerId,
    required this.totalShares,
    required this.shareValuePerUnit,
  });

  double get investmentValue => totalShares * shareValuePerUnit;

  factory CapitalSharesModel.fromMap(Map<String, dynamic> map) {
    return CapitalSharesModel(
      farmerId: map['farmer_id'] as String,
      totalShares: map['total_shares'] as int? ?? 0,
      shareValuePerUnit:
          (map['share_value_per_unit'] as num? ?? 100).toDouble(),
    );
  }
}

class CoopAnnualTotal {
  final int year;
  final double totalCoopSales;
  final double distributableSurplus;
  final double interestRatePercent;

  const CoopAnnualTotal({
    required this.year,
    required this.totalCoopSales,
    required this.distributableSurplus,
    required this.interestRatePercent,
  });

  factory CoopAnnualTotal.fromMap(Map<String, dynamic> map) {
    return CoopAnnualTotal(
      year: map['year'] as int,
      totalCoopSales: (map['total_coop_sales'] as num? ?? 0).toDouble(),
      distributableSurplus:
          (map['distributable_surplus'] as num? ?? 0).toDouble(),
      interestRatePercent:
          (map['interest_rate_percent'] as num? ?? 7).toDouble(),
    );
  }
}
