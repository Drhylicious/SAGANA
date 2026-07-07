import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_constants.dart';

// ─── Notification preference keys (all stored in hiveBoxSettings) ─────────────

class NotifPrefKey {
  NotifPrefKey._();
  static const orders          = 'notif_orders';
  static const listingApproved = 'notif_listing_approved';
  static const listingChanges  = 'notif_listing_changes';
  static const loanReminder    = 'notif_loan_reminder';
  static const priceUpdates    = 'notif_price_updates';
  static const syncCompleted   = 'notif_sync_completed';
}

// ─── Settings Model (snapshot of all user preferences) ───────────────────────

class SettingsPrefs {
  final bool notifOrders;
  final bool notifListingApproved;
  final bool notifListingChanges;
  final bool notifLoanReminder;
  final bool notifPriceUpdates;
  final bool notifSyncCompleted;
  final bool backgroundSync;
  final ThemeMode themeMode;
  final String localeCode;

  const SettingsPrefs({
    required this.notifOrders,
    required this.notifListingApproved,
    required this.notifListingChanges,
    required this.notifLoanReminder,
    required this.notifPriceUpdates,
    required this.notifSyncCompleted,
    required this.backgroundSync,
    required this.themeMode,
    required this.localeCode,
  });

  static const defaults = SettingsPrefs(
    notifOrders: true,
    notifListingApproved: true,
    notifListingChanges: true,
    notifLoanReminder: true,
    notifPriceUpdates: true,
    notifSyncCompleted: false,
    backgroundSync: true,
    themeMode: ThemeMode.light,
    localeCode: AppConstants.localeEnglish,
  );

  SettingsPrefs copyWith({
    bool? notifOrders,
    bool? notifListingApproved,
    bool? notifListingChanges,
    bool? notifLoanReminder,
    bool? notifPriceUpdates,
    bool? notifSyncCompleted,
    bool? backgroundSync,
    ThemeMode? themeMode,
    String? localeCode,
  }) {
    return SettingsPrefs(
      notifOrders: notifOrders ?? this.notifOrders,
      notifListingApproved:
          notifListingApproved ?? this.notifListingApproved,
      notifListingChanges: notifListingChanges ?? this.notifListingChanges,
      notifLoanReminder: notifLoanReminder ?? this.notifLoanReminder,
      notifPriceUpdates: notifPriceUpdates ?? this.notifPriceUpdates,
      notifSyncCompleted: notifSyncCompleted ?? this.notifSyncCompleted,
      backgroundSync: backgroundSync ?? this.backgroundSync,
      themeMode: themeMode ?? this.themeMode,
      localeCode: localeCode ?? this.localeCode,
    );
  }
}

// ─── SettingsRepository ───────────────────────────────────────────────────────

class SettingsRepository {
  SupabaseClient get _client => Supabase.instance.client;

  // ─── Load preferences from Hive ──────────────────────────────────────────

  Future<SettingsPrefs> loadPrefs() async {
    final box = await Hive.openBox(AppConstants.hiveBoxSettings);
    final themeRaw =
        box.get(AppConstants.hiveKeyThemeMode, defaultValue: AppConstants.themeLight)
            as String;
    return SettingsPrefs(
      notifOrders:
          box.get(NotifPrefKey.orders, defaultValue: true) as bool,
      notifListingApproved:
          box.get(NotifPrefKey.listingApproved, defaultValue: true) as bool,
      notifListingChanges:
          box.get(NotifPrefKey.listingChanges, defaultValue: true) as bool,
      notifLoanReminder:
          box.get(NotifPrefKey.loanReminder, defaultValue: true) as bool,
      notifPriceUpdates:
          box.get(NotifPrefKey.priceUpdates, defaultValue: true) as bool,
      notifSyncCompleted:
          box.get(NotifPrefKey.syncCompleted, defaultValue: false) as bool,
      backgroundSync:
          box.get(AppConstants.hiveKeyBackgroundSync, defaultValue: true)
              as bool,
      themeMode: themeRaw == AppConstants.themeDark
          ? ThemeMode.dark
          : ThemeMode.light,
      localeCode: box.get(AppConstants.hiveKeyLocale,
              defaultValue: AppConstants.localeEnglish)
          as String,
    );
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final box = await Hive.openBox(AppConstants.hiveBoxSettings);
    await box.put(
      AppConstants.hiveKeyThemeMode,
      mode == ThemeMode.dark
          ? AppConstants.themeDark
          : AppConstants.themeLight,
    );
  }

  Future<void> saveLocale(String languageCode) async {
    final box = await Hive.openBox(AppConstants.hiveBoxSettings);
    await box.put(AppConstants.hiveKeyLocale, languageCode);
  }

  // ─── Save a single preference ─────────────────────────────────────────────

  Future<void> savePref(String key, bool value) async {
    final box = await Hive.openBox(AppConstants.hiveBoxSettings);
    await box.put(key, value);
  }

  // ─── Clear cached price data ──────────────────────────────────────────────

  Future<void> clearCachedData() async {
    final box = await Hive.openBox(AppConstants.hiveBoxPrices);
    await box.clear();
  }

  // ─── Change password ──────────────────────────────────────────────────────
  // Re-authenticates with currentPassword first to verify identity,
  // then updates to newPassword via Supabase Auth.

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
