import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/expense_model.dart';
import '../models/admin_reports_model.dart';
import '../services/connectivity_service.dart';
import '../services/hive_service.dart';
import 'farmer_lookup.dart';

class ExpenseRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // Locally-queued expenses (not yet synced to Supabase) for the current
  // device's farmer. Mirrors HarvestRepository._pendingHarvestModels().
  List<ExpenseModel> _pendingExpenseModels() {
    return HiveService.getPendingExpenses().map((entry) {
      final p = entry.value;
      return ExpenseModel(
        id: entry.key,
        farmerId: _userId,
        category: p['category'] as String,
        description: p['description'] as String,
        amount: (p['amount'] as num).toDouble(),
        expenseDate: DateTime.parse(p['expense_date'] as String),
        isSubsidy: p['is_subsidy'] as bool? ?? false,
        notes: p['notes'] as String?,
        isSynced: false,
        createdAt: DateTime.now(),
      );
    }).toList();
  }

  // Public accessor so FarmerProfileRepository can reuse this exact
  // pending-expense source instead of re-deriving it independently —
  // same reasoning as HarvestRepository.pendingHarvestModels().
  List<ExpenseModel> pendingExpenseModels() => _pendingExpenseModels();

  // ─── Fetch expenses for a period ──────────────────────────────────────────

  Future<List<ExpenseModel>> fetchExpenses(ExpensePeriod period) async {
    List<ExpenseModel> synced = [];
    try {
      var query = _client
          .from('farmer_expenses')
          .select()
          .eq('farmer_id', _userId);

      if (period.startDate != null) {
        query = query.gte(
            'expense_date', period.startDate!.toIso8601String().split('T').first);
      }

      final rows = await query.order('expense_date', ascending: false);
      synced = rows.map((r) => ExpenseModel.fromMap(r)).toList();
    } catch (_) {
      synced = [];
    }

    // Merge in Hive-queued offline expenses not yet synced, same pattern
    // HarvestRepository uses for pending harvests (Phase 2 / U2).
    final pending = _pendingExpenseModels().where((e) =>
        period.startDate == null || !e.expenseDate.isBefore(period.startDate!));
    if (pending.isEmpty) return synced;

    final combined = [...pending, ...synced];
    combined.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    return combined;
  }

  // ─── This month total (non-subsidy only) ──────────────────────────────────

  Future<double> fetchThisMonthTotal() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    double total = 0;
    try {
      final rows = await _client
          .from('farmer_expenses')
          .select('amount, is_subsidy')
          .eq('farmer_id', _userId)
          .eq('is_subsidy', false)
          .gte('expense_date', start.toIso8601String().split('T').first);
      for (final row in rows) {
        total += (row['amount'] as num).toDouble();
      }
    } catch (_) {
      // Falls through to pending-only total below.
    }
    // Merge in Hive-queued offline expenses (non-subsidy only, matching
    // the server-side filter above) — Phase 2 / U2.
    for (final e in _pendingExpenseModels()) {
      if (!e.isSubsidy && !e.expenseDate.isBefore(start)) {
        total += e.amount;
      }
    }
    return total;
  }

  // ─── All time total (non-subsidy only) ────────────────────────────────────

  Future<double> fetchAllTimeTotal() async {
    double total = 0;
    try {
      final rows = await _client
          .from('farmer_expenses')
          .select('amount')
          .eq('farmer_id', _userId)
          .eq('is_subsidy', false);
      for (final row in rows) {
        total += (row['amount'] as num).toDouble();
      }
    } catch (_) {
      // Falls through to pending-only total below.
    }
    for (final e in _pendingExpenseModels()) {
      if (!e.isSubsidy) total += e.amount;
    }
    return total;
  }

  // ─── Category breakdown ───────────────────────────────────────────────────

  /// Re-implemented, deliberately, as
  /// AdminReportsRepository._buildExpenseCategoryBreakdown(), called from
  /// fetchExpenseReport() — the admin-scoped (cooperative-wide) equivalent
  /// of this exact algorithm. Kept as two copies rather than one shared
  /// function because this method is farmer-scoped (single farmer's
  /// expenses) while the admin version aggregates across every farmer —
  /// different enough in scope that forcing them into one shared function
  /// would need extra parameterization for a low-drift-risk formula. If
  /// this algorithm ever changes, check the admin copy too.
  List<CategoryBreakdown> buildBreakdown(List<ExpenseModel> expenses) {
    final Map<String, double> totals = {};
    final Map<String, bool> hasSubsidy = {};

    for (final e in expenses) {
      if (!e.isSubsidy) {
        totals[e.category] = (totals[e.category] ?? 0) + e.amount;
      } else {
        hasSubsidy[e.category] = true;
      }
    }

    // Include subsidy-only categories at 0
    for (final cat in hasSubsidy.keys) {
      totals.putIfAbsent(cat, () => 0);
    }

    if (totals.isEmpty) return [];

    final maxVal = totals.values.reduce((a, b) => a > b ? a : b);
    return totals.entries.map((e) => CategoryBreakdown(
          category: e.key,
          total: e.value,
          percentOfMax: maxVal > 0 ? (e.value / maxVal).clamp(0.0, 1.0) : 1.0,
          hasSubsidy: hasSubsidy.containsKey(e.key),
        ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  // ─── Add expense ──────────────────────────────────────────────────────────

  Future<ExpenseModel> addExpense({
    required String category,
    required String description,
    required double amount,
    required DateTime expenseDate,
    required bool isSubsidy,
    String? notes,
  }) async {
    final isOnline = await ConnectivityService.instance.checkConnectivity();

    if (!isOnline) {
      final localId = await HiveService.savePendingExpense({
        'category': category,
        'description': description.trim(),
        'amount': isSubsidy ? 0.0 : amount,
        'expense_date': expenseDate.toIso8601String().split('T').first,
        'is_subsidy': isSubsidy,
        'notes': notes?.trim(),
      });

      // Locally-constructed, unsynced representation — shown immediately,
      // same reasoning as HarvestEntryRepository.submitHarvest().
      return ExpenseModel(
        id: localId,
        farmerId: _userId,
        category: category,
        description: description.trim(),
        amount: isSubsidy ? 0.0 : amount,
        expenseDate: expenseDate,
        isSubsidy: isSubsidy,
        notes: notes?.trim(),
        isSynced: false,
        createdAt: DateTime.now(),
      );
    }

    return _addOnline(
      category: category,
      description: description,
      amount: amount,
      expenseDate: expenseDate,
      isSubsidy: isSubsidy,
      notes: notes,
    );
  }

  /// Performs the real farmer_expenses insert. Shared by the immediate
  /// online path above and by SyncService's replay of queued offline
  /// submissions, so the two paths can never drift apart — mirrors
  /// HarvestEntryRepository._submitOnline().
  Future<ExpenseModel> _addOnline({
    required String category,
    required String description,
    required double amount,
    required DateTime expenseDate,
    required bool isSubsidy,
    String? notes,
  }) async {
    final row = await _client
        .from('farmer_expenses')
        .insert({
          'farmer_id': _userId,
          'category': category,
          'description': description.trim(),
          'amount': isSubsidy ? 0.0 : amount,
          'expense_date': expenseDate.toIso8601String().split('T').first,
          'is_subsidy': isSubsidy,
          'notes': notes?.trim(),
        })
        .select()
        .single();
    return ExpenseModel.fromMap(row);
  }

  /// Called only by SyncService, to replay one queued offline expense
  /// once connectivity returns — mirrors submitQueuedHarvest().
  Future<ExpenseModel> submitQueuedExpense(Map<dynamic, dynamic> payload) {
    return _addOnline(
      category: payload['category'] as String,
      description: payload['description'] as String,
      amount: (payload['amount'] as num).toDouble(),
      expenseDate: DateTime.parse(payload['expense_date'] as String),
      isSubsidy: payload['is_subsidy'] as bool? ?? false,
      notes: payload['notes'] as String?,
    );
  }

  // ─── Delete expense ───────────────────────────────────────────────────────

  Future<void> deleteExpense(String id) async {
    await _client
        .from('farmer_expenses')
        .delete()
        .eq('id', id)
        .eq('farmer_id', _userId);
  }

  // ─── Export support (Phase 7 — Farmer Download Records) ───────────────────
  // Direct date-range query (rather than reusing fetchExpenses(ExpensePeriod),
  // whose enum values don't line up with ReportPeriod's), plus the same
  // offline-queued-expense merge pendingExpenseModels() already exposes.
  Future<ExpenseReportData> fetchMyExpensesForExport({
    DateTime? start,
    DateTime? end,
  }) async {
    List<ExpenseModel> synced = [];
    try {
      var query = _client
          .from('farmer_expenses')
          .select()
          .eq('farmer_id', _userId);
      if (start != null) {
        query = query.gte(
            'expense_date', start.toIso8601String().split('T').first);
      }
      if (end != null) {
        query = query.lte(
            'expense_date', end.toIso8601String().split('T').first);
      }
      final rows = await query.order('expense_date', ascending: false);
      synced = rows.map((r) => ExpenseModel.fromMap(r)).toList();
    } catch (_) {
      synced = [];
    }

    final pending = _pendingExpenseModels().where((e) {
      if (start != null && e.expenseDate.isBefore(start)) return false;
      if (end != null && e.expenseDate.isAfter(end)) return false;
      return true;
    });
    final combined = [...pending, ...synced]
      ..sort((a, b) => b.expenseDate.compareTo(a.expenseDate));

    if (combined.isEmpty) {
      return const ExpenseReportData(
        totalFarmerFundedAmount: 0,
        subsidizedCount: 0,
        farmerFundedCount: 0,
        categoryBreakdown: [],
        monthlyTrend: [],
        expenses: [],
      );
    }

    final info = (await fetchFarmerInfoMap(_client, [_userId]))[_userId];
    final expenses = combined.map((e) {
      return ExpenseReportRow(
        farmerId: e.farmerId,
        farmerName: info?.fullName ?? 'Unknown Farmer',
        memberId: info?.memberId ?? '—',
        category: e.category,
        description: e.description,
        amount: e.amount,
        isSubsidy: e.isSubsidy,
        expenseDate: e.expenseDate,
      );
    }).toList();

    return ExpenseReportData(
      totalFarmerFundedAmount: 0,
      subsidizedCount: 0,
      farmerFundedCount: 0,
      categoryBreakdown: const [],
      monthlyTrend: const [],
      expenses: expenses,
    );
  }
}