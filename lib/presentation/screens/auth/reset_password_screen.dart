import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/services/auth_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/set_password_form.dart';

/// Lands here after a user requests a password reset from the Login
/// screen's "Forgot Password" flow (see login_screen.dart —
/// _showAdminResetSheet). Route: /reset-password (see app_routes.dart /
/// app_router.dart).
///
/// Uses a manually-entered 6-digit OTP code instead of a clickable email
/// link. A clickable link requires the PKCE code_verifier to still be
/// present in the local storage of whichever browser/device completes the
/// exchange, which fails whenever the reset is requested and confirmed on
/// different devices or browsers — normal behavior for email, not an edge
/// case, so a link never worked reliably here. See AuthService for the
/// verifyOTP call this screen relies on.
class ResetPasswordScreen extends StatefulWidget {
  final String email;

  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

enum _ResetStage { enterCode, ready, success }

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _codeFormKey = GlobalKey<FormState>();
  final _formKey = GlobalKey<FormState>();

  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _ResetStage _stage = _ResetStage.enterCode;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isVerifying = false;
  bool _isResending = false;
  bool _isSaving = false;
  String? _codeError;
  String? _formError;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleVerifyCode() async {
    if (!_codeFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isVerifying = true;
      _codeError = null;
    });
    try {
      await AuthService.verifyPasswordResetOtp(
        email: widget.email,
        token: _codeController.text,
      );
      if (!mounted) return;
      setState(() => _stage = _ResetStage.ready);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _codeError =
            'Incorrect or expired code. Please try again or request a new one.';
      });
    }
  }

  Future<void> _handleResend() async {
    setState(() => _isResending = true);
    try {
      await AuthService.sendPasswordReset(widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A new code was sent to ${widget.email}',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          backgroundColor: AppConstants.successGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not resend right now. Please try again shortly.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          backgroundColor: AppConstants.errorRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
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
      await AuthService.logout();
      if (!mounted) return;
      setState(() => _stage = _ResetStage.success);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _formError = 'Could not update your password. Please try again.';
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
      case _ResetStage.enterCode:
        return _EnterCodeForm(
          email: widget.email,
          formKey: _codeFormKey,
          codeController: _codeController,
          isVerifying: _isVerifying,
          isResending: _isResending,
          errorMessage: _codeError,
          onSubmit: _handleVerifyCode,
          onResend: _handleResend,
        );
      case _ResetStage.ready:
        return SetPasswordForm(
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
// Enter code
// ─────────────────────────────────────────────────────────────────────────────

class _EnterCodeForm extends StatelessWidget {
  final String email;
  final GlobalKey<FormState> formKey;
  final TextEditingController codeController;
  final bool isVerifying;
  final bool isResending;
  final String? errorMessage;
  final VoidCallback onSubmit;
  final VoidCallback onResend;

  const _EnterCodeForm({
    required this.email,
    required this.formKey,
    required this.codeController,
    required this.isVerifying,
    required this.isResending,
    required this.errorMessage,
    required this.onSubmit,
    required this.onResend,
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
              Icons.mark_email_read_outlined,
              size: 40,
              color: AppConstants.primaryGreen,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Enter Reset Code',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppConstants.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We sent a code to $email.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: codeController,
            keyboardType: TextInputType.number,
            maxLength: 12, // generous ceiling only — not an assumed exact length
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 20, letterSpacing: 4, fontWeight: FontWeight.w600),
            decoration: resetFieldDecoration(hint: 'Enter code', icon: Icons.password_rounded).copyWith(
              counterText: '',
            ),
            validator: (v) {
              final trimmed = v?.trim() ?? '';
              if (trimmed.isEmpty) return 'Enter the code we sent you';
              if (!RegExp(r'^\d+$').hasMatch(trimmed)) {
                return 'Code should contain numbers only';
              }
              return null;
            },
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: isVerifying ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: isVerifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Verify Code',
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: isResending ? null : onResend,
            child: Text(
              isResending ? 'Sending...' : "Didn't get a code? Resend",
              style: GoogleFonts.inter(fontSize: 13, color: AppConstants.primaryGreen),
            ),
          ),
        ],
      ),
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