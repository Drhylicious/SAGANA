import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/harvest_model.dart';

class HarvestRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  Future<List<HarvestModel>> _fetchHarvestsForFarmer(String farmerId) async {
    try {
      final response = await _client
          .from('harvest_records')
          .select()
          .eq('farmer_id', farmerId)
          .order('harvest_date', ascending: false);
      return response.map((row) => HarvestModel.fromMap(row)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, double>> _fetchHistoryStatsForFarmer(
      String farmerId) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      final response = await _client
          .from('harvest_records')
          .select('quantity_kg, is_synced, harvest_date')
          .eq('farmer_id', farmerId)
          .gte('harvest_date', cutoff.toIso8601String().split('T').first);

      double totalYield = 0;
      int syncedCount = 0;
      final total = response.length;

      for (final row in response) {
        totalYield += (row['quantity_kg'] as num).toDouble();
        if (row['is_synced'] as bool? ?? false) syncedCount++;
      }

      final syncedPercent = total > 0 ? (syncedCount / total) * 100 : 100.0;

      return {
        'total_yield': totalYield,
        'synced_percent': syncedPercent,
      };
    } catch (_) {
      return {'total_yield': 0, 'synced_percent': 100};
    }
  }

  // ─── Recent Harvests ─────────────────────────────────────────────────────────

  Future<List<HarvestModel>> fetchRecentHarvests({int limit = 10}) async {
    final harvests = await _fetchHarvestsForFarmer(_userId);
    return harvests.take(limit).toList();
  }

  // ─── Harvest Stats ────────────────────────────────────────────────────────────

  Future<HarvestStats> fetchStats() async {
    try {
      final now = DateTime.now();
      final startOfSeason = DateTime(now.year, 1, 1);

      final response = await _client
          .from('harvest_records')
          .select('quantity_kg, is_synced, harvest_date')
          .eq('farmer_id', _userId)
          .gte('harvest_date', startOfSeason.toIso8601String());

      int seasonCount = response.length;
      double totalYield = 0;
      int unsyncedCount = 0;

      for (final row in response) {
        totalYield += (row['quantity_kg'] as num).toDouble();
        if (!(row['is_synced'] as bool? ?? false)) unsyncedCount++;
      }

      return HarvestStats(
        seasonCount: seasonCount,
        totalYieldKg: totalYield,
        unsyncedCount: unsyncedCount,
      );
    } catch (_) {
      return HarvestStats.empty;
    }
  }

  // ─── Inventory Batch Count ────────────────────────────────────────────────────

  Future<Map<String, int>> fetchInventoryStats() async {
    try {
      final response = await _client
          .from('inventory_batches')
          .select('status')
          .eq('farmer_id', _userId);

      int total = response.length;
      int lowStock = response
          .where((r) => r['status'] == 'low_stock')
          .length;

      return {'total': total, 'low_stock': lowStock};
    } catch (_) {
      return {'total': 0, 'low_stock': 0};
    }
  }
}

// ─── Fetch harvests for a specific crop ────────────────────────────────────

extension HarvestsForCrop on HarvestRepository {
  Future<List<HarvestModel>> fetchHarvestsForCrop(String cropId) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;
    try {
      final response = await client
          .from('harvest_records')
          .select()
          .eq('farmer_id', userId)
          .eq('crop_id', cropId)
          .order('harvest_date', ascending: false);
      return response.map((row) => HarvestModel.fromMap(row)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<HarvestModel>> fetchHarvestsForFarmer(String farmerId) {
    return _fetchHarvestsForFarmer(farmerId);
  }
}

// ─── Harvest History (all crops, filterable) ───────────────────────────────

extension HarvestHistoryFetch on HarvestRepository {
  /// Fetches all harvest records across all crops, most recent first.
  Future<List<HarvestModel>> fetchAllHarvests() async {
    return _fetchHarvestsForFarmer(_userId);
  }

  Future<List<HarvestModel>> fetchAllHarvestsForFarmer(String farmerId) {
    return _fetchHarvestsForFarmer(farmerId);
  }

  /// Stats for the History screen: 30-day total yield + sync health %.
  Future<Map<String, double>> fetchHistoryStats() async {
    return _fetchHistoryStatsForFarmer(_userId);
  }

  Future<Map<String, double>> fetchHistoryStatsForFarmer(String farmerId) {
    return _fetchHistoryStatsForFarmer(farmerId);
  }
}
