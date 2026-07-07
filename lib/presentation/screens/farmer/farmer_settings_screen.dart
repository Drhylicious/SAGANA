import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/services/auth_service.dart';
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
  final _profileRepo  = FarmerProfileRepository();

  SettingsPrefs? _prefs;
  bool _isLoading    = true;
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
    AppBottomSheet.show(
      context: context,
      builder: (ctx) => _BottomSheet(
        title: l10n.selectLanguage,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PickerTile(
              label: l10n.languageEnglish,
              selected: _prefs!.localeCode == AppConstants.localeEnglish,
              onTap: () async {
                await AppSettingsService.instance
                    .setLocale(const Locale(AppConstants.localeEnglish));
                if (mounted) {
                  setState(() => _prefs = _prefs!.copyWith(
                        localeCode: AppConstants.localeEnglish,
                      ));
                }
                if (ctx.mounted) ctx.popRoute();
              },
            ),
            _PickerTile(
              label: l10n.languageTagalog,
              selected: _prefs!.localeCode == AppConstants.localeTagalog,
              onTap: () async {
                await AppSettingsService.instance
                    .setLocale(const Locale(AppConstants.localeTagalog));
                if (mounted) {
                  setState(() => _prefs = _prefs!.copyWith(
                        localeCode: AppConstants.localeTagalog,
                      ));
                }
                if (ctx.mounted) ctx.popRoute();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showThemePicker() {
    final l10n = AppLocalizations.of(context);
    AppBottomSheet.show(
      context: context,
      builder: (ctx) => _BottomSheet(
        title: l10n.selectAppearance,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PickerTile(
              label: l10n.themeLight,
              selected: _prefs!.themeMode == ThemeMode.light,
              onTap: () async {
                await AppSettingsService.instance.setThemeMode(ThemeMode.light);
                if (mounted) {
                  setState(() => _prefs =
                      _prefs!.copyWith(themeMode: ThemeMode.light));
                }
                if (ctx.mounted) ctx.popRoute();
              },
            ),
            _PickerTile(
              label: l10n.themeDark,
              selected: _prefs!.themeMode == ThemeMode.dark,
              onTap: () async {
                await AppSettingsService.instance.setThemeMode(ThemeMode.dark);
                if (mounted) {
                  setState(() => _prefs =
                      _prefs!.copyWith(themeMode: ThemeMode.dark));
                }
                if (ctx.mounted) ctx.popRoute();
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
      _prefs     = prefs;
      _isLoading = false;
    });
  }

  Future<void> _toggle(String key, bool value) async {
    await _settingsRepo.savePref(key, value);
  }

  // ── Edit Profile ────────────────────────────────────────────────────────────

  void _showEditProfileSheet() {
    final nameCtrl  = TextEditingController();
    final phoneCtrl = TextEditingController();
    String? selectedSitio;
    bool isSaving = false;
    FarmerProfileModel? loaded;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModal) {
          return _BottomSheet(
            title: 'Edit Profile',
            child: FutureBuilder<FarmerProfileModel?>(
              future: loaded != null
                  ? Future.value(loaded)
                  : _profileRepo.fetchProfile(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(
                          color: AppConstants.primaryGreen),
                    ),
                  );
                }
                final profile = snap.data;
                loaded = profile;
                if (nameCtrl.text.isEmpty && profile != null) {
                  nameCtrl.text  = profile.fullName;
                  phoneCtrl.text = profile.phoneNumber ?? '';
                  selectedSitio  = profile.sitio;
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTextField(
                      controller: nameCtrl,
                      label: 'Full Name',
                      prefixIcon: Icons.person_outline_rounded,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: phoneCtrl,
                      label: 'Phone Number',
                      prefixIcon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: AppConstants.payanasSitios
                              .contains(selectedSitio)
                          ? selectedSitio
                          : null,
                      decoration: InputDecoration(
                        labelText: 'Sitio / Purok',
                        prefixIcon: const Icon(Icons.location_on_outlined,
                            size: 20, color: AppConstants.outline),
                        labelStyle: GoogleFonts.inter(
                            fontSize: 14, color: AppConstants.outline),
                      ),
                      style: GoogleFonts.inter(
                          fontSize: 14, color: AppConstants.onSurface),
                      items: AppConstants.payanasSitios
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setModal(() => selectedSitio = v),
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: isSaving ? 'Saving...' : 'Save Changes',
                      isLoading: isSaving,
                      onPressed: isSaving
                          ? null
                          : () async {
                              if (nameCtrl.text.trim().isEmpty) {
                                _showSnack('Full name is required.');
                                return;
                              }
                              setModal(() => isSaving = true);
                              try {
                                await _profileRepo.updateBasicInfo(
                                  fullName:    nameCtrl.text.trim(),
                                  phoneNumber: phoneCtrl.text.trim(),
                                  sitio:       selectedSitio,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                _showSnack('Profile updated successfully.');
                              } catch (_) {
                                setModal(() => isSaving = false);
                                _showSnack(
                                    'Failed to save. Please try again.');
                              }
                            },
                    ),
                  ],
                );
              },
            ),
          );
        });
      },
    );
  }

  // ── Change Password ─────────────────────────────────────────────────────────

  void _showChangePasswordSheet() {
    final currentCtrl = TextEditingController();
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool isSaving = false;
    String? errorMsg;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModal) {
          return _BottomSheet(
            title: 'Change Password',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: currentCtrl,
                  label: 'Current Password',
                  prefixIcon: Icons.lock_outline_rounded,
                  isPassword: true,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  controller: newCtrl,
                  label: 'New Password',
                  prefixIcon: Icons.lock_reset_rounded,
                  isPassword: true,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  controller: confirmCtrl,
                  label: 'Confirm New Password',
                  prefixIcon: Icons.lock_reset_rounded,
                  isPassword: true,
                ),
                if (errorMsg != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppConstants.errorRed.withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMd),
                      border: Border.all(
                        color:
                            AppConstants.errorRed.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 16, color: AppConstants.errorRed),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMsg!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppConstants.errorRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Password must be at least 8 characters.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppConstants.outline,
                  ),
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: isSaving ? 'Updating...' : 'Update Password',
                  isLoading: isSaving,
                  onPressed: isSaving
                      ? null
                      : () async {
                          final n = newCtrl.text.trim();
                          final c = confirmCtrl.text.trim();
                          if (currentCtrl.text.isEmpty ||
                              n.isEmpty ||
                              c.isEmpty) {
                            setModal(() =>
                                errorMsg = 'All fields are required.');
                            return;
                          }
                          if (n.length < 8) {
                            setModal(() => errorMsg =
                                'Password must be at least 8 characters.');
                            return;
                          }
                          if (n != c) {
                            setModal(() =>
                                errorMsg = 'Passwords do not match.');
                            return;
                          }
                          setModal(() {
                            isSaving  = true;
                            errorMsg  = null;
                          });
                          try {
                            await _settingsRepo.changePassword(
                              currentPassword: currentCtrl.text,
                              newPassword: n,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _showSnack(
                                'Password updated. Please log in again.');
                            await Future.delayed(
                                const Duration(seconds: 2));
                            await AuthService.logout();
                            if (mounted) {
                              GoRouter.of(context).go(AppRoutes.login);
                            }
                          } catch (e) {
                            setModal(() {
                              isSaving = false;
                              errorMsg = AuthService.parseAuthError(e);
                            });
                          }
                        },
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // ── Clear Cache ─────────────────────────────────────────────────────────────

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text('Clear Cached Data?',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: AppConstants.onSurface)),
        content: Text(
          'This removes locally cached price and market data. '
          'Your harvest records, inventory, and expenses are not affected.',
          style: GoogleFonts.inter(
              fontSize: 13, color: AppConstants.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: AppConstants.outline)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _settingsRepo.clearCachedData();
              _showSnack('Cached data cleared.');
            },
            child: Text('Clear',
                style: GoogleFonts.poppins(color: AppConstants.errorRed)),
          ),
        ],
      ),
    );
  }

  // ── Sign Out ────────────────────────────────────────────────────────────────

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text('Sign Out?',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: AppConstants.onSurface)),
        content: Text(
          'You will be signed out of SAGANA. '
          'Offline records will remain on this device.',
          style: GoogleFonts.inter(
              fontSize: 13, color: AppConstants.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: AppConstants.outline)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isSigningOut = true);
              await AuthService.logout();
              if (mounted) {
                GoRouter.of(context).go(AppRoutes.login);
              }
            },
            child: Text('Sign Out',
                style:
                    GoogleFonts.poppins(color: AppConstants.errorRed)),
          ),
        ],
      ),
    );
  }

  // ── Info dialogs (Support & Info) ───────────────────────────────────────────

  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text(title,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppConstants.onSurface)),
        content: SingleChildScrollView(
          child: Text(content,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppConstants.onSurfaceVariant,
                  height: 1.5)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close',
                style:
                    GoogleFonts.poppins(color: AppConstants.primaryGreen)),
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
            borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = Theme.of(context).extension<SaganaColors>() ?? SaganaColors.light;

    if (_isLoading || _isSigningOut) {
      return Scaffold(
        backgroundColor: sagana.scaffoldBackground,
        body: const Center(
            child: CircularProgressIndicator(
                color: AppConstants.primaryGreen)),
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
                    _SectionLabel(label: l10n.sectionAccount),
                    _SettingsCard(children: [
                      _SettingsRow(
                        icon: Icons.person_outline_rounded,
                        iconColor: AppConstants.primaryGreen,
                        title: l10n.editProfile,
                        subtitle: l10n.editProfileSubtitle,
                        onTap: _showEditProfileSheet,
                      ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.agriculture_rounded,
                        iconColor: AppConstants.tertiaryContainer,
                        title: l10n.editFarmDetails,
                        subtitle: l10n.editFarmDetailsSubtitle,
                        onTap: () => context.pushRoute(AppRoutes.editFarmDetails),
                      ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.lock_outline_rounded,
                        iconColor: AppConstants.amber,
                        title: l10n.changePassword,
                        subtitle: l10n.changePasswordSubtitle,
                        onTap: _showChangePasswordSheet,
                      ),
                    ]),
                    const SizedBox(height: 20),

                    _SectionLabel(label: l10n.sectionNotifications),
                    _SettingsCard(children: [
                      _ToggleRow(
                        title: l10n.notifNewOrder,
                        value: prefs.notifOrders,
                        onChanged: (v) {
                          setState(() => _prefs = prefs.copyWith(notifOrders: v));
                          _toggle(NotifPrefKey.orders, v);
                        },
                      ),
                      _Divider(),
                      _ToggleRow(
                        title: l10n.notifListingApproved,
                        value: prefs.notifListingApproved,
                        onChanged: (v) {
                          setState(
                              () => _prefs = prefs.copyWith(notifListingApproved: v));
                          _toggle(NotifPrefKey.listingApproved, v);
                        },
                      ),
                      _Divider(),
                      _ToggleRow(
                        title: l10n.notifListingChanges,
                        value: prefs.notifListingChanges,
                        onChanged: (v) {
                          setState(
                              () => _prefs = prefs.copyWith(notifListingChanges: v));
                          _toggle(NotifPrefKey.listingChanges, v);
                        },
                      ),
                      _Divider(),
                      _ToggleRow(
                        title: l10n.notifLoanReminder,
                        value: prefs.notifLoanReminder,
                        onChanged: (v) {
                          setState(
                              () => _prefs = prefs.copyWith(notifLoanReminder: v));
                          _toggle(NotifPrefKey.loanReminder, v);
                        },
                      ),
                      _Divider(),
                      _ToggleRow(
                        title: l10n.notifPriceUpdates,
                        value: prefs.notifPriceUpdates,
                        onChanged: (v) {
                          setState(
                              () => _prefs = prefs.copyWith(notifPriceUpdates: v));
                          _toggle(NotifPrefKey.priceUpdates, v);
                        },
                      ),
                      _Divider(),
                      _ToggleRow(
                        title: l10n.notifSyncCompleted,
                        value: prefs.notifSyncCompleted,
                        onChanged: (v) {
                          setState(
                              () => _prefs = prefs.copyWith(notifSyncCompleted: v));
                          _toggle(NotifPrefKey.syncCompleted, v);
                        },
                      ),
                    ]),
                    const SizedBox(height: 20),

                    _SectionLabel(label: l10n.sectionAppPreferences),
                    _SettingsCard(children: [
                      _SettingsRow(
                        icon: Icons.language_rounded,
                        iconColor: AppConstants.buyerBlue,
                        title: l10n.language,
                        subtitle: _languageLabel(l10n),
                        onTap: _showLanguagePicker,
                      ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.dark_mode_outlined,
                        iconColor: AppConstants.primaryGreen,
                        title: l10n.appearance,
                        subtitle: _themeLabel(l10n),
                        onTap: _showThemePicker,
                      ),
                      _Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(l10n.backgroundSync,
                                    style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface)),
                                Switch(
                                  value: prefs.backgroundSync,
                                  onChanged: (v) {
                                    setState(() => _prefs =
                                        prefs.copyWith(backgroundSync: v));
                                    _toggle(
                                        AppConstants.hiveKeyBackgroundSync, v);
                                  },
                                  activeThumbColor: Colors.white,
                                  activeTrackColor: AppConstants.primaryGreen,
                                ),
                              ],
                            ),
                            Text(
                              l10n.backgroundSyncDescription,
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      _Divider(),
                      // Clear Cached Data
                      InkWell(
                        onTap: _showClearCacheDialog,
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusLg),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Clear Cached Data',
                                  style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppConstants.errorRed)),
                              const SizedBox(height: 2),
                              Text(
                                'Removes locally cached price and market data. '
                                'Your harvest and inventory records are not affected.',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppConstants.onSurfaceVariant,
                                    height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),

                    // ── Data Export ───────────────────────────────────────
                    _SectionLabel(label: 'Data Export'),
                    _SettingsCard(children: [
                      _SettingsRow(
                        icon: Icons.download_rounded,
                        iconColor: AppConstants.primaryGreen,
                        title: 'Download My Records',
                        subtitle:
                            'Export your harvest, expense, and sales data',
                        trailingIcon: Icons.download_rounded,
                        onTap: () => _showSnack(
                            'Export feature coming soon. Contact SP3 Admin for records.'),
                      ),
                    ]),
                    const SizedBox(height: 20),

                    // ── Support & Info ────────────────────────────────────
                    _SectionLabel(label: 'Support & Info'),
                    _SettingsCard(children: [
                      _SettingsRow(
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
                      _Divider(),
                      _SettingsRow(
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
                      _Divider(),
                      _SettingsRow(
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
                      _Divider(),
                      _SettingsRow(
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
                    ]),
                    const SizedBox(height: 28),

                    // ── App branding ──────────────────────────────────────
                    _AppBrandingBlock(),
                    const SizedBox(height: 24),

                    // ── Sign Out ──────────────────────────────────────────
                    Center(
                      child: GestureDetector(
                        onTap: _showSignOutDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppConstants.errorRed
                                .withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusFull),
                            border: Border.all(
                              color: AppConstants.errorRed
                                  .withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.logout_rounded,
                                  color: AppConstants.errorRed, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Sign Out',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppConstants.errorRed,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Container(
                        height: 4,
                        width: 60,
                        decoration: BoxDecoration(
                          color: AppConstants.outline.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull),
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
              onProfileTap: () {},
              onNotificationTap: () =>
                  context.pushRoute(AppRoutes.farmerNotifications),
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

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppConstants.outline,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Column(children: children),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: AppConstants.outline.withValues(alpha: 0.08),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final IconData trailingIcon;

  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.trailingIcon = Icons.chevron_right_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _IconBadge(icon: icon, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppConstants.onSurface)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(trailingIcon,
                color: AppConstants.outline, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: GoogleFonts.inter(
                  fontSize: 14, color: AppConstants.onSurface)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppConstants.primaryGreen,
          ),
        ],
      ),
    );
  }
}

class _AppBrandingBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppConstants.primaryGreen,
                    AppConstants.primaryContainer,
                  ],
                ),
              ),
              child: const Icon(Icons.agriculture_rounded,
                  color: Colors.white, size: 32),
            ),
            const SizedBox(height: 12),
            Text('SAGANA',
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.primaryGreen)),
            Text(
              'Streamlined Agricultural Gateway for\nAgribusiness, Networking, and Analytics',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppConstants.onSurfaceVariant,
                  height: 1.4),
            ),
            const SizedBox(height: 6),
            Text('v1.0.0',
                style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.amber,
                    letterSpacing: 1.2)),
            const SizedBox(height: 16),
            Divider(
                height: 1,
                color: AppConstants.outline.withValues(alpha: 0.10)),
            const SizedBox(height: 14),
            Text(
              'Developed by Marinduque State University — BSIT',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppConstants.onSurfaceVariant),
            ),
            Text(
              'Partner: SP3 Agriculture Cooperative',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: GoogleFonts.poppins(fontSize: 14)),
      trailing: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: selected
            ? const Icon(Icons.check_circle_rounded,
                key: ValueKey('on'), color: AppConstants.primaryGreen)
            : Icon(Icons.circle_outlined,
                key: const ValueKey('off'),
                color: Theme.of(context).colorScheme.outline),
      ),
      onTap: onTap,
    );
  }
}

class _BottomSheet extends StatelessWidget {
  final String title;
  final Widget child;
  const _BottomSheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppConstants.offWhite,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXl)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppConstants.outline.withValues(alpha: 0.30),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.onSurface)),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}
