import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/animations/staggered_entrance.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../data/services/guest_mode_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/auth_visuals.dart';

/// The public front door: shown whenever there is no signed-in session.
/// Choosing an Explore option starts Guest Mode (in memory only); Login goes to
/// the normal Login screen, which Manager and Officer accounts also use.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _explore(BuildContext context, GuestRole role) {
    GuestModeService.instance.enter(role);
    context.go(
      role == GuestRole.buyer
          ? AppRoutes.marketplaceBrowse
          : AppRoutes.farmerDashboard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Stack(
        children: [
          const AuthBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingSafeH,
                  vertical: AppConstants.spacingSectionV,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight -
                            2 * AppConstants.spacingSectionV)
                        .clamp(0, double.infinity),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      StaggeredEntrance(
                        index: 0,
                        child: Column(
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppConstants.primaryGreen
                                        .withValues(alpha: 0.18),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Image.asset(
                                'assets/images/sagana_icon.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              AppConstants.appName,
                              style: GoogleFonts.poppins(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 6,
                                color: AppConstants.primaryGreen,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              l10n.guestWelcomeTitle,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.guestWelcomeSubtitle,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: AppConstants.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      StaggeredEntrance(
                        index: 1,
                        child: AuthGlassCard(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              _ExploreOption(
                                icon: Icons.storefront_rounded,
                                title: l10n.guestExploreAsBuyer,
                                hint: l10n.guestExploreAsBuyerHint,
                                onTap: () =>
                                    _explore(context, GuestRole.buyer),
                              ),
                              const SizedBox(height: 12),
                              _ExploreOption(
                                icon: Icons.agriculture_rounded,
                                title: l10n.guestExploreAsFarmer,
                                hint: l10n.guestExploreAsFarmerHint,
                                onTap: () =>
                                    _explore(context, GuestRole.farmer),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      StaggeredEntrance(
                        index: 2,
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              l10n.guestAlreadyHaveAccount,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppConstants.onSurfaceVariant,
                              ),
                            ),
                            TextButton(
                              onPressed: () => context.push(AppRoutes.login),
                              child: Text(
                                l10n.guestLogin,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  color: AppConstants.primaryGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  const _ExploreOption({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Icon(icon, color: AppConstants.primaryGreen),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppConstants.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppConstants.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
