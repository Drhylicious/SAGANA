import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/animations/staggered_entrance.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authRepository = AuthRepository();

  String _selectedRole = AppConstants.roleFarmer;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0, 0.8, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.15, 1, curve: Curves.easeOutCubic),
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  // ─── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _authRepository.login(
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;

      // Verify role matches selection
      if (user.role != _selectedRole && user.role != AppConstants.roleAdmin) {
        await _authRepository.logout();
        setState(() {
          _errorMessage =
              'This account is not registered as a ${_selectedRole == AppConstants.roleFarmer ? "Farmer" : "Buyer"}. Please select the correct role.';
          _isLoading = false;
        });
        return;
      }

      // Navigate by role
      String route;
      switch (user.role) {
        case AppConstants.roleAdmin:
          route = AppRoutes.adminDashboard;
          break;
        case AppConstants.roleFarmer:
          route = AppRoutes.farmerDashboard;
          break;
        case AppConstants.roleBuyer:
          route = AppRoutes.marketplaceBrowse;
          break;
        default:
          route = AppRoutes.login;
      }

      context.go(route);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AuthService.parseAuthError(e);
        _isLoading = false;
      });
    }
  }

  void _showForgotPassword() {
    final emailController = TextEditingController(
      text: _emailController.text,
    );

    AppBottomSheet.show(
      context: context,
      builder: (context) => _ForgotPasswordSheet(
        emailController: emailController,
        onSend: (email) async {
          await _authRepository.sendPasswordReset(email);
          if (context.mounted) context.popRoute();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Password reset link sent to $email',
                  style: GoogleFonts.inter(fontSize: 13),
                ),
                backgroundColor: AppConstants.successGreen,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const _LoginBackground(),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacingSafeH,
                    vertical: AppConstants.spacingSectionV,
                  ),
                  child: Column(
                    children: [
                      StaggeredEntrance(
                        index: 0,
                        child: _LogoSection(),
                      ),
                      const SizedBox(height: 32),
                      StaggeredEntrance(
                        index: 1,
                        child: _AuthCard(
                          formKey: _formKey,
                          selectedRole: _selectedRole,
                          onRoleChanged: (role) =>
                              setState(() => _selectedRole = role),
                          emailController: _emailController,
                          passwordController: _passwordController,
                          obscurePassword: _obscurePassword,
                          onTogglePassword: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          errorMessage: _errorMessage,
                          isLoading: _isLoading,
                          onLogin: _handleLogin,
                          onForgotPassword: _showForgotPassword,
                          onRegister: () =>
                              context.pushRoute(AppRoutes.register),
                        ),
                      ),
                      const SizedBox(height: 24),
                      StaggeredEntrance(
                        index: 2,
                        child: _AdminNote(),
                      ),
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
// Background
// ─────────────────────────────────────────────────────────────────────────────

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE6F6FF), // surface-container-low
            Color(0xFFF9FBF7), // background-off-white
            Color(0xFFD5ECF8), // surface-container-high
          ],
        ),
      ),
      child: Stack(
        children: [
          // Top-left orb
          Positioned(
            top: -96,
            left: -96,
            child: Container(
              width: 384,
              height: 384,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConstants.primaryGreen.withValues(alpha: 0.05),
              ),
            ),
          ),
          // Bottom-right orb
          Positioned(
            bottom: -96,
            right: -96,
            child: Container(
              width: 384,
              height: 384,
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
// Logo Section
// ─────────────────────────────────────────────────────────────────────────────

class _LogoSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Icon circle
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.agriculture_rounded,
            size: 40,
            color: AppConstants.primaryGreen,
          ),
        ),

        const SizedBox(height: 16),

        Text(
          AppConstants.appName,
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppConstants.primaryGreen,
            letterSpacing: -0.5,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          'Empowering the Future of Farming',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppConstants.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auth Card
// ─────────────────────────────────────────────────────────────────────────────

class _AuthCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final String selectedRole;
  final ValueChanged<String> onRoleChanged;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onTogglePassword;
  final String? errorMessage;
  final bool isLoading;
  final VoidCallback onLogin;
  final VoidCallback onForgotPassword;
  final VoidCallback onRegister;

  const _AuthCard({
    required this.formKey,
    required this.selectedRole,
    required this.onRoleChanged,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onTogglePassword,
    required this.errorMessage,
    required this.isLoading,
    required this.onLogin,
    required this.onForgotPassword,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.40),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 50,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Role selector label
                Text(
                  'Select Your Role',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppConstants.outline,
                  ),
                ),

                const SizedBox(height: 12),

                // Role selector
                _RoleSelector(
                  selectedRole: selectedRole,
                  onRoleChanged: onRoleChanged,
                ),

                const SizedBox(height: 28),

                // Email field
                _InputLabel('Email Address'),
                const SizedBox(height: 6),
                _EmailField(controller: emailController),

                const SizedBox(height: 20),

                // Password field
                _InputLabel('Password'),
                const SizedBox(height: 6),
                _PasswordField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  onToggle: onTogglePassword,
                ),

                // Forgot password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onForgotPassword,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Forgot Password?',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Error message
                if (errorMessage != null) ...[
                  _ErrorBanner(message: errorMessage!),
                  const SizedBox(height: 16),
                ],

                // Sign in button
                _SignInButton(
                  isLoading: isLoading,
                  onPressed: onLogin,
                ),

                const SizedBox(height: 20),

                // Register link
                Center(
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppConstants.onSurfaceVariant,
                      ),
                      children: [
                        const TextSpan(text: 'New to SAGANA? '),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: onRegister,
                            child: Text(
                              'Create an Account',
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
  final ValueChanged<String> onRoleChanged;

  const _RoleSelector({
    required this.selectedRole,
    required this.onRoleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RoleCard(
            icon: Icons.person_rounded,
            label: 'Farmer',
            role: AppConstants.roleFarmer,
            isSelected: selectedRole == AppConstants.roleFarmer,
            onTap: () => onRoleChanged(AppConstants.roleFarmer),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _RoleCard(
            icon: Icons.shopping_cart_rounded,
            label: 'Buyer',
            role: AppConstants.roleBuyer,
            isSelected: selectedRole == AppConstants.roleBuyer,
            onTap: () => onRoleChanged(AppConstants.roleBuyer),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String role;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.label,
    required this.role,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppConstants.primaryGreen.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: isSelected
                ? AppConstants.primaryGreen
                : AppConstants.outline.withValues(alpha: 0.20),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color: isSelected
                  ? AppConstants.primaryGreen
                  : AppConstants.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? AppConstants.primaryGreen
                    : AppConstants.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Input Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _InputLabel extends StatelessWidget {
  final String text;
  const _InputLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppConstants.onSurface,
      ),
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
      decoration: _fieldDecoration(
        hint: 'farmer@hub.com',
        icon: Icons.mail_outline_rounded,
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Email is required';
        final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
        if (!regex.hasMatch(v.trim())) return 'Enter a valid email address';
        return null;
      },
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscureText;
  final VoidCallback onToggle;

  const _PasswordField({
    required this.controller,
    required this.obscureText,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: _fieldDecoration(
        hint: '••••••••',
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
      validator: (v) {
        if (v == null || v.isEmpty) return 'Password is required';
        if (v.length < 8) return 'Password must be at least 8 characters';
        return null;
      },
    );
  }
}

InputDecoration _fieldDecoration({
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
        color: AppConstants.outline.withValues(alpha: 0.20),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      borderSide: BorderSide(
        color: AppConstants.outline.withValues(alpha: 0.20),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      borderSide: const BorderSide(
        color: AppConstants.primaryGreen,
        width: 2,
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      borderSide: const BorderSide(color: AppConstants.errorRed),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      borderSide: const BorderSide(color: AppConstants.errorRed, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
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
          color: AppConstants.errorRed.withValues(alpha: 0.25),
        ),
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
                fontSize: 13,
                color: AppConstants.errorRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sign In Button
// ─────────────────────────────────────────────────────────────────────────────

class _SignInButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const _SignInButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFCAB28), // secondary-container / harvest
              Color(0xFF835400), // secondary
            ],
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          boxShadow: [
            BoxShadow(
              color: AppConstants.amber.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  'Sign In',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Note
// ─────────────────────────────────────────────────────────────────────────────

class _AdminNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: AppConstants.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16,
              color: AppConstants.onSurfaceVariant.withValues(alpha: 0.7)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Admin access is managed by SP3 Cooperative staff.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Forgot Password Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ForgotPasswordSheet extends StatefulWidget {
  final TextEditingController emailController;
  final Future<void> Function(String email) onSend;

  const _ForgotPasswordSheet({
    required this.emailController,
    required this.onSend,
  });

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  bool _isSending = false;
  String? _error;

  Future<void> _handleSend() async {
    final email = widget.emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address');
      return;
    }
    final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!regex.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      await widget.onSend(email);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not send reset link. Please try again.';
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXl),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppConstants.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text(
              'Reset Password',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppConstants.onSurface,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Enter the email address linked to your SAGANA account. We\'ll send you a reset link.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppConstants.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 24),

            TextField(
              controller: widget.emailController,
              keyboardType: TextInputType.emailAddress,
              style: GoogleFonts.inter(fontSize: 14),
              decoration: _fieldDecoration(
                hint: 'Your email address',
                icon: Icons.mail_outline_rounded,
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppConstants.errorRed,
                ),
              ),
            ],

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSending ? null : _handleSend,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMd),
                  ),
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        'Send Reset Link',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
