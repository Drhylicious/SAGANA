import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/services/app_settings_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/shared_widgets.dart';

class BuyerSettingsScreen extends StatefulWidget {
  const BuyerSettingsScreen({super.key});

  @override
  State<BuyerSettingsScreen> createState() => _BuyerSettingsScreenState();
}

class _BuyerSettingsScreenState extends State<BuyerSettingsScreen> {
  final _settingsRepo = SettingsRepository();
  SettingsPrefs? _prefs;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await _settingsRepo.loadPrefs();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _isLoading = false;
    });
  }

  String _languageLabel(AppLocalizations l10n) =>
      (_prefs?.localeCode ?? AppConstants.localeEnglish) == AppConstants.localeTagalog
          ? l10n.languageTagalog
          : l10n.languageEnglish;

  String _themeLabel(AppLocalizations l10n) =>
      (_prefs?.themeMode ?? ThemeMode.light) == ThemeMode.dark ? l10n.themeDark : l10n.themeLight;

  void _showLanguagePicker() {
    final l10n = AppLocalizations.of(context);
    showManagementModal(
      context: context,
      builder: (ctx) => ManagementModalShell(
        title: l10n.selectLanguage,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PickerTile(
              label: l10n.languageEnglish,
              selected: _prefs!.localeCode == AppConstants.localeEnglish,
              onTap: () async {
                await AppSettingsService.instance.setLocale(const Locale(AppConstants.localeEnglish));
                if (mounted) setState(() => _prefs = _prefs!.copyWith(localeCode: AppConstants.localeEnglish));
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            _PickerTile(
              label: l10n.languageTagalog,
              selected: _prefs!.localeCode == AppConstants.localeTagalog,
              onTap: () async {
                await AppSettingsService.instance.setLocale(const Locale(AppConstants.localeTagalog));
                if (mounted) setState(() => _prefs = _prefs!.copyWith(localeCode: AppConstants.localeTagalog));
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showThemePicker() {
    final l10n = AppLocalizations.of(context);
    showManagementModal(
      context: context,
      builder: (ctx) => ManagementModalShell(
        title: l10n.selectAppearance,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PickerTile(
              label: l10n.themeLight,
              selected: _prefs!.themeMode == ThemeMode.light,
              onTap: () async {
                await AppSettingsService.instance.setThemeMode(ThemeMode.light);
                if (mounted) setState(() => _prefs = _prefs!.copyWith(themeMode: ThemeMode.light));
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            _PickerTile(
              label: l10n.themeDark,
              selected: _prefs!.themeMode == ThemeMode.dark,
              onTap: () async {
                await AppSettingsService.instance.setThemeMode(ThemeMode.dark);
                if (mounted) setState(() => _prefs = _prefs!.copyWith(themeMode: ThemeMode.dark));
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusXl)),
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: SingleChildScrollView(
          child: Text(content, style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant, height: 1.5)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: GoogleFonts.poppins(color: AppConstants.primaryGreen)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearCache() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: _ConfirmDialog(
        title: l10n.clearCachedData,
        message: l10n.clearCachedDataDescription,
        confirmLabel: l10n.clearCachedData,
      ),
    );
    if (confirmed == true) {
      await _settingsRepo.clearCachedData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.adminProfileCacheCleared), backgroundColor: AppConstants.successGreen),
        );
      }
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await AppDialog.show<bool>(context: context, child: const _LogoutConfirmDialog());
    if (confirmed == true) {
      await AuthService.logout();
      if (!mounted) return;
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: sagana.scaffoldBackground,
        body: const Center(child: CircularProgressIndicator()),
      );
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
              onTap: () => context.push(AppRoutes.buyerEditProfile),
            ),
          ]),
          const SizedBox(height: 20),

          SectionLabel(label: l10n.sectionAppPreferences),
          SettingsCard(children: [
            SettingsRow(
              icon: Icons.dark_mode_outlined,
              iconColor: AppConstants.primaryGreen,
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

          SectionLabel(label: l10n.sectionDataExport),
          SettingsCard(children: [
            ToggleRow(
              title: l10n.backgroundSync,
              value: _prefs!.backgroundSync,
              onChanged: (v) async {
                await _settingsRepo.savePref(AppConstants.hiveKeyBackgroundSync, v);
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
              onTap: () => _showInfoDialog(l10n.aboutSagana, l10n.aboutSaganaBody),
            ),
            const SettingsDivider(),
            SettingsRow(
              icon: Icons.support_agent_rounded,
              iconColor: AppConstants.tertiaryContainer,
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

          SignOutButton(label: l10n.logOut, onTap: _confirmLogout),
          const SizedBox(height: 24),

          const AppBrandingBlock(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets — same visual language as farmer's Settings screen,
// buyer-specific instance (Dart privacy is file-scoped, so this coexists
// fine with the identically-named classes elsewhere). _SectionLabel,
// _SettingsCard, _SettingsRow, and _Divider moved to shared_widgets.dart
// (SectionLabel/SettingsCard/SettingsRow/SettingsDivider) and _AppBrandingBlock
// moved to shared_widgets.dart (AppBrandingBlock) — no longer duplicated here.
//
// NOTE: _ConfirmDialog below duplicates the identical widget now in
// AdminSettingsScreen (and, per the shared plan, FarmerSettingsScreen too).
// Flagged as an open item to consolidate into shared_widgets.dart.
// ─────────────────────────────────────────────────────────────────────────────

class _PickerTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PickerTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: GoogleFonts.poppins(fontSize: 14)),
        trailing: selected
            ? const Icon(Icons.check_circle_rounded, color: AppConstants.primaryGreen)
            : Icon(Icons.circle_outlined, color: Theme.of(context).colorScheme.outline),
        onTap: onTap,
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  const _ConfirmDialog({required this.title, required this.message, required this.confirmLabel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel'))),
                const SizedBox(width: 10),
                Expanded(child: PrimaryButton(label: confirmLabel, height: 44, onPressed: () => Navigator.pop(context, true))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutConfirmDialog extends StatelessWidget {
  const _LogoutConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Log Out?', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('You\'ll need to sign in again to place new orders.',
                textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel'))),
                const SizedBox(width: 10),
                Expanded(child: PrimaryButton(label: 'Log Out', height: 44, onPressed: () => Navigator.pop(context, true))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}