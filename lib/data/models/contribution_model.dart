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

  /// Any crop other than Palay/Peanut sold via Offer to Cooperative, as of
  /// Phase 9's any-crop widening — previously any such sale was invisible
  /// on the farmer's own "My Total Sales to SP3" card and Admin's Farmer
  /// Details "Volume to SP3" stat, even though totalSalesAmount already
  /// correctly included it (see supabase_schema_member_contributions_
  /// other_crops.sql).
  final double otherCropsQtyKg;
  final double otherCropsAmount;
  final double estimatedBalikTangkilik;
  final double estimatedInterestOnCapital;
  final double? actualBalikTangkilik;
  final double? actualInterestOnCapital;
  final DateTime? actualPayoutDate;
  final String status; // pending | paid | not_yet_computed

  /// How much of this year's finalized payout (actualTotal) the farmer has
  /// already chosen to reinvest as capital share, via
  /// reinvest_patronage_capital(). Zero until they ever do.
  final double reinvestedAmount;

  /// Product Sales Program (farmer buys FROM the coop) — a second, parallel
  /// patronage pool never blended with the Offer to Cooperative (sales)
  /// figures above. See supabase_schema_program_sales_patronage.sql.
  final double programPurchasesAmount;
  final double estimatedPurchasePatronage;
  final double? actualPurchasePatronage;

  const MemberContribution({
    required this.id,
    required this.farmerId,
    required this.year,
    required this.totalSalesAmount,
    required this.palaySalesKg,
    required this.palaySalesAmount,
    required this.peanutSalesKg,
    required this.peanutSalesAmount,
    this.otherCropsQtyKg = 0,
    this.otherCropsAmount = 0,
    required this.estimatedBalikTangkilik,
    required this.estimatedInterestOnCapital,
    this.actualBalikTangkilik,
    this.actualInterestOnCapital,
    this.actualPayoutDate,
    required this.status,
    this.reinvestedAmount = 0,
    this.programPurchasesAmount = 0,
    this.estimatedPurchasePatronage = 0,
    this.actualPurchasePatronage,
  });

  bool get isPaid => status == 'paid';

  /// Offer to Cooperative (sales) source only.
  double get estimatedOfferToCoopTotal =>
      estimatedBalikTangkilik + estimatedInterestOnCapital;
  double get estimatedProductSalesTotal => estimatedPurchasePatronage;

  /// Both patronage sources combined.
  double get estimatedGrandTotal =>
      estimatedOfferToCoopTotal + estimatedProductSalesTotal;

  double get actualOfferToCoopTotal =>
      (actualBalikTangkilik ?? 0) + (actualInterestOnCapital ?? 0);
  double get actualProductSalesTotal => actualPurchasePatronage ?? 0;

  double get actualGrandTotal =>
      actualOfferToCoopTotal + actualProductSalesTotal;

  // Aliases kept for existing callers (e.g. farmer_details_screen.dart) —
  // now grand totals across both sources, matching the "total = everything"
  // convention MemberDistributionRow already uses.
  double get estimatedTotal => estimatedGrandTotal;
  double get actualTotal => actualGrandTotal;

  /// How much of the finalized payout is still eligible to be reinvested.
  /// Only meaningful once [isPaid] — zero otherwise.
  double get availableToReinvest =>
      (actualGrandTotal - reinvestedAmount).clamp(0, double.infinity);

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
      otherCropsQtyKg: (map['other_crops_qty_kg'] as num? ?? 0).toDouble(),
      otherCropsAmount: (map['other_crops_amount'] as num? ?? 0).toDouble(),
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
      reinvestedAmount: (map['reinvested_amount'] as num? ?? 0).toDouble(),
      programPurchasesAmount:
          (map['program_purchases_amount'] as num? ?? 0).toDouble(),
      estimatedPurchasePatronage:
          (map['estimated_purchase_patronage'] as num? ?? 0).toDouble(),
      actualPurchasePatronage: map['actual_purchase_patronage'] != null
          ? (map['actual_purchase_patronage'] as num).toDouble()
          : null,
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

  /// Option B's parallel Product Sales Program settings — never combined
  /// with totalCoopSales/distributableSurplus above, which stay scoped to
  /// Offer to Cooperative (farmer sells to the coop) only.
  final double totalProgramSales;
  final double distributableProgramSurplus;

  const CoopAnnualTotal({
    required this.year,
    required this.totalCoopSales,
    required this.distributableSurplus,
    required this.interestRatePercent,
    this.afsFinalized = false,
    this.totalProgramSales = 0,
    this.distributableProgramSurplus = 0,
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
      totalProgramSales: (map['total_program_sales'] as num? ?? 0).toDouble(),
      distributableProgramSurplus:
          (map['distributable_program_surplus'] as num? ?? 0).toDouble(),
    );
  }
}


