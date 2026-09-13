import 'package:supabase_flutter/supabase_flutter.dart';

/// A farmer's Palay/Peanut sales-to-SP3 totals for one year. Ginger is
/// structurally excluded — member_sales_transactions.crop_type has a
/// DB-level CHECK allowing only 'palay'/'peanut', so no filtering is
/// needed here to honor that business rule.
class MemberSalesTotals {
  double palayQtyKg = 0;
  double palayAmount = 0;
  double peanutQtyKg = 0;
  double peanutAmount = 0;

  double get totalAmount => palayAmount + peanutAmount;
}

/// Aggregates member_sales_transactions by farmer for a given year.
/// Extracted here after the second genuine need for this exact
/// computation — AdminReportsRepository's Member Contribution Report and
/// BalikTangkilikRepository's distribution preview both need farmers'
/// annual sales totals, and must agree on how they're computed.
Future<Map<String, MemberSalesTotals>> fetchMemberSalesTotals(
  SupabaseClient client,
  int year,
) async {
  final rows = await client
      .from('member_sales_transactions')
      .select('farmer_id, crop_type, quantity_kg, amount')
      .gte('sale_date', '$year-01-01')
      .lt('sale_date', '${year + 1}-01-01');

  final totals = <String, MemberSalesTotals>{};
  for (final row in rows) {
    final farmerId = row['farmer_id'] as String;
    final cropType = row['crop_type'] as String? ?? 'palay';
    final qty = (row['quantity_kg'] as num).toDouble();
    final amount = (row['amount'] as num).toDouble();

    final entry = totals.putIfAbsent(farmerId, () => MemberSalesTotals());
    if (cropType == 'palay') {
      entry.palayQtyKg += qty;
      entry.palayAmount += amount;
    } else {
      entry.peanutQtyKg += qty;
      entry.peanutAmount += amount;
    }
  }
  return totals;
}

/// A farmer's percent share of total cooperative sales for a year.
/// Extracted here for the same reason fetchMemberSalesTotals() was —
/// AdminReportsRepository's Member Contribution Report and
/// ContributionRepository's farmer-facing equivalent both compute this,
/// and must agree on the formula. Guards against a zero/negative
/// coopTotalSales denominator (e.g. no year settings saved yet) rather
/// than producing NaN or a divide-by-zero.
double computeMemberSharePercent({
  required double memberSales,
  required double coopTotalSales,
}) {
  if (coopTotalSales <= 0) return 0;
  return (memberSales / coopTotalSales) * 100;
}