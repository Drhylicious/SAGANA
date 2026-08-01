import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/price_record_model.dart';

class PriceManagementRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Fetch latest price per (crop, price_type) ─────────────────────────────
  // Used for the "Live Market Rates" cards grid.
  // Keyed on (crop_id, price_type) rather than crop_name alone, so a crop's
  // SP3 price and its Market Average price both show up as separate cards
  // instead of one collapsing into the other.

  Future<List<PriceRecordModel>> fetchLatestPricePerCrop() async {
    try {
      final rows = await _client
          .from('price_records')
          .select()
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
    } catch (_) {
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
    } catch (_) {
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
      return rows.map((r) => PriceRecordModel.fromMap(r)).toList();
    } catch (_) {
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

  // ─── Send notification to all farmers after price update ──────────────────
  // Inserts a notification row for every active farmer.
  // Admin-level operation: inserts into notifications table for all farmers.

  Future<void> broadcastPriceNotification({
    required String cropName,
    required double newPrice,
    required String unit,
  }) async {
    try {
      // Fetch all active farmer user IDs
      final farmers = await _client
          .from('user_roles')
          .select('user_id')
          .eq('role', 'farmer')
          .eq('status', 'active');

      if (farmers.isEmpty) return;

      final now = DateTime.now().toIso8601String();
      final notifications = farmers
          .map((f) => {
                'user_id':    f['user_id'] as String,
                'type':       'price',
                'title':      'Price Update: $cropName',
                'body':       'SP3 Admin updated the price of $cropName '
                    'to ₱${newPrice.toStringAsFixed(2)}/$unit. '
                    'Check the Analytics tab for the latest market rates.',
                'is_read':    false,
                'created_at': now,
              })
          .toList();

      // Batch insert — Supabase accepts a list
      await _client.from('notifications').insert(notifications);
    } catch (_) {
      // Notification failure is non-fatal — price was already saved
    }
  }
}
