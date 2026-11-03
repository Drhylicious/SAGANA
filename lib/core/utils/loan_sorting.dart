import '../../data/models/loan_model.dart';

/// One payment together with the loan it was made on.
typedef LoanPaymentEntry = ({LoanModel loan, LoanPaymentModel payment});

/// The Farmer's loans, most recent first (by the date issued). Two loans issued on
/// the same day are ordered by their reference number, highest first (references
/// are numbered in the order loans are created), and finally by id, so the order is
/// always the same wherever it is shown: the Input Loans landing page, and the
/// Loan History screen.
List<LoanModel> loansNewestFirst(Iterable<LoanModel> loans) {
  final sorted = [...loans];
  sorted.sort((a, b) {
    var c = b.issuedDate.compareTo(a.issuedDate);
    if (c != 0) return c;
    c = b.referenceNo.compareTo(a.referenceNo);
    if (c != 0) return c;
    return b.id.compareTo(a.id);
  });
  return sorted;
}

/// Every payment on every loan, most recent first (by the payment date). Payments
/// made on the same day are ordered by the balance they left, lowest first (a later
/// payment always leaves less owing), then by loan reference and id, so the order is
/// the same on the landing page and on the Payment History screen.
List<LoanPaymentEntry> paymentsNewestFirst(Iterable<LoanModel> loans) {
  final rows = <LoanPaymentEntry>[
    for (final l in loans)
      for (final p in l.payments) (loan: l, payment: p),
  ];
  rows.sort((a, b) {
    var c = b.payment.paymentDate.compareTo(a.payment.paymentDate);
    if (c != 0) return c;
    c = a.payment.runningBalance.compareTo(b.payment.runningBalance);
    if (c != 0) return c;
    c = b.loan.referenceNo.compareTo(a.loan.referenceNo);
    if (c != 0) return c;
    return b.payment.id.compareTo(a.payment.id);
  });
  return rows;
}

/// The loans whose Loan ID (reference number) contains [query]. Case, spaces and
/// dashes are ignored, and any part of the ID matches ("20261030", "a002",
/// "LRN-2026"), so an ID typed or pasted in any form is found. An empty query
/// matches every loan. The order of [loans] is kept.
List<LoanModel> loansMatchingId(Iterable<LoanModel> loans, String query) {
  String norm(String v) => v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final q = norm(query);
  if (q.isEmpty) return [...loans];
  return loans.where((l) => norm(l.referenceNo).contains(q)).toList();
}
