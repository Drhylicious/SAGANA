import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/services/auth_service.dart';
import '../../../routes/app_routes.dart';

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
  final _passwordCtrl        = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  String  _selectedRole    = AppConstants.roleFarmer;
  String? _selectedSitio;

  // Registry check state
  Timer?              _debounce;
  bool                _isCheckingRegistry = false;
  bool                _registryChecked    = false;
  bool                _isOfficialMember   = false;
  Sp3RegistryResult?  _registryResult;
  String?             _assignedUsername;

  // Username availability state (for non-members)
  Timer?  _usernameDebounce;
  bool    _isCheckingUsername = false;
  bool?   _usernameAvailable;

  bool _obscurePassword = true;
  bool _obscureConfirm  = true;
  bool _isLoading       = false;
  String? _error;

  bool get _isFarmer => _selectedRole == AppConstants.roleFarmer;

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
    _fullNameCtrl.removeListener(_onFullNameChanged);
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // ── Registry check — debounced, fires 600ms after typing stops ───────────────

  void _onFullNameChanged() {
    if (!_isFarmer) return;

    final name = _fullNameCtrl.text.trim();

    // Reset previous result whenever name changes
    if (_registryChecked || _isOfficialMember) {
      setState(() {
        _registryChecked  = false;
        _isOfficialMember = false;
        _registryResult   = null;
        _assignedUsername = null;
        _usernameCtrl.clear();
        _usernameAvailable = null;
      });
    }

    // Need at least 3 characters to check
    if (name.length < 3) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _checkRegistry(name);
    });
  }

  Future<void> _checkRegistry(String name) async {
    if (!mounted) return;
    setState(() => _isCheckingRegistry = true);

    final result = await AuthService.checkSp3Registry(name);

    if (!mounted) return;

    if (result != null) {
      // Matched and available — generate username
      final username = await AuthService.suggestNextUsername('SP3');
      if (!mounted) return;
      setState(() {
        _isOfficialMember   = true;
        _registryResult     = result;
        _assignedUsername   = username;
        if (result.suggestedSitio != null) {
          _selectedSitio = result.suggestedSitio;
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
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // For farmers: must have completed registry check
    if (_isFarmer && !_registryChecked) {
      setState(() =>
          _error = 'Please wait — checking SP3 member registry...');
      return;
    }

    final username = _isOfficialMember
        ? _assignedUsername!
        : _usernameCtrl.text.trim();

    if (!_isOfficialMember && _usernameAvailable != true) {
      setState(() => _error = 'Please choose an available username.');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      await AuthService.register(
        username:    username,
        password:    _passwordCtrl.text,
        fullName:    _fullNameCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        role:        _selectedRole,
        sitio:       _selectedSitio,
        registryId:  _registryResult?.registryId,
        memberId:    _isOfficialMember ? _assignedUsername : null,
      );

      if (!mounted) return;

      final msg = _isOfficialMember
          ? 'Welcome, official SP3 member!\n\n'
            'Your SAGANA username is:\n$_assignedUsername\n\n'
            'Please remember this username to log in.'
          : _isFarmer
              ? 'Account created successfully.\n\n'
                'Your username is:\n${_usernameCtrl.text.trim()}\n\n'
                'Your membership is pending verification by the '
                'SP3 Agriculture Cooperative. You will be notified '
                'once approved.'
              : 'Account created successfully.\n\n'
                'You can now log in with your username:\n'
                '${_usernameCtrl.text.trim()}';

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text(
            _isOfficialMember ? 'Welcome to SP3! 🌾' : 'Account Created',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          content: Text(msg, style: GoogleFonts.inter(fontSize: 13, height: 1.6)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.go(AppRoutes.login);
              },
              child: const Text('Go to Login'),
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

                Text('Create Account',
                    style: GoogleFonts.poppins(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
                Text('Join the SP3 cooperative network',
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
                    labelText: 'Full Name *',
                    hintText: _isFarmer
                        ? 'As it appears in cooperative records'
                        : 'Your full name',
                    prefixIcon: const Icon(Icons.person_outlined),
                    // Show spinner in suffix while checking
                    suffixIcon: _isCheckingRegistry
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
                          ? 'Enter your full name'
                          : null,
                ),
                const SizedBox(height: 12),

                // ── Registry result banner (farmers only) ────────────────────
                if (_isFarmer) ...[
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _registryChecked
                        ? _RegistryResultBanner(
                            key: ValueKey(_isOfficialMember),
                            isMatch:  _isOfficialMember,
                            username: _assignedUsername,
                            message: _isOfficialMember
                                ? 'Your name was found in the official SP3 member '
                                  'registry. Your SAGANA username has been '
                                  'assigned automatically.'
                                : 'Your name was not found in the SP3 member '
                                  'registry. You may still register — your '
                                  'account will be reviewed by SP3 staff.',
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
                      labelText: 'Choose a Username *',
                      hintText: 'e.g. juandelacruz',
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
                        return 'Choose a username';
                      }
                      if (v.trim().length < 3) {
                        return 'Username must be at least 3 characters';
                      }
                      if (_usernameAvailable == false) {
                        return 'This username is already taken';
                      }
                      return null;
                    },
                  ),
                  if (_usernameAvailable == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Username is available!',
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppConstants.successGreen)),
                    ),
                  if (_usernameAvailable == false)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('That username is taken.',
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppConstants.errorRed)),
                    ),
                  const SizedBox(height: 12),
                ],

                // Phone number
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number *',
                    hintText: '09XXXXXXXXX',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Enter your phone number';
                    }
                    if (!RegExp(r'^09\d{9}$').hasMatch(v.trim())) {
                      return 'Enter a valid PH number (09XXXXXXXXX)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Sitio — farmers only
                if (_isFarmer) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSitio,
                    decoration: const InputDecoration(
                      labelText: 'Sitio / Purok *',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    items: AppConstants.payanasSitios
                        .map((s) =>
                            DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedSitio = v),
                    validator: (v) =>
                        v == null ? 'Select your sitio' : null,
                  ),
                  const SizedBox(height: 12),
                ],

                // Password
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Password *',
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
                          ? 'Password must be at least 8 characters'
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
                    labelText: 'Confirm Password *',
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
                          ? 'Passwords do not match'
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
                        : Text('Create Account',
                            style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 16),

                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Already have an account? ',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: cs.onSurfaceVariant)),
                  GestureDetector(
                    onTap: () => context.go(AppRoutes.login),
                    child: Text('Sign In',
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

    return Row(children: [
      _RoleChip(
        label: 'Farmer',
        icon: Icons.agriculture_rounded,
        isSelected: selectedRole == AppConstants.roleFarmer,
        onTap: () => onChanged(AppConstants.roleFarmer),
        cs: cs, sagana: sagana,
      ),
      const SizedBox(width: 10),
      _RoleChip(
        label: 'Buyer',
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
                    ? 'Official SP3 Member Found ✓'
                    : 'Not in SP3 Registry',
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
                  Text('Your SAGANA Username',
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
                  Text('Auto-generated · Cannot be changed',
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