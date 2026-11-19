import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads EVERY row of a query, page after page.
///
/// The database answers a plain select with at most 1,000 rows and says nothing about the rest.
/// The volume test (4,000+ orders) showed the Manager's Order Management stopping at the newest
/// 1,000: the chips read "All (1000)" and the oldest, longest-waiting pending orders could not be
/// seen or approved. Pass a function that builds the query with a stable order and the requested
/// range, for example:
///
///     fetchAllRows((from, to) => query.order('created_at', ascending: false).order('id').range(from, to));
///
/// Pages are requested a few at a time (not one after the other) so a long list does not take
/// several round trips in a row. The result is in page order.
Future<List<Map<String, dynamic>>> fetchAllRows(
  PostgrestTransformBuilder<PostgrestList> Function(int from, int to) page, {
  int pageSize = 1000,
  int maxRows = 100000,
  int parallel = 3,
}) async {
  final out = <Map<String, dynamic>>[];
  for (var start = 0; start < maxRows; start += pageSize * parallel) {
    final batch = await Future.wait([
      for (var k = 0; k < parallel; k++)
        page(start + k * pageSize, start + (k + 1) * pageSize - 1),
    ]);
    var finished = false;
    for (final rows in batch) {
      out.addAll(rows);
      if (rows.length < pageSize) {
        finished = true;
        break;
      }
    }
    if (finished) break;
  }
  return out;
}
