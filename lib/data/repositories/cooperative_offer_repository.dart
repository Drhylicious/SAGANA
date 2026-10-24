import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/server_only.dart';
import '../models/inventory_batch_model.dart';
import '../models/cooperative_offer_model.dart';
import 'admin_activity_repository.dart';
import 'admin_listing_repository.dart';
import '../models/admin_log_message.dart';

class CooperativeOfferRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // Still needed internally by fetchOffers()'s categoryFilter branch below,
  // even though the UI no longer exposes a category filter control itself
  // (removed per review decision — only All Listings keeps that filter).
  Future<List<String>> fetchCropsByCategory({String? category}) {
    return AdminListingRepository().fetchCropsByCategory(category: category);
  }

  // ─── Farmer: submit an offer with an asking price per kg ─────────────────
  //
  // The database checks the batch is the caller's own and eligible, reserves
  // the quantity, records the first step of the negotiation and tells the
  // Cooperative. Needs a connection: the price, the reservation and the
  // eligibility are all decided on the server.

  Future<void> offerToCooperative({
    required InventoryBatchModel batch,
    required double quantityKg,
    required double askingPricePerKg,
    String? note,
  }) async {
    await ServerOnly.ensureOnline();
    await _client.rpc('offer_batch_to_cooperative', params: {
      'p_batch_id': batch.id,
      'p_quantity_kg': quantityKg,
      'p_asking_price_per_kg': askingPricePerKg,
      'p_note': note,
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
      var query = _client
          .from('cooperative_purchase_offers')
          .select(CooperativeOfferModel.selectColumns);
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
  //     CoopOfferNegotiationScreen, which also serves the Farmer.

  Future<CooperativeOfferModel?> fetchOfferById(String offerId) async {
    try {
      final row = await _client
          .from('cooperative_purchase_offers')
          .select(CooperativeOfferModel.selectColumns)
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

  // ─── Admin: offers waiting for the Cooperative's answer — the Dashboard
  //     KPI count. Offers where the Cooperative has already replied and the
  //     Farmer has to answer next are not waiting on the Cooperative.

  Future<List<CooperativeOfferModel>> fetchOffersAwaitingCooperative() async {
    final open = await fetchOffers(statusFilter: 'pending');
    return open.where((o) => o.awaitingCooperative).toList();
  }

  // ─── Farmer: every offer this farmer has made, newest first ───────────────

  Future<List<CooperativeOfferModel>> fetchMyOffers() async {
    try {
      final userId = _client.auth.currentUser!.id;
      final rows = await _client
          .from('cooperative_purchase_offers')
          .select(CooperativeOfferModel.selectColumns)
          .eq('farmer_id', userId)
          .order('offered_at', ascending: false);
      return rows.map((r) => CooperativeOfferModel.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// The open offer on [batchId], if any — what "Offer Status" opens.
  Future<String?> fetchPendingOfferIdForBatch(String batchId) async {
    try {
      final userId = _client.auth.currentUser!.id;
      final row = await _client
          .from('cooperative_purchase_offers')
          .select('id')
          .eq('farmer_id', userId)
          .eq('inventory_batch_id', batchId)
          .eq('status', 'pending')
          .maybeSingle();
      return row?['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ─── Both sides: the negotiation history of one offer, oldest first ───────

  Future<List<CooperativeOfferEvent>> fetchHistory(String offerId) async {
    try {
      final rows = await _client
          .from('cooperative_offer_events')
          .select()
          .eq('offer_id', offerId)
          .order('created_at', ascending: true)
          .order('round', ascending: true);
      return rows.map((r) => CooperativeOfferEvent.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Negotiation actions ─────────────────────────────────────────────────
  //
  // Each one is a single database function that checks who is calling, that
  // the offer is still open, that it is the caller's turn and that the price
  // on the caller's screen is still the latest ([expectedRound]). A refusal
  // comes back as a readable message (see friendlyErrorMessage). None of
  // these can be queued offline.

  /// Sends a counteroffer. Either side; the database works out which.
  /// [asCooperative] only decides whether it is written to the Manager's
  /// activity log.
  Future<void> counterOffer({
    required String offerId,
    required double pricePerKg,
    required int expectedRound,
    String? note,
    bool asCooperative = false,
  }) async {
    await ServerOnly.ensureOnline();
    await _client.rpc('counter_cooperative_offer', params: {
      'p_offer_id': offerId,
      'p_price_per_kg': pricePerKg,
      'p_expected_round': expectedRound,
      'p_note': note,
    });
    if (asCooperative) {
      AdminActivityRepository().log(
        module: 'offers',
        actionType: 'countered',
        message: AdminLogMessage('adminLogCoopOfferCountered', {
          'price': pricePerKg.toStringAsFixed(2),
        }),
        referenceId: offerId,
      );
    }
  }

  /// Accepts the latest price and settles the sale. Returns the created
  /// member_sales_transactions id. [kg] and [amount] are only used for the
  /// Manager's activity log line.
  Future<String?> acceptOffer({
    required String offerId,
    required int expectedRound,
    String? note,
    bool asCooperative = false,
    double? kg,
    double? amount,
  }) async {
    await ServerOnly.ensureOnline();
    final result = await _client.rpc('accept_cooperative_offer', params: {
      'p_offer_id': offerId,
      'p_expected_round': expectedRound,
      'p_note': note,
    });
    if (asCooperative) {
      AdminActivityRepository().log(
        module: 'offers',
        actionType: 'confirmed',
        message: AdminLogMessage('adminLogCoopOfferConfirmed', {
          'kg': (kg ?? 0).toStringAsFixed(1),
          'amount': (amount ?? 0).toStringAsFixed(2),
        }),
        referenceId: offerId,
      );
    }
    return result as String?;
  }

  /// The Cooperative ends the negotiation and the reserved kg go back to the
  /// Farmer's batch.
  Future<void> declineOffer({
    required String offerId,
    required int expectedRound,
    String? note,
  }) async {
    await ServerOnly.ensureOnline();
    await _client.rpc('decline_cooperative_offer', params: {
      'p_offer_id': offerId,
      'p_admin_notes': note,
      'p_expected_round': expectedRound,
    });
    AdminActivityRepository().log(
      module: 'offers',
      actionType: 'declined',
      message: const AdminLogMessage('adminLogCoopOfferDeclined'),
      referenceId: offerId,
    );
  }

  /// The Farmer ends the negotiation and the reserved kg go back to the batch.
  Future<void> cancelOffer({required String offerId, String? note}) async {
    await ServerOnly.ensureOnline();
    await _client.rpc('cancel_cooperative_offer', params: {
      'p_offer_id': offerId,
      'p_note': note,
    });
  }
}
