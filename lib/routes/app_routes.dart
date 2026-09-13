class AppRoutes {
  AppRoutes._();

  // ─── Auth ────────────────────────────────────────────────────────────────────
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String resetPasswordCallback = '/reset-password';
  static const String forcePasswordChange = '/force-password-change';

  // ─── Farmer ──────────────────────────────────────────────────────────────────
  static const String farmerDashboard = '/farmer/dashboard';
  static const String pendingHome          = '/farmer/pending/home';
  static const String pendingNotifications = '/farmer/pending/notifications';
  static const String pendingHelp          = '/farmer/pending/help';
  static const String pendingProfile       = '/farmer/pending/profile';
  static const String farmerRecentActivity = '/farmer/activity';
  static const String farmerNotifications = '/farmer/notifications';
  static const String harvestHub = '/farmer/harvest';
  static const String cropListing = '/farmer/harvest/crops';
  static const String selectCropForHarvest = '/farmer/harvest/select-crop';
  static const String cropDetails = '/farmer/harvest/crop-details';
  static const String harvestEntryForm = '/farmer/harvest/entry-form';
  static const String harvestHistory = '/farmer/harvest/history';
  static const String manageInventory = '/farmer/harvest/inventory';
  static const String myListings = '/farmer/marketplace';
  static const String createListing = '/farmer/marketplace/create';
  static const String listingSuccess = '/farmer/marketplace/success';
  static const String farmerAnalytics = '/farmer/analytics';
  static const String farmerProfile = '/farmer/profile';
  static const String editFarmDetails = '/farmer/profile/farm-details/edit';
  static const String myLoans = '/farmer/profile/loans';
  static const String myContribution = '/farmer/profile/contribution';
  static const String myExpenses = '/farmer/profile/expenses';
  static const String myHarvestSummary = '/farmer/profile/harvest-summary';
  static const String myPrograms = '/farmer/profile/programs';
  static const String myMarketLinking = '/farmer/profile/market-linking';
  static const String farmerSettings = '/farmer/settings';
  static const String farmerEditProfile = '/farmer/profile/edit';
  static const String viewMarket = '/farmer/market-rates';
  static const String marketRateDetails = '/farmer/market-rates/details';

  // ─── Admin ───────────────────────────────────────────────────────────────────
  static const String adminDashboard = '/admin/dashboard';
  static const String priceManagement = '/admin/prices';
  static const String announcementDashboard = '/admin/announcements';
  static const String supplyChainMap = '/admin/map';
  static const String supplyChainFullMap = '/admin/map/full';
  static const String farmerManagement = '/admin/farmers';
  static const String farmerDetails = '/admin/farmers/details';
  static const String farmerHarvestHistory = '/admin/farmers/harvest-history';
  static const String addNewMember = '/admin/farmers/add';
  static const String marketLinking = '/admin/farmers/market-linking';
  static const String pendingApprovals = '/admin/listings/pending';
  static const String allListings = '/admin/listings/all';
  static const String listingReview = '/admin/listings/review';
  static const String buyerManagement = '/admin/buyers';
  static const String buyerDetails    = '/admin/buyers/details';
  static const String buyerOrderHistory = '/admin/buyers/order-history';
  static const String loanDashboard = '/admin/loans';
  static const String issueNewLoan = '/admin/loans/issue';
  static const String recordPayment = '/admin/loans/payment';
  static const String loanDetails = '/admin/loans/details';
  static const String loanHistory = '/admin/loans/history';
  static const String loanReport = '/admin/reports/loans';
  static const String salesReport = '/admin/reports/sales';
  static const String harvestReport = '/admin/reports/harvest';
  static const String expenseReport = '/admin/reports/expenses';
  static const String memberContributionReport = '/admin/reports/contributions';
  static const String operationalReports = '/admin/reports';
  static const String adminAnalytics = '/admin/analytics';
  static const String balikTangkilikManagement = '/admin/balik-tangkilik';
  static const String exportCenter = '/admin/export';
  static const String adminProfile = '/admin/profile';
  static const String adminSettings = '/admin/profile/settings';
  static const String adminEditProfile = '/admin/profile/edit';
  static const String adminNotifications = '/admin/notifications';
  static const String adminActivityLog = '/admin/activity';
  static const String createOfficerAccount  = '/admin/members/add-officer';
  static const String manageOfficerAccounts = '/admin/members/officer-accounts';
  static const String memberExpenseHistory = '/admin/members/expense-history';

  // ─── Admin — Report Routes ───────────────────────────────────────────────────
  static const String coopStockReport = '/admin/reports/coop-stock';

  // ─── Buyer ───────────────────────────────────────────────────────────────────
  static const String marketplaceBrowse = '/buyer/browse';
  static const String buyerBrowse = marketplaceBrowse;
  static const String listingDetails = '/buyer/browse/details';
  static const String orderSuccess = '/buyer/browse/order-success';
  static const String myOrders = '/buyer/orders';
  static const String orderDetail = '/buyer/orders/detail';
  static const String priceMonitoring = '/buyer/prices';
  static const String buyerAccount = '/buyer/account';
  static const String buyerEditProfile = '/buyer/account/edit';
  static const String buyerSettings = '/buyer/account/settings';
  static const String buyerRecentActivity = '/buyer/account/activity';
  static const String buyerNotifications = '/buyer/notifications';
  static const String buyerCart = '/buyer/browse/cart';
  static const String cartCheckoutResult = '/buyer/browse/cart/result';

  // ─── Admin — New Quick-Action Routes ─────────────────────────────────────────
  static const String adminInventory      = '/admin/inventory';
  static const String cropManagement      = '/admin/crops';
  static const String cropRequestApproval = '/admin/crops/requests';
  static const String programManagement   = '/admin/programs';
  static const String loanItemManagement  = '/admin/loan-items';
  static const String adminCalendar       = '/admin/calendar';
  static const String broadcastHistory    = '/admin/broadcast-history';

  // ─── Admin — Members sub-routes ──────────────────────────────────────────────
  static const String createAdminAccount    = '/admin/members/add-admin';
  static const String manageFarmerAccounts  = '/admin/members/farmer-accounts';
  static const String manageAdminAccounts   = '/admin/members/admin-accounts';
  static const String memberPrograms        = '/admin/members/programs';

  // ─── Admin — Marketplace Dashboard ───────────────────────────────────────────
  static const String adminMarketplace = '/admin/marketplace';
  static const String adminOrders      = '/admin/marketplace/orders';
  static const String adminOrderDetail = '/admin/marketplace/orders/detail';
  static const String offerToCooperative = '/admin/marketplace/offer-to-cooperative';

}