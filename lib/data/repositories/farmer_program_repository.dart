import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/chunked_in.dart';
import '../services/hive_service.dart';
import '../services/offline_cache.dart';
import '../models/cooperative_product_model.dart';
import '../models/program_model.dart';
import '../models/program_enrollment_request_model.dart';
import '../services/server_only.dart';

/// Farmer-side repository for the Cooperative Product Sales Program —
/// browsing available products and requesting a purchase. Kept separate
/// from ProgramRepository (admin-only), matching this codebase's existing
/// role-boundary convention (e.g. CropRepository vs the admin-only crop
/// repositories).
class FarmerProgramRepository {
  final SupabaseClient _client = Supabase.instance.client;

  static const _productSelect =
      'id, program_id, unit_price, is_available, stock_allocated, stock_reserved, '
      'cooperative_inventory(item_name, category, unit, image_url), '
      'cooperative_programs(program_name, member_discount_percent, status, program_purpose)';

  /// Every Cooperative Product this Farmer can order, from every active Product Sales program,
  /// priced for this Farmer (an enrolled member pays the program's member price). The database
  /// only returns these to Farmers: a Buyer gets nothing.
  Future<List<CooperativeProduct>> fetchCooperativeProducts() async {
    try {
      final farmerId = _client.auth.currentUser?.id ?? HiveService.getUserId();
      final rows = await _client.from('program_products').select(_productSelect).eq('is_available', true).order('created_at', ascending: false);
      if (rows.isEmpty) return [];
      var memberOf = <String>{};
      if (farmerId != null) {
        try {
          final m = await _client
              .from('program_members')
              .select('program_id')
              .eq('farmer_id', farmerId)
              .eq('status', 'active');
          memberOf = {for (final r in m) r['program_id'] as String};
        } catch (_) {}
      }
      final products = <CooperativeProduct>[];
      for (final r in rows) {
        final row = Map<String, dynamic>.from(r);
        final p = CooperativeProduct.fromRow(row, isMember: memberOf.contains(row['program_id']));
        if (p != null) products.add(p);
      }
      // Buyers and quantity sold, one read per program (totals only, never who bought).
      final stats = <String, Map<String, ProgramProductStats>>{};
      for (final programId in products.map((p) => p.programId).toSet()) {
        stats[programId] = await fetchProductStats(programId);
      }
      return [
        for (final p in products)
          p.copyWith(
            buyers: stats[p.programId]?[p.productId]?.buyers ?? 0,
            soldQuantity: stats[p.programId]?[p.productId]?.quantitySold ?? 0,
          ),
      ];
    } catch (_) {
      return [];
    }
  }

  /// The live rows for the Cooperative lines of a cart, by product id; null when the lookup fails.
  Future<Map<String, Map<String, dynamic>>?> fetchCooperativeCartRows(List<String> productIds) async {
    if (productIds.isEmpty) return {};
    try {
      final rows = await chunkedIn(productIds, (slice) => _client.from('program_products').select(_productSelect).inFilter('id', slice));
      return {for (final r in rows) r['id'] as String: Map<String, dynamic>.from(r)};
    } catch (_) {
      return null;
    }
  }

  /// Buyers and quantity sold per product (totals only, never who bought).
  /// If the database function is not there yet, every product simply shows 0.
  Future<Map<String, ProgramProductStats>> fetchProductStats(String programId) async {
    try {
      final res = await _client.rpc('get_program_product_stats', params: {'p_program_id': programId});
      return {
        for (final r in (res as List))
          (r as Map)['product_id'] as String:
              ProgramProductStats.fromMap(Map<String, dynamic>.from(r)),
      };
    } catch (_) {
      return {};
    }
  }

  /// How this Farmer is priced in a Product Sales program: the program's member
  /// discount and whether the Farmer is enrolled (enrolled Farmers pay the
  /// discounted price; everyone else pays the regular price). The price the
  /// database actually charges is decided on the server when the purchase is
  /// requested — this only lets the screen show it beforehand.
  Future<({double discountPercent, bool isMember})> fetchPricingInfo(
    String programId,
  ) async {
    try {
      final farmerId = _client.auth.currentUser?.id;
      final results = await Future.wait([
        _client
            .from('cooperative_programs')
            .select('member_discount_percent')
            .eq('id', programId)
            .maybeSingle(),
        farmerId == null
            ? Future.value(null)
            : _client
                  .from('program_members')
                  .select('id')
                  .eq('program_id', programId)
                  .eq('farmer_id', farmerId)
                  .eq('status', 'active')
                  .maybeSingle(),
      ]);
      final program = results[0] as Map<String, dynamic>?;
      return (
        discountPercent:
            (program?['member_discount_percent'] as num?)?.toDouble() ?? 0,
        isMember: results[1] != null,
      );
    } catch (_) {
      // The pricing script may not be applied yet: show regular prices.
      return (discountPercent: 0.0, isMember: false);
    }
  }

  // ─── Program self-service enrollment (Full Workflow) ──────────────────────
  // See supabase_schema_program_enrollment_requests.sql. Browse Programs
  // needs every active program regardless of purpose (distribution or
  // sales) — RLS ("cooperative_programs: members read active") already
  // scopes this to status='active' for any authenticated user, so no
  // farmer_id filter is needed or possible here.
  Future<List<CooperativeProgram>> fetchAvailablePrograms() async {
    try {
      final rows = await OfflineCache.load(
        screen: 'programs_available',
        fetch: () => _client
            .from('cooperative_programs')
            .select()
            .eq('status', 'active')
            .order('program_name'),
      );
      return rows.map((r) => CooperativeProgram.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// The farmer's own enrollment requests (any status), most recent first
  /// — used by Browse Programs to show "pending"/"rejected" state per
  /// program instead of just "no request yet".
  Future<List<ProgramEnrollmentRequest>> fetchMyEnrollmentRequests() async {
    try {
      final farmerId = _client.auth.currentUser?.id;
      if (farmerId == null) return [];
      final rows = await OfflineCache.load(
        screen: 'my_enrollment_requests',
        fetch: () => _client
            .from('program_enrollment_requests')
            .select(
              'id, program_id, status, admin_notes, submitted_at, reviewed_at, '
              'cooperative_programs(program_name, image_url)',
            )
            .eq('farmer_id', farmerId)
            .order('submitted_at', ascending: false),
      );
      return rows.map((r) => ProgramEnrollmentRequest.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Throws on failure — same reasoning as requestPurchase(): a real
  /// request with server-side validation (program active, no duplicate
  /// pending/approved request, not already enrolled — see
  /// submit_program_enrollment_request()), so the caller needs to know
  /// if it was rejected rather than have that swallowed silently.
  Future<void> requestEnrollment(String programId) async {
    await ServerOnly.ensureOnline();
    await _client.rpc(
      'submit_program_enrollment_request',
      params: {'p_program_id': programId},
    );
  }
}
