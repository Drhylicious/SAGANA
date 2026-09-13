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
import '../../widgets/management_modal.dart';
import '../../widgets/material_list_tile.dart';
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

  void _showThemePicker() {
    final l10n = AppLocalizations.of(context);
    showManagementModal(
      context: context,
      builder: (ctx) => ManagementModalShell(
        title: l10n.selectAppearance,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pickerTile(l10n.themeLight, _prefs!.themeMode == ThemeMode.light, () async {
              await AppSettingsService.instance.setThemeMode(ThemeMode.light);
              if (mounted) setState(() => _prefs = _prefs!.copyWith(themeMode: ThemeMode.light));
              if (ctx.mounted) Navigator.pop(ctx);
            }),
            _pickerTile(l10n.themeDark, _prefs!.themeMode == ThemeMode.dark, () async {
              await AppSettingsService.instance.setThemeMode(ThemeMode.dark);
              if (mounted) setState(() => _prefs = _prefs!.copyWith(themeMode: ThemeMode.dark));
              if (ctx.mounted) Navigator.pop(ctx);
            }),
          ],
        ),
      ),
    );
  }

  void _showLanguagePicker() {
    final l10n = AppLocalizations.of(context);
    showManagementModal(
      context: context,
      builder: (ctx) => ManagementModalShell(
        title: l10n.selectLanguage,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pickerTile(l10n.languageEnglish, _prefs!.localeCode == AppConstants.localeEnglish, () async {
              await AppSettingsService.instance.setLocale(const Locale(AppConstants.localeEnglish));
              if (mounted) setState(() => _prefs = _prefs!.copyWith(localeCode: AppConstants.localeEnglish));
              if (ctx.mounted) Navigator.pop(ctx);
            }),
            _pickerTile(l10n.languageTagalog, _prefs!.localeCode == AppConstants.localeTagalog, () async {
              await AppSettingsService.instance.setLocale(const Locale(AppConstants.localeTagalog));
              if (mounted) setState(() => _prefs = _prefs!.copyWith(localeCode: AppConstants.localeTagalog));
              if (ctx.mounted) Navigator.pop(ctx);
            }),
          ],
        ),
      ),
    );
  }

  Widget _pickerTile(String label, bool selected, VoidCallback onTap) {
    return MaterialListTile(
      title: Text(label, style: GoogleFonts.poppins(fontSize: 14)),
      trailing: selected ? const Icon(Icons.check_circle_rounded, color: AppConstants.primaryGreen) : null,
      onTap: onTap,
    );
  }

  void _showInfoDialog(String title, String content) {
    showManagementModal(
      context: context,
      builder: (ctx) => ManagementModalShell(
        title: title,
        body: SingleChildScrollView(
          child: Text(content, style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant, height: 1.5)),
        ),
      ),
    );
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
              iconColor: AppConstants.charcoal,
              title: l10n.appearance,
              subtitle: _themeLabel(l10n),
              onTap: _showThemePicker,
            ),
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.language_rounded,
              iconColor: AppConstants.buyerBlue,
              title: l10n.language,
              subtitle: _languageLabel(l10n),
              onTap: _showLanguagePicker,
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
              onTap: () => _showInfoDialog(l10n.aboutSagana, l10n.adminAboutSaganaBody),
            ),
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.support_agent_rounded,
              iconColor: AppConstants.buyerBlue,
              title: l10n.contactSp3,
              onTap: () => _showInfoDialog(l10n.contactSp3, l10n.contactSp3Body),
            ),
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.privacy_tip_outlined,
              iconColor: AppConstants.amber,
              title: l10n.privacyPolicy,
              onTap: () => _showInfoDialog(l10n.privacyPolicy, l10n.privacyPolicyBody),
            ),
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.gavel_rounded,
              iconColor: AppConstants.onSurfaceVariant,
              title: l10n.termsOfUse,
              onTap: () => _showInfoDialog(l10n.termsOfUse, l10n.termsOfUseBody),
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