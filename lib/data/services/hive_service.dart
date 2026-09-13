import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/constants/app_constants.dart';

class HiveService {
  HiveService._();

  static late Box _userBox;
  static late Box _settingsBox;
  static late Box _loanQueueBox; // offline loan issuances + payments
  static late Box _exportHistoryBox; // NEW — Export Center's Recent Exports
  static late Box _harvestQueueBox; // NEW — offline harvest submissions
  static late Box _expenseQueueBox; // NEW — offline expense submissions (Phase 2 / U2)

  // ─── Initialization ──────────────────────────────────────────────────────────

  static Future<void> init() async {
    await Hive.initFlutter();
    _userBox = await Hive.openBox(AppConstants.hiveBoxUser);
    _settingsBox = await Hive.openBox(AppConstants.hiveBoxSettings);
    _loanQueueBox = await Hive.openBox(AppConstants.hiveBoxLoanQueue);
    _exportHistoryBox = await Hive.openBox(AppConstants.hiveBoxExportHistory); // NEW
    _harvestQueueBox = await Hive.openBox(AppConstants.hiveBoxHarvestQueue); // NEW
    _expenseQueueBox = await Hive.openBox(AppConstants.hiveBoxExpenseQueue); // NEW — Phase 2 / U2
  }

  // ─── User Session ────────────────────────────────────────────────────────────

  static Future<void> saveUserSession({
    required String userId,
    required String email,
    required String role,
    String? fullName,
  }) async {
    await _userBox.put(AppConstants.hiveKeyUserId, userId);
    await _userBox.put(AppConstants.hiveKeyUserEmail, email);
    await _userBox.put(AppConstants.hiveKeyUserRole, role);
    await _userBox.put(AppConstants.hiveKeyIsLoggedIn, true);
    if (fullName != null) {
      await _userBox.put(AppConstants.hiveKeyUserName, fullName);
    }
  }

  static Future<void> clearUserSession() async {
    await _userBox.delete(AppConstants.hiveKeyUserId);
    await _userBox.delete(AppConstants.hiveKeyUserEmail);
    await _userBox.delete(AppConstants.hiveKeyUserRole);
    await _userBox.delete(AppConstants.hiveKeyUserName);
    await _userBox.put(AppConstants.hiveKeyIsLoggedIn, false);
    // Unlike member_status (left cached on logout), this one is cleared
    // deliberately: a stale `true` here would wrongly force whoever logs
    // in next on a shared device through the password-change screen.
    await _userBox.delete('must_change_password');
    await _userBox.delete('staff_permissions'); // legacy key — cleared for old sessions
    await _userBox.delete('pending_acknowledgement');
  }

  static String? getUserRole() =>
      _userBox.get(AppConstants.hiveKeyUserRole) as String?;

  static String? getUserId() =>
      _userBox.get(AppConstants.hiveKeyUserId) as String?;

  static String? getUserEmail() =>
      _userBox.get(AppConstants.hiveKeyUserEmail) as String?;

  static String? getUserName() =>
      _userBox.get(AppConstants.hiveKeyUserName) as String?;

  static bool isLoggedIn() =>
      _userBox.get(AppConstants.hiveKeyIsLoggedIn, defaultValue: false) as bool;

  // ─── Member Status (offline splash routing) ─────────────────────────────────
  //
  // Farmers' membership status ('active' / 'pending') is fetched live at
  // login and cached here so the splash screen can route correctly even
  // when the app opens offline.

  static Future<void> saveMemberStatus(String status) async {
    await _userBox.put('member_status', status);
  }

  static String? getMemberStatus() =>
      _userBox.get('member_status') as String?;

  // Whether an approved farmer still owes the one-tap "Continue"
  // acknowledgement (Issue 5 / Decision D7). Cached at login so the router
  // can keep them on the Applicant screen until they acknowledge, offline
  // or online.
  static Future<void> savePendingAcknowledgement(bool value) async {
    await _userBox.put('pending_acknowledgement', value);
  }

  static bool getPendingAcknowledgement() =>
      _userBox.get('pending_acknowledgement', defaultValue: false) as bool;

  // ─── Forced Password Change (offline-capable, all roles) ──────────────────
  //
  // Set true at login when user_roles.must_change_password is true — happens
  // after an admin issues a temporary password via
  // AccountManagementRepository.resetUserPassword. Checked synchronously in
  // the router redirect, same pattern as member status above.

  static Future<void> saveMustChangePassword(bool value) async {
    await _userBox.put('must_change_password', value);
  }

  static bool getMustChangePassword() =>
      _userBox.get('must_change_password', defaultValue: false) as bool;

  // ─── Officer role ────────────────────────────────────────────────────────
  //
  // Phase D (Issue 6): "Staff" is now "Officer". Per-flag permissions were
  // removed (Decision D12) — an Officer has every Admin module EXCEPT the
  // Members tab, uniformly. UI gating is therefore a plain role check.

  static bool get isOfficer => getUserRole() == 'officer';

  // ─── Settings ────────────────────────────────────────────────────────────────

  // userId is optional and defaults to null (the original, unscoped flat
  // key), preserving exact prior behavior for any caller that doesn't
  // pass it. SettingsRepository is the only caller updated to pass it —
  // this makes Background Sync per-user like theme/locale, without
  // changing behavior for any other, unreviewed caller of this method.
  static String _backgroundSyncKey(String? userId) => userId != null
      ? '${userId}::${AppConstants.hiveKeyBackgroundSync}'
      : AppConstants.hiveKeyBackgroundSync;

  static Future<void> setBackgroundSync(bool enabled, {String? userId}) async {
    await _settingsBox.put(_backgroundSyncKey(userId), enabled);
  }

  static bool getBackgroundSync({String? userId}) =>
      _settingsBox.get(_backgroundSyncKey(userId), defaultValue: true) as bool;

  // ─── Sync Count ──────────────────────────────────────────────────────────────

  static Future<void> setUnsyncedCount(int count) async {
    await _settingsBox.put('unsynced_count', count);
  }

  // getUnsyncedCount() now includes both queues — a farmer with a
  // queued expense but no queued harvest would otherwise see "0
  // unsynced" on Profile despite having something waiting to sync
  // (Phase 2 / U2).
  static int getUnsyncedCount() =>
      _harvestQueueBox.length + _expenseQueueBox.length;

  // ─── Farmer Roster Cache (offline Issue-Loan / Record-Payment picker) ────────
  //
  // The cooperative has ~52 farmers total, so caching the full roster
  // (id, name, member ID only — no photos) is cheap and lets the admin
  // pick a farmer during a signal-less BOD meeting. Refreshed whenever
  // either screen loads while online.

  static Future<void> cacheFarmerRoster(List<Map<String, dynamic>> roster) async {
    await _settingsBox.put('cached_farmer_roster', roster);
  }

  static List<Map<String, dynamic>> getCachedFarmerRoster() {
    final data = _settingsBox.get('cached_farmer_roster');
    if (data == null) return [];
    return (data as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  // ─── Active Loans Cache (offline Record-Payment balance lookup) ──────────────
  //
  // Record Payment needs to know a farmer's current loan(s) and balance to
  // record anything against them — another live-query dependency. Cached
  // as a flat list of AdminLoanSummary.toCacheMap() entries whenever
  // Record Payment loads while online.

  static Future<void> cacheActiveLoans(List<Map<String, dynamic>> loans) async {
    await _settingsBox.put('cached_active_loans', loans);
  }

  static List<Map<String, dynamic>> getCachedActiveLoans() {
    final data = _settingsBox.get('cached_active_loans');
    if (data == null) return [];
    return (data as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  // ─── Loan Queue (offline BOD meeting mode) ───────────────────────────────────
  //
  // Both queued issuances and queued payments live in the same box,
  // distinguished by key prefix ('issue_' / 'payment_') rather than
  // separate boxes — they're both small, short-lived, admin-only write
  // queues with identical lifecycle (queue → sync → delete).
  //
  // Queued issuances are stored WITHOUT a reference number — reference
  // generation requires querying existing loans (needs connectivity) and
  // is deliberately deferred to sync time. See AdminLoanRepository.issueLoan().

  static Future<void> savePendingLoanIssuance(Map<String, dynamic> payload) async {
    final localId = 'issue_${DateTime.now().millisecondsSinceEpoch}';
    await _loanQueueBox.put(localId, payload);
  }

  static Future<void> savePendingLoanPayment(Map<String, dynamic> payload) async {
    final localId = 'payment_${DateTime.now().millisecondsSinceEpoch}';
    await _loanQueueBox.put(localId, payload);
  }

  static List<MapEntry<String, Map<dynamic, dynamic>>> getPendingLoanIssuances() =>
      _getPendingByPrefix('issue_');

  static List<MapEntry<String, Map<dynamic, dynamic>>> getPendingLoanPayments() =>
      _getPendingByPrefix('payment_');

  static List<MapEntry<String, Map<dynamic, dynamic>>> _getPendingByPrefix(String prefix) {
    return _loanQueueBox.keys
        .where((k) => (k as String).startsWith(prefix))
        .map((key) => MapEntry(
              key as String,
              Map<dynamic, dynamic>.from(_loanQueueBox.get(key) as Map),
            ))
        .toList();
  }

  static Future<void> removePendingQueueItem(String localId) async {
    await _loanQueueBox.delete(localId);
  }

  /// Records a sync failure against a still-queued entry without removing
  /// it — the entry stays queued and keeps retrying on the normal 5-minute
  /// cycle, but now carries the reason it failed, so Loan Dashboard can
  /// surface it instead of leaving it silently stuck. Only ever called for
  /// a PostgrestException (the RPC was reached and explicitly rejected the
  /// write) — network/timeout failures never call this and stay silent,
  /// exactly as before this change.
  static Future<void> markLoanQueueItemError(String localId, String message) async {
    final existing = _loanQueueBox.get(localId);
    if (existing == null) return;
    final updated = Map<String, dynamic>.from(existing as Map);
    updated['_syncError'] = message;
    updated['_syncErrorAt'] = DateTime.now().toIso8601String();
    await _loanQueueBox.put(localId, updated);
  }

  /// Queued loan issuances/payments that have failed at least one sync
  /// attempt with a server-explained reason (see markLoanQueueItemError).
  /// Used by Loan Dashboard to surface stuck entries instead of leaving
  /// them invisible in the background queue.
  static List<Map<String, dynamic>> getLoanSyncIssues() {
    final all = [..._getPendingByPrefix('issue_'), ..._getPendingByPrefix('payment_')];
    return all
        .where((entry) => entry.value.containsKey('_syncError'))
        .map((entry) => {
              'localId': entry.key,
              'type': entry.key.startsWith('issue_') ? 'issue' : 'payment',
              'error': entry.value['_syncError'] as String,
              'failedAt': entry.value['_syncErrorAt'] as String?,
            })
        .toList();
  }

  // ─── Export History (NEW — Export Center's Recent Exports) ──────────────────
  //
  // Device-local only, by design — no cloud sync, no shared history across
  // admin devices. Files themselves live under the app's documents
  // directory (see CsvExportService); this box just indexes them for
  // display and re-sharing.

  static Future<void> addExportHistoryEntry(Map<String, dynamic> entry) async {
    final id = entry['id'] as String;
    await _exportHistoryBox.put(id, entry);
  }

  static List<Map<String, dynamic>> getExportHistory() {
    final entries = _exportHistoryBox.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    entries.sort((a, b) =>
        (b['generatedAt'] as String).compareTo(a['generatedAt'] as String));
    return entries;
  }

  static Future<void> removeExportHistoryEntry(String id) async {
    await _exportHistoryBox.delete(id);
  }

  // ─── Harvest Queue (offline harvest submission) ──────────────────────────────
  //
  // A queued harvest carries everything HarvestEntryRepository needs to
  // fully replay itself later (harvest_records insert + inventory_batches
  // insert + cooperative-eligibility lookup) — all of that is deferred to
  // sync time, when connectivity (and therefore the eligibility lookup)
  // is actually available again.

  static Future<String> savePendingHarvest(Map<String, dynamic> payload) async {
    final localId = 'harvest_${DateTime.now().millisecondsSinceEpoch}';
    await _harvestQueueBox.put(localId, payload);
    return localId;
  }

  static List<MapEntry<String, Map<dynamic, dynamic>>> getPendingHarvests() {
    return _harvestQueueBox.keys
        .map((key) => MapEntry(
              key as String,
              Map<dynamic, dynamic>.from(_harvestQueueBox.get(key) as Map),
            ))
        .toList();
  }

  static Future<void> removePendingHarvest(String localId) async {
    await _harvestQueueBox.delete(localId);
  }

  static int getPendingHarvestCount() => _harvestQueueBox.length;

  // ─── Expense Queue (offline expense submission) ──────────────────────────────
  //
  // Mirrors the Harvest Queue above. A queued expense carries everything
  // ExpenseRepository needs to fully replay itself later (a single
  // farmer_expenses insert — no secondary table, unlike harvests).

  static Future<String> savePendingExpense(Map<String, dynamic> payload) async {
    final localId = 'expense_${DateTime.now().millisecondsSinceEpoch}';
    await _expenseQueueBox.put(localId, payload);
    return localId;
  }

  static List<MapEntry<String, Map<dynamic, dynamic>>> getPendingExpenses() {
    return _expenseQueueBox.keys
        .map((key) => MapEntry(
              key as String,
              Map<dynamic, dynamic>.from(_expenseQueueBox.get(key) as Map),
            ))
        .toList();
  }

  static Future<void> removePendingExpense(String localId) async {
    await _expenseQueueBox.delete(localId);
  }

  static int getPendingExpenseCount() => _expenseQueueBox.length;

  // ─── Cleanup ─────────────────────────────────────────────────────────────────

  static Future<void> closeAll() async {
    await Hive.close();
  }
}