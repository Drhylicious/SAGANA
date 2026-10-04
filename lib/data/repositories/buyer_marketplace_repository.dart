import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/buyer_listing_model.dart';
import '../models/price_record_model.dart';
import 'price_management_repository.dart';
import '../services/auth_service.dart';
import 'crop_lookup.dart';

/// Read-only, buyer-scoped access to the marketplace. Only ever returns
/// approved listings — buyers have no reason to see, and RLS gives them
/// no ability to see, pending/rejected listings.
/// Deliberately its own repository rather than reusing AdminListingRepository,
/// matching the codebase's existing precedent of one repository per role
/// against the same table (listing_repository.dart for farmer-own-listings
/// vs admin_listing_repository.dart for admin-all-listings already does this).
class BuyerMarketplaceRepository {
  final SupabaseClient _client = Supabase.instance.client;
  final PriceManagementRepository _priceRepo = PriceManagementRepository();

  static const List<String> _priceTypePriority = [
    'open_market',
    'sp3_cooperative',
  ];

  // external market price first (open_market) since that reflects what a
  // buyer should expect to pay; sp3_cooperative is SP3's farmgate
  // procurement rate to farmers, not a consumer price, so it's used only
  // as a last-resort fallback when no market price exists.
  Map<String, double> _resolvePriceMap(List<PriceRecordModel> prices) {
    final byCrop = <String, Map<String, double>>{};
    for (final p in prices) {
      final key = p.cropName.toLowerCase();
      (byCrop[key] ??= {})[p.priceType] = p.price;
    }

    final resolved = <String, double>{};
    for (final entry in byCrop.entries) {
      final byType = entry.value;
      for (final type in _priceTypePriority) {
        if (byType.containsKey(type)) {
          resolved[entry.key] = byType[type]!;
          break;
        }
      }
      resolved[entry.key] ??= byType.values.first;
    }
    return resolved;
  }

  // ─── Shared price-map fetch (Phase 5, item 1) ──────────────────────────────
  // The only enrichment step that was byte-for-byte identical in both
  // fetchApprovedListings() and fetchListingById() — same bulk fetch, same
  // resolution logic, same try/catch, regardless of whether the caller
  // needs prices for many listings or just one (fetchLatestPricePerCrop()
  // already returns every crop's prices in one call either way, so there's
  // no bulk-vs-single shape difference here, unlike batch/category below).
  Future<Map<String, double>> _fetchPriceMap() async {
    try {
      return _resolvePriceMap(await _priceRepo.fetchLatestPricePerCrop());
    } catch (e) {
      debugPrint(
        'BuyerMarketplaceRepository: price lookup failed ($e) — '
        'market_ref_price will be missing',
      );
      return {};
    }
  }

  // offset added for real pagination (Buyer review finding 2.2) — previously
  // `limit` alone could only ever return the first N rows; there was no way
  // to fetch page 2+. `.range()` supports both in one call and is fully
  // backward compatible: existing callers passing only `limit` still get
  // rows 0..limit-1, identical to before, since offset defaults to 0.
  Future<List<BuyerListingModel>> fetchApprovedListings({
    int? limit,
    int offset = 0,
  }) async {
    try {
      final query = _client
          .from('marketplace_listings')
          .select(
            'id, crop_name, crop_id, variety, volume_kg, remaining_kg, price_per_kg, '
            'inventory_batch_id, photo_url, created_at, farmer_id, crop_type',
          )
          .eq('status', 'approved');

      final ordered = query.order('created_at', ascending: false);
      final rows = limit != null
          ? await ordered.range(offset, offset + limit - 1)
          : await ordered;

      if (rows.isEmpty) return [];

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
              .select('id, available_kg, status, crop_type')
              .inFilter('id', batchIds);
          for (final b in batchRows) {
            batchMap[b['id'] as String] = b;
          }
        } catch (e) {
          debugPrint(
            'BuyerMarketplaceRepository.fetchApprovedListings: '
            'batch lookup failed ($e) — available_kg will be missing',
          );
        }
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
      } catch (e) {
        debugPrint(
          'BuyerMarketplaceRepository.fetchApprovedListings: '
          'category lookup failed ($e) — categories will be missing',
        );
      }

      // ── Canonical crop names (Phase D — merges historical name variants,
      // e.g. "Rice (Palay)" vs "Palay", under one display name) ───────────
      final cropIds = rows
          .map((r) => r['crop_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final canonicalCropNames = await fetchCropNameMap(_client, cropIds);

      // ── Market reference prices (reused read-only, zero new code) ────────
      final priceMap = await _fetchPriceMap();

      // ── Units sold (Buyer Browse-tab rework, Phase 3) — own try/catch so
      // a missing/broken view degrades to 0 rather than failing the whole
      // listings fetch (this method's outer catch returns [] on any
      // uncaught exception).
      final soldMap = <String, double>{};
      try {
        final listingIds = rows.map((r) => r['id'] as String).toList();
        final soldRows = await _client
            .from('marketplace_listing_units_sold')
            .select('listing_id, sold_kg')
            .inFilter('listing_id', listingIds);
        for (final s in soldRows) {
          soldMap[s['listing_id'] as String] = (s['sold_kg'] as num).toDouble();
        }
      } catch (e) {
        debugPrint(
          'BuyerMarketplaceRepository.fetchApprovedListings: '
          'units-sold lookup failed ($e) — sold_kg will default to 0',
        );
      }

      return rows.map((r) {
        final batchId = r['inventory_batch_id'] as String?;
        final batch = batchId != null ? batchMap[batchId] : null;
        final cropNameLower = (r['crop_name'] as String).toLowerCase();
        final cropId = r['crop_id'] as String?;

        return BuyerListingModel.fromMap({
          ...r,
          'category': categoryMap[cropNameLower],
          'available_kg': batch?['available_kg'],
          // marketplace_listings.crop_type is the persisted, authoritative
          // value (set by the trigger in
          // supabase_schema_harvest_market_type_persistence.sql at
          // creation time) — the batch's own crop_type is only a fallback
          // for the rare pre-migration row that predates that column, or
          // a listing whose inventory_batch_id is null. Reading only the
          // batch value (as this used to) showed "Not yet assigned" for
          // any listing without a linked batch, even though the listing
          // itself already had a correct crop_type.
          'market_type': r['crop_type'] ?? batch?['crop_type'],
          'market_ref_price': priceMap[cropNameLower],
          'canonical_crop_name': cropId != null
              ? canonicalCropNames[cropId]
              : null,
          'sold_kg': soldMap[r['id'] as String],
        });
      }).toList();
    } catch (e) {
      debugPrint('BuyerMarketplaceRepository.fetchApprovedListings failed: $e');
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
            'inventory_batch_id, photo_url, description, created_at, farmer_id, crop_type',
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
              .select(
                'available_kg, status, batch_number, harvest_record_id, crop_type',
              )
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
        } catch (e) {
          debugPrint(
            'BuyerMarketplaceRepository.fetchListingById: '
            'batch/harvest lookup failed ($e)',
          );
        }
      }

      String? category;
      try {
        final crop = await _client
            .from('crop_master')
            .select('category')
            .ilike('crop_name', row['crop_name'] as String)
            .maybeSingle();
        category = crop?['category'] as String?;
      } catch (e) {
        debugPrint(
          'BuyerMarketplaceRepository.fetchListingById: '
          'category lookup failed ($e)',
        );
      }

      final priceMap = await _fetchPriceMap();
      final marketRefPrice =
          priceMap[(row['crop_name'] as String).toLowerCase()];

      double soldKg = 0;
      try {
        final soldRow = await _client
            .from('marketplace_listing_units_sold')
            .select('sold_kg')
            .eq('listing_id', listingId)
            .maybeSingle();
        soldKg = (soldRow?['sold_kg'] as num?)?.toDouble() ?? 0;
      } catch (e) {
        debugPrint(
          'BuyerMarketplaceRepository.fetchListingById: '
          'units-sold lookup failed ($e) — sold_kg will default to 0',
        );
      }

      return BuyerListingModel.fromMap({
        ...row,
        'category': category,
        'available_kg': batch?['available_kg'],
        'batch_number': batch?['batch_number'],
        'harvest_date': harvestDate?.toIso8601String(),
        // Same fix as fetchApprovedListings() — prefer the listing's own
        // persisted crop_type over the batch join.
        'market_type': row['crop_type'] ?? batch?['crop_type'],
        'market_ref_price': marketRefPrice,
        'sold_kg': soldKg,
      });
    } catch (e) {
      debugPrint('BuyerMarketplaceRepository.fetchListingById failed: $e');
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
    } catch (e) {
      debugPrint('BuyerMarketplaceRepository.fetchListedCropNames failed: $e');
      return {};
    }
  }

  // ─── Bulk stock revalidation (for pre-checkout refresh) ───────────────────
  // Buyer review finding 2.4: cart quantities are bounded by a snapshot of
  // remaining_kg taken at add-to-cart time, which can go stale by checkout.
  // place_order()'s own server-side FOR UPDATE check is the actual
  // authority and already prevents any overselling — this method doesn't
  // change that. It exists so a future UI step (not part of this phase) can
  // show the buyer an accurate "still available" number before they commit,
  // in one query instead of one round-trip per cart item.
  Future<Map<String, double>> fetchCurrentRemainingKg(
    List<String> listingIds,
  ) async {
    if (listingIds.isEmpty) return {};
    try {
      final rows = await _client
          .from('marketplace_listings')
          .select('id, remaining_kg')
          .inFilter('id', listingIds);
      return {
        for (final r in rows)
          r['id'] as String: (r['remaining_kg'] as num).toDouble(),
      };
    } catch (e) {
      debugPrint(
        'BuyerMarketplaceRepository.fetchCurrentRemainingKg failed: $e',
      );
      return {};
    }
  }

  // ─── Place order — calls the atomic RPC, does NOT swallow errors ──────────
  // Financial write: must throw on failure so the UI can show the real
  // reason (e.g. insufficient stock), same convention as every other
  // money-touching write in this codebase.

  // fulfillmentMethod/delivery* — Checkout + My Addresses (Phase 5):
  // place_order() now accepts fulfillment atomically with order creation
  // (supabase_schema_checkout_fulfillment.sql). Defaults to 'pickup'/null
  // so any caller not yet updated to pass these (none remain after Phase
  // 6, but this keeps the signature itself backward compatible) behaves
  // exactly as before.
  Future<String> placeOrder({
    required String listingId,
    required double quantityKg,
    String fulfillmentMethod = 'pickup',
    String? deliveryAddress,
    double? deliveryLatitude,
    double? deliveryLongitude,
    String? deliveryContactNumber,
    String? deliveryNotes,
    String? deliveryRecipientName,
    String? deliveryLabel,
  }) async {
    await AuthService.requireActiveMembership();
    try {
      final result = await _client.rpc(
        'place_order',
        params: {
        'p_listing_id': listingId,
        'p_quantity_kg': quantityKg,
          'p_fulfillment_method': fulfillmentMethod,
          'p_delivery_address': deliveryAddress,
          'p_delivery_latitude': deliveryLatitude,
          'p_delivery_longitude': deliveryLongitude,
          'p_delivery_contact_number': deliveryContactNumber,
          'p_delivery_notes': deliveryNotes,
          'p_delivery_recipient_name': deliveryRecipientName,
          'p_delivery_label': deliveryLabel,
        },
      );
      return result as String;
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }
}