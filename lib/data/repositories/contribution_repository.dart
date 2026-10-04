import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/contribution_model.dart';
import '../models/admin_reports_model.dart';
import '../models/program_model.dart';
import 'farmer_lookup.dart';
import 'member_sales_aggregation.dart' as member_sales_agg;

class ContributionRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // ─── Current year contribution ────────────────────────────────────────────

  Future<MemberContribution?> fetchCurrentYearContribution() async {
    try {
      final year = DateTime.now().year;
      final row = await _client
          .from('member_contributions')
          .select()
          .eq('farmer_id', _userId)
          .eq('year', year)
          .maybeSingle();
      if (row == null) return null;
      return MemberContribution.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  // ─── Previous year contribution (for "Actual Payout" card) ───────────────

  Future<MemberContribution?> fetchPreviousYearContribution() async {
    try {
      final year = DateTime.now().year - 1;
      final row = await _client
          .from('member_contributions')
          .select()
          .eq('farmer_id', _userId)
          .eq('year', year)
          .maybeSingle();
      if (row == null) return null;
      return MemberContribution.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  // ─── Recent sales transactions ────────────────────────────────────────────

  Future<List<MemberSalesTransaction>> fetchRecentTransactions({
    int limit = 10,
  }) async {
    try {
      final rows = await _client
          .from('member_sales_transactions')
          .select()
          .eq('farmer_id', _userId)
          .order('sale_date', ascending: false)
          .limit(limit);
      return rows.map((r) => MemberSalesTransaction.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Recent Product Sales Program purchases ────────────────────────────────
  // Mirrors fetchRecentTransactions() above, but for the buying side (Option
  // B) — across every program, not scoped to one, so it lists everything
  // the farmer has confirmed buying from the cooperative this year and
  // beyond. Only 'paid' purchases count as real activity, same convention
  // as fetchMemberProgramPurchaseTotals().
  Future<List<ProgramPurchase>> fetchRecentProgramPurchases({
    int limit = 10,
  }) async {
    try {
      final rows = await _client
          .from('program_product_purchases')
          .select(
            'id, program_id, product_id, farmer_id, quantity, unit_price, '
            'total_amount, status, requested_at, confirmed_at, cancelled_at, cancel_reason, '
            'cooperative_programs(program_name), '
            'program_products(cooperative_inventory(item_name, unit))',
          )
          .eq('farmer_id', _userId)
          .eq('status', 'paid')
          .order('confirmed_at', ascending: false)
          .limit(limit);
      return rows.map((r) {
        final program = r['cooperative_programs'] as Map<String, dynamic>?;
        final product = r['program_products'] as Map<String, dynamic>?;
        final inv = product?['cooperative_inventory'] as Map<String, dynamic>?;
        return ProgramPurchase.fromMap({
          ...r,
          'program_name': program?['program_name'],
          'item_name': inv?['item_name'],
          'unit': inv?['unit'],
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Capital shares ───────────────────────────────────────────────────────

  Future<CapitalSharesModel?> fetchCapitalShares() async {
    try {
      final row = await _client
          .from('member_capital_shares')
          .select()
          .eq('farmer_id', _userId)
          .maybeSingle();
      if (row == null) return null;
      return CapitalSharesModel.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  // ─── Coop annual total (for share % calculation) ──────────────────────────

  Future<CoopAnnualTotal?> fetchCoopTotal(int year) async {
    try {
      final row = await _client
          .from('cooperative_annual_totals')
          .select()
          .eq('year', year)
          .maybeSingle();
      if (row == null) return null;
      return CoopAnnualTotal.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  // ─── Payout decision (cash or capital) ──────────────────────────────────────

  /// Submits the farmer's choice for a finalized [year] payout — 'cash' or
  /// 'capital' — via request_payout_decision(). This records the decision
  /// as PENDING only; no money moves and no capital_contribution_events
  /// row is written until an admin confirms it (see
  /// BalikTangkilikRepository.confirmPayoutDecision(), used from the
  /// admin-side History review). Superseded reinvest_patronage_capital()'s
  /// old immediate-write behavior — that RPC's authenticated access has
  /// been revoked, so this is now the only farmer-reachable path.
  ///
  /// [amount] is required for 'capital' (may be less than the full
  /// available amount); ignored for 'cash', which always claims the
  /// entire remaining available amount. Throws on failure — same
  /// real-money-adjacent convention as every other write in this
  /// repository — including the expected "a decision has already been
  /// submitted for this year" case, so the UI can surface it rather than
  /// silently pretending it succeeded.
  Future<void> requestPayoutDecision({
    required int year,
    required String decision,
    double? amount,
  }) async {
    await _client.rpc(
      'request_payout_decision',
      params: {'p_year': year, 'p_decision': decision, 'p_amount': amount},
    );
  }

  // ─── Member share percentage ──────────────────────────────────────────────

  double computeMemberSharePercent({
    required double memberSales,
    required double coopTotalSales,
  }) => member_sales_agg.computeMemberSharePercent(
        memberSales: memberSales,
        coopTotalSales: coopTotalSales,
      );

  // ─── Export support (Phase 7 — Farmer Download Records) ───────────────────
  // Farmer-scoped equivalents of AdminReportsRepository's fetchSalesReport /
  // fetchMemberContributionReport — reuses the same SalesReportData /
  // MemberContributionReportData shapes (and therefore the existing
  // report_csv_serializers.dart functions unchanged) filtered to _userId
  // via RLS's own "farmer reads own" policy, not a parallel data path.

  Future<SalesReportData> fetchMySalesForExport({
    DateTime? start,
    DateTime? end,
  }) async {
    try {
      var query = _client
          .from('member_sales_transactions')
          .select('*')
          .eq('farmer_id', _userId);
      if (start != null) {
        query = query.gte(
          'sale_date',
          start.toIso8601String().split('T').first,
        );
      }
      if (end != null) {
        query = query.lte('sale_date', end.toIso8601String().split('T').first);
      }
      final rows = await query.order('sale_date', ascending: false);
      if (rows.isEmpty) return SalesReportData.empty();

      final info = (await fetchFarmerInfoMap(_client, [_userId]))[_userId];
      final transactions = rows.map((row) {
        return SalesTransactionRow(
          id: row['id'] as String,
          farmerName: info?.fullName ?? 'Unknown Farmer',
          cropType: row['crop_type'] as String? ?? 'palay',
          cropName: row['crop_name'] as String? ?? '—',
          quantityKg: (row['quantity_kg'] as num).toDouble(),
          amount: (row['amount'] as num).toDouble(),
          saleDate: DateTime.parse(row['sale_date'] as String),
          referenceNo: row['reference_no'] as String?,
          // Farmer Download Records only ever reads member_sales_
          // transactions (this farmer's own Offer-to-Cooperative sales) —
          // the other three Selling Types aren't part of this export.
          sellingType: 'offer_to_cooperative',
        );
      }).toList();

      return SalesReportData(
        totalRevenue: 0,
        totalQuantityKg: 0,
        transactionCount: transactions.length,
        monthlyTrend: const [],
        transactions: transactions,
      );
    } catch (_) {
      return SalesReportData.empty();
    }
  }

  /// Member Contribution export is inherently annual (Balik-Tangkilik is
  /// computed per calendar year, same as the My Contribution screen's own
  /// current-year default) — [year] is passed explicitly rather than a
  /// date range, regardless of which period the farmer picked for the
  /// other export modules.
  Future<MemberContributionReportData> fetchMyContributionForExport(
    int year,
  ) async {
    try {
      final rows = await _client
          .from('member_sales_transactions')
          .select('crop_type, quantity_kg, amount')
          .eq('farmer_id', _userId)
          .gte('sale_date', '$year-01-01')
          .lte('sale_date', '$year-12-31');

      // Palay/Peanut keep their own dedicated fields; any other crop — now
      // possible here as of Phase 9's any-crop Offer-to-Cooperative
      // widening — rolls into otherCrops (Phase 11 addition), rather than
      // being silently miscounted as Palay (this loop's previous implicit
      // "else" branch) or left out of the exported breakdown entirely.
      double palayQtyKg = 0, palayAmount = 0, peanutQtyKg = 0, peanutAmount = 0;
      double otherCropsQtyKg = 0, otherCropsAmount = 0;
      for (final row in rows) {
        final qty = (row['quantity_kg'] as num).toDouble();
        final amount = (row['amount'] as num).toDouble();
        final cropType = row['crop_type'] as String?;
        if (cropType == 'palay') {
          palayQtyKg += qty;
          palayAmount += amount;
        } else if (cropType == 'peanut') {
          peanutQtyKg += qty;
          peanutAmount += amount;
        } else {
          otherCropsQtyKg += qty;
          otherCropsAmount += amount;
        }
      }
      final totalAmount = palayAmount + peanutAmount + otherCropsAmount;

      final coopTotal = await fetchCoopTotal(year);
      final sharePercent = coopTotal == null
          ? 0.0
          : computeMemberSharePercent(
              memberSales: totalAmount,
              coopTotalSales: coopTotal.totalCoopSales,
            ) *
              100;

      final info = (await fetchFarmerInfoMap(_client, [_userId]))[_userId];
      return MemberContributionReportData(
        year: year,
        totalCoopSales: 0,
        memberCount: 0,
        contributingMemberCount: 0,
        rows: [
          MemberContributionRow(
            farmerId: _userId,
            farmerName: info?.fullName ?? 'Unknown Farmer',
            palayQtyKg: palayQtyKg,
            palayAmount: palayAmount,
            peanutQtyKg: peanutQtyKg,
            peanutAmount: peanutAmount,
            totalAmount: totalAmount,
            sharePercent: sharePercent,
            otherCropsQtyKg: otherCropsQtyKg,
            otherCropsAmount: otherCropsAmount,
          ),
        ],
      );
    } catch (_) {
      return MemberContributionReportData.empty(year);
    }
  }
}