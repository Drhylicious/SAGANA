// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'SAGANA';

  @override
  String get appSubtitle => 'Streamlined Agricultural Gateway';

  @override
  String get cooperativeName => 'SP3 Agriculture Cooperative';

  @override
  String get secureGatewayActive => 'Secure Gateway Active';

  @override
  String get comingSoon => 'Coming Soon';

  @override
  String comingSoonMessage(String routeName) {
    return 'This screen ($routeName) is still under development.';
  }

  @override
  String get navHome => 'Home';

  @override
  String get navHarvest => 'Harvest';

  @override
  String get navMarketplace => 'Marketplace';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navProfile => 'Profile';

  @override
  String get greetingMorning => 'Good morning';

  @override
  String get greetingAfternoon => 'Good afternoon';

  @override
  String get greetingEvening => 'Good evening';

  @override
  String get defaultFarmerName => 'Farmer';

  @override
  String get offlineBanner =>
      'You are offline. Some features may be unavailable.';

  @override
  String get login => 'Log In';

  @override
  String get register => 'Register';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get confirmPassword => 'Confirm Password';

  @override
  String get fullName => 'Full Name';

  @override
  String get phoneNumber => 'Phone Number';

  @override
  String get forgotPassword => 'Forgot Password?';

  @override
  String get noAccount => 'Don\'t have an account?';

  @override
  String get haveAccount => 'Already have an account?';

  @override
  String get signUp => 'Sign Up';

  @override
  String get signOut => 'Sign Out';

  @override
  String get signOutConfirmTitle => 'Sign Out?';

  @override
  String get signOutConfirmMessage =>
      'You will be signed out of SAGANA. Offline records will remain on this device.';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get saveChanges => 'Save Changes';

  @override
  String get saving => 'Saving...';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get sectionAccount => 'Account';

  @override
  String get sectionNotifications => 'Notifications';

  @override
  String get sectionAppPreferences => 'App Preferences';

  @override
  String get sectionDataExport => 'Data Export';

  @override
  String get sectionSupportInfo => 'Support & Info';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get editProfileSubtitle => 'Name, phone number, sitio';

  @override
  String get editFarmDetails => 'Edit Farm Details';

  @override
  String get editFarmDetailsSubtitle => 'Farm name, land area, location';

  @override
  String get changePassword => 'Change Password';

  @override
  String get changePasswordSubtitle => 'Update your account password';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTagalog => 'Tagalog';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeLight => 'Light Mode';

  @override
  String get themeDark => 'Dark Mode';

  @override
  String get backgroundSync => 'Background Sync';

  @override
  String get backgroundSyncDescription =>
      'Automatically sync your data when internet connection is restored';

  @override
  String get clearCachedData => 'Clear Cached Data';

  @override
  String get clearCachedDataDescription =>
      'Removes locally cached price and market data. Your harvest and inventory records are not affected.';

  @override
  String get clearCachedDataConfirmTitle => 'Clear Cached Data?';

  @override
  String get clearCachedDataConfirmMessage =>
      'This removes locally cached price and market data. Your harvest records, inventory, and expenses are not affected.';

  @override
  String get clear => 'Clear';

  @override
  String get notifNewOrder => 'New Order Received';

  @override
  String get notifListingApproved => 'Listing Approved';

  @override
  String get notifListingChanges => 'Listing Changes Required';

  @override
  String get notifLoanReminder => 'Loan Payment Reminder';

  @override
  String get notifPriceUpdates => 'Price Updates';

  @override
  String get notifSyncCompleted => 'Sync Completed';

  @override
  String get currentPassword => 'Current Password';

  @override
  String get newPassword => 'New Password';

  @override
  String get confirmNewPassword => 'Confirm New Password';

  @override
  String get updatePassword => 'Update Password';

  @override
  String get updating => 'Updating...';

  @override
  String get passwordMinLength => 'Password must be at least 8 characters.';

  @override
  String get accountCreated => 'Account Created!';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String get selectAppearance => 'Select Appearance';

  @override
  String get adminProfileTitle => 'Admin Profile';

  @override
  String get adminProfileLoadError =>
      'Could not load your profile. Please try again.';

  @override
  String get adminProfileDefaultRole => 'Cooperative Administrator';

  @override
  String get adminProfileFullName => 'Full Name';

  @override
  String get adminProfilePhoneNumber => 'Phone Number';

  @override
  String get adminProfileSitio => 'Sitio / Purok';

  @override
  String get adminProfileSaveChanges => 'Save Changes';

  @override
  String get adminProfileSaving => 'Saving...';

  @override
  String get adminProfileNameRequired => 'Full name is required.';

  @override
  String get adminProfileUpdated => 'Profile updated successfully.';

  @override
  String get adminProfileSaveError => 'Failed to save. Please try again.';

  @override
  String get adminProfileChangePhoto => 'Change Photo';

  @override
  String get adminProfileRemovePhoto => 'Remove Photo';

  @override
  String get adminProfilePhotoUpdated => 'Profile photo updated.';

  @override
  String get adminProfilePhotoError =>
      'Could not update photo. Please try again.';

  @override
  String get adminProfileCurrentPassword => 'Current Password';

  @override
  String get adminProfileNewPassword => 'New Password';

  @override
  String get adminProfileConfirmPassword => 'Confirm New Password';

  @override
  String get adminProfilePasswordHint =>
      'Password must be at least 8 characters.';

  @override
  String get adminProfileAllFieldsRequired => 'All fields are required.';

  @override
  String get adminProfilePasswordTooShort =>
      'Password must be at least 8 characters.';

  @override
  String get adminProfilePasswordMismatch => 'Passwords do not match.';

  @override
  String get adminProfileUpdating => 'Updating...';

  @override
  String get adminProfileUpdatePassword => 'Update Password';

  @override
  String get adminProfilePasswordUpdated =>
      'Password updated. Please log in again.';

  @override
  String get adminProfileOrganizationalInfo => 'Organizational Information';

  @override
  String get adminProfileEmployeeId => 'Employee ID';

  @override
  String get adminProfilePosition => 'Position';

  @override
  String get adminProfileDepartment => 'Department';

  @override
  String get adminProfileAdminSince => 'Administrator Since';

  @override
  String get adminProfileOrgInfoHint =>
      'Organizational details are managed by cooperative records, not editable here.';

  @override
  String get adminProfilePreferences => 'Preferences';

  @override
  String get adminProfileDataAndStorage => 'Data & Storage';

  @override
  String get adminProfileClearCache => 'Clear Cached Data';

  @override
  String get adminProfileClearCacheTitle => 'Clear Cached Data?';

  @override
  String get adminProfileClearCacheMessage =>
      'This removes locally cached price and market data. Your reports and records are not affected.';

  @override
  String get adminProfileClearCacheConfirm => 'Clear';

  @override
  String get adminProfileCacheCleared => 'Cache cleared.';

  @override
  String get adminProfileSignOut => 'Sign Out';

  @override
  String get adminProfileSignOutTitle => 'Sign Out?';

  @override
  String get adminProfileSignOutMessage => 'You will be signed out of SAGANA.';

  @override
  String get adminProfileSignOutConfirm => 'Sign Out';

  @override
  String adminProfileAppVersion(String version) {
    return 'SAGANA v$version';
  }

  @override
  String get adminNavDashboard => 'Dashboard';

  @override
  String get adminNavMembers => 'Members';

  @override
  String get adminNavListings => 'Listings';

  @override
  String get listingsPendingTitle => 'Listings';

  @override
  String get listingsAllButton => 'View All';

  @override
  String get adminNavLoans => 'Loans';

  @override
  String get adminNavReports => 'Reports';

  @override
  String get reportsHubTitle => 'Operational Reports';

  @override
  String get reportsPerformanceSummary => 'Performance Summary';

  @override
  String get reportsTotalHarvest => 'Total Harvest';

  @override
  String get reportsCoopSales => 'Coop Sales';

  @override
  String get reportsMarketplaceRevenue => 'Marketplace Revenue';

  @override
  String get reportsActiveLoans => 'Active Loans';

  @override
  String get reportsTotalExpenses => 'Total Expenses';

  @override
  String get reportsMemberParticipation => 'Member Participation';

  @override
  String get reportsDetailedReports => 'Detailed Reports';

  @override
  String get reportsManagementTools => 'Management Tools';

  @override
  String get reportsRecentReports => 'Recent Reports';

  @override
  String get reportsNoExportsYet =>
      'No exports yet. Generate one from Export Center.';

  @override
  String get reportsSalesReport => 'Sales Report';

  @override
  String get reportsExportComingSoon => 'Export coming soon';

  @override
  String get reportsTotalRevenue => 'Total Revenue';

  @override
  String get reportsTotalVolume => 'Total Volume';

  @override
  String get reportsTransactions => 'Transactions';

  @override
  String get reportsCropBreakdown => 'Palay vs. Peanut';

  @override
  String get reportsRevenueTrend => 'Revenue Trend';

  @override
  String get reportsNotEnoughTrendData => 'Not enough data for a trend yet.';

  @override
  String get reportsTransactionDetails => 'Transaction Details';

  @override
  String get reportsSearchTransactions => 'Search farmer, crop, or reference';

  @override
  String get reportsNoSalesRecorded =>
      'No cooperative sales recorded for this period.';

  @override
  String get reportsNoSearchResults => 'No transactions match your search.';

  @override
  String get reportsInventoryReport => 'Inventory Report';

  @override
  String get reportsHarvestReport => 'Harvest Report';

  @override
  String get reportsTotalYield => 'Total Yield';

  @override
  String get reportsGradeAShare => 'Grade A Share';

  @override
  String get reportsUnsyncedEntries => 'Unsynced Entries';

  @override
  String get reportsYieldByCrop => 'Yield by Crop';

  @override
  String get reportsYieldTrend => 'Yield Trend';

  @override
  String get reportsHarvestEntries => 'Harvest Entries';

  @override
  String get reportsSearchHarvests => 'Search farmer or crop';

  @override
  String get reportsNoHarvestsRecorded =>
      'No harvests recorded for this period.';

  @override
  String get reportsToCoop => 'To Coop';

  @override
  String get reportsNotToCoop => 'Not to Coop';

  @override
  String get reportsSynced => 'Synced';

  @override
  String get reportsPendingSync => 'Pending Sync';

  @override
  String get reportsExpenseReport => 'Expense Report';

  @override
  String get reportsFarmerFundedTotal => 'Farmer-Funded Total';

  @override
  String get reportsSubsidizedItems => 'Subsidized Items';

  @override
  String get reportsTotalEntries => 'Total Entries';

  @override
  String get reportsExpensesByCategory => 'Expenses by Category';

  @override
  String get reportsSubsidizedTag => 'SUBSIDIZED';

  @override
  String get reportsSpendingTrend => 'Spending Trend';

  @override
  String get reportsExpenseEntries => 'Expense Entries';

  @override
  String get reportsSearchExpenses => 'Search farmer, category, or description';

  @override
  String get reportsNoExpensesRecorded =>
      'No expenses recorded for this period.';

  @override
  String get reportsCollectionTrend => 'Collection Trend';

  @override
  String get reportsNoSearchResultsOrLoans => 'No loans match these filters.';

  @override
  String get reportsLoanReport => 'Loan Report';

  @override
  String get reportsMemberContributionReport => 'Member Contribution Report';

  @override
  String reportsTotalCoopSalesLabel(int year) {
    return 'Total Cooperative Sales ($year)';
  }

  @override
  String get reportsContributingMembers => 'Contributing Members';

  @override
  String get reportsParticipationRate => 'Participation Rate';

  @override
  String get reportsMemberBreakdown => 'Member Breakdown';

  @override
  String get reportsSearchMembers => 'Search member name or ID';

  @override
  String reportsSharePercent(String percent) {
    return '$percent% share';
  }

  @override
  String get reportsPalay => 'Palay';

  @override
  String get reportsPeanut => 'Peanut';

  @override
  String get reportsNoContributionYet =>
      'No sales recorded to the cooperative this year.';

  @override
  String get reportsAnalyticsDashboard => 'Analytics Dashboard';

  @override
  String get reportsBalikTangkilikManagement => 'Balik-Tangkilik Management';

  @override
  String get balikTangkilikSettingsTab => 'Settings';

  @override
  String get balikTangkilikDistributionTab => 'Distribution';

  @override
  String get balikTangkilikHistoryTab => 'History';

  @override
  String get balikTangkilikHistoryTitle => 'Distribution History';

  @override
  String get balikTangkilikNoHistoryYet =>
      'No distributions have been recorded yet.';

  @override
  String balikTangkilikYearLogTitle(int year) {
    return '$year Distribution';
  }

  @override
  String balikTangkilikYearLogSubtitle(int count) {
    return '$count members paid';
  }

  @override
  String get balikTangkilikDistributionComingSoon =>
      'Distribution planning is coming soon.';

  @override
  String get balikTangkilikHistoryComingSoon =>
      'History tracking is coming soon.';

  @override
  String get balikTangkilikTotalCoopSales => 'Total Cooperative Sales';

  @override
  String get balikTangkilikPoolAmount => 'Distributable Pool Amount';

  @override
  String get balikTangkilikInterestRate => 'Interest Rate (%)';

  @override
  String balikTangkilikLiveTotalHint(String amount) {
    return 'Live total from recorded sales: $amount';
  }

  @override
  String get balikTangkilikUseThisValue => 'Use this live total';

  @override
  String get balikTangkilikPoolHint =>
      'Enter the amount available for distribution to members.';

  @override
  String get balikTangkilikInterestHint =>
      'Enter the annual interest rate for the pool.';

  @override
  String get balikTangkilikAfsFinalized => 'AFS Finalized';

  @override
  String get balikTangkilikAfsFinalizedHint =>
      'Mark this as finalized after the annual financial statement is approved.';

  @override
  String get balikTangkilikSaveSettings => 'Save Settings';

  @override
  String get balikTangkilikInvalidValues =>
      'Please enter valid non-negative values for all fields.';

  @override
  String get balikTangkilikZeroPoolWarningTitle => 'Zero pool amount?';

  @override
  String get balikTangkilikZeroPoolWarningMessage =>
      'Saving a zero distributable pool while the AFS is finalized may block future distribution. Continue anyway?';

  @override
  String get balikTangkilikContinueAnyway => 'Continue Anyway';

  @override
  String balikTangkilikSettingsSaved(int year) {
    return 'Settings saved for $year.';
  }

  @override
  String get balikTangkilikSaveError =>
      'Could not save the Balik-Tangkilik settings. Please try again.';

  @override
  String get balikTangkilikMemberBreakdown => 'Member Breakdown';

  @override
  String get balikTangkilikRefreshEstimates => 'Refresh Estimates';

  @override
  String get balikTangkilikEstimatesRefreshed => 'Estimates refreshed.';

  @override
  String get balikTangkilikRefreshError =>
      'Could not refresh estimates. Please try again.';

  @override
  String get balikTangkilikAfsNotFinalizedWarning =>
      'AFS is not finalized for this year. Go to the Settings tab to finalize it before distribution can be recorded.';

  @override
  String balikTangkilikAlreadyDistributedBanner(int year) {
    return 'Balik-Tangkilik for $year has already been distributed.';
  }

  @override
  String balikTangkilikTotalEstimated(int year) {
    return 'Total Estimated Payout ($year)';
  }

  @override
  String balikTangkilikTotalDistributed(int year) {
    return 'Total Distributed ($year)';
  }

  @override
  String get balikTangkilikRecordDistribution => 'Record Distribution';

  @override
  String balikTangkilikAlreadyDistributed(int year) {
    return 'Already Distributed for $year';
  }

  @override
  String get balikTangkilikConfirmTitle => 'Confirm Distribution';

  @override
  String balikTangkilikConfirmMessage(int year, int count, String amount) {
    return 'You are about to finalize Balik-Tangkilik for $year for $count contributing members, totaling $amount.';
  }

  @override
  String get balikTangkilikIrreversibleWarning =>
      'This action is permanent and cannot be undone.';

  @override
  String get balikTangkilikConfirmDistribute => 'Distribute Now';

  @override
  String balikTangkilikDistributionSuccess(String amount) {
    return 'Distribution recorded. Total paid out: $amount.';
  }

  @override
  String get balikTangkilikDistributionError =>
      'Could not record distribution. Please try again.';

  @override
  String get exportSelectReports => 'Select Reports';

  @override
  String get exportPeriod => 'Period';

  @override
  String get exportYearForContributionReport =>
      'Member Contribution Report uses a specific year, not a period:';

  @override
  String get exportSelectAtLeastOne => 'Select at least one report to export.';

  @override
  String get exportGenerateButton => 'Generate Export';

  @override
  String exportGenerated(int count) {
    return '$count file(s) generated.';
  }

  @override
  String get exportGenerateError =>
      'Could not generate export. Please try again.';

  @override
  String get exportFileMissing => 'This file no longer exists on this device.';

  @override
  String get exportSummaryEmpty =>
      'Select one or more reports to export as CSV.';

  @override
  String exportSummary(int count) {
    return '$count report(s) will be exported as separate CSV files.';
  }

  @override
  String get exportRecentExports => 'Recent Exports';

  @override
  String get exportNoHistoryYet => 'No exports generated yet on this device.';

  @override
  String get reportsExportCenter => 'Export Center';

  @override
  String get adminUrgentActions => 'Urgent Actions';

  @override
  String get adminQuickActions => 'Quick Actions';

  @override
  String get adminToolsManagement => 'Tools & Management';

  @override
  String get adminRecentActivity => 'Recent Activity';

  @override
  String get adminGoToLoanPayments => 'Go to Loan Payments →';

  @override
  String get analyticsMemberParticipation => 'Member Participation';

  @override
  String get analyticsActiveHarvested => 'Harvested';

  @override
  String get analyticsActiveListed => 'Listed Only';

  @override
  String get analyticsInactive => 'Inactive';

  @override
  String analyticsSendReminder(int count) {
    return 'Send Reminder ($count)';
  }

  @override
  String get analyticsSendReminderTitle => 'Send reminder?';

  @override
  String analyticsSendReminderMessage(int count) {
    return 'This will notify $count inactive members to check in with the cooperative.';
  }

  @override
  String get analyticsSendReminderConfirm => 'Send';

  @override
  String get analyticsReminderNotifTitle => 'We miss you at SP3!';

  @override
  String get analyticsReminderNotifBody =>
      'It\'s been a while since your last harvest or listing. Reach out to the cooperative if you need any help.';

  @override
  String analyticsReminderSent(int count) {
    return 'Reminder sent to $count members.';
  }

  @override
  String get analyticsReminderError =>
      'Could not send reminders. Please try again.';

  @override
  String get analyticsLoanHealth => 'Loan Collection Health';

  @override
  String get analyticsCollectionRate => 'collection rate';

  @override
  String get analyticsPriceSnapshot => 'Price Snapshot';

  @override
  String get analyticsViewFullPrices => 'View Full Price Trends →';

  @override
  String get analyticsNoForecastsYet =>
      'Forecasts will appear once enough cooperative-wide harvest history is recorded.';

  @override
  String get adminCoopPerformanceTitle => 'Cooperative Performance Summary';

  @override
  String get adminUrgentActionsTitle => 'Urgent Actions';

  @override
  String get adminInventoryAlertsTitle => 'Inventory Alerts';

  @override
  String get adminCalendarTitle => 'Cooperative Calendar';

  @override
  String get adminManagementModulesTitle => 'Management Modules';

  @override
  String get adminRecentActivityTitle => 'Recent Activity';

  @override
  String get adminViewInventory => 'View Inventory';

  @override
  String get adminViewFullCalendar => 'Full Calendar';

  @override
  String get adminNoRecentActivity => 'No recent activity';

  @override
  String get reportsAvailable => 'Available';

  @override
  String get reportsReserved => 'Reserved';

  @override
  String get reportsSold => 'Sold';

  @override
  String reportsLowStockAlert(int count) {
    return '$count batches are running low on stock.';
  }

  @override
  String get reportsStockByCrop => 'Stock by Crop';

  @override
  String get reportsInventoryBatches => 'Inventory Batches';

  @override
  String get reportsSearchBatches => 'Search farmer, crop, or batch number';

  @override
  String get reportsNoInventoryYet => 'No inventory batches recorded yet.';

  @override
  String get reportsLowStockBadge => 'LOW STOCK';

  @override
  String get loanDashTitle => 'Loan Management';

  @override
  String get loanDashNextCollection => 'Next Payment Collection';

  @override
  String loanDashFarmersOutstanding(int count) {
    return '$count farmers have outstanding balances';
  }

  @override
  String loanDashTotalExpected(String amount) {
    return 'Total expected: $amount';
  }

  @override
  String get loanDashActiveLoans => 'Active Loans';

  @override
  String get loanDashTotalOutstanding => 'Total Outstanding';

  @override
  String get loanDashOverdueLoans => 'Overdue Loans';

  @override
  String get loanDashPaidThisMonth => 'Paid This Month';

  @override
  String get loanDashActionIssue => 'Issue New Loan';

  @override
  String get loanDashActionRecordPayment => 'Record Payment';

  @override
  String get loanDashActionViewHistory => 'View History';

  @override
  String loanDashOverdueSection(int count) {
    return 'Overdue Loans ($count)';
  }

  @override
  String get loanDashActiveSection => 'Active Loans';

  @override
  String get loanDashSeeAll => 'See all';

  @override
  String get loanDashNoOverdue => 'No overdue loans right now.';

  @override
  String get loanDashNoActive => 'No active loans right now.';

  @override
  String get loanDashValue => 'Value';

  @override
  String get loanDashPaid => 'Paid';

  @override
  String get loanDashBalance => 'Balance';

  @override
  String get loanDashNext => 'Next';

  @override
  String loanDashOverdueSince(String date) {
    return 'Overdue since $date';
  }

  @override
  String get loanHistoryTitle => 'Loan History';

  @override
  String get loanHistoryExportUnavailable => 'Export coming soon';

  @override
  String get loanHistoryUnavailableOffline =>
      'Loan history requires an internet connection to load.';

  @override
  String get loanHistoryNoResults => 'No loans match these filters.';

  @override
  String get loanHistoryAllTimeSummary => 'All-Time Loan Summary';

  @override
  String get loanHistoryRate => 'Rate';

  @override
  String loanHistoryTotalIssued(int count) {
    return '$count Loans';
  }

  @override
  String get loanHistoryTotalCollected => 'Total Collected';

  @override
  String get loanHistoryHealthy => 'Healthy';

  @override
  String get loanHistoryNeedsAttention => 'Needs Attention';

  @override
  String get loanHistoryFilterAll => 'All';

  @override
  String get loanHistoryFilterPaid => 'Paid';

  @override
  String get loanHistoryThisMonth => 'This Month';

  @override
  String get loanHistoryThisQuarter => 'This Quarter';

  @override
  String get loanHistoryThisYear => 'This Year';

  @override
  String get loanHistoryAllTime => 'All Time';

  @override
  String get loanHistorySearchHint => 'Search farmer, reference, or member ID';

  @override
  String get adminPriceManagement => 'Price Management';

  @override
  String get adminPriceManagementSubtitle =>
      'Update crop buying and market prices for all members';

  @override
  String get adminNotificationBroadcast => 'Notification Broadcast';

  @override
  String get adminNotificationBroadcastSubtitle =>
      'Send announcements to farmers, buyers, or specific groups';

  @override
  String get adminSupplyChainMap => 'Supply Chain Map';

  @override
  String get adminSupplyChainMapSubtitle =>
      'View all farmer locations and crop distribution';

  @override
  String get adminReviewListings => 'Review\nListings';

  @override
  String get adminRecordPayment => 'Record\nPayment';

  @override
  String get adminUpdatePrice => 'Update\nPrice';

  @override
  String get adminIssueLoan => 'Issue\nLoan';

  @override
  String get adminViewReports => 'View\nReports';

  @override
  String get adminManageFarmers => 'Manage\nFarmers';

  @override
  String get issueLoanTitle => 'Issue New Loan';

  @override
  String get issueLoanSelectFarmer => 'Select Farmer';

  @override
  String get issueLoanSearchFarmerHint => 'Search by name or member ID';

  @override
  String get issueLoanNoFarmerSelected => 'Tap to select a farmer';

  @override
  String get issueLoanOutstandingBalance => 'Outstanding Balance';

  @override
  String get issueLoanOverdueWarning => 'This farmer has an overdue loan.';

  @override
  String get issueLoanStandingUnavailableOffline =>
      'Outstanding balance unavailable while offline.';

  @override
  String get issueLoanInputItems => 'Input Items';

  @override
  String get issueLoanAddItem => 'Add Input Item';

  @override
  String get issueLoanNoItemsYet => 'No items added yet.';

  @override
  String get issueLoanItemName => 'Item Name';

  @override
  String get issueLoanQuantity => 'Quantity';

  @override
  String get issueLoanUnit => 'Unit';

  @override
  String get issueLoanUnitPrice => 'Unit Price';

  @override
  String get issueLoanLineTotal => 'Item Total';

  @override
  String get issueLoanConfirmItem => 'Confirm';

  @override
  String get issueLoanCancel => 'Cancel';

  @override
  String get issueLoanTotalValue => 'Total Loan Value';

  @override
  String get issueLoanPaymentSchedule => 'Payment Schedule';

  @override
  String get issueLoanIssuedDate => 'Issue Date';

  @override
  String get issueLoanMonthlyPayment => 'Monthly Payment';

  @override
  String get issueLoanNextPaymentDue => 'Next Payment Due';

  @override
  String get issueLoanFrequency => 'Frequency: Monthly';

  @override
  String get issueLoanVenue => 'Venue: Barangay Payanas';

  @override
  String get issueLoanNotes => 'Notes (optional)';

  @override
  String get issueLoanSubmit => 'Issue Loan';

  @override
  String issueLoanSuccess(String reference) {
    return 'Loan $reference issued successfully.';
  }

  @override
  String get issueLoanQueuedOffline =>
      'Saved locally. Reference number will be assigned automatically once synced online.';

  @override
  String get issueLoanErrorNoFarmer => 'Please select a farmer first.';

  @override
  String get issueLoanErrorNoItems => 'Please add at least one input item.';

  @override
  String get issueLoanErrorInvalidMonthly =>
      'Monthly payment must be greater than zero.';

  @override
  String get issueLoanErrorGeneric => 'Something went wrong. Please try again.';

  @override
  String get paymentTitle => 'Record Payment';

  @override
  String get paymentChangeFarmer => 'Change';

  @override
  String get paymentSearchHint => 'Search by name or member ID';

  @override
  String get paymentNoFarmersFound => 'No farmers found.';

  @override
  String get paymentNoActiveLoans => 'No active loans';

  @override
  String get paymentSelectLoan => 'Select which loan to pay';

  @override
  String get paymentAmountReceived => 'Amount Received';

  @override
  String get paymentOverpaymentNotice => 'This exceeds the remaining balance.';

  @override
  String get paymentRemainingAfter => 'Remaining After';

  @override
  String get paymentDate => 'Payment Date';

  @override
  String get paymentNotes => 'Notes (optional)';

  @override
  String get paymentSubmit => 'Record Payment';

  @override
  String paymentSubmitWithAmount(String amount) {
    return 'Record $amount Payment';
  }

  @override
  String paymentSuccess(String name) {
    return 'Payment recorded for $name.';
  }

  @override
  String get paymentQueuedOffline =>
      'Saved locally. Will sync when back online.';

  @override
  String get paymentQueuedTag => 'queued';

  @override
  String paymentSessionSummary(int count, String total) {
    return '$count payments recorded — $total collected this session';
  }

  @override
  String get paymentErrorInvalidAmount => 'Enter an amount greater than zero.';

  @override
  String get paymentErrorGeneric => 'Something went wrong. Please try again.';

  @override
  String get paymentOverpaymentTitle => 'Amount exceeds balance';

  @override
  String paymentOverpaymentMessage(String excess) {
    return 'This payment is $excess more than the remaining balance. The loan will be marked as fully paid. Continue?';
  }

  @override
  String get paymentOverpaymentConfirm => 'Yes, continue';

  @override
  String get loanDetailsTitle => 'Loan Details';

  @override
  String get loanDetailsNotFound => 'Loan not found.';

  @override
  String get loanDetailsUnavailableOffline =>
      'Loan details require an internet connection to load.';

  @override
  String get loanDetailsMarkPaid => 'Mark as Paid';

  @override
  String get loanDetailsMarkPaidTitle => 'Mark this loan as paid?';

  @override
  String get loanDetailsMarkPaidMessage =>
      'This settles the loan without recording an additional payment. Use this only for corrections or approved write-offs.';

  @override
  String get loanDetailsMarkPaidReasonHint => 'Reason (optional)';

  @override
  String get loanDetailsMarkPaidConfirm => 'Mark as Paid';

  @override
  String get loanDetailsMarkPaidSuccess => 'Loan marked as paid.';

  @override
  String get loanDetailsMarkPaidError =>
      'Could not update the loan. Please try again.';

  @override
  String get loanDetailsPaymentHistory => 'Payment History';

  @override
  String get loanDetailsNoPayments => 'No payments recorded yet.';

  @override
  String get loanDetailsNotesLabel => 'Notes';

  @override
  String loanDetailsBalanceAfter(String amount) {
    return 'Balance after: $amount';
  }

  @override
  String loanDetailsPaidBy(String name) {
    return 'By $name';
  }

  @override
  String get farmerMgmtTitle => 'Farmer Management';

  @override
  String get farmerMgmtAdd => 'Add';

  @override
  String get seeAll => 'See All';

  @override
  String get priceManagementTitle => 'Price Management';

  @override
  String get supplyChainTitle => 'Supply Chain Map';

  @override
  String get priceLiveRates => 'Live Market Rates';

  @override
  String get priceMarketTrends => 'Market Trends';

  @override
  String get priceAddNew => 'Add Price Entry';

  @override
  String get priceOfflineWarning => 'Price updates disabled while offline.';

  @override
  String get broadcastCompose => 'Compose Message';

  @override
  String get broadcastUseTemplate => 'Use Template';

  @override
  String get broadcastPreview => 'Preview';

  @override
  String get broadcastRecent => 'Recent Broadcasts';

  @override
  String get broadcastTitle => 'Broadcast Announcements';

  @override
  String get broadcastSchedule => 'Schedule';

  @override
  String get broadcastScheduleSub => 'Send later at a specific time';
}
