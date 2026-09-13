import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../services/hive_service.dart';

// ─── Settings Model (snapshot of all user preferences) ───────────────────────

class SettingsPrefs {
  final bool backgroundSync;
  final ThemeMode themeMode;
  final String localeCode;

  const SettingsPrefs({
    required this.backgroundSync,
    required this.themeMode,
    required this.localeCode,
  });

  static const defaults = SettingsPrefs(
    backgroundSync: true,
    themeMode: ThemeMode.light,
    localeCode: AppConstants.localeEnglish,
  );

  SettingsPrefs copyWith({
    bool? backgroundSync,
    ThemeMode? themeMode,
    String? localeCode,
  }) {
    return SettingsPrefs(
      backgroundSync: backgroundSync ?? this.backgroundSync,
      themeMode: themeMode ?? this.themeMode,
      localeCode: localeCode ?? this.localeCode,
    );
  }
}

// ─── SettingsRepository ───────────────────────────────────────────────────────

class SettingsRepository {
  SupabaseClient get _client => Supabase.instance.client;

  // Theme and locale are account-specific preferences, not device-wide
  // ones — each user gets their own composite key. userId is null only
  // in the brief pre-login window (splash screen), where the unscoped
  // key is the safe fallback, matching this method's prior behavior.
  // backgroundSync intentionally NOT scoped here — see savePref() below.
  String _scopedKey(String baseKey, String? userId) =>
      userId != null ? '${userId}::$baseKey' : baseKey;

  // ─── Load preferences from Hive ──────────────────────────────────────────

  Future<SettingsPrefs> loadPrefs({String? userId}) async {
    final box = await Hive.openBox(AppConstants.hiveBoxSettings);
    final themeRaw = box.get(
      _scopedKey(AppConstants.hiveKeyThemeMode, userId),
      defaultValue: AppConstants.themeLight,
    ) as String;
    return SettingsPrefs(
      // Delegates to HiveService rather than re-reading the same box/key
      // independently — HiveService.init() is guaranteed to have run
      // before this is ever called (it's awaited first thing in main()),
      // so this is safe and removes the duplicate accessor.
      backgroundSync: HiveService.getBackgroundSync(userId: userId),
      themeMode: themeRaw == AppConstants.themeDark
          ? ThemeMode.dark
          : ThemeMode.light,
      localeCode: box.get(
        _scopedKey(AppConstants.hiveKeyLocale, userId),
        defaultValue: AppConstants.localeEnglish,
      ) as String,
    );
  }

  Future<void> saveThemeMode(ThemeMode mode, {String? userId}) async {
    final box = await Hive.openBox(AppConstants.hiveBoxSettings);
    await box.put(
      _scopedKey(AppConstants.hiveKeyThemeMode, userId),
      mode == ThemeMode.dark
          ? AppConstants.themeDark
          : AppConstants.themeLight,
    );
  }

  Future<void> saveLocale(String languageCode, {String? userId}) async {
    final box = await Hive.openBox(AppConstants.hiveBoxSettings);
    await box.put(_scopedKey(AppConstants.hiveKeyLocale, userId), languageCode);
  }

  // ─── Save a single preference ─────────────────────────────────────────────

  Future<void> savePref(String key, bool value) async {
    final box = await Hive.openBox(AppConstants.hiveBoxSettings);
    await box.put(key, value);
  }

  // Dedicated, per-user-scoped write for Background Sync specifically —
  // kept separate from savePref() above rather than adding userId there,
  // since savePref() is generic and this scoping is only meaningful for
  // this one preference right now.
  Future<void> saveBackgroundSync(bool value, {String? userId}) async {
    await HiveService.setBackgroundSync(value, userId: userId);
  }

  // ─── Clear cached price data ──────────────────────────────────────────────

  // Returns whether there was anything to actually clear. Lets the caller
  // give an honest, state-accurate message instead of always claiming a
  // clear occurred — the box is legitimately empty today because nothing
  // in the codebase currently writes price data into it, but this stays
  // correct automatically if that ever changes, with no further edits
  // needed here.
  Future<bool> clearCachedData() async {
    final box = await Hive.openBox(AppConstants.hiveBoxPrices);
    final hadData = box.isNotEmpty;
    await box.clear();
    return hadData;
  }

  // ─── Change password ──────────────────────────────────────────────────────
  // Re-authenticates with currentPassword first to verify identity,
  // then updates to newPassword via Supabase Auth.

  // User-initiated change from Settings — re-authenticates with the
  // current password before allowing the update. For the forced-reset
  // flow (admin-issued temporary password, no prior password to verify),
  // see AuthService.changePassword() instead.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) throw Exception('No authenticated user found.');

    // Step 1: Re-authenticate to verify the current password
    await _client.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );

    // Step 2: Update to new password
    await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }
}