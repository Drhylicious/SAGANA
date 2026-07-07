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

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;

  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> init() async {
    final prefs = await _repo.loadPrefs();
    _themeMode = prefs.themeMode;
    _locale = Locale(prefs.localeCode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _repo.saveThemeMode(mode);
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    await _repo.saveLocale(locale.languageCode);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    await setThemeMode(
      _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}
