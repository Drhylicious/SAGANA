import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/buyer_profile_model.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../data/services/profile_photo_service.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/change_password_dialog.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/shared_widgets.dart';

class BuyerEditProfileScreen extends StatefulWidget {
  const BuyerEditProfileScreen({super.key});

  @override
  State<BuyerEditProfileScreen> createState() => _BuyerEditProfileScreenState();
}

class _BuyerEditProfileScreenState extends State<BuyerEditProfileScreen> {
  final _repository = BuyerProfileRepository();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  String? _photoUrl;
  String? _selectedPurok;
  DateTime? _dateOfBirth;
  String? _gender; // male | female | prefer_not_to_say

  @override
  void initState() {
    super.initState();
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
    final profile = await _repository.fetchProfile();
    if (!mounted) return;
    setState(() {
      _nameController.text = profile?.fullName ?? '';
      _phoneController.text = profile?.phoneNumber ?? '';
      _photoUrl = profile?.profilePhotoUrl;
      _emailController.text = profile?.contactEmail ?? '';
      _selectedPurok = profile?.purok;
      _dateOfBirth = profile?.dateOfBirth;
      _gender = profile?.gender;
      _isLoading = false;
    });
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);
    final bytes = await picked.readAsBytes();
    final extension = picked.name.split('.').last;
    final url = await uploadProfilePhoto(
      client: Supabase.instance.client,
      userId: Supabase.instance.client.auth.currentUser!.id,
      imageBytes: bytes,
      fileExtension: extension,
    );
    if (!mounted) return;
    setState(() {
      _isUploadingPhoto = false;
      if (url != null) _photoUrl = url;
    });
    if (url == null && mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photoUploadFailed), backgroundColor: AppConstants.errorRed),
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
      final eighteenth = DateTime(_dateOfBirth!.year + 18, _dateOfBirth!.month, _dateOfBirth!.day);
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
      await _repository.updateProfile(
        fullName: _nameController.text,
        phoneNumber: _phoneController.text,
        photoUrl: _photoUrl,
        contactEmail: _emailController.text.trim(),
        purok: _selectedPurok,
        dateOfBirth: _dateOfBirth,
        gender: _gender,
      );
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
            child: Text(l10n.save,
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
                        displayName: _nameController.text.isNotEmpty ? _nameController.text : l10n.buyerDefaultName,
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
                SectionLabel(label: l10n.personalInformation),
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
                      child: _BuyerLabeledDateField(
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
                        items: const ['male', 'female', 'prefer_not_to_say'],
                        itemLabel: (key) => buyerGenderLabel(l10n, key)!,
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SectionLabel(label: l10n.sectionSecurity),
                const SizedBox(height: 8),
                Material(
                  color: context.saganaColors.cardBackground,
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  elevation: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                      onTap: () => AppDialog.show<void>(context: context, child: const ChangePasswordDialog()),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(color: AppConstants.primaryGreen.withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.lock_reset_rounded, color: AppConstants.primaryGreen),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l10n.changePassword, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                                  Text(l10n.updatePasswordSubtitle,
                                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: AppConstants.outline.withValues(alpha: 0.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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

class _BuyerLabeledDateField extends StatelessWidget {
  final String label;
  final String hintText;
  final String valueText;
  final VoidCallback onTap;

  const _BuyerLabeledDateField({
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