import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/quantity_utils.dart';
import 'paged_query.dart';

/// A farmer's Offer-to-Cooperative sales-to-SP3 totals for one year, for
/// ANY crop (as of Phase 9 — "Full financial parity"; previously
/// Palay/Peanut only, per member_sales_transactions.crop_type's old
/// DB-level CHECK). Palay and Peanut keep their own dedicated fields
/// since Sales Report and Member Contribution Report both have existing
/// breakdown UI specifically for those two crops; every other crop rolls
/// into [otherCropsAmount]/[otherCropsQtyKg] so [totalAmount] — the
/// figure Member Contribution Report's offers total uses — reflects
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
/// Benefits Tracking both need farmers'
/// annual sales totals, and must agree on how they're computed.
Future<Map<String, MemberSalesTotals>> fetchMemberSalesTotals(
  SupabaseClient client,
  int year,
) async {
  final rows = await fetchAllPages(
    client
        .from('member_sales_transactions')
        .select('farmer_id, crop_type, quantity_kg, unit, amount')
        .gte('sale_date', '$year-01-01')
        .lt('sale_date', '${year + 1}-01-01'),
  );

  final totals = <String, MemberSalesTotals>{};
  for (final row in rows) {
    final farmerId = row['farmer_id'] as String;
    final cropType = row['crop_type'] as String? ?? 'palay';
    // The quantities are kg figures: a sale in another unit adds its AMOUNT
    // (pesos are pesos) but not its quantity.
    final qty = isKg(row['unit'] as String?)
        ? (row['quantity_kg'] as num).toDouble()
        : 0.0;
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
/// total, so Member Contribution Report and Benefits Tracking can
/// always show a BOD member exactly which pool a given peso came from.
///
/// Deliberately amount-only, never a summed physical quantity — different
/// sales programs sell in different units (bags, pieces, bottles), so a
/// cross-program quantity total would be meaningless the way Palay/Peanut
/// kg is for Offer to Cooperative. Only `status = 'completed'` purchases (handed over, cash recorded, confirmed) count;
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
  // total_amount is the NET amount charged (after any member discount).
  //
  // Only purchases made at the MEMBER price count here. A farmer who is not
  // enrolled in the Product Sales program pays the regular price and earns no
  // benefit, so that purchase is never a contribution to the member's Capital Share. There is
  // no looser fallback: if the member-price data cannot be read, nothing is
  // counted rather than counting every buyer's purchase.
  final rows = await _completedPurchaseRows(
    client,
    year,
    'farmer_id, total_amount',
  );
  return _sumByFarmer(rows);
}

/// The completed Cooperative Product orders of [year], from Product Sales programs
/// only (program_purpose = 'sales'): an order in any other kind of program is
/// never a Cooperative Product purchase of the report. An order counts on the day
/// it was COMPLETED (completed_at) — the same day the Sales Report uses — not the
/// day the payment was recorded, so a purchase is in the same year in both
/// reports. Orders that predate completed_at keep counting on confirmed_at.
Future<List> _completedPurchaseRows(
  SupabaseClient client,
  int year,
  String columns,
) async {
  final from = DateTime(year).toUtc().toIso8601String();
  final to = DateTime(year + 1).toUtc().toIso8601String();
  try {
    var query = client
        .from('program_product_purchases')
        .select('$columns, cooperative_programs!inner(program_purpose)')
        .eq('status', 'completed')
        .eq('cooperative_programs.program_purpose', 'sales');
    query = query.eq('is_member_price', true);
    return await fetchAllPages(
      query.or(
        'and(completed_at.gte.$from,completed_at.lt.$to),'
        'and(completed_at.is.null,confirmed_at.gte.$from,confirmed_at.lt.$to)',
      ),
    );
  } on PostgrestException {
    // completed_at is not in this database yet: date by confirmed_at, as before.
    var query = client
        .from('program_product_purchases')
        .select('$columns, cooperative_programs!inner(program_purpose)')
        .eq('status', 'completed')
        .eq('cooperative_programs.program_purpose', 'sales');
    query = query.eq('is_member_price', true);
    return await fetchAllPages(
      query
          .gte('confirmed_at', '$year-01-01')
          .lt('confirmed_at', '${year + 1}-01-01'),
    );
  }
}

Map<String, double> _sumByFarmer(List rows) {

  final totals = <String, double>{};
  for (final row in rows) {
    final farmerId = row['farmer_id'] as String;
    final amount = (row['total_amount'] as num).toDouble();
    totals[farmerId] = (totals[farmerId] ?? 0) + amount;
  }
  return totals;
}

/// What a farmer's member-price purchases for a year were at the regular price,
/// how much of that was discounted, and what was actually paid — so a report
/// can show the three side by side and they reconcile (regular − discount = net).
class ProgramPurchaseBreakdown {
  double regular = 0;
  double discount = 0;
  double net = 0;
}

Future<Map<String, ProgramPurchaseBreakdown>> fetchMemberProgramPurchaseBreakdown(
  SupabaseClient client,
  int year,
) async {
  final out = <String, ProgramPurchaseBreakdown>{};
  try {
    final rows = await _completedPurchaseRows(
      client,
      year,
      'farmer_id, total_amount, discount_amount',
    );
    for (final row in rows) {
      final b = out.putIfAbsent(
        row['farmer_id'] as String,
        () => ProgramPurchaseBreakdown(),
      );
      final net = (row['total_amount'] as num).toDouble();
      final discount = (row['discount_amount'] as num?)?.toDouble() ?? 0;
      b.net += net;
      b.discount += discount;
      b.regular += net + discount;
    }
  } catch (_) {
    // Pricing columns not there yet: nothing to break down.
  }
  return out;
}

/// What a member's Capital Share looks like, worked out from the capital ledger
/// (capital_contribution_events) for one year.
class MemberCapitalYear {
  /// Monthly contributions (source member_payment) made in the year, net of any
  /// cancellations (a cancellation is a negative entry of the same source).
  double monthly = 0;

  /// Monthly payments of the year that were never tied to a month (recorded before
  /// payments carried one). In the Capital Share, in no month.
  double monthlyUnassigned = 0;

  /// The earlier discount credit (source purchase_discount). No longer made, but
  /// what it credited stays in the Capital Share and counts as a purchase credit.
  double discountCredited = 0;

  /// Cooperative Purchase credits of the year (source purchase_share): a
  /// percentage of each completed member-price order, and the net amounts they
  /// were worked out from.
  double purchaseShare = 0;
  double purchaseShareBase = 0;

  /// Offer to Cooperative credits of the year (source offer_share): a percentage
  /// of each completed offer's sale value, and the sale values they came from.
  double offerShare = 0;
  double offerShareBase = 0;

  /// The same credits split by the settings version they were made under:
  /// version -> [credited, base amount, discount earned (purchases only)].
  /// Keys are strings so the report can be cached as plain JSON.
  final Map<String, List<double>> purchaseByVersion = {};
  final Map<String, List<double>> offerByVersion = {};

  /// transaction id (a purchase or an offer sale) -> the settings version its
  /// credit was made under, so a list of purchases / offers can be split into
  /// newly credited and previous.
  final Map<String, int> creditVersions = {};

  /// Everything the ledger added to the Capital Share in the year (net of
  /// cancellations), whatever its source.
  double yearTotal = 0;

  /// Each Monthly Contribution record of the year (payments, Starting Capital,
  /// corrections, an older payout, and their cancellations), one map each:
  /// {date, source, amount, month, rev}. Plain maps so the report can be cached.
  final List<Map<String, dynamic>> records = [];

  /// The Capital Share at the start of the year (the ledger before it, never below zero).
  double balanceAtYearStart = 0;

  /// Starting Capital counted in the year: the capital the member already had,
  /// dated by the day they actually held it (effective_date), net of any
  /// cancellation. It is NOT a contribution of the year; it is shown beside them.
  double startingCapital = 0;

  /// Everything in the ledger up to the end of the year, never below zero. A
  /// Starting Capital counts from its own date, so a past-year entry is in that
  /// year's balance and in every later one.
  double balanceAtYearEnd = 0;
}

Future<Map<String, MemberCapitalYear>> fetchMemberCapitalYear(
  SupabaseClient client,
  int year,
) async {
  final out = <String, MemberCapitalYear>{};
  final start = DateTime(year);
  final end = DateTime(year + 1);
  try {
    // effective_date is the Starting Capital date. A database that does not have
    // it yet (the starting-capital-date script is not run) reads as before.
    // base_amount is the amount a percentage credit was worked out from (the
    // Capital Share rates script). Each older database reads with fewer columns.
    List rows = const [];
    const columnSets = [
      'farmer_id, amount, source, created_at, contribution_month, effective_date, base_amount, payment_date, reverses_event_id, rate_version, discount_amount, reference_id',
      'farmer_id, amount, source, created_at, contribution_month, effective_date, base_amount, payment_date, reverses_event_id',
      'farmer_id, amount, source, created_at, contribution_month, effective_date, base_amount',
      'farmer_id, amount, source, created_at, contribution_month, effective_date',
      'farmer_id, amount, source, created_at, contribution_month',
    ];
    for (var i = 0; i < columnSets.length; i++) {
      try {
        rows = await fetchAllPages(
          client.from('capital_contribution_events').select(columnSets[i]),
        );
        break;
      } on PostgrestException {
        if (i == columnSets.length - 1) rethrow;
      }
    }
    final sums = <String, double>{};
    final before = <String, double>{};
    for (final row in rows) {
      final id = row['farmer_id'] as String;
      final amount = (row['amount'] as num).toDouble();
      // The day an entry counts for: a Starting Capital's own date, else the day
      // it was recorded. (Filtered here, not in the query, because an entry
      // recorded this year can be dated in an earlier year.)
      final effective = row['effective_date'] as String?;
      final at = effective != null
          ? DateTime.parse(effective)
          : DateTime.parse(row['created_at'] as String).toLocal();
      if (!at.isBefore(end)) continue;
      final entry = out.putIfAbsent(id, () => MemberCapitalYear());
      sums[id] = (sums[id] ?? 0) + amount;
      if (at.isBefore(start)) {
        before[id] = (before[id] ?? 0) + amount;
      } else {
        entry.yearTotal += amount;
        final source = row['source'] as String?;
        if (const {
          'member_payment',
          'opening_balance',
          'manual_adjustment',
          'patronage_capital',
        }.contains(source)) {
          final paidOn = row['payment_date'] as String?;
          final day = (source == 'member_payment' && paidOn != null)
              ? DateTime.parse(paidOn)
              : at;
          entry.records.add({
            'date':
                '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
            'source': source,
            'amount': amount,
            'month': row['contribution_month'],
            'rev': row['reverses_event_id'] != null,
          });
        }
        if (source == 'member_payment') {
          entry.monthly += amount;
          if (row['contribution_month'] == null) {
            entry.monthlyUnassigned += amount;
          }
        }
        if (source == 'purchase_discount') entry.discountCredited += amount;
        final base = (row['base_amount'] as num?)?.toDouble() ?? 0;
        final ver = '${(row['rate_version'] as num?)?.toInt() ?? 1}';
        if ((source == 'purchase_share' || source == 'offer_share') &&
            row['reference_id'] is String) {
          entry.creditVersions[row['reference_id'] as String] =
              (row['rate_version'] as num?)?.toInt() ?? 1;
        }
        if (source == 'purchase_share') {
          entry.purchaseShare += amount;
          entry.purchaseShareBase += base;
          final slot = entry.purchaseByVersion.putIfAbsent(
            ver,
            () => [0, 0, 0],
          );
          slot[0] += amount;
          slot[1] += base;
          slot[2] += (row['discount_amount'] as num?)?.toDouble() ?? 0;
        }
        if (source == 'offer_share') {
          entry.offerShare += amount;
          entry.offerShareBase += base;
          final slot = entry.offerByVersion.putIfAbsent(ver, () => [0, 0, 0]);
          slot[0] += amount;
          slot[1] += base;
        }
        if (source == 'opening_balance') entry.startingCapital += amount;
      }
    }
    for (final e in out.entries) {
      final total = sums[e.key] ?? 0;
      e.value.balanceAtYearEnd = total < 0 ? 0 : total;
      final b = before[e.key] ?? 0;
      e.value.balanceAtYearStart = b < 0 ? 0 : b;
    }
  } catch (_) {
    // The ledger could not be read: no capital figures, nothing invented.
  }
  return out;
}

/// One member's monthly contributions for the months of a year, from the Contribution
/// section (member_monthly_contribution_status). Paid comes from the Capital
/// Contribution ledger, so the report and Farmer Details read the same records.
class MemberMonthlyYear {
  /// The year's months, one entry each: {month: 'yyyy-MM-dd', due, paid, status}.
  /// Plain maps so the report can be cached and rebuilt offline.
  final List<Map<String, dynamic>> months = [];
  double due = 0;
  double paid = 0;
  double balance = 0;
  int paidMonths = 0;
  int partial = 0;
  int unpaid = 0;
  int overdue = 0;
  int waived = 0;
}

Future<Map<String, MemberMonthlyYear>> fetchMemberMonthlyYear(
  SupabaseClient client,
  int year,
) async {
  final out = <String, MemberMonthlyYear>{};
  try {
    final rows = await fetchAllPages(
      client
          .from('member_monthly_contribution_status')
          .select(
            'farmer_id, contribution_month, amount_due, paid_amount, balance, status',
          )
          .gte('contribution_month', '$year-01-01')
          .lt('contribution_month', '${year + 1}-01-01'),
    );
    for (final row in rows) {
      final m = out.putIfAbsent(
        row['farmer_id'] as String,
        () => MemberMonthlyYear(),
      );
      final status = row['status'] as String?;
      m.months.add({
        'month': row['contribution_month'],
        'due': (row['amount_due'] as num?)?.toDouble() ?? 0,
        'paid': (row['paid_amount'] as num?)?.toDouble() ?? 0,
        'status': status,
      });
      m.paid += (row['paid_amount'] as num?)?.toDouble() ?? 0;
      m.balance += (row['balance'] as num?)?.toDouble() ?? 0;
      if (status != 'waived') {
        m.due += (row['amount_due'] as num?)?.toDouble() ?? 0;
      }
      switch (status) {
        case 'paid':
          m.paidMonths++;
        case 'partial':
          m.partial++;
        case 'overdue':
          m.overdue++;
        case 'waived':
          m.waived++;
        default:
          m.unpaid++;
      }
    }
  } catch (_) {
    // Not readable (or the SQL is not run yet): no monthly figures, nothing invented.
  }
  return out;
}
