import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/services/app_settings_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';

class FarmerSettingsScreen extends StatefulWidget {
  const FarmerSettingsScreen({super.key});

  @override
  State<FarmerSettingsScreen> createState() => _FarmerSettingsScreenState();
}

class _FarmerSettingsScreenState extends State<FarmerSettingsScreen> {
  final _settingsRepo = SettingsRepository();

  SettingsPrefs? _prefs;
  bool _isLoading = true;
  bool _isSigningOut = false;
  bool _isOnline = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _loadPrefs();
  }

  String _languageLabel(AppLocalizations l10n) {
    final code = _prefs?.localeCode ?? AppConstants.localeEnglish;
    return code == AppConstants.localeTagalog
        ? l10n.languageTagalog
        : l10n.languageEnglish;
  }

  String _themeLabel(AppLocalizations l10n) {
    final mode = _prefs?.themeMode ?? ThemeMode.light;
    return mode == ThemeMode.dark ? l10n.themeDark : l10n.themeLight;
  }

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

  Future<void> _loadPrefs() async {
    final prefs = await _settingsRepo.loadPrefs(userId: AppSettingsService.instance.currentUserId);
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _isLoading = false;
    });
  }

  // ── Sign Out ────────────────────────────────────────────────────────────────

  Future<void> _showSignOutDialog() async {
    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: const ConfirmDialog(
        title: 'Sign Out?',
        message: 'You will be signed out of SAGANA. '
            'Offline records will remain on this device.',
        confirmLabel: 'Sign Out',
      ),
    );
    if (confirmed == true) {
      setState(() => _isSigningOut = true);
      await AuthService.logout();
      if (mounted) {
        GoRouter.of(context).go(AppRoutes.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana =
        Theme.of(context).extension<SaganaColors>() ?? SaganaColors.light;

    if (_isLoading || _isSigningOut) {
      return Scaffold(
        backgroundColor: sagana.scaffoldBackground,
        body: const Center(
          child: CircularProgressIndicator(color: AppConstants.primaryGreen),
        ),
      );
    }

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(message: "You're offline — changing your password requires an internet connection."),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 64),
                    Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
                  children: [
                    // ── Account ───────────────────────────────────────────
                    SectionLabel(label: l10n.sectionAccount),
                    SettingsCard(
                      children: [
                        SettingsRow(
                          icon: Icons.person_outline_rounded,
                          iconColor: AppConstants.primaryGreen,
                          title: l10n.editProfile,
                          subtitle: l10n.editProfileSubtitle,
                          onTap: () =>
                              context.pushRoute(AppRoutes.farmerEditProfile),
                        ),
                        const SettingsDivider(),
                        SettingsRow(
                          icon: Icons.agriculture_rounded,
                          iconColor: AppConstants.tertiaryContainer,
                          title: l10n.editFarmDetails,
                          subtitle: l10n.editFarmDetailsSubtitle,
                          onTap: () =>
                              context.pushRoute(AppRoutes.editFarmDetails),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    SectionLabel(label: l10n.sectionAppPreferences),
                    SettingsCard(
                      children: [
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
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Support & Info ────────────────────────────────────
                    SectionLabel(label: l10n.sectionSupportInfo),
                    SettingsCard(
                      children: [
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
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ── Sign Out ──────────────────────────────────────────
                    SignOutButton(label: l10n.signOut, onTap: _showSignOutDialog),
                    const SizedBox(height: 24),

                    // ── App branding ──────────────────────────────────────
                    const AppBrandingBlock(),
                    const SizedBox(height: 20),
                    Center(
                      child: Container(
                        height: 4,
                        width: 60,
                        decoration: BoxDecoration(
                          color: AppConstants.outline.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: l10n.settingsTitle,
              onBack: () => context.popRoute(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

