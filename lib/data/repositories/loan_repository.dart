import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/loan_model.dart';

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
}
