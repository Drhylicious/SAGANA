import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/farmer_registration_address.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/utils/input_validation_utils.dart';
import '../../../core/utils/person_name.dart';
import '../../../core/utils/temp_password.dart';
import '../../../data/repositories/add_member_repository.dart';
import '../../../data/services/auth_service.dart' show UsernameStatus;
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/hive_service.dart';
import '../../widgets/account_form_widgets.dart';
import '../../widgets/fixed_farmer_address_fields.dart';
import '../../widgets/officer_approval_notice.dart';
import '../../widgets/person_name_fields.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/username_availability_field.dart';

// Gender labels are shared with the Register screen's translations
// (registerGenderMale/Female/PreferNotToSay) rather than duplicated here.
Map<String, String> _kGenderOptions(AppLocalizations l10n) => {
      'male': l10n.registerGenderMale,
      'female': l10n.registerGenderFemale,
      'prefer_not_to_say': l10n.registerGenderPreferNotToSay,
    };

/// Create Farmer Account (Manager and Officer). The same three steps as the
/// Register screen: Personal Information, Address Information, Summary. The
/// cooperative membership and initial crops are not asked here: every account
/// gets the database defaults, and contributions are added later from Farmer
/// Details.
class AddNewMemberScreen extends StatefulWidget {
  const AddNewMemberScreen({super.key});

  @override
  State<AddNewMemberScreen> createState() => _AddNewMemberScreenState();
}

class _AddNewMemberScreenState extends State<AddNewMemberScreen> {
  static const _stepCount = 3;

  final _repo    = AddMemberRepository();
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ────────────────────────────────────────────────────────────
  final _usernameCtrl      = TextEditingController();
  final _passwordCtrl      = TextEditingController();
  final _surnameCtrl       = TextEditingController();
  final _firstNameCtrl     = TextEditingController();
  final _middleInitialCtrl = TextEditingController();
  String? _suffix; // Jr., Sr., II, III, IV or V; null = none
  final _emailCtrl    = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _streetCtrl   = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _houseNoCtrl  = TextEditingController();

  // ── Form state ─────────────────────────────────────────────────────────────
  int _step = 0; // 0 Personal, 1 Address, 2 Summary
  DateTime? _dateOfBirth;
  String? _gender; // key of _kGenderOptions
  bool    _obscurePassword = true;
  String? _error;

  // Username availability, reported by UsernameAvailabilityField.
  UsernameStatus? _usernameStatus;
  bool _usernameChecking = false;

  bool _isSaving  = false;
  bool _isOnline  = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _surnameCtrl.dispose();
    _firstNameCtrl.dispose();
    _middleInitialCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _streetCtrl.dispose();
    _buildingCtrl.dispose();
    _houseNoCtrl.dispose();
    super.dispose();
  }

  // ── Password generation ─────────────────────────────────────────────────────

  void _generatePassword() {
    setState(() {
      _passwordCtrl.text = generateTemporaryPassword();
      _obscurePassword   = false;
    });
  }

  // ── Steps ──────────────────────────────────────────────────────────────────

  bool get _isAddressComplete =>
      _streetCtrl.text.trim().isNotEmpty && _houseNoCtrl.text.trim().isNotEmpty;

  /// First error on the Personal Information step, or null when it passes.
  String? _personalStepError(AppLocalizations l10n) {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return l10n.registerFixHighlightedFields;
    }
    final dob = _dateOfBirth;
    if (dob == null || _gender == null) return l10n.registerFixHighlightedFields;
    if (!AppUtils.isAtLeast18(dob)) return l10n.addMemberAgeRequirement;
    // The username must be confirmed free. A check that could not run
    // (UsernameStatus.error) is not a verdict: the database decides.
    if (_usernameChecking || _usernameStatus == null) {
      return l10n.registerCheckingUsername;
    }
    if (_usernameStatus == UsernameStatus.taken) return l10n.registerUsernameTaken;
    return null;
  }

  void _onNext() {
    final l10n = AppLocalizations.of(context);
    if (_step == 0) {
      final error = _personalStepError(l10n);
      setState(() => _error = error);
      if (error == null) setState(() => _step = 1);
      return;
    }
    // Step 1: the address.
    if (!(_formKey.currentState?.validate() ?? false) || !_isAddressComplete) {
      setState(() => _error = l10n.registerFixHighlightedFields);
      return;
    }
    setState(() {
      _step = 2;
      _error = null;
    });
  }

  void _onBack() {
    if (_step > 0) {
      setState(() {
        _step--;
        _error = null;
      });
      return;
    }
    context.pop();
  }

  String _fullName() => PersonName.compose(
        firstName: _firstNameCtrl.text,
        middleInitial: _middleInitialCtrl.text,
        surname: _surnameCtrl.text,
        suffix: _suffix,
      );

  String _addressLine() => FarmerRegistrationAddress.composeLine(
        houseNo: _houseNoCtrl.text,
        building: _buildingCtrl.text,
        street: _streetCtrl.text,
      );

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    // Everything was checked step by step; check again in case a field changed.
    final personalError = _personalStepError(l10n);
    if (personalError != null) {
      setState(() {
        _error = personalError;
        _step = 0;
      });
      return;
    }
    if (!_isAddressComplete) {
      setState(() {
        _error = l10n.registerFieldRequired;
        _step = 1;
      });
      return;
    }

    // An Officer's new account goes to the Manager for approval first.
    if (!await confirmOfficerSubmission(context)) return;
    if (!mounted) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final username = normalizeUsername(_usernameCtrl.text);
    final result = await _repo.createMember(
      username:      username,
      password:      _passwordCtrl.text.trim(),
      surname:       _surnameCtrl.text,
      firstName:     _firstNameCtrl.text,
      middleInitial: _middleInitialCtrl.text,
      suffix:        _suffix,
      phoneNumber:   _phoneCtrl.text.trim(),
      contactEmail:  _emailCtrl.text.trim(),
      dateOfBirth:   _dateOfBirth,
      gender:        _gender,
      street:        _streetCtrl.text.trim(),
      building:      _buildingCtrl.text.trim(),
      houseNo:       _houseNoCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.isSuccess) {
      await _showCreatedDialog(username);
      if (mounted) context.pop(true);
    } else if (result.isPartial) {
      setState(() => _error = l10n.addMemberPartialIssue(
            result.failedStep ?? '',
            result.message ?? '',
          ));
      // Member account exists — still pop back so the staff member sees them.
      context.pop(true);
    } else {
      final msg = result.message ?? l10n.addMemberCreateFailed;
      if (msg.toLowerCase().contains('username') &&
          msg.toLowerCase().contains('already taken')) {
        // Someone took the username between the availability check and Save.
        setState(() {
          _error = l10n.addMemberUsernameTakenRetry;
          _step = 0;
        });
      } else {
        setState(() => _error = msg);
      }
    }
  }

  /// The same "Account Created" dialog the Register screen shows, with the
  /// username. The password is never shown here.
  Future<void> _showCreatedDialog(String username) {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.registerAccountCreatedTitle,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          '${l10n.addMemberCreatedDialogBody(username)}\n\n'
          '${HiveService.isOfficer ? l10n.addMemberCreatedOfficerNote : l10n.addMemberCreatedManagerNote}',
          style: GoogleFonts.inter(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.addMemberClose),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  Widget _buildStepper(AppLocalizations l10n, ColorScheme cs) {
    final titles = [
      l10n.registerStepPersonal,
      l10n.registerStepAddress,
      l10n.registerStepReview,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.registerStepIndicator(_step + 1, titles.length),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppConstants.primaryGreen,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          titles[_step],
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / titles.length,
            minHeight: 4,
            backgroundColor: AppConstants.primaryGreen.withValues(alpha: 0.12),
            color: AppConstants.primaryGreen,
          ),
        ),
      ],
    );
  }

  /// Step 1: sign-in details and personal information.
  Widget _personalFields(AppLocalizations l10n, ColorScheme cs, SaganaColors sagana) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ManagerNoticeCard(
          title: l10n.addMemberAdminNoticeTitle,
          body: l10n.addMemberAdminNoticeBody,
        ),
        const SizedBox(height: 20),

        // ── Account Credentials ─────────────────────────────
        AccountFormSection(
          icon: Icons.lock_person_rounded,
          title: l10n.addMemberSectionCredentials,
          cs: cs,
          sagana: sagana,
          children: [
            AccountFieldLabel(label: l10n.addMemberUsernameLabel, cs: cs),
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
                l10n.addMemberUsernameHelp,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 14),
            AccountFieldLabel(label: l10n.addMemberPasswordLabel, cs: cs),
            TemporaryPasswordField(
              controller: _passwordCtrl,
              obscure: _obscurePassword,
              onToggleObscure: () => setState(
                () => _obscurePassword = !_obscurePassword,
              ),
              onGenerate: _generatePassword,
              requiredMessage: l10n.addMemberPasswordRequired,
              tooShortMessage: l10n.addMemberPasswordTooShort,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Personal Information ─────────────────────────────
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AccountFieldLabel(label: l10n.addMemberEmailLabel, cs: cs),
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
              ],
            ),
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AccountFieldLabel(label: l10n.addMemberPhoneLabel, cs: cs),
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
              ],
            ),
            const SizedBox(height: 14),
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
                        onChanged: (d) => setState(() => _dateOfBirth = d),
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
                        options: _kGenderOptions(l10n),
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
      ],
    );
  }

  /// Step 3: what will be created. The password is not shown.
  List<Widget> _summary(AppLocalizations l10n, ColorScheme cs) {
    final notProvided = l10n.registerReviewNotProvided;
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final dob = _dateOfBirth;
    final gender = _gender == null ? null : _kGenderOptions(l10n)[_gender];

    Widget header(String title, int stepTarget) => Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _step = stepTarget;
                _error = null;
              }),
              child: Text(l10n.registerEdit),
            ),
          ],
        );

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
              ),
            ],
          ),
        );

    String date(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    return [
      header(l10n.registerStepPersonal, 0),
      row(l10n.fullName, _fullName()),
      row(l10n.registerUsernameLabel.replaceAll(' *', ''),
          normalizeUsername(_usernameCtrl.text)),
      row(l10n.emailAddress, email.isEmpty ? notProvided : email),
      row(l10n.phoneNumber, phone.isEmpty ? notProvided : phone),
      row(l10n.addMemberDobLabel, dob == null ? notProvided : date(dob)),
      row(l10n.registerGenderLabel, gender ?? notProvided),
      const SizedBox(height: 6),
      header(l10n.registerStepAddress, 1),
      row(l10n.registerAddressReviewLabel, _addressLine()),
      const SizedBox(height: 12),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;
    final l10n   = AppLocalizations.of(context);
    final last   = _step == _stepCount - 1;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(title: l10n.addMemberTitle, onBack: _onBack),
          Expanded(
            child: SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    _buildStepper(l10n, cs),
                    const SizedBox(height: 20),

                    // Step 1 stays mounted (hidden) on the later steps, as on
                    // the Register screen, so what was typed is kept.
                    Visibility(
                      visible: _step == 0,
                      maintainState: true,
                      child: _personalFields(l10n, cs, sagana),
                    ),
                    if (_step == 1)
                      FixedFarmerAddressFields(
                        streetController: _streetCtrl,
                        buildingController: _buildingCtrl,
                        houseNoController: _houseNoCtrl,
                      ),
                    if (last) ..._summary(l10n, cs),

                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withValues(alpha: 0.50),
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMd),
                        ),
                        child: Text(
                          _error!,
                          style: GoogleFonts.inter(fontSize: 13, color: cs.error),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PrimaryButton(
                label: last
                    ? (!_isOnline
                        ? l10n.addMemberOffline
                        : (_isSaving
                            ? l10n.addMemberCreating
                            : l10n.addMemberCreateButton))
                    : l10n.registerNext,
                isLoading: _isSaving,
                onPressed: last
                    ? ((!_isOnline || _isSaving) ? null : _save)
                    : _onNext,
                icon: last ? Icons.person_add_alt_1_rounded : null,
              ),
              if (_step > 0) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _isSaving ? null : _onBack,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: Text(
                    l10n.registerBack,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
