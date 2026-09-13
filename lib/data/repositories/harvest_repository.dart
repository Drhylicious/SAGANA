import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/harvest_model.dart';
import '../models/admin_reports_model.dart';
import '../services/hive_service.dart';
import 'farmer_lookup.dart';

class HarvestRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  // Locally-queued harvests (not yet synced to Supabase) for the CURRENT
  // device's farmer only — never merged in when farmerId is someone else's
  // (e.g. Admin viewing a farmer's history), since the queue is local-only.
  List<HarvestModel> _pendingHarvestModels() {
    return HiveService.getPendingHarvests().map((entry) {
      final p = entry.value;
      return HarvestModel(
        id: entry.key,
        farmerId: _userId,
        cropId: p['crop_id'] as String,
        cropName: p['crop_name'] as String,
        cropCategory: p['crop_category'] as String? ?? 'Other',
        quantityKg: (p['quantity_kg'] as num).toDouble(),
        variety: p['variety'] as String?,
        batchNumber: p['batch_number'] as String?,
        storageLocation: p['storage_location'] as String?,
        notes: p['notes'] as String?,
        harvestDate: DateTime.parse(p['harvest_date'] as String),
        isSynced: false,
        submittedToCooperative: false,
        createdAt: DateTime.now(),
      );
    }).toList();
  }

  // Public accessor so other repositories (FarmerProfileRepository,
  // CropRepository) can reuse this exact pending-harvest source instead
  // of re-deriving their own merge logic — Phase 2 / U1.
  List<HarvestModel> pendingHarvestModels() => _pendingHarvestModels();

  Future<List<HarvestModel>> _fetchHarvestsForFarmer(String farmerId) async {
    List<HarvestModel> synced = [];
    try {
      final response = await _client
          .from('harvest_records')
          .select()
          .eq('farmer_id', farmerId)
          .order('harvest_date', ascending: false);
      synced = response.map((row) => HarvestModel.fromMap(row)).toList();
    } catch (_) {
      synced = [];
    }

    if (farmerId != _userId) return synced;

    final pending = _pendingHarvestModels();
    if (pending.isEmpty) return synced;

    final combined = [...pending, ...synced];
    combined.sort((a, b) => b.harvestDate.compareTo(a.harvestDate));
    return combined;
  }

  Future<Map<String, double>> _fetchHistoryStatsForFarmer(
      String farmerId) async {
    double totalYield = 0;
    int syncedCount = 0;
    int total = 0;

    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      final response = await _client
          .from('harvest_records')
          .select('quantity_kg, is_synced, harvest_date')
          .eq('farmer_id', farmerId)
          .gte('harvest_date', cutoff.toIso8601String().split('T').first);

      total = response.length;
      for (final row in response) {
        totalYield += (row['quantity_kg'] as num).toDouble();
        if (row['is_synced'] as bool? ?? false) syncedCount++;
      }
    } catch (_) {
      // Falls through to the pending-only figures below.
    }

    if (farmerId == _userId) {
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      final pending =
          _pendingHarvestModels().where((h) => h.harvestDate.isAfter(cutoff));
      for (final h in pending) {
        totalYield += h.quantityKg;
        total += 1; // unsynced, so it doesn't add to syncedCount
      }
    }

    final syncedPercent = total > 0 ? (syncedCount / total) * 100 : 100.0;
    return {'total_yield': totalYield, 'synced_percent': syncedPercent};
  }

  // ─── Recent Harvests ─────────────────────────────────────────────────────────

  Future<List<HarvestModel>> fetchRecentHarvests({int limit = 5}) async {
    final harvests = await _fetchHarvestsForFarmer(_userId);
    return harvests.take(limit).toList();
  }

  // ─── Harvest Stats ────────────────────────────────────────────────────────────

  Future<HarvestStats> fetchStats() async {
    final now = DateTime.now();
    final startOfSeason = DateTime(now.year, 1, 1);

    int seasonCount = 0;
    double totalYield = 0;
    int unsyncedCount = 0;

    try {
      final response = await _client
          .from('harvest_records')
          .select('quantity_kg, is_synced, harvest_date')
          .eq('farmer_id', _userId)
          .gte('harvest_date', startOfSeason.toIso8601String());

      seasonCount = response.length;
      for (final row in response) {
        totalYield += (row['quantity_kg'] as num).toDouble();
        if (!(row['is_synced'] as bool? ?? false)) unsyncedCount++;
      }
    } catch (_) {
      // Falls through to the pending-only figures below — an offline
      // farmer should still see their queued harvests reflected here,
      // even if the season-to-date server totals aren't reachable.
    }

    final pending = _pendingHarvestModels()
        .where((h) => h.harvestDate.year == now.year);
    seasonCount += pending.length;
    unsyncedCount += pending.length;
    for (final h in pending) {
      totalYield += h.quantityKg;
    }

    return HarvestStats(
      seasonCount: seasonCount,
      totalYieldKg: totalYield,
      unsyncedCount: unsyncedCount,
    );
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

  // ─── Export support (Phase 7 — Farmer Download Records) ───────────────────
  // Reuses fetchAllHarvests() (already merges synced + offline-queued
  // entries, same pattern every other screen in this repository uses)
  // rather than a parallel query, then filters by date client-side —
  // consistent with the codebase's existing client-side-filtering
  // convention at SP3's current scale.
  Future<HarvestReportData> fetchMyHarvestForExport({
    DateTime? start,
    DateTime? end,
  }) async {
    final all = await fetchAllHarvests();
    final filtered = all.where((h) {
      if (start != null && h.harvestDate.isBefore(start)) return false;
      if (end != null && h.harvestDate.isAfter(end)) return false;
      return true;
    }).toList();
    if (filtered.isEmpty) return HarvestReportData.empty();

    final info = (await fetchFarmerInfoMap(
        Supabase.instance.client, [_userId]))[_userId];
    final harvests = filtered.map((h) {
      return HarvestReportRow(
        id: h.id,
        farmerId: h.farmerId,
        farmerName: info?.fullName ?? 'Unknown Farmer',
        memberId: info?.memberId ?? '—',
        cropName: h.cropName,
        quantityKg: h.quantityKg,
        harvestDate: h.harvestDate,
        submittedToCooperative: h.submittedToCooperative,
        isSynced: h.isSynced,
        batchNumber: h.batchNumber ?? '—',
      );
    }).toList();

    return HarvestReportData(
      totalYieldKg: 0,
      harvestCount: harvests.length,
      unsyncedCount: 0,
      monthlyTrend: const [],
      cropBreakdown: const [],
      harvests: harvests,
    );
  }
}
