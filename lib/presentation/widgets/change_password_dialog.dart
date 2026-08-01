import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/auth_service.dart';
import '../../routes/app_routes.dart';
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
  const ChangePasswordDialog({super.key});

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
    setState(() => _error = null);

    if (_currentController.text.isEmpty) {
      setState(() => _error = 'Current password is required.');
      return;
    }
    if (_newController.text.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters.');
      return;
    }
    if (_newController.text != _confirmController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _repository.changePassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated. Signing you out…'), backgroundColor: AppConstants.successGreen),
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
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Change Password', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              AppTextField(controller: _currentController, label: 'Current Password', isPassword: true),
              const SizedBox(height: 12),
              AppTextField(controller: _newController, label: 'New Password', isPassword: true),
              const SizedBox(height: 12),
              AppTextField(controller: _confirmController, label: 'Confirm New Password', isPassword: true),
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
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PrimaryButton(label: 'Update', height: 44, isLoading: _isSubmitting, onPressed: _submit),
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