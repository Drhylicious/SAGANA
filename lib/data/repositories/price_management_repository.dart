import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/price_record_model.dart';

class PriceManagementRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Fetch latest price per (crop, price_type) ─────────────────────────────
  // Used for the "Live Market Rates" cards grid.
  // Keyed on (crop_id, price_type) rather than crop_name alone, so a crop's
  // Cooperative Market price and its Public Market price both show up as
  // separate cards instead of one collapsing into the other.

  Future<List<PriceRecordModel>> fetchLatestPricePerCrop() async {
    try {
      // Embeds crop_master's image via the real crop_id FK — Price
      // Management only ever references this image, never uploads or
      // stores its own copy. Left-join semantics (crop_id is nullable on
      // very old rows) mean a row with no linked crop just gets a null
      // image rather than being excluded.
      final rows = await _client
          .from('price_records')
          .select('*, crop_master(image_url)')
          .order('recorded_at', ascending: false);

      final Map<String, PriceRecordModel> latest = {};
      for (final row in rows) {
        final key = '${row['crop_id']}_${row['price_type']}';
        if (!latest.containsKey(key)) {
          latest[key] = PriceRecordModel.fromMap(row);
        }
      }
      return latest.values.toList()
        ..sort((a, b) => a.cropName.compareTo(b.cropName));
    } catch (e) {
      debugPrint('PriceManagementRepository.fetchLatestPricePerCrop failed: $e');
      return [];
    }
  }

  // ─── Fetch recent price history (for the history table) ───────────────────

  Future<List<PriceRecordModel>> fetchPriceHistory({int limit = 20}) async {
    try {
      final rows = await _client
          .from('price_records')
          .select()
          .order('recorded_at', ascending: false)
          .limit(limit);
      return rows.map((r) => PriceRecordModel.fromMap(r)).toList();
    } catch (e) {
      debugPrint('PriceManagementRepository.fetchPriceHistory failed: $e');
      return [];
    }
  }

  // ─── Fetch 30-day trend for a specific crop (for mini chart) ──────────────
  // Keyed on crop_id instead of an ilike match against crop_name.

  Future<List<PriceRecordModel>> fetchTrendForCrop(
    String cropId, {
    int days = 30,
  }) async {
    try {
      final cutoff = DateTime.now()
          .subtract(Duration(days: days))
          .toIso8601String();
      final rows = await _client
          .from('price_records')
          .select()
          .eq('crop_id', cropId)
          .gte('recorded_at', cutoff)
          .order('recorded_at', ascending: true);

      if (rows.isNotEmpty) {
        return rows.map((r) => PriceRecordModel.fromMap(r)).toList();
      }

      // Nothing in the last `days` — the crop still has price history,
      // just not recently updated. Fall back to the most recent 10
      // records regardless of age, rather than showing "no history" for
      // a crop that genuinely has data, just outside this window.
      final fallbackRows = await _client
          .from('price_records')
          .select()
          .eq('crop_id', cropId)
          .order('recorded_at', ascending: false)
          .limit(10);

      final fallback =
          fallbackRows.map((r) => PriceRecordModel.fromMap(r)).toList();
      return fallback.reversed.toList();
    } catch (e) {
      debugPrint('PriceManagementRepository.fetchTrendForCrop failed: $e');
      return [];
    }
  }

  // ─── Insert new price record ───────────────────────────────────────────────
  // cropId + cropName are passed together: the caller already has both fresh
  // from the crop_master-backed crop picker (see fetchAvailableCrops).
  // cropName is stored as a point-in-time snapshot and never rewritten later.
  // Also updates previous_price by reading the current latest before inserting.

  Future<PriceRecordModel> upsertPrice({
    required String cropId,
    required String cropName,
    required double price,
    required String priceType,
    required String unit,
    String? source,
    DateTime? effectiveDate,
  }) async {
    final adminId = _client.auth.currentUser?.id;

    // Read current price to store as previous_price
    double? previousPrice;
    try {
      final existing = await _client
          .from('price_records')
          .select('price')
          .eq('crop_id', cropId)
          .eq('price_type', priceType)
          .order('recorded_at', ascending: false)
          .limit(1);
      if (existing.isNotEmpty) {
        previousPrice = (existing.first['price'] as num).toDouble();
      }
    } catch (_) {}

    final row = await _client
        .from('price_records')
        .insert({
          'crop_id':        cropId,
          'crop_name':      cropName.trim(),
          'price':          price,
          'price_type':     priceType,
          'unit':           unit,
          'previous_price': previousPrice,
          'recorded_at':    (effectiveDate ?? DateTime.now()).toIso8601String(),
          'recorded_by':    adminId,
          if (source != null && source.isNotEmpty) 'source': source.trim(),
        })
        .select()
        .single();

    return PriceRecordModel.fromMap(row);
  }

  // ─── Delete a price record ─────────────────────────────────────────────────

  Future<void> deletePriceRecord(String id) async {
    await _client.from('price_records').delete().eq('id', id);
  }

  // ─── Fetch crops available for pricing ─────────────────────────────────────
  // Replaces fetchKnownCropNames(), which only ever returned crops that
  // already had a price on record — meaning a brand-new crop could never
  // get its first price entered. Now sources directly from crop_master, so
  // every active crop (including ones with no price yet) is selectable, and
  // each entry carries its id (needed for the crop_id FK) and crop_type.

  Future<List<Map<String, dynamic>>> fetchAvailableCrops() async {
    try {
      final rows = await _client
          .from('crop_master')
          .select('id, crop_name, crop_type')
          .eq('is_active', true)
          .order('crop_name');
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

  // ─── Live farmer listings, by market type (Phase 6b) ───────────────────────
  // Powers the two "Live Listings" sections. marketplace_listings has no
  // confirmed crop_id FK in this schema history, so each listing's market
  // type is resolved via lower(crop_name) against crop_master — same
  // pattern as approve_crop_request(). Listings for a crop no longer in
  // (or never added to) crop_master default to 'open_market' (Public
  // Market) rather than being silently dropped.
  Future<List<Map<String, dynamic>>> fetchLiveListings() async {
    try {
      final results = await Future.wait([
        _client
            .from('marketplace_listings')
            .select('id, farmer_id, crop_name, variety, volume_kg, '
                'remaining_kg, price_per_kg, photo_url')
            .eq('status', 'approved')
            .order('crop_name'),
        _client.from('crop_master').select('crop_name, crop_type'),
      ]);
      final listings = results[0] as List;
      final cropRows = results[1] as List;
      if (listings.isEmpty) return [];

      final typeByName = <String, String>{
        for (final c in cropRows)
          (c['crop_name'] as String).toLowerCase():
              c['crop_type'] as String? ?? 'open_market',
      };

      return listings.map((r) {
        final row = r as Map<String, dynamic>;
        final cropType =
            typeByName[(row['crop_name'] as String).toLowerCase()] ??
                'open_market';
        return {...row, 'crop_type': cropType};
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // Admin-only, Cooperative-Market-only, price-only edit — enforced inside
  // admin_update_listing_price() (see supabase_schema_admin_edit_listing_price.sql),
  // not just withheld in the UI. Deliberately an RPC rather than a raw
  // .update(), matching this codebase's established precedent that every
  // marketplace_listings write goes through a purpose-built RPC.
  Future<bool> updateListingPrice({
    required String listingId,
    required double newPrice,
  }) async {
    try {
      await _client.rpc('admin_update_listing_price', params: {
        'p_listing_id': listingId,
        'p_new_price': newPrice,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Crop categories (for Buyer's Price tab filter panel) ─────────────────
  // Small, purpose-built addition — not importing Farmer's CropRepository,
  // which would cross a role boundary this whole review has been careful
  // about (CropRepository/farmer_market_rates_repository were both
  // confirmed unused-by-Buyer earlier). Scoped to crop_id → category only,
  // since that's all the filter panel needs.
  Future<Map<String, String>> fetchCropCategories() async {
    try {
      final rows = await _client.from('crop_master').select('id, category');
      return {
        for (final r in rows)
          r['id'] as String: r['category'] as String? ?? 'Other',
      };
    } catch (e) {
      debugPrint('PriceManagementRepository.fetchCropCategories failed: $e');
      return {};
    }
  }

  // ─── Send notification to all farmers after price update ──────────────────
  // Inserts a notification row for every active farmer.
  // Admin-level operation: inserts into notifications table for all farmers.

  Future<void> broadcastPriceNotification({
    required String cropName,
    required double newPrice,
    required String unit,
  }) async {
    try {
      // Fetch all active farmer AND active buyer user IDs. Buyers were
      // previously excluded here — the only code path that ever inserts a
      // type:'price' notification — which meant NotificationFilter.prices
      // could never return anything for any buyer (Buyer review finding
      // 1.2). Buyers now receive the same price-update notification as
      // farmers, for every price change, per business decision.
      final recipients = await _client
          .from('user_roles')
          .select('user_id, role')
          .inFilter('role', ['farmer', 'buyer'])
          .eq('status', 'active');

      if (recipients.isEmpty) return;

      final now = DateTime.now().toIso8601String();
      final notifications = recipients.map((r) {
        final isBuyer = r['role'] == 'buyer';
        // Role-aware body: farmers have an Analytics tab, buyers have a
        // Prices tab — reusing one string for both would point buyers to
        // a tab that doesn't exist for their role.
        final tabHint = isBuyer
            ? 'Check the Prices tab for the latest market rates.'
            : 'Check the Analytics tab for the latest market rates.';
        return {
          'user_id':    r['user_id'] as String,
          'type':       'price',
          'title':      'Price Update: $cropName',
          'body':       'SP3 Admin updated the price of $cropName '
              'to ₱${newPrice.toStringAsFixed(2)}/$unit. $tabHint',
          'is_read':    false,
          'created_at': now,
        };
      }).toList();

      // Batch insert — Supabase accepts a list
      await _client.from('notifications').insert(notifications);
    } catch (_) {
      // Notification failure is non-fatal — price was already saved
    }
  }
}