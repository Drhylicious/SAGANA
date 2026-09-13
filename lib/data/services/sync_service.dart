import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_event_service.dart';
import 'connectivity_service.dart';
import 'hive_service.dart';
import 'app_settings_service.dart'; // NEW import — needed to read the current userId
import '../repositories/admin_loan_repository.dart';
import '../repositories/expense_repository.dart';
import '../repositories/harvest_entry_repository.dart';

class SyncService {
  SyncService._();

  static Timer? _syncTimer;
  static bool _isSyncing = false;
  static const Duration _syncInterval = Duration(minutes: 5);
  static final _adminLoanRepo = AdminLoanRepository();
  static final _harvestEntryRepo = HarvestEntryRepository();
  static final _expenseRepo = ExpenseRepository(); // NEW — Phase 2 / U2

  // ─── Start Auto Sync ─────────────────────────────────────────────────────────

  static void startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) async {
      if (!HiveService.getBackgroundSync(userId: AppSettingsService.instance.currentUserId)) return;
      await syncPending();
    });

    // Listen for connectivity restored
    ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (isOnline && HiveService.getBackgroundSync(userId: AppSettingsService.instance.currentUserId)) syncPending();
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
      await _syncPendingHarvests();
      await _syncPendingExpenses();
      await _syncPendingLoanIssuances();
      await _syncPendingLoanPayments();
      // Broadcasts to any listening screen (Harvest Hub, My Expenses,
      // Profile, etc.) so a background sync that completes while a
      // screen is already open is reflected immediately, instead of
      // only on next manual refresh — closes the gap noted in the
      // Final Verification (Section 4).
      AppEventService.instance.notify();
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
          idempotencyKey: entry.key,
        );
        await HiveService.removePendingQueueItem(entry.key);
      } on PostgrestException catch (e) {
        // Reached the server; it explicitly rejected the write (e.g.
        // authorization, insufficient stock, a deleted item). Stays
        // queued and still retried, but now visible on Loan Dashboard
        // instead of failing silently forever.
        await HiveService.markLoanQueueItemError(entry.key, e.message);
      } catch (_) {
        // Never reached the server (network drop, timeout) — genuinely
        // transient, retried silently on the next cycle exactly as before.
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
          idempotencyKey: entry.key,
        );
        await HiveService.removePendingQueueItem(entry.key);
      } on PostgrestException catch (e) {
        // Reached the server; it explicitly rejected the write (e.g.
        // authorization, insufficient stock, a deleted item). Stays
        // queued and still retried, but now visible on Loan Dashboard
        // instead of failing silently forever.
        await HiveService.markLoanQueueItemError(entry.key, e.message);
      } catch (_) {
        // Never reached the server (network drop, timeout) — genuinely
        // transient, retried silently on the next cycle exactly as before.
      }
    }
  }

  /// Replays each queued harvest submission through the same
  /// HarvestEntryRepository._submitOnline() path used online, so the two
  /// insert flows (harvest_records → inventory_batches, with cooperative
  /// eligibility resolved fresh) never diverge.
  static Future<void> _syncPendingHarvests() async {
    final pending = HiveService.getPendingHarvests();
    for (final entry in pending) {
      try {
        await _harvestEntryRepo.submitQueuedHarvest(entry.value);
        await HiveService.removePendingHarvest(entry.key);
      } catch (_) {
        // Leave this one queued — retried on the next sync cycle.
      }
    }
  }

  /// Replays each queued expense through the same
  /// ExpenseRepository._addOnline() path used online, so the two insert
  /// flows never diverge — mirrors _syncPendingHarvests().
  static Future<void> _syncPendingExpenses() async {
    final pending = HiveService.getPendingExpenses();
    for (final entry in pending) {
      try {
        await _expenseRepo.submitQueuedExpense(entry.value);
        await HiveService.removePendingExpense(entry.key);
      } catch (_) {
        // Leave this one queued — retried on the next sync cycle.
      }
    }
  }

  static bool get isSyncing => _isSyncing;
}