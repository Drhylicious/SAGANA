import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';

/// Shared "choose a new password" form — used by both the OTP-based reset
/// flow (ResetPasswordScreen) and the forced-password-change flow after an
/// admin-issued temporary password (ForcePasswordChangeScreen). Previously
/// private to reset_password_screen.dart as _SetPasswordForm; extracted
/// here rather than duplicated once a second caller needed it.
class SetPasswordForm extends StatelessWidget {
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
  final String title;
  final String subtitle;
  final String submitLabel;

  const SetPasswordForm({
    super.key,
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
    this.title = 'Set a New Password',
    this.subtitle = 'Choose a new password for your SAGANA account.',
    this.submitLabel = 'Update Password',
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
            child: const Icon(Icons.lock_reset_rounded, size: 40, color: AppConstants.primaryGreen),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppConstants.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: passwordController,
            obscureText: obscurePassword,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: resetFieldDecoration(
              hint: 'New password',
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20, color: AppConstants.outline),
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
            decoration: resetFieldDecoration(
              hint: 'Confirm new password',
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20, color: AppConstants.outline),
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
            Text(errorMessage!, style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed)),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: isSaving ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                    )
                  : Text(submitLabel, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration resetFieldDecoration({required String hint, required IconData icon, Widget? suffix}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.inter(fontSize: 14, color: AppConstants.outline.withValues(alpha: 0.50)),
    filled: true,
    fillColor: Colors.white,
    prefixIcon: Icon(icon, size: 20, color: AppConstants.outline),
    suffixIcon: suffix,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusLg), borderSide: BorderSide(color: AppConstants.outline.withValues(alpha: 0.20))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusLg), borderSide: BorderSide(color: AppConstants.outline.withValues(alpha: 0.20))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusLg), borderSide: const BorderSide(color: AppConstants.primaryGreen, width: 2)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusLg), borderSide: const BorderSide(color: AppConstants.errorRed)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusLg), borderSide: const BorderSide(color: AppConstants.errorRed, width: 2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}
