import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/db_error_utils.dart';
import '../../../core/utils/input_validation_utils.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/utils/contact_email.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../data/models/admin_profile_model.dart';
import '../../../data/repositories/admin_activity_repository.dart';
import '../../../data/repositories/admin_profile_repository.dart';
import '../../../data/repositories/contact_email_verification_repository.dart';
import '../../../data/services/offline_actions.dart';
import '../../../data/services/admin_profile_state_service.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/change_password_dialog.dart';
import '../../widgets/contact_email_verification.dart';
import '../../widgets/person_name_fields.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../../data/models/admin_log_message.dart';
import '../../widgets/sub_page_top_bar.dart';

/// Admin Edit Profile — name, phone, photo, and Change Password.
/// Route: /admin/profile/edit. Same shape as BuyerEditProfileScreen:
/// dedicated screen with a Save action, avatar tap-to-change, and a
/// Security section linking out to the shared ChangePasswordDialog.
class AdminEditProfileScreen extends StatefulWidget {
  const AdminEditProfileScreen({super.key, this.initialProfile, this.verifier});

  /// Tests: stands in for the server calls behind Verify Email.
  @visibleForTesting
  final ContactEmailVerifier? verifier;

  /// Tests: shown instead of loading the profile from the server.
  @visibleForTesting
  final AdminProfileModel? initialProfile;

  @override
  State<AdminEditProfileScreen> createState() => _AdminEditProfileScreenState();
}

class _AdminEditProfileScreenState extends State<AdminEditProfileScreen> {
  final _repo = AdminProfileRepository();
  final _name = PersonNameInput();
  final _nameFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _emailController = TextEditingController();

  // The email can be changed by both. The Officer's is a contact email (their
  // sign-in address is a generated username and is never touched). The Manager's
  // IS their sign-in address, so changing it also needs their current password.
  // Either way a new address is only PENDING until its code is entered: the email
  // in use, and the verified one, stay as they are until then.
  bool get _isOfficer => HiveService.isOfficer;
  late final ContactEmailVerifier _verifier =
      widget.verifier ?? SupabaseContactEmailVerifier();
  String? _activeEmail; // in use today
  String? _pendingEmail; // asked for, not yet verified
  String? _verifiedEmail; // the last address proven with a code
  /// The address a code would go to: the pending one, else the one in use.
  String? get _savedEmail => _pendingEmail ?? _activeEmail;
  bool get _emailVerified =>
      ContactEmail.isVerified(contactEmail: _savedEmail, verifiedEmail: _verifiedEmail);
  bool get _activeVerified =>
      ContactEmail.isVerified(contactEmail: _activeEmail, verifiedEmail: _verifiedEmail);

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  String? _photoUrl;
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
    _name.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = widget.initialProfile ?? await _repo.fetchProfile();
    if (!mounted) return;
    setState(() {
      _name.load(
        fullName: profile?.fullName,
        surnameValue: profile?.surname,
        firstNameValue: profile?.firstName,
        middleInitialValue: profile?.middleInitial,
        suffixValue: profile?.suffix,
      );
      _phoneController.text = profile?.phoneNumber ?? '';
      _photoUrl = profile?.profilePhotoUrl;
      _activeEmail = _isOfficer
          ? profile?.contactEmail
          : (profile?.verifiableEmail ?? profile?.email);
      final pending = profile?.pendingContactEmail?.trim() ?? '';
      _pendingEmail = pending.isEmpty ? null : pending;
      _verifiedEmail = profile?.verifiedContactEmail;
      // A change the person already started is shown where they left it.
      _emailController.text = _pendingEmail ?? _activeEmail ?? '';
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
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _isUploadingPhoto = true);
      final bytes = await picked.readAsBytes();
      final extension = picked.name.split('.').last;
      final result = await _repo.updatePhoto(
        imageBytes: bytes,
        fileExtension: extension,
      );
      if (!mounted) return;

      if (result.url != null) {
        setState(() => _photoUrl = result.url);
        AdminProfileStateService.instance.refresh();
      } else if (result.queued) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).savedOnDeviceSyncLater),
          ),
        );
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
      SnackBar(
        content: Text(l10n.adminProfilePhotoError),
        backgroundColor: AppConstants.errorRed,
      ),
    );
  }

  // Verify Email first names the address (same checks as Save): it becomes the
  // PENDING address; the email in use does not change. Returns true once stored.
  Future<bool> _saveEmailForVerification() async {
    final l10n = AppLocalizations.of(context);
    void fail(String message) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppConstants.errorRed),
      );
    }

    final email = _emailController.text.trim();
    if (!isValidEmailFormat(email)) {
      fail(l10n.registerInvalidEmail);
      return false;
    }
    if (email.toLowerCase() != (_activeEmail ?? '').toLowerCase()) {
      final domain = await AuthService.checkEmailDomain(email);
      if (!mounted) return false;
      if (domain == EmailDomainStatus.noMailServer) {
        fail(l10n.registerEmailDomainInvalid);
        return false;
      }
    }
    return _storePendingEmail(email, fail);
  }

  /// Names [email] as the address to switch to (or clears the change when it is
  /// the one already in use). Shows the reason and returns false if refused.
  Future<bool> _storePendingEmail(String email, void Function(String) fail) async {
    final l10n = AppLocalizations.of(context);
    final result = await _verifier.setPendingEmail(email);
    if (!mounted) return false;
    switch (result.status) {
      case PendingEmailStatus.pending:
        setState(() => _pendingEmail = email.toLowerCase());
        return true;
      case PendingEmailStatus.cleared:
        setState(() => _pendingEmail = null);
        return true;
      case PendingEmailStatus.invalidFormat:
        fail(l10n.registerInvalidEmail);
      case PendingEmailStatus.reserved:
        fail(l10n.emailChangeReserved);
      case PendingEmailStatus.inUse:
        fail(l10n.emailChangeAddressInUse);
      case PendingEmailStatus.notSignedIn:
        fail(l10n.emailVerifyUnauthorized);
      case PendingEmailStatus.error:
        fail(l10n.adminProfileSaveError);
    }
    return false;
  }

  // The verified address is now what the Manager signs in with.
  Future<void> _onSignInEmailChanged() async {
    final shown = _savedEmail ?? '';
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (_) {
      // The session still works; the new address is used at the next sign-in.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).emailSignInChanged(shown)),
        backgroundColor: AppConstants.midGreen,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    // Surname and first name are checked on the fields themselves.
    if (!(_nameFormKey.currentState?.validate() ?? false)) return;

    // The email: a Manager's cannot be blank (it is how they sign in); an
    // Officer may remove theirs. Otherwise format first, and the domain when it
    // differs from the one in use.
    final email = _emailController.text.trim();
    if (email.isEmpty && !_isOfficer) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.emailCannotBeEmpty),
          backgroundColor: AppConstants.errorRed,
        ),
      );
      return;
    }
    if (email.isNotEmpty) {
      if (!isValidEmailFormat(email)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.registerInvalidEmail),
            backgroundColor: AppConstants.errorRed,
          ),
        );
        return;
      }
      if (email.toLowerCase() != (_activeEmail ?? '').toLowerCase()) {
        final domain = await AuthService.checkEmailDomain(email);
        if (!mounted) return;
        if (domain == EmailDomainStatus.noMailServer) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.registerEmailDomainInvalid),
              backgroundColor: AppConstants.errorRed,
            ),
          );
          return;
        }
      }
    }

    final phoneText = _phoneController.text.trim();
    if (phoneText.isNotEmpty && normalizePhilippineMobile(phoneText) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.registerInvalidPhone),
          backgroundColor: AppConstants.errorRed,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      // The email: a change is stored as PENDING (the email in use stays until
      // the code is entered). Online only: it is checked against other accounts.
      final typed = email.toLowerCase();
      final stored = (_savedEmail ?? '').toLowerCase();
      if (typed != stored) {
        void fail(String message) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: AppConstants.errorRed),
          );
        }

        if (email.isEmpty) {
          // An Officer removing their contact email.
          await _repo.updateContactEmail('');
          await _verifier.setPendingEmail('');
          if (mounted) setState(() { _activeEmail = null; _pendingEmail = null; });
        } else if (!await _storePendingEmail(email, fail)) {
          if (mounted) setState(() => _isSaving = false);
          return;
        }
      }
      final outcome = await _repo.updateBasicInfo(
        name: _name.parts,
        phoneNumber: _phoneController.text.trim(),
        dateOfBirth: _dateOfBirth,
        gender: _gender,
      );
      AdminProfileStateService.instance.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outcome == SaveOutcome.queued
                ? l10n.savedOnDeviceSyncLater
                : l10n.adminProfileUpdated,
          ),
          backgroundColor: AppConstants.midGreen,
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      final l10n2 = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(readableDatabaseMessage(e) ?? l10n2.adminProfileSaveError),
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

      body: Column(
        children: [
          SubPageTopBar(title: l10n.editProfile, onBack: () => Navigator.of(context).pop(), trailing: TextButton( onPressed: _isSaving ? null : _save, child: Text( l10n.adminProfileSaveChanges, style: GoogleFonts.poppins( fontSize: 14, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen, ), ), )),
          Expanded(child: _isLoading
          ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingSafeH,
                16,
                AppConstants.spacingSafeH,
                40,
              ),
              children: [
                Center(
                  child: Stack(
                    children: [
                      ProfileAvatar(
                        photoUrl: _photoUrl,
                        displayName: _name.displayName('Admin'),
                        radius: 56,
                      ),
                      if (_isUploadingPhoto)
                        Positioned.fill(
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black38,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        )
                      else
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _pickPhoto,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: AppConstants.primaryGreen,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.edit_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
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
                    child: Text(
                      l10n.adminProfileChangePhoto,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SectionLabel(label: l10n.sectionPersonalInformation),
                const SizedBox(height: 8),
                Form(
                  key: _nameFormKey,
                  child: PersonNameFields(
                    style: PersonNameFieldsStyle.profile,
                    surnameController: _name.surname,
                    firstNameController: _name.firstName,
                    middleInitialController: _name.middleInitial,
                    suffix: _name.suffix,
                    onSuffixChanged: (v) => setState(() => _name.suffix = v),
                    allowAllBlank: _name.legacyFullName != null,
                    legacyFullName: _name.legacyFullName,
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _emailController,
                  label: l10n.emailAddress,
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                ContactEmailVerification(
                  emailController: _emailController,
                  savedEmail: _savedEmail,
                  verified: _emailVerified,
                  activeEmail: _activeEmail,
                  activeVerified: _activeVerified,
                  // A Manager signs in with this address.
                  signInEmail: !_isOfficer,
                  requiresPasswordWhenChanged: !_isOfficer,
                  isOnline: ConnectivityService.instance.isOnline,
                  verifier: _verifier,
                  saveEmail: _saveEmailForVerification,
                  onSignInEmailChanged: _onSignInEmailChanged,
                  onVerified: () {
                    setState(() {
                      // The proven address is now the one in use.
                      _activeEmail = _savedEmail;
                      _pendingEmail = null;
                      _verifiedEmail = _activeEmail;
                    });
                    AdminProfileStateService.instance.refresh();
                  },
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
                SettingsCard(
                  children: [
                  SettingsRow(
                    icon: Icons.lock_reset_rounded,
                    iconColor: AppConstants.primaryGreen,
                    title: l10n.changePassword,
                    subtitle: l10n.updateYourPassword,
                      onTap: () => AppDialog.show<void>(
                        context: context,
                        child: ChangePasswordDialog(
                          onSuccess: () => AdminActivityRepository().log(
                            module: 'profile',
                            actionType: 'password_changed',
                            message: const AdminLogMessage('adminLogPasswordChanged'),
                          ),
                        ),
                      ),
                    ),
                  ],
                  ),
              ],
            )),
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
        Text(
          label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
        ),
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
                      color: hasValue
                          ? cs.onSurface
                          : cs.onSurfaceVariant.withValues(alpha: 0.7),
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