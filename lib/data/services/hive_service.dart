import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/constants/app_constants.dart';
import 'encrypted_box.dart';

class HiveService {
  HiveService._();

  static late Box _userBox;
  static late Box _settingsBox;
  static late Box _loanQueueBox; // offline loan issuances + payments
  static late Box _exportHistoryBox; // NEW — Export Center's Recent Exports
  static late Box _harvestQueueBox; // NEW — offline harvest submissions
  static late Box
  _expenseQueueBox; // NEW — offline expense submissions (Phase 2 / U2)
  static late Box _actionQueueBox; // Phase 9 — queued user-owned writes
  static late Box _cacheBox; // Phase 10 — viewing snapshots, cleared on logout

  // ─── Initialization ──────────────────────────────────────────────────────────

  static Future<void> init() async {
    await Hive.initFlutter();
    _userBox = await EncryptedBox.open(AppConstants.hiveBoxUser);
    _settingsBox = await EncryptedBox.open(AppConstants.hiveBoxSettings);
    _loanQueueBox = await EncryptedBox.open(AppConstants.hiveBoxLoanQueue);
    _exportHistoryBox = await EncryptedBox.open(
      AppConstants.hiveBoxExportHistory,
    ); // NEW
    _harvestQueueBox = await EncryptedBox.open(
      AppConstants.hiveBoxHarvestQueue,
    ); // NEW
    _expenseQueueBox = await EncryptedBox.open(
      AppConstants.hiveBoxExpenseQueue,
    ); // NEW — Phase 2 / U2
    _actionQueueBox = await EncryptedBox.open(
      AppConstants.hiveBoxOfflineActions,
    ); // Phase 9
    _cacheBox = await EncryptedBox.open(
      AppConstants.hiveBoxOfflineCache,
    ); // Phase 10
  }

  /// Snapshot store for OfflineCache. Not for queued records — those live in
  /// their own boxes and survive logout.
  static Box get cacheBox => _cacheBox;

  // ─── User Session ────────────────────────────────────────────────────────────

  static Future<void> saveUserSession({
    required String userId,
    required String email,
    required String role,
    String? fullName,
  }) async {
    await _userBox.put(AppConstants.hiveKeyUserId, userId);
    if (_userBox.get('last_user_id') == null) {
      await _userBox.put('last_user_id', userId);
    }
    await _userBox.put(AppConstants.hiveKeyUserEmail, email);
    await _userBox.put(AppConstants.hiveKeyUserRole, role);
    await _userBox.put(AppConstants.hiveKeyIsLoggedIn, true);
    if (fullName != null) {
      await _userBox.put(AppConstants.hiveKeyUserName, fullName);
    }
  }

  static Future<void> clearUserSession() async {
    final signingOut = getUserId();
    if (signingOut != null) {
      await _userBox.put('last_user_id', signingOut);
    }
    await _userBox.delete(AppConstants.hiveKeyUserId);
    await _userBox.delete(AppConstants.hiveKeyUserEmail);
    await _userBox.delete(AppConstants.hiveKeyUserRole);
    await _userBox.delete(AppConstants.hiveKeyUserName);
    await _userBox.put(AppConstants.hiveKeyIsLoggedIn, false);
    // Unlike member_status (left cached on logout), this one is cleared
    // deliberately: a stale `true` here would wrongly force whoever logs
    // in next on a shared device through the password-change screen.
    await _userBox.delete('must_change_password');
    await _userBox.delete(
      'staff_permissions',
    ); // legacy key — cleared for old sessions
    await _userBox.delete('pending_acknowledgement');
    // Per-user caches: cleared on logout. Unsynced queues are not touched here.
    // The cart belongs to this user only: remove just their items, so any
    // other account's cart on this device is left alone.
    if (signingOut != null) {
      final cart = await EncryptedBox.open(AppConstants.hiveBoxCart);
      await cart.deleteAll(
        cart.keys
            .where((k) => k is String && k.startsWith("$signingOut::"))
            .toList(),
      );
    }
    await (await EncryptedBox.open(AppConstants.hiveBoxExportHistory)).clear();
    // Viewing snapshots belong to the signed-out user. Queued records are not
    // touched: they stay on the device for that user's next sign-in.
    await _cacheBox.clear();
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

  static String? getMemberStatus() => _userBox.get('member_status') as String?;

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

  // ─── Sync Count ──────────────────────────────────────────────────────────────

  static Future<void> setUnsyncedCount(int count) async {
    await _settingsBox.put('unsynced_count', count);
  }

  // getUnsyncedCount() now includes both queues — a farmer with a
  // queued expense but no queued harvest would otherwise see "0
  // unsynced" on Profile despite having something waiting to sync
  // (Phase 2 / U2).
  static int getUnsyncedCount() =>
      getPendingHarvestCount() + getPendingExpenseCount();

  // ─── Last Sync Time ──────────────────────────────────────────────────────────
  //
  // Recorded by SyncService.syncPending() on every run that completes
  // without throwing (including a no-op run with nothing queued) — this is
  // "the app last successfully checked in with the server", not "the app
  // last had something to sync". Same per-user key scoping as background
  // sync above, since both live in the same shared settings box.

  static String _lastSyncKey(String? userId) =>
      userId != null ? '$userId::last_sync_time' : 'last_sync_time';

  static Future<void> setLastSyncTime(DateTime time, {String? userId}) async {
    await _settingsBox.put(_lastSyncKey(userId), time.toIso8601String());
  }

  static DateTime? getLastSyncTime({String? userId}) {
    final stored = _settingsBox.get(_lastSyncKey(userId)) as String?;
    return stored != null ? DateTime.tryParse(stored) : null;
  }

  // ─── DA-AMAD Enrollment Approval Acknowledgment ──────────────────────────────
  //
  // One-time full-screen celebration shown the first time a farmer opens
  // Market Linking after their enrollment is approved. Keyed by the
  // specific enrollment row's id (not a single flag) — a farmer whose
  // enrollment is later rejected and re-approved gets a fresh celebration
  // for that new approval, since it's a genuinely new event. Same
  // per-user key scoping as Background Sync/Last Sync Time above.

  static String _daAmadApprovalSeenKey(String enrollmentId, String? userId) =>
      userId != null
      ? '$userId::da_amad_approval_seen::$enrollmentId'
      : 'da_amad_approval_seen::$enrollmentId';

  static Future<void> setDaAmadApprovalSeen(
    String enrollmentId, {
    String? userId,
  }) async {
    await _settingsBox.put(_daAmadApprovalSeenKey(enrollmentId, userId), true);
  }

  static bool getDaAmadApprovalSeen(String enrollmentId, {String? userId}) =>
      _settingsBox.get(
            _daAmadApprovalSeenKey(enrollmentId, userId),
            defaultValue: false,
          )
          as bool;

  // ─── Farmer Roster Cache (offline Issue-Loan / Record-Payment picker) ────────
  //
  // The cooperative has ~52 farmers total, so caching the full roster
  // (id, name, member ID only — no photos) is cheap and lets the admin
  // pick a farmer during a signal-less BOD meeting. Refreshed whenever
  // either screen loads while online.

  static Future<void> cacheFarmerRoster(
    List<Map<String, dynamic>> roster,
  ) async {
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

  static Future<void> savePendingLoanIssuance(
    Map<String, dynamic> payload,
  ) async {
    final localId = 'issue_${DateTime.now().millisecondsSinceEpoch}';
    await _loanQueueBox.put(localId, _owned(payload));
  }

  // Microseconds, not milliseconds: two payments saved in the same
  // millisecond would otherwise overwrite each other in the box.
  static Future<void> savePendingLoanPayment(
    Map<String, dynamic> payload,
  ) async {
    final localId = 'payment_${DateTime.now().microsecondsSinceEpoch}';
    await _loanQueueBox.put(localId, _owned(payload));
  }

  static List<MapEntry<String, Map<dynamic, dynamic>>>
  getPendingLoanIssuances() => _getPendingByPrefix('issue_');

  // Oldest first: the keys are time-ordered, so two payments on one loan
  // are applied in the order they were made.
  static List<MapEntry<String, Map<dynamic, dynamic>>>
  getPendingLoanPayments() =>
      _getPendingByPrefix('payment_')..sort((a, b) => a.key.compareTo(b.key));

  static List<MapEntry<String, Map<dynamic, dynamic>>> _getPendingByPrefix(
    String prefix,
  ) {
    return _ownedEntries(
      _loanQueueBox,
    ).where((entry) => entry.key.startsWith(prefix)).toList();
  }

  // ─── Record ownership ───────────────────────────────────────────────────────
  // Every queued record is stamped with the user who created it. Reads, counts,
  // and sync only return the signed-in user's records, so another user on the
  // same device sees none of them. Records written before ownership existed
  // belong to the last user who signed out, or to the first user to sign in
  // when no earlier user is recorded.

  static const String _ownerKey = '_owner_id';

  static String? _legacyOwnerId() => _userBox.get('last_user_id') as String?;

  static Map<String, dynamic> _owned(Map<String, dynamic> payload) {
    final owner = getUserId();
    if (owner == null) {
      throw StateError('Sign in before saving offline records.');
    }
    return {...payload, _ownerKey: owner};
  }

  static List<MapEntry<String, Map<dynamic, dynamic>>> _ownedEntries(Box box) {
    final me = getUserId();
    if (me == null) return const [];
    final result = <MapEntry<String, Map<dynamic, dynamic>>>[];
    for (final key in box.keys) {
      final value = Map<dynamic, dynamic>.from(box.get(key) as Map);
      final owner = (value[_ownerKey] as String?) ?? _legacyOwnerId();
      if (owner != me) continue;
      value.remove(_ownerKey);
      result.add(MapEntry(key as String, value));
    }
    return result;
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
  static Future<void> markLoanQueueItemError(String localId, String message) =>
      _markOwnedError(_loanQueueBox, localId, message);

  /// Queued loan issuances/payments that have failed at least one sync
  /// attempt with a server-explained reason (see markLoanQueueItemError).
  /// Used by Loan Dashboard to surface stuck entries instead of leaving
  /// them invisible in the background queue.
  static List<Map<String, dynamic>> getLoanSyncIssues() {
    final all = [
      ..._getPendingByPrefix('issue_'),
      ..._getPendingByPrefix('payment_'),
    ];
    return all
        .where((entry) => entry.value.containsKey('_syncError'))
        .map(
          (entry) => {
            'localId': entry.key,
            'type': entry.key.startsWith('issue_') ? 'issue' : 'payment',
            'error': entry.value['_syncError'] as String,
            'failedAt': entry.value['_syncErrorAt'] as String?,
            'payload': entry.value,
          },
        )
        .toList();
  }

  // ─── Export History (NEW — Export Center's Recent Exports) ──────────────────
  //
  // Device-local only, by design — no cloud sync, no shared history across
  // admin devices. Files themselves live under the app's documents
  // directory (see CsvExportService); this box just indexes them for
  // display and re-sharing.

  // Owner-scoped like the other device records: an entry is only listed for
  // the admin who generated it, even if another user signs in on this device.
  static Future<void> addExportHistoryEntry(Map<String, dynamic> entry) async {
    final id = entry['id'] as String;
    await _exportHistoryBox.put(id, _owned(entry));
  }

  static List<Map<String, dynamic>> getExportHistory() {
    final entries = _ownedEntries(
      _exportHistoryBox,
    ).map((e) => Map<String, dynamic>.from(e.value)).toList();
    entries.sort(
      (a, b) =>
          (b['generatedAt'] as String).compareTo(a['generatedAt'] as String),
    );
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
    await _harvestQueueBox.put(localId, _owned(payload));
    return localId;
  }

  static List<MapEntry<String, Map<dynamic, dynamic>>> getPendingHarvests() {
    return _ownedEntries(_harvestQueueBox);
  }

  static Future<void> removePendingHarvest(String localId) async {
    await _harvestQueueBox.delete(localId);
  }

  static int getPendingHarvestCount() => getPendingHarvests().length;

  /// Records a server rejection against a still-queued harvest. The record
  /// stays queued and is retried on the next manual Sync. Only called for a
  /// PostgrestException; network failures stay silent, as before.
  static Future<void> markHarvestQueueItemError(
    String localId,
    String message,
  ) => _markOwnedError(_harvestQueueBox, localId, message);

  /// Queued harvests that failed their last sync with a server-explained reason.
  static List<Map<String, dynamic>> getHarvestSyncIssues() =>
      _syncIssues(_harvestQueueBox);

  // ─── Expense Queue (offline expense submission) ──────────────────────────────
  //
  // Mirrors the Harvest Queue above. A queued expense carries everything
  // ExpenseRepository needs to fully replay itself later (a single
  // farmer_expenses insert — no secondary table, unlike harvests).

  static Future<String> savePendingExpense(Map<String, dynamic> payload) async {
    final localId = 'expense_${DateTime.now().millisecondsSinceEpoch}';
    await _expenseQueueBox.put(localId, _owned(payload));
    return localId;
  }

  static List<MapEntry<String, Map<dynamic, dynamic>>> getPendingExpenses() {
    return _ownedEntries(_expenseQueueBox);
  }

  static Future<void> removePendingExpense(String localId) async {
    await _expenseQueueBox.delete(localId);
  }

  static int getPendingExpenseCount() => getPendingExpenses().length;

  // ─── Offline Action Queue (Phase 9) ──────────────────────────────────────────
  //
  // User-owned writes that could not reach the server: profile and photo
  // edits, buyer addresses, crop photos, notification read/delete state, and
  // capital records. Each entry is {kind, payload}. Keys start with the queue
  // time, so replay keeps the order the actions were taken in.

  static Future<String> saveOfflineAction(
    String kind,
    Map<String, dynamic> payload,
  ) async {
    final stamp = DateTime.now().microsecondsSinceEpoch.toString().padLeft(
      20,
      '0',
    );
    final key = 'act_$stamp';
    await _actionQueueBox.put(key, _owned({'kind': kind, 'payload': payload}));
    return key;
  }

  static List<MapEntry<String, Map<dynamic, dynamic>>> getOfflineActions() {
    return _ownedEntries(_actionQueueBox)
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  static Future<void> removeOfflineAction(String key) async {
    await _actionQueueBox.delete(key);
  }

  static Future<void> markOfflineActionError(String key, String message) =>
      _markOwnedError(_actionQueueBox, key, message);

  /// Queued actions the server or validation rejected on their last sync.
  static List<Map<String, dynamic>> getOfflineActionIssues() =>
      _syncIssues(_actionQueueBox);

  /// Records a server rejection against a still-queued expense. The record
  /// stays queued and is retried on the next manual Sync. Only called for a
  /// PostgrestException; network failures stay silent, as before.
  static Future<void> markExpenseQueueItemError(
    String localId,
    String message,
  ) => _markOwnedError(_expenseQueueBox, localId, message);

  /// Queued expenses that failed their last sync with a server-explained reason.
  static List<Map<String, dynamic>> getExpenseSyncIssues() =>
      _syncIssues(_expenseQueueBox);

  /// Stores [message] on a queued record owned by the current user. Records
  /// owned by anyone else are left untouched.
  static Future<void> _markOwnedError(
    Box box,
    String localId,
    String message,
  ) async {
    final existing = box.get(localId);
    if (existing == null) return;
    final updated = Map<dynamic, dynamic>.from(existing as Map);
    final owner = (updated[_ownerKey] as String?) ?? _legacyOwnerId();
    if (owner != getUserId()) return;
    updated['_syncError'] = message;
    updated['_syncErrorAt'] = DateTime.now().toIso8601String();
    await box.put(localId, updated);
  }

  static List<Map<String, dynamic>> _syncIssues(Box box) {
    return _ownedEntries(box)
        .where((entry) => entry.value.containsKey('_syncError'))
        .map(
          (entry) => {
            'localId': entry.key,
            'error': entry.value['_syncError'] as String,
            'failedAt': entry.value['_syncErrorAt'] as String?,
            'payload': entry.value,
          },
        )
        .toList();
  }

  // ─── Cleanup ─────────────────────────────────────────────────────────────────

  static Future<void> closeAll() async {
    await Hive.close();
  }
}
