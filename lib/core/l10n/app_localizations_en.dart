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
  String get greetingMorning => 'Good Morning';

  @override
  String get greetingAfternoon => 'Good Afternoon';

  @override
  String get greetingEvening => 'Good Evening';

  @override
  String get defaultFarmerName => 'Farmer';

  @override
  String get offlineBanner =>
      'You\'re offline — changes will sync when connected';

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
  String get adminNavDashboard => 'Dashboard';

  @override
  String get adminNavFarmers => 'Farmers';

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
  String get adminUrgentActions => 'Urgent Actions';

  @override
  String get adminQuickActions => 'Quick Actions';

  @override
  String get adminToolsManagement => 'Tools & Management';

  @override
  String get adminRecentActivity => 'Recent Activity';

  @override
  String get adminGoToLoanPayments => 'Go to Loan Payments';

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
  String get farmerMgmtTitle => 'Farmer Management';

  @override
  String get farmerMgmtAdd => 'Add';

  @override
  String get adminCoopPerformanceTitle => 'Cooperative Performance Summary';

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
  String get broadcastTitle => 'Title';

  @override
  String get broadcastSchedule => 'Schedule';

  @override
  String get broadcastScheduleSub => 'Send later at a specific time';
}
