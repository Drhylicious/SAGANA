import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/buyer_order_model.dart';

/// Buyer-scoped access to the orders table.
///
/// Buyers have no UPDATE policy on `orders` under RLS — only SELECT (own)
/// and INSERT (own) — so this repository is read-only by design. There is
/// no cancel/edit path here to match that scope, not because it was
/// forgotten.
class BuyerOrderRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // ─── List — lightweight, no batch/harvest/category join ───────────────────

  Future<List<BuyerOrderModel>> fetchMyOrders() async {
    try {
      final orders = await _client
          .from('orders')
          .select('id, listing_id, quantity_kg, price_per_kg, total_price, '
              'status, notes, created_at, updated_at')
          .eq('buyer_id', _userId)
          .order('created_at', ascending: false);

      if (orders.isEmpty) return [];

      final listingIds =
          orders.map((o) => o['listing_id'] as String).toSet().toList();
      final listingMap = <String, Map<String, dynamic>>{};
      try {
        final listings = await _client
            .from('marketplace_listings')
            .select('id, crop_name, variety, photo_url')
            .inFilter('id', listingIds);
        for (final l in listings) {
          listingMap[l['id'] as String] = l;
        }
      } catch (_) {}

      return orders.map((o) {
        final listing = listingMap[o['listing_id']];
        return BuyerOrderModel.fromMap({
          ...o,
          'crop_name': listing?['crop_name'],
          'variety': listing?['variety'],
          'photo_url': listing?['photo_url'],
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Single order, full detail ─────────────────────────────────────────────

  Future<BuyerOrderModel?> fetchOrderById(String orderId) async {
    try {
      final order = await _client
          .from('orders')
          .select(
            'id, listing_id, quantity_kg, price_per_kg, total_price, '
            'status, notes, created_at, updated_at',
          )
          .eq('id', orderId)
          .maybeSingle();

      if (order == null) return null;

      final listingId = order['listing_id'] as String;
      String cropName = 'Produce';
      String? variety, photoUrl, batchId, batchNumber, category;
      DateTime? harvestDate;

      try {
        final listing = await _client
            .from('marketplace_listings')
            .select('crop_name, variety, photo_url, inventory_batch_id')
            .eq('id', listingId)
            .maybeSingle();
        cropName = listing?['crop_name'] as String? ?? 'Produce';
        variety = listing?['variety'] as String?;
        photoUrl = listing?['photo_url'] as String?;
        batchId = listing?['inventory_batch_id'] as String?;

        try {
          final crop = await _client
              .from('crop_master')
              .select('category')
              .ilike('crop_name', cropName)
              .maybeSingle();
          category = crop?['category'] as String?;
        } catch (_) {}

        if (batchId != null) {
          try {
            final batch = await _client
                .from('inventory_batches')
                .select('batch_number, harvest_record_id')
                .eq('id', batchId)
                .maybeSingle();
            batchNumber = batch?['batch_number'] as String?;
            final harvestRecordId = batch?['harvest_record_id'] as String?;
            if (harvestRecordId != null) {
              final hr = await _client
                  .from('harvest_records')
                  .select('harvest_date')
                  .eq('id', harvestRecordId)
                  .maybeSingle();
              if (hr?['harvest_date'] != null) {
                harvestDate = DateTime.parse(hr!['harvest_date'] as String);
              }
            }
          } catch (_) {}
        }
      } catch (_) {}

      return BuyerOrderModel.fromMap({
        ...order,
        'crop_name': cropName,
        'variety': variety,
        'photo_url': photoUrl,
        'batch_number': batchNumber,
        'harvest_date': harvestDate?.toIso8601String(),
        'category': category,
      });
    } catch (_) {
      return null;
    }
  }
}