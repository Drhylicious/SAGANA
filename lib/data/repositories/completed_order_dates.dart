import 'package:supabase_flutter/supabase_flutter.dart';

/// The day a completed Marketplace order counts as a SALE.
///
/// An order is completed when the buyer (or a Farmer buying) confirms they
/// received it (`orders.received_at`). That, not the day the order was placed
/// (`orders.created_at`), is when the sale happened: an order placed on 30 Dec
/// and received on 2 Jan is a January sale. Orders completed before
/// `received_at` existed have none, and keep counting on their creation day.
///
/// Every screen that dates, filters or totals completed orders (Farmer Home and
/// Profile, Farmer Transaction History and Analytics, the Manager / Officer Sales
/// Report, Operational Reports and the Dashboard revenue) goes through these
/// helpers, so a sale is in the same period everywhere.
class CompletedOrderDates {
  CompletedOrderDates._();

  /// The date a row from `orders` counts on. [row] needs `created_at` and, when
  /// the column exists, `received_at`.
  static DateTime of(Map<String, dynamic> row) {
    final stamp = (row['received_at'] ?? row['created_at']) as String;
    return DateTime.parse(stamp).toLocal();
  }

  /// A PostgREST `or` filter selecting orders whose sale date is in
  /// [start, endExclusive) (either bound may be null), or null when both are null.
  /// Use it with `.or(...)` on a query that already has `.eq('status', 'completed')`.
  static String? window(DateTime? start, DateTime? endExclusive) {
    if (start == null && endExclusive == null) return null;
    String bounds(String column) => [
      if (start != null) '$column.gte.${start.toUtc().toIso8601String()}',
      if (endExclusive != null) '$column.lt.${endExclusive.toUtc().toIso8601String()}',
    ].join(',');
    return 'and(${bounds('received_at')}),'
        'and(received_at.is.null,${bounds('created_at')})';
  }

  /// Runs [run] with the received_at-aware query first. A database that does not
  /// have `orders.received_at` yet refuses it, and then [run] is called again
  /// with `withReceivedAt: false`, which must date by `created_at` only.
  static Future<T> withFallback<T>(
    Future<T> Function(bool withReceivedAt) run,
  ) async {
    try {
      return await run(true);
    } on PostgrestException {
      return await run(false);
    }
  }
}
