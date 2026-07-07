import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_profile_model.dart';
import '../models/loan_model.dart';
import '../models/contribution_model.dart';
import '../models/analytics_model.dart';

/// Admin-scoped repository for viewing a single farmer's complete profile.
/// Read-only — admin does not edit farmer-owned data (farm details, photo).
/// Reuses the same data shapes as the farmer-side screens so the admin
/// sees exactly what the farmer sees about themselves.
class FarmerDetailsRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Full farmer profile (same shape as FarmerProfileModel) ──────────────

  Future<FarmerProfileModel?> fetchFarmerProfile(String farmerId) async {
    try {
      final userInfo = await _client
          .from('user_information')
          .select()
          .eq('user_id', farmerId)
          .maybeSingle();

      final farmerProfile = await _client
          .from('farmer_profiles')
          .select()
          .eq('user_id', farmerId)
          .maybeSingle();

      List<String> crops = [];
      try {
        final cropRows = await _client
            .from('farmer_crops')
            .select('crop_name')
            .eq('farmer_id', farmerId)
            .order('created_at', ascending: false);
        crops = cropRows.map((r) => r['crop_name'] as String).toList();
      } catch (_) {}

      if (userInfo == null) return null;

      return FarmerProfileModel.fromMap({
        ...userInfo,
        ...(farmerProfile ?? {}),
        'primary_crops': crops,
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
      final row = await _client
          .from('user_information')
          .select('email')
          .eq('user_id', farmerId)
          .maybeSingle();
      return row?['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ─── Harvest activity summary (admin view of one farmer) ──────────────────

  Future<FarmPerformanceSummary> fetchHarvestSummary(String farmerId) async {
    try {
      final rows = await _client
          .from('harvest_records')
          .select('crop_name, quantity_kg, harvest_date')
          .eq('farmer_id', farmerId);

      double totalYield = 0;
      final Map<String, double> byCrop = {};
      for (final row in rows) {
        final qty = (row['quantity_kg'] as num).toDouble();
        totalYield += qty;
        final crop = row['crop_name'] as String;
        byCrop[crop] = (byCrop[crop] ?? 0) + qty;
      }

      double totalRevenue = 0;
      try {
        final listingRows = await _client
            .from('marketplace_listings')
            .select('price_per_kg, volume_kg')
            .eq('farmer_id', farmerId)
            .eq('status', 'approved');
        for (final row in listingRows) {
          totalRevenue += (row['price_per_kg'] as num).toDouble() *
              (row['volume_kg'] as num).toDouble();
        }
      } catch (_) {}

      double totalExpenses = 0;
      try {
        final expenseRows = await _client
            .from('farmer_expenses')
            .select('amount')
            .eq('farmer_id', farmerId);
        for (final row in expenseRows) {
          totalExpenses += (row['amount'] as num).toDouble();
        }
      } catch (_) {}

      final maxQty =
          byCrop.values.isEmpty ? 1.0 : byCrop.values.reduce((a, b) => a > b ? a : b);
      final breakdown = byCrop.entries
          .map((e) => CropYieldBreakdown(
                cropName: e.key,
                quantityKg: e.value,
                percentOfMax: maxQty > 0 ? (e.value / maxQty).clamp(0.0, 1.0) : 0,
              ))
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

  Future<Map<String, dynamic>> fetchHarvestStats(String farmerId) async {
    try {
      final rows = await _client
          .from('harvest_records')
          .select('quantity_kg, harvest_date, crop_name')
          .eq('farmer_id', farmerId)
          .order('harvest_date', ascending: false);

      if (rows.isEmpty) {
        return {'count': 0, 'total_kg': 0.0, 'last_entry': null, 'recent': []};
      }

      double totalKg = 0;
      for (final r in rows) {
        totalKg += (r['quantity_kg'] as num).toDouble();
      }

      return {
        'count':       rows.length,
        'total_kg':    totalKg,
        'last_entry':  rows.first['harvest_date'],
        'recent':      rows.take(3).toList(),
      };
    } catch (_) {
      return {'count': 0, 'total_kg': 0.0, 'last_entry': null, 'recent': []};
    }
  }

  // ─── Loans (reuses LoanModel, same shape as my_loans_screen) ──────────────

  Future<List<LoanModel>> fetchFarmerLoans(String farmerId) async {
    try {
      final rows = await _client
          .from('farmer_loans')
          .select('*, farmer_loan_items(*), farmer_loan_payments(*)')
          .eq('farmer_id', farmerId)
          .order('issued_date', ascending: false);
      return rows.map((r) => LoanModel.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Contribution / Balik-Tangkilik (reuses MemberContribution) ───────────

  Future<MemberContribution?> fetchCurrentYearContribution(
      String farmerId) async {
    try {
      final year = DateTime.now().year;
      final row = await _client
          .from('member_contributions')
          .select()
          .eq('farmer_id', farmerId)
          .eq('year', year)
          .maybeSingle();
      if (row == null) return null;
      return MemberContribution.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  Future<CapitalSharesModel?> fetchCapitalShares(String farmerId) async {
    try {
      final row = await _client
          .from('member_capital_shares')
          .select()
          .eq('farmer_id', farmerId)
          .maybeSingle();
      if (row == null) return null;
      return CapitalSharesModel.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  // ─── Admin actions ─────────────────────────────────────────────────────────

  Future<void> setFarmerStatus({
    required String farmerId,
    required String status, // 'active' | 'inactive'
  }) async {
    await _client
        .from('user_roles')
        .update({'status': status}).eq('user_id', farmerId);
  }
}
