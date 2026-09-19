import 'package:supabase_flutter/supabase_flutter.dart';

/// A farmer's Offer-to-Cooperative sales-to-SP3 totals for one year, for
/// ANY crop (as of Phase 9 — "Full financial parity"; previously
/// Palay/Peanut only, per member_sales_transactions.crop_type's old
/// DB-level CHECK). Palay and Peanut keep their own dedicated fields
/// since Sales Report and Member Patronage Report both have existing
/// breakdown UI specifically for those two crops; every other crop rolls
/// into [otherCropsAmount]/[otherCropsQtyKg] so [totalAmount] — the
/// figure Balik-Tangkilik's patronage-share math actually uses — reflects
/// every crop a farmer sold to the cooperative, not just two of them.
/// Ginger is excluded structurally upstream (offer-creation time, via
/// crop_master.is_cooperative_eligible), not by any filtering here.
class MemberSalesTotals {
  double palayQtyKg = 0;
  double palayAmount = 0;
  double peanutQtyKg = 0;
  double peanutAmount = 0;
  double otherCropsQtyKg = 0;
  double otherCropsAmount = 0;

  double get totalAmount => palayAmount + peanutAmount + otherCropsAmount;
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
    } else if (cropType == 'peanut') {
      entry.peanutQtyKg += qty;
      entry.peanutAmount += amount;
    } else {
      entry.otherCropsQtyKg += qty;
      entry.otherCropsAmount += amount;
    }
  }
  return totals;
}

/// A farmer's total confirmed Product Sales Program purchases for one
/// year, across EVERY 'sales'-purpose cooperative program — see
/// program_product_purchases in supabase_schema_program_product_sales.sql.
/// This is the Option B "second source" (farmer BUYS cooperative
/// products), kept structurally separate from fetchMemberSalesTotals()
/// above (farmer SELLS to the cooperative) — never merged into the same
/// total, so Member Patronage Report and Balik-Tangkilik Management can
/// always show a BOD member exactly which pool a given peso came from.
///
/// Deliberately amount-only, never a summed physical quantity — different
/// sales programs sell in different units (bags, pieces, bottles), so a
/// cross-program quantity total would be meaningless the way Palay/Peanut
/// kg is for Offer to Cooperative. Only `status = 'paid'` purchases count;
/// pending/cancelled requests never represent real money moving.
///
/// Fully dynamic across any current or future sales program: this reads
/// program_product_purchases directly, with no program_id/product_id
/// filtering, so a new Product Sales program an admin creates later is
/// picked up automatically the moment a farmer's purchase there is
/// confirmed — no code change needed per program or per product.
Future<Map<String, double>> fetchMemberProgramPurchaseTotals(
  SupabaseClient client,
  int year,
) async {
  final rows = await client
      .from('program_product_purchases')
      .select('farmer_id, total_amount')
      .eq('status', 'paid')
      .gte('confirmed_at', '$year-01-01')
      .lt('confirmed_at', '${year + 1}-01-01');

  final totals = <String, double>{};
  for (final row in rows) {
    final farmerId = row['farmer_id'] as String;
    final amount = (row['total_amount'] as num).toDouble();
    totals[farmerId] = (totals[farmerId] ?? 0) + amount;
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