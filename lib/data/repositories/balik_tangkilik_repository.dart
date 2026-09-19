import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/balik_tangkilik_model.dart';
import '../models/contribution_model.dart';
import 'farmer_lookup.dart';
import 'member_sales_aggregation.dart';

/// Repository for Balik-Tangkilik Management. Reuses fetchMemberSalesTotals
/// (shared with AdminReportsRepository's Member Contribution Report) so
/// both screens agree on how a member's annual sales are computed.
///
/// WRITE METHODS DO NOT SWALLOW ERRORS — same reasoning as
/// AdminLoanRepository: these are real-money financial operations.
class BalikTangkilikRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Year settings (cooperative_annual_totals) ──────────────────────────

  Future<CoopAnnualTotal?> fetchYearSettings(int year) async {
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

  /// Upserts this year's settings. Does NOT touch afs_finalized unless
  /// explicitly passed — saving a pool/rate update mid-year shouldn't
  /// silently flip readiness.
  Future<void> saveYearSettings({
    required int year,
    required double totalCoopSales,
    required double distributableSurplus,
    required double interestRatePercent,
    bool? afsFinalized,
    double totalProgramSales = 0,
    double distributableProgramSurplus = 0,
  }) async {
    final payload = <String, dynamic>{
      'year': year,
      'total_coop_sales': totalCoopSales,
      'distributable_surplus': distributableSurplus,
      'interest_rate_percent': interestRatePercent,
      'total_program_sales': totalProgramSales,
      'distributable_program_surplus': distributableProgramSurplus,
    };
    if (afsFinalized != null) payload['afs_finalized'] = afsFinalized;

    await _client.from('cooperative_annual_totals').upsert(payload, onConflict: 'year');
  }

  // ─── Distribution preview / estimate refresh ────────────────────────────

  /// Computes each farmer's current estimate using this year's saved
  /// settings and live sales/capital data, without persisting anything —
  /// used for the live preview as the admin edits settings before saving.
  Future<BalikTangkilikYearSummary> fetchDistributionPreview(int year) async {
    try {
      final settings = await fetchYearSettings(year);
      // Active members only — farmer_profiles gets a row at registration,
      // before any admin review, and a rejected/draft account's row is
      // never removed (reject_member() explicitly leaves it in place).
      // An unfiltered roster here previously let draft/rejected/suspended
      // accounts receive real capital-share interest and dilute the
      // reported member count. Matches the same active-only pattern
      // AdminLoanRepository.fetchFarmerRoster() already established.
      final activeRoleRows = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'farmer')
          .eq('status', 'active');
      final activeIds = activeRoleRows.map((r) => r['user_id'] as String).toList();
      if (activeIds.isEmpty) return BalikTangkilikYearSummary.empty(year);

      final rosterRows = await _client
          .from('farmer_profiles')
          .select('user_id, member_id')
          .inFilter('user_id', activeIds);
      final farmerIds = rosterRows.map((r) => r['user_id'] as String).toList();
      if (farmerIds.isEmpty) return BalikTangkilikYearSummary.empty(year);

      final results = await Future.wait([
        fetchMemberSalesTotals(_client, year),
        _fetchAllCapitalShares(),
        fetchFarmerInfoMap(_client, farmerIds),
        _fetchExistingContributions(year, farmerIds),
        fetchMemberProgramPurchaseTotals(_client, year),
      ]);

      final salesTotals = results[0] as Map<String, MemberSalesTotals>;
      final capitalShares = results[1] as Map<String, CapitalSharesModel>;
      final farmerInfo = results[2] as Map<String, dynamic>;
      final existing = results[3] as Map<String, Map<String, dynamic>>;
      final purchaseTotals = results[4] as Map<String, double>;

      final liveTotalCoopSales =
          salesTotals.values.fold<double>(0, (sum, t) => sum + t.totalAmount);
      final totalCoopSales = settings?.totalCoopSales ?? liveTotalCoopSales;
      final distributableSurplus = settings?.distributableSurplus ?? 0;
      final interestRate = settings?.interestRatePercent ?? 7.0;

      // Option B — Product Sales Program's own parallel pool. Never
      // blended with the sales-side figures above.
      final liveTotalProgramSales =
          purchaseTotals.values.fold<double>(0, (sum, amount) => sum + amount);
      final totalProgramSales = settings?.totalProgramSales ?? liveTotalProgramSales;
      final distributableProgramSurplus = settings?.distributableProgramSurplus ?? 0;

      bool anyPaid = false;
      final rows = farmerIds.map((farmerId) {
        final info = farmerInfo[farmerId];
        final sales = salesTotals[farmerId] ?? MemberSalesTotals();
        final shares = capitalShares[farmerId];
        final existingRow = existing[farmerId];

        final sharePercent = totalCoopSales > 0 ? (sales.totalAmount / totalCoopSales) : 0.0;
        final estimatedBT = distributableSurplus * sharePercent;
        // Interest accrues only on fully-completed ₱2,000 shares
        // (Decision D1f) — totalShares is already floor(contribution /
        // shareValue), so any partial amount is excluded here.
        final capitalValue = ((shares?.totalShares ?? 0) * (shares?.shareValuePerUnit ?? 2000)).toDouble();
        final estimatedInterest = capitalValue * (interestRate / 100);

        // Option B — computed identically to the sales-side share/estimate
        // above, but against the Product Sales Program's own pool. Never
        // blended into sharePercent/estimatedBT.
        final purchasesAmount = purchaseTotals[farmerId] ?? 0;
        final purchaseShare =
            totalProgramSales > 0 ? (purchasesAmount / totalProgramSales) : 0.0;
        final estimatedPurchasePatronage = distributableProgramSurplus * purchaseShare;

        final status = existingRow?['status'] as String? ?? 'not_yet_computed';
        if (status == 'paid') anyPaid = true;

        return MemberDistributionRow(
          farmerId: farmerId,
          farmerName: info?.fullName ?? 'Unknown Farmer',
          memberId: info?.memberId ?? '—',
          totalSalesAmount: sales.totalAmount,
          sharePercent: sharePercent * 100,
          totalShares: shares?.totalShares ?? 0,
          capitalShareValue: capitalValue,
          estimatedBalikTangkilik: estimatedBT,
          estimatedInterest: estimatedInterest,
          actualBalikTangkilik: existingRow?['actual_balik_tangkilik'] != null
              ? (existingRow!['actual_balik_tangkilik'] as num).toDouble()
              : null,
          actualInterest: existingRow?['actual_interest_on_capital'] != null
              ? (existingRow!['actual_interest_on_capital'] as num).toDouble()
              : null,
          status: status,
          actualPayoutDate: existingRow?['actual_payout_date'] != null
              ? DateTime.tryParse(existingRow!['actual_payout_date'] as String)
              : null,
          palaySalesKg: sales.palayQtyKg,
          palaySalesAmount: sales.palayAmount,
          peanutSalesKg: sales.peanutQtyKg,
          peanutSalesAmount: sales.peanutAmount,
          otherCropsQtyKg: sales.otherCropsQtyKg,
          otherCropsAmount: sales.otherCropsAmount,
          programPurchasesAmount: purchasesAmount,
          purchaseSharePercent: purchaseShare * 100,
          estimatedPurchasePatronage: estimatedPurchasePatronage,
          actualPurchasePatronage: existingRow?['actual_purchase_patronage'] != null
              ? (existingRow!['actual_purchase_patronage'] as num).toDouble()
              : null,
        );
      }).toList()
        ..sort((a, b) => b.estimatedTotal.compareTo(a.estimatedTotal));

      return BalikTangkilikYearSummary(
        year: year,
        totalCoopSales: totalCoopSales,
        liveTotalCoopSales: liveTotalCoopSales,
        distributableSurplus: distributableSurplus,
        interestRatePercent: interestRate,
        afsFinalized: settings?.afsFinalized ?? false,
        isDistributed: anyPaid,
        rows: rows,
        totalProgramSales: totalProgramSales,
        liveTotalProgramSales: liveTotalProgramSales,
        distributableProgramSurplus: distributableProgramSurplus,
      );
    } catch (_) {
      return BalikTangkilikYearSummary.empty(year);
    }
  }

  /// Persists the current estimate into member_contributions for every
  /// farmer, WITHOUT touching actual_*/status='paid' rows — once a year is
  /// distributed, refreshing estimates must not silently overwrite the
  /// historical record. Lets farmers see an up-to-date running estimate on
  /// their own dashboard throughout the year, ahead of final distribution.
  Future<void> refreshEstimates(int year) async {
    final preview = await fetchDistributionPreview(year);
    final toUpsert = preview.rows.where((r) => !r.isPaid).map((r) => {
          'farmer_id': r.farmerId,
          'year': year,
          'total_sales_amount': r.totalSalesAmount,
          'estimated_balik_tangkilik': r.estimatedBalikTangkilik,
          'estimated_interest_on_capital': r.estimatedInterest,
          'status': 'pending',
          'palay_sales_kg': r.palaySalesKg,
          'palay_sales_amount': r.palaySalesAmount,
          'peanut_sales_kg': r.peanutSalesKg,
          'peanut_sales_amount': r.peanutSalesAmount,
          'other_crops_qty_kg': r.otherCropsQtyKg,
          'other_crops_amount': r.otherCropsAmount,
          'program_purchases_amount': r.programPurchasesAmount,
          'estimated_purchase_patronage': r.estimatedPurchasePatronage,
        }).toList();

    if (toUpsert.isEmpty) return;
    await _client.from('member_contributions').upsert(toUpsert, onConflict: 'farmer_id,year');
  }

  // ─── Final distribution ─────────────────────────────────────────────────

  /// Bulk-finalizes every non-paid farmer's distribution for [year] in one
  /// operation. Requires afs_finalized=true and blocks if the year has
  /// already been distributed — no partial or repeat distributions in
  /// this phase. Recomputes estimates fresh immediately before finalizing,
  /// so the recorded amounts reflect the latest sales data, not whatever
  /// was last previewed on screen.
  ///
  /// Throws on failure or if preconditions aren't met — the caller decides
  /// how to surface that to the admin.
  Future<void> recordDistribution(int year) async {
    final settings = await fetchYearSettings(year);
    if (settings == null || !settings.afsFinalized) {
      throw StateError('AFS must be finalized before distribution can be recorded.');
    }

    final preview = await fetchDistributionPreview(year);
    if (preview.isDistributed) {
      throw StateError('This year has already been distributed.');
    }

    final today = DateTime.now().toIso8601String().split('T').first;
    final toUpsert = preview.rows.map((r) => {
          'farmer_id': r.farmerId,
          'year': year,
          'total_sales_amount': r.totalSalesAmount,
          'estimated_balik_tangkilik': r.estimatedBalikTangkilik,
          'estimated_interest_on_capital': r.estimatedInterest,
          'actual_balik_tangkilik': r.estimatedBalikTangkilik,
          'actual_interest_on_capital': r.estimatedInterest,
          'actual_payout_date': today,
          'status': 'paid',
          'palay_sales_kg': r.palaySalesKg,
          'palay_sales_amount': r.palaySalesAmount,
          'peanut_sales_kg': r.peanutSalesKg,
          'peanut_sales_amount': r.peanutSalesAmount,
          'other_crops_qty_kg': r.otherCropsQtyKg,
          'other_crops_amount': r.otherCropsAmount,
          'program_purchases_amount': r.programPurchasesAmount,
          'estimated_purchase_patronage': r.estimatedPurchasePatronage,
          'actual_purchase_patronage': r.estimatedPurchasePatronage,
        }).toList();

    await _client.from('member_contributions').upsert(toUpsert, onConflict: 'farmer_id,year');
  }

  // ─── History ─────────────────────────────────────────────────────────────

  Future<List<DistributionHistoryYear>> fetchDistributionHistory() async {
    try {
      final rows = await _client
          .from('member_contributions')
          .select(
            'year, actual_balik_tangkilik, actual_interest_on_capital, actual_purchase_patronage',
          )
          .eq('status', 'paid');

      final byYear = <int, DistributionHistoryYear>{};
      final totals = <int, double>{};
      final counts = <int, int>{};

      for (final row in rows) {
        final year = row['year'] as int;
        final bt = (row['actual_balik_tangkilik'] as num? ?? 0).toDouble();
        final interest = (row['actual_interest_on_capital'] as num? ?? 0).toDouble();
        // Option B — was missing from this total: the per-farmer History
        // detail sheet already included it (it reads full rows via
        // fetchDistributionPreview()), but this list-level year total was
        // computed independently and never widened, so it silently
        // undercounted any year with Purchase Patronage activity.
        final purchasePatronage = (row['actual_purchase_patronage'] as num? ?? 0).toDouble();
        totals[year] = (totals[year] ?? 0) + bt + interest + purchasePatronage;
        counts[year] = (counts[year] ?? 0) + 1;
      }

      for (final year in totals.keys) {
        byYear[year] = DistributionHistoryYear(
          year: year,
          totalDistributed: totals[year]!,
          memberCount: counts[year]!,
        );
      }

      final list = byYear.values.toList()..sort((a, b) => b.year.compareTo(a.year));
      return list;
    } catch (_) {
      return [];
    }
  }

  // ─── Private helpers ─────────────────────────────────────────────────────

  Future<Map<String, CapitalSharesModel>> _fetchAllCapitalShares() async {
    try {
      final rows = await _client.from('member_capital_shares').select();
      return {
        for (final row in rows)
          row['farmer_id'] as String: CapitalSharesModel.fromMap(row),
      };
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, Map<String, dynamic>>> _fetchExistingContributions(
    int year,
    List<String> farmerIds,
  ) async {
    try {
      final rows = await _client
          .from('member_contributions')
          .select()
          .eq('year', year)
          .inFilter('farmer_id', farmerIds);
      return {for (final row in rows) row['farmer_id'] as String: row};
    } catch (_) {
      return {};
    }
  }
  
  /// Live sum of all Palay+Peanut sales for the year — used to suggest a
  /// starting value for Total Cooperative Sales. Never overwrites a saved
  /// value automatically; the screen just shows it as a reference the
  /// admin can accept or ignore, since the audited figure may legitimately
  /// differ from raw transaction sums.
  Future<double> fetchLiveTotalCoopSales(int year) async {
    try {
      final totals = await fetchMemberSalesTotals(_client, year);
      return totals.values.fold<double>(0, (sum, t) => sum + t.totalAmount);
    } catch (_) {
      return 0;
    }
  }

  /// Live sum of all confirmed Product Sales Program purchases for the
  /// year, across every sales-purpose program — Option B's parallel to
  /// fetchLiveTotalCoopSales() above. Same "reference suggestion only,
  /// never auto-overwrites a saved value" usage.
  Future<double> fetchLiveTotalProgramSales(int year) async {
    try {
      final totals = await fetchMemberProgramPurchaseTotals(_client, year);
      return totals.values.fold<double>(0, (sum, amount) => sum + amount);
    } catch (_) {
      return 0;
    }
  }
}