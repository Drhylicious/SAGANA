import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/buyer_order_model.dart';
import '../models/buyer_activity_model.dart';

/// Buyer-scoped access to the orders table.
///
/// Buyers have no UPDATE policy on `orders` under RLS — only SELECT (own)
/// and INSERT (own). setFulfillment() below is the one exception, and it
/// stays consistent with that RLS scope: it goes through the guarded
/// set_order_fulfillment() RPC (SECURITY DEFINER, same pattern as
/// place_order), never a raw .update() — the RLS gap is real (buyers have
/// no UPDATE policy at all), but the RPC's own ownership/status checks are
/// the actual enforcement, not RLS.
class BuyerOrderRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // ─── List — lightweight, no batch/harvest/category join ───────────────────

  Future<List<BuyerOrderModel>> fetchMyOrders() async {
    try {
      final orders = await _client
          .from('orders')
          .select(
            'id, listing_id, quantity_kg, price_per_kg, total_price, '
            'status, notes, created_at, updated_at, fulfillment_method',
          )
          .eq('buyer_id', _userId)
          .order('created_at', ascending: false);

      if (orders.isEmpty) return [];

      final listingIds = orders
          .map((o) => o['listing_id'] as String)
          .toSet()
          .toList();
      final listingMap = <String, Map<String, dynamic>>{};
      try {
        final listings = await _client
            .from('marketplace_listings')
            .select('id, crop_name, variety, photo_url')
            .inFilter('id', listingIds);
        for (final l in listings) {
          listingMap[l['id'] as String] = l;
        }
      } catch (e) {
        debugPrint(
          'BuyerOrderRepository.fetchMyOrders: listing lookup '
          'failed ($e) — crop name/photo will be missing',
        );
      }

      return orders.map((o) {
        final listing = listingMap[o['listing_id']];
        return BuyerOrderModel.fromMap({
          ...o,
          'crop_name': listing?['crop_name'],
          'variety': listing?['variety'],
          'photo_url': listing?['photo_url'],
        });
      }).toList();
    } catch (e) {
      debugPrint('BuyerOrderRepository.fetchMyOrders failed: $e');
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
            'status, notes, created_at, updated_at, '
            'fulfillment_method, delivery_address, delivery_latitude, '
            'delivery_longitude, delivery_contact_number, delivery_notes, '
            'delivery_recipient_name, delivery_label',
          )
          .eq('id', orderId)
          .eq('buyer_id', _userId)
          .maybeSingle();

      if (order == null) return null;

      final listingId = order['listing_id'] as String;
      String cropName = 'Produce';
      String? variety,
          photoUrl,
          batchId,
          batchNumber,
          category,
          marketType,
          description;
      DateTime? harvestDate;

      try {
        final listing = await _client
            .from('marketplace_listings')
            .select(
              'crop_name, variety, photo_url, description, inventory_batch_id',
            )
            .eq('id', listingId)
            .maybeSingle();
        cropName = listing?['crop_name'] as String? ?? 'Produce';
        variety = listing?['variety'] as String?;
        photoUrl = listing?['photo_url'] as String?;
        description = listing?['description'] as String?;
        batchId = listing?['inventory_batch_id'] as String?;

        try {
          final crop = await _client
              .from('crop_master')
              .select('category')
              .ilike('crop_name', cropName)
              .maybeSingle();
          category = crop?['category'] as String?;
        } catch (e) {
          debugPrint(
            'BuyerOrderRepository.fetchOrderById: category lookup failed ($e)',
          );
        }

        if (batchId != null) {
          try {
            final batch = await _client
                .from('inventory_batches')
                .select('batch_number, harvest_record_id, crop_type')
                .eq('id', batchId)
                .maybeSingle();
            batchNumber = batch?['batch_number'] as String?;
            marketType = batch?['crop_type'] as String?;
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
          } catch (e) {
            debugPrint(
              'BuyerOrderRepository.fetchOrderById: batch/harvest lookup failed ($e)',
            );
          }
        }
      } catch (e) {
        debugPrint(
          'BuyerOrderRepository.fetchOrderById: listing lookup failed ($e)',
        );
      }

      return BuyerOrderModel.fromMap({
        ...order,
        'crop_name': cropName,
        'variety': variety,
        'photo_url': photoUrl,
        'batch_number': batchNumber,
        'harvest_date': harvestDate?.toIso8601String(),
        'category': category,
        'market_type': marketType,
        'description': description,
      });
    } catch (e) {
      debugPrint('BuyerOrderRepository.fetchOrderById failed: $e');
      return null;
    }
  }

  // setFulfillment() removed (Checkout + My Addresses, Phase 6c) — fulfillment
  // is now captured once, atomically with order creation via place_order(),
  // not via a separate post-approval RPC call. set_order_fulfillment() itself
  // is left in the database, unmodified and unreachable, per that phase's plan.

  // ─── Recent Activity (order-derived entries) ───────────────────────────────
  // Derived at read time from `orders` directly — same convention as
  // Farmer's DashboardRepository.fetchActivity(). No new table: orders
  // already carries created_at/updated_at/status, everything needed. One
  // entry per order, reflecting its current state — mirrors how Farmer's
  // own "Orders" activity category behaves (current state, not a full
  // per-transition history), not a new pattern invented for Buyer.
  Future<List<BuyerActivityItem>> fetchOrderActivity({int limit = 50}) async {
    try {
      final rows = await _client
          .from('orders')
          .select(
            'id, total_price, status, created_at, updated_at, fulfillment_method, '
            'marketplace_listings(crop_name, photo_url)',
          )
          .eq('buyer_id', _userId)
          .order('updated_at', ascending: false)
          .limit(limit);

      return rows.map((r) {
        final listing = r['marketplace_listings'] as Map?;
        final cropName = listing?['crop_name'] as String? ?? 'Produce';
        final photoUrl = listing?['photo_url'] as String?;
        final status = r['status'] as String;
        // Folds "used Pickup/Delivery" into the order-placed entry's
        // subtitle rather than logging it as a separate activity item —
        // it's a property of the order, not a distinct event.
        final fulfillmentMethod = r['fulfillment_method'] as String?;
        final fulfillmentLabel = switch (fulfillmentMethod) {
          'delivery' => 'Delivery',
          'pickup' => 'Pickup',
          _ => null,
        };
        // English title/statusLabel kept as a defensive fallback only —
        // buyer_account_screen.dart's _RecentActivityTile and
        // buyer_recent_activity_screen.dart's _ActivityCard (the only two
        // consumers of this model) now derive the displayed, localized
        // text from orderStatus below instead of reading these directly.
        final title = switch (status) {
          'pending' => 'Order Placed',
          'approved' => 'Order Approved',
          'completed' => 'Order Completed',
          'cancelled' => 'Order Cancelled',
          _ => 'Order Updated',
        };
        final timestamp = status == 'pending'
            ? DateTime.parse(r['created_at'] as String)
            : DateTime.parse(r['updated_at'] as String);
        return BuyerActivityItem(
          id: r['id'] as String,
          type: BuyerActivityType.order,
          title: title,
          subtitle: fulfillmentLabel != null
              ? '$cropName · $fulfillmentLabel'
              : cropName,
          valueLabel: '₱${(r['total_price'] as num).toStringAsFixed(2)}',
          statusLabel: status[0].toUpperCase() + status.substring(1),
          timestamp: timestamp,
          orderStatus: status,
          imageUrl: photoUrl,
        );
      }).toList();
    } catch (e) {
      debugPrint('BuyerOrderRepository.fetchOrderActivity failed: $e');
      return [];
    }
  }

  // Preview-only variant for the Account screen's inline section — small
  // limit per call site, matching Farmer's fetchActivity()'s own
  // per-category-limit pattern rather than slicing the full list.
  Future<List<BuyerActivityItem>> fetchRecentOrderActivity({int limit = 3}) =>
      fetchOrderActivity(limit: limit);
}