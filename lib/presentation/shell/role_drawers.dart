import 'package:flutter/material.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/navigation_utils.dart';
import '../../data/models/buyer_profile_model.dart';
import '../../data/services/admin_profile_state_service.dart';
import '../../data/services/hive_service.dart';
import '../../data/services/profile_state_service.dart';
import '../../routes/app_routes.dart';
import '../widgets/admin_top_bar.dart';
import '../widgets/app_navigation_drawer.dart';
import '../widgets/buyer_top_bar.dart';
import '../widgets/farmer_top_bar.dart';

// The navigation drawer of each role, built once by its tab shell. Every primary
// tab of the role opens this same drawer (see ShellDrawerScope).

class FarmerShellDrawer extends StatelessWidget {
  const FarmerShellDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: FarmerProfileStateService.instance,
      builder: (context, _) {
        final profile = FarmerProfileStateService.instance.profile;
        return AppNavigationDrawer(
          photoUrl: profile?.profilePhotoUrl,
          displayName: profile?.fullName ?? l10n.defaultFarmerName,
          contactEmail: profile?.contactEmail,
          phoneNumber: profile?.phoneNumber,
          onEditProfile: () {
            Navigator.pop(context);
            context.pushRoute(AppRoutes.farmerEditProfile);
          },
          onEditFarmDetails: () {
            Navigator.pop(context);
            context.pushRoute(AppRoutes.editFarmDetails);
          },
          onMyAddresses: () {
            Navigator.pop(context);
            context.pushRoute(AppRoutes.myAddresses);
          },
          onSignOut: () => confirmFarmerSignOut(context),
          onAboutSagana: () => context.pushRoute(AppRoutes.aboutSagana),
          onAboutOrganization: () =>
              context.pushRoute(AppRoutes.aboutCooperative),
          onPrivacyPolicy: () => context.pushRoute(AppRoutes.privacyPolicy),
          onTermsOfUse: () => context.pushRoute(AppRoutes.termsOfUse),
        );
      },
    );
  }
}

/// Manager and Officer share the Admin shell, so they share this drawer.
class AdminShellDrawer extends StatelessWidget {
  const AdminShellDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AdminProfileStateService.instance,
      builder: (context, _) {
        final profile = AdminProfileStateService.instance.profile;
        return AppNavigationDrawer(
          photoUrl: profile?.profilePhotoUrl,
          displayName:
              profile?.fullName ??
              (HiveService.isOfficer ? 'Officer' : 'Manager'),
          contactEmail: profile?.contactEmail ?? profile?.email,
          phoneNumber: profile?.phoneNumber,
          onEditProfile: () {
            Navigator.pop(context);
            context.pushRoute(AppRoutes.adminEditProfile);
          },
          onSignOut: () => confirmAdminSignOut(context),
          onAboutSagana: () => context.pushRoute(AppRoutes.aboutSagana),
          onAboutOrganization: () =>
              context.pushRoute(AppRoutes.aboutCooperative),
          onPrivacyPolicy: () => context.pushRoute(AppRoutes.privacyPolicy),
          onTermsOfUse: () => context.pushRoute(AppRoutes.termsOfUse),
        );
      },
    );
  }
}

/// The Buyer has no shared profile state, so the shell loads the profile and
/// hands it in.
class BuyerShellDrawer extends StatelessWidget {
  final BuyerProfileModel? profile;

  const BuyerShellDrawer({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return AppNavigationDrawer(
      photoUrl: profile?.profilePhotoUrl,
      displayName: profile?.fullName ?? 'Buyer',
      contactEmail: profile?.contactEmail,
      phoneNumber: profile?.phoneNumber,
      onEditProfile: () {
        Navigator.pop(context);
        context.pushRoute(AppRoutes.buyerEditProfile);
      },
      onMyAddresses: () {
        Navigator.pop(context);
        context.pushRoute(AppRoutes.myAddresses);
      },
      onSignOut: () => confirmBuyerSignOut(context),
      onAboutSagana: () => context.pushRoute(AppRoutes.aboutSagana),
      onAboutOrganization: () => context.pushRoute(AppRoutes.aboutCooperative),
      onPrivacyPolicy: () => context.pushRoute(AppRoutes.privacyPolicy),
      onTermsOfUse: () => context.pushRoute(AppRoutes.termsOfUse),
    );
  }
}
