import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/price_record_model.dart';

class PriceManagementRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Fetch latest price per crop (one row per crop name) ──────────────────
  // Used for the "Live Market Rates" cards grid.

  Future<List<PriceRecordModel>> fetchLatestPricePerCrop() async {
    try {
      final rows = await _client
          .from('price_records')
          .select()
          .order('recorded_at', ascending: false);

      // Deduplicate: keep first (most recent) per crop_name
      final Map<String, PriceRecordModel> latest = {};
      for (final row in rows) {
        final crop = row['crop_name'] as String;
        if (!latest.containsKey(crop)) {
          latest[crop] = PriceRecordModel.fromMap(row);
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

  Future<List<PriceRecordModel>> fetchTrendForCrop(
    String cropName, {
    int days = 30,
  }) async {
    try {
      final cutoff = DateTime.now()
          .subtract(Duration(days: days))
          .toIso8601String();
      final rows = await _client
          .from('price_records')
          .select()
          .ilike('crop_name', cropName)
          .gte('recorded_at', cutoff)
          .order('recorded_at', ascending: true);
      return rows.map((r) => PriceRecordModel.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Insert new price record ───────────────────────────────────────────────
  // Also updates previous_price by reading the current latest before inserting.

  Future<PriceRecordModel> upsertPrice({
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
          .ilike('crop_name', cropName)
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

  // ─── Fetch distinct crop names already in price_records ───────────────────
  // Used to populate the crop name dropdown when adding new price.

  Future<List<String>> fetchKnownCropNames() async {
    try {
      final rows = await _client
          .from('price_records')
          .select('crop_name')
          .order('crop_name', ascending: true);
      return rows
          .map((r) => r['crop_name'] as String)
          .toSet()
          .toList()
        ..sort();
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
