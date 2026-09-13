import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/animations/app_page_transitions.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/models/export_model.dart';
import '../../data/models/farmer_crop_model.dart';
import '../../data/models/farmer_market_rate_model.dart';
import '../../data/services/hive_service.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/auth/register_screen.dart';
import '../../presentation/screens/auth/reset_password_screen.dart';
import '../../presentation/screens/auth/force_password_change_screen.dart';
import '../../presentation/screens/farmer/create_listing_screen.dart';
import '../../presentation/screens/farmer/crop_listing_screen.dart';
import '../../presentation/screens/farmer/crop_details_screen.dart';
import '../../presentation/screens/farmer/select_crop_screen.dart';
import '../../presentation/screens/farmer/view_market_screen.dart';
import '../../presentation/screens/farmer/market_rate_details_screen.dart';
import '../../presentation/screens/farmer/edit_farm_details_screen.dart';
import '../../presentation/screens/farmer/farmer_analytics_screen.dart';
import '../../presentation/screens/farmer/farmer_dashboard_screen.dart';
import '../../presentation/screens/farmer/farmer_notifications_screen.dart';
import '../../presentation/screens/farmer/farmer_profile_screen.dart';
import '../../presentation/screens/farmer/farmer_recent_activity_screen.dart';
import '../../presentation/screens/farmer/farmer_settings_screen.dart';
import '../../presentation/screens/farmer/farmer_edit_profile_screen.dart';
import '../../presentation/screens/farmer/harvest_entry_form_screen.dart';
import '../../presentation/screens/farmer/harvest_history_screen.dart';
import '../../presentation/screens/farmer/harvest_hub_screen.dart';
import '../../presentation/screens/farmer/listing_success_screen.dart';
import '../../presentation/screens/farmer/manage_inventory_screen.dart';
import '../../presentation/screens/farmer/my_contribution_screen.dart';
import '../../presentation/screens/farmer/my_expenses_screen.dart';
import '../../presentation/screens/farmer/my_harvest_summary_screen.dart';
import '../../presentation/screens/farmer/my_listings_screen.dart';
import '../../presentation/screens/farmer/my_loans_screen.dart';
import '../../presentation/screens/farmer/my_programs_screen.dart';
import '../../presentation/screens/farmer/my_market_linking_screen.dart';
import '../../presentation/screens/farmer/pending_applicant_screen.dart';
import '../../presentation/screens/admin/admin_dashboard_screen.dart';
import '../../presentation/screens/admin/add_new_member_screen.dart';
import '../../presentation/screens/admin/admin_activity_screen.dart';
import '../../presentation/screens/admin/admin_profile_screen.dart';
import '../../presentation/screens/admin/admin_settings_screen.dart';
import '../../presentation/screens/admin/admin_edit_profile_screen.dart';
import '../../presentation/screens/admin/create_officer_account_screen.dart';
import '../../presentation/screens/admin/manage_accounts_screen.dart';
import '../../presentation/screens/admin/crop_management_screen.dart';
import '../../presentation/screens/admin/crop_request_approval_screen.dart';
import '../../presentation/screens/admin/loan_item_management_screen.dart';
import '../../presentation/screens/admin/program_management_screen.dart';
import '../../presentation/screens/admin/admin_inventory_screen.dart';
import '../../presentation/screens/admin/farmer_details_screen.dart';
import '../../presentation/screens/admin/loan_dashboard_screen.dart';
import '../../presentation/screens/admin/farmer_management_screen.dart';
import '../../presentation/screens/admin/issue_new_loan_screen.dart';
import '../../presentation/screens/admin/notification_broadcast_screen.dart';
import '../../presentation/screens/admin/all_listings_screen.dart';
import '../../presentation/screens/admin/pending_approvals_screen.dart';
import '../../presentation/screens/admin/price_management_screen.dart';
import '../../presentation/screens/admin/supply_chain_map_screen.dart';
import '../../presentation/screens/admin/market_linking_screen.dart';
import '../../presentation/screens/admin/listing_review_screen.dart';
import '../../presentation/screens/admin/operational_reports_screen.dart';
import '../../presentation/screens/admin/record_payment_screen.dart';
import '../../presentation/screens/admin/harvest_report_screen.dart';
import '../../presentation/screens/admin/sales_report_screen.dart';
import '../../presentation/screens/admin/member_contribution_report_screen.dart';
import '../../presentation/screens/admin/export_center_screen.dart';
import '../../presentation/screens/admin/admin_notifications_screen.dart';
import '../../presentation/screens/admin/cooperative_stock_report_screen.dart';
import '../../presentation/screens/admin/expense_report_screen.dart';
import '../../presentation/screens/admin/loan_report_screen.dart';
import '../../presentation/screens/admin/loan_history_screen.dart';
import '../../presentation/screens/admin/loan_details_screen.dart';
import '../../presentation/screens/admin/analytics_dashboard_screen.dart';
import '../../presentation/screens/admin/admin_calendar_screen.dart';
import '../../presentation/screens/admin/admin_route_placeholder_screen.dart';
import '../../presentation/screens/admin/broadcast_history_screen.dart';
import '../../presentation/screens/admin/balik_tangkilik_management_screen.dart';
import '../../presentation/screens/admin/farmer_harvest_history_screen.dart';
import '../../presentation/screens/admin/marketplace_dashboard_screen.dart';
import '../../presentation/screens/admin/offer_to_cooperative_screen.dart';
import '../../presentation/screens/admin/buyer_management_screen.dart';
import '../../presentation/screens/admin/buyer_details_screen.dart';
import '../../presentation/screens/admin/buyer_order_history_screen.dart';
import '../../presentation/screens/admin/order_management_screen.dart';
import '../../presentation/screens/admin/admin_order_detail_screen.dart' as admin_order_detail;
import '../../presentation/screens/buyer/marketplace_browse_screen.dart';
import '../../presentation/screens/buyer/listing_details_screen.dart';
import '../../presentation/screens/buyer/cart_screen.dart';
import '../../presentation/screens/buyer/cart_checkout_result_screen.dart';
import '../../data/models/cart_item_model.dart';
import '../../presentation/screens/buyer/order_success_screen.dart';
import '../../presentation/screens/buyer/my_orders_screen.dart';
import '../../presentation/screens/buyer/order_detail_screen.dart';
import '../../presentation/screens/buyer/price_monitoring_screen.dart';
import '../../presentation/screens/buyer/buyer_account_screen.dart';
import '../../presentation/screens/buyer/buyer_edit_profile_screen.dart';
import '../../presentation/screens/buyer/buyer_settings_screen.dart';
import '../../presentation/screens/buyer/buyer_recent_activity_screen.dart';
import '../../presentation/screens/buyer/buyer_notifications_screen.dart';
import '../../presentation/screens/splash_screen.dart';
import '../../presentation/shell/admin_shell_screen.dart';
import '../../presentation/shell/buyer_shell_screen.dart';
import '../../presentation/shell/farmer_shell_screen.dart';
import '../../routes/app_routes.dart';

class AppRouter {
  AppRouter._();

  static final rootNavigatorKey = GlobalKey<NavigatorState>();
  static final homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
  static final harvestNavigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'harvest',
  );
  static final marketNavigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'market',
  );
  static final analyticsNavigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'analytics',
  );
  static final profileNavigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'profile',
  );

  // ── Admin branch keys ──────────────────────────────────────────────────────
  static final adminDashboardKey = GlobalKey<NavigatorState>(
    debugLabel: 'adminDashboard',
  );
  static final adminFarmersKey = GlobalKey<NavigatorState>(
    debugLabel: 'adminFarmers',
  );
  static final adminListingsKey = GlobalKey<NavigatorState>(
    debugLabel: 'adminListings',
  );
  static final adminLoansKey = GlobalKey<NavigatorState>(
    debugLabel: 'adminLoans',
  );
  static final adminReportsKey = GlobalKey<NavigatorState>(
    debugLabel: 'adminReports',
  );

  // ── Buyer branch keys ──────────────────────────────────────────────────────
  static final buyerBrowseKey = GlobalKey<NavigatorState>(
    debugLabel: 'buyerBrowse',
  );
  static final buyerOrdersKey = GlobalKey<NavigatorState>(
    debugLabel: 'buyerOrders',
  );
  static final buyerPricesKey = GlobalKey<NavigatorState>(
    debugLabel: 'buyerPrices',
  );
  static final buyerAccountKey = GlobalKey<NavigatorState>(
    debugLabel: 'buyerAccount',
  );

  // Tracks whether this app instance has completed its first redirect
  // check yet. Resets to false on every fresh app boot (cold load or
  // browser refresh, since that reboots the whole Dart runtime), so each
  // reload is forced through splash exactly once, then stays true for
  // the rest of that session.
  static bool _hasBootstrapped = false;

  static GoRouter create() {
    return GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: AppRoutes.splash,
      redirect: (context, state) {
        final path = state.matchedLocation;

        // Force the first navigation check of every fresh app boot (cold
        // load AND browser refresh) through splash first, regardless of
        // whatever URL is currently in the address bar. `initialLocation`
        // alone doesn't cover this on web — a refresh already has a URL
        // in the address bar, so GoRouter parses that directly and skips
        // `initialLocation` entirely. Splash's own `_navigate()` then
        // decides the real destination exactly as it already does.
        // `_hasBootstrapped` resets naturally on every hard reload (the
        // whole Dart app reboots), but stays true for the rest of the
        // session so in-app navigation isn't repeatedly bounced back.
        if (!_hasBootstrapped) {
          _hasBootstrapped = true;
          // reset-password is exempted: it's always hit as a cold boot
          // (a fresh tab opened from the email link), so without this
          // exemption every password-reset click would get bounced to
          // splash before the app ever saw Supabase's code/error query
          // params — silently breaking the whole flow.
          if (path != AppRoutes.splash &&
              path != AppRoutes.resetPasswordCallback) {
            return AppRoutes.splash;
          }
        }

        // Forced password change after an admin-issued temporary password
        // (see AccountManagementRepository.resetUserPassword). Applies to
        // every role, unlike the farmer-pending check below, so it's
        // checked first rather than nested inside that role-scoped gate.
        final isAuthPath = path == AppRoutes.login ||
            path == AppRoutes.register ||
            path == AppRoutes.resetPasswordCallback ||
            path == AppRoutes.forcePasswordChange;
        if (!isAuthPath && HiveService.getMustChangePassword()) {
          return AppRoutes.forcePasswordChange;
        }

        // Officer scope enforcement (Issue 6 / Decision D19) — an Officer
        // has every Admin module EXCEPT the Members tab and Officer/account
        // management. Admin is never subject to this. Redirects to the
        // Admin dashboard rather than splash — the person is legitimately
        // logged in, just hit a wall on one screen.
        if (HiveService.getUserRole() == 'officer') {
          const membersOnlyPaths = {
            AppRoutes.farmerManagement,
            AppRoutes.farmerDetails,
            AppRoutes.addNewMember,
            AppRoutes.createOfficerAccount,
            AppRoutes.manageOfficerAccounts,
            AppRoutes.manageAdminAccounts,
            AppRoutes.memberExpenseHistory,
          };
          if (membersOnlyPaths.contains(path) ||
              path.startsWith('/admin/members')) {
            return AppRoutes.adminDashboard;
          }
        }

        // Only enforce for farmer paths (not auth, admin, buyer, or pending paths)
        final isFarmerPath = path.startsWith('/farmer/') &&
            !path.startsWith('/farmer/pending');
        if (!isFarmerPath) return null;

        // Check cached membership status — synchronous, works offline.
        // The Pending Applicant screen holds every pre-active farmer state
        // (Issue 5): draft (not yet submitted), pending (under review),
        // rejected (can resubmit), and approved-but-not-yet-acknowledged
        // (Decision D7). Inactive is derived and never gates.
        final cachedRole = HiveService.getUserRole();
        final cachedStatus = HiveService.getMemberStatus();

        if (cachedRole == AppConstants.roleFarmer) {
          const held = {'draft', 'pending', 'rejected'};
          if (held.contains(cachedStatus) ||
              (cachedStatus == 'active' &&
                  HiveService.getPendingAcknowledgement())) {
            return AppRoutes.pendingHome;
          }
        }
        return null;
      },
      routes: [
        GoRoute(
          path: AppRoutes.splash,
          pageBuilder: (c, s) => AppPageTransitions.fadeThrough(
            key: s.pageKey,
            child: const SplashScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.login,
          pageBuilder: (c, s) => AppPageTransitions.fadeThrough(
            key: s.pageKey,
            child: const LoginScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.register,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const RegisterScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.resetPasswordCallback,
          pageBuilder: (c, s) => AppPageTransitions.fadeThrough(
            key: s.pageKey,
            child: ResetPasswordScreen(
              email: s.uri.queryParameters['email'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.forcePasswordChange,
          pageBuilder: (c, s) => AppPageTransitions.fadeThrough(
            key: s.pageKey,
            child: const ForcePasswordChangeScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.farmerHarvestHistory,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: AdminFarmerHarvestHistoryScreen(
              farmerId: s.extra is String ? s.extra as String : null,
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.farmerSettings,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const FarmerSettingsScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.farmerEditProfile,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const FarmerEditProfileScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.editFarmDetails,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const EditFarmDetailsScreen(),
          ),
        ),
        // ─── Profile secondary screens — pushed above the shell (Phase 1.1) ──
        // Previously nested under the farmerProfile branch, which kept the
        // bottom nav visible. Moved to rootNavigatorKey to match the pattern
        // already used above for Settings/Edit Profile/Edit Farm Details.
        GoRoute(
          path: AppRoutes.myLoans,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const MyLoansScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.myExpenses,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const MyExpensesScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.myHarvestSummary,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const MyHarvestSummaryScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.myContribution,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const MyContributionScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.myPrograms,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const MyProgramsScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.myMarketLinking,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const MyMarketLinkingScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.harvestEntryForm,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: HarvestEntryFormScreen(
              // prefer GoRouter extra when available; may be null
              crop: s.extra as FarmerCropModel?,
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.selectCropForHarvest,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const SelectCropScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.cropDetails,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: CropDetailsScreen(crop: s.extra as FarmerCropModel),
          ),
        ),
        GoRoute(
          path: AppRoutes.cropListing,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const CropListingScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.harvestHistory,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: HarvestHistoryScreen(
              initialCropFilter: s.extra as String?,
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.manageInventory,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const ManageInventoryScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.createListing,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: CreateListingScreen(initialArg: s.extra),
          ),
        ),
        GoRoute(
          path: AppRoutes.listingSuccess,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.scaleIn(
            key: s.pageKey,
            child: ListingSuccessScreen(initialArg: s.extra),
          ),
        ),
        GoRoute(
          path: AppRoutes.farmerNotifications,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const FarmerNotificationsScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.viewMarket,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const ViewMarketScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.marketRateDetails,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: MarketRateDetailsScreen(
              rate: s.extra as FarmerMarketRateModel?,
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.adminNotifications,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const AdminNotificationsScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.broadcastHistory,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const BroadcastHistoryScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.adminCalendar,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const AdminCalendarScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.adminActivityLog,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const AdminActivityScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.adminInventory,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const AdminInventoryScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.cropManagement,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const CropManagementScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.cropRequestApproval,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const CropRequestApprovalScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.programManagement,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const ProgramManagementScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.loanItemManagement,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const LoanItemManagementScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.priceManagement,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const PriceManagementScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.supplyChainMap,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.fadeThrough(
            key: s.pageKey,
            child: const SupplyChainMapScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.supplyChainFullMap,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const SupplyChainFullMapScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.announcementDashboard,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) {
            final extra = s.extra as Map<String, dynamic>?;
            return AppPageTransitions.slideForward(
              key: s.pageKey,
              child: NotificationBroadcastScreen(
                initialBuyerId: extra?['buyerId'] as String?,
                initialBuyerName: extra?['buyerName'] as String?,
              ),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.salesReport,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const SalesReportScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.coopStockReport,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const CooperativeStockReportScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.memberContributionReport,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const MemberContributionReportScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.exportCenter,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: ExportCenterScreen(args: s.extra as ExportCenterArgs?),
          ),
        ),
        GoRoute(
          path: AppRoutes.harvestReport,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: HarvestReportScreen(
              initialTabIndex: s.extra == 1 ? 1 : 0,
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.expenseReport,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const ExpenseReportScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.loanReport,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const LoanReportScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.adminAnalytics,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const AnalyticsDashboardScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.farmerDetails,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: FarmerDetailsScreen(
              farmerId: s.extra is String ? s.extra as String : '',
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.listingReview,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) {
            // extra is either a raw listing-id String (every existing
            // caller — Pending Review, Dashboard shortcuts, Activity feed)
            // or a {'listingId', 'readOnly'} map (All Listings, which
            // must never show approve/reject/request-changes actions —
            // see M-marketplace-2).
            final extra = s.extra;
            String listingId = '';
            bool readOnly = false;
            if (extra is String) {
              listingId = extra;
            } else if (extra is Map) {
              listingId = extra['listingId'] as String? ?? '';
              readOnly = extra['readOnly'] as bool? ?? false;
            }
            return AppPageTransitions.slideForward(
              key: s.pageKey,
              child: ListingReviewScreen(listingId: listingId, readOnly: readOnly),
            );
          },
        ),
        // Above-shell (parentNavigatorKey: rootNavigatorKey) — kept for
        // navigation from Dashboard's "pending listings" urgent action and
        // any existing deep links, now that these live nested under
        // adminMarketplace within the Listings shell branch.
        GoRoute(
          path: AppRoutes.pendingApprovals, // '/admin/listings/pending' — kept for backward compat
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const PendingApprovalsScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.allListings, // '/admin/listings/all'
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const AllListingsScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.buyerManagement,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const BuyerManagementScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.buyerDetails,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: BuyerDetailsScreen(
              buyerId: s.extra is String ? s.extra as String : '',
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.adminOrders,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) {
            final extra = s.extra as Map<String, dynamic>?;
            return AppPageTransitions.slideForward(
              key: s.pageKey,
              child: OrderManagementScreen(
                buyerId: extra?['buyerId'] as String?,
                buyerName: extra?['buyerName'] as String?,
              ),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.adminOrderDetail,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) {
            // extra is either a raw order-id String (Order Management —
            // fully actionable) or a {'orderId', 'readOnly'} map (Buyer
            // Order History — never actionable, see M-marketplace-4).
            final extra = s.extra;
            String orderId = '';
            bool readOnly = false;
            if (extra is String) {
              orderId = extra;
            } else if (extra is Map) {
              orderId = extra['orderId'] as String? ?? '';
              readOnly = extra['readOnly'] as bool? ?? false;
            }
            return AppPageTransitions.slideForward(
              key: s.pageKey,
              child: admin_order_detail.OrderDetailScreen(orderId: orderId, readOnly: readOnly),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.buyerOrderHistory,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) {
            final extra = s.extra as Map<String, dynamic>?;
            return AppPageTransitions.slideForward(
              key: s.pageKey,
              child: BuyerOrderHistoryScreen(
                buyerId: extra?['buyerId'] as String? ?? '',
                buyerName: extra?['buyerName'] as String?,
              ),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.offerToCooperative,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const OfferToCooperativeScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.addNewMember,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const AddNewMemberScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.marketLinking,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const MarketLinkingScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.issueNewLoan,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const IssueNewLoanScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.recordPayment,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: RecordPaymentScreen(loanId: s.extra as String?),
          ),
        ),
        GoRoute(
          path: AppRoutes.loanDetails,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: LoanDetailsScreen(loanId: s.extra as String),
          ),
        ),
        GoRoute(
          path: AppRoutes.loanHistory,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: LoanHistoryScreen(initialStatusFilter: s.extra as String?),
          ),
        ),
        GoRoute(
          path: AppRoutes.balikTangkilikManagement,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const BalikTangkilikManagementScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.farmerRecentActivity,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const FarmerRecentActivityScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.createOfficerAccount,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const CreateOfficerAccountScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.manageFarmerAccounts,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const ManageAccountsScreen(initialTab: 'farmer'),
          ),
        ),
        GoRoute(
          path: AppRoutes.manageOfficerAccounts,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const ManageAccountsScreen(initialTab: 'officer'),
          ),
        ),
        GoRoute(
          path: AppRoutes.manageAdminAccounts,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const ManageAccountsScreen(initialTab: 'admin'),
          ),
        ),
        GoRoute(
          path: AppRoutes.memberPrograms,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const AdminRoutePlaceholderScreen(
              routeName: AppRoutes.memberPrograms,
              label: 'Member Programs',
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.adminProfile,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const AdminProfileScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.adminSettings,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const AdminSettingsScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.adminEditProfile,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const AdminEditProfileScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.pendingHome,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => NoTransitionPage(
            key: s.pageKey,
            child: const PendingApplicantScreen(initialTab: 0),
          ),
        ),
        GoRoute(
          path: AppRoutes.pendingNotifications,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => NoTransitionPage(
            key: s.pageKey,
            child: const PendingApplicantScreen(initialTab: 1),
          ),
        ),
        GoRoute(
          path: AppRoutes.pendingHelp,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => NoTransitionPage(
            key: s.pageKey,
            child: const PendingApplicantScreen(initialTab: 2),
          ),
        ),
        GoRoute(
          path: AppRoutes.pendingProfile,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => NoTransitionPage(
            key: s.pageKey,
            child: const PendingApplicantScreen(initialTab: 3),
          ),
        ),
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
                    key: s.pageKey,
                    child: const FarmerDashboardScreen(),
                  ),
                ),
                
              ],
            ),
            StatefulShellBranch(
              navigatorKey: harvestNavigatorKey,
              routes: [
                GoRoute(
                  path: AppRoutes.harvestHub,
                  pageBuilder: (c, s) => NoTransitionPage(
                    key: s.pageKey,
                    child: const HarvestHubScreen(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: marketNavigatorKey,
              routes: [
                GoRoute(
                  path: AppRoutes.myListings,
                  pageBuilder: (c, s) => NoTransitionPage(
                    key: s.pageKey,
                    child: const MyListingsScreen(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: analyticsNavigatorKey,
              routes: [
                GoRoute(
                  path: AppRoutes.farmerAnalytics,
                  pageBuilder: (c, s) => NoTransitionPage(
                    key: s.pageKey,
                    child: const FarmerAnalyticsScreen(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: profileNavigatorKey,
              routes: [
                GoRoute(
                  path: AppRoutes.farmerProfile,
                  pageBuilder: (c, s) => NoTransitionPage(
                    key: s.pageKey,
                    child: const FarmerProfileScreen(),
                  ),
                ),
              ],
            ),
          ],
        ),
        // ─── Buyer — pushed routes (above shell) ─────────────────────────────
        GoRoute(
          path: AppRoutes.listingDetails,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: ListingDetailsScreen(listingId: s.extra as String),
          ),
        ),
        GoRoute(
          path: AppRoutes.buyerCart,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const CartScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.cartCheckoutResult,
          parentNavigatorKey: rootNavigatorKey,
          redirect: (context, state) {
            // If the in-memory checkout result was lost (e.g. a web reload
            // or a deep link straight to this URL), there's nothing
            // meaningful to render — send the buyer to their orders list
            // instead of crashing on the unguarded extra cast.
            final extra = state.extra;
            if (extra is! Map<String, dynamic> ||
                extra['succeeded'] is! List<CartItemModel> ||
                extra['failed'] is! List<(CartItemModel, String)>) {
              return AppRoutes.myOrders;
            }
            return null;
          },
          pageBuilder: (c, s) {
            final extra = s.extra as Map<String, dynamic>;
            return AppPageTransitions.slideForward(
              key: s.pageKey,
              child: CartCheckoutResultScreen(
                succeeded: extra['succeeded'] as List<CartItemModel>,
                failed: extra['failed'] as List<(CartItemModel, String)>,
              ),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.orderSuccess,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: OrderSuccessScreen(orderId: s.extra as String),
          ),
        ),
        GoRoute(
          path: AppRoutes.orderDetail,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: OrderDetailScreen(orderId: s.extra as String),
          ),
        ),
        GoRoute(
          path: AppRoutes.buyerEditProfile,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const BuyerEditProfileScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.buyerSettings,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const BuyerSettingsScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.buyerRecentActivity,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const BuyerRecentActivityScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.buyerNotifications,
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => AppPageTransitions.slideForward(
            key: s.pageKey,
            child: const BuyerNotificationsScreen(),
          ),
        ),
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
                    key: s.pageKey,
                    child: const AdminDashboardScreen(),
                  ),
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
                    child: const FarmerManagementScreen(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: adminListingsKey,
              routes: [
                // New dashboard as shell root
                GoRoute(
                  path: AppRoutes.adminMarketplace,
                  pageBuilder: (c, s) => NoTransitionPage(
                    key: s.pageKey,
                    child: const MarketplaceDashboardScreen(),
                  ),
                  routes: [
                    // Nested so they stay within the Listings shell branch
                    GoRoute(
                      path: 'pending', // resolves to /admin/marketplace/pending
                      pageBuilder: (c, s) => AppPageTransitions.slideForward(
                        key: s.pageKey,
                        child: const PendingApprovalsScreen(),
                      ),
                    ),
                    GoRoute(
                      path: 'all', // resolves to /admin/marketplace/all
                      pageBuilder: (c, s) => AppPageTransitions.slideForward(
                        key: s.pageKey,
                        child: const AllListingsScreen(),
                      ),
                    ),
                  ],
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
                    child: const LoanDashboardScreen(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: adminReportsKey,
              routes: [
                GoRoute(
                  path: AppRoutes.operationalReports,
                  pageBuilder: (c, s) => NoTransitionPage(
                    key: s.pageKey,
                    child: const OperationalReportsScreen(),
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              BuyerShellScreen(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              navigatorKey: buyerBrowseKey,
              routes: [
                GoRoute(
                  path: AppRoutes.marketplaceBrowse,
                  pageBuilder: (c, s) => NoTransitionPage(
                    key: s.pageKey,
                    child: const MarketplaceBrowseScreen(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: buyerOrdersKey,
              routes: [
                GoRoute(
                  path: AppRoutes.myOrders,
                  pageBuilder: (c, s) => NoTransitionPage(
                    key: s.pageKey,
                    child: MyOrdersScreen(initialTabIndex: s.extra as int? ?? 0),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: buyerPricesKey,
              routes: [
                GoRoute(
                  path: AppRoutes.priceMonitoring,
                  pageBuilder: (c, s) => NoTransitionPage(
                    key: s.pageKey,
                    child: const PriceMonitoringScreen(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              navigatorKey: buyerAccountKey,
              routes: [
                GoRoute(
                  path: AppRoutes.buyerAccount,
                  pageBuilder: (c, s) => NoTransitionPage(
                    key: s.pageKey,
                    child: const BuyerAccountScreen(),
                  ),
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
              Icon(
                Icons.construction_rounded,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.comingSoon,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.comingSoonMessage(routeName),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}