import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_batch_model.dart';

class CooperativeOfferRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> offerToCooperative({
    required InventoryBatchModel batch,
    required double quantityKg,
  }) async {
    await _client.rpc('offer_batch_to_cooperative', params: {
      'p_batch_id': batch.id,
      'p_crop_name': batch.cropName,
      'p_quantity_kg': quantityKg,
    });
  }

  // ─── Farmer: which of this farmer's reserved batches are tied up in a
  //     pending cooperative offer — a single set-membership query rather
  //     than an N+1 check per batch, used by manage_inventory_screen.dart
  //     to distinguish "offered to cooperative" from "listed on marketplace"
  //     once a batch is reserved. ─────────────────────────────────────────

  Future<Set<String>> fetchBatchIdsWithPendingOffers() async {
    try {
      final userId = _client.auth.currentUser!.id;
      final rows = await _client
          .from('cooperative_purchase_offers')
          .select('inventory_batch_id')
          .eq('farmer_id', userId)
          .eq('status', 'pending');
      return rows.map((r) => r['inventory_batch_id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  // ─── Admin: fetch pending cooperative offers ───────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPendingOffers() async {
    try {
      final rows = await _client
          .from('cooperative_purchase_offers')
          .select('id, farmer_id, crop_name, offered_quantity_kg, offered_at, inventory_batch_id')
          .eq('status', 'pending')
          .order('offered_at', ascending: true);
      if (rows.isEmpty) return [];

      final farmerIds = rows.map((r) => r['farmer_id'] as String).toSet().toList();
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', farmerIds);
      final nameMap = {
        for (final r in infoRows) r['user_id'] as String: r['full_name'] as String? ?? 'Farmer',
      };

      return rows
          .map((r) => {...r, 'farmer_name': nameMap[r['farmer_id']] ?? 'Farmer'})
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Admin: confirm an offer, recording the actual settlement ─────────────

  Future<String> confirmCooperativeOffer({
    required String offerId,
    required double confirmedQuantityKg,
    required double confirmedAmount,
    String? adminNotes,
  }) async {
    final result = await _client.rpc('confirm_cooperative_offer', params: {
      'p_offer_id': offerId,
      'p_confirmed_quantity_kg': confirmedQuantityKg,
      'p_confirmed_amount': confirmedAmount,
      'p_admin_notes': adminNotes,
    });
    return result as String;
  }

  // ─── Admin: decline an offer, releasing the reserved quantity ─────────────

  Future<void> declineCooperativeOffer({
    required String offerId,
    String? adminNotes,
  }) async {
    await _client.rpc('decline_cooperative_offer', params: {
      'p_offer_id': offerId,
      'p_admin_notes': adminNotes,
    });
  }
}