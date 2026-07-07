/// Admin-side loan models.
///
/// These are intentionally separate from LoanModel / LoanItemModel /
/// LoanPaymentModel (see loan_model.dart) because the admin views need
/// denormalized farmer identity fields (name, member ID) that the farmer-side
/// model has no reason to carry. Item and payment shapes are unchanged and
/// should keep using the existing farmer-side models where a full loan
/// (with items + payments) is loaded — see AdminLoanDetail below.
library;

import 'loan_model.dart';

/// KPI numbers shown on the Loan Dashboard's summary grid and BOD banner.
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

/// A single loan card's worth of data for admin list/grid views
/// (Dashboard's Overdue/Active sections, Loan History registry).
class AdminLoanSummary {
  final String id;
  final String farmerId;
  final String farmerName;
  final String memberId;
  final String referenceNo;
  final DateTime issuedDate;
  final double totalValue;
  final double amountPaid;
  final String status; // active | overdue | paid
  final DateTime? nextPaymentDate;
  final double monthlyPayment;
  final List<String> itemNames;

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
    required this.nextPaymentDate,
    required this.monthlyPayment,
    required this.itemNames,
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
      referenceNo: row['reference_no'] as String? ?? '—',
      issuedDate: DateTime.parse(row['issued_date'] as String),
      totalValue: (row['total_value'] as num).toDouble(),
      amountPaid: (row['amount_paid'] as num? ?? 0).toDouble(),
      status: row['status'] as String? ?? 'active',
      nextPaymentDate: row['next_payment_date'] != null
          ? DateTime.tryParse(row['next_payment_date'] as String)
          : null,
      monthlyPayment: (row['monthly_payment'] as num? ?? 0).toDouble(),
      itemNames: itemNames,
    );
  }
}

/// Full loan detail for LoanDetailsScreen — reuses the existing farmer-side
/// LoanItemModel / LoanPaymentModel since their shape is already correct,
/// and simply adds the denormalized farmer identity fields on top.
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

// ─── Added for Issue New Loan ──────────────────────────────────────────────

/// Lightweight farmer entry for the Issue-Loan farmer picker.
/// Deliberately minimal (no photo, no crop info) — this is a selection list,
/// not a profile view — and small enough to cache entirely in Hive for
/// offline BOD-meeting use (the cooperative only has ~52 farmers).
class FarmerPickerResult {
  final String id;
  final String fullName;
  final String memberId;

  const FarmerPickerResult({
    required this.id,
    required this.fullName,
    required this.memberId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'fullName': fullName,
        'memberId': memberId,
      };

  factory FarmerPickerResult.fromMap(Map<dynamic, dynamic> map) {
    return FarmerPickerResult(
      id: map['id'] as String,
      fullName: map['fullName'] as String? ?? 'Unknown Farmer',
      memberId: map['memberId'] as String? ?? '—',
    );
  }
}

/// A selected farmer's current loan standing, shown as a warning banner
/// on the Issue-Loan form. Only fetchable while online — see
/// AdminLoanRepository.fetchFarmerLoanStanding().
class FarmerLoanStanding {
  final double outstandingBalance;
  final bool hasOverdueLoan;

  const FarmerLoanStanding({
    required this.outstandingBalance,
    required this.hasOverdueLoan,
  });
}

/// Result of a successful loan issuance — returned so the screen can show
/// the admin the real, server-assigned reference number immediately.
class IssuedLoanResult {
  final String loanId;
  final String referenceNo;

  const IssuedLoanResult({
    required this.loanId,
    required this.referenceNo,
  });
}