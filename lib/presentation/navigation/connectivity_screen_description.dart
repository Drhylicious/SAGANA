import '../../core/l10n/app_localizations.dart';
import '../../routes/app_routes.dart';
import 'connectivity_page_observer.dart';

/// Human descriptions of the active leaf, never a parent URL or raw route name.
String connectivityScreenDescription(
  AppLocalizations l10n,
  String path, {
  ConnectivityPage? page,
}) {
  if (page != null) {
    return switch (page) {
      ConnectivityPage.farmMap => l10n.connectivityScreenFarmMap,
      ConnectivityPage.addressMap => l10n.connectivityScreenAddressMap,
      ConnectivityPage.cooperativeMap => l10n.connectivityScreenCooperativeMap,
      ConnectivityPage.deliveryMap => l10n.connectivityScreenDeliveryMap,
      ConnectivityPage.distributionYear =>
        l10n.connectivityScreenDistributionYear,
    };
  }
  return switch (path) {
    AppRoutes.splash => l10n.connectivityScreenStartup,
    AppRoutes.welcome => l10n.connectivityScreenWelcome,
    AppRoutes.login => l10n.connectivityScreenLogin,
    AppRoutes.register => l10n.connectivityScreenRegister,
    AppRoutes.resetPasswordCallback => l10n.connectivityScreenResetPassword,
    AppRoutes.forcePasswordChange => l10n.connectivityScreenChangePassword,
    AppRoutes.farmerDashboard => l10n.connectivityScreenFarmerHome,
    AppRoutes.pendingHome => l10n.connectivityScreenApplicationStatus,
    AppRoutes.pendingNotifications ||
    AppRoutes.farmerNotifications ||
    AppRoutes.adminNotifications ||
    AppRoutes.buyerNotifications => l10n.connectivityScreenNotifications,
    AppRoutes.pendingProfile => l10n.connectivityScreenApplicantProfile,
    AppRoutes.pendingReview => l10n.connectivityScreenApplicationReview,
    AppRoutes.farmerRecentActivity ||
    AppRoutes.buyerRecentActivity ||
    AppRoutes.adminActivityLog => l10n.connectivityScreenActivity,
    AppRoutes.harvestHub => l10n.connectivityScreenHarvestHub,
    AppRoutes.cropListing => l10n.connectivityScreenCropRoster,
    AppRoutes.selectCropForHarvest => l10n.connectivityScreenSelectCrop,
    AppRoutes.cropDetails => l10n.connectivityScreenCropDetails,
    AppRoutes.harvestEntryForm => l10n.connectivityScreenRecordHarvest,
    AppRoutes.harvestHistory ||
    AppRoutes.farmerHarvestHistory => l10n.connectivityScreenHarvestHistory,
    AppRoutes.manageInventory => l10n.connectivityScreenFarmStock,
    AppRoutes.myListings => l10n.connectivityScreenFarmerMarketplace,
    AppRoutes.createListing => l10n.connectivityScreenCreateListing,
    AppRoutes.listingSuccess => l10n.connectivityScreenListingSubmitted,
    AppRoutes.myListingDetail => l10n.connectivityScreenOwnListing,
    AppRoutes.editListing => l10n.connectivityScreenEditListing,
    AppRoutes.farmerListingHistory ||
    AppRoutes.adminListingHistory => l10n.connectivityScreenListingHistory,
    AppRoutes.farmerMarketplaceListingDetail ||
    AppRoutes.listingDetails => l10n.connectivityScreenProductDetails,
    AppRoutes.farmerCooperativeProduct =>
      l10n.connectivityScreenCooperativeProduct,
    AppRoutes.farmerMarketplaceCart ||
    AppRoutes.buyerCart => l10n.connectivityScreenCart,
    AppRoutes.farmerMarketplaceCartResult ||
    AppRoutes.cartCheckoutResult => l10n.connectivityScreenCheckoutResult,
    AppRoutes.farmerMarketplaceOrderSuccess ||
    AppRoutes.orderSuccess => l10n.connectivityScreenOrderConfirmation,
    AppRoutes.farmerMarketplaceCheckout ||
    AppRoutes.checkout => l10n.connectivityScreenCheckout,
    AppRoutes.farmerAnalytics => l10n.connectivityScreenFarmerAnalytics,
    AppRoutes.farmerProfile => l10n.connectivityScreenFarmerProfile,
    AppRoutes.editFarmDetails => l10n.connectivityScreenEditFarm,
    AppRoutes.myLoans => l10n.connectivityScreenOwnLoans,
    AppRoutes.myRestrictions => l10n.myRestrictionsTitle,
    AppRoutes.requestLoan => l10n.connectivityScreenRequestLoan,
    AppRoutes.myLoanRequests => l10n.connectivityScreenOwnLoanRequests,
    AppRoutes.myLoanHistory ||
    AppRoutes.farmerLoanHistory => l10n.connectivityScreenOwnLoanHistory,
    AppRoutes.myPaymentHistory ||
    AppRoutes.farmerPaymentHistory => l10n.connectivityScreenPaymentHistory,
    AppRoutes.benefitsTracking => l10n.connectivityScreenOwnContributions,
    AppRoutes.myExpenses => l10n.connectivityScreenOwnExpenses,
    AppRoutes.myPrograms => l10n.connectivityScreenBrowsePrograms,
    AppRoutes.myProgramsEnrolled => l10n.connectivityScreenEnrolledPrograms,
    AppRoutes.receivedItems => l10n.connectivityScreenReceivedItems,
    AppRoutes.programDetails => l10n.connectivityScreenProgramDetails,
    AppRoutes.myMarketLinking => l10n.connectivityScreenOwnMarketLinking,
    AppRoutes.myTransactionHistory => l10n.connectivityScreenTransactions,
    AppRoutes.farmerCoopOffers => l10n.connectivityScreenOwnOffers,
    AppRoutes.farmerCoopOfferDetail => l10n.connectivityScreenOwnOfferDetails,
    AppRoutes.farmerMyOrders ||
    AppRoutes.myOrders => l10n.connectivityScreenOwnOrders,
    AppRoutes.farmerOrderDetail ||
    AppRoutes.orderDetail ||
    AppRoutes.adminOrderDetail => l10n.connectivityScreenOrderDetails,
    AppRoutes.farmerProgramOrderDetail || AppRoutes.adminProgramOrderDetail =>
      l10n.connectivityScreenProgramOrderDetails,
    AppRoutes.farmerSettings ||
    AppRoutes.adminSettings ||
    AppRoutes.buyerSettings => l10n.connectivityScreenSettings,
    AppRoutes.farmerEditProfile ||
    AppRoutes.adminEditProfile ||
    AppRoutes.buyerEditProfile => l10n.connectivityScreenEditProfile,
    AppRoutes.viewMarket ||
    AppRoutes.priceMonitoring => l10n.connectivityScreenMarketPrices,
    AppRoutes.marketRateDetails => l10n.connectivityScreenCropPrices,
    AppRoutes.adminDashboard => l10n.connectivityScreenStaffDashboard,
    AppRoutes.priceManagement => l10n.connectivityScreenManagePrices,
    AppRoutes.announcementDashboard => l10n.connectivityScreenBroadcast,
    AppRoutes.supplyChain => l10n.connectivityScreenSupplyChain,
    AppRoutes.farmerManagement => l10n.connectivityScreenMembers,
    AppRoutes.farmerDetails => l10n.connectivityScreenMemberDetails,
    AppRoutes.addNewMember => l10n.connectivityScreenAddMember,
    AppRoutes.marketLinking => l10n.connectivityScreenManageMarketLinking,
    AppRoutes.daAmadEnrollment =>
      l10n.connectivityScreenMarketLinkingEnrollment,
    AppRoutes.pendingApprovals ||
    '/admin/marketplace/pending' => l10n.connectivityScreenListingApprovals,
    AppRoutes.allListings ||
    '/admin/marketplace/all' => l10n.connectivityScreenAllListings,
    AppRoutes.listingReview => l10n.connectivityScreenReviewListing,
    AppRoutes.listingEditRequest => l10n.connectivityScreenListingChanges,
    AppRoutes.buyerManagement => l10n.connectivityScreenBuyers,
    AppRoutes.buyerDetails => l10n.connectivityScreenBuyerDetails,
    AppRoutes.buyerOrderHistory => l10n.connectivityScreenBuyerOrderHistory,
    AppRoutes.loanDashboard => l10n.connectivityScreenStaffLoans,
    AppRoutes.issueNewLoan => l10n.connectivityScreenIssueLoan,
    AppRoutes.recordPayment => l10n.connectivityScreenRecordPayment,
    AppRoutes.loanDetails => l10n.connectivityScreenStaffLoanDetails,
    AppRoutes.loanHistory => l10n.connectivityScreenStaffLoanHistory,
    AppRoutes.loanRequests => l10n.connectivityScreenReviewLoanRequests,
    AppRoutes.loanReport => l10n.connectivityScreenLoanReport,
    AppRoutes.salesReport => l10n.connectivityScreenSalesReport,
    AppRoutes.harvestReport => l10n.connectivityScreenHarvestReport,
    AppRoutes.expenseReport => l10n.connectivityScreenExpenseReport,
    AppRoutes.memberContributionReport =>
      l10n.connectivityScreenContributionReport,
    AppRoutes.operationalReports => l10n.connectivityScreenReports,
    AppRoutes.adminAnalytics => l10n.connectivityScreenStaffAnalytics,
    AppRoutes.exportCenter => l10n.connectivityScreenExports,
    AppRoutes.capitalShareSettings => l10n.capSettingsTitle,
    AppRoutes.adminProfile => l10n.connectivityScreenStaffProfile,
    AppRoutes.createOfficerAccount => l10n.connectivityScreenCreateOfficer,
    AppRoutes.manageOfficerAccounts => l10n.connectivityScreenOfficerAccounts,
    AppRoutes.manageFarmerAccounts => l10n.connectivityScreenFarmerAccounts,
    AppRoutes.manageAdminAccounts => l10n.connectivityScreenManagerAccounts,
    AppRoutes.memberExpenseHistory => l10n.connectivityScreenMemberExpenses,
    AppRoutes.staffAccountability => l10n.connectivityScreenAccountability,
    AppRoutes.coopStockReport => l10n.connectivityScreenStockReport,
    AppRoutes.marketplaceBrowse => l10n.connectivityScreenBuyerBrowse,
    AppRoutes.buyerAccount => l10n.connectivityScreenBuyerAccount,
    AppRoutes.myAddresses => l10n.connectivityScreenAddresses,
    AppRoutes.addEditAddress => l10n.connectivityScreenEditAddress,
    AppRoutes.adminInventory => l10n.connectivityScreenCooperativeInventory,
    AppRoutes.cropManagement => l10n.connectivityScreenCropCatalog,
    AppRoutes.cropRequestApproval => l10n.connectivityScreenCropRequests,
    AppRoutes.programManagement => l10n.connectivityScreenManagePrograms,
    AppRoutes.programEnrollmentRequests =>
      l10n.connectivityScreenProgramEnrollment,
    AppRoutes.programMembers => l10n.connectivityScreenProgramMembers,
    AppRoutes.programProducts => l10n.connectivityScreenProgramProducts,
    AppRoutes.requestAssistance => l10n.connectivityScreenRequestAssistance,
    AppRoutes.assistanceRequests => l10n.connectivityScreenReviewAssistance,
    AppRoutes.loanItemManagement => l10n.connectivityScreenLoanCatalog,
    AppRoutes.adminCalendar => l10n.connectivityScreenCalendar,
    AppRoutes.broadcastHistory => l10n.connectivityScreenBroadcastHistory,
    AppRoutes.memberPrograms => l10n.connectivityScreenMemberPrograms,
    AppRoutes.adminMarketplace => l10n.connectivityScreenStaffMarketplace,
    AppRoutes.adminOrders ||
    '/admin/programs/purchases' => l10n.connectivityScreenManageOrders,
    AppRoutes.adminCooperativeDetails =>
      l10n.connectivityScreenCooperativeDetails,
    AppRoutes.adminDeliverySettings => l10n.connectivityScreenDeliverySettings,
    AppRoutes.offerToCooperative => l10n.connectivityScreenManageOffers,
    AppRoutes.offerDetail => l10n.connectivityScreenReviewOffer,
    AppRoutes.aboutSagana => l10n.connectivityScreenAboutSagana,
    AppRoutes.aboutCooperative => l10n.connectivityScreenAboutCooperative,
    AppRoutes.privacyPolicy => l10n.connectivityScreenPrivacy,
    AppRoutes.termsOfUse => l10n.connectivityScreenTerms,
    _ => l10n.connectivityScreenUnknown,
  };
}
