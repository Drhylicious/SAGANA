import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tl'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'SAGANA'**
  String get appName;

  /// No description provided for @appSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Streamlined Agricultural Gateway'**
  String get appSubtitle;

  /// No description provided for @cooperativeName.
  ///
  /// In en, this message translates to:
  /// **'SP3 Agriculture Cooperative'**
  String get cooperativeName;

  /// No description provided for @secureGatewayActive.
  ///
  /// In en, this message translates to:
  /// **'Secure Gateway Active'**
  String get secureGatewayActive;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming Soon'**
  String get comingSoon;

  /// No description provided for @comingSoonMessage.
  ///
  /// In en, this message translates to:
  /// **'This screen ({routeName}) is still under development.'**
  String comingSoonMessage(String routeName);

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navHarvest.
  ///
  /// In en, this message translates to:
  /// **'Harvest'**
  String get navHarvest;

  /// No description provided for @navMarketplace.
  ///
  /// In en, this message translates to:
  /// **'Marketplace'**
  String get navMarketplace;

  /// No description provided for @navAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get navAnalytics;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good Morning'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good Afternoon'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good Evening'**
  String get greetingEvening;

  /// No description provided for @defaultFarmerName.
  ///
  /// In en, this message translates to:
  /// **'Farmer'**
  String get defaultFarmerName;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — changes will sync when connected'**
  String get offlineBanner;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get login;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumber;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @noAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get noAccount;

  /// No description provided for @haveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get haveAccount;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @signOutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign Out?'**
  String get signOutConfirmTitle;

  /// No description provided for @signOutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'You will be signed out of SAGANA. Offline records will remain on this device.'**
  String get signOutConfirmMessage;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @sectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get sectionAccount;

  /// No description provided for @sectionNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get sectionNotifications;

  /// No description provided for @sectionAppPreferences.
  ///
  /// In en, this message translates to:
  /// **'App Preferences'**
  String get sectionAppPreferences;

  /// No description provided for @sectionDataExport.
  ///
  /// In en, this message translates to:
  /// **'Data Export'**
  String get sectionDataExport;

  /// No description provided for @sectionSupportInfo.
  ///
  /// In en, this message translates to:
  /// **'Support & Info'**
  String get sectionSupportInfo;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @editProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name, phone number, sitio'**
  String get editProfileSubtitle;

  /// No description provided for @editFarmDetails.
  ///
  /// In en, this message translates to:
  /// **'Edit Farm Details'**
  String get editFarmDetails;

  /// No description provided for @editFarmDetailsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Farm name, land area, location'**
  String get editFarmDetailsSubtitle;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @changePasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update your account password'**
  String get changePasswordSubtitle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageTagalog.
  ///
  /// In en, this message translates to:
  /// **'Tagalog'**
  String get languageTagalog;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get themeDark;

  /// No description provided for @backgroundSync.
  ///
  /// In en, this message translates to:
  /// **'Background Sync'**
  String get backgroundSync;

  /// No description provided for @backgroundSyncDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically sync your data when internet connection is restored'**
  String get backgroundSyncDescription;

  /// No description provided for @clearCachedData.
  ///
  /// In en, this message translates to:
  /// **'Clear Cached Data'**
  String get clearCachedData;

  /// No description provided for @clearCachedDataDescription.
  ///
  /// In en, this message translates to:
  /// **'Removes locally cached price and market data. Your harvest and inventory records are not affected.'**
  String get clearCachedDataDescription;

  /// No description provided for @clearCachedDataConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Cached Data?'**
  String get clearCachedDataConfirmTitle;

  /// No description provided for @clearCachedDataConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes locally cached price and market data. Your harvest records, inventory, and expenses are not affected.'**
  String get clearCachedDataConfirmMessage;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @notifNewOrder.
  ///
  /// In en, this message translates to:
  /// **'New Order Received'**
  String get notifNewOrder;

  /// No description provided for @notifListingApproved.
  ///
  /// In en, this message translates to:
  /// **'Listing Approved'**
  String get notifListingApproved;

  /// No description provided for @notifListingChanges.
  ///
  /// In en, this message translates to:
  /// **'Listing Changes Required'**
  String get notifListingChanges;

  /// No description provided for @notifLoanReminder.
  ///
  /// In en, this message translates to:
  /// **'Loan Payment Reminder'**
  String get notifLoanReminder;

  /// No description provided for @notifPriceUpdates.
  ///
  /// In en, this message translates to:
  /// **'Price Updates'**
  String get notifPriceUpdates;

  /// No description provided for @notifSyncCompleted.
  ///
  /// In en, this message translates to:
  /// **'Sync Completed'**
  String get notifSyncCompleted;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get confirmNewPassword;

  /// No description provided for @updatePassword.
  ///
  /// In en, this message translates to:
  /// **'Update Password'**
  String get updatePassword;

  /// No description provided for @updating.
  ///
  /// In en, this message translates to:
  /// **'Updating...'**
  String get updating;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters.'**
  String get passwordMinLength;

  /// No description provided for @accountCreated.
  ///
  /// In en, this message translates to:
  /// **'Account Created!'**
  String get accountCreated;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @selectAppearance.
  ///
  /// In en, this message translates to:
  /// **'Select Appearance'**
  String get selectAppearance;

  /// No description provided for @adminNavDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get adminNavDashboard;

  /// No description provided for @adminNavFarmers.
  ///
  /// In en, this message translates to:
  /// **'Farmers'**
  String get adminNavFarmers;

  /// No description provided for @adminNavListings.
  ///
  /// In en, this message translates to:
  /// **'Listings'**
  String get adminNavListings;

  /// No description provided for @listingsPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Listings'**
  String get listingsPendingTitle;

  /// No description provided for @listingsAllButton.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get listingsAllButton;

  /// No description provided for @adminNavLoans.
  ///
  /// In en, this message translates to:
  /// **'Loans'**
  String get adminNavLoans;

  /// No description provided for @adminNavReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get adminNavReports;

  /// No description provided for @adminUrgentActions.
  ///
  /// In en, this message translates to:
  /// **'Urgent Actions'**
  String get adminUrgentActions;

  /// No description provided for @adminQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get adminQuickActions;

  /// No description provided for @adminToolsManagement.
  ///
  /// In en, this message translates to:
  /// **'Tools & Management'**
  String get adminToolsManagement;

  /// No description provided for @adminRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get adminRecentActivity;

  /// No description provided for @adminGoToLoanPayments.
  ///
  /// In en, this message translates to:
  /// **'Go to Loan Payments'**
  String get adminGoToLoanPayments;

  /// No description provided for @loanDashTitle.
  ///
  /// In en, this message translates to:
  /// **'Loan Management'**
  String get loanDashTitle;

  /// No description provided for @loanDashNextCollection.
  ///
  /// In en, this message translates to:
  /// **'Next Payment Collection'**
  String get loanDashNextCollection;

  /// No description provided for @loanDashFarmersOutstanding.
  ///
  /// In en, this message translates to:
  /// **'{count} farmers have outstanding balances'**
  String loanDashFarmersOutstanding(int count);

  /// No description provided for @loanDashTotalExpected.
  ///
  /// In en, this message translates to:
  /// **'Total expected: {amount}'**
  String loanDashTotalExpected(String amount);

  /// No description provided for @loanDashActiveLoans.
  ///
  /// In en, this message translates to:
  /// **'Active Loans'**
  String get loanDashActiveLoans;

  /// No description provided for @loanDashTotalOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Total Outstanding'**
  String get loanDashTotalOutstanding;

  /// No description provided for @loanDashOverdueLoans.
  ///
  /// In en, this message translates to:
  /// **'Overdue Loans'**
  String get loanDashOverdueLoans;

  /// No description provided for @loanDashPaidThisMonth.
  ///
  /// In en, this message translates to:
  /// **'Paid This Month'**
  String get loanDashPaidThisMonth;

  /// No description provided for @loanDashActionIssue.
  ///
  /// In en, this message translates to:
  /// **'Issue New Loan'**
  String get loanDashActionIssue;

  /// No description provided for @loanDashActionRecordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get loanDashActionRecordPayment;

  /// No description provided for @loanDashActionViewHistory.
  ///
  /// In en, this message translates to:
  /// **'View History'**
  String get loanDashActionViewHistory;

  /// No description provided for @loanDashOverdueSection.
  ///
  /// In en, this message translates to:
  /// **'Overdue Loans ({count})'**
  String loanDashOverdueSection(int count);

  /// No description provided for @loanDashActiveSection.
  ///
  /// In en, this message translates to:
  /// **'Active Loans'**
  String get loanDashActiveSection;

  /// No description provided for @loanDashSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get loanDashSeeAll;

  /// No description provided for @loanDashNoOverdue.
  ///
  /// In en, this message translates to:
  /// **'No overdue loans right now.'**
  String get loanDashNoOverdue;

  /// No description provided for @loanDashNoActive.
  ///
  /// In en, this message translates to:
  /// **'No active loans right now.'**
  String get loanDashNoActive;

  /// No description provided for @loanDashValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get loanDashValue;

  /// No description provided for @loanDashPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get loanDashPaid;

  /// No description provided for @loanDashBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get loanDashBalance;

  /// No description provided for @loanDashNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get loanDashNext;

  /// No description provided for @loanDashOverdueSince.
  ///
  /// In en, this message translates to:
  /// **'Overdue since {date}'**
  String loanDashOverdueSince(String date);

  /// No description provided for @adminPriceManagement.
  ///
  /// In en, this message translates to:
  /// **'Price Management'**
  String get adminPriceManagement;

  /// No description provided for @adminPriceManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update crop buying and market prices for all members'**
  String get adminPriceManagementSubtitle;

  /// No description provided for @adminNotificationBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Notification Broadcast'**
  String get adminNotificationBroadcast;

  /// No description provided for @adminNotificationBroadcastSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send announcements to farmers, buyers, or specific groups'**
  String get adminNotificationBroadcastSubtitle;

  /// No description provided for @adminSupplyChainMap.
  ///
  /// In en, this message translates to:
  /// **'Supply Chain Map'**
  String get adminSupplyChainMap;

  /// No description provided for @adminSupplyChainMapSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View all farmer locations and crop distribution'**
  String get adminSupplyChainMapSubtitle;

  /// No description provided for @adminReviewListings.
  ///
  /// In en, this message translates to:
  /// **'Review\nListings'**
  String get adminReviewListings;

  /// No description provided for @adminRecordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record\nPayment'**
  String get adminRecordPayment;

  /// No description provided for @adminUpdatePrice.
  ///
  /// In en, this message translates to:
  /// **'Update\nPrice'**
  String get adminUpdatePrice;

  /// No description provided for @adminIssueLoan.
  ///
  /// In en, this message translates to:
  /// **'Issue\nLoan'**
  String get adminIssueLoan;

  /// No description provided for @adminViewReports.
  ///
  /// In en, this message translates to:
  /// **'View\nReports'**
  String get adminViewReports;

  /// No description provided for @adminManageFarmers.
  ///
  /// In en, this message translates to:
  /// **'Manage\nFarmers'**
  String get adminManageFarmers;

  /// No description provided for @issueLoanTitle.
  ///
  /// In en, this message translates to:
  /// **'Issue New Loan'**
  String get issueLoanTitle;

  /// No description provided for @issueLoanSelectFarmer.
  ///
  /// In en, this message translates to:
  /// **'Select Farmer'**
  String get issueLoanSelectFarmer;

  /// No description provided for @issueLoanSearchFarmerHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or member ID'**
  String get issueLoanSearchFarmerHint;

  /// No description provided for @issueLoanNoFarmerSelected.
  ///
  /// In en, this message translates to:
  /// **'Tap to select a farmer'**
  String get issueLoanNoFarmerSelected;

  /// No description provided for @issueLoanOutstandingBalance.
  ///
  /// In en, this message translates to:
  /// **'Outstanding Balance'**
  String get issueLoanOutstandingBalance;

  /// No description provided for @issueLoanOverdueWarning.
  ///
  /// In en, this message translates to:
  /// **'This farmer has an overdue loan.'**
  String get issueLoanOverdueWarning;

  /// No description provided for @issueLoanStandingUnavailableOffline.
  ///
  /// In en, this message translates to:
  /// **'Outstanding balance unavailable while offline.'**
  String get issueLoanStandingUnavailableOffline;

  /// No description provided for @issueLoanInputItems.
  ///
  /// In en, this message translates to:
  /// **'Input Items'**
  String get issueLoanInputItems;

  /// No description provided for @issueLoanAddItem.
  ///
  /// In en, this message translates to:
  /// **'Add Input Item'**
  String get issueLoanAddItem;

  /// No description provided for @issueLoanNoItemsYet.
  ///
  /// In en, this message translates to:
  /// **'No items added yet.'**
  String get issueLoanNoItemsYet;

  /// No description provided for @issueLoanItemName.
  ///
  /// In en, this message translates to:
  /// **'Item Name'**
  String get issueLoanItemName;

  /// No description provided for @issueLoanQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get issueLoanQuantity;

  /// No description provided for @issueLoanUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get issueLoanUnit;

  /// No description provided for @issueLoanUnitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit Price'**
  String get issueLoanUnitPrice;

  /// No description provided for @issueLoanLineTotal.
  ///
  /// In en, this message translates to:
  /// **'Item Total'**
  String get issueLoanLineTotal;

  /// No description provided for @issueLoanConfirmItem.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get issueLoanConfirmItem;

  /// No description provided for @issueLoanCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get issueLoanCancel;

  /// No description provided for @issueLoanTotalValue.
  ///
  /// In en, this message translates to:
  /// **'Total Loan Value'**
  String get issueLoanTotalValue;

  /// No description provided for @issueLoanPaymentSchedule.
  ///
  /// In en, this message translates to:
  /// **'Payment Schedule'**
  String get issueLoanPaymentSchedule;

  /// No description provided for @issueLoanIssuedDate.
  ///
  /// In en, this message translates to:
  /// **'Issue Date'**
  String get issueLoanIssuedDate;

  /// No description provided for @issueLoanMonthlyPayment.
  ///
  /// In en, this message translates to:
  /// **'Monthly Payment'**
  String get issueLoanMonthlyPayment;

  /// No description provided for @issueLoanNextPaymentDue.
  ///
  /// In en, this message translates to:
  /// **'Next Payment Due'**
  String get issueLoanNextPaymentDue;

  /// No description provided for @issueLoanFrequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency: Monthly'**
  String get issueLoanFrequency;

  /// No description provided for @issueLoanVenue.
  ///
  /// In en, this message translates to:
  /// **'Venue: Barangay Payanas'**
  String get issueLoanVenue;

  /// No description provided for @issueLoanNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get issueLoanNotes;

  /// No description provided for @issueLoanSubmit.
  ///
  /// In en, this message translates to:
  /// **'Issue Loan'**
  String get issueLoanSubmit;

  /// No description provided for @issueLoanSuccess.
  ///
  /// In en, this message translates to:
  /// **'Loan {reference} issued successfully.'**
  String issueLoanSuccess(String reference);

  /// No description provided for @issueLoanQueuedOffline.
  ///
  /// In en, this message translates to:
  /// **'Saved locally. Reference number will be assigned automatically once synced online.'**
  String get issueLoanQueuedOffline;

  /// No description provided for @issueLoanErrorNoFarmer.
  ///
  /// In en, this message translates to:
  /// **'Please select a farmer first.'**
  String get issueLoanErrorNoFarmer;

  /// No description provided for @issueLoanErrorNoItems.
  ///
  /// In en, this message translates to:
  /// **'Please add at least one input item.'**
  String get issueLoanErrorNoItems;

  /// No description provided for @issueLoanErrorInvalidMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly payment must be greater than zero.'**
  String get issueLoanErrorInvalidMonthly;

  /// No description provided for @issueLoanErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get issueLoanErrorGeneric;

  /// No description provided for @farmerMgmtTitle.
  ///
  /// In en, this message translates to:
  /// **'Farmer Management'**
  String get farmerMgmtTitle;

  /// No description provided for @farmerMgmtAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get farmerMgmtAdd;

  /// No description provided for @adminCoopPerformanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Cooperative Performance Summary'**
  String get adminCoopPerformanceTitle;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get seeAll;

  /// No description provided for @priceManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Price Management'**
  String get priceManagementTitle;

  /// No description provided for @supplyChainTitle.
  ///
  /// In en, this message translates to:
  /// **'Supply Chain Map'**
  String get supplyChainTitle;

  /// No description provided for @priceLiveRates.
  ///
  /// In en, this message translates to:
  /// **'Live Market Rates'**
  String get priceLiveRates;

  /// No description provided for @priceMarketTrends.
  ///
  /// In en, this message translates to:
  /// **'Market Trends'**
  String get priceMarketTrends;

  /// No description provided for @priceAddNew.
  ///
  /// In en, this message translates to:
  /// **'Add Price Entry'**
  String get priceAddNew;

  /// No description provided for @priceOfflineWarning.
  ///
  /// In en, this message translates to:
  /// **'Price updates disabled while offline.'**
  String get priceOfflineWarning;

  /// No description provided for @broadcastCompose.
  ///
  /// In en, this message translates to:
  /// **'Compose Message'**
  String get broadcastCompose;

  /// No description provided for @broadcastUseTemplate.
  ///
  /// In en, this message translates to:
  /// **'Use Template'**
  String get broadcastUseTemplate;

  /// No description provided for @broadcastPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get broadcastPreview;

  /// No description provided for @broadcastRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent Broadcasts'**
  String get broadcastRecent;

  /// No description provided for @broadcastTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get broadcastTitle;

  /// No description provided for @broadcastSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get broadcastSchedule;

  /// No description provided for @broadcastScheduleSub.
  ///
  /// In en, this message translates to:
  /// **'Send later at a specific time'**
  String get broadcastScheduleSub;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tl':
      return AppLocalizationsTl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
