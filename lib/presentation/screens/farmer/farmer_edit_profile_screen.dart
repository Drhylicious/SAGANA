import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
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

  static const Map<String, String> _genderOptions = {
    'male': 'Male',
    'female': 'Female',
    'prefer_not_to_say': 'Prefer not to say',
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload photo. Please try again.')),
      );
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Full name is required.'), backgroundColor: AppConstants.errorRed),
      );
      return;
    }
    if (_dateOfBirth != null) {
      final now = DateTime.now();
      final eighteenth = DateTime(
          _dateOfBirth!.year + 18, _dateOfBirth!.month, _dateOfBirth!.day);
      if (eighteenth.isAfter(now)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be at least 18 years old.'),
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
        const SnackBar(content: Text('Profile updated.'), backgroundColor: AppConstants.successGreen),
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
                  child: Text('Save',
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
                              displayName: _nameController.text.isNotEmpty ? _nameController.text : 'Farmer',
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
                          child: Text('Change Photo',
                              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppConstants.primaryGreen)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SectionLabel(label: l10n.sectionPersonalInformation),
                      const SizedBox(height: 8),
                      AppTextField(
                        controller: _nameController,
                        label: 'Full Name',
                        prefixIcon: Icons.person_outline_rounded,
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _phoneController,
                        label: 'Phone Number',
                        prefixIcon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _emailController,
                        label: 'Email Address (optional)',
                        prefixIcon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      AppDropdownField<String>(
                        value: AppConstants.payanasPuroks.contains(_selectedPurok) ? _selectedPurok : null,
                        hintText: 'Select a purok',
                        labelText: 'Purok',
                        items: AppConstants.payanasPuroks,
                        itemLabel: (s) => s,
                        onChanged: (v) => setState(() => _selectedPurok = v),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _dateOfBirth ?? DateTime(now.year - 25),
                            firstDate: DateTime(1930),
                            lastDate: DateTime(
                                now.year - 18, now.month, now.day),
                          );
                          if (picked != null) {
                            setState(() => _dateOfBirth = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date of Birth',
                            prefixIcon: Icon(Icons.cake_outlined,
                                size: 20, color: AppConstants.outline),
                          ),
                          child: Text(
                            _dateOfBirth == null
                                ? 'Not set'
                                : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: _dateOfBirth == null
                                  ? AppConstants.onSurfaceVariant
                                  : AppConstants.charcoal,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppDropdownField<String>(
                        value: _gender,
                        hintText: 'Select gender',
                        labelText: 'Gender',
                        items: _genderOptions.keys.toList(),
                        itemLabel: (key) => _genderOptions[key]!,
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                      const SizedBox(height: 24),
                      SectionLabel(label: l10n.sectionSecurity),
                      const SizedBox(height: 8),
                      SettingsCard(children: [
                        SettingsRow(
                          icon: Icons.lock_reset_rounded,
                          iconColor: AppConstants.primaryGreen,
                          title: 'Change Password',
                          subtitle: 'Update your account password',
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
              isOnline ? 'Could not load your profile' : 'You\'re offline',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppConstants.charcoal,
              ),
            ),
            if (!isOnline) ...[
              const SizedBox(height: 4),
              Text(
                'Your profile will load once you\'re back online.',
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
                'Retry',
                style: GoogleFonts.poppins(color: AppConstants.primaryGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}