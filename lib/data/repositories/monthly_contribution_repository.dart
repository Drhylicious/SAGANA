import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/chunked_in.dart';
import '../models/admin_log_message.dart';
import '../models/contribution_model.dart';
import '../models/monthly_contribution_model.dart';
import '../services/offline_cache.dart';
import '../services/server_only.dart';
import 'admin_activity_repository.dart';

/// A Farmer's monthly contributions (PHP 100 a month, tracked per month).
///
/// The amount paid comes from the Capital Contribution ledger itself (a monthly
/// payment IS a ledger entry carrying its month), so nothing is counted twice and
/// the Member Contribution Report reads the very same records. Reads fall back to an
/// empty list; writes throw so the screen can show the database's own reason.
class MonthlyContributionRepository {
  final SupabaseClient _client = Supabase.instance.client;

  static const _viewColumns =
      'farmer_id, contribution_month, amount_due, due_date, paid_amount, '
      'balance, status, waive_reason, waived_at';

  /// Makes the monthly rows that are missing (the database also does this daily).
  /// Never throws: offline, or before the SQL is run, it does nothing.
  Future<void> sync() async {
    try {
      await _client.rpc('sync_monthly_contributions');
    } catch (_) {}
  }

  /// Every month of [farmerId], newest first.
  Future<List<MonthlyContribution>> fetchForFarmer(String farmerId) async {
    try {
      final rows = await OfflineCache.load(
        screen: cacheScreen(farmerId),
        fetch: () => _client
            .from('member_monthly_contribution_status')
            .select(_viewColumns)
            .eq('farmer_id', farmerId)
            .order('contribution_month', ascending: false),
      );
      return rows.map(MonthlyContribution.fromMap).toList();
    } catch (_) {
      return [];
    }
  }

  static String cacheScreen(String farmerId) =>
      'monthly_contribution_$farmerId';

  /// The ledger entries (payments and their cancellations) of one month,
  /// newest first, with who recorded them.
  Future<List<CapitalContributionEvent>> fetchPayments(
    String farmerId,
    DateTime month,
  ) async {
    try {
      final first = DateTime(month.year, month.month);
      final rows = await _client
          .from('capital_contribution_events')
          .select()
          .eq('farmer_id', farmerId)
          .eq('source', 'member_payment')
          .eq('contribution_month', _date(first))
          .order('created_at', ascending: false);
      final ids = {
        for (final r in rows)
          if (r['recorded_by'] is String) r['recorded_by'] as String,
      }.toList();
      var names = <String, String>{};
      if (ids.isNotEmpty) {
        try {
          final people = await chunkedIn(ids, (slice) => _client.from('user_information').select('user_id, full_name').inFilter('user_id', slice));
          names = {
            for (final p in people)
              if ((p['full_name'] as String?)?.trim().isNotEmpty ?? false)
                p['user_id'] as String: (p['full_name'] as String).trim(),
          };
        } catch (_) {}
      }
      return rows
          .map(
            (r) => CapitalContributionEvent.fromMap(
              r,
              recordedByName: names[r['recorded_by']],
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Records a payment toward [month]. Needs a connection (it is a money entry,
  /// checked by the database against the remaining balance).
  Future<void> recordPayment({
    required String farmerId,
    required DateTime month,
    required double amount,
    required DateTime paidOn,
    String? reference,
  }) async {
    await ServerOnly.ensureOnline();
    await _client.rpc(
      'record_monthly_contribution_payment',
      params: {
        'p_farmer_id': farmerId,
        'p_month': _date(DateTime(month.year, month.month)),
        'p_amount': amount,
        'p_paid_on': _date(paidOn),
        'p_reference': (reference == null || reference.trim().isEmpty)
            ? null
            : reference.trim(),
      },
    );
    AdminActivityRepository().log(
      module: 'members',
      actionType: 'contribution_recorded',
      message: AdminLogMessage('adminLogContributionRecorded', {
        'amount': amount.toStringAsFixed(2),
      }),
      referenceId: farmerId,
    );
  }

  /// Waives [month] (reason required) or reinstates it.
  Future<void> setWaiver({
    required String farmerId,
    required DateTime month,
    required bool waive,
    String? reason,
  }) async {
    await ServerOnly.ensureOnline();
    await _client.rpc(
      'set_monthly_contribution_waiver',
      params: {
        'p_farmer_id': farmerId,
        'p_month': _date(DateTime(month.year, month.month)),
        'p_waive': waive,
        'p_reason': reason?.trim(),
      },
    );
    logStaffAction(
      'members',
      waive ? 'contribution_waived' : 'contribution_waiver_removed',
      waive
          ? 'adminLogContributionWaived'
          : 'adminLogContributionWaiverRemoved',
      referenceId: farmerId,
    );
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
