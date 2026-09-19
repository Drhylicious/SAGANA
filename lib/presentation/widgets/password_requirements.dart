import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';

/// The one password rule enforced app-wide: a minimum of 8 characters.
/// Deliberately not a multi-rule strength policy (uppercase/number/symbol
/// etc.) — that was tried and explicitly rejected as unnecessarily
/// restrictive for this project.
bool isPasswordValid(String value) => value.length >= 8;

/// Form-field validator for the minimum-length rule. Shared by every
/// screen where a user chooses their own new password — Register
/// (Farmer/Buyer), the OTP "Forgot Password" reset flow, the forced
/// password-change screen after an admin-issued temporary password, and
/// the in-app Change Password dialog — so the rule and its wording can
/// never drift apart between screens.
String? validatePasswordMinLength(String? value, AppLocalizations l10n) {
  final v = value ?? '';
  if (v.isEmpty) return l10n.passwordRequired;
  if (!isPasswordValid(v)) return l10n.passwordMinLength;
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
                      AppLocalizations.of(context).passwordMinLength,
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
