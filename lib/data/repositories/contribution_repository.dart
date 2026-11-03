import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/offline_cache.dart';
import '../models/contribution_model.dart';
import '../models/program_model.dart';
import 'member_sales_aggregation.dart' as member_sales_agg;

class ContributionRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // ─── Current year contribution ────────────────────────────────────────────

  Future<MemberContribution?> fetchCurrentYearContribution() async {
    try {
      final year = DateTime.now().year;
      final rows = await OfflineCache.load(
        screen: 'member_contribution_$year',
        fetch: () => _client
            .from('member_contributions')
            .select()
            .eq('farmer_id', _userId)
            .eq('year', year),
      );
      if (rows.isEmpty) return null;
      return MemberContribution.fromMap(rows.first);
    } catch (_) {
      return null;
    }
  }

  // ─── Previous year contribution (for "Actual Payout" card) ───────────────

  Future<MemberContribution?> fetchPreviousYearContribution() async {
    try {
      final year = DateTime.now().year - 1;
      final rows = await OfflineCache.load(
        screen: 'member_contribution_$year',
        fetch: () => _client
            .from('member_contributions')
            .select()
            .eq('farmer_id', _userId)
            .eq('year', year),
      );
      if (rows.isEmpty) return null;
      return MemberContribution.fromMap(rows.first);
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
      final rows = await OfflineCache.load(
        screen: 'member_capital_shares',
        fetch: () => _client
            .from('member_capital_shares')
            .select()
            .eq('farmer_id', _userId),
      );
      if (rows.isEmpty) return null;
      return CapitalSharesModel.fromMap(rows.first);
    } catch (_) {
      return null;
    }
  }

  // ─── My share of the cooperative's year (worked out in the database) ──────

  /// This farmer's selling and buying share (percent) for [year]. The
  /// database works it out from the saved year settings and returns only the
  /// two percentages, so the cooperative-wide totals themselves are never
  /// sent to a Farmer (get_my_activity_share, SQL script 16). Zero when the
  /// year has no saved totals or the call fails.
  Future<({double selling, double buying})> fetchMyActivityShare(int year) async {
    try {
      final rows = await _client.rpc(
        'get_my_activity_share',
        params: {'p_year': year},
      );
      if (rows is List && rows.isNotEmpty) {
        final row = rows.first as Map<String, dynamic>;
        return (
          selling: (row['selling_share_percent'] as num? ?? 0).toDouble(),
          buying: (row['buying_share_percent'] as num? ?? 0).toDouble(),
        );
      }
    } catch (_) {}
    return (selling: 0.0, buying: 0.0);
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
}
