import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../routes/app_routes.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authRepository = AuthRepository();

  String _selectedRole = AppConstants.roleFarmer;
  String? _selectedSitio;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;

  // Real Payanas puroks
  static const List<Map<String, String>> _sitios = [
    {'value': 'Purok 1-Centro 1', 'label': 'Purok 1 — Centro 1'},
    {'value': 'Purok 2-Centro 2', 'label': 'Purok 2 — Centro 2'},
    {'value': 'Purok 3-Centro 3', 'label': 'Purok 3 — Centro 3'},
    {'value': 'Purok 4-Kailugan', 'label': 'Purok 4 — Kailugan'},
    {'value': 'Purok 5-Binubungan', 'label': 'Purok 5 — Binubungan'},
    {'value': 'Purok 6-Tigas', 'label': 'Purok 6 — Tigas'},
    {'value': 'Purok 7-Manggahan', 'label': 'Purok 7 — Manggahan'},
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authRepository.register(
        email: _emailController.text,
        password: _passwordController.text,
        fullName: _fullNameController.text,
        phoneNumber: _phoneController.text,
        role: _selectedRole,
        sitio: _selectedSitio,
      );

      if (!mounted) return;
      _showSuccessDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AuthService.parseAuthError(e);
        _isLoading = false;
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        contentPadding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppConstants.successGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppConstants.successGreen,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Account Created!',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppConstants.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedRole == AppConstants.roleFarmer
                  ? 'Your farmer account has been created. Please check your email to verify your account. SP3 Cooperative staff will activate your membership.'
                  : 'Your buyer account has been created. Please check your email to verify your account before logging in.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppConstants.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushReplacementNamed(AppRoutes.login);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                'Go to Login',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Background
          _RegisterBackground(),

          // Header
          SafeArea(
            child: Column(
              children: [
                _TopHeader(onBack: () => Navigator.of(context).pop()),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacingSafeH,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),

                        // Page title
                        Text(
                          'Create Account',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: AppConstants.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Join the SAGANA cooperative and start growing your future today.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppConstants.onSurfaceVariant,
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Role selector
                        _RoleSelector(
                          selectedRole: _selectedRole,
                          onRoleChanged: (role) =>
                              setState(() => _selectedRole = role),
                        ),

                        const SizedBox(height: 28),

                        // Form
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Personal Info ─────────────────────────────
                              _FieldLabel('Full Name'),
                              const SizedBox(height: 6),
                              _FullNameField(
                                  controller: _fullNameController),

                              const SizedBox(height: 16),

                              _FieldLabel('Email Address'),
                              const SizedBox(height: 6),
                              _EmailField(
                                  controller: _emailController),

                              const SizedBox(height: 16),

                              _FieldLabel('Phone Number'),
                              const SizedBox(height: 6),
                              _PhoneField(
                                  controller: _phoneController),

                              const SizedBox(height: 16),

                              // ── Location ──────────────────────────────────
                              _FieldLabel('Sitio / Purok'),
                              const SizedBox(height: 6),
                              _SitioDropdown(
                                sitios: _sitios,
                                selectedValue: _selectedSitio,
                                onChanged: (val) =>
                                    setState(() => _selectedSitio = val),
                                isFarmer: _selectedRole ==
                                    AppConstants.roleFarmer,
                              ),

                              const SizedBox(height: 16),

                              // ── Password ──────────────────────────────────
                              _FieldLabel('Password'),
                              const SizedBox(height: 6),
                              _PasswordField(
                                controller: _passwordController,
                                hint: '••••••••',
                                obscureText: _obscurePassword,
                                onToggle: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                                validator: (v) {
                                  if (v == null || v.isEmpty)
                                    return 'Password is required';
                                  if (v.length < 8)
                                    return 'At least 8 characters';
                                  return null;
                                },
                              ),

                              const SizedBox(height: 16),

                              _FieldLabel('Confirm Password'),
                              const SizedBox(height: 6),
                              _PasswordField(
                                controller: _confirmPasswordController,
                                hint: '••••••••',
                                obscureText: _obscureConfirm,
                                onToggle: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm),
                                validator: (v) {
                                  if (v == null || v.isEmpty)
                                    return 'Please confirm your password';
                                  if (v != _passwordController.text)
                                    return 'Passwords do not match';
                                  return null;
                                },
                              ),

                              const SizedBox(height: 8),

                              // ── Error ─────────────────────────────────────
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 12),
                                _ErrorBanner(message: _errorMessage!),
                              ],

                              const SizedBox(height: 28),

                              // ── Submit ────────────────────────────────────
                              _CreateAccountButton(
                                isLoading: _isLoading,
                                onPressed: _handleRegister,
                              ),

                              const SizedBox(height: 20),

                              // ── Login link ────────────────────────────────
                              Center(
                                child: RichText(
                                  text: TextSpan(
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: AppConstants.onSurfaceVariant,
                                    ),
                                    children: [
                                      const TextSpan(
                                          text: 'Already have an account? '),
                                      WidgetSpan(
                                        child: GestureDetector(
                                          onTap: () =>
                                              Navigator.of(context).pop(),
                                          child: Text(
                                            'Login',
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: AppConstants.primaryGreen,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background
// ─────────────────────────────────────────────────────────────────────────────

class _RegisterBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppConstants.surface,
      child: Stack(
        children: [
          Positioned(
            top: 80,
            right: -80,
            child: Container(
              width: 256,
              height: 256,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConstants.primaryGreen.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: -40,
            child: Container(
              width: 192,
              height: 192,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConstants.secondaryContainer.withValues(alpha: 0.10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Header
// ─────────────────────────────────────────────────────────────────────────────

class _TopHeader extends StatelessWidget {
  final VoidCallback onBack;
  const _TopHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingSafeH),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.20),
              ),
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: onBack,
                child: const Icon(Icons.arrow_back_rounded,
                    color: AppConstants.primaryGreen),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.eco_rounded,
                  color: AppConstants.primaryGreen, size: 22),
              const SizedBox(width: 8),
              Text(
                'SAGANA',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.primaryGreen,
                  letterSpacing: -0.5,
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
// Role Selector
// ─────────────────────────────────────────────────────────────────────────────

class _RoleSelector extends StatelessWidget {
  final String selectedRole;
  final ValueChanged<String> onRoleChanged;

  const _RoleSelector({
    required this.selectedRole,
    required this.onRoleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Register as',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppConstants.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _RoleCard(
                icon: Icons.agriculture_rounded,
                iconFilled: true,
                label: 'Farmer',
                role: AppConstants.roleFarmer,
                isSelected: selectedRole == AppConstants.roleFarmer,
                onTap: () => onRoleChanged(AppConstants.roleFarmer),
                description: 'SP3 cooperative member',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _RoleCard(
                icon: Icons.shopping_basket_rounded,
                iconFilled: false,
                label: 'Buyer',
                role: AppConstants.roleBuyer,
                isSelected: selectedRole == AppConstants.roleBuyer,
                onTap: () => onRoleChanged(AppConstants.roleBuyer),
                description: 'Browse & order produce',
              ),
            ),
          ],
        ),
        if (selectedRole == AppConstants.roleFarmer) ...[
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: AppConstants.primaryGreen.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14,
                    color: AppConstants.primaryGreen.withValues(alpha: 0.8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Farmer accounts require SP3 membership verification before activation.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppConstants.primaryGreen
                          .withValues(alpha: 0.85),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final bool iconFilled;
  final String label;
  final String role;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.iconFilled,
    required this.label,
    required this.role,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.70)
              : Colors.white.withValues(alpha: 0.40),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: isSelected
                ? AppConstants.primaryGreen
                : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppConstants.primaryContainer
                    : AppConstants.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 26,
                color: isSelected
                    ? AppConstants.onPrimaryContainer
                    : AppConstants.primaryGreen,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? AppConstants.primaryGreen
                    : AppConstants.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Field Label
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppConstants.onSurfaceVariant,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form Fields
// ─────────────────────────────────────────────────────────────────────────────

InputDecoration _inputDecoration({
  required String hint,
  required IconData icon,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.inter(
      fontSize: 14,
      color: AppConstants.outline.withValues(alpha: 0.50),
    ),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.50),
    prefixIcon: Icon(icon, size: 20, color: AppConstants.outline),
    suffixIcon: suffix,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      borderSide: BorderSide(
          color: const Color(0xFF94A3B8).withValues(alpha: 0.20)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      borderSide: BorderSide(
          color: const Color(0xFF94A3B8).withValues(alpha: 0.20)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      borderSide:
          const BorderSide(color: AppConstants.primaryGreen, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      borderSide: const BorderSide(color: AppConstants.errorRed),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      borderSide:
          const BorderSide(color: AppConstants.errorRed, width: 2),
    ),
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

class _FullNameField extends StatelessWidget {
  final TextEditingController controller;
  const _FullNameField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.name,
      textCapitalization: TextCapitalization.words,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: _inputDecoration(
          hint: 'Juan Dela Cruz', icon: Icons.person_outline_rounded),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Full name is required';
        if (v.trim().length < 3) return 'Enter your complete name';
        return null;
      },
    );
  }
}

class _EmailField extends StatelessWidget {
  final TextEditingController controller;
  const _EmailField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: _inputDecoration(
          hint: 'juan@example.com', icon: Icons.mail_outline_rounded),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Email is required';
        final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
        if (!regex.hasMatch(v.trim())) return 'Enter a valid email address';
        return null;
      },
    );
  }
}

class _PhoneField extends StatelessWidget {
  final TextEditingController controller;
  const _PhoneField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: _inputDecoration(
          hint: '09XXXXXXXXX', icon: Icons.smartphone_rounded),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Phone number is required';
        final regex = RegExp(r'^09\d{9}$');
        if (!regex.hasMatch(v.trim()))
          return 'Enter a valid PH mobile number (09XXXXXXXXX)';
        return null;
      },
    );
  }
}

class _SitioDropdown extends StatelessWidget {
  final List<Map<String, String>> sitios;
  final String? selectedValue;
  final ValueChanged<String?> onChanged;
  final bool isFarmer;

  const _SitioDropdown({
    required this.sitios,
    required this.selectedValue,
    required this.onChanged,
    required this.isFarmer,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: selectedValue,
      onChanged: onChanged,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      icon: const Icon(Icons.expand_more_rounded,
          color: AppConstants.outline, size: 20),
      decoration: _inputDecoration(
        hint: 'Select your purok',
        icon: Icons.location_on_outlined,
      ),
      items: sitios
          .map((s) => DropdownMenuItem(
                value: s['value'],
                child: Text(s['label']!),
              ))
          .toList(),
      validator: isFarmer
          ? (v) {
              if (v == null || v.isEmpty)
                return 'Please select your sitio/purok';
              return null;
            }
          : null,
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscureText;
  final VoidCallback onToggle;
  final String? Function(String?)? validator;

  const _PasswordField({
    required this.controller,
    required this.hint,
    required this.obscureText,
    required this.onToggle,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: _inputDecoration(
        hint: hint,
        icon: Icons.lock_outline_rounded,
        suffix: IconButton(
          icon: Icon(
            obscureText
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 20,
            color: AppConstants.outline,
          ),
          onPressed: onToggle,
        ),
      ),
      validator: validator,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error Banner
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppConstants.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
            color: AppConstants.errorRed.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppConstants.errorRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppConstants.errorRed),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Account Button
// ─────────────────────────────────────────────────────────────────────────────

class _CreateAccountButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const _CreateAccountButton(
      {required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              AppConstants.primaryGreen,
              Color(0xFF2A6B2C), // surface-tint
            ],
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          boxShadow: [
            BoxShadow(
              color: AppConstants.primaryGreen.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            ),
          ),
          icon: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.arrow_forward_rounded,
                  size: 20, color: Colors.white),
          label: Text(
            isLoading ? 'Creating Account...' : 'Create Account',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
