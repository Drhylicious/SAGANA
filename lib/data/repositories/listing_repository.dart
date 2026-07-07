import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/marketplace_listing_model.dart';

class ListingRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  // ─── Create new listing ────────────────────────────────────────────────────

  Future<MarketplaceListingModel> createListing({
    required String cropName,
    String? variety,
    required double pricePerKg,
    required double volumeKg,
    String? inventoryBatchId,
    String? photoUrl,
  }) async {
    final response = await _client
        .from('marketplace_listings')
        .insert({
          'farmer_id': _userId,
          'inventory_batch_id': inventoryBatchId,
          'crop_name': cropName,
          'variety': variety,
          'price_per_kg': pricePerKg,
          'volume_kg': volumeKg,
          'status': 'pending_review',
          'photo_url': photoUrl,
          'submitted_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    return MarketplaceListingModel.fromMap(response);
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

  Future<void> withdrawListing(String listingId) async {
    await _client
        .from('marketplace_listings')
        .update({'status': 'withdrawn'})
        .eq('id', listingId)
        .eq('farmer_id', _userId);
  }

  // ─── Delete listing ────────────────────────────────────────────────────────

  Future<void> deleteListing(String listingId) async {
    await _client
        .from('marketplace_listings')
        .delete()
        .eq('id', listingId)
        .eq('farmer_id', _userId);
  }

  // ─── Resubmit listing (after changes required) ────────────────────────────

  Future<MarketplaceListingModel> resubmitListing({
    required String listingId,
    required double pricePerKg,
    required double volumeKg,
    String? photoUrl,
  }) async {
    final response = await _client.from('marketplace_listings').update({
      'price_per_kg': pricePerKg,
      'volume_kg': volumeKg,
      'photo_url': photoUrl,
      'status': 'pending_review',
      'admin_notes': null,
      'submitted_at': DateTime.now().toIso8601String(),
    }).eq('id', listingId).eq('farmer_id', _userId).select().single();

    return MarketplaceListingModel.fromMap(response);
  }
}
