import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/marketplace_listing_model.dart';
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
    final listingId = await _client.rpc(
      'create_listing_with_reservation',
      params: {
      'p_batch_id': inventoryBatchId,
      'p_crop_name': cropName,
      'p_variety': variety,
      'p_quantity_kg': volumeKg,
      'p_price_per_kg': pricePerKg,
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

      return response.map((row) {
        final cropId = row['crop_id'] as String?;
        return MarketplaceListingModel.fromMap({
          ...row,
          'canonical_crop_name': cropId != null
              ? canonicalCropNames[cropId]
              : null,
        });
      }).toList();
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