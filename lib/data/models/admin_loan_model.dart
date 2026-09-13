import 'loan_model.dart';

class AllTimeLoanSummary {
  final int totalLoanCount;
  final double totalIssued;
  final double totalCollected;
  final double totalOutstanding;
  final double repaymentRatePercent;
  final bool isHealthy;

  const AllTimeLoanSummary({
    required this.totalLoanCount,
    required this.totalIssued,
    required this.totalCollected,
    required this.totalOutstanding,
    required this.repaymentRatePercent,
    required this.isHealthy,
  });

  factory AllTimeLoanSummary.empty() => const AllTimeLoanSummary(
        totalLoanCount: 0,
        totalIssued: 0,
        totalCollected: 0,
        totalOutstanding: 0,
        repaymentRatePercent: 0,
        isHealthy: true,
      );
}

class LoanDashboardStats {
  final int activeLoansCount;
  final int overdueLoansCount;
  final int paidThisMonthCount;
  final double totalOutstanding;
  final double totalExpectedThisCycle;
  final int farmersOutstandingCount;
  final double totalOverdueAmount;

  const LoanDashboardStats({
    required this.activeLoansCount,
    required this.overdueLoansCount,
    required this.paidThisMonthCount,
    required this.totalOutstanding,
    required this.totalExpectedThisCycle,
    required this.farmersOutstandingCount,
    required this.totalOverdueAmount,
  });

  factory LoanDashboardStats.empty() => const LoanDashboardStats(
        activeLoansCount: 0,
        overdueLoansCount: 0,
        paidThisMonthCount: 0,
        totalOutstanding: 0,
        totalExpectedThisCycle: 0,
        farmersOutstandingCount: 0,
        totalOverdueAmount: 0,
      );
}

class AdminLoanSummary {
  final String id;
  final String farmerId;
  final String farmerName;
  final String memberId;
  final String referenceNo;
  final DateTime issuedDate;
  final double totalValue;
  final double amountPaid;
  final String status;
  final double monthlyPayment;
  final List<String> itemNames;
  final String? notes;
  final DateTime? nextPaymentDate;
  // Set only when this loan came from converting a failed program
  // distribution (Phase 8 / Issue 3's Loan/ROI workflow) — null for every
  // ordinary admin-issued loan.
  final String? sourceProgramName;

  const AdminLoanSummary({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    required this.memberId,
    required this.referenceNo,
    required this.issuedDate,
    required this.totalValue,
    required this.amountPaid,
    required this.status,
    required this.monthlyPayment,
    required this.itemNames,
    this.notes,
    this.nextPaymentDate,
    this.sourceProgramName,
  });

  double get remainingBalance =>
      (totalValue - amountPaid).clamp(0, double.infinity);

  double get repaidPercent =>
      totalValue > 0 ? (amountPaid / totalValue).clamp(0.0, 1.0) : 0.0;

  bool get isOverdue => status == 'overdue';
  bool get isActive => status == 'active';
  bool get isPaid => status == 'paid';
  bool get isFromProgramDistribution => sourceProgramName != null;

  factory AdminLoanSummary.fromRow(
    Map<String, dynamic> row, {
    required String farmerName,
    required String memberId,
    required List<String> itemNames,
  }) {
    final program = row['cooperative_programs'] as Map<String, dynamic>?;
    return AdminLoanSummary(
      id: row['id'] as String,
      farmerId: row['farmer_id'] as String,
      farmerName: farmerName,
      memberId: memberId,
      referenceNo: row['reference_no'] as String,
      issuedDate: DateTime.parse(row['issued_date'] as String),
      totalValue: (row['total_value'] as num).toDouble(),
      amountPaid: (row['amount_paid'] as num? ?? 0).toDouble(),
      status: row['status'] as String? ?? 'active',
      monthlyPayment: (row['monthly_payment'] as num? ?? 0).toDouble(),
      itemNames: itemNames,
      notes: row['notes'] as String?,
      nextPaymentDate: row['next_payment_date'] != null
          ? DateTime.tryParse(row['next_payment_date'] as String)
          : null,
      sourceProgramName: program?['program_name'] as String?,
    );
  }

  factory AdminLoanSummary.fromCacheMap(Map<String, dynamic> map) {
    return AdminLoanSummary(
      id: map['id'] as String,
      farmerId: map['farmerId'] as String,
      farmerName: map['farmerName'] as String,
      memberId: map['memberId'] as String,
      referenceNo: map['referenceNo'] as String,
      issuedDate: DateTime.parse(map['issuedDate'] as String),
      totalValue: (map['totalValue'] as num).toDouble(),
      amountPaid: (map['amountPaid'] as num? ?? 0).toDouble(),
      status: map['status'] as String? ?? 'active',
      monthlyPayment: (map['monthlyPayment'] as num? ?? 0).toDouble(),
      itemNames: List<String>.from(map['itemNames'] as List? ?? const []),
      notes: map['notes'] as String?,
      nextPaymentDate: map['nextPaymentDate'] != null
          ? DateTime.tryParse(map['nextPaymentDate'] as String)
          : null,
      sourceProgramName: map['sourceProgramName'] as String?,
    );
  }

  Map<String, dynamic> toCacheMap() => {
        'id': id,
        'farmerId': farmerId,
        'farmerName': farmerName,
        'memberId': memberId,
        'referenceNo': referenceNo,
        'issuedDate': issuedDate.toIso8601String(),
        'totalValue': totalValue,
        'amountPaid': amountPaid,
        'status': status,
        'monthlyPayment': monthlyPayment,
        'itemNames': itemNames,
        'notes': notes,
        'nextPaymentDate': nextPaymentDate?.toIso8601String(),
        'sourceProgramName': sourceProgramName,
      };
}

class FarmerPickerResult {
  final String id;
  final String fullName;
  final String memberId;
  final String? profilePhotoUrl;

  const FarmerPickerResult({
    required this.id,
    required this.fullName,
    required this.memberId,
    this.profilePhotoUrl,
  });

  factory FarmerPickerResult.fromMap(Map<String, dynamic> map) {
    return FarmerPickerResult(
      id: map['id'] as String,
      fullName: map['fullName'] as String,
      memberId: map['memberId'] as String,
      profilePhotoUrl: map['profilePhotoUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'fullName': fullName,
        'memberId': memberId,
        'profilePhotoUrl': profilePhotoUrl,
      };
}

class FarmerLoanStanding {
  final double outstandingBalance;
  final bool hasOverdueLoan;

  /// Farmer's current capital contribution total (member_capital_shares
  /// .total_contribution) and the policy minimum required to borrow.
  /// [meetsCapitalEligibility] is the UI gate; issue_loan() enforces the
  /// same rule server-side.
  final double capitalContribution;
  final double minimumCapitalRequired;

  const FarmerLoanStanding({
    required this.outstandingBalance,
    required this.hasOverdueLoan,
    this.capitalContribution = 0,
    this.minimumCapitalRequired = 0,
  });

  bool get meetsCapitalEligibility =>
      capitalContribution >= minimumCapitalRequired;

  double get capitalShortfall =>
      (minimumCapitalRequired - capitalContribution)
          .clamp(0, double.infinity)
          .toDouble();
}

class AdminLoanDetail {
  final LoanModel loan;
  final String farmerName;
  final String memberId;
  final String? farmerPhotoUrl;

  const AdminLoanDetail({
    required this.loan,
    required this.farmerName,
    required this.memberId,
    this.farmerPhotoUrl,
  });
}

class LoanCatalogItem {
  final String loanItemId;
  final String inventoryItemId;
  final String itemName;
  final String category;
  final String unit;
  final double quantityOnHand;
  final double unitPrice;
  final bool isLoanEligible;
  final String? notes;

  const LoanCatalogItem({
    required this.loanItemId,
    required this.inventoryItemId,
    required this.itemName,
    required this.category,
    required this.unit,
    required this.quantityOnHand,
    required this.unitPrice,
    this.isLoanEligible = true,
    this.notes,
  });

  factory LoanCatalogItem.fromMap(Map<String, dynamic> map) {
    final inv = map['cooperative_inventory'] as Map<String, dynamic>;
    return LoanCatalogItem(
      loanItemId: map['id'] as String,
      inventoryItemId: inv['id'] as String,
      itemName: inv['item_name'] as String,
      category: inv['category'] as String,
      unit: inv['unit'] as String,
      quantityOnHand: (inv['quantity_on_hand'] as num).toDouble(),
      unitPrice: (map['unit_price'] as num).toDouble(),
      isLoanEligible: map['is_loan_eligible'] as bool? ?? true,
      notes: map['notes'] as String?,
    );
  }
}

class IssuedLoanResult {
  final String loanId;
  final String referenceNo;

  const IssuedLoanResult({
    required this.loanId,
    required this.referenceNo,
  });
}

class LoanPaymentResult {
  final bool isFullyPaid;
  final double runningBalance;

  const LoanPaymentResult({
    required this.isFullyPaid,
    required this.runningBalance,
  });
}