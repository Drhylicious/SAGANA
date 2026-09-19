import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/repositories/admin_profile_repository.dart';
import '../../../data/services/admin_profile_state_service.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/change_password_dialog.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/shared_widgets.dart';

/// Admin Edit Profile — name, phone, purok, photo, and Change Password.
/// Route: /admin/profile/edit. Same shape as BuyerEditProfileScreen:
/// dedicated screen with a Save action, avatar tap-to-change, and a
/// Security section linking out to the shared ChangePasswordDialog.
class AdminEditProfileScreen extends StatefulWidget {
  const AdminEditProfileScreen({super.key});

  @override
  State<AdminEditProfileScreen> createState() => _AdminEditProfileScreenState();
}

class _AdminEditProfileScreenState extends State<AdminEditProfileScreen> {
  final _repo = AdminProfileRepository();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  String? _photoUrl;
  String? _selectedPurok;
  DateTime? _dateOfBirth;
  String? _gender;

  Map<String, String> _genderOptions(AppLocalizations l10n) => {
        'male': l10n.registerGenderMale,
        'female': l10n.registerGenderFemale,
        'prefer_not_to_say': l10n.registerGenderPreferNotToSay,
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _repo.fetchProfile();
    if (!mounted) return;
    setState(() {
      _nameController.text = profile?.fullName ?? '';
      _phoneController.text = profile?.phoneNumber ?? '';
      _photoUrl = profile?.profilePhotoUrl;
      _emailController.text = profile?.email ?? '';
      _selectedPurok = profile?.purok;
      _dateOfBirth = profile?.dateOfBirth;
      _dobController.text = _dateOfBirth == null
          ? ''
          : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}';
      _gender = profile?.gender;
      _isLoading = false;
    });
  }

  Future<void> _pickDateOfBirth() async {
    final picked = await AppUtils.pickDateOfBirth(
      context,
      initialDate: _dateOfBirth,
    );
    if (picked == null) return;
    if (!AppUtils.isAtLeast18(picked)) {
      if (!mounted) return;
      await AppUtils.showUnder18Dialog(context);
      return;
    }
    setState(() {
      _dateOfBirth = picked;
      _dobController.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
      if (picked == null) return;

      setState(() => _isUploadingPhoto = true);
      final bytes = await picked.readAsBytes();
      final extension = picked.name.split('.').last;
      final url = await _repo.updatePhoto(imageBytes: bytes, fileExtension: extension);
      if (!mounted) return;

      if (url != null) {
        setState(() => _photoUrl = url);
        AdminProfileStateService.instance.refresh();
      } else {
        _showPhotoError();
      }
    } catch (_) {
      if (mounted) _showPhotoError();
    } finally {
      if (mounted && _isUploadingPhoto) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  void _showPhotoError() {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.adminProfilePhotoError), backgroundColor: AppConstants.errorRed),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminProfileNameRequired), backgroundColor: AppConstants.errorRed),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _repo.updateBasicInfo(
        fullName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        purok: _selectedPurok,
        dateOfBirth: _dateOfBirth,
        gender: _gender,
      );
      AdminProfileStateService.instance.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminProfileUpdated), backgroundColor: AppConstants.successGreen),
      );
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      final l10n2 = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n2.adminProfileSaveError), backgroundColor: AppConstants.errorRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        leading: BackButton(onPressed: () => context.pop(), color: AppConstants.primaryGreen),
        title: Text(l10n.editProfile,
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(l10n.adminProfileSaveChanges,
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 16, AppConstants.spacingSafeH, 40),
              children: [
                Center(
                  child: Stack(
                    children: [
                      ProfileAvatar(
                        photoUrl: _photoUrl,
                        displayName: _nameController.text.isNotEmpty ? _nameController.text : 'Admin',
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
                    child: Text(l10n.adminProfileChangePhoto,
                        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppConstants.primaryGreen)),
                  ),
                ),
                const SizedBox(height: 20),
                SectionLabel(label: l10n.sectionPersonalInformation),
                const SizedBox(height: 8),
                AppTextField(
                  controller: _nameController,
                  label: l10n.adminProfileFullName,
                  prefixIcon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _emailController,
                  label: l10n.emailAddress,
                  prefixIcon: Icons.email_outlined,
                  readOnly: true,
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(l10n.emailCannotBeChanged,
                      style: GoogleFonts.inter(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _phoneController,
                  label: l10n.adminProfilePhoneNumber,
                  hint: '09XXXXXXXXX',
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
                      child: _LabeledDateField(
                        label: l10n.addMemberDobLabel,
                        hintText: l10n.addMemberSelectHint,
                        valueText: _dobController.text,
                        onTap: _pickDateOfBirth,
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
                    subtitle: l10n.updateYourPassword,
                    onTap: () => AppDialog.show<void>(context: context, child: const ChangePasswordDialog()),
                  ),
                ]),
              ],
            ),
    );
  }
}

/// Date-of-birth field styled to match AppDropdownField's exact shape
/// (a label rendered above the field, then a bordered box) rather than
/// AppTextField's floating inside-label — the two were visually
/// misaligned when placed side by side in a half-width Row (Gender's
/// label-above pushes its box down; AppTextField's inside-label doesn't,
/// and its text truncated at half width). No dropdown arrow box, since
/// this isn't a dropdown — the outer border/radius/padding otherwise
/// matches AppDropdownField's box exactly so both fields' boxes align.
class _LabeledDateField extends StatelessWidget {
  final String label;
  final String hintText;
  final String valueText;
  final VoidCallback onTap;

  const _LabeledDateField({
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