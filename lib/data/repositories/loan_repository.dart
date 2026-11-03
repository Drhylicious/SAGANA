import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/client_id.dart';
import '../models/loan_model.dart';
import '../models/loan_request_model.dart';
import '../services/offline_cache.dart';
import '../services/server_only.dart';

class LoanRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  // ─── Fetch all loans with items and payments ──────────────────────────────

  Future<List<LoanModel>> fetchLoans() async {
    try {
      final rows = await OfflineCache.load(
        screen: 'loans',
        fetch: () => _client
          .from('farmer_loans')
          // cooperative_programs(program_name) join added so
          // LoanModel.sourceProgramName/isFromProgramDistribution — already
          // populated on every Admin-side loan query — is also populated
          // here, closing the gap where a farmer whose program distribution
          // was converted to a loan (convert_program_distribution_to_loan())
          // had no way to see that provenance on their own My Loans screen.
          .select(
            '*, farmer_loan_items(*), farmer_loan_payments(*), cooperative_programs(program_name)',
          )
          .eq('farmer_id', _userId)
          .order('issued_date', ascending: false),
      );

      return rows.map((r) => LoanModel.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Loan requests (Request a Loan) ───────────────────────────────────────
  //
  // A Farmer asks for inputs from the existing loan item catalog; a Manager /
  // Officer approves (which issues the loan through issue_loan()) or disapproves.
  // Every rule is enforced by the database (see
  // supabase_schema_farmer_loan_requests.sql); the app only presents it. Browsing
  // the catalog and submitting need a connection: the stock shown and checked has
  // to be the live one, so none of this is queued offline.

  /// The loan catalog with the live stock on hand. Throws when offline.
  Future<List<LoanableItem>> fetchLoanableItems() async {
    await ServerOnly.ensureOnline();
    final res = await _client.rpc('list_loanable_items') as List;
    return [
      for (final r in res)
        LoanableItem.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// The Farmer's own requests, newest first (viewable offline from the last load).
  Future<List<LoanRequestModel>> fetchMyLoanRequests() async {
    try {
      final rows = await OfflineCache.load(
        screen: 'loan_requests',
        fetch: () async {
          final res = await _client.rpc('get_my_loan_requests');
          return [
            for (final r in (res as List? ?? const []))
              Map<String, dynamic>.from(r as Map),
          ];
        },
      );
      return rows.map(LoanRequestModel.fromFarmerJson).toList();
    } catch (_) {
      return [];
    }
  }

  /// Sends a request for [lines] (inventory item id + quantity). Prices and names
  /// are taken from the catalog by the database, never from the app. Returns the
  /// request number. [idempotencyKey] makes a retry after a lost connection
  /// return the same request instead of creating a second one.
  Future<String> submitLoanRequest({
    required List<({String inventoryItemId, double quantity})> lines,
    String? notes,
    String? idempotencyKey,
  }) async {
    await ServerOnly.ensureOnline();
    final res = await _client.rpc(
      'submit_loan_request',
      params: {
        'p_items': [
          for (final l in lines)
            {'inventoryItemId': l.inventoryItemId, 'quantity': l.quantity},
        ],
        'p_notes': notes,
        'p_idempotency_key': idempotencyKey ?? newClientId(),
      },
    );
    final rows = res as List;
    return rows.isEmpty ? '' : (rows.first['new_request_no'] as String? ?? '');
  }

  /// Withdraws a request nobody has decided yet.
  Future<void> cancelLoanRequest(String requestId) async {
    await ServerOnly.ensureOnline();
    await _client.rpc('cancel_loan_request', params: {'p_request_id': requestId});
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
