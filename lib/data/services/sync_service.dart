import 'dart:async';
import 'connectivity_service.dart';
import 'hive_service.dart';
import '../repositories/admin_loan_repository.dart';

class SyncService {
  SyncService._();

  static Timer? _syncTimer;
  static bool _isSyncing = false;
  static const Duration _syncInterval = Duration(minutes: 5);
  static final _adminLoanRepo = AdminLoanRepository();

  // ─── Start Auto Sync ─────────────────────────────────────────────────────────

  static void startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) async {
      if (!HiveService.getBackgroundSync()) return;
      await syncPending();
    });

    // Listen for connectivity restored
    ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (isOnline) syncPending();
    });
  }

  static void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  // ─── Sync Pending Records ────────────────────────────────────────────────────

  static Future<void> syncPending() async {
    if (_isSyncing) return;
    final isOnline = await ConnectivityService.instance.checkConnectivity();
    if (!isOnline) return;

    _isSyncing = true;
    try {
      // TODO: implement when these modules are built
      //   harvest_records → inventory_batches → farmer_expenses
      await _syncPendingLoanIssuances();
      await _syncPendingLoanPayments();
    } catch (_) {
      // Silently fail — will retry on next interval
    } finally {
      _isSyncing = false;
    }
  }

  /// Replays each queued Issue-Loan payload through the same
  /// AdminLoanRepository.issueLoan() path used for the online case, so
  /// reference-number generation and insert logic aren't duplicated.
  /// Reference numbers are intentionally NOT generated until this point —
  /// see HiveService.savePendingLoanIssuance().
  static Future<void> _syncPendingLoanIssuances() async {
    final pending = HiveService.getPendingLoanIssuances();
    for (final entry in pending) {
      try {
        final payload = entry.value;
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
        );
        await HiveService.removePendingQueueItem(entry.key);
      } catch (_) {
        // Leave this one queued — retried on the next sync cycle.
      }
    }
  }

  /// Replays each queued payment through AdminLoanRepository.recordPayment(),
  /// which re-reads the loan's current balance at execution time — so a
  /// payment queued hours earlier still computes a correct running_balance
  /// even if the loan's state changed in the meantime.
  static Future<void> _syncPendingLoanPayments() async {
    final pending = HiveService.getPendingLoanPayments();
    for (final entry in pending) {
      try {
        final payload = entry.value;
        await _adminLoanRepo.recordPayment(
          loanId: payload['loanId'] as String,
          amount: (payload['amount'] as num).toDouble(),
          paymentDate: DateTime.parse(payload['paymentDate'] as String),
          notes: payload['notes'] as String?,
        );
        await HiveService.removePendingQueueItem(entry.key);
      } catch (_) {
        // Leave this one queued — retried on the next sync cycle.
      }
    }
  }

  static bool get isSyncing => _isSyncing;
}