/// Shared BOD (Board of Directors) meeting schedule logic.
///
/// SP3's monthly loan payment cycle is anchored to the first Saturday of
/// each month. Previously duplicated as private copies in
/// AdminLoanRepository, LoanDashboardScreen, and IssueNewLoanScreen —
/// consolidated here so the rule lives in one place. If SP3's actual BOD
/// schedule differs from "1st Saturday" once confirmed on-site, this is
/// the only file that needs to change.
class BodSchedule {
  BodSchedule._();

  /// The next BOD Saturday, inclusive of today if today IS the first
  /// Saturday of the month. Use for "what's the next upcoming meeting"
  /// display purposes.
  static DateTime upcoming([DateTime? from]) {
    final reference = from ?? DateTime.now();
    var candidate = _firstSaturdayOf(reference.year, reference.month);
    if (candidate.isBefore(DateTime(reference.year, reference.month, reference.day))) {
      final nextMonth = reference.month == 12 ? 1 : reference.month + 1;
      final nextYear = reference.month == 12 ? reference.year + 1 : reference.year;
      candidate = _firstSaturdayOf(nextYear, nextMonth);
    }
    return candidate;
  }

  /// The next BOD Saturday strictly AFTER [from] — even if [from] itself
  /// is a BOD Saturday, rolls to next month. Use when scheduling the next
  /// payment cycle following an event that happened ON [from].
  static DateTime after(DateTime from) {
    var candidate = _firstSaturdayOf(from.year, from.month);
    if (!candidate.isAfter(DateTime(from.year, from.month, from.day))) {
      final nextMonth = from.month == 12 ? 1 : from.month + 1;
      final nextYear = from.month == 12 ? from.year + 1 : from.year;
      candidate = _firstSaturdayOf(nextYear, nextMonth);
    }
    return candidate;
  }

  static DateTime _firstSaturdayOf(int year, int month) {
    var d = DateTime(year, month, 1);
    while (d.weekday != DateTime.saturday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}