import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'account_status_watcher.dart';
import 'app_event_service.dart';
import 'connectivity_service.dart';
import 'hive_service.dart';
import 'app_settings_service.dart'; // NEW import — needed to read the current userId
import 'offline_action_replay.dart';
import 'offline_actions.dart' show isOfflineConnectionFailure;
import 'offline_read_client.dart';
import 'server_only.dart';
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
  static Future<void>? _pendingSync;
  static StreamSubscription<bool>? _connectionSub;
  static StreamSubscription<AuthState>? _authSub;
  static Timer? _retryTimer;
  static String? _syncOwner;

  static bool get _eligible =>
      const [
        'admin',
        'officer',
        'farmer',
      ].contains(HiveService.getUserRole()) &&
      HiveService.getUserId() != null &&
      Supabase.instance.client.auth.currentUser?.id == HiveService.getUserId();

  static bool get _sameSession =>
      _eligible && HiveService.getUserId() == _syncOwner;

  /// App-wide, independent of the current page. Buyers never replay a queue.
  static void start() {
    _connectionSub ??= ConnectivityService.instance.onConnectivityChanged
        .listen((online) {
          if (online) unawaited(syncPending());
        });
    _authSub ??= Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (_eligible) unawaited(syncPending());
    });
    _retryTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (_eligible &&
          queuedCount > 0 &&
          ConnectivityService.instance.isOnline) {
        unawaited(syncPending());
      }
    });
    if (_eligible) unawaited(syncPending());
  }

  static final _adminLoanRepo = AdminLoanRepository();
  static final _harvestEntryRepo = HarvestEntryRepository();
  static final _expenseRepo = ExpenseRepository(); // NEW — Phase 2 / U2

  // ─── Sync Pending Records ────────────────────────────────────────────────────

  static Future<void> syncPending() {
    if (_pendingSync != null) return _pendingSync!;
    if (_isSyncing || !_eligible) return Future<void>.value();
    // Acquire before the first await: reconnect and Sync Now may arrive together.
    _isSyncing = true;
    _syncOwner = HiveService.getUserId();
    // Screens reload when AppEventService notifies. That is only wanted when
    // this run had something to send: with an empty queue nothing on the
    // server changed, and telling every open screen to reload made the whole
    // screen go back to its loading state each time the app regained focus
    // (on Chrome, every Alt+Tab back to the browser window).
    final hadQueued = queuedCount > 0;
    return _pendingSync =
        OfflineReadClient.runForUser(_syncOwner!, _syncPending).whenComplete(
          () {
            _pendingSync = null;
            _isSyncing = false;
            _syncOwner = null;
            if (hadQueued) AppEventService.instance.notify();
          },
        );
  }

  static Future<void> _syncPending() async {
    try {
      if (!await ConnectivityService.instance.checkConnectivity() ||
          !_sameSession) {
        return;
      }
      if (await AccountStatusWatcher.instance.checkNow() || !_sameSession) {
        return;
      }
      for (final entry in HiveService.getPendingHarvests()) {
        if (!_sameSession) return;
        await _replayHarvest(entry.key, entry.value);
      }
      for (final entry in HiveService.getPendingExpenses()) {
        if (!_sameSession) return;
        await _replayExpense(entry.key, entry.value);
      }
      for (final entry in HiveService.getPendingLoanIssuances()) {
        if (!_sameSession) return;
        await _replayLoanIssuance(entry.key, entry.value);
      }
      for (final entry in HiveService.getPendingLoanPayments()) {
        if (!_sameSession) return;
        await _replayLoanPayment(entry.key, entry.value);
      }
      final blockedActions = <String>{};
      for (final entry in HiveService.getOfflineActions()) {
        if (!_sameSession) return;
        final kind = entry.value['kind'] as String;
        final orderKey = kind.startsWith('notification_')
            ? 'notification'
            : kind == 'admin_photo_remove'
            ? 'admin_photo'
            : kind;
        if (blockedActions.contains(orderKey)) continue;
        final ok = await _replayAction(
          entry.key,
          kind,
          entry.value['payload'] as Map<dynamic, dynamic>,
        );
        // Preserve the order of edits to the same data, while allowing unrelated
        // actions to sync when one record needs correction.
        if (!ok) blockedActions.add(orderKey);
      }
      // Broadcasts to any listening screen (Harvest Hub, My Expenses,
      // Profile, etc.) so a background sync that completes while a
      // screen is already open is reflected immediately, instead of
      // only on next manual refresh — closes the gap noted in the
      // Final Verification (Section 4).
      // Records "the app last successfully checked in with the server" —
      // recorded on every clean run, even one with nothing queued, so
      // Home can show a farmer a plain answer to "is this still working?"
      // rather than only ever showing an item count.
      if (_sameSession && queuedCount == 0) {
        await HiveService.setLastSyncTime(
          DateTime.now(),
          userId: AppSettingsService.instance.currentUserId,
        );
      }
    } catch (_) {
      // Silently fail — will retry on next interval
    }
  }

  /// Retries one queued record. Returns true when it reached the server and
  /// was removed from its queue. Does nothing while a sync is already running.
  static Future<bool> retry(FailedSyncRecord record) async {
    if (_isSyncing || !_eligible) return false;
    _isSyncing = true;
    _syncOwner = HiveService.getUserId();
    return OfflineReadClient.runForUser(_syncOwner!, () async {
      try {
        if (!await ConnectivityService.instance.checkConnectivity() ||
            !_sameSession) {
          return false;
        }
        if (await AccountStatusWatcher.instance.checkNow() || !_sameSession) {
          return false;
        }
        // A stale card cannot replay a record already removed by automatic sync.
        final stillQueued = failedRecords().any(
          (r) => r.kind == record.kind && r.localId == record.localId,
        );
        if (!stillQueued) return false;
        final ok = switch (record.kind) {
          SyncRecordKind.harvest => await _replayHarvest(
            record.localId,
            record.payload,
          ),
          SyncRecordKind.expense => await _replayExpense(
            record.localId,
            record.payload,
          ),
          SyncRecordKind.loanIssue => await _replayLoanIssuance(
            record.localId,
            record.payload,
          ),
          SyncRecordKind.loanPayment => await _replayLoanPayment(
            record.localId,
            record.payload,
          ),
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
        _syncOwner = null;
        AppEventService.instance.notify();
      }
    });
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
    } catch (error) {
      if (!isOfflineConnectionFailure(error) && error is! ServerOnlyException) {
        await HiveService.markHarvestQueueItemError(localId, _reason(error));
      }
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
    } catch (error) {
      if (!isOfflineConnectionFailure(error) && error is! ServerOnlyException) {
        await HiveService.markExpenseQueueItemError(localId, _reason(error));
      }
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
        idempotencyKey: (payload['idempotencyKey'] as String?) ?? localId,
      );
      await HiveService.removePendingQueueItem(localId);
      return true;
    } on PostgrestException catch (e) {
      // Reached the server; it explicitly rejected the write (e.g.
      // authorization, insufficient stock, a deleted item). Stays queued and
      // is shown on the Loan Dashboard with its reason.
      await HiveService.markLoanQueueItemError(localId, e.message);
      return false;
    } catch (error) {
      if (!isOfflineConnectionFailure(error) && error is! ServerOnlyException) {
        await HiveService.markLoanQueueItemError(localId, _reason(error));
      }
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
    } catch (error) {
      if (!isOfflineConnectionFailure(error) && error is! ServerOnlyException) {
        await HiveService.markLoanQueueItemError(localId, _reason(error));
      }
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
      if (!isOfflineConnectionFailure(e)) {
        await HiveService.markOfflineActionError(localId, _reason(e));
      }
      return false;
    }
  }

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
