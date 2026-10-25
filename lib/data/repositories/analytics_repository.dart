import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/offline_cache.dart';
import '../../core/utils/order_reference.dart';
import '../../core/utils/quantity_utils.dart';
import '../models/analytics_model.dart';
import '../services/hive_service.dart';
import 'crop_lookup.dart';
import 'expense_repository.dart';

// ─── Shared helpers ───────────────────────────────────────────────────────────

/// `2026-10-01` — the bound for a plain DATE column (harvest_date,
/// expense_date, member_sales_transactions.sale_date).
String _dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The bound for a TIMESTAMPTZ column (orders.created_at, informal_sales
/// .sale_date, market_linking_programs.completed_at, price_records
/// .recorded_at). A local DateTime printed without an offset is read by
/// Postgres as UTC, which would start a Philippine "This Month" eight hours
/// late; sending the real instant keeps the boundary at local midnight.
String _instant(DateTime d) => d.toUtc().toIso8601String();

/// Stable offline-cache key part for a period start: the day, or `any`.
String _periodKey(DateTime? start) => start == null ? 'any' : _dateOnly(start);

/// Adds peso amounts in whole centavos, so a long list of 2-decimal values
/// never drifts (0.1 + 0.2 stays 0.30). A missing amount counts as 0.
double _sumMoney(Iterable<num?> amounts) {
  var cents = 0;
  for (final a in amounts) {
    cents += ((a ?? 0) * 100).round();
  }
  return cents / 100;
}

/// Kilograms of a completed Market Linking round: the confirmed volume, else
/// what the buyer asked for, else the enrolled volume — the same order Home's
/// earnings and Transaction History use.
@visibleForTesting
double marketLinkingQuantityOf(Map<String, dynamic> row) =>
    (row['confirmed_volume_kg'] as num?)?.toDouble() ??
    (row['requested_volume_kg'] as num?)?.toDouble() ??
    (row['volume_kg'] as num?)?.toDouble() ??
    0;

/// Pesos earned by a completed Market Linking round, to the centavo, or null
/// when the round has no price yet (Home's earnings skip such a round too).
@visibleForTesting
double? marketLinkingAmountOf(Map<String, dynamic> row) {
  final price = (row['price_per_kg'] as num?)?.toDouble();
  if (price == null) return null;
  return moneyOf(marketLinkingQuantityOf(row), price);
}

/// Records that a source could not be read (and had no saved copy), so the
/// screen can say figures may be incomplete rather than show a silent zero.
class _LoadFailures {
  bool any = false;
}

class AnalyticsRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // ─── Shared error handling with logging ────────────────────────────────────
  Future<T> _safeFetch<T>(
    String label,
    Future<T> Function() query,
    T fallback,
  ) async {
    try {
      return await query();
    } catch (e) {
      debugPrint('AnalyticsRepository.$label failed: $e');
      return fallback;
    }
  }

  /// [_safeFetch] that also notes the failure in [failures].
  Future<T> _source<T>(
    _LoadFailures failures,
    String label,
    Future<T> Function() query,
    T fallback,
  ) async {
    try {
      return await query();
    } catch (e) {
      debugPrint('AnalyticsRepository.$label failed: $e');
      failures.any = true;
      return fallback;
    }
  }

  // ─── Farm Performance (own data) ──────────────────────────────────────────

  /// OfflineCache key for the synced harvest rows of [period] (matches the key
  /// written by fetchFarmPerformance), so the farmer analytics screen can show the notice.
  static String farmPerformanceCacheScreen(AnalyticsPeriod period) =>
      'analytics_harvests_${_periodKey(period.startDate)}';

  /// The other OfflineCache keys fetchFarmPerformance writes for [period]
  /// (revenue channels and expenses), for the screen notice.
  static List<String> farmPerformanceOtherCacheScreens(
    AnalyticsPeriod period,
  ) {
    final key = _periodKey(period.startDate);
    return [
      'analytics_orders_$key',
      'analytics_coop_sales_$key',
      'analytics_informal_sales_$key',
      'analytics_market_linking_$key',
      'analytics_expenses_$key',
    ];
  }

  Future<FarmPerformanceSummary> fetchFarmPerformance(
    AnalyticsPeriod period,
  ) async {
    return _safeFetch('fetchFarmPerformance', () async {
      final failures = _LoadFailures();
      final start = period.startDate;
      final key = _periodKey(start);

      // Harvests — its own failure mode: a harvest read that fails must not
      // blank the revenue and expense figures below, which come from other
      // tables.
      final harvestRows = await _source(failures, 'harvests', () async {
        var query = _client
            .from('harvest_records')
            .select('crop_id, crop_name, quantity_kg, unit, harvest_date')
            .eq('farmer_id', _userId);
        if (start != null) {
          query = query.gte('harvest_date', _dateOnly(start));
        }
        return OfflineCache.load(
          screen: farmPerformanceCacheScreen(period),
          fetch: () => query,
        );
      }, <Map<String, dynamic>>[]);

      double totalYield = 0;
      // Harvests in another unit, left out of the kg figures below.
      var otherUnitHarvests = 0;
      // Accumulated per harvest_records.crop_id (== farmer_crops.id), not
      // per raw crop_name text, so two differently-spelled crop_master
      // catalog entries for the same real crop (e.g. a legacy "Palay" /
      // "Rice (Palay)" split) are grouped as one before display — see the
      // canonical-name resolution pass below. rawNameByCropId is the
      // fallback if that resolution can't find a match for a given id.
      final Map<String, double> qtyByCropId = {};
      final Map<String, String> rawNameByCropId = {};

      void addHarvest({
        required String? unit,
        required num? quantity,
        required String? cropId,
        required String? cropName,
      }) {
        // Total Yield and Harvest by Crop are kg figures: a harvest measured
        // in another unit is not added to them (units are never mixed).
        if (!isKg(unit)) {
          otherUnitHarvests++;
          return;
        }
        final qty = quantity?.toDouble() ?? 0;
        final rawName = cropName ?? 'Unknown crop';
        // A harvest with no crop id is still the farmer's: group it by name
        // rather than dropping it (or failing the whole summary).
        final id = cropId ?? 'name:$rawName';
        totalYield += qty;
        qtyByCropId[id] = (qtyByCropId[id] ?? 0) + qty;
        rawNameByCropId.putIfAbsent(id, () => rawName);
      }

      for (final row in harvestRows) {
        addHarvest(
          unit: row['unit'] as String?,
          quantity: row['quantity_kg'] as num?,
          cropId: row['crop_id'] as String?,
          cropName: row['crop_name'] as String?,
        );
      }

      // Pending, not-yet-synced harvests queued locally in Hive — mirrors
      // HarvestRepository's own merge pattern (fetchStats(), etc.) so a
      // farmer who just logged a harvest while offline sees it reflected
      // here immediately, rather than Analytics silently lagging behind
      // Harvest Hub until the device reconnects and syncs. Scoped to
      // Total Yield / Harvest by Crop only — Revenue/Net Profit are
      // untouched, since a pending harvest has no corresponding sale yet.
      // Pending entries carry their own crop_id (HarvestEntryRepository
      // queues it alongside crop_name), so they fold into the same
      // qtyByCropId map and get canonicalized exactly like synced rows.
      //
      // Deliberately NOT routed through _source — a local Hive read failure
      // shouldn't blank out the already-fetched synced totals above it.
      try {
        for (final entry in HiveService.getPendingHarvests()) {
          final p = entry.value;
          final harvestDate = DateTime.parse(p['harvest_date'] as String);
          if (start != null && harvestDate.isBefore(start)) continue;
          addHarvest(
            unit: p['unit'] as String?,
            quantity: p['quantity_kg'] as num?,
            cropId: p['crop_id'] as String?,
            cropName: p['crop_name'] as String?,
          );
        }
      } catch (e) {
        debugPrint(
          'AnalyticsRepository.fetchFarmPerformance/pendingHarvests failed: $e',
        );
      }

      // Resolve canonical crop_master.crop_name for every accumulated
      // crop_id via the same two-hop path (crop_id -> farmer_crops.id ->
      // farmer_crops.crop_master_id -> crop_master.crop_name)
      // crop_lookup.dart already provides for Admin Reports / Farmer
      // Details. Kept outside _source: a failure here degrades to
      // grouping by each id's raw crop_name (the same COALESCE fallback
      // the underlying SQL views use), never to a blank breakdown.
      final Map<String, double> byCrop = {};
      try {
        final realIds = qtyByCropId.keys
            .where((id) => !id.startsWith('name:'))
            .toList();
        final farmerCropToMaster = await fetchFarmerCropToCropMasterMap(
          _client,
          realIds,
        );
        final masterNames = await fetchCropNameMap(
          _client,
          farmerCropToMaster.values.toSet().toList(),
        );
        qtyByCropId.forEach((cropId, qty) {
          final masterId = farmerCropToMaster[cropId];
          final canonicalName = masterId != null
              ? (masterNames[masterId] ?? rawNameByCropId[cropId]!)
              : rawNameByCropId[cropId]!;
          byCrop[canonicalName] = (byCrop[canonicalName] ?? 0) + qty;
        });
      } catch (e) {
        debugPrint(
          'AnalyticsRepository.fetchFarmPerformance/cropResolution failed: $e',
        );
        byCrop.clear();
        qtyByCropId.forEach((cropId, qty) {
          final rawName = rawNameByCropId[cropId]!;
          byCrop[rawName] = (byCrop[rawName] ?? 0) + qty;
        });
      }

      // Total revenue — the four real farmer income channels, the same four
      // Home's earnings and Transaction History count: completed marketplace
      // orders, confirmed cooperative sales (member_sales_transactions),
      // informal/farm-gate sales (informal_sales) and completed Market
      // Linking rounds. Only a COMPLETED order counts as a sale; a pending,
      // approved, cancelled or rejected order is never revenue. No fallback
      // to approved-listing value — that would substitute a farmer's total
      // *listed* value for their actual *earned* value. Each source runs
      // through its own _source so one failing can't blank out the others.
      //
      // AnalyticsPeriod.startDate is open-ended (no upper bound — always
      // "from X to now"), so only the lower-bound handling differs per
      // source (a DATE column takes a day, a TIMESTAMPTZ takes an instant).
      final marketplaceRevenue = await _source(failures, 'orders', () async {
        var ordersQuery = _client
            .from('orders')
            .select('total_price')
            .eq('farmer_id', _userId)
            .eq('status', 'completed');
        if (start != null) {
          ordersQuery = ordersQuery.gte('created_at', _instant(start));
        }
        final orderRows = await OfflineCache.load(
          screen: 'analytics_orders_$key',
          fetch: () => ordersQuery,
        );
        return _sumMoney(orderRows.map((r) => r['total_price'] as num?));
      }, 0.0);

      final cooperativeRevenue = await _source(failures, 'memberSales', () async {
        var coopQuery = _client
            .from('member_sales_transactions')
            .select('amount')
            .eq('farmer_id', _userId);
        if (start != null) {
          coopQuery = coopQuery.gte('sale_date', _dateOnly(start));
        }
        final coopRows = await OfflineCache.load(
          screen: 'analytics_coop_sales_$key',
          fetch: () => coopQuery,
        );
        return _sumMoney(coopRows.map((r) => r['amount'] as num?));
      }, 0.0);

      final informalRevenue = await _source(failures, 'informalSales', () async {
        var informalQuery = _client
            .from('informal_sales')
            .select('amount')
            .eq('farmer_id', _userId);
        if (start != null) {
          informalQuery = informalQuery.gte('sale_date', _instant(start));
        }
        final informalRows = await OfflineCache.load(
          screen: 'analytics_informal_sales_$key',
          fetch: () => informalQuery,
        );
        return _sumMoney(informalRows.map((r) => r['amount'] as num?));
      }, 0.0);

      // Market Linking (Ginger, run with DA-AMAD): income counts once the
      // round is completed, dated by completed_at — the same rule Home uses.
      final marketLinkingRevenue = await _source(failures, 'marketLinking', () async {
        var mlQuery = _client
            .from('market_linking_programs')
            .select(
              'confirmed_volume_kg, requested_volume_kg, volume_kg, '
              'price_per_kg, completed_at',
            )
            .eq('farmer_id', _userId)
            .eq('status', 'completed');
        if (start != null) {
          mlQuery = mlQuery.gte('completed_at', _instant(start));
        }
        final mlRows = await OfflineCache.load(
          screen: 'analytics_market_linking_$key',
          fetch: () => mlQuery,
        );
        return _sumMoney(mlRows.map(marketLinkingAmountOf));
      }, 0.0);

      final totalRevenue = _sumMoney([
        marketplaceRevenue,
        cooperativeRevenue,
        informalRevenue,
        marketLinkingRevenue,
      ]);

      // Expenses — the same definition My Expenses and the Profile tile use:
      // subsidized entries (covered by MAO/SP3, recorded at ₱0) are excluded,
      // and expenses still queued on this device are included.
      final syncedExpenses = await _source(failures, 'expenses', () async {
        var expenseQuery = _client
            .from('farmer_expenses')
            .select('amount')
            .eq('farmer_id', _userId)
            .eq('is_subsidy', false);
        if (start != null) {
          expenseQuery = expenseQuery.gte('expense_date', _dateOnly(start));
        }
        final expenseRows = await OfflineCache.load(
          screen: 'analytics_expenses_$key',
          fetch: () => expenseQuery,
        );
        return _sumMoney(expenseRows.map((r) => r['amount'] as num?));
      }, 0.0);

      var pendingExpenses = 0.0;
      try {
        pendingExpenses = _sumMoney(
          ExpenseRepository().pendingExpenseModels().where(
            (e) =>
                !e.isSubsidy &&
                (start == null || !e.expenseDate.isBefore(start)),
          ).map((e) => e.amount),
        );
      } catch (e) {
        debugPrint(
          'AnalyticsRepository.fetchFarmPerformance/pendingExpenses failed: $e',
        );
      }
      final totalExpenses = _sumMoney([syncedExpenses, pendingExpenses]);

      final maxQty = byCrop.values.isEmpty
          ? 1.0
          : byCrop.values.reduce((a, b) => a > b ? a : b);
      final breakdown =
          byCrop.entries
              .map(
                (e) => CropYieldBreakdown(
                  cropName: e.key,
                  quantityKg: roundQuantity(e.value),
                  percentOfMax: maxQty > 0
                      ? (e.value / maxQty).clamp(0.0, 1.0)
                      : 0,
                ),
              )
              .toList()
            ..sort((a, b) => b.quantityKg.compareTo(a.quantityKg));

      return FarmPerformanceSummary(
        totalYieldKg: roundQuantity(totalYield),
        totalRevenue: totalRevenue,
        totalExpenses: totalExpenses,
        cropBreakdown: breakdown.take(5).toList(),
        otherUnitHarvestCount: otherUnitHarvests,
        hasLoadError: failures.any,
      );
    }, const FarmPerformanceSummary(
      totalYieldKg: 0,
      totalRevenue: 0,
      totalExpenses: 0,
      cropBreakdown: [],
      hasLoadError: true,
    ));
  }

  // ─── Recent Transactions (the four selling channels) ──────────────────────

  // Recent Transactions — the same four real income channels as
  // fetchFarmPerformance()'s revenue total above (and Transaction History),
  // merged into one chronological list. `reference` is prefixed per source
  // (ORD-/COOP-/INF-/ML-) since the tables don't share a reference-number
  // scheme; `source` carries the channel as a typed value so the screen never
  // has to read it back out of that text. Each channel runs through its own
  // _safeFetch: one channel failing can't blank the others.
  //
  // startDate mirrors fetchFarmPerformance()'s AnalyticsPeriod.startDate
  // convention exactly, so the list never shows a transaction from outside
  // the period sitting under a Total Revenue that excluded it.

  /// OfflineCache key for the marketplace part of the recent transactions
  /// with these arguments (matches the key written by fetchRecentTransactions),
  /// for the screen notice.
  static String recentTransactionsCacheScreen({
    int limit = 5,
    DateTime? startDate,
  }) => 'analytics_recent_tx_${limit}_${_periodKey(startDate)}';

  /// The other OfflineCache keys fetchRecentTransactions writes (one per
  /// remaining channel), for the screen notice.
  static List<String> recentTransactionsOtherCacheScreens({
    int limit = 5,
    DateTime? startDate,
  }) {
    final key = '${limit}_${_periodKey(startDate)}';
    return [
      'analytics_recent_tx_coop_$key',
      'analytics_recent_tx_informal_$key',
      'analytics_recent_tx_market_linking_$key',
    ];
  }

  Future<List<TransactionRecord>> fetchRecentTransactions({
    int limit = 5,
    DateTime? startDate,
  }) async {
    final key = '${limit}_${_periodKey(startDate)}';

    final ordersList = await _safeFetch(
      'fetchRecentTransactions/orders',
      () async {
        var ordersQuery = _client
            .from('orders')
            .select(
              'id, order_number, quantity_kg, unit, total_price, created_at, '
              'marketplace_listings(crop_name)',
            )
            .eq('farmer_id', _userId)
            .eq('status', 'completed');
        if (startDate != null) {
          ordersQuery = ordersQuery.gte('created_at', _instant(startDate));
        }
        final rows = await OfflineCache.load(
          screen: recentTransactionsCacheScreen(
            limit: limit,
            startDate: startDate,
          ),
          fetch: () =>
              ordersQuery.order('created_at', ascending: false).limit(limit),
        );
        return rows.map((row) {
          final id = row['id'] as String;
          final listing = row['marketplace_listings'] as Map<String, dynamic>?;
          return TransactionRecord(
            id: id,
            cropName: listing?['crop_name'] as String? ?? 'Unknown crop',
            quantityKg: (row['quantity_kg'] as num).toDouble(),
            unit: unitOrDefault(row['unit'] as String?),
            totalAmount: (row['total_price'] as num).toDouble(),
            date: DateTime.parse(row['created_at'] as String),
            reference: orderReferenceOf(id, row['order_number'] as String?),
            source: TransactionSource.marketplace,
          );
        }).toList();
      },
      <TransactionRecord>[],
    );

    final coopList = await _safeFetch(
      'fetchRecentTransactions/memberSales',
      () async {
        var coopQuery = _client
            .from('member_sales_transactions')
            .select('id, crop_name, quantity_kg, unit, amount, sale_date')
            .eq('farmer_id', _userId);
        if (startDate != null) {
          coopQuery = coopQuery.gte('sale_date', _dateOnly(startDate));
        }
        final rows = await OfflineCache.load(
          screen: 'analytics_recent_tx_coop_$key',
          fetch: () =>
              coopQuery.order('sale_date', ascending: false).limit(limit),
        );
        return rows.map((row) {
          final id = row['id'] as String;
          return TransactionRecord(
            id: id,
            cropName: row['crop_name'] as String,
            quantityKg: (row['quantity_kg'] as num).toDouble(),
            unit: unitOrDefault(row['unit'] as String?),
            totalAmount: (row['amount'] as num).toDouble(),
            date: DateTime.parse(row['sale_date'] as String),
            reference: 'COOP-${id.substring(0, 4).toUpperCase()}',
            source: TransactionSource.cooperative,
          );
        }).toList();
      },
      <TransactionRecord>[],
    );

    final informalList = await _safeFetch(
      'fetchRecentTransactions/informalSales',
      () async {
        var informalQuery = _client
            .from('informal_sales')
            .select('id, crop_name, quantity_kg, unit, amount, sale_date')
            .eq('farmer_id', _userId);
        if (startDate != null) {
          informalQuery = informalQuery.gte('sale_date', _instant(startDate));
        }
        final rows = await OfflineCache.load(
          screen: 'analytics_recent_tx_informal_$key',
          fetch: () =>
              informalQuery.order('sale_date', ascending: false).limit(limit),
        );
        return rows.map((row) {
          final id = row['id'] as String;
          return TransactionRecord(
            id: id,
            cropName: row['crop_name'] as String,
            quantityKg: (row['quantity_kg'] as num).toDouble(),
            unit: unitOrDefault(row['unit'] as String?),
            totalAmount: ((row['amount'] as num?)?.toDouble() ?? 0),
            date: DateTime.parse(row['sale_date'] as String),
            reference: 'INF-${id.substring(0, 4).toUpperCase()}',
            source: TransactionSource.informal,
          );
        }).toList();
      },
      <TransactionRecord>[],
    );

    final marketLinkingList = await _safeFetch(
      'fetchRecentTransactions/marketLinking',
      () async {
        var mlQuery = _client
            .from('market_linking_programs')
            .select(
              'id, crop_name, confirmed_volume_kg, requested_volume_kg, '
              'volume_kg, price_per_kg, completed_at',
            )
            .eq('farmer_id', _userId)
            .eq('status', 'completed')
            .not('completed_at', 'is', null);
        if (startDate != null) {
          mlQuery = mlQuery.gte('completed_at', _instant(startDate));
        }
        final rows = await OfflineCache.load(
          screen: 'analytics_recent_tx_market_linking_$key',
          fetch: () =>
              mlQuery.order('completed_at', ascending: false).limit(limit),
        );
        final list = <TransactionRecord>[];
        for (final row in rows) {
          final amount = marketLinkingAmountOf(row);
          if (amount == null) continue; // same rule as Home's earnings
          final id = row['id'] as String;
          list.add(
            TransactionRecord(
              id: id,
              cropName: row['crop_name'] as String? ?? 'Ginger',
              quantityKg: marketLinkingQuantityOf(row),
              totalAmount: amount,
              date: DateTime.parse(row['completed_at'] as String),
              reference: 'ML-${id.substring(0, 4).toUpperCase()}',
              source: TransactionSource.marketLinking,
            ),
          );
        }
        return list;
      },
      <TransactionRecord>[],
    );

    final combined = [
      ...ordersList,
      ...coopList,
      ...informalList,
      ...marketLinkingList,
    ];
    combined.sort((a, b) => b.date.compareTo(a.date));
    return combined.take(limit).toList();
  }

  // ─── Price Cards with margin ───────────────────────────────────────────────

  Future<List<CropPriceCard>> fetchPriceCards() async {
    return _safeFetch('fetchPriceCards', () async {
      // crop_master(image_url) embed — price_records.crop_id is a direct
      // FK to crop_master.id (added in an earlier refactor, confirmed via
      // supabase_schema_crop_master_price_records_refactor.sql), not the
      // farmer_crops two-hop harvest_records/inventory_batches need. Same
      // embed FarmerMarketRatesRepository.fetchMarketRates() already uses
      // for Market Rates' own crop thumbnails.
      final rows = await OfflineCache.load(
        screen: 'analytics_price_cards',
        fetch: () => _client
            .from('price_records')
            .select(
              'crop_name, price_type, price, previous_price, recorded_at, crop_master(image_url, is_active)',
            )
            .order('recorded_at', ascending: false),
      );

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
        final cropMaster = row['crop_master'] as Map<String, dynamic>?;
        // An archived crop (retired from the catalog) shows no current price.
        if (cropMaster?['is_active'] == false) continue;
        latestByKey[key] = CropPriceCard(
          cropName: crop,
          priceType: priceType,
          currentPrice: (row['price'] as num).toDouble(),
          previousPrice: row['previous_price'] != null
              ? (row['previous_price'] as num).toDouble()
              : null,
          imageUrl: cropMaster?['image_url'] as String?,
          recordedAt: DateTime.parse(row['recorded_at'] as String),
        );
      }
      return latestByKey.values.toList();
    }, <CropPriceCard>[]);
  }

  // ─── Price History for a specific crop ─────────────────────────────────────
  // startDate replaces the old fixed `days` window — null means no lower
  // bound (All Time), matching the same nullable-startDate convention
  // fetchFarmPerformance already uses.

  /// OfflineCache key for one crop's price history (matches fetchPriceHistory's key).
  static String priceHistoryCacheScreen(
    String cropName, {
    required String priceType,
    DateTime? startDate,
  }) =>
      'analytics_price_history_${cropName}_${priceType}_${startDate?.toIso8601String() ?? 'any'}';

  Future<List<PriceHistoryPoint>> fetchPriceHistory(
    String cropName, {
    required String priceType,
    DateTime? startDate,
  }) async {
    return _safeFetch('fetchPriceHistory', () async {
      var query = _client
          .from('price_records')
          .select('price, recorded_at')
          // ilike is case-insensitive; the name is escaped so a crop name
          // containing % or _ matches itself, not a wildcard.
          .ilike(
            'crop_name',
            cropName
                .replaceAll(r'\', r'\\')
                .replaceAll('%', r'\%')
                .replaceAll('_', r'\_'),
          )
          .eq('price_type', priceType);

      if (startDate != null) {
        query = query.gte('recorded_at', _instant(startDate));
      }

      final rows = await OfflineCache.load(
        screen:
            'analytics_price_history_${cropName}_${priceType}_${startDate?.toIso8601String() ?? 'any'}',
        fetch: () => query.order('recorded_at', ascending: true),
      );

      return rows
          .map(
            (row) => PriceHistoryPoint(
              date: DateTime.parse(row['recorded_at'] as String),
              price: (row['price'] as num).toDouble(),
            ),
          )
          .toList();
    }, <PriceHistoryPoint>[]);
  }

  // ─── Planting Forecast (cooperative-wide, from SQL view) ──────────────────

  Future<List<PlantingForecast>> fetchPlantingForecasts() async {
    return _safeFetch('fetchPlantingForecasts', () async {
      final rows = await OfflineCache.load(
        screen: 'analytics_planting_forecast',
        fetch: () => _client
            .from('crop_planting_forecast')
            .select()
            .order('most_recent_cycle_kg', ascending: false),
      );

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
        final cropRows = await OfflineCache.load(
          screen: 'analytics_crop_categories',
          fetch: () =>
              _client.from('crop_master').select('crop_name, category'),
        );
        for (final row in cropRows) {
          categoryMap.putIfAbsent(
            row['crop_name'] as String,
            () => row['category'] as String? ?? 'Other',
          );
        }
      } catch (e) {
        debugPrint(
          'AnalyticsRepository.fetchPlantingForecasts/cropMaster failed: $e',
        );
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
      final rows = await OfflineCache.load(
        screen: 'analytics_top_crops',
        fetch: () =>
            _client.from('top_harvested_crops').select('crop_name, total_kg'),
      );

      final sorted = rows.toList()
        ..sort(
          (a, b) => (b['total_kg'] as num).compareTo(a['total_kg'] as num),
        );
      final top = sorted.take(limit).toList();
      final maxVal = top.isEmpty
          ? 1.0
          : (top.first['total_kg'] as num).toDouble();

      return top
          .map(
            (row) => TopSellingCrop(
              cropName: row['crop_name'] as String,
              volumeKg: (row['total_kg'] as num).toDouble(),
              percentOfMax: maxVal > 0
                  ? ((row['total_kg'] as num).toDouble() / maxVal).clamp(
                      0.0,
                      1.0,
                    )
                  : 0,
            ),
          )
          .toList();
    }, <TopSellingCrop>[]);
  }
}
