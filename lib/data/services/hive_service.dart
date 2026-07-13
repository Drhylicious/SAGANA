import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/constants/app_constants.dart';

class HiveService {
  HiveService._();

  static late Box _userBox;
  static late Box _pricesBox;
  static late Box _settingsBox;
  static late Box _loanQueueBox; // offline loan issuances + payments
  static late Box _exportHistoryBox; // NEW — Export Center's Recent Exports

  // ─── Initialization ──────────────────────────────────────────────────────────

  static Future<void> init() async {
    await Hive.initFlutter();
    _userBox = await Hive.openBox(AppConstants.hiveBoxUser);
    _pricesBox = await Hive.openBox(AppConstants.hiveBoxPrices);
    _settingsBox = await Hive.openBox(AppConstants.hiveBoxSettings);
    _loanQueueBox = await Hive.openBox(AppConstants.hiveBoxLoanQueue);
    _exportHistoryBox = await Hive.openBox(AppConstants.hiveBoxExportHistory); // NEW
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

  // ─── Settings ────────────────────────────────────────────────────────────────

  static Future<void> setBackgroundSync(bool enabled) async {
    await _settingsBox.put(AppConstants.hiveKeyBackgroundSync, enabled);
  }

  static bool getBackgroundSync() =>
      _settingsBox.get(AppConstants.hiveKeyBackgroundSync, defaultValue: true) as bool;

  // ─── Price Cache ─────────────────────────────────────────────────────────────

  static Future<void> cachePrices(Map<String, dynamic> prices) async {
    await _pricesBox.put('cached_prices', prices);
    await _pricesBox.put('prices_cached_at', DateTime.now().toIso8601String());
  }

  static Map<String, dynamic>? getCachedPrices() {
    final data = _pricesBox.get('cached_prices');
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  static DateTime? getPricesCachedAt() {
    final raw = _pricesBox.get('prices_cached_at') as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> clearPriceCache() async {
    await _pricesBox.delete('cached_prices');
    await _pricesBox.delete('prices_cached_at');
  }

  // ─── Sync Count ──────────────────────────────────────────────────────────────

  static Future<void> setUnsyncedCount(int count) async {
    await _settingsBox.put('unsynced_count', count);
  }

  static int getUnsyncedCount() =>
      _settingsBox.get('unsynced_count', defaultValue: 0) as int;

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

  static int getPendingLoanIssuanceCount() => _getPendingByPrefix('issue_').length;

  static int getPendingLoanPaymentCount() => _getPendingByPrefix('payment_').length;

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

  // ─── Cleanup ─────────────────────────────────────────────────────────────────

  static Future<void> closeAll() async {
    await Hive.close();
  }
}