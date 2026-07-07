import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/contribution_model.dart';

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
      return rows
          .map((r) => MemberSalesTransaction.fromMap(r))
          .toList();
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

  // ─── Member share percentage ──────────────────────────────────────────────

  double computeMemberSharePercent({
    required double memberSales,
    required double coopTotalSales,
  }) {
    if (coopTotalSales <= 0) return 0;
    return (memberSales / coopTotalSales) * 100;
  }
}
