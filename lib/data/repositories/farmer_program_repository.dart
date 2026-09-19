import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/program_model.dart';

/// Farmer-side repository for the Cooperative Product Sales Program —
/// browsing available products and requesting a purchase. Kept separate
/// from ProgramRepository (admin-only), matching this codebase's existing
/// role-boundary convention (e.g. CropRepository vs the admin-only crop
/// repositories).
class FarmerProgramRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// RLS ("program_products: enrolled active farmers read available" in
  /// supabase_schema_program_product_sales.sql) already restricts this to
  /// products in programs the caller has an ACTIVE enrollment in — no
  /// farmer_id filter needed here, and a farmer who isn't enrolled (or
  /// was removed) simply sees an empty list.
  Future<List<ProgramProduct>> fetchAvailableProducts(String programId) async {
    try {
      final rows = await _client
          .from('program_products')
          .select('id, program_id, inventory_item_id, unit_price, is_available, '
              'cooperative_inventory(item_name, category, unit, quantity_on_hand, image_url)')
          .eq('program_id', programId)
          .order('created_at');
      return rows.map((r) {
        final inv = r['cooperative_inventory'] as Map<String, dynamic>?;
        return ProgramProduct.fromMap({
          ...r,
          'item_name': inv?['item_name'],
          'category': inv?['category'],
          'unit': inv?['unit'],
          'quantity_on_hand': inv?['quantity_on_hand'],
          'image_url': inv?['image_url'],
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Throws on failure — same reasoning as issueLoan()/confirmPurchase():
  /// this is a real purchase request (request_program_purchase() checks
  /// enrollment and stock server-side and rejects with a specific message
  /// if either fails), and the caller needs to know it didn't go through
  /// rather than have that swallowed silently.
  Future<void> requestPurchase({
    required String programId,
    required String productId,
    required double quantity,
  }) async {
    await _client.rpc('request_program_purchase', params: {
      'p_program_id': programId,
      'p_product_id': productId,
      'p_quantity': quantity,
    });
  }

  /// RLS ("program_product_purchases: farmer reads own") already scopes
  /// this to the caller's own rows — no farmer_id filter needed, but one
  /// is applied anyway for clarity and to avoid depending on RLS alone.
  Future<List<ProgramPurchase>> fetchMyPurchases(String programId) async {
    try {
      final farmerId = _client.auth.currentUser?.id;
      if (farmerId == null) return [];
      final rows = await _client
          .from('program_product_purchases')
          .select('id, program_id, product_id, farmer_id, quantity, unit_price, '
              'total_amount, status, requested_at, confirmed_at, cancelled_at, cancel_reason, '
              'cooperative_programs(program_name), '
              'program_products(cooperative_inventory(item_name, unit, image_url))')
          .eq('program_id', programId)
          .eq('farmer_id', farmerId)
          .order('requested_at', ascending: false);
      return rows.map((r) {
        final program = r['cooperative_programs'] as Map<String, dynamic>?;
        final product = r['program_products'] as Map<String, dynamic>?;
        final inv = product?['cooperative_inventory'] as Map<String, dynamic>?;
        return ProgramPurchase.fromMap({
          ...r,
          'program_name': program?['program_name'],
          'item_name': inv?['item_name'],
          'unit': inv?['unit'],
          'image_url': inv?['image_url'],
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// A farmer may only cancel their own still-pending purchase — enforced
  /// server-side by cancel_program_purchase() itself, not just by this
  /// screen hiding the button for anything else.
  // p_reason has no default on the DB function (confirmed live:
  // cancel_program_purchase(p_purchase_id uuid, p_reason text)), so it must
  // always be supplied — omitting it previously meant PostgREST couldn't
  // match the function overload and every cancellation silently failed.
  Future<bool> cancelMyPurchase(String purchaseId, String reason) async {
    try {
      await _client.rpc('cancel_program_purchase', params: {
        'p_purchase_id': purchaseId,
        'p_reason': reason,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
