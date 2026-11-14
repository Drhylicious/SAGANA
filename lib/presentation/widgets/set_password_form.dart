import '../../core/l10n/localized_labels.dart';
import '../../core/theme/sagana_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import 'password_requirements.dart';

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
  final String? title;
  final String? subtitle;
  final String? submitLabel;

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
    this.title,
    this.subtitle,
    this.submitLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            child: Icon(
              Icons.lock_reset_rounded,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title ?? l10n.enhSetNewPasswordTitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle ?? l10n.enhSetNewPasswordBody,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: passwordController,
            obscureText: obscurePassword,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: resetFieldDecoration(
              context: context,
              hint: AppLocalizations.of(context).enhNewPassword,
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.outline,
                ),
                onPressed: onToggleObscurePassword,
              ),
            ),
            validator: (v) => validatePasswordMinLength(v, l10n),
          ),
          // Dynamic hint — bound directly to the controller so it updates
          // on every keystroke without the parent screens needing their
          // own setState wiring for it.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: passwordController,
            builder: (_, value, __) => PasswordLengthHint(password: value.text),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: confirmController,
            obscureText: obscureConfirm,
            style: GoogleFonts.inter(fontSize: 14),
            decoration: resetFieldDecoration(
              context: context,
              hint: AppLocalizations.of(context).enhConfirmNewPassword,
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(
                  obscureConfirm
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.outline,
                ),
                onPressed: onToggleObscureConfirm,
              ),
            ),
            validator: (v) {
              if (v != passwordController.text) {
                return AppLocalizations.of(context).registerPasswordMismatch;
              }
              return null;
            },
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              errorMessage!,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppConstants.errorRed,
              ),
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
                      localizeBuiltinLabel(
                        AppLocalizations.of(context),
                        submitLabel ?? l10n.updatePassword,
                      ),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration resetFieldDecoration({
  required BuildContext context,
  required String hint,
  required IconData icon,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.inter(
      fontSize: 14,
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.50),
    ),
    filled: true,
    fillColor: context.saganaColors.cardBackground,
    prefixIcon: Icon(
      icon,
      size: 20,
      color: Theme.of(context).colorScheme.outline,
    ),
    suffixIcon: suffix,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.20),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.20),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.primary,
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
