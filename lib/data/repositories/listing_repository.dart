import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/quantity_utils.dart';
import '../services/offline_cache.dart';
import '../services/server_only.dart';
import '../models/marketplace_listing_model.dart';
import '../models/listing_edit_request_model.dart';
import '../models/workflow_event_model.dart';
import '../services/app_event_service.dart';
import 'crop_lookup.dart';

class ListingRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  // Single-row canonical-name resolution, for the create path that only
  // ever hydrates one listing at a time. fetchListings() below
  // batches this the same way admin_listing_repository.dart does for a
  // full list — this is that same helper's single-row equivalent, kept
  // local since only this repository's single-row calls need it.
  Future<MarketplaceListingModel> _hydrate(Map<String, dynamic> row) async {
    final cropId = row['crop_id'] as String?;
    String? canonicalName;
    if (cropId != null) {
      final names = await fetchCropNameMap(_client, [cropId]);
      canonicalName = names[cropId];
    }
    return MarketplaceListingModel.fromMap({
      ...row,
      'canonical_crop_name': canonicalName,
    });
  }

  // ─── Create new listing ────────────────────────────────────────────────────

  Future<MarketplaceListingModel> createListing({
    required String cropName,
    String? variety,
    required double pricePerKg,
    required double volumeKg,
    required String inventoryBatchId,
    String? photoUrl,
    required String description,
  }) async {
    await ServerOnly.ensureOnline();
    final listingId = await _client.rpc(
      'create_listing_with_reservation',
      params: {
      'p_batch_id': inventoryBatchId,
      'p_crop_name': cropName,
      'p_variety': variety,
      // Both are DECIMAL(10,2) in the database; rounding here keeps a value
      // like 0.45 or 12.50 exactly as typed (no binary-float tail).
      'p_quantity_kg': roundQuantity(volumeKg),
      'p_price_per_kg': roundQuantity(pricePerKg),
      'p_photo_url': photoUrl,
        'p_description': description,
      },
    );

    final row = await _client
        .from('marketplace_listings')
        .select()
        .eq('id', listingId)
        .single();
    AppEventService.instance.notify();
    return _hydrate(row);
  }

  // ─── Fetch all listings for this farmer ───────────────────────────────────

  Future<List<MarketplaceListingModel>> fetchListings() async {
    try {
      // Cached as the enriched rows (canonical crop name included), so the
      // list can still be viewed offline.
      final rows = await OfflineCache.load(
        screen: 'my_listings',
        fetch: () async {
          final response = await _client
              .from('marketplace_listings')
              .select()
              .eq('farmer_id', _userId)
              .order('created_at', ascending: false);

          final cropIds = response
              .map((r) => r['crop_id'] as String?)
              .whereType<String>()
              .toSet()
              .toList();
          final canonicalCropNames = await fetchCropNameMap(_client, cropIds);

          return response.map<Map<String, dynamic>>((row) {
            final cropId = row['crop_id'] as String?;
            return {
              ...row,
              'canonical_crop_name': cropId != null
                  ? canonicalCropNames[cropId]
                  : null,
            };
          }).toList();
        },
      );

      return rows
          .map((row) => MarketplaceListingModel.fromMap(row))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Upload listing photo ──────────────────────────────────────────────────

  Future<String?> uploadListingPhoto({
    required String batchNumber,
    required Uint8List imageBytes,
    required String fileExtension,
  }) async {
    try {
      final path =
          '$_userId/${batchNumber}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      await _client.storage
          .from('listing_photos')
          .uploadBinary(
            path,
            imageBytes,
            fileOptions: const FileOptions(upsert: true),
          );
      return _client.storage.from('listing_photos').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  // ─── Edit own listing ──────────────────────────────────────────────────────
  // Quantity, asking price, description and (optionally) the product photo of a
  // Pending Approval or Available listing. The crop and the unit never change.
  // update_my_listing() does the work in one transaction: it re-reserves or
  // releases the difference on the harvest batch, moves remaining_kg by the same
  // amount, and leaves existing orders (their own quantity and price) alone. See
  // supabase_schema_farmer_listing_edit.sql. [refreshPhoto] asks the database to
  // copy the crop's CURRENT roster photo onto the listing.
  Future<void> updateListing({
    required String listingId,
    required double quantity,
    required double pricePerUnit,
    required String description,
    bool refreshPhoto = false,
  }) async {
    await ServerOnly.ensureOnline();
    await _client.rpc(
      'update_my_listing',
      params: {
        'p_listing_id': listingId,
        'p_quantity': roundQuantity(quantity),
        'p_price_per_kg': roundQuantity(pricePerUnit),
        'p_description': description.trim(),
        'p_refresh_photo': refreshPhoto,
      },
    );
    AppEventService.instance.notify();
  }

  // ─── Edit requests (a published listing changes only after approval) ───────
  // The listing stays exactly as it is while a request waits. The Manager or
  // Officer approves (the change is applied) or disapproves with a reason (only
  // the request is rejected). See supabase_schema_listing_edit_approval.sql.

  /// Sends the proposed values for approval. [photoUrl] is a photo this Farmer
  /// already uploaded to the listing photo bucket (null keeps the photo).
  Future<void> requestEdit({
    required String listingId,
    required double quantity,
    required double pricePerUnit,
    required String description,
    String? photoUrl,
  }) async {
    await ServerOnly.ensureOnline();
    await _client.rpc(
      'request_listing_edit',
      params: {
        'p_listing_id': listingId,
        'p_quantity': roundQuantity(quantity),
        'p_price_per_kg': roundQuantity(pricePerUnit),
        'p_description': description.trim(),
        'p_photo_url': photoUrl,
      },
    );
    AppEventService.instance.notify();
  }

  Future<void> cancelEditRequest(String requestId) async {
    await ServerOnly.ensureOnline();
    await _client.rpc('cancel_listing_edit_request', params: {'p_request_id': requestId});
    AppEventService.instance.notify();
  }

  /// This listing's edit requests, newest first. The reviewer is never included.
  Future<List<ListingEditRequest>> fetchMyEditRequests(String listingId) async {
    try {
      final result = await _client.rpc(
        'get_my_listing_edit_requests',
        params: {'p_listing_id': listingId},
      );
      return [
        for (final r in (result as List? ?? const []))
          ListingEditRequest.fromMap(Map<String, dynamic>.from(r as Map)),
      ];
    } catch (_) {
      return [];
    }
  }

  /// The listing's history for its Farmer: what happened and when, as "you" or
  /// "cooperative", with the reason for a disapproval. No staff identity.
  Future<List<WorkflowEvent>> fetchMyHistory(String listingId) async {
    try {
      final result = await _client.rpc(
        'get_my_listing_history',
        params: {'p_listing_id': listingId},
      );
      return [
        for (final r in (result as List? ?? const []))
          WorkflowEvent.fromMap(Map<String, dynamic>.from(r as Map)),
      ];
    } catch (_) {
      return [];
    }
  }

  /// One listing, freshly read (the edit screen starts from the live values,
  /// not the copy the list screen was holding).
  Future<MarketplaceListingModel?> fetchListing(String listingId) async {
    try {
      final row = await _client
          .from('marketplace_listings')
          .select()
          .eq('id', listingId)
          .eq('farmer_id', _userId)
          .maybeSingle();
      return row == null ? null : await _hydrate(row);
    } catch (_) {
      return null;
    }
  }

  // ─── What buyers actually ordered, per listing ─────────────────────────────
  // The amount ordered on a listing is the sum of its orders' own totals, NOT
  // "quantity ordered x the listing's current price": the Farmer can change the
  // asking price after orders came in, and every order keeps the price it was
  // placed at. Cancelled (and legacy rejected) orders are not counted.
  Future<Map<String, double>> fetchOrderedAmounts() async {
    try {
      final rows = await _client
          .from('orders')
          .select('listing_id, total_price, status')
          .eq('farmer_id', _userId);
      final centavos = <String, int>{};
      for (final r in rows) {
        final status = r['status'] as String?;
        if (status == 'cancelled' || status == 'rejected') continue;
        final id = r['listing_id'] as String?;
        if (id == null) continue;
        final total = ((r['total_price'] as num?) ?? 0) * 100;
        centavos[id] = (centavos[id] ?? 0) + total.round();
      }
      return {for (final e in centavos.entries) e.key: e.value / 100};
    } catch (_) {
      return {};
    }
  }

  // ─── Withdraw listing ──────────────────────────────────────────────────────
  //
  // Previously a bare status update — pulling a listing while it was
  // pending_review or approved-but-unsold never released its batch
  // reservation, and there was no guard against withdrawing a listing
  // that was already sold/rejected/withdrawn. withdraw_listing releases
  // the reservation via the same _release_batch_reservation helper used
  // by reject, and enforces the status guard atomically — see
  // supabase_schema_listing_withdraw_reservation.sql.
  Future<void> withdrawListing(String listingId) async {
    await ServerOnly.ensureOnline();
    await _client.rpc('withdraw_listing', params: {'p_listing_id': listingId});
    AppEventService.instance.notify();
  }

  // ─── Delete listing ────────────────────────────────────────────────────────
  // Routed through delete_listing (see supabase_schema_rejected_listing_terminal.sql,
  // the current canonical version — see RESERVATION_MODEL_NOTES.md's
  // "Post-Marketplace-review updates" section) rather than a plain client
  // delete — the RPC enforces that only an already-withdrawn or rejected
  // listing (reservation already released either way) can be deleted, so
  // this is safe regardless of which UI caller invokes it.
  Future<void> deleteListing(String listingId) async {
    await _client.rpc('delete_listing', params: {'p_listing_id': listingId});
    AppEventService.instance.notify();
  }
}
