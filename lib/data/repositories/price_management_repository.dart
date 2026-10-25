import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/market_types_service.dart';
import '../services/offline_cache.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/price_record_model.dart';
import 'admin_activity_repository.dart';
import '../models/admin_log_message.dart';

class PriceManagementRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Fetch latest price per (crop, price_type) ─────────────────────────────
  // Used for the "Live Market Rates" cards grid.
  // Keyed on (crop_id, price_type) rather than crop_name alone, so a crop's
  // Cooperative Market price and its Public Market price both show up as
  // separate cards instead of one collapsing into the other.

  Future<List<PriceRecordModel>> fetchLatestPricePerCrop() async {
    try {
      // Embeds crop_master's image + category via the real crop_id FK —
      // Price Management only ever references these, never uploads or
      // stores its own copy. Left-join semantics (crop_id is nullable on
      // very old rows) mean a row with no linked crop just gets nulls
      // rather than being excluded.
      final loaded = await OfflineCache.load(
        screen: 'latest_prices',
        fetch: () => _client
            .from('price_records')
            .select('*, crop_master(image_url, category, is_active)')
            .order('recorded_at', ascending: false),
      );
      // Live rows are already limited by the database (a Buyer is never sent a
      // farmer-only market's prices). A saved snapshot is re-checked against
      // the current rules, so it cannot show prices this account may not see.
      final rows = OfflineCache.servedFromCache('latest_prices')
          ? loaded
                .where(
                  (r) => MarketTypes.instance.visibleToCurrentUser(
                    r['price_type'] as String?,
                  ),
                )
                .toList()
          : loaded;

      final Map<String, PriceRecordModel> latest = {};
      for (final row in rows) {
        // An archived crop (retired from the catalog, e.g. Copra) no longer
        // shows a current price. Its records stay in the database.
        final master = row['crop_master'];
        if (master is Map && master['is_active'] == false) continue;
        final key = '${row['crop_id']}_${row['price_type']}';
        if (!latest.containsKey(key)) {
          latest[key] = PriceRecordModel.fromMap(row);
        }
      }
      return latest.values.toList()
        ..sort((a, b) => a.cropName.compareTo(b.cropName));
    } catch (e) {
      debugPrint(
        'PriceManagementRepository.fetchLatestPricePerCrop failed: $e',
      );
      return [];
    }
  }

  // ─── Fetch 30-day trend for a specific crop (for mini chart) ──────────────
  // Keyed on crop_id instead of an ilike match against crop_name.
  //
  // [priceType] limits the trend to ONE market. A crop can be priced in both
  // markets, and each market has its own price list, so a chart that mixed them
  // would zig-zag between two different prices. Pass it whenever the screen
  // shows a single market's price. Each (crop, market) keeps its own offline
  // copy. The database still decides which markets the signed-in user can read.

  Future<List<PriceRecordModel>> fetchTrendForCrop(
    String cropId, {
    int days = 30,
    String? priceType,
  }) async {
    try {
      final rows = await OfflineCache.load(
        screen: 'price_trend_${cropId}_${priceType ?? 'all'}_$days',
        fetch: () => _fetchTrendRows(cropId, days, priceType),
      );
      return rows.map((r) => PriceRecordModel.fromMap(r)).toList();
    } catch (e) {
      debugPrint('PriceManagementRepository.fetchTrendForCrop failed: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTrendRows(
    String cropId,
    int days,
    String? priceType,
  ) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String();
    var recent = _client.from('price_records').select().eq('crop_id', cropId);
    if (priceType != null) recent = recent.eq('price_type', priceType);
    final rows = await recent
        .gte('recorded_at', cutoff)
        .order('recorded_at', ascending: true);
    if (rows.isNotEmpty) return List<Map<String, dynamic>>.from(rows);

    // Nothing in the last `days` — the crop still has price history,
    // just not recently updated. Fall back to the most recent 10
    // records regardless of age, rather than showing "no history" for
    // a crop that genuinely has data, just outside this window.
    var older = _client.from('price_records').select().eq('crop_id', cropId);
    if (priceType != null) older = older.eq('price_type', priceType);
    final fallbackRows = await older
        .order('recorded_at', ascending: false)
        .limit(10);
    return List<Map<String, dynamic>>.from(fallbackRows.reversed);
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
          'crop_id': cropId,
          'crop_name': cropName.trim(),
          'price': price,
          'price_type': priceType,
          'unit': unit,
          'previous_price': previousPrice,
          'recorded_at': (effectiveDate ?? DateTime.now()).toIso8601String(),
          'recorded_by': adminId,
          if (source != null && source.isNotEmpty) 'source': source.trim(),
        })
        .select()
        .single();

    AdminActivityRepository().log(
      module: 'prices',
      actionType: 'recorded',
      message: AdminLogMessage('adminLogPriceRecorded', {
        'priceType': priceType,
        'crop': cropName.trim(),
        'price': price.toStringAsFixed(2),
        'unit': unit,
      }),
      referenceId: cropId,
    );

    return PriceRecordModel.fromMap(row);
  }

  // ─── Delete a price record ─────────────────────────────────────────────────

  Future<void> deletePriceRecord(String id) async {
    await _client.from('price_records').delete().eq('id', id);
    AdminActivityRepository().log(
      module: 'prices',
      actionType: 'deleted',
      message: const AdminLogMessage('adminLogPriceDeleted'),
      referenceId: id,
    );
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

  // ─── Send notification to all farmers after price update ──────────────────
  // Inserts a notification row for every active farmer.
  // Admin-level operation: inserts into notifications table for all farmers.

  // previousPrice is the price this save replaced (null for a first price), so
  // the notice can say "set", "increased" or "decreased". An unchanged price
  // sends nothing.
  Future<void> broadcastPriceNotification({
    required String cropName,
    required double newPrice,
    required String unit,
    double? previousPrice,
    String? priceType,
  }) async {
    // The notices are written by the database (notify_price_update), so they
    // don't depend on the device's permissions. A failure here does not undo the
    // saved price, but it is logged instead of being silently ignored.
    try {
      await _client.rpc(
        'notify_price_update',
        params: {
          'p_crop_name': cropName,
          'p_new_price': newPrice,
          'p_unit': unit,
          'p_previous_price': previousPrice,
          'p_price_type': priceType,
        },
      );
    } catch (e) {
      debugPrint(
        'PriceManagementRepository.broadcastPriceNotification failed: $e',
      );
    }
  }
}
