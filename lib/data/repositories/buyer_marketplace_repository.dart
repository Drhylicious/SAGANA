import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/buyer_listing_model.dart';
import 'price_management_repository.dart';

/// Read-only, buyer-scoped access to the marketplace. Only ever returns
/// approved listings — buyers have no reason to see, and RLS gives them
/// no ability to see, pending/changes_required/rejected listings.
/// Deliberately its own repository rather than reusing AdminListingRepository,
/// matching the codebase's existing precedent of one repository per role
/// against the same table (listing_repository.dart for farmer-own-listings
/// vs admin_listing_repository.dart for admin-all-listings already does this).
class BuyerMarketplaceRepository {
  final SupabaseClient _client = Supabase.instance.client;
  final PriceManagementRepository _priceRepo = PriceManagementRepository();

  Future<List<BuyerListingModel>> fetchApprovedListings() async {
    try {
      final rows = await _client
          .from('marketplace_listings')
          .select(
            'id, crop_name, variety, volume_kg, remaining_kg, price_per_kg, '
            'inventory_batch_id, photo_url, created_at',
          )
          .eq('status', 'approved')
          .order('created_at', ascending: false);

      if (rows.isEmpty) return [];

      // ── Batch info (grade, live available_kg, status) ────────────────────
      final batchIds = rows
          .where((r) => r['inventory_batch_id'] != null)
          .map((r) => r['inventory_batch_id'] as String)
          .toSet()
          .toList();

      final batchMap = <String, Map<String, dynamic>>{};
      if (batchIds.isNotEmpty) {
        try {
          final batchRows = await _client
              .from('inventory_batches')
              .select('id, quality_grade, available_kg, status')
              .inFilter('id', batchIds);
          for (final b in batchRows) {
            batchMap[b['id'] as String] = b;
          }
        } catch (_) {}
      }

      // ── Category lookup (crop_master) ─────────────────────────────────────
      final categoryMap = <String, String>{};
      try {
        final cropRows = await _client
            .from('crop_master')
            .select('crop_name, category')
            .eq('is_active', true);
        for (final c in cropRows) {
          categoryMap[(c['crop_name'] as String).toLowerCase()] =
              c['category'] as String;
        }
      } catch (_) {}

      // ── Market reference prices (reused read-only, zero new code) ────────
      final priceMap = <String, double>{};
      try {
        final prices = await _priceRepo.fetchLatestPricePerCrop();
        for (final p in prices) {
          priceMap[p.cropName.toLowerCase()] = p.price;
        }
      } catch (_) {}

      return rows.map((r) {
        final batchId = r['inventory_batch_id'] as String?;
        final batch = batchId != null ? batchMap[batchId] : null;
        final cropNameLower = (r['crop_name'] as String).toLowerCase();

        return BuyerListingModel.fromMap({
          ...r,
          'category': categoryMap[cropNameLower],
          'quality_grade': batch?['quality_grade'],
          'available_kg': batch?['available_kg'],
          'batch_status': batch?['status'],
          'market_ref_price': priceMap[cropNameLower],
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Single listing, full detail (batch number + harvest date included) ───

  Future<BuyerListingModel?> fetchListingById(String listingId) async {
    try {
      final row = await _client
          .from('marketplace_listings')
          .select(
            'id, crop_name, variety, volume_kg, remaining_kg, price_per_kg, '
            'inventory_batch_id, photo_url, created_at',
          )
          .eq('id', listingId)
          .eq('status', 'approved')
          .maybeSingle();

      if (row == null) return null;

      final batchId = row['inventory_batch_id'] as String?;

      Map<String, dynamic>? batch;
      DateTime? harvestDate;
      if (batchId != null) {
        try {
          batch = await _client
              .from('inventory_batches')
              .select('quality_grade, available_kg, status, batch_number, harvest_record_id')
              .eq('id', batchId)
              .maybeSingle();

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

      String? category;
      try {
        final crop = await _client
            .from('crop_master')
            .select('category')
            .ilike('crop_name', row['crop_name'] as String)
            .maybeSingle();
        category = crop?['category'] as String?;
      } catch (_) {}

      double? marketRefPrice;
      try {
        final priceRow = await _client
            .from('price_records')
            .select('price')
            .ilike('crop_name', row['crop_name'] as String)
            .order('recorded_at', ascending: false)
            .limit(1)
            .maybeSingle();
        marketRefPrice = priceRow?['price'] != null
            ? (priceRow!['price'] as num).toDouble()
            : null;
      } catch (_) {}

      return BuyerListingModel.fromMap({
        ...row,
        'category': category,
        'quality_grade': batch?['quality_grade'],
        'available_kg': batch?['available_kg'],
        'batch_status': batch?['status'],
        'batch_number': batch?['batch_number'],
        'harvest_date': harvestDate?.toIso8601String(),
        'market_ref_price': marketRefPrice,
      });
    } catch (_) {
      return null;
    }
  }

  // ─── Related listings ("More from SP3" strip) ──────────────────────────────

  Future<List<BuyerListingModel>> fetchRelatedListings({
    required String excludeListingId,
    int limit = 6,
  }) async {
    final all = await fetchApprovedListings();
    return all.where((l) => l.id != excludeListingId).take(limit).toList();
  }

  // ─── Crop names currently listed (for the Prices tab cross-reference) ─────

  Future<Set<String>> fetchListedCropNames() async {
    try {
      final rows = await _client
          .from('marketplace_listings')
          .select('crop_name')
          .eq('status', 'approved');
      return rows.map((r) => (r['crop_name'] as String).toLowerCase()).toSet();
    } catch (_) {
      return {};
    }
  }

  // ─── Place order — calls the atomic RPC, does NOT swallow errors ──────────
  // Financial write: must throw on failure so the UI can show the real
  // reason (e.g. insufficient stock), same convention as every other
  // money-touching write in this codebase.

  Future<String> placeOrder({
    required String listingId,
    required double quantityKg,
  }) async {
    try {
      final result = await _client.rpc('place_order', params: {
        'p_listing_id': listingId,
        'p_quantity_kg': quantityKg,
      });
      return result as String;
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }
}