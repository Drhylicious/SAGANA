import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/analytics_model.dart';
import '../services/hive_service.dart';

class AnalyticsRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // ─── Shared error handling with logging ────────────────────────────────────
  Future<T> _safeFetch<T>(String label, Future<T> Function() query, T fallback) async {
    try {
      return await query();
    } catch (e) {
      debugPrint('AnalyticsRepository.$label failed: $e');
      return fallback;
    }
  }

  // ─── Farm Performance (own data) ──────────────────────────────────────────

  Future<FarmPerformanceSummary> fetchFarmPerformance(AnalyticsPeriod period) async {
    return _safeFetch('fetchFarmPerformance', () async {
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

      // Pending, not-yet-synced harvests queued locally in Hive — mirrors
      // HarvestRepository's own merge pattern (fetchStats(), etc.) so a
      // farmer who just logged a harvest while offline sees it reflected
      // here immediately, rather than Analytics silently lagging behind
      // Harvest Hub until the device reconnects and syncs. Scoped to
      // Total Yield / Harvest by Crop only (Option A) — Revenue/Net
      // Profit are untouched, since a pending harvest has no
      // corresponding sale yet.
      //
      // Deliberately NOT routed through _safeFetch — a local Hive read
      // failure shouldn't blank out the already-fetched synced totals
      // sitting above it in this same method.
      try {
        for (final entry in HiveService.getPendingHarvests()) {
          final p = entry.value;
          final harvestDate = DateTime.parse(p['harvest_date'] as String);
          if (period.startDate != null && harvestDate.isBefore(period.startDate!)) {
            continue;
          }
          final qty = (p['quantity_kg'] as num).toDouble();
          final crop = p['crop_name'] as String;
          totalYield += qty;
          byCrop[crop] = (byCrop[crop] ?? 0) + qty;
        }
      } catch (e) {
        debugPrint('AnalyticsRepository.fetchFarmPerformance/pendingHarvests failed: $e');
      }

      // Total revenue — three real farmer income channels, matching
      // DashboardRepository.fetchSummary()'s established pattern exactly:
      // completed marketplace orders, confirmed cooperative sales
      // (member_sales_transactions), and informal/farm-gate sales
      // (informal_sales). No fallback to approved-listing value — that
      // would substitute a farmer's total *listed* value for their actual
      // *earned* value, which is a different metric, not an approximation
      // of this one. Each source runs through its own _safeFetch so one
      // failing can't blank out the other two.
      //
      // AnalyticsPeriod.startDate is open-ended (no upper bound — always
      // "from X to now"), unlike DashboardRepository's fixed-month window,
      // so unlike that method, none of the three queries below need an
      // upper bound; only the lower-bound handling differs per source.
      final marketplaceRevenue = await _safeFetch('fetchFarmPerformance/orders', () async {
        var ordersQuery = _client
            .from('orders')
            .select('total_price')
            .eq('farmer_id', _userId)
            .eq('status', 'completed');
        if (period.startDate != null) {
          ordersQuery = ordersQuery.gte('created_at', period.startDate!.toIso8601String());
        }
        final orderRows = await ordersQuery;
        double revenue = 0;
        for (final row in orderRows) {
          revenue += (row['total_price'] as num).toDouble();
        }
        return revenue;
      }, 0.0);

      // member_sales_transactions.sale_date is a plain DATE column, so the
      // lower bound needs a date-only string, same reasoning as
      // DashboardRepository's dateOnly() helper.
      final cooperativeRevenue = await _safeFetch('fetchFarmPerformance/memberSales', () async {
        String dateOnly(DateTime d) =>
            '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
        var coopQuery = _client
            .from('member_sales_transactions')
            .select('amount')
            .eq('farmer_id', _userId);
        if (period.startDate != null) {
          coopQuery = coopQuery.gte('sale_date', dateOnly(period.startDate!));
        }
        final coopRows = await coopQuery;
        double revenue = 0;
        for (final row in coopRows) {
          revenue += (row['amount'] as num).toDouble();
        }
        return revenue;
      }, 0.0);

      final informalRevenue = await _safeFetch('fetchFarmPerformance/informalSales', () async {
        var informalQuery = _client
            .from('informal_sales')
            .select('amount')
            .eq('farmer_id', _userId);
        if (period.startDate != null) {
          informalQuery = informalQuery.gte('sale_date', period.startDate!.toIso8601String());
        }
        final informalRows = await informalQuery;
        double revenue = 0;
        for (final row in informalRows) {
          revenue += ((row['amount'] as num?)?.toDouble() ?? 0);
        }
        return revenue;
      }, 0.0);

      final totalRevenue = marketplaceRevenue + cooperativeRevenue + informalRevenue;

      // Expenses (best-effort; farmer_expenses table may not exist yet)
      final totalExpenses = await _safeFetch('fetchFarmPerformance/expenses', () async {
        var expenseQuery = _client
            .from('farmer_expenses')
            .select('amount, expense_date')
            .eq('farmer_id', _userId);
        if (period.startDate != null) {
          expenseQuery = expenseQuery.gte('expense_date', period.startDate!.toIso8601String().split('T').first);
        }
        final expenseRows = await expenseQuery;
        double expenses = 0;
        for (final row in expenseRows) {
          expenses += (row['amount'] as num).toDouble();
        }
        return expenses;
      }, 0.0);

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
    }, FarmPerformanceSummary.empty);
  }

  // ─── Recent Transactions (approved listings treated as sales) ─────────────

  // Recent Transactions — same three real income channels as
  // fetchFarmPerformance()'s revenue total above, merged into one
  // chronological list. `reference` is prefixed per source (ORD-/COOP-/
  // INF-) since the three tables don't share a reference-number scheme —
  // this keeps the existing single-string `reference` field usable by
  // _TransactionsCard without any widget change. Each source channel runs
  // through its own _safeFetch, same resilience as the original per-source
  // try/catch: one channel failing can't blank the other two.
  Future<List<TransactionRecord>> fetchRecentTransactions({int limit = 5}) async {
    final ordersList = await _safeFetch('fetchRecentTransactions/orders', () async {
      final rows = await _client
          .from('orders')
          .select('id, quantity_kg, total_price, created_at, marketplace_listings(crop_name)')
          .eq('farmer_id', _userId)
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(limit);
      final List<TransactionRecord> list = [];
      for (final row in rows) {
        final id = row['id'] as String;
        final listing = row['marketplace_listings'] as Map<String, dynamic>?;
        list.add(TransactionRecord(
          id: id,
          cropName: listing?['crop_name'] as String? ?? 'Unknown crop',
          quantityKg: (row['quantity_kg'] as num).toDouble(),
          totalAmount: (row['total_price'] as num).toDouble(),
          date: DateTime.parse(row['created_at'] as String),
          reference: 'ORD-${id.substring(0, 4).toUpperCase()}',
        ));
      }
      return list;
    }, <TransactionRecord>[]);

    final coopList = await _safeFetch('fetchRecentTransactions/memberSales', () async {
      final rows = await _client
          .from('member_sales_transactions')
          .select('id, crop_name, quantity_kg, amount, sale_date')
          .eq('farmer_id', _userId)
          .order('sale_date', ascending: false)
          .limit(limit);
      final List<TransactionRecord> list = [];
      for (final row in rows) {
        final id = row['id'] as String;
        list.add(TransactionRecord(
          id: id,
          cropName: row['crop_name'] as String,
          quantityKg: (row['quantity_kg'] as num).toDouble(),
          totalAmount: (row['amount'] as num).toDouble(),
          date: DateTime.parse(row['sale_date'] as String),
          reference: 'COOP-${id.substring(0, 4).toUpperCase()}',
        ));
      }
      return list;
    }, <TransactionRecord>[]);

    final informalList = await _safeFetch('fetchRecentTransactions/informalSales', () async {
      final rows = await _client
          .from('informal_sales')
          .select('id, crop_name, quantity_kg, amount, sale_date')
          .eq('farmer_id', _userId)
          .order('sale_date', ascending: false)
          .limit(limit);
      final List<TransactionRecord> list = [];
      for (final row in rows) {
        final id = row['id'] as String;
        list.add(TransactionRecord(
          id: id,
          cropName: row['crop_name'] as String,
          quantityKg: (row['quantity_kg'] as num).toDouble(),
          totalAmount: ((row['amount'] as num?)?.toDouble() ?? 0),
          date: DateTime.parse(row['sale_date'] as String),
          reference: 'INF-${id.substring(0, 4).toUpperCase()}',
        ));
      }
      return list;
    }, <TransactionRecord>[]);

    final combined = [...ordersList, ...coopList, ...informalList];
    combined.sort((a, b) => b.date.compareTo(a.date));
    return combined.take(limit).toList();
  }

  // ─── Price Cards with margin ───────────────────────────────────────────────

  Future<List<CropPriceCard>> fetchPriceCards() async {
    return _safeFetch('fetchPriceCards', () async {
      final rows = await _client
          .from('price_records')
          .select('crop_name, price_type, price, previous_price, recorded_at')
          .order('recorded_at', ascending: false);

      // Keyed on (crop_name, price_type), not crop_name alone — matching
      // PriceManagementRepository/FarmerMarketRatesRepository's existing
      // convention. A crop can have more than one concurrent price source
      // (e.g. its SP3 cooperative price and an open-market reference
      // price); collapsing on crop_name alone would arbitrarily pick one
      // and hide the other.
      final Map<String, CropPriceCard> latestByKey = {};
      for (final row in rows) {
        final crop = row['crop_name'] as String;
        final priceType = row['price_type'] as String;
        final key = '$crop|$priceType';
        if (latestByKey.containsKey(key)) continue;
        latestByKey[key] = CropPriceCard(
          cropName: crop,
          priceType: priceType,
          currentPrice: (row['price'] as num).toDouble(),
          previousPrice: row['previous_price'] != null ? (row['previous_price'] as num).toDouble() : null,
        );
      }
      return latestByKey.values.toList();
    }, <CropPriceCard>[]);
  }

  // ─── Price History for a specific crop ─────────────────────────────────────
  // startDate replaces the old fixed `days` window — null means no lower
  // bound (All Time), matching the same nullable-startDate convention
  // fetchFarmPerformance already uses.

  Future<List<PriceHistoryPoint>> fetchPriceHistory(String cropName, {required String priceType, DateTime? startDate}) async {
    return _safeFetch('fetchPriceHistory', () async {
      var query = _client
          .from('price_records')
          .select('price, recorded_at')
          .ilike('crop_name', cropName)
          .eq('price_type', priceType);

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
    }, <PriceHistoryPoint>[]);
  }

  // ─── Planting Forecast (cooperative-wide, from SQL view) ──────────────────

  Future<List<PlantingForecast>> fetchPlantingForecasts() async {
    return _safeFetch('fetchPlantingForecasts', () async {
      final rows = await _client
          .from('crop_planting_forecast')
          .select()
          .order('most_recent_cycle_kg', ascending: false);

      // Join category from crop_master — the coop-wide canonical catalog,
      // readable by any authenticated user. farmer_crops was the previous
      // source, but it's RLS-scoped to each farmer's own rows, so it
      // silently missed any crop the viewing farmer hadn't personally
      // added — falling back to 'Other' for crops that genuinely have a
      // real category, just not in this farmer's own list.
      //
      // Deliberately kept as its own labeled try/catch rather than routed
      // through _safeFetch — its failure semantics differ from the rest
      // of this method: fall back to 'Other' per-crop, not blank the
      // whole forecast list.
      final categoryMap = <String, String>{};
      try {
        final cropRows = await _client.from('crop_master').select('crop_name, category');
        for (final row in cropRows) {
          categoryMap.putIfAbsent(row['crop_name'] as String, () => row['category'] as String? ?? 'Other');
        }
      } catch (e) {
        debugPrint('AnalyticsRepository.fetchPlantingForecasts/cropMaster failed: $e');
      }

      return rows.map((row) {
        final cropName = row['crop_name'] as String;
        return PlantingForecast.fromMap({
          ...row,
          'category': categoryMap[cropName] ?? 'Other',
        });
      }).toList();
    }, <PlantingForecast>[]);
  }

  // ─── Top Selling Crops (coop-wide, last 90 days) ───────────────────────────

  Future<List<TopSellingCrop>> fetchTopSellingCrops({int limit = 5}) async {
    return _safeFetch('fetchTopSellingCrops', () async {
      // Reads the top_harvested_crops view (cooperative-wide,
      // pre-aggregated, RLS-bypassed via view-owner privilege) instead of
      // querying harvest_records directly — see
      // supabase_schema_top_harvested_crops.sql for why. The view already
      // does the SUM/GROUP BY, so this no longer re-aggregates client-side,
      // just sorts and takes the top N.
      final rows = await _client
          .from('top_harvested_crops')
          .select('crop_name, total_kg');

      final sorted = rows.toList()
        ..sort((a, b) => (b['total_kg'] as num).compareTo(a['total_kg'] as num));
      final top = sorted.take(limit).toList();
      final maxVal = top.isEmpty ? 1.0 : (top.first['total_kg'] as num).toDouble();

      return top
          .map((row) => TopSellingCrop(
                cropName: row['crop_name'] as String,
                volumeKg: (row['total_kg'] as num).toDouble(),
                percentOfMax: maxVal > 0
                    ? ((row['total_kg'] as num).toDouble() / maxVal).clamp(0.0, 1.0)
                    : 0,
              ))
          .toList();
    }, <TopSellingCrop>[]);
  }
}