import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/set_password_form.dart';

/// Forced stop after logging in with an admin-issued temporary password
/// (see AccountManagementRepository.resetUserPassword). Unlike
/// ResetPasswordScreen, the user arriving here is already properly
/// authenticated — this isn't a recovery session — so a successful submit
/// proceeds straight into the app instead of logging out to the login screen.
class ForcePasswordChangeScreen extends StatefulWidget {
  const ForcePasswordChangeScreen({super.key});

  @override
  State<ForcePasswordChangeScreen> createState() => _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends State<ForcePasswordChangeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;
  String? _formError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
      _formError = null;
    });
    try {
      await AuthService.changePassword(_passwordController.text);
      await AuthService.clearMustChangePassword();
      if (!mounted) return;

      final role = HiveService.getUserRole();
      switch (role) {
        case AppConstants.roleAdmin:
        case 'officer':
          context.go(AppRoutes.adminDashboard);
          break;
        case AppConstants.roleBuyer:
          context.go(AppRoutes.buyerBrowse);
          break;
        default:
          context.go(AppRoutes.farmerDashboard);
      }
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
            child: SingleChildScrollView(
              child: SetPasswordForm(
                formKey: _formKey,
                passwordController: _passwordController,
                confirmController: _confirmController,
                obscurePassword: _obscurePassword,
                obscureConfirm: _obscureConfirm,
                isSaving: _isSaving,
                errorMessage: _formError,
                subtitle: 'Your password was reset by an Admin. Please choose a new one to continue.',
                submitLabel: 'Continue',
                onToggleObscurePassword: () => setState(() => _obscurePassword = !_obscurePassword),
                onToggleObscureConfirm: () => setState(() => _obscureConfirm = !_obscureConfirm),
                onSubmit: _handleSubmit,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
