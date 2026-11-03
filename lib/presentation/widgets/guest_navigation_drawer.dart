import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../core/utils/navigation_utils.dart';
import '../../data/services/guest_mode_service.dart';
import '../../routes/app_routes.dart';
import 'guest_prompt.dart';
import 'shared_widgets.dart';

/// The navigation drawer of a signed-out guest. It has no profile and no
/// account actions: just Login / Register, a way to switch exploration mode,
/// the shared Support & Info pages, and a way back to Welcome.
class GuestNavigationDrawer extends StatelessWidget {
  final GuestRole role;

  const GuestNavigationDrawer({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final isBuyer = role == GuestRole.buyer;

    void closeThen(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    const pad = EdgeInsets.symmetric(horizontal: 16, vertical: 4);

    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: sagana.scaffoldBackground,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(AppConstants.radiusLg),
              bottomRight: Radius.circular(AppConstants.radiusLg),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(6, 0),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  16,
                  22 + MediaQuery.of(context).padding.top,
                  16,
                  20,
                ),
                decoration: const BoxDecoration(
                  gradient: AppConstants.primaryButtonGradient,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(AppConstants.radiusLg),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.guestName,
                            style: GoogleFonts.poppins(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            isBuyer
                                ? l10n.guestExploreAsBuyer
                                : l10n.guestExploreAsFarmer,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      SettingsCard(
                        children: [
                          SettingsRow(
                            icon: Icons.login_rounded,
                            iconColor: AppConstants.primaryGreen,
                            title: l10n.guestLogin,
                            contentPadding: pad,
                            onTap: () => closeThen(
                              () => goToGuestLogin(context),
                            ),
                          ),
                          const SettingsDivider(),
                          SettingsRow(
                            icon: Icons.person_add_alt_1_rounded,
                            iconColor: AppConstants.primaryGreen,
                            title: l10n.guestRegister,
                            contentPadding: pad,
                            onTap: () => closeThen(
                              () => goToGuestRegister(context),
                            ),
                          ),
                          const SettingsDivider(),
                          SettingsRow(
                            icon: Icons.swap_horiz_rounded,
                            iconColor: AppConstants.buyerBlue,
                            title: isBuyer
                                ? l10n.guestSwitchToFarmer
                                : l10n.guestSwitchToBuyer,
                            contentPadding: pad,
                            onTap: () => closeThen(
                              () => switchGuestMode(
                                context,
                                isBuyer ? GuestRole.farmer : GuestRole.buyer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SettingsCard(
                        children: [
                          SettingsRow(
                            icon: Icons.info_outline_rounded,
                            iconColor: AppConstants.primaryGreen,
                            title: l10n.aboutSagana,
                            contentPadding: pad,
                            onTap: () => context.pushRoute(AppRoutes.aboutSagana),
                          ),
                          const SettingsDivider(),
                          SettingsRow(
                            icon: Icons.support_agent_rounded,
                            iconColor: AppConstants.buyerBlue,
                            title: l10n.aboutCooperative,
                            contentPadding: pad,
                            onTap: () =>
                                context.pushRoute(AppRoutes.aboutCooperative),
                          ),
                          const SettingsDivider(),
                          SettingsRow(
                            icon: Icons.privacy_tip_outlined,
                            iconColor: AppConstants.amber,
                            title: l10n.privacyPolicy,
                            contentPadding: pad,
                            onTap: () =>
                                context.pushRoute(AppRoutes.privacyPolicy),
                          ),
                          const SettingsDivider(),
                          SettingsRow(
                            icon: Icons.gavel_rounded,
                            iconColor: AppConstants.onSurfaceVariant,
                            title: l10n.termsOfUse,
                            contentPadding: pad,
                            onTap: () =>
                                context.pushRoute(AppRoutes.termsOfUse),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SettingsCard(
                        children: [
                          SettingsRow(
                            icon: Icons.arrow_back_rounded,
                            iconColor: AppConstants.onSurfaceVariant,
                            title: l10n.guestBackToWelcome,
                            showChevron: false,
                            contentPadding: pad,
                            onTap: () => closeThen(() => backToWelcome(context)),
                          ),
                        ],
                      ),
                    ],
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
