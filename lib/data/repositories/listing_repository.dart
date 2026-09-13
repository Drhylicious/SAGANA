import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/marketplace_listing_model.dart';
import '../services/app_event_service.dart';

class ListingRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  // ─── Create new listing ────────────────────────────────────────────────────

  Future<MarketplaceListingModel> createListing({
    required String cropName,
    String? variety,
    required double pricePerKg,
    required double volumeKg,
    required String inventoryBatchId,
    String? photoUrl,
  }) async {
    final listingId = await _client.rpc('create_listing_with_reservation', params: {
      'p_batch_id': inventoryBatchId,
      'p_crop_name': cropName,
      'p_variety': variety,
      'p_quantity_kg': volumeKg,
      'p_price_per_kg': pricePerKg,
      'p_photo_url': photoUrl,
    });

    final row = await _client.from('marketplace_listings').select().eq('id', listingId).single();
    AppEventService.instance.notify();
    return MarketplaceListingModel.fromMap(row);
  }

  // ─── Fetch all listings for this farmer ───────────────────────────────────

  Future<List<MarketplaceListingModel>> fetchListings() async {
    try {
      final response = await _client
          .from('marketplace_listings')
          .select()
          .eq('farmer_id', _userId)
          .order('created_at', ascending: false);
      return response
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
      await _client.storage.from('listing_photos').uploadBinary(
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
  // pending_review, changes_required, or approved-but-unsold never released
  // its batch reservation, and there was no guard against withdrawing a
  // listing that was already sold/rejected/withdrawn. withdraw_listing
  // releases the reservation via the same _release_batch_reservation helper
  // used by reject and resubmit, and enforces the status guard atomically —
  // see supabase_schema_listing_withdraw_reservation.sql.
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

  // ─── Resubmit listing (after changes required) ────────────────────────────
  //
  // Previously a bare status update — a quantity change on resubmit never
  // touched the batch reservation, so a decrease leaked stock permanently
  // and an increase had no ceiling at all. resubmit_listing_with_reservation
  // reconciles the delta (reserving more via _apply_batch_reservation, or
  // releasing the difference via _release_batch_reservation) atomically with
  // the listing update, and raises if an increase exceeds real available
  // stock — see supabase_schema_listing_resubmit_reservation.sql.
  Future<MarketplaceListingModel> resubmitListing({
    required String listingId,
    required double pricePerKg,
    required double volumeKg,
    String? photoUrl,
  }) async {
    await _client.rpc('resubmit_listing_with_reservation', params: {
      'p_listing_id': listingId,
      'p_price_per_kg': pricePerKg,
      'p_volume_kg': volumeKg,
      'p_photo_url': photoUrl,
    });

    final row = await _client
        .from('marketplace_listings')
        .select()
        .eq('id', listingId)
        .eq('farmer_id', _userId)
        .single();
    AppEventService.instance.notify();
    return MarketplaceListingModel.fromMap(row);
  }
}