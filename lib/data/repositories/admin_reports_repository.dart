import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_reports_model.dart';
import 'crop_lookup.dart';
import 'farmer_lookup.dart';
import '../models/expense_model.dart';
import 'member_sales_aggregation.dart';

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
    return fetchPerformanceSummaryForRange(previous.startDate, previous.endDate);
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
        _fetchMemberParticipationPercent(startDate: startDate, endDate: endDate),
      ]);

      return PerformanceSummary(
        totalHarvestKg: results[0],
        coopSalesAmount: results[1],
        marketplaceRevenue: results[2],
        activeLoanOutstanding: results[3],
        totalExpenses: results[4],
        memberParticipationPercent: results[5],
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
      var query = _client.from('harvest_records').select('quantity_kg');
      if (startDate != null) {
        query = query.gte('harvest_date', _dateOnly(startDate));
      }
      if (endDate != null) {
        query = query.lte('harvest_date', _dateOnly(endDate));
      }
      final rows = await query;
      return rows.fold<double>(
        0,
        (sum, r) => sum + (r['quantity_kg'] as num).toDouble(),
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
      final rows = await query;
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
      final rows = await query;
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
      final rows = await _client
          .from('farmer_loans')
          .select('total_value, amount_paid')
          .inFilter('status', ['active', 'overdue']);
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
      var query = _client.from('member_sales_transactions').select('*');
      if (window.startDate != null) {
        query = query.gte('sale_date', _dateOnly(window.startDate!));
      }
      if (window.endDate != null) {
        query = query.lte('sale_date', _dateOnly(window.endDate!));
      }
      final rows = await query;
      if (rows.isEmpty) return QuickInsights.empty();

      final cropIds = rows
          .map((r) => r['crop_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final cropNames = await fetchCropNameMap(_client, cropIds);

      final cropTotals = <String, double>{};
      final farmerTotals = <String, double>{};
      for (final row in rows) {
        final amount = (row['amount'] as num).toDouble();
        final cropId = row['crop_id'] as String?;
        final crop = (cropId != null ? cropNames[cropId] : null) ?? row['crop_name'] as String;
        final farmerId = row['farmer_id'] as String;
        cropTotals[crop] = (cropTotals[crop] ?? 0) + amount;
        farmerTotals[farmerId] = (farmerTotals[farmerId] ?? 0) + amount;
      }

      final topCropEntry = cropTotals.entries.reduce((a, b) => a.value > b.value ? a : b);
      final topFarmerEntry = farmerTotals.entries.reduce((a, b) => a.value > b.value ? a : b);
      final farmerInfo = await fetchFarmerInfoMap(_client, [topFarmerEntry.key]);

      final expenseRows = await _client
          .from('farmer_expenses')
          .select('category, amount')
          .eq('is_subsidy', false);
      final expenseCategoryTotals = <String, double>{};
      for (final row in expenseRows) {
        final cat = row['category'] as String;
        expenseCategoryTotals[cat] =
            (expenseCategoryTotals[cat] ?? 0) + (row['amount'] as num).toDouble();
      }
      final topExpenseCategory = expenseCategoryTotals.isEmpty
          ? null
          : expenseCategoryTotals.entries.reduce((a, b) => a.value > b.value ? a : b);

      return QuickInsights(
        topCropName: topCropEntry.key,
        topCropAmount: topCropEntry.value,
        topFarmerName: farmerInfo[topFarmerEntry.key]?.fullName ?? 'Unknown Farmer',
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
      final rows = await query;
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
      final totalFarmersRows = await _client
          .from('farmer_profiles')
          .select('user_id');
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
      final harvestRows = await harvestQuery;
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
      final salesRows = await salesQuery;
      activeIds.addAll(salesRows.map((r) => r['farmer_id'] as String));

      var listingQuery = _client
          .from('marketplace_listings')
          .select('farmer_id');
      if (startDate != null) {
        listingQuery = listingQuery.gte('submitted_at', startDate.toIso8601String());
      }
      if (endDate != null) {
        listingQuery = listingQuery.lt('submitted_at', _exclusiveUpperBound(endDate));
      }
      final listingRows = await listingQuery;
      activeIds.addAll(listingRows.map((r) => r['farmer_id'] as String));

      return (activeIds.length / totalFarmers * 100).clamp(0, 100);
    } catch (_) {
      return 0;
    }
  }

  // ─── Sales Report ───────────────────────────────────────────────────────

  /// Reports on member_sales_transactions (direct Palay/Peanut sales to
  /// SP3) per the agreed pivot away from the empty `orders` table. Trend
  /// is aggregated by month, capped to the most recent 6 buckets within
  /// the selected period so the chart stays readable regardless of range.
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
      var query = _client.from('member_sales_transactions').select('*');
      if (startDate != null) {
        query = query.gte('sale_date', _dateOnly(startDate));
      }
      if (endDate != null) {
        query = query.lte('sale_date', _dateOnly(endDate));
      }
      final results = await Future.wait<dynamic>([
        query.order('sale_date', ascending: false),
        _fetchMarketplaceRevenue(startDate: startDate, endDate: endDate),
      ]);
      final rows = results[0] as List<Map<String, dynamic>>;
      final marketplaceRevenue = results[1] as double;

      if (rows.isEmpty) {
        return SalesReportData.empty().copyWithMarketplaceRevenue(marketplaceRevenue);
      }

      final farmerIds = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .toList();
      final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

      double totalRevenue = 0;
      double totalQtyKg = 0;
      double palayAmount = 0;
      double peanutAmount = 0;
      final monthlyBuckets = <String, double>{};
      final transactions = <SalesTransactionRow>[];

      for (final row in rows) {
        final amount = (row['amount'] as num).toDouble();
        final qty = (row['quantity_kg'] as num).toDouble();
        final cropType = row['crop_type'] as String? ?? 'palay';
        final saleDate = DateTime.parse(row['sale_date'] as String);

        totalRevenue += amount;
        totalQtyKg += qty;
        if (cropType == 'palay') {
          palayAmount += amount;
        } else {
          peanutAmount += amount;
        }

        final bucketKey =
            '${saleDate.year}-${saleDate.month.toString().padLeft(2, '0')}';
        monthlyBuckets[bucketKey] = (monthlyBuckets[bucketKey] ?? 0) + amount;

        final info = farmerInfo[row['farmer_id']];
        transactions.add(
          SalesTransactionRow(
            id: row['id'] as String,
            farmerName: info?.fullName ?? 'Unknown Farmer',
            memberId: info?.memberId ?? '—',
            cropType: cropType,
            cropName: row['crop_name'] as String,
            quantityKg: qty,
            amount: amount,
            saleDate: saleDate,
            referenceNo: row['reference_no'] as String?,
          ),
        );
      }

      final sortedMonthKeys = monthlyBuckets.keys.toList()..sort();
      final fullTrend = sortedMonthKeys.map((k) => monthlyBuckets[k]!).toList();
      final trend = fullTrend.length > 6
          ? fullTrend.sublist(fullTrend.length - 6)
          : fullTrend;

      return SalesReportData(
        totalRevenue: totalRevenue,
        marketplaceRevenue: marketplaceRevenue,
        totalQuantityKg: totalQtyKg,
        transactionCount: rows.length,
        palayAmount: palayAmount,
        peanutAmount: peanutAmount,
        monthlyTrend: trend,
        transactions: transactions,
      );
    } catch (_) {
      return SalesReportData.empty();
    }
  }

  // ─── Inventory Report ───────────────────────────────────────────────────

  /// No period filter — inventory levels are a current snapshot, not
  /// something that happened within a date range.
  Future<InventoryReportData> fetchInventoryReport() async {
    try {
      final rows = await _client
          .from('inventory_batches')
          .select('*')
          .order('created_at', ascending: false);

      if (rows.isEmpty) return InventoryReportData.empty();

      final farmerIds = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .toList();
      final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

      final farmerCropIds = rows
          .map((r) => r['crop_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final farmerCropToCropMaster =
          await fetchFarmerCropToCropMasterMap(_client, farmerCropIds);
      final cropMasterIds = farmerCropToCropMaster.values.toSet().toList();
      final cropNames = await fetchCropNameMap(_client, cropMasterIds);

      double totalAvailable = 0;
      double totalReserved = 0;
      double totalSold = 0;
      int lowStockCount = 0;
      final cropTotals = <String, double>{};
      final batches = <InventoryReportRow>[];

      for (final row in rows) {
        final available = (row['available_kg'] as num).toDouble();
        final reserved = (row['reserved_kg'] as num? ?? 0).toDouble();
        final sold = (row['sold_kg'] as num? ?? 0).toDouble();
        final status = row['status'] as String? ?? 'available';
        final farmerCropId = row['crop_id'] as String?;
        final cropMasterId =
            farmerCropId != null ? farmerCropToCropMaster[farmerCropId] : null;
        final cropName = (cropMasterId != null ? cropNames[cropMasterId] : null) ??
            row['crop_name'] as String;

        totalAvailable += available;
        totalReserved += reserved;
        totalSold += sold;
        if (status == 'low_stock') lowStockCount++;
        cropTotals[cropName] = (cropTotals[cropName] ?? 0) + available;

        final info = farmerInfo[row['farmer_id']];
        batches.add(
          InventoryReportRow(
            batchId: row['id'] as String,
            farmerId: row['farmer_id'] as String,
            farmerName: info?.fullName ?? 'Unknown Farmer',
            memberId: info?.memberId ?? '—',
            cropName: cropName,
            batchNumber: row['batch_number'] as String,
            quantityKg: (row['quantity_kg'] as num).toDouble(),
            availableKg: available,
            reservedKg: reserved,
            soldKg: sold,
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

  Future<HarvestReportData> fetchHarvestReport(ReportPeriod period) async {
    try {
      final window = period.range();
      var query = _client.from('harvest_records').select('*');
      if (window.startDate != null) {
        query = query.gte('harvest_date', _dateOnly(window.startDate!));
      }
      if (window.endDate != null) {
        query = query.lte('harvest_date', _dateOnly(window.endDate!));
      }
      final rows = await query.order('harvest_date', ascending: false);

      if (rows.isEmpty) return HarvestReportData.empty();

      final farmerIds = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .toList();
      final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

      final cropIds = rows
          .map((r) => r['crop_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      // harvest_records.crop_id references farmer_crops(id), NOT
      // crop_master(id) directly — confirmed by production data (see
      // supabase_schema history / conversation log for the query that
      // caught this). Same collision already handled correctly in
      // fetchInventoryReport(); this table was missed in the first pass
      // because member_sales_transactions.crop_id — despite the identical
      // column name — DOES reference crop_master(id) directly, which is
      // what fetchQuickInsights() correctly relies on. Two tables named
      // crop_id pointing at two different targets — do not assume they
      // match without checking, if a fourth crop_id-bearing table shows
      // up later.
      final farmerCropToCropMaster =
          await fetchFarmerCropToCropMasterMap(_client, cropIds);
      final cropMasterIds = farmerCropToCropMaster.values.toSet().toList();
      final cropNames = await fetchCropNameMap(_client, cropMasterIds);

      double totalYield = 0;
      int unsyncedCount = 0;
      final cropTotals = <String, double>{};
      final monthlyBuckets = <String, double>{};
      final harvests = <HarvestReportRow>[];

      for (final row in rows) {
        final qty = (row['quantity_kg'] as num).toDouble();
        final farmerCropId = row['crop_id'] as String?;
        final cropMasterId =
            farmerCropId != null ? farmerCropToCropMaster[farmerCropId] : null;
        final cropName = (cropMasterId != null ? cropNames[cropMasterId] : null) ??
            row['crop_name'] as String;
        final harvestDate = DateTime.parse(row['harvest_date'] as String);
        final isSynced = row['is_synced'] as bool? ?? true;

        totalYield += qty;
        if (!isSynced) unsyncedCount++;
        cropTotals[cropName] = (cropTotals[cropName] ?? 0) + qty;

        final bucketKey =
            '${harvestDate.year}-${harvestDate.month.toString().padLeft(2, '0')}';
        monthlyBuckets[bucketKey] = (monthlyBuckets[bucketKey] ?? 0) + qty;

        final info = farmerInfo[row['farmer_id']];
        harvests.add(
          HarvestReportRow(
            id: row['id'] as String,
            farmerId: row['farmer_id'] as String,
            farmerName: info?.fullName ?? 'Unknown Farmer',
            memberId: info?.memberId ?? '—',
            cropName: cropName,
            quantityKg: qty,
            harvestDate: harvestDate,
            submittedToCooperative:
                row['submitted_to_cooperative'] as bool? ?? false,
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

      return HarvestReportData(
        totalYieldKg: totalYield,
        harvestCount: rows.length,
        unsyncedCount: unsyncedCount,
        monthlyTrend: trend,
        cropBreakdown: cropBreakdown,
        harvests: harvests,
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
  Future<List<double>> fetchYieldTrend({int months = 6}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: months * 31));
      final rows = await _client
          .from('harvest_records')
          .select('quantity_kg, harvest_date')
          .gte('harvest_date', _dateOnly(cutoff));

      final buckets = <String, double>{};
      for (final row in rows) {
        final date = DateTime.parse(row['harvest_date'] as String);
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        buckets[key] = (buckets[key] ?? 0) + (row['quantity_kg'] as num).toDouble();
      }

      final sortedKeys = buckets.keys.toList()..sort();
      final trend = sortedKeys.map((k) => buckets[k]!).toList();
      return trend.length > months ? trend.sublist(trend.length - months) : trend;
    } catch (_) {
      return [];
    }
  }

  // ─── Expense Report ─────────────────────────────────────────────────────

  Future<ExpenseReportData> fetchExpenseReport(ReportPeriod period) async {
    try {
      final window = period.range();
      var query = _client.from('farmer_expenses').select('*');
      if (window.startDate != null) {
        query = query.gte('expense_date', _dateOnly(window.startDate!));
      }
      if (window.endDate != null) {
        query = query.lte('expense_date', _dateOnly(window.endDate!));
      }
      final rows = await query.order('expense_date', ascending: false);

      if (rows.isEmpty) return ExpenseReportData.empty();

      final farmerIds = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .toList();
      final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

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

        final info = farmerInfo[row['farmer_id']];
        expenseRows.add(
          ExpenseReportRow(
            farmerId: row['farmer_id'] as String,
            farmerName: info?.fullName ?? 'Unknown Farmer',
            memberId: info?.memberId ?? '—',
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
  Future<List<double>> fetchExpenseTrend({int months = 6}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: months * 31));
      final rows = await _client
          .from('farmer_expenses')
          .select('amount, expense_date, is_subsidy')
          .gte('expense_date', _dateOnly(cutoff));

      final buckets = <String, double>{};
      for (final row in rows) {
        if (row['is_subsidy'] as bool? ?? false) continue;
        final date = DateTime.parse(row['expense_date'] as String);
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        buckets[key] = (buckets[key] ?? 0) + (row['amount'] as num).toDouble();
      }

      final sortedKeys = buckets.keys.toList()..sort();
      final trend = sortedKeys.map((k) => buckets[k]!).toList();
      return trend.length > months ? trend.sublist(trend.length - months) : trend;
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

  Future<MemberContributionReportData> fetchMemberContributionReport(
    int year,
  ) async {
    try {
      final salesTotals = await fetchMemberSalesTotals(_client, year);

      final rosterRows = await _client
          .from('farmer_profiles')
          .select('user_id, member_id');
      final farmerIds = rosterRows.map((r) => r['user_id'] as String).toList();
      final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

      double totalCoopSales = 0;
      for (final totals in salesTotals.values) {
        totalCoopSales += totals.totalAmount;
      }

      final rows = farmerIds.map((farmerId) {
        final info = farmerInfo[farmerId];
        final MemberSalesTotals totals =
            salesTotals[farmerId] ?? MemberSalesTotals();
        final sharePercent = computeMemberSharePercent(
          memberSales: totals.totalAmount,
          coopTotalSales: totalCoopSales,
        );
        return MemberContributionRow(
          farmerId: farmerId,
          farmerName: info?.fullName ?? 'Unknown Farmer',
          memberId: info?.memberId ?? '—',
          palayQtyKg: totals.palayQtyKg,
          palayAmount: totals.palayAmount,
          peanutQtyKg: totals.peanutQtyKg,
          peanutAmount: totals.peanutAmount,
          totalAmount: totals.totalAmount,
          sharePercent: sharePercent,
        );
      }).toList()..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

      return MemberContributionReportData(
        year: year,
        totalCoopSales: totalCoopSales,
        memberCount: rows.length,
        contributingMemberCount: rows.where((r) => r.hasContributed).length,
        rows: rows,
      );
    } catch (_) {
      return MemberContributionReportData.empty(year);
    }
  }

  Future<CoopStockReportData> fetchCoopStockReport() async {
    try {
      final rows = await _client
          .from('cooperative_inventory')
          .select('*')
          .eq('is_active', true)
          .order('item_name');

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