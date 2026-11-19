import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthWeakPasswordException;
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';

/// The one password rule enforced app-wide, for every role (Buyer, Farmer, Manager, Officer)
/// wherever a password is CHOSEN: at least 8 characters, with at least one uppercase letter,
/// one number and one special character (anything that is not a letter, digit or space).
/// (Signing in is not checked against this rule, so existing accounts keep working.)
bool isPasswordValid(String value) =>
    value.length >= 8 &&
    RegExp(r'[A-Z]').hasMatch(value) &&
    RegExp(r'[0-9]').hasMatch(value) &&
    RegExp(r'[^A-Za-z0-9\s]').hasMatch(value);

/// What to tell the person when the server refused a new password (HTTP 422 from
/// Supabase Auth: the same password again, or one its own policy calls weak), or
/// when the reset session is no longer valid. Null for any other failure, so the
/// caller keeps its generic message.
String? passwordUpdateErrorMessage(Object error, AppLocalizations l10n) {
  if (error is AuthWeakPasswordException) {
    return error.reasons.contains('pwned')
        ? l10n.passwordErrBreached
        : l10n.passwordErrWeak;
  }
  if (error is AuthException) {
    switch (error.code) {
      case 'same_password':
        return l10n.passwordErrSame;
      case 'weak_password':
        return l10n.passwordErrWeak;
      case 'session_not_found':
      case 'session_expired':
      case 'reauthentication_needed':
      case 'refresh_token_not_found':
        return l10n.passwordErrExpired;
    }
    if (error.statusCode == '401' || error.statusCode == '403') {
      return l10n.passwordErrExpired;
    }
  }
  return null;
}

/// Form-field validator for the password rule (length, uppercase, number, special character). Shared by every
/// screen where a user chooses their own new password — Register
/// (Farmer/Buyer), the OTP "Forgot Password" reset flow, the forced
/// password-change screen after an admin-issued temporary password, and
/// the in-app Change Password dialog — so the rule and its wording can
/// never drift apart between screens.
String? validatePasswordMinLength(String? value, AppLocalizations l10n) {
  final v = value ?? '';
  if (v.isEmpty) return l10n.passwordRequired;
  if (!isPasswordValid(v)) return l10n.passwordRequirements;
  return null;
}

/// Small, unobtrusive dynamic hint shown directly below a password field —
/// not a permanent checklist. Shows nothing before the user starts typing
/// and once the 8-character minimum is met; shows a brief amber warning
/// while it isn't.
class PasswordLengthHint extends StatelessWidget {
  final String password;
  const PasswordLengthHint({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    final showWarning = password.isNotEmpty && !isPasswordValid(password);
    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      alignment: Alignment.topCenter,
      child: showWarning
          ? Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: AppConstants.warningAmber),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      AppLocalizations.of(context).passwordRequirements,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: AppConstants.warningAmber,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity, height: 0),
    );
  }
}
