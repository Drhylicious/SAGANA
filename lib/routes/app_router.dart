import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/animations/app_page_transitions.dart';
import '../../core/l10n/app_localizations.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/register_screen.dart';
import '../../presentation/screens/farmer/add_crop_screen.dart';
import '../../presentation/screens/farmer/create_listing_screen.dart';
import '../../presentation/screens/farmer/crop_listing_screen.dart';
import '../../presentation/screens/farmer/edit_farm_details_screen.dart';
import '../../presentation/screens/farmer/farmer_analytics_screen.dart';
import '../../presentation/screens/farmer/farmer_dashboard_screen.dart';
import '../../presentation/screens/farmer/farmer_notifications_screen.dart';
import '../../presentation/screens/farmer/farmer_profile_screen.dart';
import '../../presentation/screens/farmer/farmer_recent_activity_screen.dart';
import '../../presentation/screens/farmer/farmer_settings_screen.dart';
import '../../presentation/screens/farmer/harvest_entry_form_screen.dart';
import '../../presentation/screens/farmer/harvest_history_screen.dart';
import '../../presentation/screens/farmer/harvest_hub_screen.dart';
import '../../presentation/screens/farmer/harvest_management_screen.dart';
import '../../presentation/screens/farmer/listing_success_screen.dart';
import '../../presentation/screens/farmer/manage_inventory_screen.dart';
import '../../presentation/screens/farmer/my_contribution_screen.dart';
import '../../presentation/screens/farmer/my_expenses_screen.dart';
import '../../presentation/screens/farmer/my_harvest_summary_screen.dart';
import '../../presentation/screens/farmer/my_listings_screen.dart';
import '../../presentation/screens/farmer/my_loans_screen.dart';
import '../../presentation/screens/admin/admin_dashboard_screen.dart';
import '../../presentation/screens/admin/price_management_screen.dart';
import '../../presentation/screens/admin/notification_broadcast_screen.dart';
import '../../presentation/screens/admin/supply_chain_map_screen.dart';
import '../../presentation/screens/admin/farmer_management_screen.dart';
import '../../presentation/screens/admin/farmer_details_screen.dart';
import '../../presentation/screens/admin/add_new_member_screen.dart';
import '../../presentation/screens/admin/pending_approvals_screen.dart';
import '../../presentation/screens/admin/all_listings_screen.dart';
import '../../presentation/screens/admin/listing_review_screen.dart';
import '../../presentation/screens/admin/market_linking_screen.dart';
import '../../presentation/screens/admin/buyer_management_screen.dart';
import '../../presentation/screens/splash_screen.dart';
import '../../presentation/shell/farmer_shell_screen.dart';
import '../../presentation/shell/admin_shell_screen.dart';
import '../../routes/app_routes.dart';

class AppRouter {
  AppRouter._();

  static final rootNavigatorKey = GlobalKey<NavigatorState>();

  // ── Farmer branch keys ─────────────────────────────────────────────────────
  static final homeNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'home');
  static final harvestNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'harvest');
  static final marketNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'market');
  static final analyticsNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'analytics');
  static final profileNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'profile');

  // ── Admin branch keys ──────────────────────────────────────────────────────
  static final adminDashboardKey =
      GlobalKey<NavigatorState>(debugLabel: 'adminDashboard');
  static final adminFarmersKey =
      GlobalKey<NavigatorState>(debugLabel: 'adminFarmers');
  static final adminListingsKey =
      GlobalKey<NavigatorState>(debugLabel: 'adminListings');
  static final adminLoansKey =
      GlobalKey<NavigatorState>(debugLabel: 'adminLoans');
  static final adminReportsKey =
      GlobalKey<NavigatorState>(debugLabel: 'adminReports');

  static GoRouter create() {
    return GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: AppRoutes.splash,
      routes: [

        // ── Auth ──────────────────────────────────────────────────────────────
        GoRoute(
          path: AppRoutes.splash,
          pageBuilder: (c, s) => AppPageTransitions.fadeThrough(
              key: s.pageKey, child: const SplashScreen()),
        ),
        GoRoute(
          path: AppRoutes.login,
          pageBuilder: (c, s) => AppPageTransitions.fadeThrough(
              key: s.pageKey, child: const LoginScreen()),
        ),
        GoRoute(
          path: AppRoutes.register,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey, child: const RegisterScreen()),
        ),

        // ── Farmer screens above shell ─────────────────────────────────────────
        GoRoute(
          path: AppRoutes.farmerSettings,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey, child: const FarmerSettingsScreen()),
        ),
        GoRoute(
          path: AppRoutes.editFarmDetails,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey, child: const EditFarmDetailsScreen()),
        ),
        GoRoute(
          path: AppRoutes.addCrop,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey, child: const AddCropScreen()),
        ),
        GoRoute(
          path: AppRoutes.harvestEntryForm,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: HarvestEntryFormScreen(crop: s.extra as dynamic)),
        ),
        GoRoute(
          path: AppRoutes.harvestManagement,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: HarvestManagementScreen(crop: s.extra as dynamic)),
        ),
        GoRoute(
          path: AppRoutes.createListing,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey, child: const CreateListingScreen()),
        ),
        GoRoute(
          path: AppRoutes.listingSuccess,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.scaleIn(
              key: s.pageKey, child: const ListingSuccessScreen()),
        ),
        GoRoute(
          path: AppRoutes.farmerNotifications,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey, child: const FarmerNotificationsScreen()),
        ),

        // ── Admin screens above shell ──────────────────────────────────────────
        GoRoute(
          path: AppRoutes.adminNotifications,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey, child: const FarmerNotificationsScreen()),
        ),
        GoRoute(
          path: AppRoutes.adminProfile,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const _ComingSoonScreen(routeName: AppRoutes.adminProfile)),
        ),
        GoRoute(
          path: AppRoutes.farmerDetails,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: FarmerDetailsScreen(farmerId: s.extra as String)),
        ),
        GoRoute(
          path: AppRoutes.addNewMember,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const AddNewMemberScreen()),
        ),
        GoRoute(
          path: AppRoutes.marketLinking,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const MarketLinkingScreen()),
        ),
        GoRoute(
          path: AppRoutes.listingReview,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: ListingReviewScreen(listingId: s.extra as String)),
        ),
        GoRoute(
          path: AppRoutes.allListings,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const AllListingsScreen()),
        ),
        GoRoute(
          path: AppRoutes.issueNewLoan,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const _ComingSoonScreen(routeName: AppRoutes.issueNewLoan)),
        ),
        GoRoute(
          path: AppRoutes.recordPayment,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const _ComingSoonScreen(routeName: AppRoutes.recordPayment)),
        ),
        GoRoute(
          path: AppRoutes.loanDetails,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const _ComingSoonScreen(routeName: AppRoutes.loanDetails)),
        ),
        GoRoute(
          path: AppRoutes.loanHistory,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const _ComingSoonScreen(routeName: AppRoutes.loanHistory)),
        ),
        GoRoute(
          path: AppRoutes.buyerManagement,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const BuyerManagementScreen()),
        ),
        GoRoute(
          path: AppRoutes.exportCenter,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const _ComingSoonScreen(routeName: AppRoutes.exportCenter)),
        ),
        GoRoute(
          path: AppRoutes.balikTangkilikManagement,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const _ComingSoonScreen(routeName: AppRoutes.balikTangkilikManagement)),
        ),
        GoRoute(
          path: AppRoutes.supplyChainMap,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.fadeThrough(
              key: s.pageKey,
              child: const SupplyChainMapScreen()),
        ),
        GoRoute(
          path: AppRoutes.announcementDashboard,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const NotificationBroadcastScreen()),
        ),
        GoRoute(
          path: AppRoutes.priceManagement,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const PriceManagementScreen()),
        ),
        GoRoute(
          path: AppRoutes.inventoryReport,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
              key: s.pageKey,
              child: const _ComingSoonScreen(routeName: AppRoutes.inventoryReport)),
        ),

        // ── Farmer StatefulShellRoute ──────────────────────────────────────────
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              FarmerShellScreen(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              navigatorKey: homeNavigatorKey,
              routes: [
                GoRoute(
                  path: AppRoutes.farmerDashboard,
                  pageBuilder: (c, s) => NoTransitionPage(
                      key: s.pageKey, child: const FarmerDashboardScreen()),
                ),
                GoRoute(
                  path: AppRoutes.farmerRecentActivity,
                  pageBuilder: (c, s) => AppPageTransitions.slideForward(
                      key: s.pageKey,
                      child: const FarmerRecentActivityScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: harvestNavigatorKey,
              routes: [
                GoRoute(
                  path: AppRoutes.harvestHub,
                  pageBuilder: (c, s) => NoTransitionPage(
                      key: s.pageKey, child: const HarvestHubScreen()),
                  routes: [
                    GoRoute(
                      path: 'crops',
                      pageBuilder: (c, s) => AppPageTransitions.slideForward(
                          key: s.pageKey, child: const CropListingScreen()),
                    ),
                    GoRoute(
                      path: 'history',
                      pageBuilder: (c, s) => AppPageTransitions.slideForward(
                          key: s.pageKey,
                          child: const HarvestHistoryScreen()),
                    ),
                    GoRoute(
                      path: 'inventory',
                      pageBuilder: (c, s) => AppPageTransitions.slideForward(
                          key: s.pageKey,
                          child: const ManageInventoryScreen()),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: marketNavigatorKey,
              routes: [
                GoRoute(
                  path: AppRoutes.myListings,
                  pageBuilder: (c, s) => NoTransitionPage(
                      key: s.pageKey, child: const MyListingsScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: analyticsNavigatorKey,
              routes: [
                GoRoute(
                  path: AppRoutes.farmerAnalytics,
                  pageBuilder: (c, s) => NoTransitionPage(
                      key: s.pageKey, child: const FarmerAnalyticsScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: profileNavigatorKey,
              routes: [
                GoRoute(
                  path: AppRoutes.farmerProfile,
                  pageBuilder: (c, s) => NoTransitionPage(
                      key: s.pageKey, child: const FarmerProfileScreen()),
                  routes: [
                    GoRoute(
                      path: 'loans',
                      pageBuilder: (c, s) => AppPageTransitions.slideForward(
                          key: s.pageKey, child: const MyLoansScreen()),
                    ),
                    GoRoute(
                      path: 'expenses',
                      pageBuilder: (c, s) => AppPageTransitions.slideForward(
                          key: s.pageKey, child: const MyExpensesScreen()),
                    ),
                    GoRoute(
                      path: 'harvest-summary',
                      pageBuilder: (c, s) => AppPageTransitions.slideForward(
                          key: s.pageKey,
                          child: const MyHarvestSummaryScreen()),
                    ),
                    GoRoute(
                      path: 'contribution',
                      pageBuilder: (c, s) => AppPageTransitions.slideForward(
                          key: s.pageKey, child: const MyContributionScreen()),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        // ── Admin StatefulShellRoute ───────────────────────────────────────────
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AdminShellScreen(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              navigatorKey: adminDashboardKey,
              routes: [
                GoRoute(
                  path: AppRoutes.adminDashboard,
                  pageBuilder: (c, s) => NoTransitionPage(
                      key: s.pageKey, child: const AdminDashboardScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: adminFarmersKey,
              routes: [
                GoRoute(
                  path: AppRoutes.farmerManagement,
                  pageBuilder: (c, s) => NoTransitionPage(
                      key: s.pageKey,
                      child: const FarmerManagementScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: adminListingsKey,
              routes: [
                GoRoute(
                  path: AppRoutes.pendingApprovals,
                  pageBuilder: (c, s) => NoTransitionPage(
                      key: s.pageKey,
                      child: const PendingApprovalsScreen()),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: adminLoansKey,
              routes: [
                GoRoute(
                  path: AppRoutes.loanDashboard,
                  pageBuilder: (c, s) => NoTransitionPage(
                      key: s.pageKey,
                      child: const _ComingSoonScreen(
                          routeName: AppRoutes.loanDashboard)),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: adminReportsKey,
              routes: [
                GoRoute(
                  path: AppRoutes.adminAnalytics,
                  pageBuilder: (c, s) => NoTransitionPage(
                      key: s.pageKey,
                      child: const _ComingSoonScreen(
                          routeName: AppRoutes.adminAnalytics)),
                ),
              ],
            ),
          ],
        ),
      ],
      errorBuilder: (context, state) =>
          _ComingSoonScreen(routeName: state.uri.path),
    );
  }
}

class _ComingSoonScreen extends StatelessWidget {
  final String routeName;
  const _ComingSoonScreen({required this.routeName});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction_rounded,
                  size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(l10n.comingSoon,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(l10n.comingSoonMessage(routeName),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
