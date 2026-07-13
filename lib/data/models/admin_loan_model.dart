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

  const LoanDashboardStats({
    required this.activeLoansCount,
    required this.overdueLoansCount,
    required this.paidThisMonthCount,
    required this.totalOutstanding,
    required this.totalExpectedThisCycle,
    required this.farmersOutstandingCount,
  });

  factory LoanDashboardStats.empty() => const LoanDashboardStats(
        activeLoansCount: 0,
        overdueLoansCount: 0,
        paidThisMonthCount: 0,
        totalOutstanding: 0,
        totalExpectedThisCycle: 0,
        farmersOutstandingCount: 0,
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
  });

  double get remainingBalance =>
      (totalValue - amountPaid).clamp(0, double.infinity);

  double get repaidPercent =>
      totalValue > 0 ? (amountPaid / totalValue).clamp(0.0, 1.0) : 0.0;

  bool get isOverdue => status == 'overdue';
  bool get isActive => status == 'active';
  bool get isPaid => status == 'paid';

  factory AdminLoanSummary.fromRow(
    Map<String, dynamic> row, {
    required String farmerName,
    required String memberId,
    required List<String> itemNames,
  }) {
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
      };
}

class FarmerPickerResult {
  final String id;
  final String fullName;
  final String memberId;

  const FarmerPickerResult({
    required this.id,
    required this.fullName,
    required this.memberId,
  });

  factory FarmerPickerResult.fromMap(Map<String, dynamic> map) {
    return FarmerPickerResult(
      id: map['id'] as String,
      fullName: map['fullName'] as String,
      memberId: map['memberId'] as String,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'fullName': fullName,
        'memberId': memberId,
      };
}

class FarmerLoanStanding {
  final double outstandingBalance;
  final bool hasOverdueLoan;

  const FarmerLoanStanding({
    required this.outstandingBalance,
    required this.hasOverdueLoan,
  });
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

class IssuedLoanResult {
  final String loanId;
  final String referenceNo;

  const IssuedLoanResult({
    required this.loanId,
    required this.referenceNo,
  });
}