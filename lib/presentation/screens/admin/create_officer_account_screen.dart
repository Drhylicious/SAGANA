import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/input_validation_utils.dart';
import '../../../core/utils/temp_password.dart';
import '../../../data/repositories/account_management_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/auth_service.dart';
import '../../widgets/account_form_widgets.dart';
import '../../widgets/person_name_fields.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/username_availability_field.dart';

/// Manager → Members → Add Officer Account.
///
/// The Manager enters the Officer's details directly. There is no registry
/// lookup: the full name is ordinary text, and the username must be unique
/// across all SAGANA accounts (checked live, enforced by the database). The
/// Officer ID (OFF-YYYY-NNN) is issued by the database when the account is
/// created. There are no per-officer permissions — an Officer gets every
/// Manager module except the Members tab.
class CreateOfficerAccountScreen extends StatefulWidget {
  const CreateOfficerAccountScreen({super.key});

  @override
  State<CreateOfficerAccountScreen> createState() =>
      _CreateOfficerAccountScreenState();
}

class _CreateOfficerAccountScreenState
    extends State<CreateOfficerAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _surnameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _middleInitialCtrl = TextEditingController();
  String? _suffix; // Jr., Sr., II, III, IV or V; null = none
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _repo = AccountManagementRepository();

  bool _isSaving = false;
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySub;
  bool _obscurePassword = true;
  DateTime? _dateOfBirth;
  String? _gender;

  // Username availability, reported by UsernameAvailabilityField.
  UsernameStatus? _usernameStatus;
  bool _usernameChecking = false;

  Map<String, String> _genderOptions(AppLocalizations l10n) => {
        'male': l10n.registerGenderMale,
        'female': l10n.registerGenderFemale,
        'prefer_not_to_say': l10n.registerGenderPreferNotToSay,
      };

  // Temporary password — either auto-generated (AUTO button, from the secure
  // random source) or typed by the Manager, matching Create Farmer Account.
  void _generatePassword() {
    setState(() {
      _passwordCtrl.text = generateTemporaryPassword();
      _obscurePassword = false;
    });
  }

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _surnameCtrl.dispose();
    _firstNameCtrl.dispose();
    _middleInitialCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _positionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    // The username must be confirmed free. A check that could not run
    // (UsernameStatus.error) is not a verdict: the database decides.
    if (_usernameChecking || _usernameStatus == null) {
      _toast(l10n.registerCheckingUsername);
      return;
    }
    if (_usernameStatus == UsernameStatus.taken) {
      _toast(l10n.registerUsernameTaken);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _repo.createOfficerAccount(
        username: normalizeUsername(_usernameCtrl.text),
        password: _passwordCtrl.text,
        surname: _surnameCtrl.text,
        firstName: _firstNameCtrl.text,
        middleInitial: _middleInitialCtrl.text,
        suffix: _suffix,
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim().isEmpty
            ? null
            : _phoneCtrl.text.trim(),
        position: _positionCtrl.text.trim().isEmpty
            ? null
            : _positionCtrl.text.trim(),
        dateOfBirth: _dateOfBirth,
        gender: _gender,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.createOfficerCreated,
            style: GoogleFonts.inter(fontSize: 13),
          ),
        backgroundColor: AppConstants.midGreen,
        ),
      );
      context.pop(true);
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      if (!mounted) return;
      _toast(message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
      content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: AppConstants.charcoal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      body: Column(
        children: [
          SubPageTopBar(title: l10n.createOfficerTitle, onBack: () => context.pop()),
          Expanded(child: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  // ── Manager notice ──────────────────────────────────────
                  ManagerNoticeCard(
                    title: l10n.addMemberAdminNoticeTitle,
                    body: l10n.createOfficerNotice,
                  ),
                  const SizedBox(height: 20),

                  // ── Account Credentials ─────────────────────────────────
                  AccountFormSection(
                    icon: Icons.lock_person_rounded,
                    title: l10n.addMemberSectionCredentials,
                    cs: cs,
                    sagana: sagana,
                    children: [
                      AccountFieldLabel(label: l10n.createOfficerUsernameLabel, cs: cs),
                      UsernameAvailabilityField(
                        controller: _usernameCtrl,
                        decorationBuilder: (suffix) => InputDecoration(
                          hintText: l10n.registerUsernameHint,
                          suffixIcon: suffix,
                        ),
                        onStatusChanged: (status, checking) {
                          if (!mounted) return;
                          setState(() {
                            _usernameStatus = status;
                            _usernameChecking = checking;
                          });
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 4),
                        child: Text(
                          l10n.createOfficerUsernameHelp,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      AccountFieldLabel(label: l10n.createOfficerPasswordLabel, cs: cs),
                      TemporaryPasswordField(
                        controller: _passwordCtrl,
                        obscure: _obscurePassword,
                        onToggleObscure: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        onGenerate: _generatePassword,
                        requiredMessage: l10n.addMemberPasswordRequired,
                        tooShortMessage: l10n.createOfficerPasswordTooShort,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Personal Information ────────────────────────────────
                  AccountFormSection(
                    icon: Icons.person_rounded,
                    title: l10n.addMemberSectionPersonal,
                    cs: cs,
                    sagana: sagana,
                    children: [
                      PersonNameFields(
                        style: PersonNameFieldsStyle.form,
                        surnameController: _surnameCtrl,
                        firstNameController: _firstNameCtrl,
                        middleInitialController: _middleInitialCtrl,
                        suffix: _suffix,
                        onSuffixChanged: (v) => setState(() => _suffix = v),
                      ),
                      const SizedBox(height: 14),
                      // Email above Phone (every account form).
                      AccountFieldLabel(label: l10n.createOfficerEmailLabel, cs: cs),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          hintText: 'name@example.com',
                        ),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return null;
                          if (!isValidEmailFormat(t)) {
                            return l10n.addMemberEmailInvalid;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      AccountFieldLabel(label: l10n.createOfficerPhoneLabel, cs: cs),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: '09XX XXX XXXX',
                        ),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return null;
                          if (normalizePhilippineMobile(t) == null) {
                            return l10n.addMemberPhoneInvalid;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      // Date of birth and gender are required, as on Create Farmer.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AccountFieldLabel(
                                  label: '${l10n.addMemberDobLabel} *',
                                  cs: cs,
                                ),
                                AccountDateOfBirthField(
                                  value: _dateOfBirth,
                                  onChanged: (d) =>
                                      setState(() => _dateOfBirth = d),
                                  hint: l10n.addMemberSelectHint,
                                  requiredMessage: l10n.addMemberDobRequired,
                                  underAgeMessage: l10n.addMemberAgeRequirement,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AccountFieldLabel(
                                  label: '${l10n.addMemberGenderLabel} *',
                                  cs: cs,
                                ),
                                AccountGenderField(
                                  value: _gender,
                                  options: _genderOptions(l10n),
                                  onChanged: (v) => setState(() => _gender = v),
                                  hint: l10n.addMemberSelectHint,
                                  requiredMessage: l10n.addMemberGenderRequired,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Officer ─────────────────────────────────────────────
                  AccountFormSection(
                    icon: Icons.badge_rounded,
                    title: l10n.createOfficerSectionOfficer,
                    cs: cs,
                    sagana: sagana,
                    children: [
                      AccountFieldLabel(label: l10n.createOfficerPositionLabel, cs: cs),
                      TextFormField(
                        controller: _positionCtrl,
                        decoration: InputDecoration(
                          hintText: l10n.createOfficerPositionHint,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: PrimaryButton(
            label: !_isOnline
                ? l10n.addMemberOffline
                : (_isSaving
                    ? l10n.createOfficerCreating
                    : l10n.createOfficerCreateButton),
            isLoading: _isSaving,
            onPressed: (!_isOnline || _isSaving) ? null : _submit,
            icon: Icons.person_add_alt_1_rounded,
          ),
        ),
      ),
    );
  }
}
