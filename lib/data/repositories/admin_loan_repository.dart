import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_loan_model.dart';
import '../models/loan_model.dart';
import 'farmer_lookup.dart';

/// Repository for all admin-side loan operations.
///
/// NOTE: Dashboard, Issue-Loan, and Record-Payment methods are implemented.
/// The remaining methods (fetchAllLoans for History, fetchLoanById for
/// Loan Details, markLoanAsPaid, fetchAllTimeLoanSummary) will be added
/// incrementally as each subsequent Loans Module screen is built.
///
/// Column reference (cross-checked against supabase_schema_loans.sql and
/// supabase_schema_fixes.sql):
///   farmer_loans: id, farmer_id, reference_no, issued_date, total_value,
///                 amount_paid, status, notes, next_payment_date,
///                 monthly_payment, created_at, updated_at
///   farmer_loan_items: id, loan_id, item_name, quantity, unit,
///                      unit_price, line_total, created_at
///   farmer_loan_payments: id, loan_id, payment_date, amount_paid,
///                         running_balance, notes, recorded_by, created_at
///
/// IMPORTANT: farmer_loans.loan_reference (added by supabase_schema_fixes.sql)
/// is NOT used anywhere in this repository. It is a duplicate/orphaned column —
/// the actual reference field in use everywhere else (LoanModel, farmer-side
/// screens) is reference_no. Do not read or write loan_reference.
///
/// WRITE METHODS DELIBERATELY DO NOT SWALLOW ERRORS.
/// Every other repository in this project catches internally and returns
/// null/empty on failure, which is correct for reads. For issueLoan() and
/// recordPayment() — financial writes — silently swallowing a failure would
/// mean money changing hands while the admin believes it succeeded. Both
/// throw; the screen decides whether to retry, show an error, or fall back
/// to the offline queue.
class AdminLoanRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Dashboard KPI stats ───────────────────────────────────────────────

  Future<LoanDashboardStats> fetchDashboardStats() async {
    try {
      final rows = await _client
          .from('farmer_loans')
          .select(
            'farmer_id, status, total_value, amount_paid, monthly_payment, updated_at',
          );

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
          totalOutstanding += (totalValue - amountPaid).clamp(
            0,
            double.infinity,
          );
        } else if (status == 'paid') {
          final updatedAt = DateTime.tryParse(
            row['updated_at'] as String? ?? '',
          );
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
      _fetchLoansByStatus(['overdue'], limit: limit);

  Future<List<AdminLoanSummary>> fetchActiveLoans({int limit = 5}) =>
      _fetchLoansByStatus(['active'], limit: limit);

  /// All active + overdue loans, unlimited — used to populate the offline
  /// cache for Record Payment's BOD-meeting mode. Also usable as a general
  /// "all outstanding loans" fetch beyond the Dashboard's capped previews.
  Future<List<AdminLoanSummary>> fetchAllActiveAndOverdueLoans() =>
      _fetchLoansByStatus(['active', 'overdue'], limit: null);

  Future<List<AdminLoanSummary>> _fetchLoansByStatus(
    List<String> statuses, {
    required int? limit,
  }) async {
    try {
      var query = _client
          .from('farmer_loans')
          .select('*, farmer_loan_items(item_name)')
          .inFilter('status', statuses)
          .order('next_payment_date', ascending: true);

      final rows = limit != null ? await query.limit(limit) : await query;

      if (rows.isEmpty) return [];

      final farmerIds = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .toList();
      final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

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

  // ─── Loan History (all-loans registry) ─────────────────────────────────

  /// Fetches loans matching the given server-side filters. Farmer-name
  /// search is applied client-side afterward via AdminLoanListFilter,
  /// since farmer name isn't a column on farmer_loans — same reasoning
  /// FarmerManagementRepository uses for its own FarmerListFilter extension.
  Future<List<AdminLoanSummary>> fetchAllLoans({
    String? statusFilter,
    DateTime? issuedAfter,
  }) async {
    try {
      var query = _client
          .from('farmer_loans')
          .select('*, farmer_loan_items(item_name)');
      if (statusFilter != null) {
        query = query.eq('status', statusFilter);
      }
      if (issuedAfter != null) {
        query = query.gte('issued_date', _dateOnly(issuedAfter));
      }

      final rows = await query.order('issued_date', ascending: false);

      if (rows.isEmpty) return [];

      final farmerIds = rows
          .map((r) => r['farmer_id'] as String)
          .toSet()
          .toList();
      final farmerInfo = await fetchFarmerInfoMap(_client, farmerIds);

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

  /// All-time aggregates for History's summary card. "Healthy" is a simple
  /// heuristic — overdue loans making up more than 20% of currently
  /// outstanding (active + overdue) loans flips it to "Needs Attention".
  Future<AllTimeLoanSummary> fetchAllTimeLoanSummary() async {
    try {
      final rows = await _client
          .from('farmer_loans')
          .select('status, total_value, amount_paid');

      double totalIssued = 0;
      double totalCollected = 0;
      int overdueCount = 0;
      int outstandingCount = 0;

      for (final row in rows) {
        final status = row['status'] as String? ?? 'active';
        final totalValue = (row['total_value'] as num).toDouble();
        final amountPaid = (row['amount_paid'] as num? ?? 0).toDouble();

        totalIssued += totalValue;
        totalCollected += amountPaid;

        if (status == 'active' || status == 'overdue') {
          outstandingCount++;
          if (status == 'overdue') {
            overdueCount++;
          }
        }
      }

      final totalOutstanding = (totalIssued - totalCollected)
          .clamp(0, double.infinity)
          .toDouble();
      final repaymentRate = totalIssued > 0
          ? (totalCollected / totalIssued * 100)
          : 0.0;
      final isHealthy =
          outstandingCount == 0 || (overdueCount / outstandingCount) <= 0.2;

      return AllTimeLoanSummary(
        totalLoanCount: rows.length,
        totalIssued: totalIssued,
        totalCollected: totalCollected,
        totalOutstanding: totalOutstanding,
        repaymentRatePercent: repaymentRate,
        isHealthy: isHealthy,
      );
    } catch (_) {
      return AllTimeLoanSummary.empty();
    }
  }

  /// Builds a monthly collection trend from farmer_loan_payments.
  Future<List<double>> fetchMonthlyCollectionTrend({int months = 6}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: months * 31));
      final rows = await _client
          .from('farmer_loan_payments')
          .select('amount_paid, payment_date')
          .gte('payment_date', _dateOnly(cutoff));

      final buckets = <String, double>{};
      for (final row in rows) {
        final date = DateTime.parse(row['payment_date'] as String);
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        buckets[key] = (buckets[key] ?? 0) + (row['amount_paid'] as num).toDouble();
      }

      final sortedKeys = buckets.keys.toList()..sort();
      final trend = sortedKeys.map((k) => buckets[k]!).toList();
      return trend.length > months ? trend.sublist(trend.length - months) : trend;
    } catch (_) {
      return [];
    }
  }

  /// A single loan's current summary, used when Record Payment is opened
  /// directly with a loanId (from a loan card or Loan Details) — a fresh,
  /// precise lookup rather than trusting a possibly-stale cached list.
  /// Only meaningful while online; the screen falls back to its cached
  /// active-loans list when offline.
  Future<AdminLoanSummary?> fetchLoanSummaryById(String loanId) async {
    try {
      final row = await _client
          .from('farmer_loans')
          .select('*, farmer_loan_items(item_name)')
          .eq('id', loanId)
          .maybeSingle();
      if (row == null) return null;

      final farmerId = row['farmer_id'] as String;
      final info = (await fetchFarmerInfoMap(_client, [farmerId]))[farmerId];
      final items = ((row['farmer_loan_items'] as List?) ?? [])
          .map((i) => i['item_name'] as String)
          .toList();

      return AdminLoanSummary.fromRow(
        row,
        farmerName: info?.fullName ?? 'Unknown Farmer',
        memberId: info?.memberId ?? '—',
        itemNames: items,
      );
    } catch (_) {
      return null;
    }
  }

  // ─── Farmer roster (Issue-Loan + Record-Payment pickers; Hive-cached) ──

  /// Fetches the full farmer roster (id, name, member ID) — deliberately
  /// unfiltered by search, since the cooperative only has ~52 farmers and
  /// pickers filter client-side. Farmer-scoped via farmer_profiles
  /// (not user_information directly), since user_information also holds
  /// admin/buyer rows.
  Future<List<FarmerPickerResult>> fetchFarmerRoster() async {
    try {
      final profileRows = await _client
          .from('farmer_profiles')
          .select('user_id, member_id');

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
          .map(
            (r) => FarmerPickerResult(
              id: r['user_id'] as String,
              fullName: names[r['user_id']] ?? 'Unknown Farmer',
              memberId: r['member_id'] as String? ?? '—',
            ),
          )
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
      return FarmerLoanStanding(
        outstandingBalance: outstanding,
        hasOverdueLoan: hasOverdue,
      );
    } catch (_) {
      return const FarmerLoanStanding(
        outstandingBalance: 0,
        hasOverdueLoan: false,
      );
    }
  }

  // ─── Issue a new loan ───────────────────────────────────────────────────

  /// Inserts one farmer_loans row, then its farmer_loan_items rows.
  /// Two sequential inserts — same pattern already used by
  /// HarvestEntryRepository for harvest_records + inventory_batches.
  ///
  /// Always auto-generates the reference number (requires connectivity —
  /// only ever called while online, directly or from SyncService).
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
      await _client
          .from('farmer_loan_items')
          .insert(
            items
                .map(
                  (i) => {
                    'loan_id': loanId,
                    'item_name': i['itemName'],
                    'quantity': i['quantity'],
                    'unit': i['unit'],
                    'unit_price': i['unitPrice'],
                    'line_total': i['lineTotal'],
                  },
                )
                .toList(),
          );
    }

    return IssuedLoanResult(
      loanId: loanId,
      referenceNo: loanRow['reference_no'] as String,
    );
  }

  // ─── Record a payment ───────────────────────────────────────────────────

  /// Inserts a farmer_loan_payments row and updates the parent loan's
  /// amount_paid / status / next_payment_date.
  ///
  /// Re-reads the loan's CURRENT total_value/amount_paid immediately before
  /// updating, rather than trusting a value the caller captured earlier —
  /// this matters most for payments queued offline and synced later, where
  /// the on-screen numbers could be stale by the time this actually runs.
  ///
  /// If the payment brings amount_paid to or past total_value, the loan is
  /// marked 'paid'. Otherwise status is set to 'active' (clearing 'overdue'
  /// if it was set) and next_payment_date advances to the next BOD Saturday
  /// after the payment date.
  ///
  /// Throws on failure — see class doc comment.
  Future<void> recordPayment({
    required String loanId,
    required double amount,
    required DateTime paymentDate,
    String? notes,
  }) async {
    final loanRow = await _client
        .from('farmer_loans')
        .select('total_value, amount_paid')
        .eq('id', loanId)
        .single();

    final totalValue = (loanRow['total_value'] as num).toDouble();
    final currentPaid = (loanRow['amount_paid'] as num? ?? 0).toDouble();
    final newPaid = currentPaid + amount;
    final runningBalance = (totalValue - newPaid).clamp(0, double.infinity);
    final isFullyPaid = newPaid >= totalValue;

    await _client.from('farmer_loan_payments').insert({
      'loan_id': loanId,
      'payment_date': _dateOnly(paymentDate),
      'amount_paid': amount,
      'running_balance': runningBalance,
      'notes': notes,
      'recorded_by': _client.auth.currentUser?.id,
    });

    final updates = <String, dynamic>{
      'amount_paid': newPaid,
      'status': isFullyPaid ? 'paid' : 'active',
    };
    if (!isFullyPaid) {
      updates['next_payment_date'] = _dateOnly(
        _nextBodSaturdayAfter(paymentDate),
      );
    }

    await _client.from('farmer_loans').update(updates).eq('id', loanId);
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

  /// Same BOD-Saturday algorithm used across the Loans Module screens,
  /// anchored to an arbitrary [from] date rather than DateTime.now() —
  /// needed here because a payment can be recorded for a past date.
  DateTime _nextBodSaturdayAfter(DateTime from) {
    var candidate = _firstSaturdayOf(from.year, from.month);
    if (!candidate.isAfter(DateTime(from.year, from.month, from.day))) {
      final nextMonth = from.month == 12 ? 1 : from.month + 1;
      final nextYear = from.month == 12 ? from.year + 1 : from.year;
      candidate = _firstSaturdayOf(nextYear, nextMonth);
    }
    return candidate;
  }

  DateTime _firstSaturdayOf(int year, int month) {
    var d = DateTime(year, month, 1);
    while (d.weekday != DateTime.saturday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  // ─── Loan Details ───────────────────────────────────────────────────────

  /// Full loan detail — items + full payment history + farmer identity.
  /// Online-only; there is no offline cache for this (unlike the roster /
  /// active-loan-list caches used by Issue Loan and Record Payment) since
  /// caching every loan's complete history "just in case" isn't worth the
  /// storage for a feature that isn't part of the BOD-meeting workflow.
  Future<dynamic> fetchLoanById(String loanId) async {
    try {
      final row = await _client
          .from('farmer_loans')
          .select('*, farmer_loan_items(*), farmer_loan_payments(*)')
          .eq('id', loanId)
          .maybeSingle();
      if (row == null) return null;

      final loan = LoanModel.fromMap(row);
      final farmerId = row['farmer_id'] as String;

      final infoRow = await _client
          .from('user_information')
          .select('full_name, profile_photo_url')
          .eq('user_id', farmerId)
          .maybeSingle();
      final profileRow = await _client
          .from('farmer_profiles')
          .select('member_id')
          .eq('user_id', farmerId)
          .maybeSingle();

      return AdminLoanDetail(
        loan: loan,
        farmerName: infoRow?['full_name'] as String? ?? 'Unknown Farmer',
        memberId: profileRow?['member_id'] as String? ?? '—',
        farmerPhotoUrl: infoRow?['profile_photo_url'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Resolves admin display names for payment history's "By {name}" line.
  /// Same sibling-FK limitation as farmer info lookups — no direct
  /// embedding path from farmer_loan_payments.recorded_by to a name.
  Future<Map<String, String>> fetchAdminNames(List<String> adminIds) async {
    if (adminIds.isEmpty) return {};
    try {
      final rows = await _client
          .from('user_information')
          .select('user_id, full_name')
          .inFilter('user_id', adminIds);
      return {
        for (final r in rows)
          r['user_id'] as String: r['full_name'] as String? ?? 'Admin',
      };
    } catch (_) {
      return {};
    }
  }

  /// Administratively settles a loan WITHOUT inserting a payment record —
  /// this represents a correction or approved write-off, not an actual
  /// cash payment, so it must not appear in the farmer's payment history
  /// as if money changed hands. The reason (if given) is appended to the
  /// loan's notes with a timestamp for audit purposes.
  ///
  /// Throws on failure — see class doc comment on write-method error handling.
  Future<void> markLoanAsPaid(String loanId, {String? reason}) async {
    final loanRow = await _client
        .from('farmer_loans')
        .select('total_value, notes')
        .eq('id', loanId)
        .single();

    final totalValue = (loanRow['total_value'] as num).toDouble();
    final existingNotes = loanRow['notes'] as String?;
    final stamp =
        '[Marked as paid manually on ${_dateOnly(DateTime.now())}'
        '${reason != null && reason.isNotEmpty ? ": $reason" : ""}]';
    final newNotes = (existingNotes == null || existingNotes.isEmpty)
        ? stamp
        : '$existingNotes\n$stamp';

    await _client
        .from('farmer_loans')
        .update({
          'amount_paid': totalValue,
          'status': 'paid',
          'notes': newNotes,
        })
        .eq('id', loanId);
  }
}

extension AdminLoanListFilter on List<AdminLoanSummary> {
  List<AdminLoanSummary> applySearch(String query) {
    if (query.isEmpty) return this;
    final q = query.toLowerCase();
    return where(
      (loan) =>
          loan.farmerName.toLowerCase().contains(q) ||
          loan.memberId.toLowerCase().contains(q) ||
          loan.referenceNo.toLowerCase().contains(q),
    ).toList();
  }
}
