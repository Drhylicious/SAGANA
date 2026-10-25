import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/offline_cache.dart';
import '../services/server_only.dart';
import '../models/buyer_address_model.dart';
import '../models/farmer_profile_model.dart';
import '../models/farmer_member_model.dart';
import '../models/loan_model.dart';
import '../models/contribution_model.dart';
import '../models/analytics_model.dart';
import '../../core/utils/quantity_utils.dart';
import 'admin_activity_repository.dart';
import '../models/admin_log_message.dart';

/// Admin-scoped repository for viewing a single farmer's complete profile.
/// Read-only — admin does not edit farmer-owned data (farm details, photo).
/// Reuses the same data shapes as the farmer-side screens so the admin
/// sees exactly what the farmer sees about themselves.
class FarmerDetailsRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Every OfflineCache key this repository writes for one farmer (profile, loans,
  /// contribution, capital, expenses, programs). The screen notice covers them all.
  static List<String> cacheScreens(String farmerId) {
    final year = DateTime.now().year;
    return [
      'fd_profile_info_$farmerId',
      'fd_profile_farmer_$farmerId',
      'fd_profile_crops_$farmerId',
      'fd_profile_role_$farmerId',
      'fd_loans_$farmerId',
      'fd_contribution_${year}_$farmerId',
      'fd_capital_shares_$farmerId',
      'fd_expenses_$farmerId',
      'fd_programs_$farmerId',
      'capital_ledger_$farmerId',
      'fd_address_$farmerId',
      'fd_email_$farmerId',
      'fd_summary_harvests_$farmerId',
      'fd_summary_orders_$farmerId',
      'fd_summary_coop_$farmerId',
      'fd_summary_informal_$farmerId',
      'fd_summary_expenses_$farmerId',
      'fd_harvest_stats_$farmerId',
      'fd_status_history_$farmerId',
      'capital_summary_share_$farmerId',
      'capital_summary_policy',
    ];
  }

  /// Every address the farmer saved, the default one first (as My Addresses
  /// lists them). For an outsider applicant this is the address entered at
  /// registration. Empty when none is saved.
  Future<List<BuyerAddressModel>> fetchAddresses(String farmerId) async {
    try {
      final rows = await OfflineCache.load(
        screen: 'fd_address_$farmerId',
        fetch: () => _client
            .from('buyer_addresses')
            .select()
            .eq('user_id', farmerId)
            .order('is_default', ascending: false)
            .order('created_at', ascending: false),
      );
      return rows.map((r) => BuyerAddressModel.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Full farmer profile (same shape as FarmerProfileModel) ──────────────

  Future<FarmerProfileModel?> fetchFarmerProfile(String farmerId) async {
    try {
      final userInfoRows = await OfflineCache.load(
        screen: 'fd_profile_info_$farmerId',
        fetch: () => _client
            .from('user_information')
            .select()
            .eq('user_id', farmerId)
            .limit(1),
      );
      final userInfo = userInfoRows.isEmpty ? null : userInfoRows.first;
      final farmerProfileRows = await OfflineCache.load(
        screen: 'fd_profile_farmer_$farmerId',
        fetch: () => _client
            .from('farmer_profiles')
            .select()
            .eq('user_id', farmerId)
            .limit(1),
      );
      final farmerProfile = farmerProfileRows.isEmpty
          ? null
          : farmerProfileRows.first;
      List<String> crops = [];
      try {
        final cropRows = await OfflineCache.load(
          screen: 'fd_profile_crops_$farmerId',
          fetch: () => _client
              .from('farmer_crops')
              .select('crop_name')
              .eq('farmer_id', farmerId),
        );
        crops = cropRows.map((r) => r['crop_name'] as String).toList();
      } catch (_) {}

      // Real account status, not farmer_profiles.is_verified (a different
      // concept — verified-as-official-member vs. suspended/active).
      // Also pulls rejection_reason/suspension_reason so the detail screen
      // can show why a Rejected/Suspended member is in that state, and to
      // drive the same 5-status derivation the Members list uses.
      String accountStatus = 'active';
      String? rejectionReason;
      String? suspensionReason;
      try {
        final roleRowRows = await OfflineCache.load(
          screen: 'fd_profile_role_$farmerId',
          fetch: () => _client
              .from('user_roles')
              .select('status, rejection_reason, suspension_reason')
              .eq('user_id', farmerId)
              .eq('role', 'farmer')
              .limit(1),
        );
        final roleRow = roleRowRows.isEmpty ? null : roleRowRows.first;
        accountStatus = roleRow?['status'] as String? ?? 'active';
        rejectionReason = roleRow?['rejection_reason'] as String?;
        suspensionReason = roleRow?['suspension_reason'] as String?;
      } catch (_) {}

      if (userInfo == null) return null;

      return FarmerProfileModel.fromMap({
        ...userInfo, // includes last_active_at (user_information.*)
        ...(farmerProfile ?? {}),
        'primary_crops': crops,
        'account_status': accountStatus,
        'rejection_reason': rejectionReason,
        'suspension_reason': suspensionReason,
      });
    } catch (_) {
      return null;
    }
  }

  // ─── Phone number / email for contact actions ─────────────────────────────

  Future<String?> fetchFarmerEmail(String farmerId) async {
    try {
      // Admin can read auth.users via a Postgres function if exposed;
      // otherwise fall back to user_information if email is stored there.
      final rowRows = await OfflineCache.load(
        screen: 'fd_email_$farmerId',
        fetch: () => _client
            .from('user_information')
            .select('email')
            .eq('user_id', farmerId)
            .limit(1),
      );
      final row = rowRows.isEmpty ? null : rowRows.first;
      return row?['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ─── Harvest activity summary (admin view of one farmer) ──────────────────

  Future<FarmPerformanceSummary> fetchHarvestSummary(String farmerId) async {
    try {
      final rows = await OfflineCache.load(
        screen: 'fd_summary_harvests_$farmerId',
        fetch: () => _client
            .from('harvest_records')
            .select('crop_name, quantity_kg, unit, harvest_date'),
      );
      double totalYield = 0;
      final Map<String, double> byCrop = {};
      for (final row in rows) {
        // kg figures only: another unit is never added to a kg total.
        if (!isKg(row['unit'] as String?)) continue;
        final qty = (row['quantity_kg'] as num).toDouble();
        totalYield += qty;
        final crop = row['crop_name'] as String;
        byCrop[crop] = (byCrop[crop] ?? 0) + qty;
      }

      // Total revenue — same three-channel definition as
      // AnalyticsRepository.fetchFarmPerformance() and
      // DashboardRepository.fetchSummary(): completed marketplace orders,
      // confirmed cooperative sales, and informal sales. This method has
      // no period parameter (all-time, same as totalYield/totalExpenses
      // above), so unlike the other two, there's no date lower bound here.
      double totalRevenue = 0;
      try {
        final orderRows = await OfflineCache.load(
          screen: 'fd_summary_orders_$farmerId',
          fetch: () => _client
              .from('orders')
              .select('total_price')
              .eq('farmer_id', farmerId),
        );
        for (final row in orderRows) {
          totalRevenue += (row['total_price'] as num).toDouble();
        }
      } catch (_) {}

      try {
        final coopRows = await OfflineCache.load(
          screen: 'fd_summary_coop_$farmerId',
          fetch: () =>
              _client.from('member_sales_transactions').select('amount'),
        );
        for (final row in coopRows) {
          totalRevenue += (row['amount'] as num).toDouble();
        }
      } catch (_) {}

      try {
        final informalRows = await OfflineCache.load(
          screen: 'fd_summary_informal_$farmerId',
          fetch: () => _client.from('informal_sales').select('amount'),
        );
        for (final row in informalRows) {
          totalRevenue += ((row['amount'] as num?)?.toDouble() ?? 0);
        }
      } catch (_) {}

      double totalExpenses = 0;
      try {
        final expenseRows = await OfflineCache.load(
          screen: 'fd_summary_expenses_$farmerId',
          fetch: () => _client.from('farmer_expenses').select('amount'),
        );
        for (final row in expenseRows) {
          totalExpenses += (row['amount'] as num).toDouble();
        }
      } catch (_) {}

      final maxQty = byCrop.values.isEmpty
          ? 1.0
          : byCrop.values.reduce((a, b) => a > b ? a : b);
      final breakdown =
          byCrop.entries
              .map(
                (e) => CropYieldBreakdown(
                  cropName: e.key,
                  quantityKg: e.value,
                  percentOfMax: maxQty > 0
                      ? (e.value / maxQty).clamp(0.0, 1.0)
                      : 0,
                ),
              )
              .toList()
            ..sort((a, b) => b.quantityKg.compareTo(a.quantityKg));

      return FarmPerformanceSummary(
        totalYieldKg: totalYield,
        totalRevenue: totalRevenue,
        totalExpenses: totalExpenses,
        cropBreakdown: breakdown,
      );
    } catch (_) {
      return FarmPerformanceSummary.empty;
    }
  }

  // ─── Harvest stats (record count + last entry date) ───────────────────────
  // this_year_kg / unsynced_count added so _HarvestActivityCard's KPI row
  // (Farmer Details' "Harvest" section) can match the farmer-facing Harvest
  // History screen's own KPIs (Total Harvest / This Year's Yield / Sync
  // Status) exactly, rather than the previous Records/Total KG/Last Entry
  // structure, which didn't correspond to anything the farmer sees.

  Future<Map<String, dynamic>> fetchHarvestStats(String farmerId) async {
    try {
      final rows = await OfflineCache.load(
        screen: 'fd_harvest_stats_$farmerId',
        fetch: () => _client
            .from('harvest_records')
            .select('quantity_kg, unit, harvest_date, crop_name, is_synced')
            .eq('farmer_id', farmerId),
      );
      if (rows.isEmpty) {
        return {
          'count': 0,
          'total_kg': 0.0,
          'this_year_kg': 0.0,
          'unsynced_count': 0,
          'last_entry': null,
          'recent': [],
        };
      }

      final currentYear = DateTime.now().year;
      double totalKg = 0;
      double thisYearKg = 0;
      int unsyncedCount = 0;
      for (final r in rows) {
        final qty = (r['quantity_kg'] as num).toDouble();
        final harvestDate = DateTime.parse(r['harvest_date'] as String);
        // The totals are kg figures; a harvest in another unit is still
        // counted and listed, but not added to them.
        if (isKg(r['unit'] as String?)) {
          totalKg += qty;
          if (harvestDate.year == currentYear) thisYearKg += qty;
        }
        if (!(r['is_synced'] as bool? ?? true)) unsyncedCount++;
      }

      return {
        'count': rows.length,
        'total_kg': totalKg,
        'this_year_kg': thisYearKg,
        'unsynced_count': unsyncedCount,
        'last_entry': rows.first['harvest_date'],
        'recent': rows.take(3).toList(),
      };
    } catch (_) {
      return {
        'count': 0,
        'total_kg': 0.0,
        'this_year_kg': 0.0,
        'unsynced_count': 0,
        'last_entry': null,
        'recent': [],
      };
    }
  }

  // ─── Loans (reuses LoanModel, same shape as my_loans_screen) ──────────────

  Future<List<LoanModel>> fetchFarmerLoans(String farmerId) async {
    try {
      final rows = await OfflineCache.load(
        screen: 'fd_loans_$farmerId',
        fetch: () => _client
            .from('farmer_loans')
            .select('*, farmer_loan_items(*), farmer_loan_payments(*)')
            .eq('farmer_id', farmerId),
      );
      return rows.map((r) => LoanModel.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Contribution / Balik-Tangkilik (reuses MemberContribution) ───────────

  Future<MemberContribution?> fetchCurrentYearContribution(
    String farmerId,
  ) async {
    try {
      final year = DateTime.now().year;
      final rowRows = await OfflineCache.load(
        screen: 'fd_contribution_${year}_$farmerId',
        fetch: () => _client
            .from('member_contributions')
            .select()
            .eq('farmer_id', farmerId)
            .eq('year', year)
            .limit(1),
      );
      final row = rowRows.isEmpty ? null : rowRows.first;
      if (row == null) return null;
      return MemberContribution.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  Future<CapitalSharesModel?> fetchCapitalShares(String farmerId) async {
    try {
      final rowRows = await OfflineCache.load(
        screen: 'fd_capital_shares_$farmerId',
        fetch: () => _client
            .from('member_capital_shares')
            .select()
            .eq('farmer_id', farmerId)
            .limit(1),
      );
      final row = rowRows.isEmpty ? null : rowRows.first;
      if (row == null) return null;
      return CapitalSharesModel.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchFarmerExpenses(
    String farmerId,
  ) async {
    try {
      final rows = await OfflineCache.load(
        screen: 'fd_expenses_$farmerId',
        fetch: () => _client
            .from('farmer_expenses')
            .select(
              'id, description, amount, expense_date, category, is_subsidy',
            )
            .eq('farmer_id', farmerId),
      );
      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Assigned programs (via program_members → cooperative_programs) ──────
  //
  // Programs are assigned per-farmer through the 'program_members' join
  // table, not read directly off 'cooperative_programs'. The embedded
  // resource name in the select() must match the actual FK table name
  // ('cooperative_programs') exactly, or PostgREST returns a 400.
  // Results are flattened here so _ProgramsTab (which reads program['name']
  // and program['description']) doesn't need to know about the join shape.

  Future<List<Map<String, dynamic>>> fetchAssignedPrograms(
    String farmerId,
  ) async {
    try {
      final rows = await OfflineCache.load(
        screen: 'fd_programs_$farmerId',
        fetch: () => _client
            .from('program_members')
            .select(
              'id, program_id, farmer_id, status, enrolled_at, '
              'cooperative_programs(program_name, program_type, '
              'program_purpose, description, status, season_year)',
            )
            .eq('farmer_id', farmerId),
      );
      return rows.map((row) {
        final program = row['cooperative_programs'] as Map<String, dynamic>?;
        return {
          'name': program?['program_name'] as String? ?? 'Program',
          'description': program?['description'] as String? ?? '',
          'program_type': program?['program_type'] as String?,
          'program_purpose':
              program?['program_purpose'] as String? ?? 'distribution',
          'season_year': program?['season_year'],
          'enrolled_at': row['enrolled_at'],
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Admin actions ─────────────────────────────────────────────────────────

  /// Suspend (reason required) or reactivate a member. Routes through the
  /// Phase C RPCs so the reason, audit row (member_status_events) and the
  /// farmer notification are always written together.
  Future<void> setFarmerStatus({
    required String farmerId,
    required String status, // 'active' | 'suspended'
    String? reason,
    DateTime? suspendedUntil, // null = until an admin reactivates
  }) async {
    await ServerOnly.ensureOnline();
    if (status == 'suspended') {
      await _client.rpc(
        'suspend_member',
        params: {
          'p_user_id': farmerId,
          'p_reason': (reason == null || reason.trim().isEmpty)
              ? 'Suspended by Manager'
              : reason.trim(),
          'p_suspended_until': suspendedUntil?.toUtc().toIso8601String(),
        },
      );
      AdminActivityRepository().log(
        module: 'members',
        actionType: 'suspended',
        message: const AdminLogMessage('adminLogMemberSuspended'),
        referenceId: farmerId,
      );
    } else {
      await _client.rpc('reactivate_member', params: {'p_user_id': farmerId});
      AdminActivityRepository().log(
        module: 'members',
        actionType: 'reactivated',
        message: const AdminLogMessage('adminLogMemberReactivated'),
        referenceId: farmerId,
      );
    }
  }

  Future<List<MemberStatusEvent>> fetchStatusHistory(String farmerId) async {
    try {
      final rows = await OfflineCache.load(
        screen: 'fd_status_history_$farmerId',
        fetch: () => _client
            .from('member_status_events')
            .select('from_status, to_status, reason, created_at')
            .eq('member_id', farmerId)
            .order('created_at', ascending: false),
      );
      return rows.map((r) => MemberStatusEvent.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }
}
