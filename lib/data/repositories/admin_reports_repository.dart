import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_reports_model.dart';
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
    try {
      final results = await Future.wait([
        _fetchTotalHarvestKg(period),
        _fetchCoopSalesAmount(period),
        _fetchMarketplaceRevenue(period),
        _fetchActiveLoanOutstanding(),
        _fetchTotalExpenses(period),
        _fetchMemberParticipationPercent(period),
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

  Future<double> _fetchTotalHarvestKg(ReportPeriod period) async {
    try {
      var query = _client.from('harvest_records').select('quantity_kg');
      if (period.startDate != null) {
        query = query.gte('harvest_date', _dateOnly(period.startDate!));
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

  Future<double> _fetchCoopSalesAmount(ReportPeriod period) async {
    try {
      var query = _client.from('member_sales_transactions').select('amount');
      if (period.startDate != null) {
        query = query.gte('sale_date', _dateOnly(period.startDate!));
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

  Future<double> _fetchMarketplaceRevenue(ReportPeriod period) async {
    try {
      var query = _client
          .from('orders')
          .select('total_price')
          .eq('status', 'completed');
      if (period.startDate != null) {
        query = query.gte('created_at', _dateOnly(period.startDate!));
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

  Future<double> _fetchTotalExpenses(ReportPeriod period) async {
    try {
      var query = _client
          .from('farmer_expenses')
          .select('amount')
          .eq('is_subsidy', false);
      if (period.startDate != null) {
        query = query.gte('expense_date', _dateOnly(period.startDate!));
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

  Future<double> _fetchMemberParticipationPercent(ReportPeriod period) async {
    try {
      final totalFarmersRows = await _client
          .from('farmer_profiles')
          .select('user_id');
      final totalFarmers = totalFarmersRows.length;
      if (totalFarmers == 0) return 0;

      final activeIds = <String>{};

      var harvestQuery = _client.from('harvest_records').select('farmer_id');
      if (period.startDate != null) {
        harvestQuery = harvestQuery.gte(
          'harvest_date',
          _dateOnly(period.startDate!),
        );
      }
      final harvestRows = await harvestQuery;
      activeIds.addAll(harvestRows.map((r) => r['farmer_id'] as String));

      var salesQuery = _client
          .from('member_sales_transactions')
          .select('farmer_id');
      if (period.startDate != null) {
        salesQuery = salesQuery.gte('sale_date', _dateOnly(period.startDate!));
      }
      final salesRows = await salesQuery;
      activeIds.addAll(salesRows.map((r) => r['farmer_id'] as String));

      var listingQuery = _client
          .from('marketplace_listings')
          .select('farmer_id');
      if (period.startDate != null) {
        listingQuery = listingQuery.gte(
          'submitted_at',
          period.startDate!.toIso8601String(),
        );
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
  Future<SalesReportData> fetchSalesReport(ReportPeriod period) async {
    try {
      var query = _client.from('member_sales_transactions').select('*');
      if (period.startDate != null) {
        query = query.gte('sale_date', _dateOnly(period.startDate!));
      }
      final rows = await query.order('sale_date', ascending: false);

      if (rows.isEmpty) return SalesReportData.empty();

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
        final cropName = row['crop_name'] as String;

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
            qualityGrade: row['quality_grade'] as String? ?? 'Grade A',
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
      var query = _client.from('harvest_records').select('*');
      if (period.startDate != null) {
        query = query.gte('harvest_date', _dateOnly(period.startDate!));
      }
      final rows = await query.order('harvest_date', ascending: false);

      if (rows.isEmpty) return HarvestReportData.empty();

      final farmerIds = rows.map((r) => r['farmer_id'] as String).toSet().toList();
      final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

      double totalYield = 0;
      int gradeACount = 0;
      int unsyncedCount = 0;
      final cropTotals = <String, double>{};
      final monthlyBuckets = <String, double>{};
      final harvests = <HarvestReportRow>[];

      for (final row in rows) {
        final qty = (row['quantity_kg'] as num).toDouble();
        final grade = row['quality_grade'] as String? ?? 'Grade A';
        final cropName = row['crop_name'] as String;
        final harvestDate = DateTime.parse(row['harvest_date'] as String);
        final isSynced = row['is_synced'] as bool? ?? true;

        totalYield += qty;
        if (grade == 'Grade A') gradeACount++;
        if (!isSynced) unsyncedCount++;
        cropTotals[cropName] = (cropTotals[cropName] ?? 0) + qty;

        final bucketKey = '${harvestDate.year}-${harvestDate.month.toString().padLeft(2, '0')}';
        monthlyBuckets[bucketKey] = (monthlyBuckets[bucketKey] ?? 0) + qty;

        final info = farmerInfo[row['farmer_id']];
        harvests.add(HarvestReportRow(
          id: row['id'] as String,
          farmerId: row['farmer_id'] as String,
          farmerName: info?.fullName ?? 'Unknown Farmer',
          memberId: info?.memberId ?? '—',
          cropName: cropName,
          qualityGrade: grade,
          quantityKg: qty,
          harvestDate: harvestDate,
          submittedToCooperative: row['submitted_to_cooperative'] as bool? ?? false,
          isSynced: isSynced,
        ));
      }

      final sortedMonthKeys = monthlyBuckets.keys.toList()..sort();
      final fullTrend = sortedMonthKeys.map((k) => monthlyBuckets[k]!).toList();
      final trend = fullTrend.length > 6 ? fullTrend.sublist(fullTrend.length - 6) : fullTrend;

      final cropBreakdown = cropTotals.entries
          .map((e) => CropStockBreakdown(cropName: e.key, totalKg: e.value))
          .toList()
        ..sort((a, b) => b.totalKg.compareTo(a.totalKg));

      return HarvestReportData(
        totalYieldKg: totalYield,
        harvestCount: rows.length,
        gradeAPercent: rows.isNotEmpty ? (gradeACount / rows.length * 100) : 0,
        unsyncedCount: unsyncedCount,
        monthlyTrend: trend,
        cropBreakdown: cropBreakdown,
        harvests: harvests,
      );
    } catch (_) {
      return HarvestReportData.empty();
    }
  }

  // ─── Expense Report ─────────────────────────────────────────────────────

  Future<ExpenseReportData> fetchExpenseReport(ReportPeriod period) async {
    try {
      var query = _client.from('farmer_expenses').select('*');
      if (period.startDate != null) {
        query = query.gte('expense_date', _dateOnly(period.startDate!));
      }
      final rows = await query.order('expense_date', ascending: false);

      if (rows.isEmpty) return ExpenseReportData.empty();

      final farmerIds = rows.map((r) => r['farmer_id'] as String).toSet().toList();
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
          monthlyBuckets[bucketKey] = (monthlyBuckets[bucketKey] ?? 0) + expense.amount;
        }

        final info = farmerInfo[row['farmer_id']];
        expenseRows.add(ExpenseReportRow(
          farmerId: row['farmer_id'] as String,
          farmerName: info?.fullName ?? 'Unknown Farmer',
          memberId: info?.memberId ?? '—',
          category: expense.category,
          description: expense.description,
          amount: expense.amount,
          isSubsidy: expense.isSubsidy,
          expenseDate: expense.expenseDate,
        ));
      }

      final categoryBreakdown = _buildExpenseCategoryBreakdown(expenses);

      final sortedMonthKeys = monthlyBuckets.keys.toList()..sort();
      final fullTrend = sortedMonthKeys.map((k) => monthlyBuckets[k]!).toList();
      final trend = fullTrend.length > 6 ? fullTrend.sublist(fullTrend.length - 6) : fullTrend;

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

  /// Mirrors ExpenseRepository.buildBreakdown()'s exact algorithm, admin-
  /// scoped across all farmers. See class doc comment for why this is
  /// re-implemented here rather than calling that farmer-scoped method.
  List<CategoryBreakdown> _buildExpenseCategoryBreakdown(List<ExpenseModel> expenses) {
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
        .map((e) => CategoryBreakdown(
              category: e.key,
              total: e.value,
              percentOfMax: maxVal > 0 ? (e.value / maxVal).clamp(0.0, 1.0) : 1.0,
              hasSubsidy: hasSubsidy.containsKey(e.key),
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  Future<MemberContributionReportData> fetchMemberContributionReport(int year) async {
    try {
      final salesTotals = await fetchMemberSalesTotals(_client, year);

      final rosterRows = await _client.from('farmer_profiles').select('user_id, member_id');
      final farmerIds = rosterRows.map((r) => r['user_id'] as String).toList();
      final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

      double totalCoopSales = 0;
      for (final totals in salesTotals.values) {
        totalCoopSales += totals.totalAmount;
      }

      final rows = farmerIds.map((farmerId) {
        final info = farmerInfo[farmerId];
        final MemberSalesTotals totals = salesTotals[farmerId] ?? MemberSalesTotals();
        final sharePercent = totalCoopSales > 0 ? (totals.totalAmount / totalCoopSales * 100) : 0.0;
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
      }).toList()
        ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

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

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;
}
