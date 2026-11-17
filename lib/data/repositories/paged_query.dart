import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads EVERY row a query matches, a page at a time.
///
/// The database returns at most 1,000 rows per request, and a plain `await query`
/// stops there without saying so. A report or an export built from such a query
/// would quietly leave records out once a period holds more than 1,000. This keeps
/// asking for the next page until a short page comes back.
///
/// Pages need a stable order, so the row id is added as the last sort key (after
/// whatever order the query already has). The query builder is immutable, so the
/// same [query] can be asked for page after page.
Future<List<Map<String, dynamic>>> fetchAllPages(
  PostgrestTransformBuilder<PostgrestList> query, {
  int pageSize = 1000,
}) async {
  final all = <Map<String, dynamic>>[];
  final ordered = query.order('id', ascending: true);
  var from = 0;
  while (true) {
    final page = await ordered.range(from, from + pageSize - 1);
    all.addAll(page);
    if (page.length < pageSize) break;
    from += pageSize;
  }
  return all;
}
