class AppRoutes {
  AppRoutes._();

  // ─── Auth ────────────────────────────────────────────────────────────────────
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';

  // ─── Farmer ──────────────────────────────────────────────────────────────────
  static const String farmerDashboard      = '/farmer/dashboard';
  static const String farmerRecentActivity = '/farmer/activity';
  static const String farmerNotifications  = '/farmer/notifications';
  static const String harvestHub           = '/farmer/harvest';
  static const String cropListing          = '/farmer/harvest/crops';
  static const String addCrop              = '/farmer/harvest/crops/add';
  static const String harvestManagement    = '/farmer/harvest/manage';
  static const String harvestEntryForm     = '/farmer/harvest/entry';
  static const String harvestHistory       = '/farmer/harvest/history';
  static const String manageInventory      = '/farmer/harvest/inventory';
  static const String myListings           = '/farmer/marketplace';
  static const String createListing        = '/farmer/marketplace/create';
  static const String listingSuccess       = '/farmer/marketplace/success';
  static const String farmerAnalytics      = '/farmer/analytics';
  static const String farmerProfile        = '/farmer/profile';
  static const String editFarmDetails      = '/farmer/profile/farm-details/edit';
  static const String myLoans              = '/farmer/profile/loans';
  static const String myContribution       = '/farmer/profile/contribution';
  static const String myExpenses           = '/farmer/profile/expenses';
  static const String myHarvestSummary     = '/farmer/profile/harvest-summary';
  static const String farmerSettings       = '/farmer/settings';

  // ─── Admin ───────────────────────────────────────────────────────────────────
  static const String adminDashboard           = '/admin/dashboard';
  static const String priceManagement          = '/admin/prices';
  static const String announcementDashboard    = '/admin/announcements';
  static const String supplyChainMap           = '/admin/map';
  static const String farmerManagement         = '/admin/farmers';
  static const String farmerDetails            = '/admin/farmers/details';
  static const String farmerHarvestHistory     = '/admin/farmers/harvest-history';
  static const String addNewMember             = '/admin/farmers/add';
  static const String marketLinking            = '/admin/farmers/market-linking';
  static const String pendingApprovals         = '/admin/listings/pending';
  static const String allListings              = '/admin/listings/all';
  static const String listingReview            = '/admin/listings/review';
  static const String buyerManagement          = '/admin/buyers';
  static const String loanDashboard            = '/admin/loans';
  static const String issueNewLoan             = '/admin/loans/issue';
  static const String recordPayment            = '/admin/loans/payment';
  static const String loanDetails              = '/admin/loans/details';
  static const String loanHistory              = '/admin/loans/history';
  static const String inventoryReport          = '/admin/reports/inventory';
  static const String loanReport               = '/admin/reports/loans';
  static const String salesReport              = '/admin/reports/sales';
  static const String harvestReport            = '/admin/reports/harvest';
  static const String expenseReport            = '/admin/reports/expenses';
  static const String memberContributionReport = '/admin/reports/contributions';
  static const String adminAnalytics           = '/admin/analytics';
  static const String balikTangkilikManagement = '/admin/balik-tangkilik';
  static const String exportCenter             = '/admin/export';
  static const String adminProfile             = '/admin/profile';
  static const String adminNotifications       = '/admin/notifications';

  // ─── Buyer ───────────────────────────────────────────────────────────────────
  static const String marketplaceBrowse  = '/buyer/browse';
  static const String listingDetails     = '/buyer/browse/details';
  static const String orderSuccess       = '/buyer/browse/order-success';
  static const String myOrders           = '/buyer/orders';
  static const String orderDetail        = '/buyer/orders/detail';
  static const String priceMonitoring    = '/buyer/prices';
  static const String buyerAccount       = '/buyer/account';
  static const String buyerEditProfile   = '/buyer/account/edit';
  static const String buyerNotifications = '/buyer/notifications';
}
