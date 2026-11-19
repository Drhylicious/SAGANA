import '../../core/l10n/localized_labels.dart';
import '../../core/utils/chunked_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/offline_cache.dart';
import '../../core/utils/order_reference.dart';
import '../../core/utils/quantity_utils.dart';
import '../models/admin_reports_model.dart';
import '../models/shelf_life_model.dart';
import 'shelf_life_repository.dart';
import 'completed_order_dates.dart';
import 'crop_lookup.dart';
import 'farmer_lookup.dart';
import '../models/expense_model.dart';
import '../models/supply_chain_model.dart' show SupplyChainTotals;
import 'member_sales_aggregation.dart';
import 'supply_chain_repository.dart';
import '../services/market_types_service.dart';
import 'paged_query.dart';
import 'capital_share_rates_repository.dart';

/// Repository for the Operational Reports hub and five of its six
/// sub-reports (Sales, Inventory, Harvest, Expense, Member Contribution).
/// Loan Report reuses AdminLoanRepository directly instead of duplicating
/// loan queries here.
class AdminReportsRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Operational Reports Hub ────────────────────────────────────────────

  Future<PerformanceSummary> fetchPerformanceSummary(
    ReportPeriod period,
  ) async {
    final window = period.range();
    return fetchPerformanceSummaryForRange(window.startDate, window.endDate);
  }

  Future<PerformanceSummary> fetchPreviousPeriodSummary(
    ReportPeriod period,
  ) async {
    final previous = period.previousRange();
    if (previous == null) return PerformanceSummary.empty();
    return fetchPerformanceSummaryForRange(
      previous.startDate,
      previous.endDate,
    );
  }

  /// OfflineCache key for the harvest part of the performance summary for [period]
  /// (matches _fetchTotalHarvestKg), so the operational reports screen can show the notice.
  static String performanceCacheScreen(ReportPeriod period) {
    final window = period.range();
    return 'perf_harvest_${window.startDate?.toIso8601String() ?? 'any'}_'
        '${window.endDate?.toIso8601String() ?? 'any'}';
  }

  Future<PerformanceSummary> fetchPerformanceSummaryForRange(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    try {
      final results = await Future.wait([
        _fetchTotalHarvestKg(startDate: startDate, endDate: endDate),
        _fetchCoopSalesAmount(startDate: startDate, endDate: endDate),
        _fetchMarketplaceRevenue(startDate: startDate, endDate: endDate),
        _fetchActiveLoanOutstanding(),
        _fetchTotalExpenses(startDate: startDate, endDate: endDate),
        _fetchMemberParticipationPercent(
          startDate: startDate,
          endDate: endDate,
        ),
        // Reuses Sales Report's own already-correct 4-channel total
        // (fetchSalesReportForRange) rather than re-deriving it — see
        // PerformanceSummary.totalSalesAmount's own note.
        fetchSalesReportForRange(startDate, endDate),
        fetchProductSalesForRange(startDate, endDate),
        _fetchMarketplaceCompletedCount(startDate, endDate),
      ]);
      final productSales = results[7] as ProductSalesSummary;

      return PerformanceSummary(
        totalHarvestKg: results[0] as double,
        coopSalesAmount: results[1] as double,
        marketplaceRevenue: results[2] as double,
        activeLoanOutstanding: results[3] as double,
        totalExpenses: results[4] as double,
        memberParticipationPercent: results[5] as double,
        totalSalesAmount: (results[6] as SalesReportData).totalRevenue,
        productSalesAmount: productSales.amount,
        completedOrders: (results[8] as int) + productSales.orders,
      );
    } catch (_) {
      return PerformanceSummary.empty();
    }
  }

  Future<double> _fetchTotalHarvestKg({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _client.from('harvest_records').select('quantity_kg, unit').eq('source_type', 'self');
      if (startDate != null) {
        query = query.gte('harvest_date', _dateOnly(startDate));
      }
      if (endDate != null) {
        query = query.lte('harvest_date', _dateOnly(endDate));
      }
      final rows = await OfflineCache.load(
        screen:
            'perf_harvest_${startDate?.toIso8601String() ?? 'any'}_${endDate?.toIso8601String() ?? 'any'}',
        fetch: () => query,
      );
      // A kg total: harvests measured in another unit are not added to it.
      return rows.fold<double>(
        0,
        (sum, r) => isKg(r['unit'] as String?)
            ? sum + (r['quantity_kg'] as num).toDouble()
            : sum,
      );
    } catch (_) {
      return 0;
    }
  }

  Future<double> _fetchCoopSalesAmount({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _client.from('member_sales_transactions').select('amount');
      if (startDate != null) {
        query = query.gte('sale_date', _dateOnly(startDate));
      }
      if (endDate != null) {
        query = query.lte('sale_date', _dateOnly(endDate));
      }
      final rows = await OfflineCache.load(
        screen:
            'perf_coop_sales_${startDate?.toIso8601String() ?? 'any'}_${endDate?.toIso8601String() ?? 'any'}',
        fetch: () => query,
      );
      return rows.fold<double>(
        0,
        (sum, r) => sum + (r['amount'] as num).toDouble(),
      );
    } catch (_) {
      return 0;
    }
  }

  Future<double> _fetchMarketplaceRevenue({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final rows = await _marketplaceCompletedRows(startDate, endDate);
      return rows.fold<double>(
        0,
        (sum, r) => sum + (r['total_price'] as num).toDouble(),
      );
    } catch (_) {
      return 0;
    }
  }

  Future<int> _fetchMarketplaceCompletedCount(DateTime? startDate, DateTime? endDate) async {
    try {
      return (await _marketplaceCompletedRows(startDate, endDate)).length;
    } catch (_) {
      return 0;
    }
  }

  /// The completed Marketplace orders of the period (throws when they cannot be read).
  Future<List<Map<String, dynamic>>> _marketplaceCompletedRows(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    {
      // A completed order counts on the day the buyer confirmed receipt (see
      // CompletedOrderDates), the same day the Sales Report and every Farmer's
      // own history use for it.
      final lower = startDate == null ? null : DateTime.parse(_dateOnly(startDate));
      final upper = endDate == null
          ? null
          : DateTime.parse(_exclusiveUpperBound(endDate));
      final rows = await OfflineCache.load(
        screen:
            'perf_marketplace_${startDate?.toIso8601String() ?? 'any'}_${endDate?.toIso8601String() ?? 'any'}',
        fetch: () => CompletedOrderDates.withFallback((withReceivedAt) {
          var query = _client
              .from('orders')
              .select(
                withReceivedAt ? 'total_price, created_at, received_at' : 'total_price, created_at',
              )
              .eq('status', 'completed');
          if (withReceivedAt) {
            final window = CompletedOrderDates.window(lower, upper);
            return window == null ? query : query.or(window);
          }
          if (lower != null) query = query.gte('created_at', lower.toIso8601String());
          if (upper != null) query = query.lt('created_at', upper.toIso8601String());
          return query;
        }),
      );
      return rows;
    }
  }

  // ─── Cooperative Product sales ──────────────────────────────────────────

  /// Completed Product Sales orders of [period], counted on the day they were completed (the
  /// same day idea as a Marketplace order: when the customer confirmed receipt, or staff
  /// completed it). Its own figure, never mixed into the selling channels.
  Future<ProductSalesSummary> fetchProductSales(ReportPeriod period) {
    final window = period.range();
    return fetchProductSalesForRange(window.startDate, window.endDate);
  }

  Future<ProductSalesSummary> fetchPreviousProductSales(ReportPeriod period) {
    final previous = period.previousRange();
    if (previous == null) return Future.value(ProductSalesSummary.empty);
    return fetchProductSalesForRange(previous.startDate, previous.endDate);
  }

  Future<ProductSalesSummary> fetchProductSalesForRange(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    try {
      final lower = startDate == null ? null : DateTime.parse(_dateOnly(startDate));
      final upper = endDate == null ? null : DateTime.parse(_exclusiveUpperBound(endDate));
      final rows = await OfflineCache.load(
        screen:
            'perf_product_sales_${startDate?.toIso8601String() ?? 'any'}_${endDate?.toIso8601String() ?? 'any'}',
        fetch: () {
          var query = _client
              .from('program_product_purchases')
              .select('total_amount, farmer_id')
              .eq('status', 'completed');
          if (lower != null) query = query.gte('completed_at', lower.toUtc().toIso8601String());
          if (upper != null) query = query.lt('completed_at', upper.toUtc().toIso8601String());
          return query;
        },
      );
      var amount = 0.0;
      final buyers = <String>{};
      for (final r in rows) {
        amount += (r['total_amount'] as num).toDouble();
        final farmer = r['farmer_id'];
        if (farmer is String) buyers.add(farmer);
      }
      return ProductSalesSummary(amount: amount, orders: rows.length, buyers: buyers.length);
    } catch (_) {
      return ProductSalesSummary.empty;
    }
  }

  /// Every completed Cooperative Product order of [period], newest first, with the Farmer's name.
  Future<ProductSalesReportData> fetchProductSalesReport(ReportPeriod period) {
    final window = period.range();
    return fetchProductSalesReportForRange(window.startDate, window.endDate);
  }

  Future<ProductSalesReportData> fetchProductSalesReportForRange(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    try {
      final lower = startDate == null ? null : DateTime.parse(_dateOnly(startDate));
      final upper = endDate == null ? null : DateTime.parse(_exclusiveUpperBound(endDate));
      final rows = await OfflineCache.load(
        screen:
            'sales_product_rows_${startDate?.toIso8601String() ?? 'any'}_${endDate?.toIso8601String() ?? 'any'}',
        fetch: () {
          var query = _client
              .from('program_product_purchases')
              .select(
                'id, order_number, farmer_id, item_name, program_name, unit, quantity, total_amount, completed_at',
              )
              .eq('status', 'completed');
          if (lower != null) {
            query = query.gte('completed_at', lower.toUtc().toIso8601String());
          }
          if (upper != null) {
            query = query.lt('completed_at', upper.toUtc().toIso8601String());
          }
          return fetchAllPages(query.order('completed_at', ascending: false));
        },
      );
      final names = await fetchFarmerInfoMap(_client, {
        for (final r in rows)
          if (r['farmer_id'] is String) r['farmer_id'] as String,
      }.toList());
      final sales = [
        for (final r in rows)
          if (r['completed_at'] is String)
            ProductSaleRow(
              id: r['id'] as String,
              orderNumber: (r['order_number'] as String?) ?? '',
              farmerName: names[r['farmer_id']]?.fullName ?? '',
              itemName: (r['item_name'] as String?) ?? '',
              programName: r['program_name'] as String?,
              quantity: (r['quantity'] as num).toDouble(),
              unit: (r['unit'] as String?) ?? '',
              amount: (r['total_amount'] as num).toDouble(),
              saleDate: DateTime.parse(r['completed_at'] as String).toLocal(),
            ),
      ];
      final buyers = {for (final r in rows) r['farmer_id']}.whereType<String>().length;
      return ProductSalesReportData(
        summary: ProductSalesSummary(
          amount: sales.fold<double>(0, (s, r) => s + r.amount),
          orders: sales.length,
          buyers: buyers,
        ),
        rows: sales,
      );
    } catch (_) {
      return ProductSalesReportData.empty;
    }
  }

  /// Cooperative Product sales per calendar month for the last [months] months (oldest first,
  /// zero-filled), for the Revenue Trend of that report. Independent of the period chip, like
  /// [fetchSalesTrend].
  Future<List<double>> fetchProductSalesTrend({int months = 6}) async {
    try {
      final now = DateTime.now();
      final cutoff = DateTime(now.year, now.month - (months - 1), 1);
      final rows = await OfflineCache.load(
        screen: 'sales_product_trend_$months',
        fetch: () => _client
            .from('program_product_purchases')
            .select('total_amount, completed_at')
            .eq('status', 'completed')
            .gte('completed_at', cutoff.toUtc().toIso8601String()),
      );
      if (rows.isEmpty) return [];
      final buckets = <String, double>{};
      for (final r in rows) {
        final at = r['completed_at'];
        if (at is! String) continue;
        final d = DateTime.parse(at).toLocal();
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        buckets[key] = (buckets[key] ?? 0) + (r['total_amount'] as num).toDouble();
      }
      return List.generate(months, (i) {
        final date = DateTime(now.year, now.month - (months - 1 - i), 1);
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        return buckets[key] ?? 0.0;
      });
    } catch (_) {
      return [];
    }
  }

  /// The Dashboard Overview figures. Every one follows the current calendar year and starts again
  /// in January. A figure that cannot be read counts as zero.
  Future<DashboardOverview> fetchDashboardOverview() async {
    final window = ReportPeriod.thisYear.range();
    final yearStart = DateTime(DateTime.now().year, 1, 1);
    final since = yearStart.toUtc().toIso8601String();

    Future<int> count(Future<int> Function() run) async {
      try {
        return await run();
      } catch (_) {
        return 0;
      }
    }

    final results = await Future.wait<Object>([
      count(() => _client.from('cooperative_inventory').count().eq('is_active', true)),
      count(() => _client.from('crop_master').count().eq('is_active', true)),
      count(() => _client.from('cooperative_programs').count().eq('season_year', yearStart.year)),
      _fetchMarketplaceRevenue(startDate: window.startDate, endDate: window.endDate),
      fetchProductSalesForRange(window.startDate, window.endDate),
      // Supply Chain Management: supplies tracked this year, incoming + outgoing.
      SupplyChainRepository(client: _client).fetchYearTotals(),
      // Retail prices: the Public Market and the Cooperative Market (not the DA-AMAD price).
      count(
        () => _client
            .from('price_records')
            .count()
            .inFilter('price_type', ['open_market', 'sp3_cooperative'])
            .gte('recorded_at', since),
      ),
    ]);
    final product = results[4] as ProductSalesSummary;
    return DashboardOverview(
      inventoryItems: results[0] as int,
      crops: results[1] as int,
      programs: results[2] as int,
      revenue: (results[3] as double) + product.amount,
      suppliesIncoming: (results[5] as SupplyChainTotals).incoming,
      suppliesOutgoing: (results[5] as SupplyChainTotals).outgoing,
      retailPrices: results[6] as int,
    );
  }

  Future<double> _fetchActiveLoanOutstanding() async {
    try {
      final rows = await OfflineCache.load(
        screen: 'perf_loan_outstanding',
        fetch: () => _client
            .from('farmer_loans')
            .select('total_value, amount_paid')
            .inFilter('status', ['active', 'overdue']),
      );
      return rows.fold<double>(0, (sum, r) {
        final total = (r['total_value'] as num).toDouble();
        final paid = (r['amount_paid'] as num? ?? 0).toDouble();
        return sum + (total - paid).clamp(0, double.infinity);
      });
    } catch (_) {
      return 0;
    }
  }

  Future<QuickInsights> fetchQuickInsights(ReportPeriod period) async {
    try {
      final window = period.range();

      // Sales rows for the period, with crop and farmer names resolved before
      // caching, so the insights can be rebuilt offline.
      final rows = await OfflineCache.load(
        screen:
            'insights_sales_${window.startDate?.toIso8601String() ?? 'any'}_'
            '${window.endDate?.toIso8601String() ?? 'any'}',
        fetch: () async {
          var query = _client.from('member_sales_transactions').select('*');
          if (window.startDate != null) {
            query = query.gte('sale_date', _dateOnly(window.startDate!));
          }
          if (window.endDate != null) {
            query = query.lte('sale_date', _dateOnly(window.endDate!));
          }
          final raw = await query;
          if (raw.isEmpty) return <Map<String, dynamic>>[];

          final cropIds = raw
              .map((r) => r['crop_id'] as String?)
              .whereType<String>()
              .toSet()
              .toList();
          final cropNames = await fetchCropNameMap(_client, cropIds);
          final farmerIds = raw
              .map((r) => r['farmer_id'] as String)
              .toSet()
              .toList();
          final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

          return raw.map<Map<String, dynamic>>((row) {
            final cropId = row['crop_id'] as String?;
            final crop =
                (cropId != null ? cropNames[cropId] : null) ??
                row['crop_name'] as String;
            final info = farmerInfo[row['farmer_id']];
            return {
              ...row,
              '_crop_name': crop,
              '_farmer_name': info?.fullName ?? currentL10n().dlUnknownFarmer,
            };
          }).toList();
        },
      );
      if (rows.isEmpty) return QuickInsights.empty();

      final cropTotals = <String, double>{};
      final farmerTotals = <String, double>{};
      final farmerNames = <String, String>{};
      for (final row in rows) {
        final amount = (row['amount'] as num).toDouble();
        final crop = row['_crop_name'] as String;
        final farmerId = row['farmer_id'] as String;
        cropTotals[crop] = (cropTotals[crop] ?? 0) + amount;
        farmerTotals[farmerId] = (farmerTotals[farmerId] ?? 0) + amount;
        farmerNames[farmerId] = row['_farmer_name'] as String;
      }

      final topCropEntry = cropTotals.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );
      final topFarmerEntry = farmerTotals.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );

      // Expenses are all-time (not period-filtered), so they have their own key.
      final expenseRows = await OfflineCache.load(
        screen: 'insights_expenses',
        fetch: () => _client
            .from('farmer_expenses')
            .select('category, amount')
            .eq('is_subsidy', false),
      );
      final expenseCategoryTotals = <String, double>{};
      for (final row in expenseRows) {
        final cat = row['category'] as String;
        expenseCategoryTotals[cat] =
            (expenseCategoryTotals[cat] ?? 0) +
            (row['amount'] as num).toDouble();
      }
      final topExpenseCategory = expenseCategoryTotals.isEmpty
          ? null
          : expenseCategoryTotals.entries.reduce(
              (a, b) => a.value > b.value ? a : b,
            );

      return QuickInsights(
        topCropName: topCropEntry.key,
        topCropAmount: topCropEntry.value,
        topFarmerName:
            farmerNames[topFarmerEntry.key] ?? currentL10n().dlUnknownFarmer,
        topFarmerAmount: topFarmerEntry.value,
        topExpenseCategory: topExpenseCategory?.key,
        topExpenseAmount: topExpenseCategory?.value,
      );
    } catch (_) {
      return QuickInsights.empty();
    }
  }

  Future<double> _fetchTotalExpenses({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _client
          .from('farmer_expenses')
          .select('amount')
          .eq('is_subsidy', false);
      if (startDate != null) {
        query = query.gte('expense_date', _dateOnly(startDate));
      }
      if (endDate != null) {
        query = query.lte('expense_date', _dateOnly(endDate));
      }
      final rows = await OfflineCache.load(
        screen:
            'perf_expenses_${startDate?.toIso8601String() ?? 'any'}_${endDate?.toIso8601String() ?? 'any'}',
        fetch: () => query,
      );
      return rows.fold<double>(
        0,
        (sum, r) => sum + (r['amount'] as num).toDouble(),
      );
    } catch (_) {
      return 0;
    }
  }

  Future<double> _fetchMemberParticipationPercent({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final totalFarmersRows = await OfflineCache.load(
        screen: 'participation_farmers',
        fetch: () => _client.from('farmer_profiles').select('user_id'),
      );
      final totalFarmers = totalFarmersRows.length;
      if (totalFarmers == 0) return 0;

      final activeIds = <String>{};

      var harvestQuery = _client.from('harvest_records').select('farmer_id').eq('source_type', 'self');
      if (startDate != null) {
        harvestQuery = harvestQuery.gte('harvest_date', _dateOnly(startDate));
      }
      if (endDate != null) {
        harvestQuery = harvestQuery.lte('harvest_date', _dateOnly(endDate));
      }
      final harvestRows = await OfflineCache.load(
        screen:
            'participation_harvest_${startDate?.toIso8601String() ?? 'any'}_${endDate?.toIso8601String() ?? 'any'}',
        fetch: () => harvestQuery,
      );
      activeIds.addAll(harvestRows.map((r) => r['farmer_id'] as String));

      var salesQuery = _client
          .from('member_sales_transactions')
          .select('farmer_id');
      if (startDate != null) {
        salesQuery = salesQuery.gte('sale_date', _dateOnly(startDate));
      }
      if (endDate != null) {
        salesQuery = salesQuery.lte('sale_date', _dateOnly(endDate));
      }
      final salesRows = await OfflineCache.load(
        screen:
            'participation_sales_${startDate?.toIso8601String() ?? 'any'}_${endDate?.toIso8601String() ?? 'any'}',
        fetch: () => salesQuery,
      );
      activeIds.addAll(salesRows.map((r) => r['farmer_id'] as String));

      var listingQuery = _client
          .from('marketplace_listings')
          .select('farmer_id');
      if (startDate != null) {
        listingQuery = listingQuery.gte(
          'submitted_at',
          startDate.toUtc().toIso8601String(),
        );
      }
      if (endDate != null) {
        listingQuery = listingQuery.lt(
          'submitted_at',
          DateTime.parse(
            _exclusiveUpperBound(endDate),
          ).toUtc().toIso8601String(),
        );
      }
      final listingRows = await OfflineCache.load(
        screen:
            'participation_listings_${startDate?.toIso8601String() ?? 'any'}_${endDate?.toIso8601String() ?? 'any'}',
        fetch: () => listingQuery,
      );
      activeIds.addAll(listingRows.map((r) => r['farmer_id'] as String));

      return (activeIds.length / totalFarmers * 100).clamp(0, 100);
    } catch (_) {
      return 0;
    }
  }

  // ─── Sales Report ───────────────────────────────────────────────────────

  /// Sales Report is a unified view across the four real Selling Types
  /// (Phase 10 redesign, per the organization's clarified Market Type vs.
  /// Selling Type distinction): Offer to Cooperative (any crop, per Phase
  /// 9), Marketplace, Informal Sale (F2F), and DA-AMAD Market Linking.
  /// Previously this screen only ever read member_sales_transactions —
  /// Informal Sale and DA-AMAD Market Linking were completely invisible to
  /// any report. Trend is aggregated by month across all four sources
  /// combined, capped to the most recent 6 buckets.
  /// OfflineCache key for the sales channel rows of [period] (matches the
  /// keys written by _cachedSalesRows), so the sales screen can show the notice.
  static String salesCacheScreen(ReportPeriod period) {
    final window = period.range();
    return 'sales_offer_to_coop_${window.startDate?.toIso8601String() ?? 'any'}_'
        '${window.endDate?.toIso8601String() ?? 'any'}';
  }

  Future<SalesReportData> fetchSalesReport(ReportPeriod period) {
    final window = period.range();
    return fetchSalesReportForRange(window.startDate, window.endDate);
  }

  /// Previous-period Sales figures, for a Total Revenue delta badge —
  /// same range → previousRange pattern as fetchPreviousPeriodSummary().
  Future<SalesReportData> fetchPreviousSalesReport(ReportPeriod period) {
    final previous = period.previousRange();
    if (previous == null) return Future.value(SalesReportData.empty());
    return fetchSalesReportForRange(previous.startDate, previous.endDate);
  }

  Future<SalesReportData> fetchSalesReportForRange(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    try {
      final results = await Future.wait([
        _fetchOfferToCoopSalesRows(startDate, endDate),
        _fetchMarketplaceSalesRows(startDate, endDate),
        _fetchInformalSaleRows(startDate, endDate),
        _fetchDaAmadMarketLinkingRows(startDate, endDate),
      ]);
      final offerRows = results[0];
      final marketplaceRows = results[1];
      final informalRows = results[2];
      final daAmadRows = results[3];

      return buildSalesReportData(
        offerRows: offerRows,
        marketplaceRows: marketplaceRows,
        informalRows: informalRows,
        daAmadRows: daAmadRows,
      );
    } catch (_) {
      return SalesReportData.empty();
    }
  }

  /// Revenue Trend's dedicated data source — deliberately independent of
  /// the on-screen period filter, mirroring fetchYieldTrend()/
  /// fetchExpenseTrend()/AdminLoanRepository.fetchMonthlyCollectionTrend()
  /// exactly. fetchSalesReport(period)'s own monthlyTrend is filtered to
  /// the SAME period selected by the chips before bucketing by month —
  /// meaning it could never show more than one point while "This Month"
  /// was selected, regardless of real sales history across all four
  /// Selling Types. This method always looks at a fixed trailing window
  /// instead, so the trend can render correctly no matter which period
  /// chip is currently selected on screen.
  ///
  /// Always returns a dense, gap-filled array of exactly [months] entries
  /// (one per trailing calendar month, zero-filled where there's no data)
  /// when there's at least one real data point in the window — same
  /// convention as fetchYieldTrend(). Returns [] only when the window has
  /// no data at all.
  Future<List<double>> fetchSalesTrend({int months = 6}) async {
    try {
      final now = DateTime.now();
      final cutoff = DateTime(now.year, now.month - (months - 1), 1);
      final results = await Future.wait([
        _fetchOfferToCoopSalesRows(cutoff, null),
        _fetchMarketplaceSalesRows(cutoff, null),
        _fetchInformalSaleRows(cutoff, null),
        _fetchDaAmadMarketLinkingRows(cutoff, null),
      ]);
      final allRows = [
        ...results[0],
        ...results[1],
        ...results[2],
        ...results[3],
      ];
      if (allRows.isEmpty) return [];

      final buckets = <String, double>{};
      for (final row in allRows) {
        final key =
            '${row.saleDate.year}-${row.saleDate.month.toString().padLeft(2, '0')}';
        buckets[key] = (buckets[key] ?? 0) + row.amount;
      }

      return List.generate(months, (i) {
        final offset = months - 1 - i;
        final date = DateTime(now.year, now.month - offset, 1);
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        return buckets[key] ?? 0.0;
      });
    } catch (_) {
      return [];
    }
  }

  /// Channel 1/4: Offer to Cooperative — any crop, per Phase 9's widening.
  /// The only channel with a Palay/Peanut-specific breakdown elsewhere.
  /// Caches one channel's sales rows per date range, so the sales report can be
  /// viewed offline. The live builder keeps its own logic; only its result is cached.
  Future<List<SalesTransactionRow>> _cachedSalesRows(
    String channel,
    DateTime? startDate,
    DateTime? endDate,
    Future<List<SalesTransactionRow>> Function() live,
  ) async {
    try {
      final rows = await OfflineCache.load(
        screen:
            'sales_${channel}_${startDate?.toIso8601String() ?? 'any'}_'
            '${endDate?.toIso8601String() ?? 'any'}',
        fetch: () async => (await live()).map((r) => r.toMap()).toList(),
      );
      return rows.map(SalesTransactionRow.fromMap).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<SalesTransactionRow>> _fetchOfferToCoopSalesRows(
    DateTime? startDate,
    DateTime? endDate,
  ) => _cachedSalesRows(
    'offer_to_coop',
    startDate,
    endDate,
    () => _fetchOfferToCoopSalesRowsLive(startDate, endDate),
  );

  Future<List<SalesTransactionRow>> _fetchMarketplaceSalesRows(
    DateTime? startDate,
    DateTime? endDate,
  ) => _cachedSalesRows(
    'marketplace',
    startDate,
    endDate,
    () => _fetchMarketplaceSalesRowsLive(startDate, endDate),
  );

  Future<List<SalesTransactionRow>> _fetchInformalSaleRows(
    DateTime? startDate,
    DateTime? endDate,
  ) => _cachedSalesRows(
    'informal',
    startDate,
    endDate,
    () => _fetchInformalSaleRowsLive(startDate, endDate),
  );

  Future<List<SalesTransactionRow>> _fetchDaAmadMarketLinkingRows(
    DateTime? startDate,
    DateTime? endDate,
  ) => _cachedSalesRows(
    'da_amad',
    startDate,
    endDate,
    () => _fetchDaAmadMarketLinkingRowsLive(startDate, endDate),
  );

  Future<List<SalesTransactionRow>> _fetchOfferToCoopSalesRowsLive(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    var query = _client.from('member_sales_transactions').select('*');
    if (startDate != null) {
      query = query.gte('sale_date', _dateOnly(startDate));
    }
    if (endDate != null) {
      query = query.lte('sale_date', _dateOnly(endDate));
    }
    final rows = await fetchAllPages(query);
    if (rows.isEmpty) return [];

    final farmerIds = rows
        .map((r) => r['farmer_id'] as String)
        .toSet()
        .toList();
    final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);
    final cropInfo = await _fetchCropInfoByName();
    final staffNames = await _fetchStaffNames([
      for (final r in rows)
        if (r['recorded_by'] != null) r['recorded_by'] as String,
    ]);
    // The agreed price per unit lives on the offer that created the sale.
    final priceBySale = await _fetchOfferPricesBySale([
      for (final r in rows) r['id'] as String,
    ]);
    final offerBatch = await _fetchOfferBatchBySale([
      for (final r in rows) r['id'] as String,
    ]);
    final offerProgramBatches = await _programOriginBatchIds(offerBatch.values);

    return rows.map((row) {
      final info = farmerInfo[row['farmer_id']];
      final crop = cropInfo[(row['crop_name'] as String).toLowerCase()];
      return SalesTransactionRow(
        id: row['id'] as String,
        farmerName: info?.fullName ?? currentL10n().dlUnknownFarmer,
        cropType: row['crop_type'] as String? ?? 'palay',
        cropName: row['crop_name'] as String,
        quantityKg: (row['quantity_kg'] as num).toDouble(),
        unit: unitOrDefault(row['unit'] as String?),
        amount: (row['amount'] as num).toDouble(),
        saleDate: DateTime.parse(row['sale_date'] as String),
        referenceNo: row['reference_no'] as String?,
        sellingType: 'offer_to_cooperative',
        marketType: crop?.marketType,
        cropCategory: crop?.category,
        pricePerKg: priceBySale[row['id'] as String],
        recordedBy: staffNames[row['recorded_by']],
        fromProgram: offerProgramBatches.contains(offerBatch[row['id'] as String]),
      );
    }).toList();
  }

  /// The agreed price per unit of each cooperative sale, from the completed offer
  /// that created it. A sale entered some other way has none.
  Future<Map<String, double>> _fetchOfferPricesBySale(List<String> saleIds) async {
    if (saleIds.isEmpty) return {};
    try {
      final rows = await _client
          .from('cooperative_purchase_offers')
          .select('member_sales_transaction_id, agreed_price_per_kg')
          .inFilter('member_sales_transaction_id', saleIds);
      return {
        for (final r in rows)
          if (r['agreed_price_per_kg'] != null)
            r['member_sales_transaction_id'] as String:
                (r['agreed_price_per_kg'] as num).toDouble(),
      };
    } catch (_) {
      return {};
    }
  }

  /// The batches (of these ids) that hold produce a Cooperative Program gave the Farmer, found through each
  /// batch's harvest entry. A failed lookup just marks nothing.
  Future<Set<String>> _programOriginBatchIds(Iterable<String?> batchIds) async {
    final ids = batchIds.whereType<String>().toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final rows = await chunkedIn(ids, (slice) => _client.from('inventory_batches').select('id, harvest_records(source_type)').inFilter('id', slice));
      bool fromProgram(Map r) {
        final h = r['harvest_records'];
        final first = h is List ? (h.isEmpty ? null : h.first) : h;
        return first is Map && first['source_type'] == 'program_received';
      }

      return {for (final r in rows) if (fromProgram(r)) r['id'] as String};
    } catch (_) {
      return {};
    }
  }

  /// sale id -> the batch an accepted cooperative offer was made from.
  Future<Map<String, String>> _fetchOfferBatchBySale(List<String> saleIds) async {
    if (saleIds.isEmpty) return {};
    try {
      final rows = await _client
          .from('cooperative_purchase_offers')
          .select('member_sales_transaction_id, inventory_batch_id')
          .inFilter('member_sales_transaction_id', saleIds);
      return {
        for (final r in rows)
          if (r['inventory_batch_id'] != null)
            r['member_sales_transaction_id'] as String: r['inventory_batch_id'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  /// user id -> full name of the Manager / Officer behind a recorded sale (staff
  /// may read every user's name).
  Future<Map<String, String>> _fetchStaffNames(List<String> userIds) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final rows = await chunkedIn(ids, (slice) => _client.from('user_information').select('user_id, full_name').inFilter('user_id', slice));
      return {
        for (final r in rows)
          r['user_id'] as String: (r['full_name'] as String? ?? '').trim(),
      };
    } catch (_) {
      return {};
    }
  }

  /// Channel 2/4: Marketplace — orders completed against a listing, any
  /// crop under either Public Market or Cooperative Market classification.
  /// marketplace_listings has no direct crop_id FK to crop_master (per
  /// supabase_schema_admin_edit_listing_price.sql's own confirmation), so
  /// Market Type is resolved by name match, same convention already used
  /// for the price_records backfill in supabase_schema_crop_master_price_
  /// records_refactor.sql.
  Future<List<SalesTransactionRow>> _fetchMarketplaceSalesRowsLive(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    // A completed order is a sale on the day the buyer confirmed receipt (see
    // CompletedOrderDates), the same day the Farmer's own history shows.
    final lower = startDate == null ? null : DateTime.parse(_dateOnly(startDate));
    final upper = endDate == null
        ? null
        : DateTime.parse(_exclusiveUpperBound(endDate));
    final rows = await CompletedOrderDates.withFallback((withReceivedAt) {
      var query = _client
          .from('orders')
          .select(
            'id, order_number, listing_id, buyer_id, quantity_kg, unit, price_per_kg, '
            'total_price, status, created_at${withReceivedAt ? ', received_at' : ''}',
          )
          .eq('status', 'completed');
      if (withReceivedAt) {
        final window = CompletedOrderDates.window(lower, upper);
        return fetchAllPages(window == null ? query : query.or(window));
      }
      if (lower != null) {
        query = query.gte('created_at', lower.toIso8601String());
      }
      if (upper != null) {
        query = query.lt('created_at', upper.toIso8601String());
      }
      return fetchAllPages(query);
    });
    if (rows.isEmpty) return [];

    final listingIds = rows
        .map((r) => r['listing_id'] as String)
        .toSet()
        .toList();
    final listingRows = await chunkedIn(listingIds, (slice) => _client.from('marketplace_listings').select('id, farmer_id, crop_name, inventory_batch_id').inFilter('id', slice));
    final listingMap = {for (final l in listingRows) l['id'] as String: l};
    final listingProgramBatches = await _programOriginBatchIds(
      listingRows.map((l) => l['inventory_batch_id'] as String?),
    );

    final farmerIds = listingRows
        .map((l) => l['farmer_id'] as String)
        .toSet()
        .toList();
    final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

    final cropInfo = await _fetchCropInfoByName();

    // Buyer name for the detail popup — admin has full read access to
    // user_information (unlike the farmer-side equivalent, which needs
    // a SECURITY DEFINER RPC to get past RLS), so a direct select is
    // sufficient here.
    final buyerIds = rows
        .map((r) => r['buyer_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final buyerNameById = <String, String>{};
    if (buyerIds.isNotEmpty) {
      final buyerRows = await chunkedIn(buyerIds, (slice) => _client.from('user_information').select('user_id, full_name').inFilter('user_id', slice));
      for (final b in buyerRows) {
        buyerNameById[b['user_id'] as String] = b['full_name'] as String;
      }
    }

    return rows.map((row) {
      final listing = listingMap[row['listing_id']];
      final farmerId = listing?['farmer_id'] as String?;
      final cropName = listing?['crop_name'] as String? ?? 'Unknown';
      final info = farmerId != null ? farmerInfo[farmerId] : null;
      return SalesTransactionRow(
        id: row['id'] as String,
        farmerName: info?.fullName ?? currentL10n().dlUnknownFarmer,
        cropType: cropName.toLowerCase(),
        cropName: cropName,
        quantityKg: (row['quantity_kg'] as num).toDouble(),
        unit: unitOrDefault(row['unit'] as String?),
        amount: (row['total_price'] as num).toDouble(),
        saleDate: CompletedOrderDates.of(row),
        referenceNo: orderReferenceOf(row['id'] as String, row['order_number'] as String?),
        sellingType: 'marketplace',
        marketType: cropInfo[cropName.toLowerCase()]?.marketType,
        cropCategory: cropInfo[cropName.toLowerCase()]?.category,
        pricePerKg: (row['price_per_kg'] as num?)?.toDouble(),
        buyerName: buyerNameById[row['buyer_id']],
        orderStatus: row['status'] as String?,
        fromProgram: listingProgramBatches.contains(listing?['inventory_batch_id']),
      );
    }).toList();
  }

  /// Channel 3/4: Informal Sale (F2F) — previously invisible to every
  /// report. No market-type concept applies (it's a direct, off-platform
  /// sale). amount is nullable in the schema (a barter/no-cash sale is
  /// possible); treated as 0 for revenue purposes, but still shown as a
  /// real transaction.
  Future<List<SalesTransactionRow>> _fetchInformalSaleRowsLive(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    var query = _client
        .from('informal_sales')
        .select(
          'id, farmer_id, crop_name, quantity_kg, unit, amount, buyer_name, sale_date, inventory_batch_id',
        );
    // sale_date is a timestamptz: the day starts at LOCAL midnight (as it does for
    // Marketplace and Cooperative Product sales), so a sale just after midnight
    // is in the right period in every report.
    if (startDate != null) {
      query = query.gte('sale_date', startDate.toUtc().toIso8601String());
    }
    if (endDate != null) {
      query = query.lt(
        'sale_date',
        DateTime.parse(_exclusiveUpperBound(endDate)).toUtc().toIso8601String(),
      );
    }
    final rows = await fetchAllPages(query);
    if (rows.isEmpty) return [];

    final farmerIds = rows
        .map((r) => r['farmer_id'] as String)
        .toSet()
        .toList();
    final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);
    final cropInfo = await _fetchCropInfoByName();
    final informalProgramBatches = await _programOriginBatchIds(
      rows.map((r) => r['inventory_batch_id'] as String?),
    );

    return rows.map((row) {
      final info = farmerInfo[row['farmer_id']];
      final crop = cropInfo[(row['crop_name'] as String).toLowerCase()];
      return SalesTransactionRow(
        id: row['id'] as String,
        farmerName: info?.fullName ?? currentL10n().dlUnknownFarmer,
        cropType: (row['crop_name'] as String).toLowerCase(),
        cropName: row['crop_name'] as String,
        quantityKg: (row['quantity_kg'] as num).toDouble(),
        unit: unitOrDefault(row['unit'] as String?),
        amount: (row['amount'] as num?)?.toDouble() ?? 0,
        saleDate: DateTime.parse(row['sale_date'] as String).toLocal(),
        sellingType: 'informal_sale',
        marketType: crop?.marketType,
        cropCategory: crop?.category,
        buyerName: row['buyer_name'] as String?,
        fromProgram: informalProgramBatches.contains(row['inventory_batch_id']),
      );
    }).toList();
  }

  /// Channel 4/4: DA-AMAD Market Linking — previously invisible to every
  /// report. Ginger-exclusive; the buyer (found by the Admin on the
  /// farmer's behalf) sets price_per_kg, so amount = quantity × price
  /// rather than a stored total. Uses confirmed_volume_kg (the final
  /// quantity at completion) when present, falling back to the originally
  /// enrolled volume_kg.
  Future<List<SalesTransactionRow>> _fetchDaAmadMarketLinkingRowsLive(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    // One row per recorded sale (market_linking_sales), with the buyer saved
    // on it. A database without the email column yet still returns the sale.
    Future<List<Map<String, dynamic>>> read(String columns) async {
      var query = _client.from('market_linking_sales').select(columns);
      // completed_at is a timestamptz: the day starts at local midnight.
      if (startDate != null) {
        query = query.gte('completed_at', startDate.toUtc().toIso8601String());
      }
      if (endDate != null) {
        query = query.lt(
          'completed_at',
          DateTime.parse(
            _exclusiveUpperBound(endDate),
          ).toUtc().toIso8601String(),
        );
      }
      return fetchAllPages(query);
    }

    const base =
        'id, farmer_id, crop_name, confirmed_volume_kg, price_per_kg, buyer_name, buyer_contact, completed_at, recorded_by, inventory_batch_id';
    List<Map<String, dynamic>> rows;
    try {
      rows = await read('$base, buyer_email, unit');
    } catch (_) {
      try {
        rows = await read('$base, buyer_email');
      } catch (_) {
        rows = await read(base);
      }
    }
    if (rows.isEmpty) return [];

    final farmerIds = rows
        .map((r) => r['farmer_id'] as String)
        .toSet()
        .toList();
    final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);
    final cropInfo = await _fetchCropInfoByName();
    final staffNames = await _fetchStaffNames([
      for (final r in rows)
        if (r['recorded_by'] != null) r['recorded_by'] as String,
    ]);
    final linkingProgramBatches = await _programOriginBatchIds(
      rows.map((r) => r['inventory_batch_id'] as String?),
    );

    return rows.where((r) => r['completed_at'] != null).map((row) {
      final info = farmerInfo[row['farmer_id']];
      // The quantity of this one sale. Farmer Home, Farmer Transaction History
      // and this report all read the same rows, so they cannot disagree.
      final qty = (row['confirmed_volume_kg'] as num?)?.toDouble() ?? 0;

      final pricePerKg = (row['price_per_kg'] as num?)?.toDouble() ?? 0;
      final cropName = row['crop_name'] as String? ?? 'Ginger';
      return SalesTransactionRow(
        id: row['id'] as String,
        farmerName: info?.fullName ?? currentL10n().dlUnknownFarmer,
        cropType: cropName.toLowerCase(),
        cropName: cropName,
        quantityKg: qty,
        unit: unitOrDefault(row['unit'] as String?),
        amount: moneyOf(qty, pricePerKg),
        saleDate: DateTime.parse(row['completed_at'] as String).toLocal(),
        sellingType: 'da_amad_market_linking',
        // DA-AMAD is a selling channel, not a market type: this is the CROP's
        // own market type (Ginger is sold to DA-AMAD, whatever its market).
        marketType: cropInfo[cropName.toLowerCase()]?.marketType,
        cropCategory: cropInfo[cropName.toLowerCase()]?.category,
        buyerName: row['buyer_name'] as String?,
        buyerContact: row['buyer_contact'] as String?,
        buyerEmail: row['buyer_email'] as String?,
        pricePerKg: pricePerKg,
        recordedBy: staffNames[row['recorded_by']],
        fromProgram: linkingProgramBatches.contains(row['inventory_batch_id']),
      );
    }).toList();
  }

  /// Resolves each crop name to its Market Type label and category via
  /// crop_master, by name (case-insensitive) — marketplace_listings and the other
  /// sale tables have no crop_id FK to join on directly. The same lookup the
  /// Farmer's own Transaction History uses, so the two always read a crop alike.
  Future<Map<String, ({String? marketType, String? category})>>
  _fetchCropInfoByName() async {
    try {
      final rows = await _client
          .from('crop_master')
          .select('crop_name, crop_type, category');
      return {
        for (final r in rows)
          (r['crop_name'] as String).toLowerCase(): (
            marketType: r['crop_type'] == null
                ? null
                : _marketTypeLabel(r['crop_type'] as String?),
            category: r['category'] as String?,
          ),
      };
    } catch (_) {
      return {};
    }
  }

  String _marketTypeLabel(String? cropType) =>
      MarketTypes.instance.label(cropType);

  // ─── Inventory Report ───────────────────────────────────────────────────

  /// No period filter — inventory levels are a current snapshot, not
  /// something that happened within a date range.
  Future<InventoryReportData> fetchInventoryReport() async {
    try {
      // Rows are cached with the farmer and crop names resolved, so the report
      // can be viewed offline. Aggregation runs on the cached rows.
      final rows = await OfflineCache.load(
        screen: 'inventory_report',
        fetch: () async {
          // Each batch with its shelf-life row (what was reported as rotten);
          // read without it on a database that has no shelf-life tables.
          final raw = await withShelfLifeEmbed(
            '*',
            'batch_shelf_life(*)',
            (columns) => fetchAllPages(
              _client
                  .from('inventory_batches')
                  .select(columns)
                  .order('created_at', ascending: false),
            ),
          );
          if (raw.isEmpty) return <Map<String, dynamic>>[];

          final farmerIds = raw
              .map((r) => r['farmer_id'] as String)
              .toSet()
              .toList();
          final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

          final farmerCropIds = raw
              .map((r) => r['crop_id'] as String?)
              .whereType<String>()
              .toSet()
              .toList();
          final farmerCropToCropMaster = await fetchFarmerCropToCropMasterMap(
            _client,
            farmerCropIds,
          );
          final cropMasterIds = farmerCropToCropMaster.values.toSet().toList();
          final cropNames = await fetchCropNameMap(_client, cropMasterIds);

          return raw.map<Map<String, dynamic>>((row) {
            final farmerCropId = row['crop_id'] as String?;
            final cropMasterId = farmerCropId != null
                ? farmerCropToCropMaster[farmerCropId]
                : null;
            final cropName =
                (cropMasterId != null ? cropNames[cropMasterId] : null) ??
                row['crop_name'] as String;
            final info = farmerInfo[row['farmer_id']];
            return {
              ...row,
              '_farmer_name': info?.fullName ?? currentL10n().dlUnknownFarmer,
              '_crop_name': cropName,
            };
          }).toList();
        },
      );

      if (rows.isEmpty) return InventoryReportData.empty();

      double totalAvailable = 0;
      double totalReserved = 0;
      double totalSold = 0;
      double totalSpoiled = 0;
      int lowStockCount = 0;
      final cropTotals = <String, double>{};
      final batches = <InventoryReportRow>[];

      for (final row in rows) {
        final available = (row['available_kg'] as num).toDouble();
        final sold = (row['sold_kg'] as num? ?? 0).toDouble();
        // Committed = harvested - available - sold - adjusted (the same figure
        // the database keeps in reserved_kg).
        final reserved = committedBatchKg(
          quantityKg: (row['quantity_kg'] as num).toDouble(),
          availableKg: available,
          soldKg: sold,
          adjustedKg: (row['adjusted_kg'] as num? ?? 0).toDouble(),
        );
        final status = row['status'] as String? ?? 'available';
        final cropName = row['_crop_name'] as String;

        // The totals are kg figures: stock held in another unit is listed in
        // the table but never added to them.
        if (isKg(row['unit'] as String?)) {
          totalAvailable += available;
          totalReserved += reserved;
          totalSold += sold;
          totalSpoiled +=
              BatchShelfLife.fromEmbed(row['batch_shelf_life'])?.spoiledKg ?? 0;
          cropTotals[cropName] = (cropTotals[cropName] ?? 0) + available;
        }
        if (status == 'low_stock') lowStockCount++;

        batches.add(
          InventoryReportRow(
            batchId: row['id'] as String,
            farmerId: row['farmer_id'] as String,
            farmerName: row['_farmer_name'] as String,
            cropName: cropName,
            batchNumber: row['batch_number'] as String,
            quantityKg: (row['quantity_kg'] as num).toDouble(),
            availableKg: available,
            reservedKg: reserved,
            soldKg: sold,
            unit: unitOrDefault(row['unit'] as String?),
            status: status,
            createdAt: DateTime.parse(row['created_at'] as String),
            spoiledKg:
                BatchShelfLife.fromEmbed(row['batch_shelf_life'])?.spoiledKg ??
                0,
            shelfLife: BatchShelfLife.fromEmbed(row['batch_shelf_life']),
          ),
        );
      }

      final cropBreakdown =
          cropTotals.entries
              .map((e) => CropStockBreakdown(cropName: e.key, totalKg: e.value))
              .toList()
            ..sort((a, b) => b.totalKg.compareTo(a.totalKg));

      return InventoryReportData(
        totalAvailableKg: totalAvailable,
        totalReservedKg: totalReserved,
        totalSoldKg: totalSold,
        totalSpoiledKg: totalSpoiled,
        lowStockCount: lowStockCount,
        cropBreakdown: cropBreakdown,
        batches: batches,
      );
    } catch (_) {
      return InventoryReportData.empty();
    }
  }

  // ─── Harvest Report ─────────────────────────────────────────────────────

  /// What was reported as rotten from a harvest row that embeds its batch:
  /// the quantity, and whether nothing of the harvest is left (Lost).
  static ({double spoiled, bool lost}) _harvestLoss(Map<String, dynamic> row) {
    final batches = row['inventory_batches'];
    final batch = batches is List && batches.isNotEmpty
        ? batches.first
        : batches is Map
        ? batches
        : null;
    if (batch is! Map) return (spoiled: 0, lost: false);
    final spoiled =
        BatchShelfLife.fromEmbed(batch['batch_shelf_life'])?.spoiledKg ?? 0;
    final left =
        ((batch['available_kg'] as num?)?.toDouble() ?? 0) +
        ((batch['reserved_kg'] as num?)?.toDouble() ?? 0);
    return (spoiled: spoiled, lost: spoiled > 0 && left <= 0);
  }

  /// OfflineCache key for the harvest rows of [period] (matches the key written
  /// by fetchHarvestReport), so the harvest report screen can show the notice.
  static String harvestCacheScreen(ReportPeriod period) {
    final window = period.range();
    return 'harvest_report_${window.startDate?.toIso8601String() ?? 'any'}_'
        '${window.endDate?.toIso8601String() ?? 'any'}';
  }

  Future<HarvestReportData> fetchHarvestReport(ReportPeriod period) async {
    try {
      final window = period.range();
      final rows = await OfflineCache.load(
        screen:
            'harvest_report_${window.startDate?.toIso8601String() ?? 'any'}_'
            '${window.endDate?.toIso8601String() ?? 'any'}',
        fetch: () async {
          // Each harvest with its own batch and that batch's shelf-life row
          // (what was reported as rotten); read without them on a database
          // that has no shelf-life tables.
          final raw = await withShelfLifeEmbed(
            '*',
            'inventory_batches(available_kg, reserved_kg, batch_shelf_life(*))',
            (columns) {
              var query = _client
                  .from('harvest_records')
                  .select(columns)
                  .eq('source_type', 'self');
              if (window.startDate != null) {
                query = query.gte('harvest_date', _dateOnly(window.startDate!));
              }
              if (window.endDate != null) {
                query = query.lte('harvest_date', _dateOnly(window.endDate!));
              }
              return fetchAllPages(
                query.order('harvest_date', ascending: false),
              );
            },
          );
          if (raw.isEmpty) return <Map<String, dynamic>>[];

          final farmerIds = raw
              .map((r) => r['farmer_id'] as String)
              .toSet()
              .toList();
          final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

          final cropIds = raw
              .map((r) => r['crop_id'] as String?)
              .whereType<String>()
              .toSet()
              .toList();
          // harvest_records.crop_id references farmer_crops(id), NOT
          // crop_master(id) directly — see fetchInventoryReport() for the same
          // mapping. Resolved here, before caching, so the names are stored.
          final farmerCropToCropMaster = await fetchFarmerCropToCropMasterMap(
            _client,
            cropIds,
          );
          final cropMasterIds = farmerCropToCropMaster.values.toSet().toList();
          final cropNames = await fetchCropNameMap(_client, cropMasterIds);

          return raw.map<Map<String, dynamic>>((row) {
            final farmerCropId = row['crop_id'] as String?;
            final cropMasterId = farmerCropId != null
                ? farmerCropToCropMaster[farmerCropId]
                : null;
            final cropName =
                (cropMasterId != null ? cropNames[cropMasterId] : null) ??
                row['crop_name'] as String;
            final info = farmerInfo[row['farmer_id']];
            return {
              ...row,
              '_farmer_name': info?.fullName ?? currentL10n().dlUnknownFarmer,
              '_crop_name': cropName,
            };
          }).toList();
        },
      );

      double totalYield = 0;
      int unsyncedCount = 0;
      final cropTotals = <String, double>{};
      final monthlyBuckets = <String, double>{};
      final harvests = <HarvestReportRow>[];

      for (final row in rows) {
        final qty = (row['quantity_kg'] as num).toDouble();
        final cropName = row['_crop_name'] as String;
        final harvestDate = DateTime.parse(row['harvest_date'] as String);
        final isSynced = row['is_synced'] as bool? ?? true;

        // The yield, crop breakdown and trend are kg figures: a harvest
        // measured in another unit is listed in the table but never added.
        if (isKg(row['unit'] as String?)) {
          totalYield += qty;
          cropTotals[cropName] = (cropTotals[cropName] ?? 0) + qty;

          final bucketKey =
              '${harvestDate.year}-${harvestDate.month.toString().padLeft(2, '0')}';
          monthlyBuckets[bucketKey] = (monthlyBuckets[bucketKey] ?? 0) + qty;
        }
        if (!isSynced) unsyncedCount++;

        harvests.add(
          HarvestReportRow(
            id: row['id'] as String,
            farmerId: row['farmer_id'] as String,
            farmerName: row['_farmer_name'] as String,
            cropName: cropName,
            quantityKg: qty,
            unit: unitOrDefault(row['unit'] as String?),
            harvestDate: harvestDate,
            isSynced: isSynced,
            batchNumber: row['batch_number'] as String? ?? '—',
            cropCategory: row['crop_category'] as String? ?? 'Other',
            spoiledKg: _harvestLoss(row).spoiled,
            isLost: _harvestLoss(row).lost,
          ),
        );
      }

      final sortedMonthKeys = monthlyBuckets.keys.toList()..sort();
      final fullTrend = sortedMonthKeys.map((k) => monthlyBuckets[k]!).toList();
      final trend = fullTrend.length > 6
          ? fullTrend.sublist(fullTrend.length - 6)
          : fullTrend;

      final cropBreakdown =
          cropTotals.entries
              .map((e) => CropStockBreakdown(cropName: e.key, totalKg: e.value))
              .toList()
            ..sort((a, b) => b.totalKg.compareTo(a.totalKg));

      // Same 4-channel sales query set the Sales Report tab already uses
      // (_fetchOfferToCoopSalesRows etc.), same period window as the yield
      // figure above — pairs "harvested" with "sold" for one window,
      // instead of Harvest Overview's previous second card, which just
      // repeated the live Available Stock figure already shown lower on
      // this same screen regardless of which period chip was selected.
      double soldKgInPeriod = 0;
      try {
        final salesResults = await Future.wait([
          _fetchOfferToCoopSalesRows(window.startDate, window.endDate),
          _fetchMarketplaceSalesRows(window.startDate, window.endDate),
          _fetchInformalSaleRows(window.startDate, window.endDate),
          _fetchDaAmadMarketLinkingRows(window.startDate, window.endDate),
        ]);
        for (final channelRows in salesResults) {
          for (final row in channelRows) {
            // A kg figure: a sale measured in another unit is not added.
            // Produce a program gave the Farmer is not in the yield, so it is not in this comparison either.
            if (isKg(row.unit) && !row.fromProgram) soldKgInPeriod += row.quantityKg;
          }
        }
      } catch (_) {
        // Falls through to 0 — yield figures above still stand on their own.
      }

      // Produce Cooperative Programs gave Farmers in this period, on its own line (not production).
      var programReceivedKg = 0.0;
      var programReceivedCount = 0;
      try {
        var rq = _client
            .from('harvest_records')
            .select('quantity_kg, unit')
            .eq('source_type', 'program_received');
        if (window.startDate != null) rq = rq.gte('harvest_date', _dateOnly(window.startDate!));
        if (window.endDate != null) rq = rq.lte('harvest_date', _dateOnly(window.endDate!));
        for (final r in await rq) {
          programReceivedCount++;
          if (isKg(r['unit'] as String?)) programReceivedKg += (r['quantity_kg'] as num).toDouble();
        }
      } catch (_) {}

      return HarvestReportData(
        totalYieldKg: totalYield,
        harvestCount: rows.length,
        unsyncedCount: unsyncedCount,
        monthlyTrend: trend,
        cropBreakdown: cropBreakdown,
        harvests: harvests,
        soldKgInPeriod: soldKgInPeriod,
        programReceivedKg: programReceivedKg,
        programReceivedCount: programReceivedCount,
      );
    } catch (_) {
      return HarvestReportData.empty();
    }
  }

  /// Yield Trend's dedicated data source — deliberately independent of the
  /// on-screen period filter, mirroring AdminLoanRepository's
  /// fetchMonthlyCollectionTrend() exactly. fetchHarvestReport(period)'s own
  /// monthlyTrend is filtered to the SAME period selected by the chips
  /// before bucketing by month — meaning it could never show more than one
  /// point while "This Month" was selected, regardless of real harvest
  /// history. This method always looks at a fixed trailing window instead,
  /// so the trend can render correctly no matter which period chip is
  /// currently selected on screen.
  ///
  /// Always returns a dense, gap-filled array of exactly [months] entries
  /// (one per trailing calendar month, zero-filled where there's no data)
  /// when there's at least one real data point in the window — never a
  /// sparse array that skips empty months. The screen's month-label
  /// generator assumes the last entry is always the current month; a sparse
  /// array (e.g. [July, August] when September has no harvests) would
  /// silently mislabel July's value as August's. Returns [] only when the
  /// window has no data at all, so the screen's own "not enough data" state
  /// still shows correctly.
  Future<List<double>> fetchYieldTrend({int months = 6}) async {
    try {
      final now = DateTime.now();
      final cutoff = DateTime(now.year, now.month - (months - 1), 1);
      final rows = await OfflineCache.load(
        screen: 'yield_trend_$months',
        fetch: () => _client
            .from('harvest_records')
            .select('quantity_kg, unit, harvest_date').eq('source_type', 'self')
            .gte('harvest_date', _dateOnly(cutoff)),
      );
      if (rows.isEmpty) return [];

      final buckets = <String, double>{};
      for (final row in rows) {
        // A kg trend: harvests in another unit are not added to it.
        if (!isKg(row['unit'] as String?)) continue;
        final date = DateTime.parse(row['harvest_date'] as String);
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        buckets[key] =
            (buckets[key] ?? 0) + (row['quantity_kg'] as num).toDouble();
      }

      return List.generate(months, (i) {
        final offset = months - 1 - i;
        final date = DateTime(now.year, now.month - offset, 1);
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        return buckets[key] ?? 0.0;
      });
    } catch (_) {
      return [];
    }
  }

  // ─── Expense Report ─────────────────────────────────────────────────────

  /// OfflineCache key for the expense rows of [period] (matches the key written
  /// by fetchExpenseReport), so the expense report screen can show the notice.
  static String expenseCacheScreen(ReportPeriod period) {
    final window = period.range();
    return 'expense_report_${window.startDate?.toIso8601String() ?? 'any'}_'
        '${window.endDate?.toIso8601String() ?? 'any'}';
  }

  Future<ExpenseReportData> fetchExpenseReport(ReportPeriod period) async {
    try {
      final window = period.range();
      final rows = await OfflineCache.load(
        screen:
            'expense_report_${window.startDate?.toIso8601String() ?? 'any'}_'
            '${window.endDate?.toIso8601String() ?? 'any'}',
        fetch: () async {
          var query = _client.from('farmer_expenses').select('*');
          if (window.startDate != null) {
            query = query.gte('expense_date', _dateOnly(window.startDate!));
          }
          if (window.endDate != null) {
            query = query.lte('expense_date', _dateOnly(window.endDate!));
          }
          final raw = await fetchAllPages(
            query.order('expense_date', ascending: false),
          );
          if (raw.isEmpty) return <Map<String, dynamic>>[];

          final farmerIds = raw
              .map((r) => r['farmer_id'] as String)
              .toSet()
              .toList();
          final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

          return raw.map<Map<String, dynamic>>((row) {
            final info = farmerInfo[row['farmer_id']];
            return {
              ...row,
              '_farmer_name': info?.fullName ?? currentL10n().dlUnknownFarmer,
            };
          }).toList();
        },
      );

      if (rows.isEmpty) return ExpenseReportData.empty();

      final expenses = rows.map((r) => ExpenseModel.fromMap(r)).toList();

      double totalFarmerFunded = 0;
      int subsidizedCount = 0;
      int farmerFundedCount = 0;
      final monthlyBuckets = <String, double>{};
      final expenseRows = <ExpenseReportRow>[];

      for (final row in rows) {
        final expense = ExpenseModel.fromMap(row);

        if (expense.isSubsidy) {
          subsidizedCount++;
        } else {
          farmerFundedCount++;
          totalFarmerFunded += expense.amount;
          final bucketKey =
              '${expense.expenseDate.year}-${expense.expenseDate.month.toString().padLeft(2, '0')}';
          monthlyBuckets[bucketKey] =
              (monthlyBuckets[bucketKey] ?? 0) + expense.amount;
        }

        expenseRows.add(
          ExpenseReportRow(
            farmerId: row['farmer_id'] as String,
            farmerName: row['_farmer_name'] as String,
            name: expense.displayName,
            category: expense.category,
            description: expense.description,
            amount: expense.amount,
            isSubsidy: expense.isSubsidy,
            expenseDate: expense.expenseDate,
          ),
        );
      }

      final categoryBreakdown = _buildExpenseCategoryBreakdown(expenses);

      final sortedMonthKeys = monthlyBuckets.keys.toList()..sort();
      final fullTrend = sortedMonthKeys.map((k) => monthlyBuckets[k]!).toList();
      final trend = fullTrend.length > 6
          ? fullTrend.sublist(fullTrend.length - 6)
          : fullTrend;

      return ExpenseReportData(
        totalFarmerFundedAmount: totalFarmerFunded,
        subsidizedCount: subsidizedCount,
        farmerFundedCount: farmerFundedCount,
        categoryBreakdown: categoryBreakdown,
        monthlyTrend: trend,
        expenses: expenseRows,
      );
    } catch (_) {
      return ExpenseReportData.empty();
    }
  }

  /// Spending Trend's dedicated data source — deliberately independent of
  /// the on-screen period filter, mirroring fetchYieldTrend() and
  /// AdminLoanRepository.fetchMonthlyCollectionTrend() exactly.
  /// fetchExpenseReport(period)'s own monthlyTrend is filtered to the SAME
  /// period selected by the chips before bucketing by month — meaning it
  /// could never show more than one point while "This Month" was
  /// selected, regardless of real expense history. This method always
  /// looks at a fixed trailing window instead. Excludes subsidized
  /// entries, matching fetchExpenseReport()'s own totalFarmerFundedAmount
  /// convention (subsidized entries carry no peso total by design).
  ///
  /// Always returns a dense, gap-filled array of exactly [months] entries
  /// when there's at least one real data point — see fetchYieldTrend()'s
  /// doc comment for why (avoids mislabeling the x-axis when a trailing
  /// month has zero expenses).
  Future<List<double>> fetchExpenseTrend({int months = 6}) async {
    try {
      final now = DateTime.now();
      final cutoff = DateTime(now.year, now.month - (months - 1), 1);
      final rows = await OfflineCache.load(
        screen: 'expense_trend_$months',
        fetch: () => _client
            .from('farmer_expenses')
            .select('amount, expense_date, is_subsidy')
            .gte('expense_date', _dateOnly(cutoff)),
      );

      final buckets = <String, double>{};
      for (final row in rows) {
        if (row['is_subsidy'] as bool? ?? false) continue;
        final date = DateTime.parse(row['expense_date'] as String);
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        buckets[key] = (buckets[key] ?? 0) + (row['amount'] as num).toDouble();
      }
      if (buckets.isEmpty) return [];

      return List.generate(months, (i) {
        final offset = months - 1 - i;
        final date = DateTime(now.year, now.month - offset, 1);
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        return buckets[key] ?? 0.0;
      });
    } catch (_) {
      return [];
    }
  }

  /// Mirrors ExpenseRepository.buildBreakdown()'s exact algorithm, admin-
  /// scoped across all farmers. See class doc comment for why this is
  /// re-implemented here rather than calling that farmer-scoped method.
  List<CategoryBreakdown> _buildExpenseCategoryBreakdown(
    List<ExpenseModel> expenses,
  ) {
    final Map<String, double> totals = {};
    final Map<String, bool> hasSubsidy = {};

    for (final e in expenses) {
      if (!e.isSubsidy) {
        totals[e.category] = (totals[e.category] ?? 0) + e.amount;
      } else {
        hasSubsidy[e.category] = true;
      }
    }

    for (final cat in hasSubsidy.keys) {
      totals.putIfAbsent(cat, () => 0);
    }

    if (totals.isEmpty) return [];

    final maxVal = totals.values.reduce((a, b) => a > b ? a : b);
    return totals.entries
        .map(
          (e) => CategoryBreakdown(
            category: e.key,
            total: e.value,
            percentOfMax: maxVal > 0 ? (e.value / maxVal).clamp(0.0, 1.0) : 1.0,
            hasSubsidy: hasSubsidy.containsKey(e.key),
          ),
        )
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  /// Which years the Member Contribution Report's year selector should
  /// actually offer — the distinct years member_sales_transactions has
  /// real rows for (the same table fetchMemberSalesTotals() reads),
  /// always including the current year even if it has no rows yet, so
  /// the selector never advertises years with nothing to show and never
  /// hides the current, most-relevant year while it's still empty.
  /// Sorted most-recent-first, matching every other year-descending list
  /// in Reports.
  Future<List<int>> fetchAvailableContributionYears() async {
    final now = DateTime.now().year;
    var earliest = now;
    Future<void> consider(
      String table,
      String column, {
      String? status,
      String? source,
    }) async {
      try {
        var query = _client.from(table).select(column);
        if (status != null) query = query.eq('status', status);
        if (source != null) query = query.eq('source', source);
        final rows = await query.not(column, 'is', null).order(column).limit(1);
        if (rows.isEmpty) return;
        final year = DateTime.parse(
          rows.first[column] as String,
        ).toLocal().year;
        if (year < earliest) earliest = year;
      } catch (_) {}
    }

    // The first record of any of the three sources decides where the list starts.
    await Future.wait([
      consider('member_sales_transactions', 'sale_date'),
      consider(
        'program_product_purchases',
        'completed_at',
        status: 'completed',
      ),
      consider('capital_contribution_events', 'created_at'),
      // A Starting Capital dated in an earlier year opens that year's report.
      consider(
        'capital_contribution_events',
        'effective_date',
        source: 'opening_balance',
      ),
    ]);
    // Newest first, with no gaps, and never a year that has not started yet.
    return [for (var y = now; y >= earliest; y--) y];
  }

  /// OfflineCache key for the member contribution rows of [year] (matches the key
  /// written by fetchMemberContributionReport), so the screen can show the notice.
  static String memberContributionCacheScreen(int year) =>
      'member_contribution_report_$year';

  Future<MemberContributionReportData> fetchMemberContributionReport(
    int year,
  ) async {
    try {
      // One cached row per active farmer, with that farmer's totals and name
      // merged in. The cooperative-wide totals are repeated on each row, so the
      // report can be rebuilt offline.
      final rows = await OfflineCache.load(
        screen: 'member_contribution_report_$year',
        fetch: () async {
          final results = await Future.wait([
            fetchMemberSalesTotals(_client, year),
            fetchMemberProgramPurchaseTotals(_client, year),
            fetchMemberProgramPurchaseBreakdown(_client, year),
            fetchMemberCapitalYear(_client, year),
            _fetchCapitalShareRows(),
            fetchMemberMonthlyYear(_client, year),
          ]);
          final capitalYear = results[3] as Map<String, MemberCapitalYear>;
          final capitalRows = results[4] as Map<String, Map<String, dynamic>>;
          final monthlyYear = results[5] as Map<String, MemberMonthlyYear>;
          final isThisYear = year == DateTime.now().year;
          // The settings history: how many times the percentages were changed and
          // which version is the current one (newly credited = the latest).
          final versions = await CapitalShareRatesRepository().fetchVersions();
          final salesTotals = results[0] as Map<String, MemberSalesTotals>;
          final purchaseTotals = results[1] as Map<String, double>;
          final purchaseBreakdown =
              results[2] as Map<String, ProgramPurchaseBreakdown>;

          // Active members only — a removed or suspended account is not a member of the year.
          final activeRoleRows = await _client
              .from('user_roles')
              .select('user_id')
              .eq('role', 'farmer')
              .eq('status', 'active');
          final activeIds = activeRoleRows
              .map((r) => r['user_id'] as String)
              .toList();
          if (activeIds.isEmpty) return <Map<String, dynamic>>[];

          final rosterRows = await chunkedIn(activeIds, (slice) => _client.from('farmer_profiles').select('user_id').inFilter('user_id', slice));
          final farmerIds = rosterRows
              .map((r) => r['user_id'] as String)
              .toList();
          final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

          return farmerIds.map<Map<String, dynamic>>((farmerId) {
            final info = farmerInfo[farmerId];
            final MemberSalesTotals totals =
                salesTotals[farmerId] ?? MemberSalesTotals();
            return {
              'farmer_id': farmerId,
              'farmer_name': info?.fullName ?? currentL10n().dlUnknownFarmer,
              'palay_qty_kg': totals.palayQtyKg,
              'palay_amount': totals.palayAmount,
              'peanut_qty_kg': totals.peanutQtyKg,
              'peanut_amount': totals.peanutAmount,
              'total_amount': totals.totalAmount,
              'other_crops_qty_kg': totals.otherCropsQtyKg,
              'other_crops_amount': totals.otherCropsAmount,
              'purchases_amount': purchaseTotals[farmerId] ?? 0,
              'purchases_regular': purchaseBreakdown[farmerId]?.regular ?? 0,
              'purchases_discount': purchaseBreakdown[farmerId]?.discount ?? 0,
              // Paid toward the year's months, from the Contribution section.
              // Every monthly payment of the year: those tied to a month plus the
              // earlier ones that were never tied to a month (both are in the
              // Capital Share, so both are contributions).
              // Payments received in the year, from the capital ledger (every
              // member_payment of the year, tied to a month or not): this is what
              // the Monthly Contributions added to the Capital Share.
              'monthly': capitalYear[farmerId]?.monthly ?? 0,
              'capital_at_start':
                  capitalYear[farmerId]?.balanceAtYearStart ?? 0,
              'records':
                  capitalYear[farmerId]?.records ??
                  const <Map<String, dynamic>>[],
              'purchase_by_version':
                  capitalYear[farmerId]?.purchaseByVersion ??
                  const <String, List<double>>{},
              'offer_by_version':
                  capitalYear[farmerId]?.offerByVersion ??
                  const <String, List<double>>{},
              'credit_versions':
                  capitalYear[farmerId]?.creditVersions ??
                  const <String, int>{},
              '_latest_version': versions.isEmpty ? 1 : versions.last.version,
              '_rate_changes': versions.length > 1 ? versions.length - 1 : 0,
              'months':
                  ((monthlyYear[farmerId]?.months ??
                          const <Map<String, dynamic>>[])
                      .toList()
                    ..sort(
                      (a, b) => (a['month'] as String).compareTo(
                        b['month'] as String,
                      ),
                    )),
              'monthly_due': monthlyYear[farmerId]?.due ?? 0,
              'monthly_balance': monthlyYear[farmerId]?.balance ?? 0,
              'months_paid': monthlyYear[farmerId]?.paidMonths ?? 0,
              'months_partial': monthlyYear[farmerId]?.partial ?? 0,
              'months_unpaid': monthlyYear[farmerId]?.unpaid ?? 0,
              'months_overdue': monthlyYear[farmerId]?.overdue ?? 0,
              'months_waived': monthlyYear[farmerId]?.waived ?? 0,
              'monthly_unassigned':
                  capitalYear[farmerId]?.monthlyUnassigned ?? 0,
              'discount_credited': capitalYear[farmerId]?.discountCredited ?? 0,
              'purchase_share': capitalYear[farmerId]?.purchaseShare ?? 0,
              'purchase_share_base':
                  capitalYear[farmerId]?.purchaseShareBase ?? 0,
              'offer_share': capitalYear[farmerId]?.offerShare ?? 0,
              'offer_share_base': capitalYear[farmerId]?.offerShareBase ?? 0,
              'starting_capital': capitalYear[farmerId]?.startingCapital ?? 0,
              // This year the figure is the member's live Capital Share (the same
              // row Farmer Details shows); a past year is the ledger at year end.
              'capital_balance': isThisYear && capitalRows[farmerId] != null
                  ? (capitalRows[farmerId]!['total_contribution'] as num? ?? 0)
                  : (capitalYear[farmerId]?.balanceAtYearEnd ?? 0),
              'capital_shares': _sharesFor(
                capitalRows[farmerId],
                capitalYear[farmerId]?.balanceAtYearEnd ?? 0,
                isThisYear,
              ),
              'share_value':
                  (capitalRows[farmerId]?['share_value_per_unit'] as num?) ??
                  2000,
            };
          }).toList();
        },
      );

      if (rows.isEmpty) return MemberContributionReportData.empty(year);

      final reportRows = rows.map((row) {
        final totalAmount = (row['total_amount'] as num).toDouble();
        final purchasesAmount = (row['purchases_amount'] as num).toDouble();
        return MemberContributionRow(
          farmerId: row['farmer_id'] as String,
          farmerName: row['farmer_name'] as String,
          palayQtyKg: (row['palay_qty_kg'] as num).toDouble(),
          palayAmount: (row['palay_amount'] as num).toDouble(),
          peanutQtyKg: (row['peanut_qty_kg'] as num).toDouble(),
          peanutAmount: (row['peanut_amount'] as num).toDouble(),
          totalAmount: totalAmount,
          otherCropsQtyKg: (row['other_crops_qty_kg'] as num).toDouble(),
          otherCropsAmount: (row['other_crops_amount'] as num).toDouble(),
          programPurchasesAmount: purchasesAmount,
          programRegularAmount:
              (row['purchases_regular'] as num?)?.toDouble() ?? 0,
          programDiscountAmount:
              (row['purchases_discount'] as num?)?.toDouble() ?? 0,
          monthlyContributions: (row['monthly'] as num?)?.toDouble() ?? 0,
          monthlyDue: (row['monthly_due'] as num?)?.toDouble() ?? 0,
          monthlyBalance: (row['monthly_balance'] as num?)?.toDouble() ?? 0,
          monthsPaid: (row['months_paid'] as num?)?.toInt() ?? 0,
          monthsPartial: (row['months_partial'] as num?)?.toInt() ?? 0,
          monthsUnpaid: (row['months_unpaid'] as num?)?.toInt() ?? 0,
          monthsOverdue: (row['months_overdue'] as num?)?.toInt() ?? 0,
          monthsWaived: (row['months_waived'] as num?)?.toInt() ?? 0,
          monthlyUnassigned:
              (row['monthly_unassigned'] as num?)?.toDouble() ?? 0,
          discountCredited: (row['discount_credited'] as num?)?.toDouble() ?? 0,
          purchaseShareCredited:
              (row['purchase_share'] as num?)?.toDouble() ?? 0,
          purchaseShareBase:
              (row['purchase_share_base'] as num?)?.toDouble() ?? 0,
          offerShareCredited: (row['offer_share'] as num?)?.toDouble() ?? 0,
          offerShareBase: (row['offer_share_base'] as num?)?.toDouble() ?? 0,
          startingCapital: (row['starting_capital'] as num?)?.toDouble() ?? 0,
          capitalBalance: (row['capital_balance'] as num?)?.toDouble() ?? 0,
          capitalShares: (row['capital_shares'] as num?)?.toInt() ?? 0,
          capitalShareValue: (row['share_value'] as num?)?.toDouble() ?? 2000,
          capitalAtYearStart:
              (row['capital_at_start'] as num?)?.toDouble() ?? 0,
          purchaseByVersion: parseCreditSlices(row['purchase_by_version']),
          offerByVersion: parseCreditSlices(row['offer_by_version']),
          creditVersions: {
            if (row['credit_versions'] is Map)
              for (final e in (row['credit_versions'] as Map).entries)
                '${e.key}': (e.value as num).toInt(),
          },
          latestRateVersion: (row['_latest_version'] as num?)?.toInt() ?? 1,
          rateChanges: (row['_rate_changes'] as num?)?.toInt() ?? 0,
          records: [
            for (final m in (row['records'] as List?) ?? const [])
              MemberCapitalRecord.fromMap(Map<String, dynamic>.from(m as Map)),
          ],
          months: [
            for (final m in (row['months'] as List?) ?? const [])
              MemberMonthStatus.fromMap(Map<String, dynamic>.from(m as Map)),
          ],
        );
      }).toList()..sort((a, b) => b.capitalBalance.compareTo(a.capitalBalance));

      return MemberContributionReportData(
        year: year,
        memberCount: reportRows.length,
        contributingMemberCount: reportRows
            .where((r) => r.hasAnyActivity)
            .length,
        rows: reportRows,
      );
    } catch (_) {
      return MemberContributionReportData.empty(year);
    }
  }

  /// Every member's live Capital Share row (what Farmer Details shows).
  Future<Map<String, Map<String, dynamic>>> _fetchCapitalShareRows() async {
    try {
      final rows = await _client
          .from('member_capital_shares')
          .select(
            'farmer_id, total_shares, share_value_per_unit, total_contribution',
          );
      return {for (final r in rows) r['farmer_id'] as String: r};
    } catch (_) {
      return {};
    }
  }

  /// Whole shares: this year the live count, a past year the ledger balance
  /// divided by the share value (₱2,000 unless the member's row says otherwise).
  static int _sharesFor(
    Map<String, dynamic>? live,
    double yearEndBalance,
    bool isThisYear,
  ) {
    if (isThisYear && live != null) {
      return (live['total_shares'] as num?)?.toInt() ?? 0;
    }
    final value = (live?['share_value_per_unit'] as num?)?.toDouble() ?? 2000;
    return value > 0 ? (yearEndBalance / value).floor() : 0;
  }

  Future<CoopStockReportData> fetchCoopStockReport() async {
    try {
      final rows = await OfflineCache.load(
        screen: 'coop_stock_report',
        fetch: () => _client
            .from('cooperative_inventory')
            .select('*')
            .eq('is_active', true)
            .order('item_name'),
      );

      if (rows.isEmpty) return CoopStockReportData.empty;

      final categoryTotals = <String, int>{};
      int lowStockCount = 0;
      final items = <CoopStockReportRow>[];

      for (final row in rows) {
        final onHand = (row['quantity_on_hand'] as num).toDouble();
        final reorder = (row['reorder_level'] as num?)?.toDouble() ?? 0;
        final category = row['category'] as String;
        final isLow = onHand <= reorder;

        categoryTotals[category] = (categoryTotals[category] ?? 0) + 1;
        if (isLow) lowStockCount++;

        items.add(
          CoopStockReportRow(
            id: row['id'] as String,
            itemName: row['item_name'] as String,
            category: category,
            itemType: row['item_type'] as String? ?? 'non_crop',
            unit: row['unit'] as String,
            quantityOnHand: onHand,
            reorderLevel: reorder,
            isLowStock: isLow,
            unitCost: (row['unit_cost'] as num?)?.toDouble(),
            lastRestockedAt: row['last_restocked_at'] != null
                ? DateTime.tryParse(row['last_restocked_at'] as String)
                : null,
            imageUrl: row['image_url'] as String?,
          ),
        );
      }

      return CoopStockReportData(
        totalItems: rows.length,
        lowStockCount: lowStockCount,
        categoryCounts: categoryTotals,
        items: items,
        seedsItemCount: items.where((i) => i.itemType == 'seeds_seedlings').length,
        produceItemCount: items.where((i) => i.itemType == 'harvested_produce').length,
        nonCropItemCount: items.where((i) => i.itemType == 'non_crop').length,
      );
    } catch (_) {
      return CoopStockReportData.empty;
    }
  }

  /// Lightweight preview for the Cooperative Stock Report card — reuses
  /// fetchCoopStockReport() as-is rather than a second query path.
  Future<int> fetchLowStockCount() async {
    final data = await fetchCoopStockReport();
    return data.lowStockCount;
  }

  /// For TIMESTAMPTZ columns only (orders.created_at, marketplace_listings
  /// .submitted_at). _dateOnly() truncates to midnight, so an .lte() upper
  /// bound against it silently excludes same-day activity after 00:00:00.
  /// Use as: query.lt(column, _exclusiveUpperBound(endDate))
  String _exclusiveUpperBound(DateTime d) =>
      _dateOnly(d.add(const Duration(days: 1)));

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;
}
