/// Whether a farmer may borrow, and how much, from the database's
/// get_loan_capital_standing(). The rules live there (and are enforced there):
///  * a loan item can be worth no more than the Capital Share ([maxItemValue]);
///  * a Capital Share of zero allows no loan;
///  * an overdue loan that is not paid in full ([overdueBalance]) allows no new
///    loan; a partial payment does not lift it.
class LoanCapitalStanding {
  final double capitalShare;
  final double maxItemValue;

  /// What is still unpaid on the farmer's overdue loans (0 when none).
  final double overdueBalance;
  final int overdueLoans;

  const LoanCapitalStanding({
    required this.capitalShare,
    required this.maxItemValue,
    this.overdueBalance = 0,
    this.overdueLoans = 0,
  });

  /// Nothing can be borrowed while the Capital Share is zero.
  bool get isZero => maxItemValue <= 0;

  /// An overdue loan is not paid in full.
  bool get hasOverdue => overdueBalance > 0;

  /// A new loan cannot be issued or requested.
  bool get isBlocked => isZero || hasOverdue;

  factory LoanCapitalStanding.fromMap(Map<String, dynamic> map) =>
      LoanCapitalStanding(
        capitalShare: (map['capital_share'] as num? ?? 0).toDouble(),
        maxItemValue: (map['max_item_value'] as num? ?? 0).toDouble(),
        overdueBalance: (map['overdue_balance'] as num? ?? 0).toDouble(),
        overdueLoans: (map['overdue_loans'] as num? ?? 0).toInt(),
      );
}
