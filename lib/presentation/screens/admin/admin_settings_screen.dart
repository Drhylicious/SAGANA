import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/services/admin_profile_state_service.dart';
import '../../../data/services/app_settings_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';

/// Admin Settings — Account, App Preference, Data & Storage, Support & Info,
/// Sign Out. Route: /admin/profile/settings
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _settingsRepo = SettingsRepository();
  SettingsPrefs? _prefs;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await _settingsRepo.loadPrefs(userId: AppSettingsService.instance.currentUserId);
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _isLoading = false;
    });
  }

  String _languageLabel(AppLocalizations l10n) =>
      (_prefs?.localeCode ?? AppConstants.localeEnglish) == AppConstants.localeTagalog
          ? l10n.languageTagalog : l10n.languageEnglish;

  String _themeLabel(AppLocalizations l10n) =>
      (_prefs?.themeMode ?? ThemeMode.light) == ThemeMode.dark ? l10n.themeDark : l10n.themeLight;

  Future<void> _setDarkMode(bool isDark) async {
    await AppSettingsService.instance.setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
    if (mounted) {
      setState(() => _prefs = _prefs!.copyWith(themeMode: isDark ? ThemeMode.dark : ThemeMode.light));
    }
  }

  Future<void> _setTagalog(bool isTagalog) async {
    final code = isTagalog ? AppConstants.localeTagalog : AppConstants.localeEnglish;
    await AppSettingsService.instance.setLocale(Locale(code));
    if (mounted) setState(() => _prefs = _prefs!.copyWith(localeCode: code));
  }

  Future<void> _confirmClearCache() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: ConfirmDialog(title: l10n.clearCachedData, message: l10n.clearCachedDataDescription, confirmLabel: l10n.clearCachedData, cancelLabel: l10n.issueLoanCancel),
    );
    if (confirmed == true) {
      final hadData = await _settingsRepo.clearCachedData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hadData ? l10n.adminProfileCacheCleared : 'No cached data to clear.'),
            backgroundColor: hadData ? AppConstants.successGreen : AppConstants.onSurfaceVariant,
          ),
        );
      }
    }
  }

  Future<void> _confirmSignOut() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: ConfirmDialog(
        title: l10n.adminProfileSignOutTitle,
        message: l10n.adminProfileSignOutMessage,
        confirmLabel: l10n.adminProfileSignOut,
        cancelLabel: l10n.issueLoanCancel,
      ),
    );
    if (confirmed == true) {
      AdminProfileStateService.instance.clear();
      await AuthService.logout();
      if (mounted) context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    if (_isLoading) {
      return Scaffold(backgroundColor: sagana.scaffoldBackground, body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        leading: BackButton(onPressed: () => context.pop(), color: AppConstants.primaryGreen),
        title: Text(l10n.settingsTitle,
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 8, AppConstants.spacingSafeH, 40),
        children: [
          SectionLabel(label: l10n.sectionAccount),
          SettingsCard(children: [
            SettingsRow(
              icon: Icons.person_outline_rounded,
              iconColor: AppConstants.primaryGreen,
              title: l10n.editProfile,
              subtitle: l10n.editProfileSubtitle,
              onTap: () => context.push(AppRoutes.adminEditProfile),
            ),
          ]),
          const SizedBox(height: 20),

          SectionLabel(label: l10n.sectionAppPreferences),
          SettingsCard(children: [
            SettingsRow(
              icon: Icons.dark_mode_outlined,
              iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
              title: l10n.appearance,
              subtitle: _themeLabel(l10n),
              showChevron: false,
              trailing: Switch(
                value: (_prefs?.themeMode ?? ThemeMode.light) == ThemeMode.dark,
                onChanged: _setDarkMode,
              ),
            ),
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.language_rounded,
              iconColor: AppConstants.buyerBlue,
              title: l10n.language,
              subtitle: _languageLabel(l10n),
              showChevron: false,
              trailing: Switch(
                value: (_prefs?.localeCode ?? AppConstants.localeEnglish) == AppConstants.localeTagalog,
                onChanged: _setTagalog,
              ),
            ),
          ]),
          const SizedBox(height: 20),

          SectionLabel(label: l10n.sectionStorage),
          SettingsCard(children: [
            ToggleRow(
              title: l10n.backgroundSync,
              value: _prefs!.backgroundSync,
              onChanged: (v) async {
                await _settingsRepo.saveBackgroundSync(v, userId: AppSettingsService.instance.currentUserId);
                setState(() => _prefs = _prefs!.copyWith(backgroundSync: v));
              },
            ),
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.cleaning_services_outlined,
              iconColor: AppConstants.buyerBlue,
              title: l10n.clearCachedData,
              onTap: _confirmClearCache,
            ),
          ]),
          const SizedBox(height: 20),

          SectionLabel(label: l10n.sectionSupportInfo),
          SettingsCard(children: [
            SettingsRow(
              icon: Icons.info_outline_rounded,
              iconColor: AppConstants.primaryGreen,
              title: l10n.aboutSagana,
              onTap: () => context.push(AppRoutes.aboutSagana),
            ),
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.support_agent_rounded,
              iconColor: AppConstants.buyerBlue,
              title: l10n.aboutCooperative,
              onTap: () => context.push(AppRoutes.aboutCooperative),
            ),
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.privacy_tip_outlined,
              iconColor: AppConstants.amber,
              title: l10n.privacyPolicy,
              onTap: () => context.push(AppRoutes.privacyPolicy),
            ),
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.gavel_rounded,
              iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
              title: l10n.termsOfUse,
              onTap: () => context.push(AppRoutes.termsOfUse),
            ),
          ]),
          const SizedBox(height: 28),

          SignOutButton(label: l10n.adminProfileSignOut, onTap: _confirmSignOut),
          const SizedBox(height: 24),

          const AppBrandingBlock(),
        ],
      ),
    );
  }
}