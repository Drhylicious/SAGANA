import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/auth_service.dart';
import '../../../routes/app_routes.dart';

/// Lands here after an admin taps the "reset password" link from their
/// email. Route: /reset-password (see app_routes.dart / app_router.dart).
///
/// Two distinct ways to arrive:
///
/// 1. Supabase successfully validated the token and exchanged it for a
///    real (temporary) session — supabase_flutter does this exchange
///    automatically during app init (PKCE flow, detectSessionInUri).
///    We detect it via onAuthStateChange's `AuthChangeEvent.passwordRecovery`
///    and show the "set a new password" form.
/// 2. The token was invalid, already used, or expired — Supabase appends
///    error/error_code/error_description query params to the redirect
///    instead of establishing a session. Those are read directly from the
///    URL by the router and passed in here, so we can show a clear
///    explanation immediately instead of spinning forever.
class ResetPasswordScreen extends StatefulWidget {
  final String? errorCode;
  final String? errorDescription;

  const ResetPasswordScreen({
    super.key,
    this.errorCode,
    this.errorDescription,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

enum _ResetStage { waiting, expired, ready, success }

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  StreamSubscription<AuthState>? _authSub;
  Timer? _timeoutTimer;

  _ResetStage _stage = _ResetStage.waiting;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;
  String? _formError;

  @override
  void initState() {
    super.initState();

    // The link itself already came back as an error — no need to wait for
    // anything, Supabase never established a session for this click.
    if (widget.errorCode != null) {
      _stage = _ResetStage.expired;
      return;
    }

    // A session may already be live by the time this screen builds
    // (Supabase's code-exchange runs during app init), or it may arrive a
    // moment later via the auth stream — listen for both rather than
    // assuming either timing.
    if (AuthService.currentUser != null) {
      _stage = _ResetStage.ready;
    } else {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (!mounted) return;
        if (data.event == AuthChangeEvent.passwordRecovery ||
            (data.event == AuthChangeEvent.signedIn && data.session != null)) {
          setState(() => _stage = _ResetStage.ready);
        }
      });

      // If nothing arrives within a few seconds, the link was almost
      // certainly already consumed — a very common real-world cause is
      // corporate email security scanners "clicking" links to scan them
      // before the real user does, silently burning the one-time token.
      // Don't leave the admin staring at a spinner forever.
      _timeoutTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && _stage == _ResetStage.waiting) {
          setState(() => _stage = _ResetStage.expired);
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _timeoutTimer?.cancel();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
      _formError = null;
    });

    try {
      await AuthService.changePassword(_passwordController.text);
      // Force a clean re-login with the new password rather than leaving
      // the temporary recovery session active.
      await AuthService.logout();
      if (!mounted) return;
      setState(() => _stage = _ResetStage.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _formError = 'Could not update your password. Please try again.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Center(
            child: SingleChildScrollView(child: _buildStage()),
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    switch (_stage) {
      case _ResetStage.waiting:
        return const _WaitingView();
      case _ResetStage.expired:
        return _ExpiredView(description: widget.errorDescription);
      case _ResetStage.ready:
        return _SetPasswordForm(
          formKey: _formKey,
          passwordController: _passwordController,
          confirmController: _confirmController,
          obscurePassword: _obscurePassword,
          obscureConfirm: _obscureConfirm,
          isSaving: _isSaving,
          errorMessage: _formError,
          onToggleObscurePassword: () =>
              setState(() => _obscurePassword = !_obscurePassword),
          onToggleObscureConfirm: () =>
              setState(() => _obscureConfirm = !_obscureConfirm),
          onSubmit: _handleSetPassword,
        );
      case _ResetStage.success:
        return const _SuccessView();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Waiting
// ─────────────────────────────────────────────────────────────────────────────

class _WaitingView extends StatelessWidget {
  const _WaitingView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: AppConstants.primaryGreen),
        const SizedBox(height: 20),
        Text(
          'Verifying your reset link...',
          style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expired / invalid
// ─────────────────────────────────────────────────────────────────────────────

class _ExpiredView extends StatelessWidget {
  final String? description;
  const _ExpiredView({this.description});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: AppConstants.errorRed.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.link_off_rounded,
            size: 40,
            color: AppConstants.errorRed,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Link Expired or Already Used',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppConstants.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Password reset links can only be used once, and expire shortly '
          'after they\'re sent. This can also happen if your email provider '
          'automatically scans links before you open them.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppConstants.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => context.go(AppRoutes.login),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            child: Text(
              'Back to Login',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'You can request a new reset link from the login screen.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 12, color: AppConstants.outline),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Set new password
// ─────────────────────────────────────────────────────────────────────────────

class _SetPasswordForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool obscurePassword;
  final bool obscureConfirm;
  final bool isSaving;
  final String? errorMessage;
  final VoidCallback onToggleObscurePassword;
  final VoidCallback onToggleObscureConfirm;
  final VoidCallback onSubmit;

  const _SetPasswordForm({
    required this.formKey,
    required this.passwordController,
    required this.confirmController,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.isSaving,
    required this.errorMessage,
    required this.onToggleObscurePassword,
    required this.onToggleObscureConfirm,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_reset_rounded,
              size: 40,
              color: AppConstants.primaryGreen,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Set a New Password',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppConstants.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a new password for your SAGANA admin account.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: passwordController,
            obscureText: obscurePassword,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: _decoration(
              hint: 'New password',
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(
                  obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  size: 20,
                  color: AppConstants.outline,
                ),
                onPressed: onToggleObscurePassword,
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please enter a new password';
              if (v.length < 8) return 'Password must be at least 8 characters';
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: confirmController,
            obscureText: obscureConfirm,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: _decoration(
              hint: 'Confirm new password',
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(
                  obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  size: 20,
                  color: AppConstants.outline,
                ),
                onPressed: onToggleObscureConfirm,
              ),
            ),
            validator: (v) {
              if (v != passwordController.text) return 'Passwords do not match';
              return null;
            },
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              errorMessage!,
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: isSaving ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Update Password',
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 14, color: AppConstants.outline.withValues(alpha: 0.50)),
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Icon(icon, size: 20, color: AppConstants.outline),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        borderSide: BorderSide(color: AppConstants.outline.withValues(alpha: 0.20)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        borderSide: BorderSide(color: AppConstants.outline.withValues(alpha: 0.20)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        borderSide: const BorderSide(color: AppConstants.primaryGreen, width: 2),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Success
// ─────────────────────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  const _SuccessView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: AppConstants.successGreen.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            size: 40,
            color: AppConstants.successGreen,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Password Updated',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppConstants.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Please log in with your new password.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => context.go(AppRoutes.login),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            child: Text(
              'Back to Login',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
