import 'dart:math' as math;

/// Runs an "id is in this list" query in slices.
///
/// The ids travel in the request URL, so one query with hundreds of ids is refused by the
/// server (found by the volume test: 1,500 listings sent a 45 KB address and the Marketplace
/// failed to load). Each slice stays well under the limit; the rows of all slices are joined
/// in order. A list that already fits is sent as one request, exactly as before.
Future<List<Map<String, dynamic>>> chunkedIn(
  List<String> ids,
  Future<List<Map<String, dynamic>>> Function(List<String> slice) run, {
  int size = 80,
}) async {
  if (ids.length <= size) return run(ids);
  final slices = <List<String>>[
    for (var i = 0; i < ids.length; i += size)
      ids.sublist(i, math.min(i + size, ids.length)),
  ];
  final parts = await Future.wait(slices.map(run));
  return [for (final p in parts) ...p];
}
