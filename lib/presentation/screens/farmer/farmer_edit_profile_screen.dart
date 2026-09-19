import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/profile_state_service.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/change_password_dialog.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/shared_widgets.dart';

/// Farmer Edit Profile — name, phone, purok, photo, Change Password.
/// Route: /farmer/profile/edit. Mirrors AdminEditProfileScreen exactly;
/// replaces the bottom-sheet edit form and photo picker that previously
/// lived inline in FarmerProfileScreen/FarmerSettingsScreen.
class FarmerEditProfileScreen extends StatefulWidget {
  const FarmerEditProfileScreen({super.key});

  @override
  State<FarmerEditProfileScreen> createState() => _FarmerEditProfileScreenState();
}

class _FarmerEditProfileScreenState extends State<FarmerEditProfileScreen> {
  final _repo = FarmerProfileRepository();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  bool _isOnline = true;
  bool _loadFailed = false;
  String? _photoUrl;
  String? _selectedPurok;
  DateTime? _dateOfBirth;
  String? _gender; // male | female | prefer_not_to_say

  Map<String, String> _genderOptions(AppLocalizations l10n) => {
        'male': l10n.registerGenderMale,
        'female': l10n.registerGenderFemale,
        'prefer_not_to_say': l10n.registerGenderPreferNotToSay,
      };

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final profile =
          await _repo.fetchProfile().timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _nameController.text = profile?.fullName ?? '';
        _phoneController.text = profile?.phoneNumber ?? '';
        _emailController.text = profile?.contactEmail ?? '';
        _photoUrl = profile?.profilePhotoUrl;
        _selectedPurok = profile?.purok;
        _dateOfBirth = profile?.dateOfBirth;
        _gender = profile?.gender;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);
    final Uint8List bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').last;
    final url = await _repo.updatePhoto(imageBytes: bytes, fileExtension: ext);
    if (!mounted) return;
    setState(() {
      _isUploadingPhoto = false;
      if (url != null) _photoUrl = url;
    });
    if (url != null) {
      FarmerProfileStateService.instance.refresh();
    } else if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photoUploadFailed)),
      );
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.fullNameEmpty), backgroundColor: AppConstants.errorRed),
      );
      return;
    }
    if (_dateOfBirth != null) {
      final now = DateTime.now();
      final eighteenth = DateTime(
          _dateOfBirth!.year + 18, _dateOfBirth!.month, _dateOfBirth!.day);
      if (eighteenth.isAfter(now)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.pendingAgeError),
            backgroundColor: AppConstants.errorRed,
          ),
        );
        return;
      }
    }
    setState(() => _isSaving = true);
    try {
      await _repo.updateBasicInfo(
        fullName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        purok: _selectedPurok,
        contactEmail: _emailController.text.trim(),
        dateOfBirth: _dateOfBirth,
        gender: _gender,
      );
      FarmerProfileStateService.instance.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileUpdated), backgroundColor: AppConstants.successGreen),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppConstants.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(message: "You're offline — you won't be able to save changes until you're reconnected."),
          // When the banner is showing, it already occupies the space the
          // status bar inset would otherwise reserve, so that inset is
          // removed here to avoid double top-padding between the banner
          // and the title row. When online (no banner), this AppBar
          // behaves exactly as it did as Scaffold's native appBar.
          MediaQuery.removePadding(
            context: context,
            removeTop: !_isOnline,
            child: AppBar(
              backgroundColor: sagana.scaffoldBackground,
              elevation: 0,
              leading: BackButton(onPressed: () => context.pop(), color: AppConstants.primaryGreen),
              title: Text(l10n.editProfile,
                  style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
              actions: [
                TextButton(
                  onPressed: _isSaving ? null : _save,
                  child: Text(l10n.save,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _loadFailed
                ? _EditProfileLoadError(onRetry: _load, isOnline: _isOnline)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 16, AppConstants.spacingSafeH, 40),
                    children: [
                      Center(
                        child: Stack(
                          children: [
                            ProfileAvatar(
                              photoUrl: _photoUrl,
                              displayName: _nameController.text.isNotEmpty ? _nameController.text : l10n.defaultFarmerName,
                              radius: 56,
                            ),
                            if (_isUploadingPhoto)
                              Positioned.fill(
                                child: Container(
                                  decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                                  child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                                ),
                              )
                            else
                              Positioned(
                                bottom: 0, right: 0,
                                child: GestureDetector(
                                  onTap: _pickPhoto,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(color: AppConstants.primaryGreen, shape: BoxShape.circle),
                                    child: const Icon(Icons.edit_rounded, size: 16, color: Colors.white),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: _isUploadingPhoto ? null : _pickPhoto,
                          child: Text(l10n.changePhoto,
                              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppConstants.primaryGreen)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SectionLabel(label: l10n.sectionPersonalInformation),
                      const SizedBox(height: 8),
                      AppTextField(
                        controller: _nameController,
                        label: l10n.fullName,
                        prefixIcon: Icons.person_outline_rounded,
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _emailController,
                        label: l10n.emailAddress,
                        prefixIcon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _phoneController,
                        label: l10n.phoneNumber,
                        prefixIcon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      AppDropdownField<String>(
                        value: AppConstants.payanasPuroks.contains(_selectedPurok) ? _selectedPurok : null,
                        hintText: l10n.addMemberSelectHint,
                        labelText: l10n.adminProfilePurok,
                        items: AppConstants.payanasPuroks,
                        itemLabel: (s) => s,
                        onChanged: (v) => setState(() => _selectedPurok = v),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _FarmerLabeledDateField(
                              label: l10n.addMemberDobLabel,
                              hintText: l10n.addMemberSelectHint,
                              valueText: _dateOfBirth == null
                                  ? ''
                                  : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
                              onTap: () async {
                                final picked = await AppUtils.pickDateOfBirth(
                                  context,
                                  initialDate: _dateOfBirth,
                                );
                                if (picked == null) return;
                                if (!AppUtils.isAtLeast18(picked)) {
                                  if (!context.mounted) return;
                                  await AppUtils.showUnder18Dialog(context);
                                  return;
                                }
                                setState(() => _dateOfBirth = picked);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppDropdownField<String>(
                              value: _gender,
                              hintText: l10n.addMemberSelectHint,
                              labelText: l10n.addMemberGenderLabel,
                              items: _genderOptions(l10n).keys.toList(),
                              itemLabel: (key) => _genderOptions(l10n)[key]!,
                              onChanged: (v) => setState(() => _gender = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SectionLabel(label: l10n.sectionSecurity),
                      const SizedBox(height: 8),
                      SettingsCard(children: [
                        SettingsRow(
                          icon: Icons.lock_reset_rounded,
                          iconColor: AppConstants.primaryGreen,
                          title: l10n.changePassword,
                          subtitle: l10n.updatePasswordSubtitle,
                          onTap: () => AppDialog.show<void>(
                            context: context,
                            child: ChangePasswordDialog(onSuccess: _repo.logPasswordChanged),
                          ),
                        ),
                      ]),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Profile Load Error — shown when fetchProfile() fails or times out.
// Message/icon distinguish "you're offline" from a genuine load failure,
// matching FarmerProfileScreen's _ProfileLoadError pattern.
// ─────────────────────────────────────────────────────────────────────────────

class _EditProfileLoadError extends StatelessWidget {
  final VoidCallback onRetry;
  final bool isOnline;
  const _EditProfileLoadError({required this.onRetry, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOnline ? Icons.error_outline_rounded : Icons.wifi_off_rounded,
              size: 40,
              color: AppConstants.outline.withValues(alpha: 0.60),
            ),
            const SizedBox(height: 12),
            Text(
              isOnline ? l10n.couldNotLoadProfile : l10n.youAreOffline,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppConstants.charcoal,
              ),
            ),
            if (!isOnline) ...[
              const SizedBox(height: 4),
              Text(
                l10n.profileWillLoadWhenOnline,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text(
                l10n.retry,
                style: GoogleFonts.poppins(color: AppConstants.primaryGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Labeled date field — mirrors AdminEditProfileScreen's private
// _LabeledDateField (Dart privates aren't shared across files) so DOB/Gender
// align identically across roles: a one-line label capped with maxLines/
// ellipsis so a longer translated label never wraps and misaligns this
// field's height against its sibling Gender dropdown.
// ─────────────────────────────────────────────────────────────────────────────

class _FarmerLabeledDateField extends StatelessWidget {
  final String label;
  final String hintText;
  final String valueText;
  final VoidCallback onTap;

  const _FarmerLabeledDateField({
    required this.label,
    required this.hintText,
    required this.valueText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasValue = valueText.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.cake_outlined, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasValue ? valueText : hintText,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: hasValue ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}