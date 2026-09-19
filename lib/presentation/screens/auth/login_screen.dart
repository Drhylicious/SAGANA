import 'dart:ui';
import 'package:flutter/material.dart';
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
import '../../widgets/auth_visuals.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authRepository = AuthRepository();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isForgotPasswordLoading = false;
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
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.15, 1, curve: Curves.easeOutCubic),
          ),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  @override
  void dispose() {
    _identifierController.dispose();
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
        identifier: _identifierController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;

      String route;
      switch (user.role) {
        case AppConstants.roleAdmin:
          route = AppRoutes.adminDashboard;
          break;
        case 'officer':
          route = AppRoutes.adminDashboard;
          break;
        case AppConstants.roleFarmer:
          route = AppRoutes.farmerDashboard;
          break;
        case AppConstants.roleBuyer:
          route = AppRoutes.marketplaceBrowse;
          break;
        default:
          route = AppRoutes.farmerDashboard;
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

  Future<void> _showForgotPassword() async {
    // Guard against rapid/repeated taps stacking multiple Forgot Password
    // sheets while the async eligibility check (and the sheet itself) is
    // still in flight.
    if (_isForgotPasswordLoading) return;
    setState(() => _isForgotPasswordLoading = true);
    try {
      // Admins, and any Farmer/Buyer who has promoted a real contact email,
      // are eligible for the automated OTP reset; everyone else (including
      // Officer, always) is routed to Admin-assisted reset. See
      // can_use_otp_reset() — unifies this without special-casing by role.
      final identifier = _identifierController.text.trim();
      final canUseOtp = await AuthService.canUseOtpReset(identifier);
      if (!mounted) return;
      if (canUseOtp) {
        await _showAdminResetSheet(prefill: identifier);
      } else {
        await _showContactAdminSheet();
      }
    } finally {
      if (mounted) setState(() => _isForgotPasswordLoading = false);
    }
  }

  Future<void> _showAdminResetSheet({required String prefill}) async {
    final emailController = TextEditingController(text: prefill);

    await AppBottomSheet.show(
      context: context,
      builder: (context) => _ForgotPasswordSheet(
        emailController: emailController,
        onSend: (email) async {
          await _authRepository.sendPasswordReset(email);
          if (!context.mounted) return;
          context.popRoute();
          if (!mounted) return;
          context.pushRoute(
            '${AppRoutes.resetPasswordCallback}?email=${Uri.encodeComponent(email)}',
          );
        },
      ),
    );
  }

  Future<void> _showContactAdminSheet() async {
    await AppBottomSheet.show(
      context: context,
      builder: (context) =>
          _ContactAdminSheet(username: _identifierController.text.trim()),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const AuthBackground(),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                // Centering the content vertically (rather than letting it
                // simply stack from the top, which on a normal-height phone
                // leaves a large, visually unbalanced gap below the Admin
                // note) — LayoutBuilder + a minHeight-constrained Column
                // still scrolls normally on shorter viewports or once the
                // keyboard is open, since SingleChildScrollView only kicks
                // in when content actually exceeds the available height.
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spacingSafeH,
                        vertical: AppConstants.spacingSectionV,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight:
                              (constraints.maxHeight -
                                      2 * AppConstants.spacingSectionV)
                                  .clamp(0, double.infinity),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            StaggeredEntrance(index: 0, child: _LogoSection()),
                            const SizedBox(height: 32),
                            StaggeredEntrance(
                              index: 1,
                              child: _AuthCard(
                                formKey: _formKey,
                                identifierController: _identifierController,
                                passwordController: _passwordController,
                                obscurePassword: _obscurePassword,
                                onTogglePassword: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                errorMessage: _errorMessage,
                                isLoading: _isLoading,
                                onLogin: _handleLogin,
                                onForgotPassword: _showForgotPassword,
                                isForgotPasswordLoading:
                                    _isForgotPasswordLoading,
                                onRegister: () =>
                                    context.pushRoute(AppRoutes.register),
                              ),
                            ),
                            const SizedBox(height: 24),
                            StaggeredEntrance(index: 2, child: _AdminNote()),
                          ],
                        ),
                      ),
                    );
                  },
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
          child: Image.asset(
            'assets/images/sagana_icon.png',
            width: 64,
            height: 64,
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
  final TextEditingController identifierController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onTogglePassword;
  final String? errorMessage;
  final bool isLoading;
  final VoidCallback onLogin;
  final VoidCallback onForgotPassword;
  final bool isForgotPasswordLoading;
  final VoidCallback onRegister;

  const _AuthCard({
    required this.formKey,
    required this.identifierController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onTogglePassword,
    required this.errorMessage,
    required this.isLoading,
    required this.onLogin,
    required this.onForgotPassword,
    required this.isForgotPasswordLoading,
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
                // Identifier field
                const _InputLabel('Username / Email'),
                const SizedBox(height: 6),
                _EmailField(
                  controller: identifierController,
                  isUsername: !identifierController.text.trim().contains('@'),
                ),

                const SizedBox(height: 20),

                // Password field
                const _InputLabel('Password'),
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
                    onPressed: isForgotPasswordLoading
                        ? null
                        : onForgotPassword,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
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
                AuthGradientButton(
                  label: 'Sign In',
                  isLoading: isLoading,
                  onPressed: onLogin,
                  gradientColors: const [
                    Color(0xFFFCAB28), // secondary-container / harvest
                    Color(0xFF835400), // secondary
                  ],
                  glowColor: AppConstants.amber,
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
  final bool isUsername;

  const _EmailField({required this.controller, required this.isUsername});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: isUsername
          ? TextInputType.text
          : TextInputType.emailAddress,
      autocorrect: false,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: authFieldDecoration(
        hint: isUsername ? 'SP3-0001 or OFF-0001' : 'admin@sp3.coop',
        icon: isUsername ? Icons.badge_outlined : Icons.mail_outline_rounded,
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) {
          return 'Username or email is required';
        }
        if (!isUsername) {
          final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
          if (!regex.hasMatch(v.trim())) return 'Enter a valid email address';
        }
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
      decoration: authFieldDecoration(
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
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppConstants.errorRed,
          ),
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
        border: Border.all(color: AppConstants.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: AppConstants.onSurfaceVariant.withValues(alpha: 0.7),
          ),
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
              decoration: authFieldDecoration(
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
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Contact Admin Sheet — farmer / staff / buyer path
// ─────────────────────────────────────────────────────────────────────────────
//
// These roles authenticate with a SAGANA username, not a real email
// address, so there's no inbox an automated reset link could reach.
// Password assistance has to go through the SP3 office instead.

class _ContactAdminSheet extends StatefulWidget {
  final String username;
  const _ContactAdminSheet({required this.username});

  @override
  State<_ContactAdminSheet> createState() => _ContactAdminSheetState();
}

class _ContactAdminSheetState extends State<_ContactAdminSheet> {
  bool _isSubmitting = false;
  bool _requestSent = false;

  bool get _hasUsername => widget.username.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
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

              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: AppConstants.primaryGreen,
                  size: 28,
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Need Help Signing In?',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.onSurface,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Farmer, Officer, and Buyer accounts sign in with a SAGANA '
                'username instead of an email address, so we can\'t send an '
                'automatic reset link. Please contact the '
                '${AppConstants.cooperativeName} office for password '
                'assistance.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppConstants.onSurfaceVariant,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 20),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
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
                    const Icon(
                      Icons.location_on_outlined,
                      color: AppConstants.primaryGreen,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppConstants.cooperativeLocation,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppConstants.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'Option 1 — Contact SP3 Office',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.phone_outlined,
                    color: AppConstants.primaryGreen,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '#0000000',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppConstants.onSurface,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Text(
                'Option 2 — Request Password Assistance',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'If you cannot remember your password, you may send a '
                'temporary-password assistance request to the SP3 Admin.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppConstants.onSurfaceVariant,
                  height: 1.4,
                ),
              ),

              if (_requestSent) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppConstants.successGreen.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Text(
                    'Request sent. An SP3 Admin will assist you.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppConstants.successGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],

              if (!_hasUsername) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: AppConstants.errorRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Please enter your username on the login screen first.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppConstants.errorRed,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.popRoute(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed:
                          (_isSubmitting || _requestSent || !_hasUsername)
                          ? null
                          : _handleRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              _requestSent
                                  ? 'Request Sent'
                                  : 'Request Temporary Password',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleRequest() async {
    if (widget.username.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      await AuthService.requestPasswordAssistance(widget.username);
    } catch (_) {
      // Deliberately no error surfaced here either — see the RPC's
      // enumeration-safety note. Whether it's a network hiccup or the
      // username not existing, the person sees the same outcome.
    }
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _requestSent = true;
    });
  }
}
