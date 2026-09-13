import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/loan_model.dart';
import '../models/admin_loan_model.dart';
import 'farmer_lookup.dart';

class LoanRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // ─── Fetch all loans with items and payments ──────────────────────────────

  Future<List<LoanModel>> fetchLoans() async {
    try {
      final rows = await _client
          .from('farmer_loans')
          .select('*, farmer_loan_items(*), farmer_loan_payments(*)')
          .eq('farmer_id', _userId)
          .order('issued_date', ascending: false);

      return rows
          .map((r) => LoanModel.fromMap(r))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Total outstanding balance ────────────────────────────────────────────

  Future<double> fetchTotalOutstanding() async {
    try {
      final rows = await _client
          .from('farmer_loans')
          .select('total_value, amount_paid')
          .eq('farmer_id', _userId)
          .neq('status', 'paid');

      double total = 0;
      for (final row in rows) {
        final remaining =
            (row['total_value'] as num).toDouble() -
            (row['amount_paid'] as num? ?? 0).toDouble();
        total += remaining.clamp(0, double.infinity);
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  // ─── Export support (Phase 7 — Farmer Download Records) ───────────────────
  // Mirrors AdminLoanRepository.fetchAllLoans()'s query/mapping exactly
  // (same table joins, same AdminLoanSummary.fromRow() factory) but scoped
  // to the current farmer, so the CSV output matches Admin's own Loan
  // Report format precisely.
  Future<List<AdminLoanSummary>> fetchMyLoansForExport({
    DateTime? start,
    DateTime? end,
  }) async {
    try {
      var query = _client
          .from('farmer_loans')
          .select('*, farmer_loan_items(item_name)')
          .eq('farmer_id', _userId);
      if (start != null) {
        query = query.gte('issued_date', start.toIso8601String().split('T').first);
      }
      if (end != null) {
        query = query.lte('issued_date', end.toIso8601String().split('T').first);
      }
      final rows = await query.order('issued_date', ascending: false);
      if (rows.isEmpty) return [];

      final info = (await fetchFarmerInfoMap(_client, [_userId]))[_userId];
      return rows.map<AdminLoanSummary>((row) {
        final items = ((row['farmer_loan_items'] as List?) ?? [])
            .map((i) => i['item_name'] as String)
            .toList();
        return AdminLoanSummary.fromRow(
          row,
          farmerName: info?.fullName ?? 'Unknown Farmer',
          memberId: info?.memberId ?? '—',
          itemNames: items,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
