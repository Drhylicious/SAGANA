import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../repositories/settings_repository.dart';

/// Global app preferences: theme mode and locale.
/// Persists in Hive (survives logout).
class AppSettingsService extends ChangeNotifier {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  final SettingsRepository _repo = SettingsRepository();

  ThemeMode _themeMode = ThemeMode.light;
  Locale _locale = const Locale(AppConstants.localeEnglish);
  String? _currentUserId;

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  String? get currentUserId => _currentUserId;

  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> init({String? userId}) async {
    _currentUserId = userId;
    final prefs = await _repo.loadPrefs(userId: userId);
    _themeMode = prefs.themeMode;
    _locale = Locale(prefs.localeCode);
  }

  // Called on successful login — reloads whichever preferences belong to
  // the newly authenticated user (or defaults, for a first-time device),
  // without requiring an app restart. Preferences are never reset on
  // logout by design — only overwritten by the next successful login.
  Future<void> reloadForUser(String? userId) async {
    _currentUserId = userId;
    final prefs = await _repo.loadPrefs(userId: userId);
    _themeMode = prefs.themeMode;
    _locale = Locale(prefs.localeCode);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _repo.saveThemeMode(mode, userId: _currentUserId);
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    await _repo.saveLocale(locale.languageCode, userId: _currentUserId);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    await setThemeMode(
      _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}
