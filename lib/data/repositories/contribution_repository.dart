import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/contribution_model.dart';
import '../models/admin_reports_model.dart';
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
  }) =>
      member_sales_agg.computeMemberSharePercent(
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
        query = query.gte('sale_date', start.toIso8601String().split('T').first);
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
          memberId: info?.memberId ?? '—',
          cropType: row['crop_type'] as String? ?? 'palay',
          cropName: row['crop_name'] as String? ?? '—',
          quantityKg: (row['quantity_kg'] as num).toDouble(),
          amount: (row['amount'] as num).toDouble(),
          saleDate: DateTime.parse(row['sale_date'] as String),
          referenceNo: row['reference_no'] as String?,
        );
      }).toList();

      return SalesReportData(
        totalRevenue: 0,
        marketplaceRevenue: 0,
        totalQuantityKg: 0,
        transactionCount: transactions.length,
        palayAmount: 0,
        peanutAmount: 0,
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

      double palayQtyKg = 0, palayAmount = 0, peanutQtyKg = 0, peanutAmount = 0;
      for (final row in rows) {
        final qty = (row['quantity_kg'] as num).toDouble();
        final amount = (row['amount'] as num).toDouble();
        if (row['crop_type'] == 'peanut') {
          peanutQtyKg += qty;
          peanutAmount += amount;
        } else {
          palayQtyKg += qty;
          palayAmount += amount;
        }
      }
      final totalAmount = palayAmount + peanutAmount;

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
            memberId: info?.memberId ?? '—',
            palayQtyKg: palayQtyKg,
            palayAmount: palayAmount,
            peanutQtyKg: peanutQtyKg,
            peanutAmount: peanutAmount,
            totalAmount: totalAmount,
            sharePercent: sharePercent,
          ),
        ],
      );
    } catch (_) {
      return MemberContributionReportData.empty(year);
    }
  }
}