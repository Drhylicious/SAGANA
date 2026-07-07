import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/expense_model.dart';

class ExpenseRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // ─── Fetch expenses for a period ──────────────────────────────────────────

  Future<List<ExpenseModel>> fetchExpenses(ExpensePeriod period) async {
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
      return rows.map((r) => ExpenseModel.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── This month total (non-subsidy only) ──────────────────────────────────

  Future<double> fetchThisMonthTotal() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final rows = await _client
          .from('farmer_expenses')
          .select('amount, is_subsidy')
          .eq('farmer_id', _userId)
          .eq('is_subsidy', false)
          .gte('expense_date', start.toIso8601String().split('T').first);
      double total = 0;
      for (final row in rows) {
        total += (row['amount'] as num).toDouble();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  // ─── All time total (non-subsidy only) ────────────────────────────────────

  Future<double> fetchAllTimeTotal() async {
    try {
      final rows = await _client
          .from('farmer_expenses')
          .select('amount')
          .eq('farmer_id', _userId)
          .eq('is_subsidy', false);
      double total = 0;
      for (final row in rows) {
        total += (row['amount'] as num).toDouble();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  // ─── Category breakdown ───────────────────────────────────────────────────

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

  Future<void> addExpense({
    required String category,
    required String description,
    required double amount,
    required DateTime expenseDate,
    required bool isSubsidy,
    String? notes,
  }) async {
    await _client.from('farmer_expenses').insert({
      'farmer_id': _userId,
      'category': category,
      'description': description.trim(),
      'amount': isSubsidy ? 0.0 : amount,
      'expense_date': expenseDate.toIso8601String().split('T').first,
      'is_subsidy': isSubsidy,
      'notes': notes?.trim(),
    });
  }

  // ─── Delete expense ───────────────────────────────────────────────────────

  Future<void> deleteExpense(String id) async {
    await _client
        .from('farmer_expenses')
        .delete()
        .eq('id', id)
        .eq('farmer_id', _userId);
  }
}
