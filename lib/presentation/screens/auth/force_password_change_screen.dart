import '../../../core/theme/sagana_colors.dart';
import '../../../core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/password_requirements.dart';
import '../../widgets/set_password_form.dart';

/// Forced stop after logging in with an admin-issued temporary password
/// (see AccountManagementRepository.resetUserPassword). Unlike
/// ResetPasswordScreen, the user arriving here is already properly
/// authenticated — this isn't a recovery session — so a successful submit
/// proceeds straight into the app instead of logging out to the login screen.
class ForcePasswordChangeScreen extends StatefulWidget {
  const ForcePasswordChangeScreen({super.key});

  @override
  State<ForcePasswordChangeScreen> createState() =>
      _ForcePasswordChangeScreenState();
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
      // The password the reset replaced cannot come back; the temporary one is
      // refused by the server (shown the same way, inline under the fields).
      if (await AuthService.newPasswordMatchesPrevious(_passwordController.text)) {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _formError = AppLocalizations.of(context).passwordErrPrevious;
        });
        return;
      }
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
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _isSaving = false;
        _formError =
            passwordUpdateErrorMessage(e, l10n) ??
            l10n.enhCouldNotUpdateYourPasswordPleaseTryAgain;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
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
                subtitle: AppLocalizations.of(
                  context,
                ).enhYourPasswordWasResetByAManagerPlease,
                submitLabel: AppLocalizations.of(
                  context,
                ).marketLinkCelebrationContinue,
                onToggleObscurePassword: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                onToggleObscureConfirm: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                onSubmit: _handleSubmit,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
