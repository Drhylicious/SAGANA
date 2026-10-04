import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/buyer_address_model.dart';
import '../../../data/models/psgc_models.dart';
import '../../../data/repositories/psgc_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/auth_visuals.dart';
import '../../widgets/password_requirements.dart';

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

  // Farmer registration wizard (Batch 4). 0 = Personal Information,
  // 1 = Address Information (outsiders only), 2 = Review and Confirm.
  int _farmerStep = 0;
  PsgcHierarchy? _psgc;
  bool _isLoadingPsgc = false;
  PsgcRegion? _region;
  PsgcProvince? _province;
  PsgcCity? _city;
  PsgcBarangay? _barangay;
  final _postalCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _houseNoCtrl = TextEditingController();

  Map<String, String> _genderOptions(AppLocalizations l10n) => {
    'male': l10n.registerGenderMale,
    'female': l10n.registerGenderFemale,
    'prefer_not_to_say': l10n.registerGenderPreferNotToSay,
  };

  // Registry check state
  Timer? _debounce;
  bool _isCheckingRegistry = false;
  bool _registryChecked = false;
  bool _isOfficialMember = false;
  // Registry email/phone already belong to another account (Batch 4).
  bool _registryContactInUse = false;
  Sp3RegistryResult? _registryResult;
  String? _assignedUsername;

  // Full-name duplicate check (Issue 3) — runs for BOTH roles.
  // One of: null (unchecked), 'available', 'taken_account', 'taken_registry'.
  String? _fullNameStatus;
  bool _isCheckingFullName = false;

  // Username availability state (for non-members)
  Timer? _usernameDebounce;
  bool _isCheckingUsername = false;
  bool? _usernameAvailable;

  // Email availability state (optional field — Issue 1 / D10)
  Timer? _emailDebounce;
  bool _isCheckingEmail = false;
  bool? _emailAvailable;

  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
  );

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _error;

  bool get _isFarmer => _selectedRole == AppConstants.roleFarmer;

  // Registry-matched Farmer: skips Address and Review, and their email and
  // phone come from the registry (locked).
  bool get _isMatchedMember =>
      _isFarmer && _isOfficialMember && _registryChecked;
  bool get _phoneLocked => _isMatchedMember && (_registryResult?.phone != null);
  bool get _emailLocked => _isMatchedMember && (_registryResult?.email != null);

  // Whether to show the username field — only for non-members
  // and only after the registry check has completed
  bool get _showUsernameField =>
      !_isFarmer || (_registryChecked && !_isOfficialMember);

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    // Listen to full name changes with debounce
    _fullNameCtrl.addListener(_onFullNameChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _usernameDebounce?.cancel();
    _emailDebounce?.cancel();
    _fullNameCtrl.removeListener(_onFullNameChanged);
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _postalCtrl.dispose();
    _streetCtrl.dispose();
    _buildingCtrl.dispose();
    _houseNoCtrl.dispose();
    super.dispose();
  }

  // ── Registry check — debounced, fires 600ms after typing stops ───────────────

  void _onFullNameChanged() {
    final name = _fullNameCtrl.text.trim();

    // Reset any previous result whenever the name changes.
    if (_registryChecked || _isOfficialMember || _fullNameStatus != null) {
      final wasOfficial = _isOfficialMember;
      setState(() {
        _registryChecked = false;
        _isOfficialMember = false;
        _registryResult = null;
        _assignedUsername = null;
        _fullNameStatus = null;
        // Only clear the username field when it held an auto-assigned
        // SP3-XXXX — never discard what an outsider typed themselves.
        if (wasOfficial) _usernameCtrl.clear();
        _usernameAvailable = null;
      });
      // Email and phone were filled from the previous registry match and
      // are locked while it lasts; clear them so they unlock with it.
      if (wasOfficial) {
        _phoneCtrl.clear();
        _emailCtrl.clear();
        _emailAvailable = null;
      }
    }

    // Need at least 3 characters to check.
    if (name.length < 3) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _runNameChecks(name);
    });
  }

  /// Runs the duplicate-name guard first (both roles), then — for farmers
  /// whose name is free — the SP3 registry lookup.
  Future<void> _runNameChecks(String name) async {
    if (!mounted) return;
    final roleAtStart = _selectedRole;
    setState(() => _isCheckingFullName = true);

    final status = await AuthService.checkFullNameAvailability(name);
    // Discard the result if the role was switched while the check ran.
    if (!mounted || _selectedRole != roleAtStart) return;

    if (status == 'taken_account' || status == 'taken_registry') {
      setState(() {
        _fullNameStatus = status;
        _isCheckingFullName = false;
        _registryChecked = false;
        _isOfficialMember = false;
        _registryResult = null;
        _assignedUsername = null;
      });
      return;
    }

    // 'available' or 'error' — allow the flow to continue. On 'error' the
    // server-side insert still enforces uniqueness.
    setState(() {
      _fullNameStatus = 'available';
      _isCheckingFullName = false;
    });

    if (_isFarmer) {
      await _checkRegistry(name);
    }
  }

  Future<void> _checkRegistry(String name) async {
    if (!mounted) return;
    final roleAtStart = _selectedRole;
    setState(() => _isCheckingRegistry = true);

    final result = await AuthService.checkSp3Registry(name);

    // Discard the result if the role was switched while the check ran.
    if (!mounted || _selectedRole != roleAtStart) return;

    if (result != null && result.alreadyRegistered) {
      // Matched a registry row that is already registered — treat as a
      // duplicate, not an outsider.
      setState(() {
        _fullNameStatus = 'taken_registry';
        _isOfficialMember = false;
        _registryResult = null;
        _assignedUsername = null;
        _registryChecked = false;
        _isCheckingRegistry = false;
      });
      return;
    }

    if (result != null) {
      // Matched and available — generate username, auto-fill contact fields.
      final username = await AuthService.suggestNextUsername('SP3');
      if (!mounted || _selectedRole != roleAtStart) return;
      setState(() {
        _isOfficialMember = true;
        _registryResult = result;
        _assignedUsername = username;
        // Fill phone + email from the registry and lock them (Batch 4).
        // Only fields the registry actually supplies are filled and locked;
        // a blank registry value stays editable.
        if (result.phone != null) {
          _phoneCtrl.text = result.phone!;
        }
        if (result.email != null) {
          _emailCtrl.text = result.email!;
          _emailAvailable = null;
        }
        _registryContactInUse = false;
        _registryChecked = true;
        _isCheckingRegistry = false;
      });
      // The registry email/phone are locked, so if either already belongs
      // to another account this match cannot be completed. Flag it now so
      // the user sees why before pressing Create Account.
      final contactTaken = await _registryContactTaken(result);
      if (!mounted || _selectedRole != roleAtStart) return;
      setState(() => _registryContactInUse = contactTaken);
    } else {
      setState(() {
        _isOfficialMember = false;
        _registryResult = null;
        _assignedUsername = null;
        _registryChecked = true;
        _isCheckingRegistry = false;
      });
    }
  }

  /// True when the registry email or phone already belongs to another
  /// account. Fails open (false) if the check cannot run, since the server
  /// still enforces uniqueness on the email.
  Future<bool> _registryContactTaken(Sp3RegistryResult result) async {
    final email = result.email;
    if (email != null && !await AuthService.isEmailAvailable(email)) {
      return true;
    }
    final phone = result.phone;
    if (phone != null && !await AuthService.isPhoneAvailable(phone)) {
      return true;
    }
    return false;
  }

  // ── Email availability — debounced, optional field ───────────────────────────

  void _onEmailChanged(String value) {
    setState(() => _emailAvailable = null);
    final trimmed = value.trim();
    if (trimmed.isEmpty || !_emailRegex.hasMatch(trimmed)) return;

    _emailDebounce?.cancel();
    _emailDebounce = Timer(const Duration(milliseconds: 700), () {
      _checkEmail(trimmed);
    });
  }

  Future<void> _checkEmail(String email) async {
    if (!mounted) return;
    setState(() => _isCheckingEmail = true);
    final available = await AuthService.isEmailAvailable(email);
    if (!mounted) return;
    setState(() {
      _emailAvailable = available;
      _isCheckingEmail = false;
    });
  }

  // ── Username availability — debounced ─────────────────────────────────────────

  void _onUsernameChanged(String value) {
    setState(() => _usernameAvailable = null);
    if (value.trim().length < 3) return;

    _usernameDebounce?.cancel();
    _usernameDebounce = Timer(const Duration(milliseconds: 700), () {
      _checkUsername(value.trim());
    });
  }

  Future<void> _checkUsername(String username) async {
    if (!mounted) return;
    setState(() => _isCheckingUsername = true);
    final available = await AuthService.isUsernameAvailable(username);
    if (!mounted) return;
    setState(() {
      _usernameAvailable = available;
      _isCheckingUsername = false;
    });
  }

  // ── Role switch ───────────────────────────────────────────────────────────────

  void _onRoleChanged(String role) {
    if (role == _selectedRole) return;

    // Cancel pending checks first so a late result cannot fill the new form.
    _debounce?.cancel();
    _usernameDebounce?.cancel();
    _emailDebounce?.cancel();

    // Controllers are cleared outside setState: clearing the name field
    // fires _onFullNameChanged, which calls setState itself.
    _fullNameCtrl.clear();
    _usernameCtrl.clear();
    _phoneCtrl.clear();
    _emailCtrl.clear();
    _passwordCtrl.clear();
    _confirmPasswordCtrl.clear();

    setState(() {
      _selectedRole = role;
      _dateOfBirth = null;
      _gender = null;
      _obscurePassword = true;
      _obscureConfirm = true;
      _error = null;
      _fullNameStatus = null;
      _isCheckingFullName = false;
      _registryChecked = false;
      _isOfficialMember = false;
      _isCheckingRegistry = false;
      _registryResult = null;
      _assignedUsername = null;
      _usernameAvailable = null;
      _isCheckingUsername = false;
      _emailAvailable = null;
      _isCheckingEmail = false;
      _dobError = null;
      _farmerStep = 0;
      _region = null;
      _province = null;
      _city = null;
      _barangay = null;
    });
    _postalCtrl.clear();
    _streetCtrl.clear();
    _buildingCtrl.clear();
    _houseNoCtrl.clear();
  }

  /// Email and Phone fields, both optional, plain labels, Email first.
  List<Widget> _buildContactFields(AppLocalizations l10n, ColorScheme cs) {
    final phoneField = TextFormField(
      controller: _phoneCtrl,
      readOnly: _phoneLocked,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      decoration: authFieldDecoration(
        label: l10n.registerPhoneLabel,
        hint: '09XXXXXXXXX',
        icon: Icons.phone_outlined,
        suffix: _phoneLocked ? _lockSuffix(cs) : null,
      ),
      validator: (v) {
        final t = v?.trim() ?? '';
        if (t.isEmpty) return null; // optional
        if (!RegExp(r'^09\d{9}$').hasMatch(t)) {
          return l10n.registerInvalidPhone;
        }
        return null;
      },
    );

    final emailField = TextFormField(
      controller: _emailCtrl,
      readOnly: _emailLocked,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      onChanged: _onEmailChanged,
      decoration: authFieldDecoration(
        label: l10n.registerEmailLabel,
        hint: 'name@example.com',
        icon: Icons.email_outlined,
        suffix: _emailLocked
            ? _lockSuffix(cs)
            : _isCheckingEmail
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
        if (!_emailRegex.hasMatch(t)) {
          return l10n.registerInvalidEmail;
        }
        if (_emailAvailable == false) {
          return l10n.registerEmailTaken;
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
      });
      return;
    }

    // Outsider Farmers: the address is saved with the account, so it must
    // be complete before anything is created.
    final isOutsiderFarmer = _isFarmer && !_isOfficialMember;
    if (isOutsiderFarmer && !_isAddressComplete) {
      setState(() {
        _farmerStep = 1;
        _error = l10n.registerFieldRequired;
      });
      return;
    }

    final username = _isOfficialMember
        ? _assignedUsername!
        : _usernameCtrl.text.trim();
    final emailInput = _emailCtrl.text.trim();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final phoneInput = _phoneCtrl.text.trim();

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
        registryId: _registryResult?.registryId,
        structuredAddress: isOutsiderFarmer ? _buildAddressStructure() : null,
        addressLine: isOutsiderFarmer ? _composeAddressLine() : null,
      );

      if (!mounted) return;

      final msg = _isOfficialMember
          ? l10n.registerWelcomeOfficialMessage(_assignedUsername ?? '')
          : _isFarmer
          ? l10n.registerFarmerCreatedMessage(_usernameCtrl.text.trim())
          : l10n.registerBuyerCreatedMessage(_usernameCtrl.text.trim());

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text(
            _isOfficialMember
                ? l10n.registerWelcomeOfficialTitle
                : l10n.registerAccountCreatedTitle,
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

  // ── Farmer wizard (Batch 4) ─────────────────────────────────────────────────

  /// First error on the Personal Information step, or null when it passes.
  String? _personalStepError(AppLocalizations l10n) {
    // Duplicate full name — hard block for both roles (Issue 3).
    if (_fullNameStatus == 'taken_account' ||
        _fullNameStatus == 'taken_registry') {
      return l10n.registerNameAlreadyRegistered;
    }
    if (_isCheckingFullName) return l10n.registerCheckingName;
    // The registry lookup starts only after 3 characters, so a shorter name
    // will never be checked and must be lengthened first.
    if (_isFarmer && _fullNameCtrl.text.trim().length < 3) {
      return l10n.registerNameMinChars;
    }
    // Farmers must have completed the registry check.
    if (_isFarmer && (!_registryChecked || _isCheckingRegistry)) {
      return l10n.registerCheckingRegistry;
    }
    // Registry contact already in use: the locked values cannot be used.
    if (_isMatchedMember && _registryContactInUse) {
      return l10n.registerRegistryContactInUse;
    }
    if (!_isOfficialMember && _usernameAvailable != true) {
      return l10n.registerChooseAvailableUsername;
    }
    // Email is optional, but if provided it must be well-formed and free.
    final emailInput = _emailCtrl.text.trim();
    if (emailInput.isNotEmpty) {
      if (!_emailRegex.hasMatch(emailInput)) return l10n.registerInvalidEmail;
      if (_emailAvailable == false) return l10n.registerEmailTaken;
    }
    if (_isFarmer && (_dateOfBirth == null || _gender == null)) {
      return l10n.registerFieldRequired;
    }
    return null;
  }

  bool get _isAddressComplete {
    final region = _region;
    if (region == null || _city == null || _barangay == null) return false;
    if (region.hasProvinces && _province == null) return false;
    return isValidPhilippinePostalCode(_postalCtrl.text) &&
        _streetCtrl.text.trim().isNotEmpty &&
        _houseNoCtrl.text.trim().isNotEmpty;
  }

  /// Structured fields for buyer_addresses. PSGC names and codes are both
  /// stored (confirmed in Batch 3).
  BuyerAddressStructure _buildAddressStructure() {
    final building = _buildingCtrl.text.trim();
    return BuyerAddressStructure(
      regionCode: _region?.code,
      regionName: _region?.name,
      provinceCode: _province?.code,
      provinceName: _province?.name,
      cityMunicipalityCode: _city?.code,
      cityMunicipalityName: _city?.name,
      barangayCode: _barangay?.code,
      barangayName: _barangay?.name,
      postalCode: _postalCtrl.text.trim(),
      street: _streetCtrl.text.trim(),
      building: building.isEmpty ? null : building,
      houseNo: _houseNoCtrl.text.trim(),
    );
  }

  /// Single-line address for buyer_addresses.address_line (NOT NULL).
  String _composeAddressLine() {
    return [
      _houseNoCtrl.text.trim(),
      _buildingCtrl.text.trim(),
      _streetCtrl.text.trim(),
      _barangay?.name,
      _city?.name,
      _province?.name,
      _region?.name,
      _postalCtrl.text.trim(),
    ].whereType<String>().where((p) => p.isNotEmpty).join(', ');
  }

  Widget _lockSuffix(ColorScheme cs) => Padding(
    padding: const EdgeInsets.all(14),
    child: Icon(
      Icons.lock_outline_rounded,
      size: 18,
      color: cs.onSurfaceVariant,
    ),
  );

  /// Step 1 "Next" for a Farmer. A registry match skips the address steps
  /// and creates the account directly.
  Future<void> _onFarmerNext() async {
    final l10n = AppLocalizations.of(context);
    final formOk = _formKey.currentState?.validate() ?? false;
    setState(() {
      _dobError = _dateOfBirth == null ? l10n.registerFieldRequired : null;
    });
    // Empty or invalid fields: say so, rather than describing a registry
    // check that has not started.
    if (!formOk || _dateOfBirth == null) {
      setState(() => _error = l10n.registerFixHighlightedFields);
      return;
    }
    final personalError = _personalStepError(l10n);
    setState(() => _error = personalError);
    if (personalError != null) return;
    if (_isMatchedMember) {
      await _submit();
      return;
    }
    await _goToAddressStep();
  }

  Future<void> _goToAddressStep() async {
    setState(() {
      _farmerStep = 1;
      _error = null;
    });
    if (_psgc != null) return;
    setState(() => _isLoadingPsgc = true);
    final hierarchy = await PsgcRepository.load();
    if (!mounted) return;
    setState(() {
      // An empty hierarchy means the asset failed to load; leave _psgc null
      // so the next visit retries.
      if (hierarchy.regions.isNotEmpty) _psgc = hierarchy;
      _isLoadingPsgc = false;
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
    if (_isFarmer && _farmerStep == 0 && !_isMatchedMember) {
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

  List<Widget> _buildAddressStep(AppLocalizations l10n, ColorScheme cs) {
    final psgc = _psgc;
    final region = _region;
    // Regions without provinces (NCR, HUCs, independent cities) list their
    // cities directly.
    final cityOptions = region == null
        ? const <PsgcCity>[]
        : (region.hasProvinces
              ? (_province?.cities ?? const <PsgcCity>[])
              : region.cities);
    String required(String label) => '$label *';
    String? requiredValidator(Object? v) =>
        v == null ? l10n.registerFieldRequired : null;

    return [
      if (_isLoadingPsgc)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (!_isLoadingPsgc && psgc == null) ...[
        Text(
          l10n.registerAddressLoadFailed,
          style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed),
        ),
        const SizedBox(height: 12),
      ],
      if (psgc != null) ...[
        AppDropdownField<PsgcRegion>(
          value: _region,
          hintText: l10n.addMemberSelectHint,
          labelText: required(l10n.registerRegionLabel),
          items: psgc.regions,
          itemLabel: (r) => r.name,
          validator: requiredValidator,
          onChanged: (v) => setState(() {
            _region = v;
            _province = null;
            _city = null;
            _barangay = null;
          }),
        ),
        const SizedBox(height: 12),
        if (region != null && region.hasProvinces) ...[
          AppDropdownField<PsgcProvince>(
            value: _province,
            hintText: l10n.addMemberSelectHint,
            labelText: required(l10n.registerProvinceLabel),
            items: region.provinces,
            itemLabel: (p) => p.name,
            validator: requiredValidator,
            onChanged: (v) => setState(() {
              _province = v;
              _city = null;
              _barangay = null;
            }),
          ),
          const SizedBox(height: 12),
        ],
        AppDropdownField<PsgcCity>(
          value: _city,
          hintText: l10n.addMemberSelectHint,
          labelText: required(l10n.registerCityLabel),
          items: cityOptions,
          itemLabel: (c) => c.name,
          validator: requiredValidator,
          onChanged: (v) => setState(() {
            _city = v;
            _barangay = null;
          }),
        ),
        const SizedBox(height: 12),
        AppDropdownField<PsgcBarangay>(
          value: _barangay,
          hintText: l10n.addMemberSelectHint,
          labelText: required(l10n.registerBarangayLabel),
          items: _city?.barangays ?? const <PsgcBarangay>[],
          itemLabel: (b) => b.name,
          validator: requiredValidator,
          onChanged: (v) => setState(() => _barangay = v),
        ),
        const SizedBox(height: 12),
      ],
      TextFormField(
        controller: _postalCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        decoration: authFieldDecoration(
          label: required(l10n.registerPostalLabel),
          icon: Icons.markunread_mailbox_outlined,
        ),
        validator: (v) => isValidPhilippinePostalCode(v ?? '')
            ? null
            : l10n.registerPostalInvalid,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _streetCtrl,
        textCapitalization: TextCapitalization.words,
        decoration: authFieldDecoration(
          label: required(l10n.registerStreetLabel),
          icon: Icons.signpost_outlined,
        ),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? l10n.registerFieldRequired : null,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _buildingCtrl,
        textCapitalization: TextCapitalization.words,
        decoration: authFieldDecoration(
          label: l10n.registerBuildingLabel,
          icon: Icons.apartment_outlined,
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _houseNoCtrl,
        decoration: authFieldDecoration(
          label: required(l10n.registerHouseNoLabel),
          icon: Icons.home_outlined,
        ),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? l10n.registerFieldRequired : null,
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _buildReviewStep(AppLocalizations l10n, ColorScheme cs) {
    final notProvided = l10n.registerReviewNotProvided;
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final dob = _dateOfBirth;
    final gender = _gender == null ? null : _genderOptions(l10n)[_gender];
    final username = _isOfficialMember
        ? (_assignedUsername ?? '')
        : _usernameCtrl.text.trim();

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
      row(l10n.registerUsernameLabel, username),
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
    final isNext = _isFarmer && _farmerStep < 2 && !_isMatchedMember;
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

                          if (_isFarmer && !_isMatchedMember) ...[
                            _buildStepper(l10n, cs),
                            const SizedBox(height: 20),
                          ],

                          // Step 1 (Personal Information). Hidden on the
                          // address and review steps; its values stay in
                          // the controllers.
                          if (!_isFarmer || _farmerStep == 0) ...[
                            // Full Name — triggers registry check on change
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
                                suffix:
                                    (_isCheckingRegistry || _isCheckingFullName)
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
                                    : null,
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().length < 2)
                                  ? l10n.registerEnterFullName
                                  : null,
                            ),
                            const SizedBox(height: 12),

                            // ── Duplicate full name (both roles — Issue 3) ───────────────
                            if (_fullNameStatus == 'taken_account' ||
                                _fullNameStatus == 'taken_registry') ...[
                              _InlineBanner(
                                color: AppConstants.errorRed,
                                icon: Icons.block_rounded,
                                title: l10n.registerNameTakenTitle,
                                message: l10n.registerNameAlreadyRegistered,
                                cs: cs,
                              ),
                              const SizedBox(height: 12),
                            ],

                            // ── Registry result banner (farmers only) ────────────────────
                            if (_isFarmer &&
                                _fullNameStatus != 'taken_account' &&
                                _fullNameStatus != 'taken_registry') ...[
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: _registryChecked
                                    ? _RegistryResultBanner(
                                        key: ValueKey(_isOfficialMember),
                                        isMatch: _isOfficialMember,
                                        username: _assignedUsername,
                                        message: _isOfficialMember
                                            ? l10n.registerRegistryMatchMessage
                                            : l10n.registerRegistryNoMatchMessage,
                                        cs: cs,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              if (_registryChecked) const SizedBox(height: 12),
                              if (_registryContactInUse) ...[
                                Text(
                                  l10n.registerRegistryContactInUse,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppConstants.errorRed,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],

                            // ── Username field — only shown when needed ───────────────────
                            if (_showUsernameField) ...[
                              TextFormField(
                                controller: _usernameCtrl,
                                autocorrect: false,
                                textInputAction: TextInputAction.next,
                                onChanged: _onUsernameChanged,
                                decoration: authFieldDecoration(
                                  label: l10n.registerUsernameLabel,
                                  hint: l10n.registerUsernameHint,
                                  icon: Icons.badge_outlined,
                                  suffix: _isCheckingUsername
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
                                      : _usernameAvailable == null
                                      ? null
                                      : Icon(
                                          _usernameAvailable!
                                              ? Icons.check_circle_rounded
                                              : Icons.cancel_rounded,
                                          color: _usernameAvailable!
                                              ? AppConstants.successGreen
                                              : AppConstants.errorRed,
                                        ),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return l10n.registerUsernameRequired;
                                  }
                                  if (v.trim().length < 3) {
                                    return l10n.registerUsernameTooShort;
                                  }
                                  if (_usernameAvailable == false) {
                                    return l10n.registerUsernameTaken;
                                  }
                                  return null;
                                },
                              ),
                              if (_usernameAvailable == true)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    l10n.registerUsernameAvailable,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: AppConstants.successGreen,
                                    ),
                                  ),
                                ),
                              if (_usernameAvailable == false)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    l10n.registerUsernameNotAvailable,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: AppConstants.errorRed,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                            ],

                            // Phone and Email — optional (Issue 1 / D10); order and
                            // labels depend on role (see _buildContactFields).
                            ..._buildContactFields(l10n, cs),

                            // Date of Birth and Gender — farmers only, both required.
                            if (_isFarmer) ...[
                              // Date of Birth — farmers only. The picker itself allows
                              // any real date (dynamically relative to today, not a
                              // fixed year); the 18+ cooperative-membership rule is
                              // enforced afterward via a warning dialog (Phase B, and
                              // the later "fully dynamic picker" revision).
                              InkWell(
                                onTap: () async {
                                  final picked = await AppUtils.pickDateOfBirth(
                                    context,
                                    initialDate: _dateOfBirth,
                                    helpText: l10n.registerDobHelp,
                                  );
                                  if (picked == null) return;
                                  if (!AppUtils.isAtLeast18(picked)) {
                                    if (!context.mounted) return;
                                    await _showAgeRequirementDialog();
                                    return;
                                  }
                                  setState(() {
                                    _dateOfBirth = picked;
                                    _dobError = null;
                                  });
                                },
                                child: InputDecorator(
                                  // errorText gives the same red border and
                                  // message as the other required fields.
                                  decoration: authFieldDecoration(
                                    label: l10n.registerDob,
                                    icon: Icons.cake_outlined,
                                  ).copyWith(errorText: _dobError),
                                  child: Text(
                                    _dateOfBirth == null
                                        ? l10n.registerDobSelect
                                        : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
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
                                validator: (v) => v == null
                                    ? l10n.registerFieldRequired
                                    : null,
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
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                              validator: (v) =>
                                  validatePasswordMinLength(v, l10n),
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
                                  onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm,
                                  ),
                                ),
                              ),
                              validator: (v) => v != _passwordCtrl.text
                                  ? l10n.registerPasswordMismatch
                                  : null,
                            ),
                          ],

                          if (_isFarmer && _farmerStep == 1)
                            ..._buildAddressStep(l10n, cs),
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

// ─────────────────────────────────────────────────────────────────────────────
// Registry Result Banner
// ─────────────────────────────────────────────────────────────────────────────

class _RegistryResultBanner extends StatelessWidget {
  final bool isMatch;
  final String message;
  final String? username;
  final ColorScheme cs;

  const _RegistryResultBanner({
    super.key,
    required this.isMatch,
    required this.message,
    this.username,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = isMatch
        ? AppConstants.successGreen
        : AppConstants.warningAmber;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isMatch ? Icons.verified_rounded : Icons.info_outline_rounded,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                isMatch
                    ? l10n.registerOfficialMemberFound
                    : l10n.registerNotInRegistry,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: cs.onSurface,
              height: 1.5,
            ),
          ),

          // Show assigned username prominently for official members
          if (isMatch && username != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.registerYourUsernameLabel,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    username!.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: color,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    l10n.registerUsernameAutoGenerated,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline banner (generic — used for the duplicate-name error)
// ─────────────────────────────────────────────────────────────────────────────

class _InlineBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String message;
  final ColorScheme cs;

  const _InlineBanner({
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: cs.onSurface,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
