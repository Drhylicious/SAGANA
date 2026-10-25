import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/offline_cache.dart';
import '../../core/utils/order_reference.dart';
import '../../core/utils/quantity_utils.dart';
import '../models/admin_reports_model.dart';
import 'crop_lookup.dart';
import 'farmer_lookup.dart';
import '../models/expense_model.dart';
import 'member_sales_aggregation.dart';
import '../services/market_types_service.dart';

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
      ]);

      return PerformanceSummary(
        totalHarvestKg: results[0] as double,
        coopSalesAmount: results[1] as double,
        marketplaceRevenue: results[2] as double,
        activeLoanOutstanding: results[3] as double,
        totalExpenses: results[4] as double,
        memberParticipationPercent: results[5] as double,
        totalSalesAmount: (results[6] as SalesReportData).totalRevenue,
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
      var query = _client.from('harvest_records').select('quantity_kg, unit');
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
      var query = _client
          .from('orders')
          .select('total_price')
          .eq('status', 'completed');
      if (startDate != null) {
        query = query.gte('created_at', _dateOnly(startDate));
      }
      if (endDate != null) {
        query = query.lt('created_at', _exclusiveUpperBound(endDate));
      }
      final rows = await OfflineCache.load(
        screen:
            'perf_marketplace_${startDate?.toIso8601String() ?? 'any'}_${endDate?.toIso8601String() ?? 'any'}',
        fetch: () => query,
      );
      return rows.fold<double>(
        0,
        (sum, r) => sum + (r['total_price'] as num).toDouble(),
      );
    } catch (_) {
      return 0;
    }
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
              '_farmer_name': info?.fullName ?? 'Unknown Farmer',
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
        topFarmerName: farmerNames[topFarmerEntry.key] ?? 'Unknown Farmer',
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

      var harvestQuery = _client.from('harvest_records').select('farmer_id');
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
          startDate.toIso8601String(),
        );
      }
      if (endDate != null) {
        listingQuery = listingQuery.lt(
          'submitted_at',
          _exclusiveUpperBound(endDate),
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
    final rows = await query;
    if (rows.isEmpty) return [];

    final farmerIds = rows
        .map((r) => r['farmer_id'] as String)
        .toSet()
        .toList();
    final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

    return rows.map((row) {
      final info = farmerInfo[row['farmer_id']];
      return SalesTransactionRow(
        id: row['id'] as String,
        farmerName: info?.fullName ?? 'Unknown Farmer',
        cropType: row['crop_type'] as String? ?? 'palay',
        cropName: row['crop_name'] as String,
        quantityKg: (row['quantity_kg'] as num).toDouble(),
        unit: unitOrDefault(row['unit'] as String?),
        amount: (row['amount'] as num).toDouble(),
        saleDate: DateTime.parse(row['sale_date'] as String),
        referenceNo: row['reference_no'] as String?,
        sellingType: 'offer_to_cooperative',
        marketType: null,
      );
    }).toList();
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
    var query = _client
        .from('orders')
        .select(
          'id, order_number, listing_id, buyer_id, quantity_kg, unit, total_price, status, created_at',
        )
        .eq('status', 'completed');
    if (startDate != null) {
      query = query.gte('created_at', _dateOnly(startDate));
    }
    if (endDate != null) {
      query = query.lt('created_at', _exclusiveUpperBound(endDate));
    }
    final rows = await query;
    if (rows.isEmpty) return [];

    final listingIds = rows
        .map((r) => r['listing_id'] as String)
        .toSet()
        .toList();
    final listingRows = await _client
        .from('marketplace_listings')
        .select('id, farmer_id, crop_name')
        .inFilter('id', listingIds);
    final listingMap = {for (final l in listingRows) l['id'] as String: l};

    final farmerIds = listingRows
        .map((l) => l['farmer_id'] as String)
        .toSet()
        .toList();
    final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

    final cropNames = listingRows
        .map((l) => l['crop_name'] as String)
        .toSet()
        .toList();
    final marketTypeMap = await _fetchMarketTypeByCropName(cropNames);

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
      final buyerRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', buyerIds);
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
        farmerName: info?.fullName ?? 'Unknown Farmer',
        cropType: cropName.toLowerCase(),
        cropName: cropName,
        quantityKg: (row['quantity_kg'] as num).toDouble(),
        unit: unitOrDefault(row['unit'] as String?),
        amount: (row['total_price'] as num).toDouble(),
        saleDate: DateTime.parse(row['created_at'] as String),
        referenceNo: orderReferenceOf(row['id'] as String, row['order_number'] as String?),
        sellingType: 'marketplace',
        marketType: marketTypeMap[cropName.toLowerCase()],
        buyerName: buyerNameById[row['buyer_id']],
        orderStatus: row['status'] as String?,
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
          'id, farmer_id, crop_name, quantity_kg, unit, amount, buyer_name, sale_date',
        );
    if (startDate != null) {
      query = query.gte('sale_date', startDate.toIso8601String());
    }
    if (endDate != null) {
      query = query.lt('sale_date', _exclusiveUpperBound(endDate));
    }
    final rows = await query;
    if (rows.isEmpty) return [];

    final farmerIds = rows
        .map((r) => r['farmer_id'] as String)
        .toSet()
        .toList();
    final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

    return rows.map((row) {
      final info = farmerInfo[row['farmer_id']];
      return SalesTransactionRow(
        id: row['id'] as String,
        farmerName: info?.fullName ?? 'Unknown Farmer',
        cropType: (row['crop_name'] as String).toLowerCase(),
        cropName: row['crop_name'] as String,
        quantityKg: (row['quantity_kg'] as num).toDouble(),
        unit: unitOrDefault(row['unit'] as String?),
        amount: (row['amount'] as num?)?.toDouble() ?? 0,
        saleDate: DateTime.parse(row['sale_date'] as String),
        sellingType: 'informal_sale',
        marketType: null,
        buyerName: row['buyer_name'] as String?,
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
    var query = _client
        .from('market_linking_programs')
        .select(
          'id, farmer_id, crop_name, volume_kg, requested_volume_kg, confirmed_volume_kg, price_per_kg, buyer_name, completed_at',
        )
        .eq('status', 'completed');
    if (startDate != null) {
      query = query.gte('completed_at', startDate.toIso8601String());
    }
    if (endDate != null) {
      query = query.lt('completed_at', _exclusiveUpperBound(endDate));
    }
    final rows = await query;
    if (rows.isEmpty) return [];

    final farmerIds = rows
        .map((r) => r['farmer_id'] as String)
        .toSet()
        .toList();
    final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

    return rows.where((r) => r['completed_at'] != null).map((row) {
      final info = farmerInfo[row['farmer_id']];
      // The quantity actually sold: the confirmed volume if one was set at
      // completion, else what the buyer asked for, else what the farmer
      // enrolled. Farmer Home, Farmer Transaction History and this report all
      // use the same order, so they cannot disagree.
      final qty =
          (row['confirmed_volume_kg'] as num?)?.toDouble() ??
          (row['requested_volume_kg'] as num?)?.toDouble() ??
          (row['volume_kg'] as num?)?.toDouble() ??
          0;
      final pricePerKg = (row['price_per_kg'] as num?)?.toDouble() ?? 0;
      final cropName = row['crop_name'] as String? ?? 'Ginger';
      return SalesTransactionRow(
        id: row['id'] as String,
        farmerName: info?.fullName ?? 'Unknown Farmer',
        cropType: cropName.toLowerCase(),
        cropName: cropName,
        quantityKg: qty,
        amount: moneyOf(qty, pricePerKg),
        saleDate: DateTime.parse(row['completed_at'] as String),
        sellingType: 'da_amad_market_linking',
        // DA-AMAD is a selling channel, not a market type.
        marketType: null,
        buyerName: row['buyer_name'] as String?,
      );
    }).toList();
  }

  /// Resolves each crop name to its Market Type label via crop_master,
  /// by name (case-insensitive) — marketplace_listings has no crop_id FK
  /// to join on directly.
  Future<Map<String, String>> _fetchMarketTypeByCropName(
    List<String> cropNames,
  ) async {
    if (cropNames.isEmpty) return {};
    try {
      final rows = await _client
          .from('crop_master')
          .select('crop_name, crop_type');
      final map = <String, String>{};
      for (final r in rows) {
        final name = (r['crop_name'] as String).toLowerCase();
        map[name] = _marketTypeLabel(r['crop_type'] as String?);
      }
      return map;
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
          final raw = await _client
              .from('inventory_batches')
              .select('*')
              .order('created_at', ascending: false);
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
              '_farmer_name': info?.fullName ?? 'Unknown Farmer',
              '_crop_name': cropName,
            };
          }).toList();
        },
      );

      if (rows.isEmpty) return InventoryReportData.empty();

      double totalAvailable = 0;
      double totalReserved = 0;
      double totalSold = 0;
      int lowStockCount = 0;
      final cropTotals = <String, double>{};
      final batches = <InventoryReportRow>[];

      for (final row in rows) {
        final available = (row['available_kg'] as num).toDouble();
        final sold = (row['sold_kg'] as num? ?? 0).toDouble();
        // The stored reserved_kg column is never written by the reservation
        // model (always 0), so the committed amount is derived instead.
        final reserved = committedBatchKg(
          quantityKg: (row['quantity_kg'] as num).toDouble(),
          availableKg: available,
          soldKg: sold,
        );
        final status = row['status'] as String? ?? 'available';
        final cropName = row['_crop_name'] as String;

        // The totals are kg figures: stock held in another unit is listed in
        // the table but never added to them.
        if (isKg(row['unit'] as String?)) {
          totalAvailable += available;
          totalReserved += reserved;
          totalSold += sold;
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
        lowStockCount: lowStockCount,
        cropBreakdown: cropBreakdown,
        batches: batches,
      );
    } catch (_) {
      return InventoryReportData.empty();
    }
  }

  // ─── Harvest Report ─────────────────────────────────────────────────────

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
          var query = _client.from('harvest_records').select('*');
          if (window.startDate != null) {
            query = query.gte('harvest_date', _dateOnly(window.startDate!));
          }
          if (window.endDate != null) {
            query = query.lte('harvest_date', _dateOnly(window.endDate!));
          }
          final raw = await query.order('harvest_date', ascending: false);
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
              '_farmer_name': info?.fullName ?? 'Unknown Farmer',
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
            if (isKg(row.unit)) soldKgInPeriod += row.quantityKg;
          }
        }
      } catch (_) {
        // Falls through to 0 — yield figures above still stand on their own.
      }

      return HarvestReportData(
        totalYieldKg: totalYield,
        harvestCount: rows.length,
        unsyncedCount: unsyncedCount,
        monthlyTrend: trend,
        cropBreakdown: cropBreakdown,
        harvests: harvests,
        soldKgInPeriod: soldKgInPeriod,
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
            .select('quantity_kg, unit, harvest_date')
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
          final raw = await query.order('expense_date', ascending: false);
          if (raw.isEmpty) return <Map<String, dynamic>>[];

          final farmerIds = raw
              .map((r) => r['farmer_id'] as String)
              .toSet()
              .toList();
          final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

          return raw.map<Map<String, dynamic>>((row) {
            final info = farmerInfo[row['farmer_id']];
            return {...row, '_farmer_name': info?.fullName ?? 'Unknown Farmer'};
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

  /// Which years the Member Patronage Report's year selector should
  /// actually offer — the distinct years member_sales_transactions has
  /// real rows for (the same table fetchMemberSalesTotals() reads),
  /// always including the current year even if it has no rows yet, so
  /// the selector never advertises years with nothing to show and never
  /// hides the current, most-relevant year while it's still empty.
  /// Sorted most-recent-first, matching every other year-descending list
  /// in Reports.
  Future<List<int>> fetchAvailablePatronageYears() async {
    try {
      final rows = await _client
          .from('member_sales_transactions')
          .select('sale_date');
      final years = rows
          .map((r) => DateTime.parse(r['sale_date'] as String).year)
          .toSet();
      years.add(DateTime.now().year);
      return years.toList()..sort((a, b) => b.compareTo(a));
    } catch (_) {
      return [DateTime.now().year];
    }
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
          ]);
          final salesTotals = results[0] as Map<String, MemberSalesTotals>;
          final purchaseTotals = results[1] as Map<String, double>;

          // Active members only — see BalikTangkilikRepository.
          // fetchDistributionPreview() for the full reasoning; this method
          // shares the identical previously-unfiltered farmer_profiles bug.
          final activeRoleRows = await _client
              .from('user_roles')
              .select('user_id')
              .eq('role', 'farmer')
              .eq('status', 'active');
          final activeIds = activeRoleRows
              .map((r) => r['user_id'] as String)
              .toList();
          if (activeIds.isEmpty) return <Map<String, dynamic>>[];

          final rosterRows = await _client
              .from('farmer_profiles')
              .select('user_id')
              .inFilter('user_id', activeIds);
          final farmerIds = rosterRows
              .map((r) => r['user_id'] as String)
              .toList();
          final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

          double totalCoopSales = 0;
          for (final totals in salesTotals.values) {
            totalCoopSales += totals.totalAmount;
          }
          double totalProgramPurchases = 0;
          for (final amount in purchaseTotals.values) {
            totalProgramPurchases += amount;
          }

          return farmerIds.map<Map<String, dynamic>>((farmerId) {
            final info = farmerInfo[farmerId];
            final MemberSalesTotals totals =
                salesTotals[farmerId] ?? MemberSalesTotals();
            return {
              'farmer_id': farmerId,
              'farmer_name': info?.fullName ?? 'Unknown Farmer',
              'palay_qty_kg': totals.palayQtyKg,
              'palay_amount': totals.palayAmount,
              'peanut_qty_kg': totals.peanutQtyKg,
              'peanut_amount': totals.peanutAmount,
              'total_amount': totals.totalAmount,
              'other_crops_qty_kg': totals.otherCropsQtyKg,
              'other_crops_amount': totals.otherCropsAmount,
              'purchases_amount': purchaseTotals[farmerId] ?? 0,
              '_total_coop_sales': totalCoopSales,
              '_total_program_purchases': totalProgramPurchases,
            };
          }).toList();
        },
      );

      if (rows.isEmpty) return MemberContributionReportData.empty(year);

      final totalCoopSales = (rows.first['_total_coop_sales'] as num)
          .toDouble();
      final totalProgramPurchases =
          (rows.first['_total_program_purchases'] as num).toDouble();

      final reportRows =
          rows.map((row) {
            final totalAmount = (row['total_amount'] as num).toDouble();
            final purchasesAmount = (row['purchases_amount'] as num).toDouble();
            final sharePercent = computeMemberSharePercent(
              memberSales: totalAmount,
              coopTotalSales: totalCoopSales,
            );
            final purchaseSharePercent = computeMemberSharePercent(
              memberSales: purchasesAmount,
              coopTotalSales: totalProgramPurchases,
            );
            return MemberContributionRow(
              farmerId: row['farmer_id'] as String,
              farmerName: row['farmer_name'] as String,
              palayQtyKg: (row['palay_qty_kg'] as num).toDouble(),
              palayAmount: (row['palay_amount'] as num).toDouble(),
              peanutQtyKg: (row['peanut_qty_kg'] as num).toDouble(),
              peanutAmount: (row['peanut_amount'] as num).toDouble(),
              totalAmount: totalAmount,
              sharePercent: sharePercent,
              otherCropsQtyKg: (row['other_crops_qty_kg'] as num).toDouble(),
              otherCropsAmount: (row['other_crops_amount'] as num).toDouble(),
              programPurchasesAmount: purchasesAmount,
              purchaseSharePercent: purchaseSharePercent,
            );
          }).toList()..sort(
            (a, b) => b.combinedTotalAmount.compareTo(a.combinedTotalAmount),
          );

      return MemberContributionReportData(
        year: year,
        totalCoopSales: totalCoopSales,
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
