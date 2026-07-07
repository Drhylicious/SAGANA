import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/constants/app_constants.dart';

class HiveService {
  HiveService._();

  static late Box _userBox;
  static late Box _pricesBox;
  static late Box _settingsBox;
  static late Box _loanQueueBox; // NEW — pending offline loan issuances

  // ─── Initialization ──────────────────────────────────────────────────────────

  static Future<void> init() async {
    await Hive.initFlutter();
    _userBox = await Hive.openBox(AppConstants.hiveBoxUser);
    _pricesBox = await Hive.openBox(AppConstants.hiveBoxPrices);
    _settingsBox = await Hive.openBox(AppConstants.hiveBoxSettings);
    _loanQueueBox = await Hive.openBox(AppConstants.hiveBoxLoanQueue); // NEW
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

  // ─── Farmer Roster Cache (NEW — offline Issue-Loan farmer picker) ────────────
  //
  // The cooperative has ~52 farmers total, so caching the full roster
  // (id, name, member ID only — no photos) is cheap and lets the admin
  // pick a farmer during a signal-less BOD meeting. Refreshed whenever
  // Issue New Loan loads while online.

  static Future<void> cacheFarmerRoster(List<Map<String, dynamic>> roster) async {
    await _settingsBox.put('cached_farmer_roster', roster);
  }

  static List<Map<dynamic, dynamic>> getCachedFarmerRoster() {
    final data = _settingsBox.get('cached_farmer_roster');
    if (data == null) return [];
    return List<Map<dynamic, dynamic>>.from(data as List);
  }

  // ─── Loan Issuance Queue (NEW — offline BOD meeting mode) ────────────────────
  //
  // A queued loan is stored WITHOUT a reference number — reference
  // generation requires querying existing loans (needs connectivity) and
  // is deliberately deferred to sync time. See AdminLoanRepository.issueLoan().

  static Future<void> savePendingLoanIssuance(Map<String, dynamic> payload) async {
    final localId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
    await _loanQueueBox.put(localId, payload);
  }

  static List<MapEntry<String, Map<dynamic, dynamic>>> getPendingLoanIssuances() {
    return _loanQueueBox.keys
        .map((key) => MapEntry(
              key as String,
              Map<dynamic, dynamic>.from(_loanQueueBox.get(key) as Map),
            ))
        .toList();
  }

  static Future<void> removePendingLoanIssuance(String localId) async {
    await _loanQueueBox.delete(localId);
  }

  static int getPendingLoanIssuanceCount() => _loanQueueBox.length;

  // ─── Cleanup ─────────────────────────────────────────────────────────────────

  static Future<void> closeAll() async {
    await Hive.close();
  }
}