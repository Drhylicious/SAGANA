/// Where one month's contribution stands. A month is in exactly one of these:
/// Overdue wins over Unpaid / Partial once the due date has passed, and a Waived
/// month owes nothing.
enum MonthlyContributionStatus { unpaid, partial, paid, overdue, waived }

MonthlyContributionStatus monthlyStatusFrom(String? s) {
  switch (s) {
    case 'partial':
      return MonthlyContributionStatus.partial;
    case 'paid':
      return MonthlyContributionStatus.paid;
    case 'overdue':
      return MonthlyContributionStatus.overdue;
    case 'waived':
      return MonthlyContributionStatus.waived;
    default:
      return MonthlyContributionStatus.unpaid;
  }
}

/// One Farmer's monthly contribution for one month
/// (member_monthly_contribution_status): what is due, what was paid (from the
/// Capital Contribution ledger), what is left, and the status.
class MonthlyContribution {
  final String farmerId;

  /// The first day of the month this contribution is for.
  final DateTime month;
  final double amountDue;
  final DateTime dueDate;
  final double paidAmount;

  /// What is still owed (zero when paid or waived).
  final double balance;
  final MonthlyContributionStatus status;
  final String? waiveReason;
  final DateTime? waivedAt;

  const MonthlyContribution({
    required this.farmerId,
    required this.month,
    required this.amountDue,
    required this.dueDate,
    required this.paidAmount,
    required this.balance,
    required this.status,
    this.waiveReason,
    this.waivedAt,
  });

  bool get isWaived => status == MonthlyContributionStatus.waived;

  /// A payment can still be recorded.
  bool get canRecordPayment => !isWaived && balance > 0;

  factory MonthlyContribution.fromMap(Map<String, dynamic> m) {
    double n(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return MonthlyContribution(
      farmerId: m['farmer_id'] as String,
      month: DateTime.parse(m['contribution_month'] as String),
      amountDue: n(m['amount_due']),
      dueDate: DateTime.parse(m['due_date'] as String),
      paidAmount: n(m['paid_amount']),
      balance: n(m['balance']),
      status: monthlyStatusFrom(m['status'] as String?),
      waiveReason: m['waive_reason'] as String?,
      waivedAt: m['waived_at'] == null
          ? null
          : DateTime.parse(m['waived_at'] as String).toLocal(),
    );
  }
}

/// The totals of a list of months. A waived month owes nothing, so it is left out
/// of [totalDue]; due - paid = remaining always holds.
class MonthlyContributionSummary {
  final double totalDue;
  final double totalPaid;
  final double remaining;
  final int monthsPaid;
  final int monthsPartial;
  final int monthsUnpaid;
  final int monthsOverdue;
  final int monthsWaived;

  const MonthlyContributionSummary({
    this.totalDue = 0,
    this.totalPaid = 0,
    this.remaining = 0,
    this.monthsPaid = 0,
    this.monthsPartial = 0,
    this.monthsUnpaid = 0,
    this.monthsOverdue = 0,
    this.monthsWaived = 0,
  });

  int get monthCount =>
      monthsPaid + monthsPartial + monthsUnpaid + monthsOverdue + monthsWaived;

  factory MonthlyContributionSummary.of(Iterable<MonthlyContribution> months) {
    double due = 0, paid = 0, left = 0;
    var p = 0, pt = 0, u = 0, o = 0, w = 0;
    for (final m in months) {
      paid += m.paidAmount;
      left += m.balance;
      if (!m.isWaived) due += m.amountDue;
      switch (m.status) {
        case MonthlyContributionStatus.paid:
          p++;
        case MonthlyContributionStatus.partial:
          pt++;
        case MonthlyContributionStatus.unpaid:
          u++;
        case MonthlyContributionStatus.overdue:
          o++;
        case MonthlyContributionStatus.waived:
          w++;
      }
    }
    return MonthlyContributionSummary(
      totalDue: due,
      totalPaid: paid,
      remaining: left,
      monthsPaid: p,
      monthsPartial: pt,
      monthsUnpaid: u,
      monthsOverdue: o,
      monthsWaived: w,
    );
  }
}
