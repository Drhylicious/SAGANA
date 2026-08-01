import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/analytics_model.dart';

class AnalyticsRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // ─── Farm Performance (own data) ──────────────────────────────────────────

  Future<FarmPerformanceSummary> fetchFarmPerformance(AnalyticsPeriod period) async {
    try {
      var query = _client
          .from('harvest_records')
          .select('crop_name, quantity_kg, harvest_date')
          .eq('farmer_id', _userId);

      if (period.startDate != null) {
        query = query.gte('harvest_date', period.startDate!.toIso8601String().split('T').first);
      }

      final harvestRows = await query;

      double totalYield = 0;
      final Map<String, double> byCrop = {};
      for (final row in harvestRows) {
        final qty = (row['quantity_kg'] as num).toDouble();
        totalYield += qty;
        final crop = row['crop_name'] as String;
        byCrop[crop] = (byCrop[crop] ?? 0) + qty;
      }

      // Revenue from approved listings, now scoped to the selected period —
      // was previously unfiltered, so every period chip returned the same
      // total regardless of which one was active. Filtered on updated_at,
      // matching fetchRecentTransactions()'s own convention elsewhere in
      // this file for treating an approved listing's updated_at as its
      // effective transaction date.
      //
      // NOTE: still counts full listed volume for every approved listing,
      // not confirmed-sold quantity — same "approved ≠ sold" gap already
      // flagged on the Home dashboard's earnings calculation. Not fixed
      // here; only the missing date filter was in scope for this pass.
      double totalRevenue = 0;
      try {
        var revenueQuery = _client
            .from('marketplace_listings')
            .select('price_per_kg, volume_kg, status, updated_at')
            .eq('farmer_id', _userId)
            .eq('status', 'approved');
        if (period.startDate != null) {
          revenueQuery = revenueQuery.gte('updated_at', period.startDate!.toIso8601String());
        }
        final listingRows = await revenueQuery;
        for (final row in listingRows) {
          totalRevenue += (row['price_per_kg'] as num).toDouble() * (row['volume_kg'] as num).toDouble();
        }
      } catch (_) {}

      // Expenses (best-effort; farmer_expenses table may not exist yet)
      double totalExpenses = 0;
      try {
        var expenseQuery = _client
            .from('farmer_expenses')
            .select('amount, expense_date')
            .eq('farmer_id', _userId);
        if (period.startDate != null) {
          expenseQuery = expenseQuery.gte('expense_date', period.startDate!.toIso8601String().split('T').first);
        }
        final expenseRows = await expenseQuery;
        for (final row in expenseRows) {
          totalExpenses += (row['amount'] as num).toDouble();
        }
      } catch (_) {}

      final maxQty = byCrop.values.isEmpty ? 1.0 : byCrop.values.reduce((a, b) => a > b ? a : b);
      final breakdown = byCrop.entries
          .map((e) => CropYieldBreakdown(
                cropName: e.key,
                quantityKg: e.value,
                percentOfMax: maxQty > 0 ? (e.value / maxQty).clamp(0.0, 1.0) : 0,
              ))
          .toList()
        ..sort((a, b) => b.quantityKg.compareTo(a.quantityKg));

      return FarmPerformanceSummary(
        totalYieldKg: totalYield,
        totalRevenue: totalRevenue,
        totalExpenses: totalExpenses,
        cropBreakdown: breakdown.take(5).toList(),
      );
    } catch (_) {
      return FarmPerformanceSummary.empty;
    }
  }

  // ─── Recent Transactions (approved listings treated as sales) ─────────────

  Future<List<TransactionRecord>> fetchRecentTransactions({int limit = 5}) async {
    try {
      final rows = await _client
          .from('marketplace_listings')
          .select('id, crop_name, volume_kg, price_per_kg, updated_at')
          .eq('farmer_id', _userId)
          .eq('status', 'approved')
          .order('updated_at', ascending: false)
          .limit(limit);

      return rows.map((row) {
        final qty = (row['volume_kg'] as num).toDouble();
        final price = (row['price_per_kg'] as num).toDouble();
        final id = row['id'] as String;
        return TransactionRecord(
          id: id,
          cropName: row['crop_name'] as String,
          quantityKg: qty,
          totalAmount: qty * price,
          date: DateTime.parse(row['updated_at'] as String),
          reference: 'TR-${id.substring(0, 4).toUpperCase()}',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Price Cards with margin ───────────────────────────────────────────────

  Future<List<CropPriceCard>> fetchPriceCards() async {
    try {
      final rows = await _client
          .from('price_records')
          .select('crop_name, price, previous_price, recorded_at')
          .order('recorded_at', ascending: false);

      final Map<String, CropPriceCard> latestByCrop = {};
      for (final row in rows) {
        final crop = row['crop_name'] as String;
        if (latestByCrop.containsKey(crop)) continue;
        latestByCrop[crop] = CropPriceCard(
          cropName: crop,
          currentPrice: (row['price'] as num).toDouble(),
          previousPrice: row['previous_price'] != null ? (row['previous_price'] as num).toDouble() : null,
        );
      }
      return latestByCrop.values.toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Price History for a specific crop ─────────────────────────────────────
  // startDate replaces the old fixed `days` window — null means no lower
  // bound (All Time), matching the same nullable-startDate convention
  // fetchFarmPerformance already uses.

  Future<List<PriceHistoryPoint>> fetchPriceHistory(String cropName, {DateTime? startDate}) async {
    try {
      var query = _client
          .from('price_records')
          .select('price, recorded_at')
          .ilike('crop_name', cropName);

      if (startDate != null) {
        query = query.gte('recorded_at', startDate.toIso8601String());
      }

      final rows = await query.order('recorded_at', ascending: true);

      return rows
          .map((row) => PriceHistoryPoint(
                date: DateTime.parse(row['recorded_at'] as String),
                price: (row['price'] as num).toDouble(),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Planting Forecast (cooperative-wide, from SQL view) ──────────────────

  Future<List<PlantingForecast>> fetchPlantingForecasts() async {
    try {
      final rows = await _client
          .from('crop_planting_forecast')
          .select()
          .order('most_recent_cycle_kg', ascending: false);

      // Join category from farmer_crops (best-effort, first match per crop name)
      final categoryMap = <String, String>{};
      try {
        final cropRows = await _client.from('farmer_crops').select('crop_name, category');
        for (final row in cropRows) {
          categoryMap.putIfAbsent(row['crop_name'] as String, () => row['category'] as String? ?? 'Other');
        }
      } catch (_) {}

      return rows.map((row) {
        final cropName = row['crop_name'] as String;
        return PlantingForecast.fromMap({
          ...row,
          'category': categoryMap[cropName] ?? 'Other',
        });
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Top Selling Crops (coop-wide, last 90 days) ───────────────────────────

  Future<List<TopSellingCrop>> fetchTopSellingCrops({int limit = 5}) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      final rows = await _client
          .from('harvest_records')
          .select('crop_name, quantity_kg')
          .gte('harvest_date', cutoff.toIso8601String().split('T').first);

      final Map<String, double> totals = {};
      for (final row in rows) {
        final crop = row['crop_name'] as String;
        totals[crop] = (totals[crop] ?? 0) + (row['quantity_kg'] as num).toDouble();
      }

      final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final top = sorted.take(limit).toList();
      final maxVal = top.isEmpty ? 1.0 : top.first.value;

      return top
          .map((e) => TopSellingCrop(
                cropName: e.key,
                volumeKg: e.value,
                percentOfMax: maxVal > 0 ? (e.value / maxVal).clamp(0.0, 1.0) : 0,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }
}