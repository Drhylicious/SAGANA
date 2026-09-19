import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/auth_service.dart';
import '../../routes/app_routes.dart';
import 'password_requirements.dart';
import 'shared_widgets.dart';

/// Shared Change Password flow for all three roles — replaces Buyer's
/// private _ChangePasswordDialog and Admin's _showChangePasswordSheet
/// bottom sheet (Farmer's equivalent, if present, folds in here too).
/// Opened via AppDialog.show(child: const ChangePasswordDialog()).
///
/// Always logs the user out and returns to Login after a successful
/// change — Supabase invalidates the session at the Auth level when a
/// password changes, so this keeps the client behavior consistent with
/// that rather than trying to keep a stale session alive.
class ChangePasswordDialog extends StatefulWidget {
  // Optional hook, called right after a successful password change and
  // before the sign-out delay. Existing callers (Admin, Buyer) that don't
  // pass this see no behavior change at all.
  final VoidCallback? onSuccess;

  const ChangePasswordDialog({super.key, this.onSuccess});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _repository = SettingsRepository();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = null);

    if (_currentController.text.isEmpty) {
      setState(() => _error = l10n.currentPasswordRequired);
      return;
    }
    if (!isPasswordValid(_newController.text)) {
      setState(() => _error = l10n.passwordMinLength);
      return;
    }
    if (_newController.text != _confirmController.text) {
      setState(() => _error = l10n.passwordsDoNotMatch);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _repository.changePassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      widget.onSuccess?.call();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.passwordUpdatedSigningOut), backgroundColor: AppConstants.successGreen),
      );
      await Future.delayed(const Duration(seconds: 2));
      await AuthService.logout();
      if (mounted) context.go(AppRoutes.login);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = AuthService.parseAuthError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: sagana.cardBackground, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.changePassword, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              AppTextField(controller: _currentController, label: l10n.currentPassword, isPassword: true),
              const SizedBox(height: 12),
              AppTextField(controller: _newController, label: l10n.newPassword, isPassword: true),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _newController,
                builder: (_, value, __) => PasswordLengthHint(password: value.text),
              ),
              const SizedBox(height: 12),
              AppTextField(controller: _confirmController, label: l10n.confirmNewPassword, isPassword: true),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                      child: Text(l10n.issueLoanCancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PrimaryButton(label: l10n.updatePassword, height: 44, isLoading: _isSubmitting, onPressed: _submit),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}