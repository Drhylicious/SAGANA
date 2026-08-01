import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/services/app_settings_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/management_modal.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  @override
  void initState() {
    super.initState();
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
                await AppSettingsService.instance.setLocale(
                  const Locale(AppConstants.localeEnglish),
                );
                if (mounted) {
                  setState(
                    () => _prefs = _prefs!.copyWith(
                      localeCode: AppConstants.localeEnglish,
                    ),
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            _PickerTile(
              label: l10n.languageTagalog,
              selected: _prefs!.localeCode == AppConstants.localeTagalog,
              onTap: () async {
                await AppSettingsService.instance.setLocale(
                  const Locale(AppConstants.localeTagalog),
                );
                if (mounted) {
                  setState(
                    () => _prefs = _prefs!.copyWith(
                      localeCode: AppConstants.localeTagalog,
                    ),
                  );
                }
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
                if (mounted) {
                  setState(
                    () => _prefs = _prefs!.copyWith(themeMode: ThemeMode.light),
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            _PickerTile(
              label: l10n.themeDark,
              selected: _prefs!.themeMode == ThemeMode.dark,
              onTap: () async {
                await AppSettingsService.instance.setThemeMode(ThemeMode.dark);
                if (mounted) {
                  setState(
                    () => _prefs = _prefs!.copyWith(themeMode: ThemeMode.dark),
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadPrefs() async {
    final prefs = await _settingsRepo.loadPrefs();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _isLoading = false;
    });
  }

  // ── Clear Cache ─────────────────────────────────────────────────────────────

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
      _showSnack('Cached data cleared.');
    }
  }

  // ── Sign Out ────────────────────────────────────────────────────────────────

  Future<void> _showSignOutDialog() async {
    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: const _ConfirmDialog(
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

  // ── Info dialogs (Support & Info) ───────────────────────────────────────────

  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text(
          title,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppConstants.onSurface,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            content,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppConstants.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Close',
              style: GoogleFonts.poppins(color: AppConstants.primaryGreen),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),
    );
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

    final prefs = _prefs!;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Stack(
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
                      ],
                    ),
                    const SizedBox(height: 20),

                    SectionLabel(label: l10n.sectionDataExport),
                    SettingsCard(
                      children: [
                        ToggleRow(
                          title: l10n.backgroundSync,
                          value: prefs.backgroundSync,
                          onChanged: (v) async {
                            await _settingsRepo.savePref(
                              AppConstants.hiveKeyBackgroundSync,
                              v,
                            );
                            setState(
                              () => _prefs = prefs.copyWith(backgroundSync: v),
                            );
                          },
                        ),
                        const SettingsDivider(),
                        SettingsRow(
                          icon: Icons.cleaning_services_outlined,
                          iconColor: AppConstants.buyerBlue,
                          title: l10n.clearCachedData,
                          onTap: _confirmClearCache,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Data Export ───────────────────────────────────────
                    const SectionLabel(label: 'Data Export'),
                    SettingsCard(
                      children: [
                        SettingsRow(
                          icon: Icons.download_rounded,
                          iconColor: AppConstants.primaryGreen,
                          title: 'Download My Records',
                          subtitle:
                              'Export your harvest, expense, and sales data',
                          onTap: () => _showSnack(
                            'Export feature coming soon. Contact SP3 Admin for records.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Support & Info ────────────────────────────────────
                    const SectionLabel(label: 'Support & Info'),
                    SettingsCard(
                      children: [
                        SettingsRow(
                          icon: Icons.info_outline_rounded,
                          iconColor: AppConstants.primaryGreen,
                          title: 'About SAGANA',
                          onTap: () => _showInfoDialog(
                            'About SAGANA',
                            'SAGANA — Streamlined Agricultural Gateway for Agribusiness, Networking, and Analytics\n\n'
                                'Version 1.0.0\n\n'
                                'Developed by Marinduque State University — BSIT\n'
                                'Partner: SP3 Agriculture Cooperative\n'
                                'Barangay Payanas, Torrijos, Marinduque\n\n'
                                'SAGANA is a capstone project designed to empower SP3 cooperative farmers through digital record-keeping, direct market access, and data-driven planting insights.',
                          ),
                        ),
                        const SettingsDivider(),
                        SettingsRow(
                          icon: Icons.support_agent_rounded,
                          iconColor: AppConstants.tertiaryContainer,
                          title: 'Contact SP3 Cooperative',
                          onTap: () => _showInfoDialog(
                            'Contact SP3 Cooperative',
                            'Samahan ng Pagkakaisa sa Pag-unlad ng Payanas\n'
                                'SP3 Agriculture Cooperative\n\n'
                                'Address:\nBarangay Payanas, Torrijos, Marinduque\n\n'
                                'For concerns about your account, loans, marketplace listings, or cooperative services, please visit the cooperative office or contact your BOD representative.\n\n'
                                'CDA Registration No.: 9520-1040000000036899\n'
                                'Registered: February 1, 2017',
                          ),
                        ),
                        const SettingsDivider(),
                        SettingsRow(
                          icon: Icons.privacy_tip_outlined,
                          iconColor: AppConstants.amber,
                          title: 'Privacy Policy',
                          onTap: () => _showInfoDialog(
                            'Privacy Policy',
                            'SAGANA collects personal information such as your name, contact number, farm details, and agricultural records solely for the purpose of managing cooperative operations within the SP3 Agriculture Cooperative.\n\n'
                                'Your data is stored securely in Supabase (PostgreSQL) and is accessible only to authorized cooperative staff and your own account.\n\n'
                                'We do not share your personal data with third parties outside the cooperative without your consent.\n\n'
                                'Offline data is stored locally on your device and synchronized to the cooperative database when internet connectivity is restored.\n\n'
                                'For data-related concerns, contact SP3 cooperative management.',
                          ),
                        ),
                        const SettingsDivider(),
                        SettingsRow(
                          icon: Icons.gavel_rounded,
                          iconColor: AppConstants.onSurfaceVariant,
                          title: 'Terms of Use',
                          onTap: () => _showInfoDialog(
                            'Terms of Use',
                            'By using SAGANA, you agree to:\n\n'
                                '1. Use the application solely for cooperative agricultural management within SP3.\n\n'
                                '2. Provide accurate harvest, inventory, and sales data to ensure fair cooperative operations.\n\n'
                                '3. Not share your login credentials with unauthorized individuals.\n\n'
                                '4. Respect the marketplace approval process — listings are subject to SP3 admin review.\n\n'
                                '5. Acknowledge that Balik-Tangkilik estimates shown in the app are approximations and that actual distributions are determined at the Annual General Assembly.\n\n'
                                'Violation of these terms may result in account suspension by the cooperative administrator.',
                          ),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PickerTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PickerTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: GoogleFonts.poppins(fontSize: 14)),
        trailing: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: selected
              ? const Icon(
                  Icons.check_circle_rounded,
                  key: ValueKey('on'),
                  color: AppConstants.primaryGreen,
                )
              : Icon(
                  Icons.circle_outlined,
                  key: const ValueKey('off'),
                  color: Theme.of(context).colorScheme.outline,
                ),
        ),
        onTap: onTap,
      ),
    );
  }
}

/// Shared confirm/cancel pattern for Sign Out — same shape as
/// AdminSettingsScreen's private _ConfirmDialog. Kept local to this file
/// since it isn't reused elsewhere yet; worth promoting to a shared widget
/// if Buyer's sign-out confirm ends up needing the same treatment.
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

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
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: confirmLabel,
                    height: 44,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}