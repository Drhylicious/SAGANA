import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_profile_model.dart';
import '../../../data/repositories/admin_profile_repository.dart';
import '../../../data/services/admin_profile_state_service.dart';
import '../../../data/services/app_settings_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/web_safe_blur_container.dart';

/// Admin Profile — the logged-in administrator's own account.
/// Pushed above the shell. Route: /admin/profile
///
/// Deliberately excludes any cooperative-wide stats (pending approvals,
/// overdue loans, etc.) — that surface belongs to Admin Dashboard. This
/// screen is only about the admin's own account: identity, organizational
/// info (read-only), and app preferences. No notification-preference
/// toggles — admin_notifications_screen.dart has no underlying preference
/// mechanism yet, so there's nothing real to expose here.
class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  final _repo = AdminProfileRepository();
  final _settingsRepo = SettingsRepository();

  AdminProfileModel? _profile;
  bool _isLoading = true;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final profile = await _repo.fetchProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _isLoading = false;
    });
    if (profile != null) {
      AdminProfileStateService.instance.updateProfile(profile);
    }
  }

  // ─── Photo actions ──────────────────────────────────────────────────────

  void _showPhotoActionsSheet() {
    final l10n = AppLocalizations.of(context);
    final hasPhoto = (_profile?.profilePhotoUrl ?? '').isNotEmpty;

    AppBottomSheet.show(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppConstants.primaryGreen),
              title: Text(l10n.adminProfileChangePhoto, style: GoogleFonts.inter(fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadPhoto();
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppConstants.errorRed),
                title: Text(
                  l10n.adminProfileRemovePhoto,
                  style: GoogleFonts.inter(fontSize: 14, color: AppConstants.errorRed),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _removePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPhoto() async {
    final l10n = AppLocalizations.of(context);
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final Uint8List bytes = await picked.readAsBytes();
      final extension = picked.path.split('.').last.toLowerCase();
      final url = await _repo.updatePhoto(imageBytes: bytes, fileExtension: extension);

      if (!mounted) return;
      if (url == null) {
        _showSnack(l10n.adminProfilePhotoError, isError: true);
      } else {
        setState(() => _profile = _profile?.copyWith(profilePhotoUrl: url));
        if (_profile != null) AdminProfileStateService.instance.updateProfile(_profile!);
        _showSnack(l10n.adminProfilePhotoUpdated);
      }
    } catch (_) {
      if (!mounted) return;
      _showSnack(l10n.adminProfilePhotoError, isError: true);
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    await _repo.removePhoto();
    if (!mounted) return;
    setState(() => _profile = _profile?.copyWith(profilePhotoUrl: ''));
    if (_profile != null) AdminProfileStateService.instance.updateProfile(_profile!);
  }

  // ─── Edit profile ───────────────────────────────────────────────────────

  void _showEditProfileSheet() {
    final l10n = AppLocalizations.of(context);
    final profile = _profile;
    if (profile == null) return;

    final nameCtrl = TextEditingController(text: profile.fullName);
    final phoneCtrl = TextEditingController(text: profile.phoneNumber ?? '');
    String? selectedSitio = profile.sitio;
    bool isSaving = false;

    AppBottomSheet.show(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.editProfile, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: nameCtrl,
                    label: l10n.adminProfileFullName,
                    prefixIcon: Icons.person_outline_rounded,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: phoneCtrl,
                    label: l10n.adminProfilePhoneNumber,
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: AppConstants.payanasSitios.contains(selectedSitio) ? selectedSitio : null,
                    decoration: InputDecoration(
                      labelText: l10n.adminProfileSitio,
                      prefixIcon: const Icon(Icons.location_on_outlined, size: 20, color: AppConstants.outline),
                    ),
                    items: AppConstants.payanasSitios
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setModal(() => selectedSitio = v),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: isSaving ? l10n.adminProfileSaving : l10n.adminProfileSaveChanges,
                    isLoading: isSaving,
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (nameCtrl.text.trim().isEmpty) {
                              _showSnack(l10n.adminProfileNameRequired, isError: true);
                              return;
                            }
                            setModal(() => isSaving = true);
                            try {
                              await _repo.updateBasicInfo(
                                fullName: nameCtrl.text.trim(),
                                phoneNumber: phoneCtrl.text.trim(),
                                sitio: selectedSitio,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              setState(() => _profile = _profile?.copyWith(
                                    fullName: nameCtrl.text.trim(),
                                    phoneNumber: phoneCtrl.text.trim(),
                                    sitio: selectedSitio,
                                  ));
                              if (_profile != null) AdminProfileStateService.instance.updateProfile(_profile!);
                              _showSnack(l10n.adminProfileUpdated);
                            } catch (_) {
                              setModal(() => isSaving = false);
                              _showSnack(l10n.adminProfileSaveError, isError: true);
                            }
                          },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── Change password ────────────────────────────────────────────────────

  void _showChangePasswordSheet() {
    final l10n = AppLocalizations.of(context);
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool isSaving = false;
    String? errorMsg;

    AppBottomSheet.show(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.changePassword, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: currentCtrl,
                    label: l10n.adminProfileCurrentPassword,
                    prefixIcon: Icons.lock_outline_rounded,
                    isPassword: true,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: newCtrl,
                    label: l10n.adminProfileNewPassword,
                    prefixIcon: Icons.lock_reset_rounded,
                    isPassword: true,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: confirmCtrl,
                    label: l10n.adminProfileConfirmPassword,
                    prefixIcon: Icons.lock_reset_rounded,
                    isPassword: true,
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppConstants.errorRed.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                        border: Border.all(color: AppConstants.errorRed.withValues(alpha: 0.20)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 16, color: AppConstants.errorRed),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(errorMsg!, style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    l10n.adminProfilePasswordHint,
                    style: GoogleFonts.inter(fontSize: 11, color: AppConstants.outline),
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: isSaving ? l10n.adminProfileUpdating : l10n.adminProfileUpdatePassword,
                    isLoading: isSaving,
                    onPressed: isSaving
                        ? null
                        : () async {
                            final n = newCtrl.text.trim();
                            final c = confirmCtrl.text.trim();
                            if (currentCtrl.text.isEmpty || n.isEmpty || c.isEmpty) {
                              setModal(() => errorMsg = l10n.adminProfileAllFieldsRequired);
                              return;
                            }
                            if (n.length < 8) {
                              setModal(() => errorMsg = l10n.adminProfilePasswordTooShort);
                              return;
                            }
                            if (n != c) {
                              setModal(() => errorMsg = l10n.adminProfilePasswordMismatch);
                              return;
                            }
                            setModal(() {
                              isSaving = true;
                              errorMsg = null;
                            });
                            try {
                              await _settingsRepo.changePassword(
                                currentPassword: currentCtrl.text,
                                newPassword: n,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              _showSnack(l10n.adminProfilePasswordUpdated);
                              await Future.delayed(const Duration(seconds: 2));
                              await AuthService.logout();
                              if (mounted) context.go(AppRoutes.login);
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
          },
        );
      },
    );
  }

  // ─── Clear cache / sign out ─────────────────────────────────────────────

  void _showClearCacheDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusXl)),
        title: Text(l10n.adminProfileClearCacheTitle, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(l10n.adminProfileClearCacheMessage, style: GoogleFonts.inter(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.issueLoanCancel)),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _settingsRepo.clearCachedData();
              if (mounted) _showSnack(l10n.adminProfileCacheCleared);
            },
            child: Text(l10n.adminProfileClearCacheConfirm, style: const TextStyle(color: AppConstants.errorRed)),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusXl)),
        title: Text(l10n.adminProfileSignOutTitle, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(l10n.adminProfileSignOutMessage, style: GoogleFonts.inter(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.issueLoanCancel)),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              AdminProfileStateService.instance.clear();
              await AuthService.logout();
              if (mounted) context.go(AppRoutes.login);
            },
            child: Text(l10n.adminProfileSignOutConfirm, style: const TextStyle(color: AppConstants.errorRed)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: isError ? AppConstants.errorRed : AppConstants.successGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
    ));
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildTopBar(context, l10n, cs, sagana),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _profile == null
                    ? Center(
                        child: Text(l10n.adminProfileLoadError, style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                          children: [
                            _buildIdentityCard(context, l10n, cs, sagana),
                            const SizedBox(height: AppConstants.spacingSectionV),
                            _sectionLabel(l10n.sectionAccount, cs),
                            _settingsCard(sagana, cs, [
                              _settingsRow(
                                icon: Icons.person_outline_rounded,
                                iconColor: AppConstants.primaryGreen,
                                title: l10n.editProfile,
                                onTap: _showEditProfileSheet,
                                cs: cs,
                              ),
                              _divider(cs),
                              _settingsRow(
                                icon: Icons.lock_outline_rounded,
                                iconColor: AppConstants.amber,
                                title: l10n.changePassword,
                                onTap: _showChangePasswordSheet,
                                cs: cs,
                              ),
                            ]),
                            const SizedBox(height: AppConstants.spacingSectionV),
                            _sectionLabel(l10n.adminProfileOrganizationalInfo, cs),
                            _buildOrgInfoCard(context, l10n, cs, sagana),
                            const SizedBox(height: AppConstants.spacingSectionV),
                            _sectionLabel(l10n.adminProfilePreferences, cs),
                            _buildPreferencesCard(context, l10n, cs, sagana),
                            const SizedBox(height: AppConstants.spacingSectionV),
                            _sectionLabel(l10n.adminProfileDataAndStorage, cs),
                            _settingsCard(sagana, cs, [
                              _settingsRow(
                                icon: Icons.cleaning_services_outlined,
                                iconColor: AppConstants.buyerBlue,
                                title: l10n.adminProfileClearCache,
                                onTap: _showClearCacheDialog,
                                cs: cs,
                              ),
                            ]),
                            const SizedBox(height: AppConstants.spacingSectionV),
                            _settingsCard(sagana, cs, [
                              _settingsRow(
                                icon: Icons.logout_rounded,
                                iconColor: AppConstants.errorRed,
                                title: l10n.adminProfileSignOut,
                                titleColor: AppConstants.errorRed,
                                onTap: _showSignOutDialog,
                                cs: cs,
                                showChevron: false,
                              ),
                            ]),
                            const SizedBox(height: AppConstants.spacingSectionV),
                            Center(
                              child: Text(
                                l10n.adminProfileAppVersion('1.0.0'),
                                style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return WebSafeBlurContainer(
      decoration: BoxDecoration(
        color: sagana.glassBackground,
        border: Border(bottom: BorderSide(color: sagana.glassBorder)),
      ),
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSm),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  l10n.adminProfileTitle,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: cs.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentityCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final profile = _profile!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        gradient: AppConstants.primaryButtonGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        children: [
          ProfileAvatar(
            photoUrl: profile.profilePhotoUrl,
            displayName: profile.fullName,
            radius: 40,
            onTap: _isUploadingPhoto ? null : _showPhotoActionsSheet,
            badge: _isUploadingPhoto
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt_rounded, size: 12, color: AppConstants.primaryGreen),
                  ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            profile.fullName,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white),
          ),
          Text(
            profile.position ?? l10n.adminProfileDefaultRole,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 4),
          Text(
            profile.email,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.70)),
          ),
        ],
      ),
    );
  }

  Widget _buildOrgInfoCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final profile = _profile!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _orgInfoRow(l10n.adminProfileEmployeeId, profile.employeeId ?? '—', cs),
          const SizedBox(height: AppConstants.spacingSm),
          _orgInfoRow(l10n.adminProfilePosition, profile.position ?? '—', cs),
          const SizedBox(height: AppConstants.spacingSm),
          _orgInfoRow(l10n.adminProfileDepartment, profile.department ?? '—', cs),
          if (profile.adminSince != null) ...[
            const SizedBox(height: AppConstants.spacingSm),
            _orgInfoRow(
              l10n.adminProfileAdminSince,
              DateFormat('MMMM yyyy').format(profile.adminSince!),
              cs,
            ),
          ],
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            l10n.adminProfileOrgInfoHint,
            style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _orgInfoRow(String label, String value, ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
        Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface)),
      ],
    );
  }

  Widget _buildPreferencesCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return ListenableBuilder(
      listenable: AppSettingsService.instance,
      builder: (context, _) {
        final settings = AppSettingsService.instance;
        return _settingsCard(sagana, cs, [
          _settingsRow(
            icon: Icons.dark_mode_outlined,
            iconColor: AppConstants.charcoal,
            title: l10n.selectAppearance,
            subtitle: settings.isDark ? l10n.themeDark : l10n.themeLight,
            onTap: () => _showThemePicker(context, l10n),
            cs: cs,
          ),
          _divider(cs),
          _settingsRow(
            icon: Icons.language_rounded,
            iconColor: AppConstants.buyerBlue,
            title: l10n.selectLanguage,
            subtitle: settings.locale.languageCode == AppConstants.localeTagalog
                ? l10n.languageTagalog
                : l10n.languageEnglish,
            onTap: () => _showLanguagePicker(context, l10n),
            cs: cs,
          ),
        ]);
      },
    );
  }

  void _showThemePicker(BuildContext context, AppLocalizations l10n) {
    AppBottomSheet.show(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.themeLight),
              trailing: AppSettingsService.instance.themeMode == ThemeMode.light ? const Icon(Icons.check, color: AppConstants.primaryGreen) : null,
              onTap: () async {
                await AppSettingsService.instance.setThemeMode(ThemeMode.light);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: Text(l10n.themeDark),
              trailing: AppSettingsService.instance.themeMode == ThemeMode.dark ? const Icon(Icons.check, color: AppConstants.primaryGreen) : null,
              onTap: () async {
                await AppSettingsService.instance.setThemeMode(ThemeMode.dark);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, AppLocalizations l10n) {
    AppBottomSheet.show(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.languageEnglish),
              trailing: AppSettingsService.instance.locale.languageCode == AppConstants.localeEnglish
                  ? const Icon(Icons.check, color: AppConstants.primaryGreen)
                  : null,
              onTap: () async {
                await AppSettingsService.instance.setLocale(const Locale(AppConstants.localeEnglish));
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: Text(l10n.languageTagalog),
              trailing: AppSettingsService.instance.locale.languageCode == AppConstants.localeTagalog
                  ? const Icon(Icons.check, color: AppConstants.primaryGreen)
                  : null,
              onTap: () async {
                await AppSettingsService.instance.setLocale(const Locale(AppConstants.localeTagalog));
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Local settings-list primitives (mirrors farmer_settings_screen.dart's
  // private widgets visually; not imported since those are library-private
  // to that file) ────────────────────────────────────────────────────────

  Widget _sectionLabel(String label, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: cs.outline, letterSpacing: 0.8),
      ),
    );
  }

  Widget _settingsCard(SaganaColors sagana, ColorScheme cs, List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Column(children: children),
      ),
    );
  }

  Widget _divider(ColorScheme cs) {
    return Divider(height: 1, thickness: 1, color: cs.outline.withValues(alpha: 0.08));
  }

  Widget _settingsRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    required ColorScheme cs,
    Color? titleColor,
    bool showChevron = true,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: titleColor ?? cs.onSurface),
                  ),
                  if (subtitle != null)
                    Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            if (showChevron) Icon(Icons.chevron_right_rounded, color: cs.outline, size: 18),
          ],
        ),
      ),
    );
  }
}