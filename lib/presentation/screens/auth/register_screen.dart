import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/services/auth_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dropdown_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey             = GlobalKey<FormState>();
  final _fullNameCtrl        = TextEditingController();
  final _usernameCtrl        = TextEditingController();
  final _phoneCtrl           = TextEditingController();
  final _emailCtrl           = TextEditingController();
  final _passwordCtrl        = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  String  _selectedRole    = AppConstants.roleFarmer;
  String? _selectedPurok;
  DateTime? _dateOfBirth;
  String? _gender; // male | female | prefer_not_to_say

  Map<String, String> _genderOptions(AppLocalizations l10n) => {
        'male': l10n.registerGenderMale,
        'female': l10n.registerGenderFemale,
        'prefer_not_to_say': l10n.registerGenderPreferNotToSay,
      };

  // Registry check state
  Timer?              _debounce;
  bool                _isCheckingRegistry = false;
  bool                _registryChecked    = false;
  bool                _isOfficialMember   = false;
  Sp3RegistryResult?  _registryResult;
  String?             _assignedUsername;

  // Full-name duplicate check (Issue 3) — runs for BOTH roles.
  // One of: null (unchecked), 'available', 'taken_account', 'taken_registry'.
  String? _fullNameStatus;
  bool    _isCheckingFullName = false;

  // Username availability state (for non-members)
  Timer?  _usernameDebounce;
  bool    _isCheckingUsername = false;
  bool?   _usernameAvailable;

  // Email availability state (optional field — Issue 1 / D10)
  Timer?  _emailDebounce;
  bool    _isCheckingEmail = false;
  bool?   _emailAvailable;

  static final RegExp _emailRegex =
      RegExp(r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$');

  bool _obscurePassword = true;
  bool _obscureConfirm  = true;
  bool _isLoading       = false;
  String? _error;

  bool get _isFarmer => _selectedRole == AppConstants.roleFarmer;

  String? _mapSuggestedPurokToCanonical(String? suggested) {
    if (suggested == null) return null;
    String normalize(String s) => s
        .replaceAll(RegExp(r'[\u2013\u2014–-]'), '-')
        .replaceAll(RegExp(r"\s+"), ' ')
        .trim()
        .toLowerCase();
    final target = normalize(suggested);
    for (final p in AppConstants.payanasPuroks) {
      if (normalize(p) == target) return p;
    }
    return null;
  }

  // Whether to show the username field — only for non-members
  // and only after the registry check has completed
  bool get _showUsernameField =>
      !_isFarmer ||
      (_registryChecked && !_isOfficialMember);

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
    super.dispose();
  }

  // ── Registry check — debounced, fires 600ms after typing stops ───────────────

  void _onFullNameChanged() {
    final name = _fullNameCtrl.text.trim();

    // Reset any previous result whenever the name changes.
    if (_registryChecked || _isOfficialMember || _fullNameStatus != null) {
      final wasOfficial = _isOfficialMember;
      setState(() {
        _registryChecked  = false;
        _isOfficialMember = false;
        _registryResult   = null;
        _assignedUsername = null;
        _fullNameStatus   = null;
        // Only clear the username field when it held an auto-assigned
        // SP3-XXXX — never discard what an outsider typed themselves.
        if (wasOfficial) _usernameCtrl.clear();
        _usernameAvailable = null;
      });
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
    setState(() => _isCheckingFullName = true);

    final status = await AuthService.checkFullNameAvailability(name);
    if (!mounted) return;

    if (status == 'taken_account' || status == 'taken_registry') {
      setState(() {
        _fullNameStatus     = status;
        _isCheckingFullName  = false;
        _registryChecked     = false;
        _isOfficialMember    = false;
        _registryResult      = null;
        _assignedUsername    = null;
      });
      return;
    }

    // 'available' or 'error' — allow the flow to continue. On 'error' the
    // server-side insert still enforces uniqueness.
    setState(() {
      _fullNameStatus    = 'available';
      _isCheckingFullName = false;
    });

    if (_isFarmer) {
      await _checkRegistry(name);
    }
  }

  Future<void> _checkRegistry(String name) async {
    if (!mounted) return;
    setState(() => _isCheckingRegistry = true);

    final result = await AuthService.checkSp3Registry(name);

    if (!mounted) return;

    if (result != null && result.alreadyRegistered) {
      // Matched a registry row that is already registered — treat as a
      // duplicate, not an outsider.
      setState(() {
        _fullNameStatus     = 'taken_registry';
        _isOfficialMember   = false;
        _registryResult     = null;
        _assignedUsername   = null;
        _registryChecked    = false;
        _isCheckingRegistry = false;
      });
      return;
    }

    if (result != null) {
      // Matched and available — generate username, auto-fill contact fields.
      final username = await AuthService.suggestNextUsername('SP3');
      if (!mounted) return;
      setState(() {
        _isOfficialMember = true;
        _registryResult   = result;
        _assignedUsername = username;
        if (result.suggestedPurok != null) {
          // Map the server-provided purok string to the canonical
          // AppConstants.payanasPuroks entry (normalizes dashes/spacing).
          _selectedPurok = _mapSuggestedPurokToCanonical(result.suggestedPurok);
        }
        // Auto-fill phone + email from the registry (both stay editable — D5).
        if (result.phone != null && _phoneCtrl.text.trim().isEmpty) {
          _phoneCtrl.text = result.phone!;
        }
        if (result.email != null && _emailCtrl.text.trim().isEmpty) {
          _emailCtrl.text = result.email!;
          _emailAvailable = null;
        }
        _registryChecked    = true;
        _isCheckingRegistry = false;
      });
    } else {
      setState(() {
        _isOfficialMember   = false;
        _registryResult     = null;
        _assignedUsername   = null;
        _registryChecked    = true;
        _isCheckingRegistry = false;
      });
    }
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
      _emailAvailable  = available;
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
      _usernameAvailable  = available;
      _isCheckingUsername = false;
    });
  }

  // ── Role switch ───────────────────────────────────────────────────────────────

  void _onRoleChanged(String role) {
    setState(() {
      _selectedRole      = role;
      _registryChecked   = false;
      _isOfficialMember  = false;
      _registryResult    = null;
      _assignedUsername  = null;
      _usernameAvailable = null;
      _usernameCtrl.clear();
      // Re-run duplicate/registry checks under the new role's rules.
      _fullNameStatus    = null;
      if (_fullNameCtrl.text.trim().length >= 3) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300),
            () => _runNameChecks(_fullNameCtrl.text.trim()));
      }
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Duplicate full name — hard block for both roles (Issue 3).
    if (_fullNameStatus == 'taken_account' ||
        _fullNameStatus == 'taken_registry') {
      setState(() => _error = l10n.registerNameAlreadyRegistered);
      return;
    }
    if (_isCheckingFullName) {
      setState(() => _error = l10n.registerCheckingName);
      return;
    }

    // For farmers: must have completed registry check
    if (_isFarmer && !_registryChecked) {
      setState(() => _error = l10n.registerCheckingRegistry);
      return;
    }

    final username = _isOfficialMember
        ? _assignedUsername!
        : _usernameCtrl.text.trim();

    if (!_isOfficialMember && _usernameAvailable != true) {
      setState(() => _error = l10n.registerChooseAvailableUsername);
      return;
    }

    // Email is optional, but if provided it must be well-formed and free.
    final emailInput = _emailCtrl.text.trim();
    if (emailInput.isNotEmpty) {
      if (!_emailRegex.hasMatch(emailInput)) {
        setState(() => _error = l10n.registerInvalidEmail);
        return;
      }
      if (_emailAvailable == false) {
        setState(() => _error = l10n.registerEmailTaken);
        return;
      }
    }

    setState(() { _isLoading = true; _error = null; });

    final phoneInput = _phoneCtrl.text.trim();

    try {
      await AuthService.register(
        username:     username,
        password:     _passwordCtrl.text,
        fullName:     _fullNameCtrl.text.trim(),
        phoneNumber:  phoneInput.isEmpty ? null : phoneInput,
        contactEmail: emailInput.isEmpty ? null : emailInput,
        role:         _selectedRole,
        purok:        _selectedPurok,
        dateOfBirth:  _isFarmer ? _dateOfBirth : null,
        gender:       _isFarmer ? _gender : null,
        registryId:   _registryResult?.registryId,
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
          content: Text(msg, style: GoogleFonts.inter(fontSize: 13, height: 1.6)),
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
        _error    = AuthService.parseAuthError(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;
    final l10n   = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Back
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: sagana.cardBackground,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: cs.outline.withValues(alpha: 0.15)),
                      ),
                      child: Icon(Icons.arrow_back_rounded,
                          color: cs.onSurface, size: 20),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Text(l10n.registerTitle,
                    style: GoogleFonts.poppins(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
                Text(l10n.registerSubtitle,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 24),

                // Role selector
                _RoleSelector(
                  selectedRole: _selectedRole,
                  onChanged: _onRoleChanged,
                ),
                const SizedBox(height: 20),

                // Full Name — triggers registry check on change
                TextFormField(
                  controller: _fullNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: '${l10n.fullName} *',
                    hintText: _isFarmer
                        ? l10n.registerFullNameHintFarmer
                        : l10n.registerFullNameHintBuyer,
                    prefixIcon: const Icon(Icons.person_outlined),
                    // Show spinner in suffix while checking
                    suffixIcon: (_isCheckingRegistry || _isCheckingFullName)
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cs.primary),
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
                if (_isFarmer && _fullNameStatus != 'taken_account' &&
                    _fullNameStatus != 'taken_registry') ...[
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _registryChecked
                        ? _RegistryResultBanner(
                            key: ValueKey(_isOfficialMember),
                            isMatch:  _isOfficialMember,
                            username: _assignedUsername,
                            message: _isOfficialMember
                                ? l10n.registerRegistryMatchMessage
                                : l10n.registerRegistryNoMatchMessage,
                            cs: cs,
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (_registryChecked) const SizedBox(height: 12),
                ],

                // ── Username field — only shown when needed ───────────────────
                if (_showUsernameField) ...[
                  TextFormField(
                    controller: _usernameCtrl,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    onChanged: _onUsernameChanged,
                    decoration: InputDecoration(
                      labelText: l10n.registerUsernameLabel,
                      hintText: l10n.registerUsernameHint,
                      prefixIcon: const Icon(Icons.badge_outlined),
                      suffixIcon: _isCheckingUsername
                          ? Padding(
                              padding: const EdgeInsets.all(14),
                              child: SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: cs.primary),
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
                      child: Text(l10n.registerUsernameAvailable,
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppConstants.successGreen)),
                    ),
                  if (_usernameAvailable == false)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(l10n.registerUsernameNotAvailable,
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppConstants.errorRed)),
                    ),
                  const SizedBox(height: 12),
                ],

                // Phone number — optional (Issue 1)
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.registerPhoneOptional,
                    hintText: '09XXXXXXXXX',
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null; // optional
                    if (!RegExp(r'^09\d{9}$').hasMatch(t)) {
                      return l10n.registerInvalidPhone;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Email — optional (Issue 1 / D10)
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  onChanged: _onEmailChanged,
                  decoration: InputDecoration(
                    labelText: l10n.registerEmailOptional,
                    hintText: 'name@example.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    suffixIcon: _isCheckingEmail
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cs.primary),
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
                ),
                const SizedBox(height: 12),

                // Purok — farmers only, optional (Issue 1)
                if (_isFarmer) ...[
                  AppDropdownField<String>(
                    value: _selectedPurok,
                    hintText: 'Select a purok',
                    labelText: l10n.registerPurokOptional,
                    items: AppConstants.payanasPuroks,
                    itemLabel: (s) => s,
                    onChanged: (v) => setState(() => _selectedPurok = v),
                  ),
                  const SizedBox(height: 12),

                  // Date of Birth — farmers only, 18+ enforced (Phase B)
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dateOfBirth ?? DateTime(now.year - 25),
                        firstDate: DateTime(1930),
                        lastDate:
                            DateTime(now.year - 18, now.month, now.day),
                        helpText: l10n.registerDobHelp,
                      );
                      if (picked != null) {
                        setState(() => _dateOfBirth = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: l10n.registerDob,
                        prefixIcon: const Icon(Icons.cake_outlined),
                      ),
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

                  // Gender — farmers only, optional
                  AppDropdownField<String>(
                    value: _gender,
                    hintText: 'Select gender',
                    labelText: l10n.registerGenderOptional,
                    items: _genderOptions(l10n).keys.toList(),
                    itemLabel: (key) => _genderOptions(l10n)[key]!,
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                  const SizedBox(height: 12),
                ],

                // Password
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.registerPasswordLabel,
                    prefixIcon:
                        const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.length < 8)
                          ? l10n.registerPasswordTooShort
                          : null,
                ),
                const SizedBox(height: 12),

                // Confirm password
                TextFormField(
                  controller: _confirmPasswordCtrl,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: l10n.registerConfirmPasswordLabel,
                    prefixIcon:
                        const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(
                          () => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) =>
                      v != _passwordCtrl.text
                          ? l10n.registerPasswordMismatch
                          : null,
                ),

                // Error
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.50),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMd),
                    ),
                    child: Text(_error!,
                        style: GoogleFonts.inter(
                            fontSize: 13, color: cs.error)),
                  ),
                ],

                const SizedBox(height: 28),

                // Submit
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(l10n.registerTitle,
                            style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 16),

                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(l10n.registerAlreadyHaveAccount,
                      style: GoogleFonts.inter(
                          fontSize: 13, color: cs.onSurfaceVariant)),
                  GestureDetector(
                    onTap: () => context.go(AppRoutes.login),
                    child: Text(l10n.registerSignIn,
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.primary)),
                  ),
                ]),
              ],
            ),
          ),
        ),
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

  const _RoleSelector(
      {required this.selectedRole, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    final l10n = AppLocalizations.of(context);
    return Row(children: [
      _RoleChip(
        label: l10n.registerRoleFarmer,
        icon: Icons.agriculture_rounded,
        isSelected: selectedRole == AppConstants.roleFarmer,
        onTap: () => onChanged(AppConstants.roleFarmer),
        cs: cs, sagana: sagana,
      ),
      const SizedBox(width: 10),
      _RoleChip(
        label: l10n.registerRoleBuyer,
        icon: Icons.shopping_bag_outlined,
        isSelected: selectedRole == AppConstants.roleBuyer,
        onTap: () => onChanged(AppConstants.roleBuyer),
        cs: cs, sagana: sagana,
      ),
    ]);
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
    required this.label, required this.icon,
    required this.isSelected, required this.onTap,
    required this.cs, required this.sagana,
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
            borderRadius:
                BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: isSelected
                  ? cs.primary
                  : cs.outline.withValues(alpha: 0.20),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(children: [
            Icon(icon,
                color:
                    isSelected ? cs.primary : cs.onSurfaceVariant,
                size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: isSelected
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: isSelected
                      ? cs.primary
                      : cs.onSurfaceVariant,
                )),
          ]),
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
    final color =
        isMatch ? AppConstants.successGreen : AppConstants.warningAmber;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius:
            BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isMatch
                    ? Icons.verified_rounded
                    : Icons.info_outline_rounded,
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
                    color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(message,
              style: GoogleFonts.inter(
                  fontSize: 12, color: cs.onSurface, height: 1.5)),

          // Show assigned username prominently for official members
          if (isMatch && username != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.registerYourUsernameLabel,
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4)),
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
                  Text(l10n.registerUsernameAutoGenerated,
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          color: cs.onSurfaceVariant)),
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
                child: Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(message,
              style: GoogleFonts.inter(
                  fontSize: 12, color: cs.onSurface, height: 1.5)),
        ],
      ),
    );
  }
}