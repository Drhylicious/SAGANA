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
  /// **'Good morning'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get greetingEvening;

  /// No description provided for @defaultFarmerName.
  ///
  /// In en, this message translates to:
  /// **'Farmer'**
  String get defaultFarmerName;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Some features may be unavailable.'**
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

  /// No description provided for @adminProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin Profile'**
  String get adminProfileTitle;

  /// No description provided for @adminProfileLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load your profile. Please try again.'**
  String get adminProfileLoadError;

  /// No description provided for @adminProfileDefaultRole.
  ///
  /// In en, this message translates to:
  /// **'Cooperative Administrator'**
  String get adminProfileDefaultRole;

  /// No description provided for @adminProfileFullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get adminProfileFullName;

  /// No description provided for @adminProfilePhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get adminProfilePhoneNumber;

  /// No description provided for @adminProfileSitio.
  ///
  /// In en, this message translates to:
  /// **'Sitio / Purok'**
  String get adminProfileSitio;

  /// No description provided for @adminProfileSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get adminProfileSaveChanges;

  /// No description provided for @adminProfileSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get adminProfileSaving;

  /// No description provided for @adminProfileNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Full name is required.'**
  String get adminProfileNameRequired;

  /// No description provided for @adminProfileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully.'**
  String get adminProfileUpdated;

  /// No description provided for @adminProfileSaveError.
  ///
  /// In en, this message translates to:
  /// **'Failed to save. Please try again.'**
  String get adminProfileSaveError;

  /// No description provided for @adminProfileChangePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change Photo'**
  String get adminProfileChangePhoto;

  /// No description provided for @adminProfileRemovePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove Photo'**
  String get adminProfileRemovePhoto;

  /// No description provided for @adminProfilePhotoUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile photo updated.'**
  String get adminProfilePhotoUpdated;

  /// No description provided for @adminProfilePhotoError.
  ///
  /// In en, this message translates to:
  /// **'Could not update photo. Please try again.'**
  String get adminProfilePhotoError;

  /// No description provided for @adminProfileCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get adminProfileCurrentPassword;

  /// No description provided for @adminProfileNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get adminProfileNewPassword;

  /// No description provided for @adminProfileConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get adminProfileConfirmPassword;

  /// No description provided for @adminProfilePasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters.'**
  String get adminProfilePasswordHint;

  /// No description provided for @adminProfileAllFieldsRequired.
  ///
  /// In en, this message translates to:
  /// **'All fields are required.'**
  String get adminProfileAllFieldsRequired;

  /// No description provided for @adminProfilePasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters.'**
  String get adminProfilePasswordTooShort;

  /// No description provided for @adminProfilePasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get adminProfilePasswordMismatch;

  /// No description provided for @adminProfileUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating...'**
  String get adminProfileUpdating;

  /// No description provided for @adminProfileUpdatePassword.
  ///
  /// In en, this message translates to:
  /// **'Update Password'**
  String get adminProfileUpdatePassword;

  /// No description provided for @adminProfilePasswordUpdated.
  ///
  /// In en, this message translates to:
  /// **'Password updated. Please log in again.'**
  String get adminProfilePasswordUpdated;

  /// No description provided for @adminProfileOrganizationalInfo.
  ///
  /// In en, this message translates to:
  /// **'Organizational Information'**
  String get adminProfileOrganizationalInfo;

  /// No description provided for @adminProfileEmployeeId.
  ///
  /// In en, this message translates to:
  /// **'Employee ID'**
  String get adminProfileEmployeeId;

  /// No description provided for @adminProfilePosition.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get adminProfilePosition;

  /// No description provided for @adminProfileDepartment.
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get adminProfileDepartment;

  /// No description provided for @adminProfileAdminSince.
  ///
  /// In en, this message translates to:
  /// **'Administrator Since'**
  String get adminProfileAdminSince;

  /// No description provided for @adminProfileOrgInfoHint.
  ///
  /// In en, this message translates to:
  /// **'Organizational details are managed by cooperative records, not editable here.'**
  String get adminProfileOrgInfoHint;

  /// No description provided for @adminProfilePreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get adminProfilePreferences;

  /// No description provided for @adminProfileDataAndStorage.
  ///
  /// In en, this message translates to:
  /// **'Data & Storage'**
  String get adminProfileDataAndStorage;

  /// No description provided for @adminProfileClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear Cached Data'**
  String get adminProfileClearCache;

  /// No description provided for @adminProfileClearCacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Cached Data?'**
  String get adminProfileClearCacheTitle;

  /// No description provided for @adminProfileClearCacheMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes locally cached price and market data. Your reports and records are not affected.'**
  String get adminProfileClearCacheMessage;

  /// No description provided for @adminProfileClearCacheConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get adminProfileClearCacheConfirm;

  /// No description provided for @adminProfileCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared.'**
  String get adminProfileCacheCleared;

  /// No description provided for @adminProfileSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get adminProfileSignOut;

  /// No description provided for @adminProfileSignOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign Out?'**
  String get adminProfileSignOutTitle;

  /// No description provided for @adminProfileSignOutMessage.
  ///
  /// In en, this message translates to:
  /// **'You will be signed out of SAGANA.'**
  String get adminProfileSignOutMessage;

  /// No description provided for @adminProfileSignOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get adminProfileSignOutConfirm;

  /// No description provided for @adminProfileAppVersion.
  ///
  /// In en, this message translates to:
  /// **'SAGANA v{version}'**
  String adminProfileAppVersion(String version);

  /// No description provided for @adminNavDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get adminNavDashboard;

  /// No description provided for @adminNavMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get adminNavMembers;

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

  /// No description provided for @reportsHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Operational Reports'**
  String get reportsHubTitle;

  /// No description provided for @reportsPerformanceSummary.
  ///
  /// In en, this message translates to:
  /// **'Performance Summary'**
  String get reportsPerformanceSummary;

  /// No description provided for @reportsTotalHarvest.
  ///
  /// In en, this message translates to:
  /// **'Total Harvest'**
  String get reportsTotalHarvest;

  /// No description provided for @reportsCoopSales.
  ///
  /// In en, this message translates to:
  /// **'Coop Sales'**
  String get reportsCoopSales;

  /// No description provided for @reportsMarketplaceRevenue.
  ///
  /// In en, this message translates to:
  /// **'Marketplace Revenue'**
  String get reportsMarketplaceRevenue;

  /// No description provided for @reportsActiveLoans.
  ///
  /// In en, this message translates to:
  /// **'Active Loans'**
  String get reportsActiveLoans;

  /// No description provided for @reportsTotalExpenses.
  ///
  /// In en, this message translates to:
  /// **'Total Expenses'**
  String get reportsTotalExpenses;

  /// No description provided for @reportsMemberParticipation.
  ///
  /// In en, this message translates to:
  /// **'Member Participation'**
  String get reportsMemberParticipation;

  /// No description provided for @reportsDetailedReports.
  ///
  /// In en, this message translates to:
  /// **'Detailed Reports'**
  String get reportsDetailedReports;

  /// No description provided for @reportsManagementTools.
  ///
  /// In en, this message translates to:
  /// **'Management Tools'**
  String get reportsManagementTools;

  /// No description provided for @reportsRecentReports.
  ///
  /// In en, this message translates to:
  /// **'Recent Reports'**
  String get reportsRecentReports;

  /// No description provided for @reportsNoExportsYet.
  ///
  /// In en, this message translates to:
  /// **'No exports yet. Generate one from Export Center.'**
  String get reportsNoExportsYet;

  /// No description provided for @reportsSalesReport.
  ///
  /// In en, this message translates to:
  /// **'Sales Report'**
  String get reportsSalesReport;

  /// No description provided for @reportsExportComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Export coming soon'**
  String get reportsExportComingSoon;

  /// No description provided for @reportsTotalRevenue.
  ///
  /// In en, this message translates to:
  /// **'Total Revenue'**
  String get reportsTotalRevenue;

  /// No description provided for @reportsTotalVolume.
  ///
  /// In en, this message translates to:
  /// **'Total Volume'**
  String get reportsTotalVolume;

  /// No description provided for @reportsTransactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get reportsTransactions;

  /// No description provided for @reportsCropBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Palay vs. Peanut'**
  String get reportsCropBreakdown;

  /// No description provided for @reportsRevenueTrend.
  ///
  /// In en, this message translates to:
  /// **'Revenue Trend'**
  String get reportsRevenueTrend;

  /// No description provided for @reportsNotEnoughTrendData.
  ///
  /// In en, this message translates to:
  /// **'Not enough data for a trend yet.'**
  String get reportsNotEnoughTrendData;

  /// No description provided for @reportsTransactionDetails.
  ///
  /// In en, this message translates to:
  /// **'Transaction Details'**
  String get reportsTransactionDetails;

  /// No description provided for @reportsSearchTransactions.
  ///
  /// In en, this message translates to:
  /// **'Search farmer, crop, or reference'**
  String get reportsSearchTransactions;

  /// No description provided for @reportsNoSalesRecorded.
  ///
  /// In en, this message translates to:
  /// **'No cooperative sales recorded for this period.'**
  String get reportsNoSalesRecorded;

  /// No description provided for @reportsNoSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No transactions match your search.'**
  String get reportsNoSearchResults;

  /// No description provided for @reportsInventoryReport.
  ///
  /// In en, this message translates to:
  /// **'Inventory Report'**
  String get reportsInventoryReport;

  /// No description provided for @reportsHarvestReport.
  ///
  /// In en, this message translates to:
  /// **'Harvest Report'**
  String get reportsHarvestReport;

  /// No description provided for @reportsTotalYield.
  ///
  /// In en, this message translates to:
  /// **'Total Yield'**
  String get reportsTotalYield;

  /// No description provided for @reportsGradeAShare.
  ///
  /// In en, this message translates to:
  /// **'Grade A Share'**
  String get reportsGradeAShare;

  /// No description provided for @reportsUnsyncedEntries.
  ///
  /// In en, this message translates to:
  /// **'Unsynced Entries'**
  String get reportsUnsyncedEntries;

  /// No description provided for @reportsYieldByCrop.
  ///
  /// In en, this message translates to:
  /// **'Yield by Crop'**
  String get reportsYieldByCrop;

  /// No description provided for @reportsYieldTrend.
  ///
  /// In en, this message translates to:
  /// **'Yield Trend'**
  String get reportsYieldTrend;

  /// No description provided for @reportsHarvestEntries.
  ///
  /// In en, this message translates to:
  /// **'Harvest Entries'**
  String get reportsHarvestEntries;

  /// No description provided for @reportsSearchHarvests.
  ///
  /// In en, this message translates to:
  /// **'Search farmer or crop'**
  String get reportsSearchHarvests;

  /// No description provided for @reportsNoHarvestsRecorded.
  ///
  /// In en, this message translates to:
  /// **'No harvests recorded for this period.'**
  String get reportsNoHarvestsRecorded;

  /// No description provided for @reportsToCoop.
  ///
  /// In en, this message translates to:
  /// **'To Coop'**
  String get reportsToCoop;

  /// No description provided for @reportsNotToCoop.
  ///
  /// In en, this message translates to:
  /// **'Not to Coop'**
  String get reportsNotToCoop;

  /// No description provided for @reportsSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get reportsSynced;

  /// No description provided for @reportsPendingSync.
  ///
  /// In en, this message translates to:
  /// **'Pending Sync'**
  String get reportsPendingSync;

  /// No description provided for @reportsExpenseReport.
  ///
  /// In en, this message translates to:
  /// **'Expense Report'**
  String get reportsExpenseReport;

  /// No description provided for @reportsFarmerFundedTotal.
  ///
  /// In en, this message translates to:
  /// **'Farmer-Funded Total'**
  String get reportsFarmerFundedTotal;

  /// No description provided for @reportsSubsidizedItems.
  ///
  /// In en, this message translates to:
  /// **'Subsidized Items'**
  String get reportsSubsidizedItems;

  /// No description provided for @reportsTotalEntries.
  ///
  /// In en, this message translates to:
  /// **'Total Entries'**
  String get reportsTotalEntries;

  /// No description provided for @reportsExpensesByCategory.
  ///
  /// In en, this message translates to:
  /// **'Expenses by Category'**
  String get reportsExpensesByCategory;

  /// No description provided for @reportsSubsidizedTag.
  ///
  /// In en, this message translates to:
  /// **'SUBSIDIZED'**
  String get reportsSubsidizedTag;

  /// No description provided for @reportsSpendingTrend.
  ///
  /// In en, this message translates to:
  /// **'Spending Trend'**
  String get reportsSpendingTrend;

  /// No description provided for @reportsExpenseEntries.
  ///
  /// In en, this message translates to:
  /// **'Expense Entries'**
  String get reportsExpenseEntries;

  /// No description provided for @reportsSearchExpenses.
  ///
  /// In en, this message translates to:
  /// **'Search farmer, category, or description'**
  String get reportsSearchExpenses;

  /// No description provided for @reportsNoExpensesRecorded.
  ///
  /// In en, this message translates to:
  /// **'No expenses recorded for this period.'**
  String get reportsNoExpensesRecorded;

  /// No description provided for @reportsCollectionTrend.
  ///
  /// In en, this message translates to:
  /// **'Collection Trend'**
  String get reportsCollectionTrend;

  /// No description provided for @reportsNoSearchResultsOrLoans.
  ///
  /// In en, this message translates to:
  /// **'No loans match these filters.'**
  String get reportsNoSearchResultsOrLoans;

  /// No description provided for @reportsLoanReport.
  ///
  /// In en, this message translates to:
  /// **'Loan Report'**
  String get reportsLoanReport;

  /// No description provided for @reportsMemberContributionReport.
  ///
  /// In en, this message translates to:
  /// **'Member Contribution Report'**
  String get reportsMemberContributionReport;

  /// No description provided for @reportsTotalCoopSalesLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Cooperative Sales ({year})'**
  String reportsTotalCoopSalesLabel(int year);

  /// No description provided for @reportsContributingMembers.
  ///
  /// In en, this message translates to:
  /// **'Contributing Members'**
  String get reportsContributingMembers;

  /// No description provided for @reportsParticipationRate.
  ///
  /// In en, this message translates to:
  /// **'Participation Rate'**
  String get reportsParticipationRate;

  /// No description provided for @reportsMemberBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Member Breakdown'**
  String get reportsMemberBreakdown;

  /// No description provided for @reportsSearchMembers.
  ///
  /// In en, this message translates to:
  /// **'Search member name or ID'**
  String get reportsSearchMembers;

  /// No description provided for @reportsSharePercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% share'**
  String reportsSharePercent(String percent);

  /// No description provided for @reportsPalay.
  ///
  /// In en, this message translates to:
  /// **'Palay'**
  String get reportsPalay;

  /// No description provided for @reportsPeanut.
  ///
  /// In en, this message translates to:
  /// **'Peanut'**
  String get reportsPeanut;

  /// No description provided for @reportsNoContributionYet.
  ///
  /// In en, this message translates to:
  /// **'No sales recorded to the cooperative this year.'**
  String get reportsNoContributionYet;

  /// No description provided for @reportsAnalyticsDashboard.
  ///
  /// In en, this message translates to:
  /// **'Analytics Dashboard'**
  String get reportsAnalyticsDashboard;

  /// No description provided for @reportsBalikTangkilikManagement.
  ///
  /// In en, this message translates to:
  /// **'Balik-Tangkilik Management'**
  String get reportsBalikTangkilikManagement;

  /// No description provided for @balikTangkilikSettingsTab.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get balikTangkilikSettingsTab;

  /// No description provided for @balikTangkilikDistributionTab.
  ///
  /// In en, this message translates to:
  /// **'Distribution'**
  String get balikTangkilikDistributionTab;

  /// No description provided for @balikTangkilikHistoryTab.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get balikTangkilikHistoryTab;

  /// No description provided for @balikTangkilikHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Distribution History'**
  String get balikTangkilikHistoryTitle;

  /// No description provided for @balikTangkilikNoHistoryYet.
  ///
  /// In en, this message translates to:
  /// **'No distributions have been recorded yet.'**
  String get balikTangkilikNoHistoryYet;

  /// No description provided for @balikTangkilikYearLogTitle.
  ///
  /// In en, this message translates to:
  /// **'{year} Distribution'**
  String balikTangkilikYearLogTitle(int year);

  /// No description provided for @balikTangkilikYearLogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} members paid'**
  String balikTangkilikYearLogSubtitle(int count);

  /// No description provided for @balikTangkilikDistributionComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Distribution planning is coming soon.'**
  String get balikTangkilikDistributionComingSoon;

  /// No description provided for @balikTangkilikHistoryComingSoon.
  ///
  /// In en, this message translates to:
  /// **'History tracking is coming soon.'**
  String get balikTangkilikHistoryComingSoon;

  /// No description provided for @balikTangkilikTotalCoopSales.
  ///
  /// In en, this message translates to:
  /// **'Total Cooperative Sales'**
  String get balikTangkilikTotalCoopSales;

  /// No description provided for @balikTangkilikPoolAmount.
  ///
  /// In en, this message translates to:
  /// **'Distributable Pool Amount'**
  String get balikTangkilikPoolAmount;

  /// No description provided for @balikTangkilikInterestRate.
  ///
  /// In en, this message translates to:
  /// **'Interest Rate (%)'**
  String get balikTangkilikInterestRate;

  /// No description provided for @balikTangkilikLiveTotalHint.
  ///
  /// In en, this message translates to:
  /// **'Live total from recorded sales: {amount}'**
  String balikTangkilikLiveTotalHint(String amount);

  /// No description provided for @balikTangkilikUseThisValue.
  ///
  /// In en, this message translates to:
  /// **'Use this live total'**
  String get balikTangkilikUseThisValue;

  /// No description provided for @balikTangkilikPoolHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the amount available for distribution to members.'**
  String get balikTangkilikPoolHint;

  /// No description provided for @balikTangkilikInterestHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the annual interest rate for the pool.'**
  String get balikTangkilikInterestHint;

  /// No description provided for @balikTangkilikAfsFinalized.
  ///
  /// In en, this message translates to:
  /// **'AFS Finalized'**
  String get balikTangkilikAfsFinalized;

  /// No description provided for @balikTangkilikAfsFinalizedHint.
  ///
  /// In en, this message translates to:
  /// **'Mark this as finalized after the annual financial statement is approved.'**
  String get balikTangkilikAfsFinalizedHint;

  /// No description provided for @balikTangkilikSaveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save Settings'**
  String get balikTangkilikSaveSettings;

  /// No description provided for @balikTangkilikInvalidValues.
  ///
  /// In en, this message translates to:
  /// **'Please enter valid non-negative values for all fields.'**
  String get balikTangkilikInvalidValues;

  /// No description provided for @balikTangkilikZeroPoolWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Zero pool amount?'**
  String get balikTangkilikZeroPoolWarningTitle;

  /// No description provided for @balikTangkilikZeroPoolWarningMessage.
  ///
  /// In en, this message translates to:
  /// **'Saving a zero distributable pool while the AFS is finalized may block future distribution. Continue anyway?'**
  String get balikTangkilikZeroPoolWarningMessage;

  /// No description provided for @balikTangkilikContinueAnyway.
  ///
  /// In en, this message translates to:
  /// **'Continue Anyway'**
  String get balikTangkilikContinueAnyway;

  /// No description provided for @balikTangkilikSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved for {year}.'**
  String balikTangkilikSettingsSaved(int year);

  /// No description provided for @balikTangkilikSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save the Balik-Tangkilik settings. Please try again.'**
  String get balikTangkilikSaveError;

  /// No description provided for @balikTangkilikMemberBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Member Breakdown'**
  String get balikTangkilikMemberBreakdown;

  /// No description provided for @balikTangkilikRefreshEstimates.
  ///
  /// In en, this message translates to:
  /// **'Refresh Estimates'**
  String get balikTangkilikRefreshEstimates;

  /// No description provided for @balikTangkilikEstimatesRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Estimates refreshed.'**
  String get balikTangkilikEstimatesRefreshed;

  /// No description provided for @balikTangkilikRefreshError.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh estimates. Please try again.'**
  String get balikTangkilikRefreshError;

  /// No description provided for @balikTangkilikAfsNotFinalizedWarning.
  ///
  /// In en, this message translates to:
  /// **'AFS is not finalized for this year. Go to the Settings tab to finalize it before distribution can be recorded.'**
  String get balikTangkilikAfsNotFinalizedWarning;

  /// No description provided for @balikTangkilikAlreadyDistributedBanner.
  ///
  /// In en, this message translates to:
  /// **'Balik-Tangkilik for {year} has already been distributed.'**
  String balikTangkilikAlreadyDistributedBanner(int year);

  /// No description provided for @balikTangkilikTotalEstimated.
  ///
  /// In en, this message translates to:
  /// **'Total Estimated Payout ({year})'**
  String balikTangkilikTotalEstimated(int year);

  /// No description provided for @balikTangkilikTotalDistributed.
  ///
  /// In en, this message translates to:
  /// **'Total Distributed ({year})'**
  String balikTangkilikTotalDistributed(int year);

  /// No description provided for @balikTangkilikRecordDistribution.
  ///
  /// In en, this message translates to:
  /// **'Record Distribution'**
  String get balikTangkilikRecordDistribution;

  /// No description provided for @balikTangkilikAlreadyDistributed.
  ///
  /// In en, this message translates to:
  /// **'Already Distributed for {year}'**
  String balikTangkilikAlreadyDistributed(int year);

  /// No description provided for @balikTangkilikConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Distribution'**
  String get balikTangkilikConfirmTitle;

  /// No description provided for @balikTangkilikConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'You are about to finalize Balik-Tangkilik for {year} for {count} contributing members, totaling {amount}.'**
  String balikTangkilikConfirmMessage(int year, int count, String amount);

  /// No description provided for @balikTangkilikIrreversibleWarning.
  ///
  /// In en, this message translates to:
  /// **'This action is permanent and cannot be undone.'**
  String get balikTangkilikIrreversibleWarning;

  /// No description provided for @balikTangkilikConfirmDistribute.
  ///
  /// In en, this message translates to:
  /// **'Distribute Now'**
  String get balikTangkilikConfirmDistribute;

  /// No description provided for @balikTangkilikDistributionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Distribution recorded. Total paid out: {amount}.'**
  String balikTangkilikDistributionSuccess(String amount);

  /// No description provided for @balikTangkilikDistributionError.
  ///
  /// In en, this message translates to:
  /// **'Could not record distribution. Please try again.'**
  String get balikTangkilikDistributionError;

  /// No description provided for @exportSelectReports.
  ///
  /// In en, this message translates to:
  /// **'Select Reports'**
  String get exportSelectReports;

  /// No description provided for @exportPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get exportPeriod;

  /// No description provided for @exportYearForContributionReport.
  ///
  /// In en, this message translates to:
  /// **'Member Contribution Report uses a specific year, not a period:'**
  String get exportYearForContributionReport;

  /// No description provided for @exportSelectAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'Select at least one report to export.'**
  String get exportSelectAtLeastOne;

  /// No description provided for @exportGenerateButton.
  ///
  /// In en, this message translates to:
  /// **'Generate Export'**
  String get exportGenerateButton;

  /// No description provided for @exportGenerated.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) generated.'**
  String exportGenerated(int count);

  /// No description provided for @exportGenerateError.
  ///
  /// In en, this message translates to:
  /// **'Could not generate export. Please try again.'**
  String get exportGenerateError;

  /// No description provided for @exportFileMissing.
  ///
  /// In en, this message translates to:
  /// **'This file no longer exists on this device.'**
  String get exportFileMissing;

  /// No description provided for @exportSummaryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Select one or more reports to export as CSV.'**
  String get exportSummaryEmpty;

  /// No description provided for @exportSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} report(s) will be exported as separate CSV files.'**
  String exportSummary(int count);

  /// No description provided for @exportRecentExports.
  ///
  /// In en, this message translates to:
  /// **'Recent Exports'**
  String get exportRecentExports;

  /// No description provided for @exportNoHistoryYet.
  ///
  /// In en, this message translates to:
  /// **'No exports generated yet on this device.'**
  String get exportNoHistoryYet;

  /// No description provided for @reportsExportCenter.
  ///
  /// In en, this message translates to:
  /// **'Export Center'**
  String get reportsExportCenter;

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
  /// **'Go to Loan Payments →'**
  String get adminGoToLoanPayments;

  /// No description provided for @analyticsMemberParticipation.
  ///
  /// In en, this message translates to:
  /// **'Member Participation'**
  String get analyticsMemberParticipation;

  /// No description provided for @analyticsActiveHarvested.
  ///
  /// In en, this message translates to:
  /// **'Harvested'**
  String get analyticsActiveHarvested;

  /// No description provided for @analyticsActiveListed.
  ///
  /// In en, this message translates to:
  /// **'Listed Only'**
  String get analyticsActiveListed;

  /// No description provided for @analyticsInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get analyticsInactive;

  /// No description provided for @analyticsSendReminder.
  ///
  /// In en, this message translates to:
  /// **'Send Reminder ({count})'**
  String analyticsSendReminder(int count);

  /// No description provided for @analyticsSendReminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Send reminder?'**
  String get analyticsSendReminderTitle;

  /// No description provided for @analyticsSendReminderMessage.
  ///
  /// In en, this message translates to:
  /// **'This will notify {count} inactive members to check in with the cooperative.'**
  String analyticsSendReminderMessage(int count);

  /// No description provided for @analyticsSendReminderConfirm.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get analyticsSendReminderConfirm;

  /// No description provided for @analyticsReminderNotifTitle.
  ///
  /// In en, this message translates to:
  /// **'We miss you at SP3!'**
  String get analyticsReminderNotifTitle;

  /// No description provided for @analyticsReminderNotifBody.
  ///
  /// In en, this message translates to:
  /// **'It\'s been a while since your last harvest or listing. Reach out to the cooperative if you need any help.'**
  String get analyticsReminderNotifBody;

  /// No description provided for @analyticsReminderSent.
  ///
  /// In en, this message translates to:
  /// **'Reminder sent to {count} members.'**
  String analyticsReminderSent(int count);

  /// No description provided for @analyticsReminderError.
  ///
  /// In en, this message translates to:
  /// **'Could not send reminders. Please try again.'**
  String get analyticsReminderError;

  /// No description provided for @analyticsLoanHealth.
  ///
  /// In en, this message translates to:
  /// **'Loan Collection Health'**
  String get analyticsLoanHealth;

  /// No description provided for @analyticsCollectionRate.
  ///
  /// In en, this message translates to:
  /// **'collection rate'**
  String get analyticsCollectionRate;

  /// No description provided for @analyticsPriceSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Price Snapshot'**
  String get analyticsPriceSnapshot;

  /// No description provided for @analyticsViewFullPrices.
  ///
  /// In en, this message translates to:
  /// **'View Full Price Trends →'**
  String get analyticsViewFullPrices;

  /// No description provided for @analyticsNoForecastsYet.
  ///
  /// In en, this message translates to:
  /// **'Forecasts will appear once enough cooperative-wide harvest history is recorded.'**
  String get analyticsNoForecastsYet;

  /// No description provided for @adminCoopPerformanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Cooperative Performance Summary'**
  String get adminCoopPerformanceTitle;

  /// No description provided for @adminUrgentActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Urgent Actions'**
  String get adminUrgentActionsTitle;

  /// No description provided for @adminInventoryAlertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory Alerts'**
  String get adminInventoryAlertsTitle;

  /// No description provided for @adminCalendarTitle.
  ///
  /// In en, this message translates to:
  /// **'Cooperative Calendar'**
  String get adminCalendarTitle;

  /// No description provided for @adminManagementModulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Management Modules'**
  String get adminManagementModulesTitle;

  /// No description provided for @adminRecentActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get adminRecentActivityTitle;

  /// No description provided for @adminViewInventory.
  ///
  /// In en, this message translates to:
  /// **'View Inventory'**
  String get adminViewInventory;

  /// No description provided for @adminViewFullCalendar.
  ///
  /// In en, this message translates to:
  /// **'Full Calendar'**
  String get adminViewFullCalendar;

  /// No description provided for @adminNoRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'No recent activity'**
  String get adminNoRecentActivity;

  /// No description provided for @reportsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get reportsAvailable;

  /// No description provided for @reportsReserved.
  ///
  /// In en, this message translates to:
  /// **'Reserved'**
  String get reportsReserved;

  /// No description provided for @reportsSold.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get reportsSold;

  /// No description provided for @reportsLowStockAlert.
  ///
  /// In en, this message translates to:
  /// **'{count} batches are running low on stock.'**
  String reportsLowStockAlert(int count);

  /// No description provided for @reportsStockByCrop.
  ///
  /// In en, this message translates to:
  /// **'Stock by Crop'**
  String get reportsStockByCrop;

  /// No description provided for @reportsInventoryBatches.
  ///
  /// In en, this message translates to:
  /// **'Inventory Batches'**
  String get reportsInventoryBatches;

  /// No description provided for @reportsSearchBatches.
  ///
  /// In en, this message translates to:
  /// **'Search farmer, crop, or batch number'**
  String get reportsSearchBatches;

  /// No description provided for @reportsNoInventoryYet.
  ///
  /// In en, this message translates to:
  /// **'No inventory batches recorded yet.'**
  String get reportsNoInventoryYet;

  /// No description provided for @reportsLowStockBadge.
  ///
  /// In en, this message translates to:
  /// **'LOW STOCK'**
  String get reportsLowStockBadge;

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

  /// No description provided for @loanHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Loan History'**
  String get loanHistoryTitle;

  /// No description provided for @loanHistoryExportUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Export coming soon'**
  String get loanHistoryExportUnavailable;

  /// No description provided for @loanHistoryUnavailableOffline.
  ///
  /// In en, this message translates to:
  /// **'Loan history requires an internet connection to load.'**
  String get loanHistoryUnavailableOffline;

  /// No description provided for @loanHistoryNoResults.
  ///
  /// In en, this message translates to:
  /// **'No loans match these filters.'**
  String get loanHistoryNoResults;

  /// No description provided for @loanHistoryAllTimeSummary.
  ///
  /// In en, this message translates to:
  /// **'All-Time Loan Summary'**
  String get loanHistoryAllTimeSummary;

  /// No description provided for @loanHistoryRate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get loanHistoryRate;

  /// No description provided for @loanHistoryTotalIssued.
  ///
  /// In en, this message translates to:
  /// **'{count} Loans'**
  String loanHistoryTotalIssued(int count);

  /// No description provided for @loanHistoryTotalCollected.
  ///
  /// In en, this message translates to:
  /// **'Total Collected'**
  String get loanHistoryTotalCollected;

  /// No description provided for @loanHistoryHealthy.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get loanHistoryHealthy;

  /// No description provided for @loanHistoryNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs Attention'**
  String get loanHistoryNeedsAttention;

  /// No description provided for @loanHistoryFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get loanHistoryFilterAll;

  /// No description provided for @loanHistoryFilterPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get loanHistoryFilterPaid;

  /// No description provided for @loanHistoryThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get loanHistoryThisMonth;

  /// No description provided for @loanHistoryThisQuarter.
  ///
  /// In en, this message translates to:
  /// **'This Quarter'**
  String get loanHistoryThisQuarter;

  /// No description provided for @loanHistoryThisYear.
  ///
  /// In en, this message translates to:
  /// **'This Year'**
  String get loanHistoryThisYear;

  /// No description provided for @loanHistoryAllTime.
  ///
  /// In en, this message translates to:
  /// **'All Time'**
  String get loanHistoryAllTime;

  /// No description provided for @loanHistorySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search farmer, reference, or member ID'**
  String get loanHistorySearchHint;

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

  /// No description provided for @paymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get paymentTitle;

  /// No description provided for @paymentChangeFarmer.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get paymentChangeFarmer;

  /// No description provided for @paymentSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or member ID'**
  String get paymentSearchHint;

  /// No description provided for @paymentNoFarmersFound.
  ///
  /// In en, this message translates to:
  /// **'No farmers found.'**
  String get paymentNoFarmersFound;

  /// No description provided for @paymentNoActiveLoans.
  ///
  /// In en, this message translates to:
  /// **'No active loans'**
  String get paymentNoActiveLoans;

  /// No description provided for @paymentSelectLoan.
  ///
  /// In en, this message translates to:
  /// **'Select which loan to pay'**
  String get paymentSelectLoan;

  /// No description provided for @paymentAmountReceived.
  ///
  /// In en, this message translates to:
  /// **'Amount Received'**
  String get paymentAmountReceived;

  /// No description provided for @paymentOverpaymentNotice.
  ///
  /// In en, this message translates to:
  /// **'This exceeds the remaining balance.'**
  String get paymentOverpaymentNotice;

  /// No description provided for @paymentRemainingAfter.
  ///
  /// In en, this message translates to:
  /// **'Remaining After'**
  String get paymentRemainingAfter;

  /// No description provided for @paymentDate.
  ///
  /// In en, this message translates to:
  /// **'Payment Date'**
  String get paymentDate;

  /// No description provided for @paymentNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get paymentNotes;

  /// No description provided for @paymentSubmit.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get paymentSubmit;

  /// No description provided for @paymentSubmitWithAmount.
  ///
  /// In en, this message translates to:
  /// **'Record {amount} Payment'**
  String paymentSubmitWithAmount(String amount);

  /// No description provided for @paymentSuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded for {name}.'**
  String paymentSuccess(String name);

  /// No description provided for @paymentQueuedOffline.
  ///
  /// In en, this message translates to:
  /// **'Saved locally. Will sync when back online.'**
  String get paymentQueuedOffline;

  /// No description provided for @paymentQueuedTag.
  ///
  /// In en, this message translates to:
  /// **'queued'**
  String get paymentQueuedTag;

  /// No description provided for @paymentSessionSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} payments recorded — {total} collected this session'**
  String paymentSessionSummary(int count, String total);

  /// No description provided for @paymentErrorInvalidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than zero.'**
  String get paymentErrorInvalidAmount;

  /// No description provided for @paymentErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get paymentErrorGeneric;

  /// No description provided for @paymentOverpaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Amount exceeds balance'**
  String get paymentOverpaymentTitle;

  /// No description provided for @paymentOverpaymentMessage.
  ///
  /// In en, this message translates to:
  /// **'This payment is {excess} more than the remaining balance. The loan will be marked as fully paid. Continue?'**
  String paymentOverpaymentMessage(String excess);

  /// No description provided for @paymentOverpaymentConfirm.
  ///
  /// In en, this message translates to:
  /// **'Yes, continue'**
  String get paymentOverpaymentConfirm;

  /// No description provided for @loanDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Loan Details'**
  String get loanDetailsTitle;

  /// No description provided for @loanDetailsNotFound.
  ///
  /// In en, this message translates to:
  /// **'Loan not found.'**
  String get loanDetailsNotFound;

  /// No description provided for @loanDetailsUnavailableOffline.
  ///
  /// In en, this message translates to:
  /// **'Loan details require an internet connection to load.'**
  String get loanDetailsUnavailableOffline;

  /// No description provided for @loanDetailsMarkPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark as Paid'**
  String get loanDetailsMarkPaid;

  /// No description provided for @loanDetailsMarkPaidTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark this loan as paid?'**
  String get loanDetailsMarkPaidTitle;

  /// No description provided for @loanDetailsMarkPaidMessage.
  ///
  /// In en, this message translates to:
  /// **'This settles the loan without recording an additional payment. Use this only for corrections or approved write-offs.'**
  String get loanDetailsMarkPaidMessage;

  /// No description provided for @loanDetailsMarkPaidReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get loanDetailsMarkPaidReasonHint;

  /// No description provided for @loanDetailsMarkPaidConfirm.
  ///
  /// In en, this message translates to:
  /// **'Mark as Paid'**
  String get loanDetailsMarkPaidConfirm;

  /// No description provided for @loanDetailsMarkPaidSuccess.
  ///
  /// In en, this message translates to:
  /// **'Loan marked as paid.'**
  String get loanDetailsMarkPaidSuccess;

  /// No description provided for @loanDetailsMarkPaidError.
  ///
  /// In en, this message translates to:
  /// **'Could not update the loan. Please try again.'**
  String get loanDetailsMarkPaidError;

  /// No description provided for @loanDetailsPaymentHistory.
  ///
  /// In en, this message translates to:
  /// **'Payment History'**
  String get loanDetailsPaymentHistory;

  /// No description provided for @loanDetailsNoPayments.
  ///
  /// In en, this message translates to:
  /// **'No payments recorded yet.'**
  String get loanDetailsNoPayments;

  /// No description provided for @loanDetailsNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get loanDetailsNotesLabel;

  /// No description provided for @loanDetailsBalanceAfter.
  ///
  /// In en, this message translates to:
  /// **'Balance after: {amount}'**
  String loanDetailsBalanceAfter(String amount);

  /// No description provided for @loanDetailsPaidBy.
  ///
  /// In en, this message translates to:
  /// **'By {name}'**
  String loanDetailsPaidBy(String name);

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
  /// **'Broadcast Announcements'**
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
