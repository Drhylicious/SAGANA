import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/services/guest_mode_service.dart';
import '../../routes/app_routes.dart';
import 'app_dialog.dart';
import 'shared_widgets.dart';

/// Opens Login / Register above the current guest screen. Backing out returns to
/// where the guest was; a successful login replaces the whole stack.
void goToGuestLogin(BuildContext context) =>
    GoRouter.of(context).push(AppRoutes.login);

void goToGuestRegister(BuildContext context) =>
    GoRouter.of(context).push(AppRoutes.register);

/// Leaves guest exploration and returns to the Welcome screen.
void backToWelcome(BuildContext context) {
  GuestModeService.instance.exit();
  GoRouter.of(context).go(AppRoutes.welcome);
}

/// Switches between Explore as Buyer and Explore as Farmer without signing in.
void switchGuestMode(BuildContext context, GuestRole role) {
  GuestModeService.instance.enter(role);
  GoRouter.of(context).go(
    role == GuestRole.buyer
        ? AppRoutes.marketplaceBrowse
        : AppRoutes.farmerDashboard,
  );
}

enum _PromptChoice { login, register }

/// The contextual "log in or create an account" prompt a guest sees when they
/// try an action that needs an account. Every prompt offers Login, Register and
/// a way to carry on ([continueLabel]). Nothing is created or saved.
Future<void> showGuestPrompt(
  BuildContext context, {
  required String title,
  required String message,
  required String continueLabel,
  IconData icon = Icons.lock_outline_rounded,
}) async {
  final choice = await AppDialog.show<_PromptChoice>(
    context: context,
    child: _GuestPromptDialog(
      title: title,
      message: message,
      continueLabel: continueLabel,
      icon: icon,
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == _PromptChoice.login) {
    goToGuestLogin(context);
  } else {
    goToGuestRegister(context);
  }
}

/// Convenience wrappers so call sites state intent, not strings.
extension GuestPrompts on BuildContext {
  Future<void> promptBuyer(
    String Function(AppLocalizations l) title,
    String Function(AppLocalizations l) message, {
    IconData icon = Icons.lock_outline_rounded,
  }) {
    final l10n = AppLocalizations.of(this);
    return showGuestPrompt(
      this,
      title: title(l10n),
      message: message(l10n),
      continueLabel: l10n.guestContinueBrowsing,
      icon: icon,
    );
  }

  Future<void> promptFarmer(
    String Function(AppLocalizations l) title,
    String Function(AppLocalizations l) message, {
    IconData icon = Icons.lock_outline_rounded,
  }) {
    final l10n = AppLocalizations.of(this);
    return showGuestPrompt(
      this,
      title: title(l10n),
      message: message(l10n),
      continueLabel: l10n.guestContinueExploring,
      icon: icon,
    );
  }

  /// Picks the "Continue Browsing" / "Continue Exploring" wording from the mode.
  Future<void> promptGuest(
    String Function(AppLocalizations l) title,
    String Function(AppLocalizations l) message, {
    IconData icon = Icons.lock_outline_rounded,
  }) => GuestModeService.instance.role == GuestRole.farmer
      ? promptFarmer(title, message, icon: icon)
      : promptBuyer(title, message, icon: icon);
}

class _GuestPromptDialog extends StatelessWidget {
  final String title;
  final String message;
  final String continueLabel;
  final IconData icon;

  const _GuestPromptDialog({
    required this.title,
    required this.message,
    required this.continueLabel,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppConstants.primaryGreen, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.5,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: l10n.guestLogin,
                height: 48,
                onPressed: () => Navigator.pop(context, _PromptChoice.login),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, _PromptChoice.register),
                  child: Text(l10n.guestRegister),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  continueLabel,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: AppConstants.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Login + Register buttons used by the Guest Profile and the Orders empty state.
class GuestAuthButtons extends StatelessWidget {
  const GuestAuthButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        PrimaryButton(
          label: l10n.guestLogin,
          onPressed: () => goToGuestLogin(context),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: () => goToGuestRegister(context),
            child: Text(l10n.guestRegister),
          ),
        ),
      ],
    );
  }
}

/// The strip shown at the top of every Explore-as-Farmer screen so sample
/// figures are never mistaken for real records.
class GuestSampleBanner extends StatelessWidget {
  const GuestSampleBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppConstants.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppConstants.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppConstants.amber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.guestSampleBanner,
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.4,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
