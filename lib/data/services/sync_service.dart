import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'account_status_watcher.dart';
import 'app_event_service.dart';
import 'connectivity_service.dart';
import 'hive_service.dart';
import 'app_settings_service.dart'; // NEW import — needed to read the current userId
import 'offline_action_replay.dart';
import '../repositories/admin_loan_repository.dart';
import '../repositories/expense_repository.dart';
import '../repositories/harvest_entry_repository.dart';

/// The kinds of queued record the device can hold.
enum SyncRecordKind { harvest, expense, loanIssue, loanPayment, action }

/// A queued record the server rejected on its last sync. It stays queued.
class FailedSyncRecord {
  final SyncRecordKind kind;
  final String localId;
  final String error;
  final DateTime? failedAt;
  final Map<dynamic, dynamic> payload;

  /// For [SyncRecordKind.action]: which user action it is (see
  /// OfflineActionReplay). Null for the other kinds.
  final String? actionKind;

  const FailedSyncRecord({
    required this.kind,
    required this.localId,
    required this.error,
    required this.failedAt,
    required this.payload,
    this.actionKind,
  });
}

class SyncService {
  SyncService._();

  static bool _isSyncing = false;
  static final _adminLoanRepo = AdminLoanRepository();
  static final _harvestEntryRepo = HarvestEntryRepository();
  static final _expenseRepo = ExpenseRepository(); // NEW — Phase 2 / U2

  // ─── Sync Pending Records ────────────────────────────────────────────────────

  static Future<void> syncPending() async {
    if (_isSyncing) return;
    final isOnline = await ConnectivityService.instance.checkConnectivity();
    if (!isOnline) return;

    // A suspended account must not push more writes. The check also ends
    // the session through AccountStatusWatcher's stream.
    if (await AccountStatusWatcher.instance.checkNow()) return;

    _isSyncing = true;
    try {
      for (final entry in HiveService.getPendingHarvests()) {
        await _replayHarvest(entry.key, entry.value);
      }
      for (final entry in HiveService.getPendingExpenses()) {
        await _replayExpense(entry.key, entry.value);
      }
      for (final entry in HiveService.getPendingLoanIssuances()) {
        await _replayLoanIssuance(entry.key, entry.value);
      }
      for (final entry in HiveService.getPendingLoanPayments()) {
        await _replayLoanPayment(entry.key, entry.value);
      }
      for (final entry in HiveService.getOfflineActions()) {
        await _replayAction(
          entry.key,
          entry.value['kind'] as String,
          entry.value['payload'] as Map<dynamic, dynamic>,
        );
      }
      // Broadcasts to any listening screen (Harvest Hub, My Expenses,
      // Profile, etc.) so a background sync that completes while a
      // screen is already open is reflected immediately, instead of
      // only on next manual refresh — closes the gap noted in the
      // Final Verification (Section 4).
      AppEventService.instance.notify();
      // Records "the app last successfully checked in with the server" —
      // recorded on every clean run, even one with nothing queued, so
      // Home can show a farmer a plain answer to "is this still working?"
      // rather than only ever showing an item count.
      await HiveService.setLastSyncTime(
        DateTime.now(),
        userId: AppSettingsService.instance.currentUserId,
      );
    } catch (_) {
      // Silently fail — will retry on next interval
    } finally {
      _isSyncing = false;
    }
  }

  /// Retries one queued record. Returns true when it reached the server and
  /// was removed from its queue. Does nothing while a sync is already running.
  static Future<bool> retry(FailedSyncRecord record) async {
    if (_isSyncing) return false;
    final isOnline = await ConnectivityService.instance.checkConnectivity();
    if (!isOnline) return false;

    _isSyncing = true;
    try {
      final ok = switch (record.kind) {
        SyncRecordKind.harvest =>
          await _replayHarvest(record.localId, record.payload),
        SyncRecordKind.expense =>
          await _replayExpense(record.localId, record.payload),
        SyncRecordKind.loanIssue =>
          await _replayLoanIssuance(record.localId, record.payload),
        SyncRecordKind.loanPayment =>
          await _replayLoanPayment(record.localId, record.payload),
        SyncRecordKind.action => await _replayAction(
          record.localId,
          record.actionKind!,
          record.payload,
        ),
      };
      AppEventService.instance.notify();
      return ok;
    } finally {
      _isSyncing = false;
    }
  }

  // ─── Single-record replays ───────────────────────────────────────────────────
  //
  // Each returns true when the record was synced and removed. A
  // PostgrestException means the server reached and rejected the write: the
  // reason is stored on the record and it stays queued. Any other failure
  // (network drop, timeout) stays silent and the record stays queued.

  /// Replays a queued harvest through the same HarvestEntryRepository
  /// ._submitOnline() path used online, so the two insert flows never diverge.
  static Future<bool> _replayHarvest(
    String localId,
    Map<dynamic, dynamic> payload,
  ) async {
    try {
      await _harvestEntryRepo.submitQueuedHarvest(payload);
      await HiveService.removePendingHarvest(localId);
      return true;
    } on PostgrestException catch (e) {
      await HiveService.markHarvestQueueItemError(localId, e.message);
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Replays a queued expense through ExpenseRepository._addOnline(), so the
  /// two insert flows never diverge.
  static Future<bool> _replayExpense(
    String localId,
    Map<dynamic, dynamic> payload,
  ) async {
    try {
      await _expenseRepo.submitQueuedExpense(payload);
      await HiveService.removePendingExpense(localId);
      return true;
    } on PostgrestException catch (e) {
      await HiveService.markExpenseQueueItemError(localId, e.message);
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Replays a queued Issue-Loan payload through the same
  /// AdminLoanRepository.issueLoan() path used for the online case, so
  /// reference-number generation and insert logic aren't duplicated.
  /// Reference numbers are intentionally NOT generated until this point —
  /// see HiveService.savePendingLoanIssuance().
  static Future<bool> _replayLoanIssuance(
    String localId,
    Map<dynamic, dynamic> payload,
  ) async {
    try {
      final rawItems = (payload['items'] as List)
          .map((i) => Map<String, dynamic>.from(i as Map))
          .toList();

      await _adminLoanRepo.issueLoan(
        farmerId: payload['farmerId'] as String,
        items: rawItems,
        issuedDate: DateTime.parse(payload['issuedDate'] as String),
        monthlyPayment: (payload['monthlyPayment'] as num).toDouble(),
        nextPaymentDate: DateTime.parse(payload['nextPaymentDate'] as String),
        notes: payload['notes'] as String?,
        idempotencyKey: localId,
      );
      await HiveService.removePendingQueueItem(localId);
      return true;
    } on PostgrestException catch (e) {
      // Reached the server; it explicitly rejected the write (e.g.
      // authorization, insufficient stock, a deleted item). Stays queued and
      // is shown on the Loan Dashboard with its reason.
      await HiveService.markLoanQueueItemError(localId, e.message);
      return false;
    } catch (_) {
      // Never reached the server (network drop, timeout) — retried on the
      // next sync.
      return false;
    }
  }

  /// Replays a queued payment through AdminLoanRepository.recordPayment(),
  /// which re-reads the loan's current balance at execution time — so a
  /// payment queued hours earlier still computes a correct running_balance
  /// even if the loan's state changed in the meantime.
  static Future<bool> _replayLoanPayment(
    String localId,
    Map<dynamic, dynamic> payload,
  ) async {
    try {
      await _adminLoanRepo.recordPayment(
        loanId: payload['loanId'] as String,
        amount: (payload['amount'] as num).toDouble(),
        paymentDate: DateTime.parse(payload['paymentDate'] as String),
        notes: payload['notes'] as String?,
        // The key stored with the payment, so a retry is never applied twice.
        // Older entries without one fall back to the queue key.
        idempotencyKey: (payload['idempotencyKey'] as String?) ?? localId,
      );
      await HiveService.removePendingQueueItem(localId);
      return true;
    } on PostgrestException catch (e) {
      await HiveService.markLoanQueueItemError(localId, e.message);
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Replays one queued user action (profile, address, photo, notification,
  /// or capital record). Returns true when it was sent and removed.
  ///
  /// A rejection (the server refused the write, or validation failed) is
  /// stored on the action and it stays queued. A connection problem is not
  /// stored, so the action is retried silently on the next Sync.
  static Future<bool> _replayAction(
    String localId,
    String kind,
    Map<dynamic, dynamic> payload,
  ) async {
    try {
      await OfflineActionReplay.run(kind, payload);
      await HiveService.removeOfflineAction(localId);
      return true;
    } catch (e) {
      if (!_isConnectionFailure(e)) {
        await HiveService.markOfflineActionError(localId, _reason(e));
      }
      return false;
    }
  }

  static bool _isConnectionFailure(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      e.runtimeType.toString() == 'ClientException';

  static String _reason(Object e) => e is PostgrestException
      ? e.message
      : e.toString().replaceFirst('Exception: ', '');

  // ─── Queue state ─────────────────────────────────────────────────────────────

  static bool get isSyncing => _isSyncing;

  /// Every record of the signed-in user still waiting to sync, across all
  /// queues. Each queue is already limited to the current user.
  static int get queuedCount =>
      HiveService.getUnsyncedCount() +
      HiveService.getPendingLoanIssuances().length +
      HiveService.getPendingLoanPayments().length +
      HiveService.getOfflineActions().length;

  /// Queued records the server rejected on their last sync.
  static List<FailedSyncRecord> failedRecords() {
    FailedSyncRecord from(SyncRecordKind kind, Map<String, dynamic> issue) {
      return FailedSyncRecord(
        kind: kind,
        localId: issue['localId'] as String,
        error: issue['error'] as String,
        failedAt: DateTime.tryParse(issue['failedAt'] as String? ?? ''),
        payload: issue['payload'] as Map<dynamic, dynamic>,
      );
    }

    return [
      for (final issue in HiveService.getHarvestSyncIssues())
        from(SyncRecordKind.harvest, issue),
      for (final issue in HiveService.getExpenseSyncIssues())
        from(SyncRecordKind.expense, issue),
      for (final issue in HiveService.getLoanSyncIssues())
        from(
          issue['type'] == 'issue'
              ? SyncRecordKind.loanIssue
              : SyncRecordKind.loanPayment,
          issue,
        ),
      for (final issue in HiveService.getOfflineActionIssues())
        _actionFailure(issue),
    ];
  }

  static FailedSyncRecord _actionFailure(Map<String, dynamic> issue) {
    // The stored issue wraps the action as {kind, payload}.
    final action = issue['payload'] as Map<dynamic, dynamic>;
    return FailedSyncRecord(
      kind: SyncRecordKind.action,
      localId: issue['localId'] as String,
      error: issue['error'] as String,
      failedAt: DateTime.tryParse(issue['failedAt'] as String? ?? ''),
      payload: action['payload'] as Map<dynamic, dynamic>,
      actionKind: action['kind'] as String,
    );
  }

  static int get failedRecordCount => failedRecords().length;
}
