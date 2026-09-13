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
  String get navListings => 'Listings';

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
  String get commonClose => 'Close';

  @override
  String get save => 'Save';

  @override
  String get saveChanges => 'Save Changes';

  @override
  String get saving => 'Saving...';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get sectionPersonalInformation => 'Personal Information';

  @override
  String get sectionSecurity => 'Security';

  @override
  String get emailAddress => 'Email Address';

  @override
  String get emailCannotBeChanged => 'Email address cannot be changed.';

  @override
  String get updateYourPassword => 'Update your password';

  @override
  String get sectionAccount => 'Account';

  @override
  String get sectionNotifications => 'Notifications';

  @override
  String get sectionAppPreferences => 'App Preferences';

  @override
  String get sectionDataExport => 'Data Export';

  @override
  String get sectionStorage => 'Storage';

  @override
  String get sectionSupportInfo => 'Support & Info';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get editProfileSubtitle => 'Name, phone number, purok';

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
  String get currentPasswordRequired => 'Current Password is required.';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match.';

  @override
  String get passwordUpdatedSigningOut => 'Password updated. Signing you out…';

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
  String get adminProfilePurok => 'Purok';

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
      'Organizational details are managed through cooperative administration records.';

  @override
  String get adminProfileFarmerAccounts => 'Farmer Accounts';

  @override
  String get adminProfileFarmerAccountsSubtitle => 'Manage Farmer Members';

  @override
  String get adminProfileOfficerAccounts => 'Officer Accounts';

  @override
  String get adminProfileOfficerAccountsSubtitle =>
      'Manage cooperative officers';

  @override
  String get adminProfileSystemOverview => 'System Overview';

  @override
  String get adminProfileSystemOverviewSubtitle =>
      'Open operational dashboards';

  @override
  String get adminProfileYourActivity => 'Your Activity';

  @override
  String get adminProfileActivitySummary => 'Activity Summary';

  @override
  String get adminProfileActivitySummaryCaption =>
      'See your recent administrative work at a glance.';

  @override
  String get adminProfileQuickAccess => 'Quick Access';

  @override
  String get adminProfileQuickAccessCaption =>
      'Open common admin workflows without leaving the profile.';

  @override
  String get adminProfileOrganizationalInfoCaption =>
      'This information is tied to your cooperative administration record.';

  @override
  String get adminProfileEmail => 'Email';

  @override
  String get adminProfileAccountStatus => 'Account Status';

  @override
  String get adminProfileManageAdminAccounts => 'Manage Admin Accounts';

  @override
  String get adminProfileManageAdminAccountsSubtitle =>
      'Create and review administrator access';

  @override
  String get adminProfileManageOfficerAccounts => 'Manage Officer Accounts';

  @override
  String get adminProfileManageOfficerAccountsSubtitle =>
      'Add and manage officers';

  @override
  String get adminProfileRecentActivity => 'Recent Activity';

  @override
  String get adminProfileRecentActivitySubtitle =>
      'Review recent admin actions';

  @override
  String get adminProfilePricesUpdated => 'Prices Updated';

  @override
  String get adminProfilePricesUpdatedCaption =>
      'Count of price records you\'ve entered';

  @override
  String get adminProfilePricesUpdatedSubtitle =>
      'Count of price records you\'ve entered';

  @override
  String get adminProfileBroadcastsSent => 'Broadcasts Sent';

  @override
  String get adminProfileBroadcastsSentCaption =>
      'Count of broadcasts you\'ve sent';

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
  String get reportsReminderTitle => 'Send reminder to inactive members';

  @override
  String get reportsReminderBody =>
      'This will notify inactive members to update their activity.';

  @override
  String get reportsReminderSent => 'Reminders sent.';

  @override
  String get reportsReminderFailed => 'Reminders could not be sent.';

  @override
  String get reportsNeedsAttention => 'Needs Attention';

  @override
  String get reportsReportingTools => 'Reporting Tools';

  @override
  String get reportsExportHistory => 'Export History';

  @override
  String get reportsExecutiveSnapshot => 'Executive Snapshot';

  @override
  String get reportsOverdueLoans => 'Overdue Loans';

  @override
  String get reportsInactiveMembers => 'Inactive Members';

  @override
  String get reportsRemindInactiveMembers => 'Remind';

  @override
  String get reportsAllClear => 'All clear';

  @override
  String get reportsLastExport => 'Last export';

  @override
  String get reportsQuickInsights => 'Quick Insights';

  @override
  String get reportsInsightTopCrop => 'Top Crop';

  @override
  String get reportsInsightTopFarmer => 'Top Contributor';

  @override
  String get reportsInsightTopExpense => 'Largest Expense';

  @override
  String get reportsViewAllExports => 'View All in Export Center';

  @override
  String get reportsSalesReport => 'Sales Report';

  @override
  String get reportsExportComingSoon => 'Export coming soon';

  @override
  String get reportsTotalRevenue => 'Total Revenue';

  @override
  String get reportsAvgSale => 'Avg Sale';

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
  String get reportsCoopStockReport => 'Cooperative Stock Report';

  @override
  String get reportsCoopStockByCategory => 'Stock by Category';

  @override
  String get reportsCoopStockItems => 'Stock Items';

  @override
  String get reportsTotalItems => 'Total Items';

  @override
  String get reportsLowStockItems => 'Low Stock';

  @override
  String get reportsCategories => 'Categories';

  @override
  String get reportsSearchItems => 'Search items…';

  @override
  String get reportsNoCoopStockYet => 'No cooperative stock recorded yet';

  @override
  String get reportsAll => 'All';

  @override
  String get reportsSoldOut => 'Sold Out';

  @override
  String get reportsInventoryReport => 'Farmer Harvest Report';

  @override
  String get reportsHarvestReport => 'Harvest Report';

  @override
  String get reportsTotalYield => 'Total Yield';

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
  String get reportsMemberContributionReport => 'Member Patronage Report';

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
  String balikTangkilikReconciliationHint(String entered, String liveTotal) {
    return 'The entered amount ($entered) differs from the live total ($liveTotal). Please reconcile before saving.';
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
      'Member Patronage Report uses a specific year, not a period:';

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
  String get reportsHarvestManagement => 'Harvest Report';

  @override
  String get reportsActivityTrendsTab => 'Activity & Trends';

  @override
  String get reportsBatchesStockTab => 'Batches & Stock';

  @override
  String get reportsViewBatch => 'View Batch';

  @override
  String get reportsViewHarvest => 'View Harvest';

  @override
  String get reportsHarvestedQty => 'Harvested';

  @override
  String get reportsTotalAvailableStock => 'Total Available Stock';

  @override
  String get reportsLiveLabel => 'Live';

  @override
  String get reportsNoBatchFound =>
      'No inventory batch found for this harvest.';

  @override
  String get reportsNoHarvestFound =>
      'Couldn\'t find the source harvest for this batch.';

  @override
  String get reportsSearchHarvestsWithBatch =>
      'Search farmer, crop, or batch number';

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
  String get loanDashOverdueHeroSubtitle =>
      'Review and follow up before the next BOD meeting.';

  @override
  String get loanDashReviewOverdue => 'Review Overdue Loans';

  @override
  String get loanDashActiveSection => 'Active Loans';

  @override
  String get loanDashRecentActivitySection => 'Loan History';

  @override
  String get loanDashSeeAll => 'See all';

  @override
  String get loanDashNoOverdue => 'No overdue loans right now.';

  @override
  String get loanDashNoActive => 'No active loans right now.';

  @override
  String get loanDashNoRecentActivity =>
      'No active or overdue loans right now.';

  @override
  String get loanDashSyncIssueIssuanceTitle => 'Loan Issuance Sync Issue';

  @override
  String get loanDashSyncIssuePaymentTitle => 'Loan Payment Sync Issue';

  @override
  String loanDashSyncIssueLastAttempt(String when) {
    return 'Last attempt: $when';
  }

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
  String get loanHistoryNoResultsForFilter =>
      'No loans match this status or period yet.';

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
  String get loanHistoryNoActivity => 'No Activity';

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
  String get loanHistoryFilterTitle => 'Filter Loans';

  @override
  String get loanHistoryApplyFilter => 'Apply';

  @override
  String get loanDashActionPayments => 'Record Payment';

  @override
  String get loanDashNoRecentActivitySubtitle =>
      'New loans and upcoming payments will appear here once recorded.';

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
  String get issueLoanNoFarmerResults => 'No farmers match your search.';

  @override
  String get issueLoanOutstandingBalance => 'Outstanding Balance';

  @override
  String get issueLoanOverdueWarning => 'This farmer has an overdue loan.';

  @override
  String get issueLoanStandingUnavailableOffline =>
      'Outstanding balance unavailable while offline.';

  @override
  String get issueLoanStandingLoading => 'Checking outstanding balance…';

  @override
  String get issueLoanInputItems => 'Input Items';

  @override
  String get issueLoanAddItem => 'Add Input Item';

  @override
  String get issueLoanNoItemsYet => 'No items added yet.';

  @override
  String get issueLoanSelectItem => 'Select Item';

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
  String paymentContextualTitle(String name) {
    return '$name\'s Loan';
  }

  @override
  String get paymentChangeFarmer => 'Change';

  @override
  String get paymentSwitchFarmer => 'Switch Farmer';

  @override
  String get paymentSearchHint => 'Search by name or member ID';

  @override
  String get paymentNoFarmersFound => 'No farmers found.';

  @override
  String get paymentNoActiveLoans => 'No active loans';

  @override
  String get paymentSelectLoan => 'Select which loan to pay';

  @override
  String get paymentDetailsSectionTitle => 'Payment Details';

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
  String loanDetailsContextualTitle(String reference) {
    return 'Loan $reference';
  }

  @override
  String get loanDetailsNotFound => 'Loan not found.';

  @override
  String get loanDetailsUnavailableOffline =>
      'Loan details require an internet connection to load.';

  @override
  String get loanDetailsMarkPaid => 'Mark as Paid';

  @override
  String get loanDetailsMarkPaidCaption =>
      'For corrections or approved write-offs only.';

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
  String get supplyChainTitle => 'Supply Chain Management';

  @override
  String get supplyChainOpsSummary => 'Operations Summary';

  @override
  String get supplyChainInsights => 'Actionable Insights';

  @override
  String get supplyChainFlow => 'Cooperative Flow';

  @override
  String get supplyChainPlannedOps => 'Planned Operations';

  @override
  String get supplyChainPlannedOpsDesc =>
      'Collection scheduling, warehouse movement tracking, and delivery logistics will appear here once the cooperative\'s real workflow is confirmed on-site.';

  @override
  String get supplyChainMapSection => 'Farmer Locations';

  @override
  String get supplyChainRefresh => 'Refresh';

  @override
  String get supplyChainAllMapped => 'All members have a mapped farm location.';

  @override
  String get supplyChainAllSubmitted =>
      'All harvests have been submitted to the cooperative.';

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

  @override
  String get buyerNavBrowse => 'Browse';

  @override
  String get buyerNavOrders => 'Orders';

  @override
  String get buyerNavPrices => 'Prices';

  @override
  String get buyerNavAccount => 'Account';

  @override
  String get buyerBrowseTitle => 'Marketplace';

  @override
  String get buyerBrowseSubtitle => 'Fresh produce from SP3 farmers';

  @override
  String get buyerBrowseSearchHint => 'Search crops or variety';

  @override
  String get buyerBrowseEmptyTitle => 'Marketplace is quiet right now';

  @override
  String get buyerBrowseEmptyBody =>
      'Check back soon for new listings from SP3 farmers.';

  @override
  String get buyerBrowseNoResultsTitle => 'No listings match your filters';

  @override
  String get buyerBrowseNoResultsBody =>
      'Try a different search term or category.';

  @override
  String get buyerBrowseSoldOut => 'Sold Out';

  @override
  String get buyerBrowseLowStock => 'Low Stock';

  @override
  String get buyerBrowseOrderNow => 'Order Now';

  @override
  String get buyerBrowseAvailableSuffix => 'available';

  @override
  String get buyerBrowseAboveMarketRange =>
      'Priced outside typical market range';

  @override
  String get dashboardAllClearTitle => 'All Clear';

  @override
  String get dashboardAllClearMessage =>
      'No urgent items today. Keep up the good work!';

  @override
  String get dashboardQuickActions => 'Quick Actions';

  @override
  String get quickActionRecordHarvest => 'Record Harvest';

  @override
  String get quickActionCreateListing => 'Create Listing';

  @override
  String get quickActionCheckPrices => 'Check Prices';

  @override
  String get purchaseSummary => 'Purchase Summary';

  @override
  String get recentActivity => 'Recent Activity';

  @override
  String get account => 'Account';

  @override
  String get buyerDefaultName => 'Buyer';

  @override
  String get statOrders => 'Orders';

  @override
  String get statCompleted => 'Completed';

  @override
  String get statSpent => 'Spent';

  @override
  String get buyerNoOrdersTitle => 'No orders yet';

  @override
  String get buyerNoOrdersSubtitle =>
      'Start browsing the marketplace to place your first order.';

  @override
  String get browseMarketplace => 'Browse Marketplace';

  @override
  String get buyerOrdersTitle => 'My Orders';

  @override
  String buyerOrdersTabPending(int count) {
    return 'Pending ($count)';
  }

  @override
  String buyerOrdersTabApproved(int count) {
    return 'Approved ($count)';
  }

  @override
  String buyerOrdersTabCompleted(int count) {
    return 'Completed ($count)';
  }

  @override
  String buyerOrdersTabCancelled(int count) {
    return 'Cancelled ($count)';
  }

  @override
  String get buyerOrdersEmptyPending => 'No pending orders';

  @override
  String get buyerOrdersEmptyApproved => 'No approved orders yet';

  @override
  String get buyerOrdersEmptyCompleted => 'No completed orders yet';

  @override
  String get buyerOrdersEmptyCancelled => 'No cancelled orders';

  @override
  String get buyerOrdersPickupBannerTitle => 'Order Ready for Pickup!';

  @override
  String buyerOrdersPickupBannerBody(int count, String cooperative) {
    return 'You have $count approved orders waiting for pickup at $cooperative.';
  }

  @override
  String get buyerOrdersQuantityLabel => 'Quantity';

  @override
  String get buyerOrdersTotalLabel => 'Total Amount';

  @override
  String buyerOrdersCancelledOn(String date) {
    return 'Cancelled on $date';
  }

  @override
  String get buyerOrdersViewPickupDetails => 'View Pickup Details';

  @override
  String get buyerOrdersReorder => 'Reorder';

  @override
  String get buyerOrdersBrowseAgain => 'Browse Again';

  @override
  String get buyerOrdersAwaitingReview => 'Awaiting cooperative review';

  @override
  String get buyerNotifMenuMarkAllRead => 'Mark all as read';

  @override
  String get buyerNotifMenuClearAll => 'Clear all';

  @override
  String get buyerNotifFilterAll => 'All';

  @override
  String get buyerNotifFilterListings => 'Listings';

  @override
  String get buyerNotifEmptyTitle => 'No notifications';

  @override
  String get buyerNotifEmptyBody =>
      'You\'ll see order and marketplace updates here.';

  @override
  String get buyerNotifClearDialogTitle => 'Clear All Notifications?';

  @override
  String get buyerNotifClearDialogMessage => 'This cannot be undone.';

  @override
  String get buyerNotifDialogClearAll => 'Clear All';

  @override
  String buyerNotifTimeMinutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String buyerNotifTimeHoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String get buyerNotifTimeYesterday => 'Yesterday';

  @override
  String buyerNotifTimeDaysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String get buyerActivityTitle => 'Recent Activity';

  @override
  String get buyerActivityViewAll => 'View All';

  @override
  String get buyerActivityEmpty => 'No recent activity';

  @override
  String get buyerPriceTitle => 'Market Prices';

  @override
  String get buyerPriceSearchLabel => 'Search';

  @override
  String get buyerPriceSearchHint => 'Search crops...';

  @override
  String get buyerPriceFilterAll => 'All';

  @override
  String get buyerPriceTypeSp3 => 'Cooperative Market Price';

  @override
  String get buyerPriceTypeMarketRef => 'Public Market Price';

  @override
  String get buyerPriceEmptyTitle => 'No price data yet';

  @override
  String get buyerPriceEmptyBody =>
      'Price data will appear here once SP3 Cooperative records market rates for a crop.';

  @override
  String get buyerPriceNoResultsTitle =>
      'No crops match your search or filters';

  @override
  String get buyerPriceClearFilters => 'Clear filters';

  @override
  String get buyerPriceListedTag => 'Currently available on marketplace';

  @override
  String get buyerPriceNotListedTag => 'Not currently listed';

  @override
  String get buyerPriceNoTrendHistory =>
      'Not enough history for a trend chart yet';

  @override
  String get buyerPriceStatHigh => 'High';

  @override
  String get buyerPriceStatLow => 'Low';

  @override
  String get buyerPriceStatCurrent => 'Current';

  @override
  String get buyerPriceFilterPanelTitle => 'Filter Market Prices';

  @override
  String get buyerPriceFilterPanelSubtitle =>
      'Refine the list by crop category or crop';

  @override
  String get buyerPriceFilterCategoryLabel => 'CROP CATEGORY';

  @override
  String get buyerPriceFilterCropLabel => 'CROP';

  @override
  String get buyerPriceResetAll => 'Reset All';

  @override
  String get buyerPriceApplyFilters => 'Apply Filters';

  @override
  String get buyerOrdersStatusPending => 'PENDING REVIEW';

  @override
  String get buyerOrdersStatusApproved => 'APPROVED';

  @override
  String get buyerOrdersStatusCompleted => 'COMPLETED';

  @override
  String get buyerOrdersStatusCancelled => 'CANCELLED';

  @override
  String get buyerActivityFilterProfile => 'Profile';

  @override
  String get buyerActivityOrderApproved => 'Order Approved';

  @override
  String get buyerActivityOrderCompleted => 'Order Completed';

  @override
  String get buyerActivityOrderCancelled => 'Order Cancelled';

  @override
  String get buyerActivityOrderUpdated => 'Order Updated';

  @override
  String get buyerActivityStatusCancelled => 'Cancelled';

  @override
  String get buyerActivityAllEmptyTitle => 'No activity yet';

  @override
  String get buyerActivityAllEmptyBody =>
      'Orders you place and profile changes you make will show up here.';

  @override
  String get buyerCartTitle => 'My Cart';

  @override
  String get buyerCartEmptyTitle => 'Your cart is empty';

  @override
  String get buyerCartEmptyBody =>
      'Add produce from the marketplace — you can queue up several items and check out at once.';

  @override
  String buyerCartPlacingOrder(int index, int total) {
    return 'Placing order $index of $total';
  }

  @override
  String buyerCartItemCount(int count) {
    return '$count items';
  }

  @override
  String buyerCartItemsFrom(int count, String cooperative) {
    return '$count items from $cooperative';
  }

  @override
  String get buyerCartProceedCheckout => 'Proceed to Checkout';

  @override
  String buyerCartAdjustedRemoved(String name) {
    return '$name is no longer available and was removed from your cart.';
  }

  @override
  String buyerCartAdjustedReduced(String name, String qty) {
    return '$name was reduced to ${qty}kg — only that much remains.';
  }

  @override
  String get buyerCartStockChangedTitle => 'Your cart was updated';

  @override
  String get buyerCartStockChangedBody =>
      'Stock changed since these items were added:';

  @override
  String get buyerCartReviewCart => 'Review Cart';

  @override
  String get buyerCartConfirmOrderTitle => 'Confirm Order';

  @override
  String get buyerCartTotalLabel => 'Total';

  @override
  String buyerCartPickupNotice(String location) {
    return 'Pickup at $location. No delivery — you must arrange transport.';
  }

  @override
  String get buyerCartConfirm => 'Confirm';

  @override
  String get photoUploadFailed => 'Photo upload failed. Please try again.';

  @override
  String get fullNameEmpty => 'Full name is required.';

  @override
  String get profileUpdated => 'Profile updated.';

  @override
  String get saveChangesFailed => 'Unable to save changes. Please try again.';

  @override
  String get changePhoto => 'Change Photo';

  @override
  String get personalInformation => 'Personal Information';

  @override
  String get updatePasswordSubtitle => 'Update your account password';

  @override
  String get aboutSagana => 'About SAGANA';

  @override
  String get aboutSaganaBody =>
      'SAGANA helps buyers connect with trusted SP3 farmers and manage purchases in one place.';

  @override
  String get adminAboutSaganaBody =>
      'SAGANA helps cooperative admins manage members, marketplace listings, loans, inventory, and reports in one place.';

  @override
  String get contactSp3 => 'Contact SP3';

  @override
  String get contactSp3Body =>
      'For concerns about your account, orders, or payments, please visit the cooperative office or reach out to your assigned coordinator.';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get privacyPolicyBody =>
      'Your account, order details, and contact information are kept secure and accessible only to authorized cooperative personnel.';

  @override
  String get termsOfUse => 'Terms of Use';

  @override
  String get termsOfUseBody =>
      'By using SAGANA, you agree to use the platform responsibly and follow cooperative policies.';

  @override
  String get logOut => 'Log Out';

  @override
  String buyerListingAddedToCart(String name) {
    return 'Added to cart — $name';
  }

  @override
  String get buyerListingViewCart => 'View Cart';

  @override
  String get buyerListingNotAvailable => 'This listing is no longer available.';

  @override
  String get buyerListingSp3Badge => '✓ SP3 Cooperative';

  @override
  String get buyerListingBatchNo => 'Batch No.';

  @override
  String get buyerListingHarvestDate => 'Harvest Date';

  @override
  String get buyerListingAvailable => 'Available';

  @override
  String get buyerListingCategory => 'Category';

  @override
  String get buyerListingSellingPrice => 'Selling Price';

  @override
  String get buyerListingWithinRange => 'Within market range';

  @override
  String get buyerListingAboveRange => 'Above market range';

  @override
  String buyerListingMarketRate(String price) {
    return 'Market Rate: ₱$price/kg';
  }

  @override
  String get buyerListingMoreFromSp3 => 'More from SP3';

  @override
  String get buyerListingAddToCart => 'Add to Cart';

  @override
  String buyerListingPlaceOrder(String total) {
    return 'Place Order — ₱$total';
  }

  @override
  String get buyerListingOrderQty => 'Order Quantity (kg)';

  @override
  String buyerListingMaxAvailable(String kg) {
    return 'Max: $kg kg available';
  }

  @override
  String get buyerListingPickupLocation => '📍 Pickup Location';

  @override
  String get buyerListingNoDelivery =>
      'No delivery available. Buyer must arrange transport.';

  @override
  String get buyerPricePerKg => 'Price per kg';

  @override
  String get buyerHarvestedToday => 'Harvested today';

  @override
  String get buyerHarvestedYesterday => 'Harvested yesterday';

  @override
  String buyerHarvestedDaysAgo(int count) {
    return 'Harvested $count days ago';
  }

  @override
  String buyerOrderDetailTitle(String ref) {
    return 'Order #$ref';
  }

  @override
  String get buyerOrderDetailNotFound => 'Order not found.';

  @override
  String get buyerOrderDetailReadyPickup => 'Ready for Pickup';

  @override
  String get buyerOrderDetailPickedUp => 'Picked up';

  @override
  String get buyerOrderDetailCancelledStatus => 'Order cancelled';

  @override
  String buyerOrderDetailMsgApproved(String cooperative) {
    return 'Your order has been approved by $cooperative. Please contact SP3 to arrange your pickup schedule.';
  }

  @override
  String buyerOrderDetailMsgPending(String cooperative) {
    return 'Your order is awaiting review by $cooperative. You\'ll be notified once it\'s approved.';
  }

  @override
  String get buyerOrderDetailMsgCompleted =>
      'This order has been picked up. Thank you for supporting SP3 farmers!';

  @override
  String get buyerOrderDetailMsgCancelled =>
      'This order was cancelled and is no longer active.';

  @override
  String get buyerOrderDetailContactCoop => 'Contact SP3 Cooperative';

  @override
  String get buyerOrderDetailComingSoon => 'SP3 contact number coming soon.';

  @override
  String get buyerOrderDetailStepPlaced => 'Order Placed';

  @override
  String get buyerOrderDetailStepPendingReview => 'Pending Review';

  @override
  String get buyerOrderDetailStepApproved => 'Approved';

  @override
  String get buyerOrderDetailStepCompleted => 'Completed';

  @override
  String get buyerOrderDetailPendingTimestamp => 'Pending';

  @override
  String get buyerOrderDetailJourney => 'Order Journey';

  @override
  String get buyerOrderDetailBatchRef => 'Batch Reference';

  @override
  String get buyerOrderDetailFreshness => 'Freshness';

  @override
  String get buyerOrderDetailSummary => 'Order Summary';

  @override
  String get buyerOrderDetailReferenceLabel => 'REFERENCE';

  @override
  String get buyerOrderDetailDateLabel => 'ORDER DATE';

  @override
  String get buyerOrderDetailPaymentInfo => 'PAYMENT INFORMATION';

  @override
  String get buyerOrderDetailPaymentBody =>
      'Payment for this order is collected at the time of pickup at the cooperative. SP3 accepts cash payment upon collection.';

  @override
  String get buyerOrderDetailPickupLocationTitle => 'Pickup Location';

  @override
  String get buyerOrderDetailBodSchedule => 'BOD Meeting Schedule';

  @override
  String get buyerOrderDetailBodBody =>
      'Every 1st Saturday of the month — payments and pickups can be coordinated during this meeting.';

  @override
  String get buyerOrderDetailNeedHelp => 'Need help with this order?';

  @override
  String get buyerOrderDetailSupportBody =>
      'Contact SP3 Agriculture Cooperative directly for assistance.';

  @override
  String get buyerOrderDetailCallCoop => 'Call SP3 Cooperative';

  @override
  String get buyerOrderDetailBrowseMore => 'Browse More Products';

  @override
  String get buyerOrderSuccessTitle => 'Order Placed!';

  @override
  String get buyerOrderSuccessSubtitle =>
      'SP3 Agriculture Cooperative will review your order shortly.';

  @override
  String get buyerOrderSuccessViewOrders => 'View My Orders';

  @override
  String get buyerOrderSuccessContinueShopping => 'Continue Shopping';

  @override
  String buyerCheckoutResultPartialTitle(int succeeded, int total) {
    return '$succeeded of $total Items Ordered';
  }

  @override
  String get buyerCheckoutResultPartialBody =>
      'Some items couldn\'t be ordered — see details below.';

  @override
  String get buyerCheckoutResultOrderedLabel => 'ORDERED';

  @override
  String get buyerCheckoutResultFailedLabel => 'COULDN\'T BE ORDERED';

  @override
  String buyerMemberSince(String date) {
    return 'Member since $date';
  }

  @override
  String get brandingTagline =>
      'Streamlined Agricultural Gateway for\nAgribusiness, Networking, and Analytics';

  @override
  String get brandingDevelopedBy =>
      'Developed by Marinduque State University — BSIT';

  @override
  String get brandingPartner => 'Partner: SP3 Agriculture Cooperative';

  @override
  String get registerFullNameHintFarmer =>
      'As it appears in cooperative records';

  @override
  String get registerFullNameHintBuyer => 'Your full name';

  @override
  String get registerEnterFullName => 'Enter your full name';

  @override
  String get registerCheckingName => 'Please wait — checking this name…';

  @override
  String get registerCheckingRegistry =>
      'Please wait — checking SP3 member registry…';

  @override
  String get registerChooseAvailableUsername =>
      'Please choose an available username.';

  @override
  String get registerNameTakenTitle => 'Name Already Registered';

  @override
  String get registerNameAlreadyRegistered =>
      'This full name is already registered. Please log in instead, or contact the SP3 Agriculture Cooperative if you believe this is a mistake.';

  @override
  String get registerRegistryMatchMessage =>
      'Your name was found in the official SP3 member registry. Your SAGANA username has been assigned automatically.';

  @override
  String get registerRegistryNoMatchMessage =>
      'Your name was not found in the SP3 member registry. You may still register — your application will be reviewed by the SP3 Cooperative.';

  @override
  String get registerPhoneOptional => 'Phone Number (optional)';

  @override
  String get registerInvalidPhone => 'Enter a valid PH number (09XXXXXXXXX)';

  @override
  String get registerEmailOptional => 'Email (optional)';

  @override
  String get registerInvalidEmail => 'Enter a valid email address';

  @override
  String get registerEmailTaken =>
      'This email address is already used by another account.';

  @override
  String get registerPurokOptional => 'Purok (optional)';

  @override
  String get registerDob => 'Date of Birth *';

  @override
  String get registerDobSelect => 'Select your date of birth';

  @override
  String get registerDobHelp => 'You must be at least 18 years old to join';

  @override
  String get registerGenderOptional => 'Gender (optional)';

  @override
  String get registerTitle => 'Create Account';

  @override
  String get registerSubtitle => 'Join the SP3 cooperative network';

  @override
  String get registerRoleFarmer => 'Farmer';

  @override
  String get registerRoleBuyer => 'Buyer';

  @override
  String get registerUsernameLabel => 'Choose a Username *';

  @override
  String get registerUsernameHint => 'e.g. juandelacruz';

  @override
  String get registerUsernameRequired => 'Choose a username';

  @override
  String get registerUsernameTooShort =>
      'Username must be at least 3 characters';

  @override
  String get registerUsernameTaken => 'This username is already taken';

  @override
  String get registerUsernameAvailable => 'Username is available!';

  @override
  String get registerUsernameNotAvailable => 'That username is taken.';

  @override
  String get registerPasswordLabel => 'Password *';

  @override
  String get registerPasswordTooShort =>
      'Password must be at least 8 characters';

  @override
  String get registerConfirmPasswordLabel => 'Confirm Password *';

  @override
  String get registerPasswordMismatch => 'Passwords do not match';

  @override
  String get registerWelcomeOfficialTitle => 'Welcome to SP3! 🌾';

  @override
  String get registerAccountCreatedTitle => 'Account Created';

  @override
  String registerWelcomeOfficialMessage(String username) {
    return 'Welcome, official SP3 member!\n\nYour SAGANA username is:\n$username\n\nPlease remember this username to log in.';
  }

  @override
  String registerFarmerCreatedMessage(String username) {
    return 'Account created successfully.\n\nYour username is:\n$username\n\nYour membership is pending verification by the SP3 Agriculture Cooperative. You will be notified once approved.';
  }

  @override
  String registerBuyerCreatedMessage(String username) {
    return 'Account created successfully.\n\nYou can now log in with your username:\n$username';
  }

  @override
  String get registerGoToLogin => 'Go to Login';

  @override
  String get registerAlreadyHaveAccount => 'Already have an account? ';

  @override
  String get registerSignIn => 'Sign In';

  @override
  String get registerOfficialMemberFound => 'Official SP3 Member Found ✓';

  @override
  String get registerNotInRegistry => 'Not in SP3 Registry';

  @override
  String get registerYourUsernameLabel => 'Your SAGANA Username';

  @override
  String get registerUsernameAutoGenerated =>
      'Auto-generated · Cannot be changed';

  @override
  String get registerGenderMale => 'Male';

  @override
  String get registerGenderFemale => 'Female';

  @override
  String get registerGenderPreferNotToSay => 'Prefer not to say';

  @override
  String issueLoanCapitalIneligible(String current, String minimum) {
    return 'Capital contribution ₱$current — below the ₱$minimum minimum required for a loan.';
  }

  @override
  String issueLoanCapitalBlocked(String minimum) {
    return 'This member has not met the ₱$minimum minimum capital contribution required to be issued a loan.';
  }

  @override
  String get addMemberTitle => 'Add New Member';

  @override
  String get addMemberSave => 'Save';

  @override
  String get addMemberAdminNoticeTitle => 'Admin Notice';

  @override
  String get addMemberAdminNoticeBody =>
      'The member will be created with active status and can log in immediately using the credentials below.';

  @override
  String get addMemberSectionCredentials => 'Account Credentials';

  @override
  String get addMemberUsernameLabel => 'SAGANA Username';

  @override
  String get addMemberUsernameRequired => 'Username is required';

  @override
  String get addMemberUsernameHelp =>
      'Automatically generated — Admin-created Farmer accounts are reserved for official SP3 members.';

  @override
  String get addMemberPasswordLabel => 'Temporary Password';

  @override
  String get addMemberPasswordRequired => 'Password is required';

  @override
  String get addMemberPasswordTooShort => 'Minimum 8 characters';

  @override
  String get addMemberSectionPersonal => 'Personal Information';

  @override
  String get addMemberFullNameLabel => 'Full Name';

  @override
  String get addMemberFullNameHint => 'As it appears in cooperative records';

  @override
  String get addMemberFullNameRequired => 'Full name is required';

  @override
  String get addMemberRegistryMatch =>
      'Matched the SP3 member registry — Purok and phone auto-filled.';

  @override
  String get addMemberRegistryNoMatch =>
      'Not in the SP3 member registry. You can still create the account.';

  @override
  String get addMemberPhoneLabel => 'Phone Number (optional)';

  @override
  String get addMemberPhoneInvalid => 'Invalid PH number';

  @override
  String get addMemberPurokLabel => 'Purok';

  @override
  String get addMemberSelectHint => 'Select';

  @override
  String get addMemberDobLabel => 'Date of Birth (18+)';

  @override
  String get addMemberGenderLabel => 'Gender';

  @override
  String get addMemberSectionMembership => 'Cooperative Membership';

  @override
  String get addMemberMemberIdLabel => 'Member ID';

  @override
  String get addMemberMemberIdHelp =>
      'Auto-generated (SP3-year-sequence) — assigned on save, cannot be edited. Distinct from the login username.';

  @override
  String get addMemberShareValueLabel => 'Share Value (₱)';

  @override
  String get addMemberInitialContributionLabel => 'Initial Contribution (₱)';

  @override
  String get addMemberInvalidNumber => 'Invalid number';

  @override
  String get addMemberContributionHelp =>
      'Optional opening capital. Members build toward the ₱2,000 annual share; ₱100/month minimum. More payments are recorded later from the member\'s record.';

  @override
  String get addMemberSectionCrops => 'Initial Crops';

  @override
  String get addMemberAddCrop => 'Add Crop';

  @override
  String get addMemberNoCropsYet => 'No crops added yet';

  @override
  String get addMemberSelectCropTitle => 'Select Crop';

  @override
  String get addMemberNoCatalogCrops =>
      'No active crops in Crop Management yet.';

  @override
  String get addMemberAllCropsAdded => 'All catalog crops have been added.';

  @override
  String get addMemberClose => 'Close';

  @override
  String get addMemberSelectPurok => 'Please select a purok.';

  @override
  String get addMemberAgeRequirement =>
      'The member must be at least 18 years old.';

  @override
  String addMemberCreatedSuccess(String name) {
    return '$name was added successfully.';
  }

  @override
  String addMemberPartialIssue(String step, String message) {
    return '$step step had an issue: $message';
  }

  @override
  String get addMemberCreateFailed =>
      'Failed to create member. Please try again.';

  @override
  String get addMemberUsernameTakenRetry =>
      'That username was just taken — a new one has been generated. Please try again.';

  @override
  String get addMemberOffline => 'Offline — Cannot Create Account';

  @override
  String get addMemberCreating => 'Creating Account...';

  @override
  String get addMemberCreateButton => 'Create Farmer Account';

  @override
  String get pendingNavHome => 'Home';

  @override
  String get pendingNavUpdates => 'Updates';

  @override
  String get pendingNavHelp => 'Help';

  @override
  String get pendingNavProfile => 'Profile';

  @override
  String get pendingHomeTitle => 'SP3 Cooperative';

  @override
  String pendingWelcome(String name) {
    return 'Welcome, $name!';
  }

  @override
  String get pendingBannerApproved =>
      'Your membership has been approved. Tap Continue below to activate your farmer access.';

  @override
  String get pendingBannerRejected =>
      'Your application was not approved. Review your details below and resubmit when ready.';

  @override
  String get pendingBannerDraft =>
      'Your account is ready. Review the details below, then send your application to the cooperative.';

  @override
  String get pendingBannerPending =>
      'Your application has been received and is being reviewed by the cooperative administration. You\'ll be notified here once a decision is made.';

  @override
  String get pendingOfflineBanner =>
      'You\'re offline — updates to your application won\'t come through until you\'re reconnected.';

  @override
  String get pendingApplicationStatusTitle => 'Application Status';

  @override
  String get pendingBadgeApproved => 'APPROVED';

  @override
  String get pendingBadgeRejected => 'NOT APPROVED';

  @override
  String get pendingBadgeDraft => 'NOT SUBMITTED';

  @override
  String get pendingBadgePending => 'PENDING REVIEW';

  @override
  String pendingYourUsername(String username) {
    return 'Your username: $username';
  }

  @override
  String pendingApprovedMessage(String name) {
    return 'Welcome to the SP3 Agriculture Cooperative, $name! Tap Continue to acknowledge and unlock your farmer features.';
  }

  @override
  String get pendingContinueButton => 'Continue to SAGANA';

  @override
  String get pendingRejectedReasonTitle => 'Reason from the cooperative';

  @override
  String get pendingNoReasonProvided => 'No reason was provided.';

  @override
  String pendingAttemptsRemaining(int count) {
    return 'Review and update your details, then resubmit. Attempts remaining: $count of 3.';
  }

  @override
  String get pendingAttemptsExhausted =>
      'You have used all 3 application attempts. Please visit the SP3 Cooperative office to continue.';

  @override
  String get pendingReviewEditButton => 'Review & Edit Details';

  @override
  String get pendingResubmitButton => 'Resubmit Application';

  @override
  String get pendingDraftMessage =>
      'Your application has not been sent yet. Check that your details below are correct, then submit to the cooperative for review.';

  @override
  String get pendingSubmitButton => 'Submit Application';

  @override
  String get pendingStepSubmitted => 'Application Submitted';

  @override
  String get pendingStepSubmittedSub => 'Sent to the cooperative for review';

  @override
  String get pendingStepReview => 'Under Review';

  @override
  String get pendingStepReviewSub => 'SP3 Admin is reviewing your application';

  @override
  String get pendingStepDecision => 'Decision';

  @override
  String get pendingStepDecisionSub =>
      'You are notified here — approved or not';

  @override
  String get pendingContactAddress => 'Barangay Payanas, Torrijos, Marinduque';

  @override
  String get pendingContactBod =>
      'BOD Meetings: Every 1st Saturday of the month';

  @override
  String get pendingContactMembers => '52 registered cooperative members';

  @override
  String pendingSubmittedToast(int attempt) {
    return 'Application submitted (attempt $attempt of 3).';
  }

  @override
  String get pendingDetailsUpdatedToast => 'Details updated.';

  @override
  String get pendingNotificationsTitle => 'Notifications';

  @override
  String get pendingNoNotifications => 'No notifications yet';

  @override
  String get pendingNoNotificationsSub =>
      'You\'ll be notified here when your\nmembership application is updated.';

  @override
  String get pendingHelpTitle => 'Help & FAQ';

  @override
  String get pendingHelpIntro =>
      'Your application is under review. Here are answers to common questions while you wait.';

  @override
  String get pendingFaq1Q =>
      'Why can\'t I access Harvest, Loans, or Marketplace?';

  @override
  String get pendingFaq1A =>
      'These features are exclusive to official SP3 cooperative members. They will become available automatically once an Administrator approves your membership application.';

  @override
  String get pendingFaq2Q => 'How long does the approval process take?';

  @override
  String get pendingFaq2A =>
      'The cooperative administrator reviews applications at their earliest convenience, usually during or after BOD meetings held on the first Saturday of every month. If your application has been pending for more than one month, please contact the cooperative office directly.';

  @override
  String get pendingFaq3Q =>
      'Will I be notified when my application is approved?';

  @override
  String get pendingFaq3A =>
      'Yes. You will receive an in-app notification the moment your application is reviewed. If it is approved, the Home tab shows a Continue button — tap it to acknowledge and unlock your farmer features. If it is not approved, the reason appears on the Home tab and you can update your details and resubmit (3 attempts total).';

  @override
  String get pendingFaq4Q => 'What is the SP3 Agriculture Cooperative?';

  @override
  String get pendingFaq4A =>
      'SP3 (Samahan ng mga Produktibong Pamilyang Pilipino sa Payanas) is a CDA-registered agricultural cooperative located in Barangay Payanas, Torrijos, Marinduque. It was established on February 1, 2017 and currently serves 52 member-farmers.';

  @override
  String get pendingFaq5Q => 'What is my SAGANA username for?';

  @override
  String get pendingFaq5A =>
      'Your SAGANA username is your permanent login identifier for this application. Keep it safe and do not share it. If you were recognized as an official SP3 member during registration, your username follows the format SP3-XXXX.';

  @override
  String get pendingFaq6Q => 'How do I contact the cooperative?';

  @override
  String get pendingFaq6A =>
      'Visit the SP3 Cooperative office at Barangay Payanas, Torrijos, Marinduque. BOD meetings are held every first Saturday of the month and are open to applicants.';

  @override
  String get pendingProfileTitle => 'My Profile';

  @override
  String get pendingVerificationBadge => 'PENDING VERIFICATION';

  @override
  String get pendingAccountInfoTitle => 'Account Information';

  @override
  String get pendingPhoneLabel => 'Phone';

  @override
  String get pendingNotSet => 'Not set';

  @override
  String get pendingPurokLabel => 'Purok';

  @override
  String get pendingLockedFeatures =>
      'Farm Details, Input Loans, Harvest Summary, Expenses, and Cooperative Contributions will be available after your membership is approved.';

  @override
  String get pendingSignOut => 'Sign Out';

  @override
  String get pendingSignOutConfirm => 'Are you sure you want to sign out?';

  @override
  String get pendingCancel => 'Cancel';

  @override
  String get pendingDetailsTitle => 'Your Details';

  @override
  String get pendingFullNameLabel => 'Full Name';

  @override
  String get pendingFullNameRequired => 'Enter your full name';

  @override
  String get pendingPhoneOptionalLabel => 'Phone Number (optional)';

  @override
  String get pendingPhoneInvalid => 'Invalid PH number';

  @override
  String get pendingEmailOptionalLabel => 'Email (optional)';

  @override
  String get pendingPurokOptionalLabel => 'Purok (optional)';

  @override
  String get pendingDobLabel => 'Date of Birth (18+)';

  @override
  String get pendingSelectHint => 'Select';

  @override
  String get pendingGenderOptionalLabel => 'Gender (optional)';

  @override
  String get pendingAgeError => 'You must be at least 18 years old.';

  @override
  String get pendingSave => 'Save';

  @override
  String get createOfficerTitle => 'Add Officer Account';

  @override
  String get createOfficerNotice =>
      'An Officer gets every Admin module except the Members tab. The person must already be in the Officer Registry.';

  @override
  String get createOfficerSectionOfficer => 'Officer';

  @override
  String get createOfficerFullNameLabel => 'Full Name';

  @override
  String get createOfficerFullNameHint => 'As recorded in the Officer Registry';

  @override
  String get createOfficerFullNameRequired => 'Full name is required';

  @override
  String get createOfficerNotInRegistry =>
      'This name is not in the Officer Registry. Add it to the registry first.';

  @override
  String get createOfficerAlreadyHasAccount =>
      'This Officer Registry record already has an account.';

  @override
  String get createOfficerMatched =>
      'Matched the Officer Registry — details auto-filled.';

  @override
  String get createOfficerEmailLabel => 'Email (optional)';

  @override
  String get createOfficerPhoneLabel => 'Phone Number (optional)';

  @override
  String get createOfficerPositionLabel => 'Position (optional)';

  @override
  String get createOfficerPositionHint => 'e.g. Operations Officer';

  @override
  String get createOfficerEmployeeIdLabel => 'Employee ID';

  @override
  String get createOfficerEmployeeIdHelp =>
      'Auto-generated (EMP-###), assigned on save — cannot be edited.';

  @override
  String get createOfficerSectionLogin => 'Login';

  @override
  String get createOfficerUsernameLabel => 'SAGANA Username';

  @override
  String get createOfficerUsernameRequired => 'Username is required';

  @override
  String get createOfficerUsernameHelp =>
      'Automatically generated — cannot be edited.';

  @override
  String get createOfficerPasswordLabel => 'Temporary Password';

  @override
  String get createOfficerPasswordHint => 'Type one, or tap AUTO';

  @override
  String get createOfficerPasswordTooShort => 'Minimum 8 characters';

  @override
  String get createOfficerWaitForCheck =>
      'Wait for the Officer Registry check to finish.';

  @override
  String get createOfficerCreated => 'Officer account created.';

  @override
  String get createOfficerCreating => 'Creating account...';

  @override
  String get createOfficerCreateButton => 'Create Officer Account';

  @override
  String farmerMgmtRejectDialogTitle(String name) {
    return 'Reject $name';
  }

  @override
  String get farmerMgmtRejectHint =>
      'Explain why the application is not approved. The applicant sees this and can resubmit (3 attempts total).';

  @override
  String get farmerMgmtNext => 'Next';

  @override
  String get farmerMgmtConfirmRejectionTitle => 'Confirm Rejection';

  @override
  String farmerMgmtRejectApplicantLine(String name) {
    return 'Applicant: $name';
  }

  @override
  String get farmerMgmtRejectOutcomeLine =>
      'Outcome: Application rejected (they keep their account, no farmer access)';

  @override
  String farmerMgmtReasonLine(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get farmerMgmtRejectResubmitLine =>
      'They can review their details and resubmit.';

  @override
  String get farmerMgmtRejectApplicationAction => 'Reject Application';

  @override
  String farmerMgmtRejectedToast(String name) {
    return '$name\'s application was rejected.';
  }

  @override
  String farmerMgmtSuspendDialogTitle(String name) {
    return 'Suspend $name';
  }

  @override
  String get farmerMgmtSuspendHint =>
      'Explain why this account is being suspended. The member sees this and cannot log in until reactivated.';

  @override
  String get farmerMgmtConfirmSuspensionTitle => 'Confirm Suspension';

  @override
  String farmerMgmtSuspendMemberLine(String name) {
    return 'Member: $name';
  }

  @override
  String get farmerMgmtSuspendOutcomeLine =>
      'Outcome: Suspended — blocked from logging in';

  @override
  String get farmerMgmtSuspendReactivateLine =>
      'You can reactivate them at any time.';

  @override
  String get farmerMgmtSuspendAccountAction => 'Suspend Account';

  @override
  String farmerMgmtSuspendedToast(String name) {
    return '$name has been suspended.';
  }

  @override
  String get farmerMgmtCancel => 'Cancel';

  @override
  String get farmerMgmtBack => 'Back';
}
