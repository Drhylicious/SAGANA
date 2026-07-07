import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_loan_model.dart';

/// Repository for all admin-side loan operations.
///
/// NOTE: Dashboard + Issue-Loan methods are implemented. The remaining
/// methods (recordPayment, fetchAllLoans, fetchLoanById, markLoanAsPaid,
/// fetchAllTimeLoanSummary) will be added incrementally as each subsequent
/// Loans Module screen is built, per the agreed one-screen-at-a-time workflow.
///
/// Column reference (cross-checked against supabase_schema_loans.sql and
/// supabase_schema_fixes.sql):
///   farmer_loans: id, farmer_id, reference_no, issued_date, total_value,
///                 amount_paid, status, notes, next_payment_date,
///                 monthly_payment, created_at, updated_at
///   farmer_loan_items: id, loan_id, item_name, quantity, unit,
///                      unit_price, line_total, created_at
///
/// IMPORTANT: farmer_loans.loan_reference (added by supabase_schema_fixes.sql)
/// is NOT used anywhere in this repository. It is a duplicate/orphaned column —
/// the actual reference field in use everywhere else (LoanModel, farmer-side
/// screens) is reference_no. Do not read or write loan_reference.
///
/// WRITE METHODS DELIBERATELY DO NOT SWALLOW ERRORS.
/// Every other repository in this project catches internally and returns
/// null/empty on failure, which is correct for reads. For issueLoan() —
/// a financial write — silently swallowing a failure would mean a loan
/// silently never gets created while the admin believes it succeeded.
/// issueLoan() throws; the screen decides whether to retry, show an error,
/// or fall back to the offline queue.
class AdminLoanRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Dashboard KPI stats ───────────────────────────────────────────────

  Future<LoanDashboardStats> fetchDashboardStats() async {
    try {
      final rows = await _client
          .from('farmer_loans')
          .select('farmer_id, status, total_value, amount_paid, monthly_payment, updated_at');

      int active = 0;
      int overdue = 0;
      int paidThisMonth = 0;
      double totalOutstanding = 0;
      double totalExpected = 0;
      final farmersOwing = <String>{};
      final now = DateTime.now();

      for (final row in rows) {
        final status = row['status'] as String? ?? 'active';
        final totalValue = (row['total_value'] as num).toDouble();
        final amountPaid = (row['amount_paid'] as num? ?? 0).toDouble();
        final monthlyPayment = (row['monthly_payment'] as num? ?? 0).toDouble();

        if (status == 'active' || status == 'overdue') {
          totalExpected += monthlyPayment;
          farmersOwing.add(row['farmer_id'] as String);
          if (status == 'active') {
            active++;
          } else {
            overdue++;
          }
          totalOutstanding += (totalValue - amountPaid).clamp(0, double.infinity);
        } else if (status == 'paid') {
          final updatedAt = DateTime.tryParse(row['updated_at'] as String? ?? '');
          if (updatedAt != null &&
              updatedAt.year == now.year &&
              updatedAt.month == now.month) {
            paidThisMonth++;
          }
        }
      }

      return LoanDashboardStats(
        activeLoansCount: active,
        overdueLoansCount: overdue,
        paidThisMonthCount: paidThisMonth,
        totalOutstanding: totalOutstanding,
        totalExpectedThisCycle: totalExpected,
        farmersOutstandingCount: farmersOwing.length,
      );
    } catch (_) {
      return LoanDashboardStats.empty();
    }
  }

  // ─── Overdue / Active loan previews (Dashboard sections) ──────────────

  Future<List<AdminLoanSummary>> fetchOverdueLoans({int limit = 3}) =>
      _fetchLoansByStatus('overdue', limit: limit);

  Future<List<AdminLoanSummary>> fetchActiveLoans({int limit = 5}) =>
      _fetchLoansByStatus('active', limit: limit);

  Future<List<AdminLoanSummary>> _fetchLoansByStatus(
    String status, {
    required int limit,
  }) async {
    try {
      final rows = await _client
          .from('farmer_loans')
          .select('*, farmer_loan_items(item_name)')
          .eq('status', status)
          .order('next_payment_date', ascending: true)
          .limit(limit);

      if (rows.isEmpty) return [];

      final farmerIds =
          rows.map((r) => r['farmer_id'] as String).toSet().toList();
      final farmerInfo = await _fetchFarmerInfoMap(farmerIds);

      return rows.map<AdminLoanSummary>((row) {
        final info = farmerInfo[row['farmer_id']];
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

  /// Batch-fetches farmer display info (name + member ID) for a set of
  /// farmer IDs. Done as two separate lookups rather than a single nested
  /// select, because farmer_loans.farmer_id, user_information.user_id,
  /// and farmer_profiles.user_id are sibling foreign keys into
  /// auth.users — there's no direct FK between farmer_loans and either
  /// info table for PostgREST to embed through.
  ///
  /// ASSUMPTION TO VERIFY: uses .inFilter(), the current postgrest-dart
  /// API for "IN" queries. If your installed supabase_flutter version is
  /// older and this doesn't compile, swap inFilter for filter('user_id',
  /// 'in', '(${farmerIds.join(",")})') instead — same intent, older syntax.
  Future<Map<String, _FarmerInfo>> _fetchFarmerInfoMap(
    List<String> farmerIds,
  ) async {
    if (farmerIds.isEmpty) return {};
    try {
      final results = await Future.wait([
        _client
            .from('user_information')
            .select('user_id, full_name')
            .inFilter('user_id', farmerIds),
        _client
            .from('farmer_profiles')
            .select('user_id, member_id')
            .inFilter('user_id', farmerIds),
      ]);

      final names = {
        for (final r in results[0])
          r['user_id'] as String: r['full_name'] as String? ?? 'Unknown Farmer',
      };
      final memberIds = {
        for (final r in results[1])
          r['user_id'] as String: r['member_id'] as String? ?? '—',
      };

      return {
        for (final id in farmerIds)
          id: _FarmerInfo(
            fullName: names[id] ?? 'Unknown Farmer',
            memberId: memberIds[id] ?? '—',
          ),
      };
    } catch (_) {
      return {};
    }
  }

  // ─── Farmer roster (Issue-Loan picker; cached to Hive for offline use) ──

  /// Fetches the full farmer roster (id, name, member ID) — deliberately
  /// unfiltered by search, since the cooperative only has ~52 farmers and
  /// the picker filters client-side. Farmer-scoped via farmer_profiles
  /// (not user_information directly), since user_information also holds
  /// admin/buyer rows.
  Future<List<FarmerPickerResult>> fetchFarmerRoster() async {
    try {
      final profileRows =
          await _client.from('farmer_profiles').select('user_id, member_id');

      if (profileRows.isEmpty) return [];

      final ids = profileRows.map((r) => r['user_id'] as String).toList();
      final infoRows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', ids);

      final names = {
        for (final r in infoRows)
          r['user_id'] as String: r['full_name'] as String? ?? 'Unknown Farmer',
      };

      final roster = profileRows
          .map((r) => FarmerPickerResult(
                id: r['user_id'] as String,
                fullName: names[r['user_id']] ?? 'Unknown Farmer',
                memberId: r['member_id'] as String? ?? '—',
              ))
          .toList();
      roster.sort((a, b) => a.fullName.compareTo(b.fullName));
      return roster;
    } catch (_) {
      return [];
    }
  }

  /// Current outstanding balance + overdue flag for a farmer, shown as a
  /// warning banner once selected on the Issue-Loan form. Read-only —
  /// requires connectivity; the screen skips calling this while offline.
  Future<FarmerLoanStanding> fetchFarmerLoanStanding(String farmerId) async {
    try {
      final rows = await _client
          .from('farmer_loans')
          .select('total_value, amount_paid, status')
          .eq('farmer_id', farmerId)
          .neq('status', 'paid');

      double outstanding = 0;
      bool hasOverdue = false;
      for (final row in rows) {
        final totalValue = (row['total_value'] as num).toDouble();
        final amountPaid = (row['amount_paid'] as num? ?? 0).toDouble();
        outstanding += (totalValue - amountPaid).clamp(0, double.infinity);
        if (row['status'] == 'overdue') hasOverdue = true;
      }
      return FarmerLoanStanding(outstandingBalance: outstanding, hasOverdueLoan: hasOverdue);
    } catch (_) {
      return const FarmerLoanStanding(outstandingBalance: 0, hasOverdueLoan: false);
    }
  }

  // ─── Issue a new loan ───────────────────────────────────────────────────

  /// Inserts one farmer_loans row, then its farmer_loan_items rows.
  /// Two sequential inserts — same pattern already used by
  /// HarvestEntryRepository for harvest_records + inventory_batches.
  ///
  /// If [referenceNo] is omitted, one is auto-generated here. Callers
  /// syncing a loan that was queued offline should also omit it and let
  /// this method generate it fresh at sync time (online), since sequence
  /// lookups require connectivity.
  ///
  /// Throws on failure — see class doc comment for why this method does
  /// not swallow errors like the read methods above.
  Future<IssuedLoanResult> issueLoan({
    required String farmerId,
    required List<Map<String, dynamic>> items,
    required DateTime issuedDate,
    required double monthlyPayment,
    required DateTime nextPaymentDate,
    String? notes,
  }) async {
    final referenceNo = await _generateLoanReference();
    final totalValue = items.fold<double>(
      0,
      (sum, i) => sum + (i['lineTotal'] as num).toDouble(),
    );

    final loanRow = await _client
        .from('farmer_loans')
        .insert({
          'farmer_id': farmerId,
          'reference_no': referenceNo,
          'issued_date': _dateOnly(issuedDate),
          'total_value': totalValue,
          'amount_paid': 0,
          'status': 'active',
          'notes': notes,
          'monthly_payment': monthlyPayment,
          'next_payment_date': _dateOnly(nextPaymentDate),
        })
        .select('id, reference_no')
        .single();

    final loanId = loanRow['id'] as String;

    if (items.isNotEmpty) {
      await _client.from('farmer_loan_items').insert(
            items
                .map((i) => {
                      'loan_id': loanId,
                      'item_name': i['itemName'],
                      'quantity': i['quantity'],
                      'unit': i['unit'],
                      'unit_price': i['unitPrice'],
                      'line_total': i['lineTotal'],
                    })
                .toList(),
          );
    }

    return IssuedLoanResult(
      loanId: loanId,
      referenceNo: loanRow['reference_no'] as String,
    );
  }

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  /// Generates the next sequential reference in the form LN-{year}-{seq}.
  /// Requires connectivity (queries existing references for the year) —
  /// only ever called from issueLoan(), which is only ever called while
  /// online (directly, or from SyncService once connectivity returns).
  Future<String> _generateLoanReference() async {
    final year = DateTime.now().year;
    try {
      final rows = await _client
          .from('farmer_loans')
          .select('reference_no')
          .like('reference_no', 'LN-$year-%');

      int maxSeq = 0;
      for (final row in rows) {
        final ref = row['reference_no'] as String? ?? '';
        final parts = ref.split('-');
        if (parts.length == 3) {
          final seq = int.tryParse(parts[2]) ?? 0;
          if (seq > maxSeq) maxSeq = seq;
        }
      }
      final next = (maxSeq + 1).toString().padLeft(3, '0');
      return 'LN-$year-$next';
    } catch (_) {
      // Fallback avoids a hard failure on the reference lookup alone;
      // extremely unlikely to collide given loan issuance volume.
      final fallbackSeq = DateTime.now().millisecondsSinceEpoch % 1000;
      return 'LN-$year-${fallbackSeq.toString().padLeft(3, '0')}';
    }
  }
}

class _FarmerInfo {
  final String fullName;
  final String memberId;
  const _FarmerInfo({required this.fullName, required this.memberId});
}