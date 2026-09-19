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
    final prefs = await _settingsRepo.loadPrefs(userId: AppSettingsService.instance.currentUserId);
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
              iconColor: AppConstants.tertiaryContainer,
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
              iconColor: AppConstants.onSurfaceVariant,
              title: l10n.termsOfUse,
              onTap: () => context.push(AppRoutes.termsOfUse),
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
// _ConfirmDialog moved to shared_widgets.dart (ConfirmDialog) — no longer
// duplicated here either.
// ─────────────────────────────────────────────────────────────────────────────

class _LogoutConfirmDialog extends StatelessWidget {
  const _LogoutConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: context.saganaColors.cardBackground, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
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