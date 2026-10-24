import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/shared_widgets.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/farmer_registration_address.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/utils/input_validation_utils.dart';
import '../../../data/services/auth_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/auth_visuals.dart';
import '../../widgets/fixed_farmer_address_fields.dart';
import '../../widgets/password_requirements.dart';
import '../../widgets/username_availability_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  String _selectedRole = AppConstants.roleFarmer;
  DateTime? _dateOfBirth;
  String?
  _dobError; // shown under the DOB field (InputDecorator is not a FormField)
  String? _gender; // male | female | prefer_not_to_say

  // Farmer registration wizard. 0 = Personal Information, 1 = Address
  // Information (fixed area + street / building / house no.), 2 = Review and
  // Confirm. A Buyer registers on a single form.
  int _farmerStep = 0;
  final _streetCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _houseNoCtrl = TextEditingController();

  Map<String, String> _genderOptions(AppLocalizations l10n) => {
    'male': l10n.registerGenderMale,
    'female': l10n.registerGenderFemale,
    'prefer_not_to_say': l10n.registerGenderPreferNotToSay,
  };

  // Username availability, reported by UsernameAvailabilityField.
  UsernameStatus? _usernameStatus;
  bool _usernameChecking = false;

  // Email availability state (optional field)
  Timer? _emailDebounce;
  bool _isCheckingEmail = false;
  bool? _emailAvailable;
  // Whether the email's domain can receive mail (format-valid addresses only).
  // This is not proof that the mailbox exists or belongs to the person.
  EmailDomainStatus? _emailDomain;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _error;

  bool get _isFarmer => _selectedRole == AppConstants.roleFarmer;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
  }

  @override
  void dispose() {
    _emailDebounce?.cancel();
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _streetCtrl.dispose();
    _buildingCtrl.dispose();
    _houseNoCtrl.dispose();
    super.dispose();
  }

  // ── Email availability — debounced, optional field ───────────────────────────

  void _onEmailChanged(String value) {
    setState(() {
      _emailAvailable = null;
      _emailDomain = null;
    });
    final trimmed = value.trim();
    if (trimmed.isEmpty || !isValidEmailFormat(trimmed)) return;

    _emailDebounce?.cancel();
    _emailDebounce = Timer(const Duration(milliseconds: 700), () {
      _checkEmail(trimmed);
    });
  }

  Future<void> _checkEmail(String email) async {
    if (!mounted) return;
    setState(() => _isCheckingEmail = true);
    final results = await Future.wait<Object>([
      AuthService.isEmailAvailable(email),
      AuthService.checkEmailDomain(email),
    ]);
    // Ignore the answer if the field changed while the checks ran.
    if (!mounted || _emailCtrl.text.trim() != email) return;
    setState(() {
      _emailAvailable = results[0] as bool;
      _emailDomain = results[1] as EmailDomainStatus;
      _isCheckingEmail = false;
    });
  }

  // ── Role switch ───────────────────────────────────────────────────────────────

  void _onRoleChanged(String role) {
    if (role == _selectedRole) return;

    // Cancel pending checks first so a late result cannot fill the new form.
    _emailDebounce?.cancel();

    _fullNameCtrl.clear();
    _usernameCtrl.clear();
    _phoneCtrl.clear();
    _emailCtrl.clear();
    _passwordCtrl.clear();
    _confirmPasswordCtrl.clear();
    _streetCtrl.clear();
    _buildingCtrl.clear();
    _houseNoCtrl.clear();

    setState(() {
      _selectedRole = role;
      _dateOfBirth = null;
      _gender = null;
      _obscurePassword = true;
      _obscureConfirm = true;
      _error = null;
      _usernameStatus = null;
      _usernameChecking = false;
      _emailAvailable = null;
      _emailDomain = null;
      _isCheckingEmail = false;
      _dobError = null;
      _farmerStep = 0;
    });
  }

  /// Email and Phone fields, both optional, Email first.
  List<Widget> _buildContactFields(AppLocalizations l10n, ColorScheme cs) {
    final phoneField = TextFormField(
      controller: _phoneCtrl,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      decoration: authFieldDecoration(
        label: l10n.registerPhoneLabel,
        hint: '09XXXXXXXXX',
        icon: Icons.phone_outlined,
      ),
      validator: (v) {
        final t = v?.trim() ?? '';
        if (t.isEmpty) return null; // optional
        if (normalizePhilippineMobile(t) == null) {
          return l10n.registerInvalidPhone;
        }
        return null;
      },
    );

    final emailField = TextFormField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      onChanged: _onEmailChanged,
      decoration: authFieldDecoration(
        label: l10n.registerEmailLabel,
        hint: 'name@example.com',
        icon: Icons.email_outlined,
        suffix: _isCheckingEmail
            ? Padding(
                padding: const EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
              )
            : _emailAvailable == null
            ? null
            : Icon(
                _emailAvailable!
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: _emailAvailable!
                    ? AppConstants.successGreen
                    : AppConstants.errorRed,
              ),
      ),
      validator: (v) {
        final t = v?.trim() ?? '';
        if (t.isEmpty) return null; // optional
        if (!isValidEmailFormat(t)) {
          return l10n.registerInvalidEmail;
        }
        if (_emailAvailable == false) {
          return l10n.registerEmailTaken;
        }
        if (_emailDomain == EmailDomainStatus.noMailServer) {
          return l10n.registerEmailDomainInvalid;
        }
        return null;
      },
    );

    // Email above Phone on every account form.
    return [
      emailField,
      const SizedBox(height: 12),
      phoneField,
      const SizedBox(height: 12),
    ];
  }

  // ── Submit ────────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _error = l10n.registerFixHighlightedFields);
      return;
    }

    final personalError = _personalStepError(l10n);
    if (personalError != null) {
      setState(() {
        _error = personalError;
        _dobError = _dateOfBirth == null && _isFarmer
            ? l10n.registerFieldRequired
            : null;
        if (_isFarmer) _farmerStep = 0;
      });
      return;
    }

    if (_isFarmer && !_isAddressComplete) {
      setState(() {
        _farmerStep = 1;
        _error = l10n.registerFieldRequired;
      });
      return;
    }

    final username = normalizeUsername(_usernameCtrl.text);
    final emailInput = _emailCtrl.text.trim();
    final phoneInput = _phoneCtrl.text.trim();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await AuthService.register(
        username: username,
        password: _passwordCtrl.text,
        fullName: _fullNameCtrl.text.trim(),
        phoneNumber: phoneInput.isEmpty ? null : phoneInput,
        contactEmail: emailInput.isEmpty ? null : emailInput,
        role: _selectedRole,
        dateOfBirth: _isFarmer ? _dateOfBirth : null,
        gender: _isFarmer ? _gender : null,
        street: _isFarmer ? _streetCtrl.text.trim() : null,
        building: _isFarmer ? _buildingCtrl.text.trim() : null,
        houseNo: _isFarmer ? _houseNoCtrl.text.trim() : null,
      );

      if (!mounted) return;

      final msg = _isFarmer
          ? l10n.registerFarmerCreatedMessage(username)
          : l10n.registerBuyerCreatedMessage(username);

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text(
            l10n.registerAccountCreatedTitle,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          content: Text(
            msg,
            style: GoogleFonts.inter(fontSize: 13, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.go(AppRoutes.login);
              },
              child: Text(l10n.registerGoToLogin),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() {
        _error = e is RegistrationNotCancelledException
            ? l10n.registerRollbackFailed
            : AuthService.parseAuthError(e);
        _isLoading = false;
      });
    }
  }

  // ── Farmer wizard ───────────────────────────────────────────────────────────

  /// First error on the Personal Information step, or null when it passes.
  String? _personalStepError(AppLocalizations l10n) {
    // The username is required for every account, and must be free. A check
    // that could not run (UsernameStatus.error) is not a verdict: the database
    // decides when the account is created.
    if (_usernameChecking || _usernameStatus == null) {
      return l10n.registerCheckingUsername;
    }
    if (_usernameStatus == UsernameStatus.taken) {
      return l10n.registerUsernameTaken;
    }
    if (_usernameStatus == UsernameStatus.invalid) {
      return l10n.registerUsernameInvalid;
    }
    // Email is optional, but if provided it must be well-formed and free.
    final emailInput = _emailCtrl.text.trim();
    if (emailInput.isNotEmpty) {
      if (!isValidEmailFormat(emailInput)) return l10n.registerInvalidEmail;
      if (_emailAvailable == false) return l10n.registerEmailTaken;
      if (_emailDomain == EmailDomainStatus.noMailServer) {
        return l10n.registerEmailDomainInvalid;
      }
    }
    if (_isFarmer && (_dateOfBirth == null || _gender == null)) {
      return l10n.registerFieldRequired;
    }
    return null;
  }

  bool get _isAddressComplete =>
      _streetCtrl.text.trim().isNotEmpty && _houseNoCtrl.text.trim().isNotEmpty;

  /// Single-line address shown on the review step.
  String _composeAddressLine() => FarmerRegistrationAddress.composeLine(
    houseNo: _houseNoCtrl.text,
    building: _buildingCtrl.text,
    street: _streetCtrl.text,
  );

  /// Step 1 "Next" for a Farmer.
  void _onFarmerNext() {
    final l10n = AppLocalizations.of(context);
    final formOk = _formKey.currentState?.validate() ?? false;
    setState(() {
      _dobError = _dateOfBirth == null ? l10n.registerFieldRequired : null;
    });
    // Empty or invalid fields: say so.
    if (!formOk || _dateOfBirth == null) {
      setState(() => _error = l10n.registerFixHighlightedFields);
      return;
    }
    final personalError = _personalStepError(l10n);
    setState(() => _error = personalError);
    if (personalError != null) return;
    setState(() {
      _farmerStep = 1;
      _error = null;
    });
  }

  void _onAddressNext() {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false) || !_isAddressComplete) {
      setState(() => _error = l10n.registerFixHighlightedFields);
      return;
    }
    setState(() {
      _farmerStep = 2;
      _error = null;
    });
  }

  /// Whatever the primary button does at the current step.
  void _onPrimaryPressed() {
    if (_isFarmer && _farmerStep == 0) {
      _onFarmerNext();
    } else if (_isFarmer && _farmerStep == 1) {
      _onAddressNext();
    } else {
      _submit();
    }
  }

  void _onBack() {
    if (_isFarmer && _farmerStep > 0) {
      setState(() {
        _farmerStep--;
        _error = null;
      });
      return;
    }
    context.pop();
  }

  /// Warning-style alert for an under-18 date of birth. Matches the other
  /// warning dialogs in the app: AlertDialog with a warning icon in the
  /// content and a single dismiss button.
  Future<void> _showAgeRequirementDialog() {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppConstants.warningAmber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 30,
                color: AppConstants.warningAmber,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.dobUnder18Title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppConstants.primaryGreen,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.registerUnder18Message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.6,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                l10n.cropMgmtOk,
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
          l10n.registerStepIndicator(_farmerStep + 1, titles.length),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppConstants.primaryGreen,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          titles[_farmerStep],
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
            value: (_farmerStep + 1) / titles.length,
            minHeight: 4,
            backgroundColor: AppConstants.primaryGreen.withValues(alpha: 0.12),
            color: AppConstants.primaryGreen,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildReviewStep(AppLocalizations l10n, ColorScheme cs) {
    final notProvided = l10n.registerReviewNotProvided;
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final dob = _dateOfBirth;
    final gender = _gender == null ? null : _genderOptions(l10n)[_gender];
    final username = normalizeUsername(_usernameCtrl.text);

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
            _farmerStep = stepTarget;
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

    return [
      header(l10n.registerStepPersonal, 0),
      row(l10n.fullName, _fullNameCtrl.text.trim()),
      row(l10n.registerUsernameLabel.replaceAll(' *', ''), username),
      row(l10n.emailAddress, email.isEmpty ? notProvided : email),
      row(l10n.phoneNumber, phone.isEmpty ? notProvided : phone),
      row(l10n.addMemberDobLabel, dob == null ? notProvided : _formatDate(dob)),
      row(l10n.registerGenderLabel, gender ?? notProvided),
      const SizedBox(height: 6),
      header(l10n.registerStepAddress, 1),
      row(l10n.registerAddressReviewLabel, _composeAddressLine()),
      const SizedBox(height: 12),
    ];
  }

  Widget _buildFooter(AppLocalizations l10n) {
    final isNext = _isFarmer && _farmerStep < 2;
    final label = isNext
        ? l10n.registerNext
        : (_isFarmer ? l10n.registerCreateAccount : l10n.registerTitle);
    final primary = AuthGradientButton(
      label: label,
      isLoading: _isLoading,
      onPressed: _onPrimaryPressed,
      gradientColors: const [Color(0xFF43A047), AppConstants.primaryGreen],
      glowColor: AppConstants.primaryGreen,
    );
    if (!(_isFarmer && _farmerStep > 0)) return primary;
    // Both buttons span the full width, so each label is centred and fits on
    // one line at every screen size.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        primary,
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _isLoading ? null : _onBack,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
          ),
          child: Text(
            l10n.registerBack,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// Step 1 (Personal Information) fields. Kept mounted but hidden on the
  /// address and review steps, so the username keeps its availability result.
  Widget _buildPersonalFields(AppLocalizations l10n, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Full Name — an ordinary text field. It is not searched anywhere and
        // does not have to be unique.
        TextFormField(
          controller: _fullNameCtrl,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: authFieldDecoration(
            label: '${l10n.fullName} *',
            hint: _isFarmer
                ? l10n.registerFullNameHintFarmer
                : l10n.registerFullNameHintBuyer,
            icon: Icons.person_outlined,
          ),
          validator: (v) =>
              (v == null || v.trim().length < 2)
              ? l10n.registerEnterFullName
              : null,
        ),
        const SizedBox(height: 12),

        // Username — always shown, always required, unique across all accounts.
        UsernameAvailabilityField(
          key: ValueKey('username-$_selectedRole'),
          controller: _usernameCtrl,
          decorationBuilder: (suffix) => authFieldDecoration(
            label: l10n.registerUsernameLabel,
            hint: l10n.registerUsernameHint,
            icon: Icons.badge_outlined,
            suffix: suffix,
          ),
          onStatusChanged: (status, checking) {
            if (!mounted) return;
            setState(() {
              _usernameStatus = status;
              _usernameChecking = checking;
            });
          },
        ),
        const SizedBox(height: 12),

        // Email and Phone — both optional.
        ..._buildContactFields(l10n, cs),

        // Date of Birth and Gender — farmers only, both required.
        if (_isFarmer) ...[
          // The picker allows any real date; the 18+ cooperative-membership
          // rule is enforced afterward via a warning dialog (and again by the
          // database when the account is created).
          InkWell(
            onTap: () async {
              final picked = await AppUtils.pickDateOfBirth(
                context,
                initialDate: _dateOfBirth,
                helpText: l10n.registerDobHelp,
              );
              if (picked == null) return;
              if (!AppUtils.isAtLeast18(picked)) {
                if (!mounted) return;
                await _showAgeRequirementDialog();
                return;
              }
              setState(() {
                _dateOfBirth = picked;
                _dobError = null;
              });
            },
            child: InputDecorator(
              // errorText gives the same red border and message as the other
              // required fields.
              decoration: authFieldDecoration(
                label: l10n.registerDob,
                icon: Icons.cake_outlined,
              ).copyWith(errorText: _dobError),
              child: Text(
                _dateOfBirth == null
                    ? l10n.registerDobSelect
                    : _formatDate(_dateOfBirth!),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: _dateOfBirth == null
                      ? cs.onSurfaceVariant
                      : cs.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Gender — farmers only, required
          AppDropdownField<String>(
            value: _gender,
            hintText: l10n.addMemberSelectHint,
            labelText: '${l10n.registerGenderLabel} *',
            items: _genderOptions(l10n).keys.toList(),
            itemLabel: (key) => _genderOptions(l10n)[key]!,
            validator: (v) => v == null ? l10n.registerFieldRequired : null,
            onChanged: (v) => setState(() => _gender = v),
          ),
          const SizedBox(height: 12),
        ],

        // Password
        TextFormField(
          controller: _passwordCtrl,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.next,
          decoration: authFieldDecoration(
            label: l10n.registerPasswordLabel,
            icon: Icons.lock_outline_rounded,
            suffix: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          validator: (v) => validatePasswordMinLength(v, l10n),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _passwordCtrl,
          builder: (_, value, __) =>
              PasswordLengthHint(password: value.text),
        ),
        const SizedBox(height: 12),

        // Confirm password
        TextFormField(
          controller: _confirmPasswordCtrl,
          obscureText: _obscureConfirm,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _onPrimaryPressed(),
          decoration: authFieldDecoration(
            label: l10n.registerConfirmPasswordLabel,
            icon: Icons.lock_outline_rounded,
            suffix: IconButton(
              icon: Icon(
                _obscureConfirm
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          validator: (v) =>
              v != _passwordCtrl.text ? l10n.registerPasswordMismatch : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: Stack(
        children: [
          const AuthBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const OfflineStatusCard(),
                  // Back
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: _onBack,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.70),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: cs.onSurface,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppConstants.primaryGreen.withValues(
                              alpha: 0.10,
                            ),
                            border: Border.all(
                              color: AppConstants.primaryGreen.withValues(
                                alpha: 0.18,
                              ),
                            ),
                          ),
                          child: const Icon(
                            Icons.person_add_alt_1_rounded,
                            color: AppConstants.primaryGreen,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          l10n.registerTitle,
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.registerSubtitle,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  AuthGlassCard(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Role selector
                          _RoleSelector(
                            selectedRole: _selectedRole,
                            onChanged: _onRoleChanged,
                          ),
                          const SizedBox(height: 20),

                          if (_isFarmer) ...[
                            _buildStepper(l10n, cs),
                            const SizedBox(height: 20),
                          ],

                          // Step 1 (Personal Information). Hidden — not
                          // removed — on the address and review steps.
                          Visibility(
                            visible: !_isFarmer || _farmerStep == 0,
                            maintainState: true,
                            child: _buildPersonalFields(l10n, cs),
                          ),

                          if (_isFarmer && _farmerStep == 1)
                            FixedFarmerAddressFields(
                              streetController: _streetCtrl,
                              buildingController: _buildingCtrl,
                              houseNoController: _houseNoCtrl,
                            ),
                          if (_isFarmer && _farmerStep == 2)
                            ..._buildReviewStep(l10n, cs),

                          // Error
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.errorContainer.withValues(
                                  alpha: 0.50,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppConstants.radiusMd,
                                ),
                              ),
                              child: Text(
                                _error!,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: cs.error,
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),

                          // Next / Back / Create Account, by step
                          _buildFooter(l10n),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        l10n.registerAlreadyHaveAccount,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.go(AppRoutes.login),
                        child: Text(
                          l10n.registerSignIn,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Role Selector
// ─────────────────────────────────────────────────────────────────────────────

class _RoleSelector extends StatelessWidget {
  final String selectedRole;
  final void Function(String) onChanged;

  const _RoleSelector({required this.selectedRole, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        _RoleChip(
          label: l10n.registerRoleFarmer,
          icon: Icons.agriculture_rounded,
          isSelected: selectedRole == AppConstants.roleFarmer,
          onTap: () => onChanged(AppConstants.roleFarmer),
          cs: cs,
          sagana: sagana,
        ),
        const SizedBox(width: 10),
        _RoleChip(
          label: l10n.registerRoleBuyer,
          icon: Icons.shopping_bag_outlined,
          isSelected: selectedRole == AppConstants.roleBuyer,
          onTap: () => onChanged(AppConstants.roleBuyer),
          cs: cs,
          sagana: sagana,
        ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _RoleChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? cs.primary.withValues(alpha: 0.10)
                : sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: isSelected
                  ? cs.primary
                  : cs.outline.withValues(alpha: 0.20),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
