import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_batch_model.dart';
import '../models/cooperative_offer_model.dart';
import 'admin_activity_repository.dart';
import 'admin_listing_repository.dart';

class CooperativeOfferRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // Still needed internally by fetchOffers()'s categoryFilter branch below,
  // even though the UI no longer exposes a category filter control itself
  // (removed per review decision — only All Listings keeps that filter).
  Future<List<String>> fetchCropsByCategory({String? category}) {
    return AdminListingRepository().fetchCropsByCategory(category: category);
  }

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

  // ─── Admin: fetch offers — All (unscoped) or a specific status, with
  //     search + crop/category filtering. Mirrors AdminListingRepository's
  //     _fetchListings shape so this screen behaves identically to Pending
  //     Review / All Listings. Category filtering resolves to a set of
  //     crop names first (same text-match approach already used elsewhere
  //     for tables without a crop_id column yet — this table is one of
  //     them), since cooperative_purchase_offers only stores crop_name. ──

  Future<List<CooperativeOfferModel>> fetchOffers({
    String? statusFilter,
    String? searchQuery,
    String? cropFilter,
    String? categoryFilter,
  }) async {
    try {
      var query = _client.from('cooperative_purchase_offers').select(
        'id, farmer_id, crop_name, offered_quantity_kg, offered_at, '
        'inventory_batch_id, status, confirmed_quantity_kg, confirmed_amount, admin_notes',
      );
      if (statusFilter != null) query = query.eq('status', statusFilter);
      if (cropFilter != null) query = query.eq('crop_name', cropFilter);

      var rows = await query.order('offered_at', ascending: false);
      if (rows.isEmpty) return [];

      if (categoryFilter != null && cropFilter == null) {
        final namesInCategory = await fetchCropsByCategory(category: categoryFilter);
        rows = rows.where((r) => namesInCategory.contains(r['crop_name'])).toList();
        if (rows.isEmpty) return [];
      }

      final farmerIds = rows.map((r) => r['farmer_id'] as String).toSet().toList();
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', farmerIds);
      final nameMap = {
        for (final r in infoRows) r['user_id'] as String: r['full_name'] as String? ?? 'Farmer',
      };

      var result = rows
          .map((r) => CooperativeOfferModel.fromMap({...r, 'farmer_name': nameMap[r['farmer_id']] ?? 'Farmer'}))
          .toList();

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        result = result.where((o) =>
            o.farmerName.toLowerCase().contains(q) ||
            o.cropName.toLowerCase().contains(q)).toList();
      }

      return result;
    } catch (_) {
      return [];
    }
  }

  // ─── Admin: fetch one offer by id, with the extra detail-screen-only
  //     fields fetchOffers() doesn't bother resolving (farmer phone/photo,
  //     batch number, harvest date, category) — same multi-step resolution
  //     pattern as AdminOrderRepository.fetchOrderById(). Used by
  //     OfferDetailScreen, opened for a confirmed/declined offer.

  Future<CooperativeOfferModel?> fetchOfferById(String offerId) async {
    try {
      final row = await _client
          .from('cooperative_purchase_offers')
          .select('id, farmer_id, crop_name, offered_quantity_kg, offered_at, '
              'inventory_batch_id, status, confirmed_quantity_kg, confirmed_amount, '
              'admin_notes, confirmed_at')
          .eq('id', offerId)
          .maybeSingle();
      if (row == null) return null;

      final farmerId = row['farmer_id'] as String;

      String farmerName = 'Farmer';
      String? farmerPhone, farmerPhotoUrl;
      try {
        final farmer = await _client
            .from('user_information')
            .select('full_name, phone_number, profile_photo_url')
            .eq('user_id', farmerId)
            .maybeSingle();
        farmerName = farmer?['full_name'] as String? ?? 'Farmer';
        farmerPhone = farmer?['phone_number'] as String?;
        farmerPhotoUrl = farmer?['profile_photo_url'] as String?;
      } catch (_) {}

      String? batchNumber, category;
      DateTime? harvestDate;
      final batchId = row['inventory_batch_id'] as String?;
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
      try {
        final crop = await _client
            .from('crop_master')
            .select('category')
            .ilike('crop_name', row['crop_name'] as String? ?? '')
            .maybeSingle();
        category = crop?['category'] as String?;
      } catch (_) {}

      return CooperativeOfferModel.fromMap({
        ...row,
        'farmer_name': farmerName,
        'farmer_phone': farmerPhone,
        'farmer_photo_url': farmerPhotoUrl,
        'batch_number': batchNumber,
        'harvest_date': harvestDate?.toIso8601String(),
        'category': category,
      });
    } catch (_) {
      return null;
    }
  }

  // ─── Admin: pending offers only — still used by MarketplaceDashboardScreen
  //     for the KPI count. Kept as its own method (rather than making the
  //     dashboard call fetchOffers(statusFilter: 'pending')) purely because
  //     that call site only ever wants .length and this reads clearer there.

  Future<List<CooperativeOfferModel>> fetchPendingOffers() =>
      fetchOffers(statusFilter: 'pending');

  // ─── Admin: confirm an offer, recording the actual settlement ─────────────

  // Returns the created member_sales_transactions id — or null for a
  // confirmed offer on any crop other than Palay/Peanut, which settles
  // directly on the offer row instead (Scoped Fix decision, Admin
  // Marketplace review). Callers don't currently use this value either
  // way, but the nullability must be honest since the RPC can now
  // genuinely return no id.
  Future<String?> confirmCooperativeOffer({
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
    AdminActivityRepository().log(
      module: 'offers',
      actionType: 'confirmed',
      description: 'Confirmed a cooperative offer for ${confirmedQuantityKg.toStringAsFixed(1)}kg (₱${confirmedAmount.toStringAsFixed(2)}).',
      referenceId: offerId,
    );
    return result as String?;
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
    AdminActivityRepository().log(
      module: 'offers',
      actionType: 'declined',
      description: 'Declined a cooperative offer.',
      referenceId: offerId,
    );
  }
}
