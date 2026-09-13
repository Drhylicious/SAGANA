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

  /// No description provided for @navListings.
  ///
  /// In en, this message translates to:
  /// **'Listings'**
  String get navListings;

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

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

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

  /// No description provided for @sectionPersonalInformation.
  ///
  /// In en, this message translates to:
  /// **'Personal Information'**
  String get sectionPersonalInformation;

  /// No description provided for @sectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get sectionSecurity;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailAddress;

  /// No description provided for @emailCannotBeChanged.
  ///
  /// In en, this message translates to:
  /// **'Email address cannot be changed.'**
  String get emailCannotBeChanged;

  /// No description provided for @updateYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Update your password'**
  String get updateYourPassword;

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

  /// No description provided for @sectionStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get sectionStorage;

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
  /// **'Name, phone number, purok'**
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

  /// No description provided for @currentPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Current Password is required.'**
  String get currentPasswordRequired;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get passwordsDoNotMatch;

  /// No description provided for @passwordUpdatedSigningOut.
  ///
  /// In en, this message translates to:
  /// **'Password updated. Signing you out…'**
  String get passwordUpdatedSigningOut;

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

  /// No description provided for @adminProfilePurok.
  ///
  /// In en, this message translates to:
  /// **'Purok'**
  String get adminProfilePurok;

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
  /// **'Organizational details are managed through cooperative administration records.'**
  String get adminProfileOrgInfoHint;

  /// No description provided for @adminProfileFarmerAccounts.
  ///
  /// In en, this message translates to:
  /// **'Farmer Accounts'**
  String get adminProfileFarmerAccounts;

  /// No description provided for @adminProfileFarmerAccountsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Farmer Members'**
  String get adminProfileFarmerAccountsSubtitle;

  /// No description provided for @adminProfileOfficerAccounts.
  ///
  /// In en, this message translates to:
  /// **'Officer Accounts'**
  String get adminProfileOfficerAccounts;

  /// No description provided for @adminProfileOfficerAccountsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage cooperative officers'**
  String get adminProfileOfficerAccountsSubtitle;

  /// No description provided for @adminProfileSystemOverview.
  ///
  /// In en, this message translates to:
  /// **'System Overview'**
  String get adminProfileSystemOverview;

  /// No description provided for @adminProfileSystemOverviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open operational dashboards'**
  String get adminProfileSystemOverviewSubtitle;

  /// No description provided for @adminProfileYourActivity.
  ///
  /// In en, this message translates to:
  /// **'Your Activity'**
  String get adminProfileYourActivity;

  /// No description provided for @adminProfileActivitySummary.
  ///
  /// In en, this message translates to:
  /// **'Activity Summary'**
  String get adminProfileActivitySummary;

  /// No description provided for @adminProfileActivitySummaryCaption.
  ///
  /// In en, this message translates to:
  /// **'See your recent administrative work at a glance.'**
  String get adminProfileActivitySummaryCaption;

  /// No description provided for @adminProfileQuickAccess.
  ///
  /// In en, this message translates to:
  /// **'Quick Access'**
  String get adminProfileQuickAccess;

  /// No description provided for @adminProfileQuickAccessCaption.
  ///
  /// In en, this message translates to:
  /// **'Open common admin workflows without leaving the profile.'**
  String get adminProfileQuickAccessCaption;

  /// No description provided for @adminProfileOrganizationalInfoCaption.
  ///
  /// In en, this message translates to:
  /// **'This information is tied to your cooperative administration record.'**
  String get adminProfileOrganizationalInfoCaption;

  /// No description provided for @adminProfileEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get adminProfileEmail;

  /// No description provided for @adminProfileAccountStatus.
  ///
  /// In en, this message translates to:
  /// **'Account Status'**
  String get adminProfileAccountStatus;

  /// No description provided for @adminProfileManageAdminAccounts.
  ///
  /// In en, this message translates to:
  /// **'Manage Admin Accounts'**
  String get adminProfileManageAdminAccounts;

  /// No description provided for @adminProfileManageAdminAccountsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create and review administrator access'**
  String get adminProfileManageAdminAccountsSubtitle;

  /// No description provided for @adminProfileManageOfficerAccounts.
  ///
  /// In en, this message translates to:
  /// **'Manage Officer Accounts'**
  String get adminProfileManageOfficerAccounts;

  /// No description provided for @adminProfileManageOfficerAccountsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add and manage officers'**
  String get adminProfileManageOfficerAccountsSubtitle;

  /// No description provided for @adminProfileRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get adminProfileRecentActivity;

  /// No description provided for @adminProfileRecentActivitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review recent admin actions'**
  String get adminProfileRecentActivitySubtitle;

  /// No description provided for @adminProfilePricesUpdated.
  ///
  /// In en, this message translates to:
  /// **'Prices Updated'**
  String get adminProfilePricesUpdated;

  /// No description provided for @adminProfilePricesUpdatedCaption.
  ///
  /// In en, this message translates to:
  /// **'Count of price records you\'ve entered'**
  String get adminProfilePricesUpdatedCaption;

  /// No description provided for @adminProfilePricesUpdatedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Count of price records you\'ve entered'**
  String get adminProfilePricesUpdatedSubtitle;

  /// No description provided for @adminProfileBroadcastsSent.
  ///
  /// In en, this message translates to:
  /// **'Broadcasts Sent'**
  String get adminProfileBroadcastsSent;

  /// No description provided for @adminProfileBroadcastsSentCaption.
  ///
  /// In en, this message translates to:
  /// **'Count of broadcasts you\'ve sent'**
  String get adminProfileBroadcastsSentCaption;

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

  /// No description provided for @reportsReminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Send reminder to inactive members'**
  String get reportsReminderTitle;

  /// No description provided for @reportsReminderBody.
  ///
  /// In en, this message translates to:
  /// **'This will notify inactive members to update their activity.'**
  String get reportsReminderBody;

  /// No description provided for @reportsReminderSent.
  ///
  /// In en, this message translates to:
  /// **'Reminders sent.'**
  String get reportsReminderSent;

  /// No description provided for @reportsReminderFailed.
  ///
  /// In en, this message translates to:
  /// **'Reminders could not be sent.'**
  String get reportsReminderFailed;

  /// No description provided for @reportsNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs Attention'**
  String get reportsNeedsAttention;

  /// No description provided for @reportsReportingTools.
  ///
  /// In en, this message translates to:
  /// **'Reporting Tools'**
  String get reportsReportingTools;

  /// No description provided for @reportsExportHistory.
  ///
  /// In en, this message translates to:
  /// **'Export History'**
  String get reportsExportHistory;

  /// No description provided for @reportsExecutiveSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Executive Snapshot'**
  String get reportsExecutiveSnapshot;

  /// No description provided for @reportsOverdueLoans.
  ///
  /// In en, this message translates to:
  /// **'Overdue Loans'**
  String get reportsOverdueLoans;

  /// No description provided for @reportsInactiveMembers.
  ///
  /// In en, this message translates to:
  /// **'Inactive Members'**
  String get reportsInactiveMembers;

  /// No description provided for @reportsRemindInactiveMembers.
  ///
  /// In en, this message translates to:
  /// **'Remind'**
  String get reportsRemindInactiveMembers;

  /// No description provided for @reportsAllClear.
  ///
  /// In en, this message translates to:
  /// **'All clear'**
  String get reportsAllClear;

  /// No description provided for @reportsLastExport.
  ///
  /// In en, this message translates to:
  /// **'Last export'**
  String get reportsLastExport;

  /// No description provided for @reportsQuickInsights.
  ///
  /// In en, this message translates to:
  /// **'Quick Insights'**
  String get reportsQuickInsights;

  /// No description provided for @reportsInsightTopCrop.
  ///
  /// In en, this message translates to:
  /// **'Top Crop'**
  String get reportsInsightTopCrop;

  /// No description provided for @reportsInsightTopFarmer.
  ///
  /// In en, this message translates to:
  /// **'Top Contributor'**
  String get reportsInsightTopFarmer;

  /// No description provided for @reportsInsightTopExpense.
  ///
  /// In en, this message translates to:
  /// **'Largest Expense'**
  String get reportsInsightTopExpense;

  /// No description provided for @reportsViewAllExports.
  ///
  /// In en, this message translates to:
  /// **'View All in Export Center'**
  String get reportsViewAllExports;

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

  /// No description provided for @reportsAvgSale.
  ///
  /// In en, this message translates to:
  /// **'Avg Sale'**
  String get reportsAvgSale;

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

  /// No description provided for @reportsCoopStockReport.
  ///
  /// In en, this message translates to:
  /// **'Cooperative Stock Report'**
  String get reportsCoopStockReport;

  /// No description provided for @reportsCoopStockByCategory.
  ///
  /// In en, this message translates to:
  /// **'Stock by Category'**
  String get reportsCoopStockByCategory;

  /// No description provided for @reportsCoopStockItems.
  ///
  /// In en, this message translates to:
  /// **'Stock Items'**
  String get reportsCoopStockItems;

  /// No description provided for @reportsTotalItems.
  ///
  /// In en, this message translates to:
  /// **'Total Items'**
  String get reportsTotalItems;

  /// No description provided for @reportsLowStockItems.
  ///
  /// In en, this message translates to:
  /// **'Low Stock'**
  String get reportsLowStockItems;

  /// No description provided for @reportsCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get reportsCategories;

  /// No description provided for @reportsSearchItems.
  ///
  /// In en, this message translates to:
  /// **'Search items…'**
  String get reportsSearchItems;

  /// No description provided for @reportsNoCoopStockYet.
  ///
  /// In en, this message translates to:
  /// **'No cooperative stock recorded yet'**
  String get reportsNoCoopStockYet;

  /// No description provided for @reportsAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get reportsAll;

  /// No description provided for @reportsSoldOut.
  ///
  /// In en, this message translates to:
  /// **'Sold Out'**
  String get reportsSoldOut;

  /// No description provided for @reportsInventoryReport.
  ///
  /// In en, this message translates to:
  /// **'Farmer Harvest Report'**
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
  /// **'Member Patronage Report'**
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

  /// No description provided for @balikTangkilikReconciliationHint.
  ///
  /// In en, this message translates to:
  /// **'The entered amount ({entered}) differs from the live total ({liveTotal}). Please reconcile before saving.'**
  String balikTangkilikReconciliationHint(String entered, String liveTotal);

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
  /// **'Member Patronage Report uses a specific year, not a period:'**
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

  /// No description provided for @reportsHarvestManagement.
  ///
  /// In en, this message translates to:
  /// **'Harvest Report'**
  String get reportsHarvestManagement;

  /// No description provided for @reportsActivityTrendsTab.
  ///
  /// In en, this message translates to:
  /// **'Activity & Trends'**
  String get reportsActivityTrendsTab;

  /// No description provided for @reportsBatchesStockTab.
  ///
  /// In en, this message translates to:
  /// **'Batches & Stock'**
  String get reportsBatchesStockTab;

  /// No description provided for @reportsViewBatch.
  ///
  /// In en, this message translates to:
  /// **'View Batch'**
  String get reportsViewBatch;

  /// No description provided for @reportsViewHarvest.
  ///
  /// In en, this message translates to:
  /// **'View Harvest'**
  String get reportsViewHarvest;

  /// No description provided for @reportsHarvestedQty.
  ///
  /// In en, this message translates to:
  /// **'Harvested'**
  String get reportsHarvestedQty;

  /// No description provided for @reportsTotalAvailableStock.
  ///
  /// In en, this message translates to:
  /// **'Total Available Stock'**
  String get reportsTotalAvailableStock;

  /// No description provided for @reportsLiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get reportsLiveLabel;

  /// No description provided for @reportsNoBatchFound.
  ///
  /// In en, this message translates to:
  /// **'No inventory batch found for this harvest.'**
  String get reportsNoBatchFound;

  /// No description provided for @reportsNoHarvestFound.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find the source harvest for this batch.'**
  String get reportsNoHarvestFound;

  /// No description provided for @reportsSearchHarvestsWithBatch.
  ///
  /// In en, this message translates to:
  /// **'Search farmer, crop, or batch number'**
  String get reportsSearchHarvestsWithBatch;

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

  /// No description provided for @loanDashOverdueHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review and follow up before the next BOD meeting.'**
  String get loanDashOverdueHeroSubtitle;

  /// No description provided for @loanDashReviewOverdue.
  ///
  /// In en, this message translates to:
  /// **'Review Overdue Loans'**
  String get loanDashReviewOverdue;

  /// No description provided for @loanDashActiveSection.
  ///
  /// In en, this message translates to:
  /// **'Active Loans'**
  String get loanDashActiveSection;

  /// No description provided for @loanDashRecentActivitySection.
  ///
  /// In en, this message translates to:
  /// **'Loan History'**
  String get loanDashRecentActivitySection;

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

  /// No description provided for @loanDashNoRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'No active or overdue loans right now.'**
  String get loanDashNoRecentActivity;

  /// No description provided for @loanDashSyncIssueIssuanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Loan Issuance Sync Issue'**
  String get loanDashSyncIssueIssuanceTitle;

  /// No description provided for @loanDashSyncIssuePaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Loan Payment Sync Issue'**
  String get loanDashSyncIssuePaymentTitle;

  /// No description provided for @loanDashSyncIssueLastAttempt.
  ///
  /// In en, this message translates to:
  /// **'Last attempt: {when}'**
  String loanDashSyncIssueLastAttempt(String when);

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

  /// No description provided for @loanHistoryNoResultsForFilter.
  ///
  /// In en, this message translates to:
  /// **'No loans match this status or period yet.'**
  String get loanHistoryNoResultsForFilter;

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

  /// No description provided for @loanHistoryNoActivity.
  ///
  /// In en, this message translates to:
  /// **'No Activity'**
  String get loanHistoryNoActivity;

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

  /// No description provided for @loanHistoryFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter Loans'**
  String get loanHistoryFilterTitle;

  /// No description provided for @loanHistoryApplyFilter.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get loanHistoryApplyFilter;

  /// No description provided for @loanDashActionPayments.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get loanDashActionPayments;

  /// No description provided for @loanDashNoRecentActivitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'New loans and upcoming payments will appear here once recorded.'**
  String get loanDashNoRecentActivitySubtitle;

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

  /// No description provided for @issueLoanNoFarmerResults.
  ///
  /// In en, this message translates to:
  /// **'No farmers match your search.'**
  String get issueLoanNoFarmerResults;

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

  /// No description provided for @issueLoanStandingLoading.
  ///
  /// In en, this message translates to:
  /// **'Checking outstanding balance…'**
  String get issueLoanStandingLoading;

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

  /// No description provided for @issueLoanSelectItem.
  ///
  /// In en, this message translates to:
  /// **'Select Item'**
  String get issueLoanSelectItem;

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

  /// No description provided for @paymentContextualTitle.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s Loan'**
  String paymentContextualTitle(String name);

  /// No description provided for @paymentChangeFarmer.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get paymentChangeFarmer;

  /// No description provided for @paymentSwitchFarmer.
  ///
  /// In en, this message translates to:
  /// **'Switch Farmer'**
  String get paymentSwitchFarmer;

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

  /// No description provided for @paymentDetailsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment Details'**
  String get paymentDetailsSectionTitle;

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

  /// No description provided for @loanDetailsContextualTitle.
  ///
  /// In en, this message translates to:
  /// **'Loan {reference}'**
  String loanDetailsContextualTitle(String reference);

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

  /// No description provided for @loanDetailsMarkPaidCaption.
  ///
  /// In en, this message translates to:
  /// **'For corrections or approved write-offs only.'**
  String get loanDetailsMarkPaidCaption;

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
  /// **'Supply Chain Management'**
  String get supplyChainTitle;

  /// No description provided for @supplyChainOpsSummary.
  ///
  /// In en, this message translates to:
  /// **'Operations Summary'**
  String get supplyChainOpsSummary;

  /// No description provided for @supplyChainInsights.
  ///
  /// In en, this message translates to:
  /// **'Actionable Insights'**
  String get supplyChainInsights;

  /// No description provided for @supplyChainFlow.
  ///
  /// In en, this message translates to:
  /// **'Cooperative Flow'**
  String get supplyChainFlow;

  /// No description provided for @supplyChainPlannedOps.
  ///
  /// In en, this message translates to:
  /// **'Planned Operations'**
  String get supplyChainPlannedOps;

  /// No description provided for @supplyChainPlannedOpsDesc.
  ///
  /// In en, this message translates to:
  /// **'Collection scheduling, warehouse movement tracking, and delivery logistics will appear here once the cooperative\'s real workflow is confirmed on-site.'**
  String get supplyChainPlannedOpsDesc;

  /// No description provided for @supplyChainMapSection.
  ///
  /// In en, this message translates to:
  /// **'Farmer Locations'**
  String get supplyChainMapSection;

  /// No description provided for @supplyChainRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get supplyChainRefresh;

  /// No description provided for @supplyChainAllMapped.
  ///
  /// In en, this message translates to:
  /// **'All members have a mapped farm location.'**
  String get supplyChainAllMapped;

  /// No description provided for @supplyChainAllSubmitted.
  ///
  /// In en, this message translates to:
  /// **'All harvests have been submitted to the cooperative.'**
  String get supplyChainAllSubmitted;

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

  /// No description provided for @buyerNavBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get buyerNavBrowse;

  /// No description provided for @buyerNavOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get buyerNavOrders;

  /// No description provided for @buyerNavPrices.
  ///
  /// In en, this message translates to:
  /// **'Prices'**
  String get buyerNavPrices;

  /// No description provided for @buyerNavAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get buyerNavAccount;

  /// No description provided for @buyerBrowseTitle.
  ///
  /// In en, this message translates to:
  /// **'Marketplace'**
  String get buyerBrowseTitle;

  /// No description provided for @buyerBrowseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fresh produce from SP3 farmers'**
  String get buyerBrowseSubtitle;

  /// No description provided for @buyerBrowseSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search crops or variety'**
  String get buyerBrowseSearchHint;

  /// No description provided for @buyerBrowseEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Marketplace is quiet right now'**
  String get buyerBrowseEmptyTitle;

  /// No description provided for @buyerBrowseEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Check back soon for new listings from SP3 farmers.'**
  String get buyerBrowseEmptyBody;

  /// No description provided for @buyerBrowseNoResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No listings match your filters'**
  String get buyerBrowseNoResultsTitle;

  /// No description provided for @buyerBrowseNoResultsBody.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term or category.'**
  String get buyerBrowseNoResultsBody;

  /// No description provided for @buyerBrowseSoldOut.
  ///
  /// In en, this message translates to:
  /// **'Sold Out'**
  String get buyerBrowseSoldOut;

  /// No description provided for @buyerBrowseLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low Stock'**
  String get buyerBrowseLowStock;

  /// No description provided for @buyerBrowseOrderNow.
  ///
  /// In en, this message translates to:
  /// **'Order Now'**
  String get buyerBrowseOrderNow;

  /// No description provided for @buyerBrowseAvailableSuffix.
  ///
  /// In en, this message translates to:
  /// **'available'**
  String get buyerBrowseAvailableSuffix;

  /// No description provided for @buyerBrowseAboveMarketRange.
  ///
  /// In en, this message translates to:
  /// **'Priced outside typical market range'**
  String get buyerBrowseAboveMarketRange;

  /// No description provided for @dashboardAllClearTitle.
  ///
  /// In en, this message translates to:
  /// **'All Clear'**
  String get dashboardAllClearTitle;

  /// No description provided for @dashboardAllClearMessage.
  ///
  /// In en, this message translates to:
  /// **'No urgent items today. Keep up the good work!'**
  String get dashboardAllClearMessage;

  /// No description provided for @dashboardQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get dashboardQuickActions;

  /// No description provided for @quickActionRecordHarvest.
  ///
  /// In en, this message translates to:
  /// **'Record Harvest'**
  String get quickActionRecordHarvest;

  /// No description provided for @quickActionCreateListing.
  ///
  /// In en, this message translates to:
  /// **'Create Listing'**
  String get quickActionCreateListing;

  /// No description provided for @quickActionCheckPrices.
  ///
  /// In en, this message translates to:
  /// **'Check Prices'**
  String get quickActionCheckPrices;

  /// No description provided for @purchaseSummary.
  ///
  /// In en, this message translates to:
  /// **'Purchase Summary'**
  String get purchaseSummary;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get recentActivity;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @buyerDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Buyer'**
  String get buyerDefaultName;

  /// No description provided for @statOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get statOrders;

  /// No description provided for @statCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statCompleted;

  /// No description provided for @statSpent.
  ///
  /// In en, this message translates to:
  /// **'Spent'**
  String get statSpent;

  /// No description provided for @buyerNoOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get buyerNoOrdersTitle;

  /// No description provided for @buyerNoOrdersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start browsing the marketplace to place your first order.'**
  String get buyerNoOrdersSubtitle;

  /// No description provided for @browseMarketplace.
  ///
  /// In en, this message translates to:
  /// **'Browse Marketplace'**
  String get browseMarketplace;

  /// No description provided for @buyerOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'My Orders'**
  String get buyerOrdersTitle;

  /// No description provided for @buyerOrdersTabPending.
  ///
  /// In en, this message translates to:
  /// **'Pending ({count})'**
  String buyerOrdersTabPending(int count);

  /// No description provided for @buyerOrdersTabApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved ({count})'**
  String buyerOrdersTabApproved(int count);

  /// No description provided for @buyerOrdersTabCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed ({count})'**
  String buyerOrdersTabCompleted(int count);

  /// No description provided for @buyerOrdersTabCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled ({count})'**
  String buyerOrdersTabCancelled(int count);

  /// No description provided for @buyerOrdersEmptyPending.
  ///
  /// In en, this message translates to:
  /// **'No pending orders'**
  String get buyerOrdersEmptyPending;

  /// No description provided for @buyerOrdersEmptyApproved.
  ///
  /// In en, this message translates to:
  /// **'No approved orders yet'**
  String get buyerOrdersEmptyApproved;

  /// No description provided for @buyerOrdersEmptyCompleted.
  ///
  /// In en, this message translates to:
  /// **'No completed orders yet'**
  String get buyerOrdersEmptyCompleted;

  /// No description provided for @buyerOrdersEmptyCancelled.
  ///
  /// In en, this message translates to:
  /// **'No cancelled orders'**
  String get buyerOrdersEmptyCancelled;

  /// No description provided for @buyerOrdersPickupBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Order Ready for Pickup!'**
  String get buyerOrdersPickupBannerTitle;

  /// No description provided for @buyerOrdersPickupBannerBody.
  ///
  /// In en, this message translates to:
  /// **'You have {count} approved orders waiting for pickup at {cooperative}.'**
  String buyerOrdersPickupBannerBody(int count, String cooperative);

  /// No description provided for @buyerOrdersQuantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get buyerOrdersQuantityLabel;

  /// No description provided for @buyerOrdersTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get buyerOrdersTotalLabel;

  /// No description provided for @buyerOrdersCancelledOn.
  ///
  /// In en, this message translates to:
  /// **'Cancelled on {date}'**
  String buyerOrdersCancelledOn(String date);

  /// No description provided for @buyerOrdersViewPickupDetails.
  ///
  /// In en, this message translates to:
  /// **'View Pickup Details'**
  String get buyerOrdersViewPickupDetails;

  /// No description provided for @buyerOrdersReorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get buyerOrdersReorder;

  /// No description provided for @buyerOrdersBrowseAgain.
  ///
  /// In en, this message translates to:
  /// **'Browse Again'**
  String get buyerOrdersBrowseAgain;

  /// No description provided for @buyerOrdersAwaitingReview.
  ///
  /// In en, this message translates to:
  /// **'Awaiting cooperative review'**
  String get buyerOrdersAwaitingReview;

  /// No description provided for @buyerNotifMenuMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get buyerNotifMenuMarkAllRead;

  /// No description provided for @buyerNotifMenuClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get buyerNotifMenuClearAll;

  /// No description provided for @buyerNotifFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get buyerNotifFilterAll;

  /// No description provided for @buyerNotifFilterListings.
  ///
  /// In en, this message translates to:
  /// **'Listings'**
  String get buyerNotifFilterListings;

  /// No description provided for @buyerNotifEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get buyerNotifEmptyTitle;

  /// No description provided for @buyerNotifEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll see order and marketplace updates here.'**
  String get buyerNotifEmptyBody;

  /// No description provided for @buyerNotifClearDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear All Notifications?'**
  String get buyerNotifClearDialogTitle;

  /// No description provided for @buyerNotifClearDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get buyerNotifClearDialogMessage;

  /// No description provided for @buyerNotifDialogClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get buyerNotifDialogClearAll;

  /// No description provided for @buyerNotifTimeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String buyerNotifTimeMinutesAgo(int count);

  /// No description provided for @buyerNotifTimeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String buyerNotifTimeHoursAgo(int count);

  /// No description provided for @buyerNotifTimeYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get buyerNotifTimeYesterday;

  /// No description provided for @buyerNotifTimeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String buyerNotifTimeDaysAgo(int count);

  /// No description provided for @buyerActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get buyerActivityTitle;

  /// No description provided for @buyerActivityViewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get buyerActivityViewAll;

  /// No description provided for @buyerActivityEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recent activity'**
  String get buyerActivityEmpty;

  /// No description provided for @buyerPriceTitle.
  ///
  /// In en, this message translates to:
  /// **'Market Prices'**
  String get buyerPriceTitle;

  /// No description provided for @buyerPriceSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get buyerPriceSearchLabel;

  /// No description provided for @buyerPriceSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search crops...'**
  String get buyerPriceSearchHint;

  /// No description provided for @buyerPriceFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get buyerPriceFilterAll;

  /// No description provided for @buyerPriceTypeSp3.
  ///
  /// In en, this message translates to:
  /// **'Cooperative Market Price'**
  String get buyerPriceTypeSp3;

  /// No description provided for @buyerPriceTypeMarketRef.
  ///
  /// In en, this message translates to:
  /// **'Public Market Price'**
  String get buyerPriceTypeMarketRef;

  /// No description provided for @buyerPriceEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No price data yet'**
  String get buyerPriceEmptyTitle;

  /// No description provided for @buyerPriceEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Price data will appear here once SP3 Cooperative records market rates for a crop.'**
  String get buyerPriceEmptyBody;

  /// No description provided for @buyerPriceNoResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No crops match your search or filters'**
  String get buyerPriceNoResultsTitle;

  /// No description provided for @buyerPriceClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get buyerPriceClearFilters;

  /// No description provided for @buyerPriceListedTag.
  ///
  /// In en, this message translates to:
  /// **'Currently available on marketplace'**
  String get buyerPriceListedTag;

  /// No description provided for @buyerPriceNotListedTag.
  ///
  /// In en, this message translates to:
  /// **'Not currently listed'**
  String get buyerPriceNotListedTag;

  /// No description provided for @buyerPriceNoTrendHistory.
  ///
  /// In en, this message translates to:
  /// **'Not enough history for a trend chart yet'**
  String get buyerPriceNoTrendHistory;

  /// No description provided for @buyerPriceStatHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get buyerPriceStatHigh;

  /// No description provided for @buyerPriceStatLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get buyerPriceStatLow;

  /// No description provided for @buyerPriceStatCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get buyerPriceStatCurrent;

  /// No description provided for @buyerPriceFilterPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter Market Prices'**
  String get buyerPriceFilterPanelTitle;

  /// No description provided for @buyerPriceFilterPanelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Refine the list by crop category or crop'**
  String get buyerPriceFilterPanelSubtitle;

  /// No description provided for @buyerPriceFilterCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'CROP CATEGORY'**
  String get buyerPriceFilterCategoryLabel;

  /// No description provided for @buyerPriceFilterCropLabel.
  ///
  /// In en, this message translates to:
  /// **'CROP'**
  String get buyerPriceFilterCropLabel;

  /// No description provided for @buyerPriceResetAll.
  ///
  /// In en, this message translates to:
  /// **'Reset All'**
  String get buyerPriceResetAll;

  /// No description provided for @buyerPriceApplyFilters.
  ///
  /// In en, this message translates to:
  /// **'Apply Filters'**
  String get buyerPriceApplyFilters;

  /// No description provided for @buyerOrdersStatusPending.
  ///
  /// In en, this message translates to:
  /// **'PENDING REVIEW'**
  String get buyerOrdersStatusPending;

  /// No description provided for @buyerOrdersStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'APPROVED'**
  String get buyerOrdersStatusApproved;

  /// No description provided for @buyerOrdersStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'COMPLETED'**
  String get buyerOrdersStatusCompleted;

  /// No description provided for @buyerOrdersStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'CANCELLED'**
  String get buyerOrdersStatusCancelled;

  /// No description provided for @buyerActivityFilterProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get buyerActivityFilterProfile;

  /// No description provided for @buyerActivityOrderApproved.
  ///
  /// In en, this message translates to:
  /// **'Order Approved'**
  String get buyerActivityOrderApproved;

  /// No description provided for @buyerActivityOrderCompleted.
  ///
  /// In en, this message translates to:
  /// **'Order Completed'**
  String get buyerActivityOrderCompleted;

  /// No description provided for @buyerActivityOrderCancelled.
  ///
  /// In en, this message translates to:
  /// **'Order Cancelled'**
  String get buyerActivityOrderCancelled;

  /// No description provided for @buyerActivityOrderUpdated.
  ///
  /// In en, this message translates to:
  /// **'Order Updated'**
  String get buyerActivityOrderUpdated;

  /// No description provided for @buyerActivityStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get buyerActivityStatusCancelled;

  /// No description provided for @buyerActivityAllEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get buyerActivityAllEmptyTitle;

  /// No description provided for @buyerActivityAllEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Orders you place and profile changes you make will show up here.'**
  String get buyerActivityAllEmptyBody;

  /// No description provided for @buyerCartTitle.
  ///
  /// In en, this message translates to:
  /// **'My Cart'**
  String get buyerCartTitle;

  /// No description provided for @buyerCartEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your cart is empty'**
  String get buyerCartEmptyTitle;

  /// No description provided for @buyerCartEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add produce from the marketplace — you can queue up several items and check out at once.'**
  String get buyerCartEmptyBody;

  /// No description provided for @buyerCartPlacingOrder.
  ///
  /// In en, this message translates to:
  /// **'Placing order {index} of {total}'**
  String buyerCartPlacingOrder(int index, int total);

  /// No description provided for @buyerCartItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String buyerCartItemCount(int count);

  /// No description provided for @buyerCartItemsFrom.
  ///
  /// In en, this message translates to:
  /// **'{count} items from {cooperative}'**
  String buyerCartItemsFrom(int count, String cooperative);

  /// No description provided for @buyerCartProceedCheckout.
  ///
  /// In en, this message translates to:
  /// **'Proceed to Checkout'**
  String get buyerCartProceedCheckout;

  /// No description provided for @buyerCartAdjustedRemoved.
  ///
  /// In en, this message translates to:
  /// **'{name} is no longer available and was removed from your cart.'**
  String buyerCartAdjustedRemoved(String name);

  /// No description provided for @buyerCartAdjustedReduced.
  ///
  /// In en, this message translates to:
  /// **'{name} was reduced to {qty}kg — only that much remains.'**
  String buyerCartAdjustedReduced(String name, String qty);

  /// No description provided for @buyerCartStockChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your cart was updated'**
  String get buyerCartStockChangedTitle;

  /// No description provided for @buyerCartStockChangedBody.
  ///
  /// In en, this message translates to:
  /// **'Stock changed since these items were added:'**
  String get buyerCartStockChangedBody;

  /// No description provided for @buyerCartReviewCart.
  ///
  /// In en, this message translates to:
  /// **'Review Cart'**
  String get buyerCartReviewCart;

  /// No description provided for @buyerCartConfirmOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Order'**
  String get buyerCartConfirmOrderTitle;

  /// No description provided for @buyerCartTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get buyerCartTotalLabel;

  /// No description provided for @buyerCartPickupNotice.
  ///
  /// In en, this message translates to:
  /// **'Pickup at {location}. No delivery — you must arrange transport.'**
  String buyerCartPickupNotice(String location);

  /// No description provided for @buyerCartConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get buyerCartConfirm;

  /// No description provided for @photoUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Photo upload failed. Please try again.'**
  String get photoUploadFailed;

  /// No description provided for @fullNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Full name is required.'**
  String get fullNameEmpty;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated.'**
  String get profileUpdated;

  /// No description provided for @saveChangesFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to save changes. Please try again.'**
  String get saveChangesFailed;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change Photo'**
  String get changePhoto;

  /// No description provided for @personalInformation.
  ///
  /// In en, this message translates to:
  /// **'Personal Information'**
  String get personalInformation;

  /// No description provided for @updatePasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update your account password'**
  String get updatePasswordSubtitle;

  /// No description provided for @aboutSagana.
  ///
  /// In en, this message translates to:
  /// **'About SAGANA'**
  String get aboutSagana;

  /// No description provided for @aboutSaganaBody.
  ///
  /// In en, this message translates to:
  /// **'SAGANA helps buyers connect with trusted SP3 farmers and manage purchases in one place.'**
  String get aboutSaganaBody;

  /// No description provided for @adminAboutSaganaBody.
  ///
  /// In en, this message translates to:
  /// **'SAGANA helps cooperative admins manage members, marketplace listings, loans, inventory, and reports in one place.'**
  String get adminAboutSaganaBody;

  /// No description provided for @contactSp3.
  ///
  /// In en, this message translates to:
  /// **'Contact SP3'**
  String get contactSp3;

  /// No description provided for @contactSp3Body.
  ///
  /// In en, this message translates to:
  /// **'For concerns about your account, orders, or payments, please visit the cooperative office or reach out to your assigned coordinator.'**
  String get contactSp3Body;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @privacyPolicyBody.
  ///
  /// In en, this message translates to:
  /// **'Your account, order details, and contact information are kept secure and accessible only to authorized cooperative personnel.'**
  String get privacyPolicyBody;

  /// No description provided for @termsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get termsOfUse;

  /// No description provided for @termsOfUseBody.
  ///
  /// In en, this message translates to:
  /// **'By using SAGANA, you agree to use the platform responsibly and follow cooperative policies.'**
  String get termsOfUseBody;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logOut;

  /// No description provided for @buyerListingAddedToCart.
  ///
  /// In en, this message translates to:
  /// **'Added to cart — {name}'**
  String buyerListingAddedToCart(String name);

  /// No description provided for @buyerListingViewCart.
  ///
  /// In en, this message translates to:
  /// **'View Cart'**
  String get buyerListingViewCart;

  /// No description provided for @buyerListingNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'This listing is no longer available.'**
  String get buyerListingNotAvailable;

  /// No description provided for @buyerListingSp3Badge.
  ///
  /// In en, this message translates to:
  /// **'✓ SP3 Cooperative'**
  String get buyerListingSp3Badge;

  /// No description provided for @buyerListingBatchNo.
  ///
  /// In en, this message translates to:
  /// **'Batch No.'**
  String get buyerListingBatchNo;

  /// No description provided for @buyerListingHarvestDate.
  ///
  /// In en, this message translates to:
  /// **'Harvest Date'**
  String get buyerListingHarvestDate;

  /// No description provided for @buyerListingAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get buyerListingAvailable;

  /// No description provided for @buyerListingCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get buyerListingCategory;

  /// No description provided for @buyerListingSellingPrice.
  ///
  /// In en, this message translates to:
  /// **'Selling Price'**
  String get buyerListingSellingPrice;

  /// No description provided for @buyerListingWithinRange.
  ///
  /// In en, this message translates to:
  /// **'Within market range'**
  String get buyerListingWithinRange;

  /// No description provided for @buyerListingAboveRange.
  ///
  /// In en, this message translates to:
  /// **'Above market range'**
  String get buyerListingAboveRange;

  /// No description provided for @buyerListingMarketRate.
  ///
  /// In en, this message translates to:
  /// **'Market Rate: ₱{price}/kg'**
  String buyerListingMarketRate(String price);

  /// No description provided for @buyerListingMoreFromSp3.
  ///
  /// In en, this message translates to:
  /// **'More from SP3'**
  String get buyerListingMoreFromSp3;

  /// No description provided for @buyerListingAddToCart.
  ///
  /// In en, this message translates to:
  /// **'Add to Cart'**
  String get buyerListingAddToCart;

  /// No description provided for @buyerListingPlaceOrder.
  ///
  /// In en, this message translates to:
  /// **'Place Order — ₱{total}'**
  String buyerListingPlaceOrder(String total);

  /// No description provided for @buyerListingOrderQty.
  ///
  /// In en, this message translates to:
  /// **'Order Quantity (kg)'**
  String get buyerListingOrderQty;

  /// No description provided for @buyerListingMaxAvailable.
  ///
  /// In en, this message translates to:
  /// **'Max: {kg} kg available'**
  String buyerListingMaxAvailable(String kg);

  /// No description provided for @buyerListingPickupLocation.
  ///
  /// In en, this message translates to:
  /// **'📍 Pickup Location'**
  String get buyerListingPickupLocation;

  /// No description provided for @buyerListingNoDelivery.
  ///
  /// In en, this message translates to:
  /// **'No delivery available. Buyer must arrange transport.'**
  String get buyerListingNoDelivery;

  /// No description provided for @buyerPricePerKg.
  ///
  /// In en, this message translates to:
  /// **'Price per kg'**
  String get buyerPricePerKg;

  /// No description provided for @buyerHarvestedToday.
  ///
  /// In en, this message translates to:
  /// **'Harvested today'**
  String get buyerHarvestedToday;

  /// No description provided for @buyerHarvestedYesterday.
  ///
  /// In en, this message translates to:
  /// **'Harvested yesterday'**
  String get buyerHarvestedYesterday;

  /// No description provided for @buyerHarvestedDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'Harvested {count} days ago'**
  String buyerHarvestedDaysAgo(int count);

  /// No description provided for @buyerOrderDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Order #{ref}'**
  String buyerOrderDetailTitle(String ref);

  /// No description provided for @buyerOrderDetailNotFound.
  ///
  /// In en, this message translates to:
  /// **'Order not found.'**
  String get buyerOrderDetailNotFound;

  /// No description provided for @buyerOrderDetailReadyPickup.
  ///
  /// In en, this message translates to:
  /// **'Ready for Pickup'**
  String get buyerOrderDetailReadyPickup;

  /// No description provided for @buyerOrderDetailPickedUp.
  ///
  /// In en, this message translates to:
  /// **'Picked up'**
  String get buyerOrderDetailPickedUp;

  /// No description provided for @buyerOrderDetailCancelledStatus.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled'**
  String get buyerOrderDetailCancelledStatus;

  /// No description provided for @buyerOrderDetailMsgApproved.
  ///
  /// In en, this message translates to:
  /// **'Your order has been approved by {cooperative}. Please contact SP3 to arrange your pickup schedule.'**
  String buyerOrderDetailMsgApproved(String cooperative);

  /// No description provided for @buyerOrderDetailMsgPending.
  ///
  /// In en, this message translates to:
  /// **'Your order is awaiting review by {cooperative}. You\'ll be notified once it\'s approved.'**
  String buyerOrderDetailMsgPending(String cooperative);

  /// No description provided for @buyerOrderDetailMsgCompleted.
  ///
  /// In en, this message translates to:
  /// **'This order has been picked up. Thank you for supporting SP3 farmers!'**
  String get buyerOrderDetailMsgCompleted;

  /// No description provided for @buyerOrderDetailMsgCancelled.
  ///
  /// In en, this message translates to:
  /// **'This order was cancelled and is no longer active.'**
  String get buyerOrderDetailMsgCancelled;

  /// No description provided for @buyerOrderDetailContactCoop.
  ///
  /// In en, this message translates to:
  /// **'Contact SP3 Cooperative'**
  String get buyerOrderDetailContactCoop;

  /// No description provided for @buyerOrderDetailComingSoon.
  ///
  /// In en, this message translates to:
  /// **'SP3 contact number coming soon.'**
  String get buyerOrderDetailComingSoon;

  /// No description provided for @buyerOrderDetailStepPlaced.
  ///
  /// In en, this message translates to:
  /// **'Order Placed'**
  String get buyerOrderDetailStepPlaced;

  /// No description provided for @buyerOrderDetailStepPendingReview.
  ///
  /// In en, this message translates to:
  /// **'Pending Review'**
  String get buyerOrderDetailStepPendingReview;

  /// No description provided for @buyerOrderDetailStepApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get buyerOrderDetailStepApproved;

  /// No description provided for @buyerOrderDetailStepCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get buyerOrderDetailStepCompleted;

  /// No description provided for @buyerOrderDetailPendingTimestamp.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get buyerOrderDetailPendingTimestamp;

  /// No description provided for @buyerOrderDetailJourney.
  ///
  /// In en, this message translates to:
  /// **'Order Journey'**
  String get buyerOrderDetailJourney;

  /// No description provided for @buyerOrderDetailBatchRef.
  ///
  /// In en, this message translates to:
  /// **'Batch Reference'**
  String get buyerOrderDetailBatchRef;

  /// No description provided for @buyerOrderDetailFreshness.
  ///
  /// In en, this message translates to:
  /// **'Freshness'**
  String get buyerOrderDetailFreshness;

  /// No description provided for @buyerOrderDetailSummary.
  ///
  /// In en, this message translates to:
  /// **'Order Summary'**
  String get buyerOrderDetailSummary;

  /// No description provided for @buyerOrderDetailReferenceLabel.
  ///
  /// In en, this message translates to:
  /// **'REFERENCE'**
  String get buyerOrderDetailReferenceLabel;

  /// No description provided for @buyerOrderDetailDateLabel.
  ///
  /// In en, this message translates to:
  /// **'ORDER DATE'**
  String get buyerOrderDetailDateLabel;

  /// No description provided for @buyerOrderDetailPaymentInfo.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT INFORMATION'**
  String get buyerOrderDetailPaymentInfo;

  /// No description provided for @buyerOrderDetailPaymentBody.
  ///
  /// In en, this message translates to:
  /// **'Payment for this order is collected at the time of pickup at the cooperative. SP3 accepts cash payment upon collection.'**
  String get buyerOrderDetailPaymentBody;

  /// No description provided for @buyerOrderDetailPickupLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Pickup Location'**
  String get buyerOrderDetailPickupLocationTitle;

  /// No description provided for @buyerOrderDetailBodSchedule.
  ///
  /// In en, this message translates to:
  /// **'BOD Meeting Schedule'**
  String get buyerOrderDetailBodSchedule;

  /// No description provided for @buyerOrderDetailBodBody.
  ///
  /// In en, this message translates to:
  /// **'Every 1st Saturday of the month — payments and pickups can be coordinated during this meeting.'**
  String get buyerOrderDetailBodBody;

  /// No description provided for @buyerOrderDetailNeedHelp.
  ///
  /// In en, this message translates to:
  /// **'Need help with this order?'**
  String get buyerOrderDetailNeedHelp;

  /// No description provided for @buyerOrderDetailSupportBody.
  ///
  /// In en, this message translates to:
  /// **'Contact SP3 Agriculture Cooperative directly for assistance.'**
  String get buyerOrderDetailSupportBody;

  /// No description provided for @buyerOrderDetailCallCoop.
  ///
  /// In en, this message translates to:
  /// **'Call SP3 Cooperative'**
  String get buyerOrderDetailCallCoop;

  /// No description provided for @buyerOrderDetailBrowseMore.
  ///
  /// In en, this message translates to:
  /// **'Browse More Products'**
  String get buyerOrderDetailBrowseMore;

  /// No description provided for @buyerOrderSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Order Placed!'**
  String get buyerOrderSuccessTitle;

  /// No description provided for @buyerOrderSuccessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'SP3 Agriculture Cooperative will review your order shortly.'**
  String get buyerOrderSuccessSubtitle;

  /// No description provided for @buyerOrderSuccessViewOrders.
  ///
  /// In en, this message translates to:
  /// **'View My Orders'**
  String get buyerOrderSuccessViewOrders;

  /// No description provided for @buyerOrderSuccessContinueShopping.
  ///
  /// In en, this message translates to:
  /// **'Continue Shopping'**
  String get buyerOrderSuccessContinueShopping;

  /// No description provided for @buyerCheckoutResultPartialTitle.
  ///
  /// In en, this message translates to:
  /// **'{succeeded} of {total} Items Ordered'**
  String buyerCheckoutResultPartialTitle(int succeeded, int total);

  /// No description provided for @buyerCheckoutResultPartialBody.
  ///
  /// In en, this message translates to:
  /// **'Some items couldn\'t be ordered — see details below.'**
  String get buyerCheckoutResultPartialBody;

  /// No description provided for @buyerCheckoutResultOrderedLabel.
  ///
  /// In en, this message translates to:
  /// **'ORDERED'**
  String get buyerCheckoutResultOrderedLabel;

  /// No description provided for @buyerCheckoutResultFailedLabel.
  ///
  /// In en, this message translates to:
  /// **'COULDN\'T BE ORDERED'**
  String get buyerCheckoutResultFailedLabel;

  /// No description provided for @buyerMemberSince.
  ///
  /// In en, this message translates to:
  /// **'Member since {date}'**
  String buyerMemberSince(String date);

  /// No description provided for @brandingTagline.
  ///
  /// In en, this message translates to:
  /// **'Streamlined Agricultural Gateway for\nAgribusiness, Networking, and Analytics'**
  String get brandingTagline;

  /// No description provided for @brandingDevelopedBy.
  ///
  /// In en, this message translates to:
  /// **'Developed by Marinduque State University — BSIT'**
  String get brandingDevelopedBy;

  /// No description provided for @brandingPartner.
  ///
  /// In en, this message translates to:
  /// **'Partner: SP3 Agriculture Cooperative'**
  String get brandingPartner;

  /// No description provided for @registerFullNameHintFarmer.
  ///
  /// In en, this message translates to:
  /// **'As it appears in cooperative records'**
  String get registerFullNameHintFarmer;

  /// No description provided for @registerFullNameHintBuyer.
  ///
  /// In en, this message translates to:
  /// **'Your full name'**
  String get registerFullNameHintBuyer;

  /// No description provided for @registerEnterFullName.
  ///
  /// In en, this message translates to:
  /// **'Enter your full name'**
  String get registerEnterFullName;

  /// No description provided for @registerCheckingName.
  ///
  /// In en, this message translates to:
  /// **'Please wait — checking this name…'**
  String get registerCheckingName;

  /// No description provided for @registerCheckingRegistry.
  ///
  /// In en, this message translates to:
  /// **'Please wait — checking SP3 member registry…'**
  String get registerCheckingRegistry;

  /// No description provided for @registerChooseAvailableUsername.
  ///
  /// In en, this message translates to:
  /// **'Please choose an available username.'**
  String get registerChooseAvailableUsername;

  /// No description provided for @registerNameTakenTitle.
  ///
  /// In en, this message translates to:
  /// **'Name Already Registered'**
  String get registerNameTakenTitle;

  /// No description provided for @registerNameAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'This full name is already registered. Please log in instead, or contact the SP3 Agriculture Cooperative if you believe this is a mistake.'**
  String get registerNameAlreadyRegistered;

  /// No description provided for @registerRegistryMatchMessage.
  ///
  /// In en, this message translates to:
  /// **'Your name was found in the official SP3 member registry. Your SAGANA username has been assigned automatically.'**
  String get registerRegistryMatchMessage;

  /// No description provided for @registerRegistryNoMatchMessage.
  ///
  /// In en, this message translates to:
  /// **'Your name was not found in the SP3 member registry. You may still register — your application will be reviewed by the SP3 Cooperative.'**
  String get registerRegistryNoMatchMessage;

  /// No description provided for @registerPhoneOptional.
  ///
  /// In en, this message translates to:
  /// **'Phone Number (optional)'**
  String get registerPhoneOptional;

  /// No description provided for @registerInvalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid PH number (09XXXXXXXXX)'**
  String get registerInvalidPhone;

  /// No description provided for @registerEmailOptional.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get registerEmailOptional;

  /// No description provided for @registerInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get registerInvalidEmail;

  /// No description provided for @registerEmailTaken.
  ///
  /// In en, this message translates to:
  /// **'This email address is already used by another account.'**
  String get registerEmailTaken;

  /// No description provided for @registerPurokOptional.
  ///
  /// In en, this message translates to:
  /// **'Purok (optional)'**
  String get registerPurokOptional;

  /// No description provided for @registerDob.
  ///
  /// In en, this message translates to:
  /// **'Date of Birth *'**
  String get registerDob;

  /// No description provided for @registerDobSelect.
  ///
  /// In en, this message translates to:
  /// **'Select your date of birth'**
  String get registerDobSelect;

  /// No description provided for @registerDobHelp.
  ///
  /// In en, this message translates to:
  /// **'You must be at least 18 years old to join'**
  String get registerDobHelp;

  /// No description provided for @registerGenderOptional.
  ///
  /// In en, this message translates to:
  /// **'Gender (optional)'**
  String get registerGenderOptional;

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get registerTitle;

  /// No description provided for @registerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Join the SP3 cooperative network'**
  String get registerSubtitle;

  /// No description provided for @registerRoleFarmer.
  ///
  /// In en, this message translates to:
  /// **'Farmer'**
  String get registerRoleFarmer;

  /// No description provided for @registerRoleBuyer.
  ///
  /// In en, this message translates to:
  /// **'Buyer'**
  String get registerRoleBuyer;

  /// No description provided for @registerUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Choose a Username *'**
  String get registerUsernameLabel;

  /// No description provided for @registerUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. juandelacruz'**
  String get registerUsernameHint;

  /// No description provided for @registerUsernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a username'**
  String get registerUsernameRequired;

  /// No description provided for @registerUsernameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Username must be at least 3 characters'**
  String get registerUsernameTooShort;

  /// No description provided for @registerUsernameTaken.
  ///
  /// In en, this message translates to:
  /// **'This username is already taken'**
  String get registerUsernameTaken;

  /// No description provided for @registerUsernameAvailable.
  ///
  /// In en, this message translates to:
  /// **'Username is available!'**
  String get registerUsernameAvailable;

  /// No description provided for @registerUsernameNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'That username is taken.'**
  String get registerUsernameNotAvailable;

  /// No description provided for @registerPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password *'**
  String get registerPasswordLabel;

  /// No description provided for @registerPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get registerPasswordTooShort;

  /// No description provided for @registerConfirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password *'**
  String get registerConfirmPasswordLabel;

  /// No description provided for @registerPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get registerPasswordMismatch;

  /// No description provided for @registerWelcomeOfficialTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to SP3! 🌾'**
  String get registerWelcomeOfficialTitle;

  /// No description provided for @registerAccountCreatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account Created'**
  String get registerAccountCreatedTitle;

  /// No description provided for @registerWelcomeOfficialMessage.
  ///
  /// In en, this message translates to:
  /// **'Welcome, official SP3 member!\n\nYour SAGANA username is:\n{username}\n\nPlease remember this username to log in.'**
  String registerWelcomeOfficialMessage(String username);

  /// No description provided for @registerFarmerCreatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Account created successfully.\n\nYour username is:\n{username}\n\nYour membership is pending verification by the SP3 Agriculture Cooperative. You will be notified once approved.'**
  String registerFarmerCreatedMessage(String username);

  /// No description provided for @registerBuyerCreatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Account created successfully.\n\nYou can now log in with your username:\n{username}'**
  String registerBuyerCreatedMessage(String username);

  /// No description provided for @registerGoToLogin.
  ///
  /// In en, this message translates to:
  /// **'Go to Login'**
  String get registerGoToLogin;

  /// No description provided for @registerAlreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get registerAlreadyHaveAccount;

  /// No description provided for @registerSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get registerSignIn;

  /// No description provided for @registerOfficialMemberFound.
  ///
  /// In en, this message translates to:
  /// **'Official SP3 Member Found ✓'**
  String get registerOfficialMemberFound;

  /// No description provided for @registerNotInRegistry.
  ///
  /// In en, this message translates to:
  /// **'Not in SP3 Registry'**
  String get registerNotInRegistry;

  /// No description provided for @registerYourUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Your SAGANA Username'**
  String get registerYourUsernameLabel;

  /// No description provided for @registerUsernameAutoGenerated.
  ///
  /// In en, this message translates to:
  /// **'Auto-generated · Cannot be changed'**
  String get registerUsernameAutoGenerated;

  /// No description provided for @registerGenderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get registerGenderMale;

  /// No description provided for @registerGenderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get registerGenderFemale;

  /// No description provided for @registerGenderPreferNotToSay.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get registerGenderPreferNotToSay;

  /// No description provided for @issueLoanCapitalIneligible.
  ///
  /// In en, this message translates to:
  /// **'Capital contribution ₱{current} — below the ₱{minimum} minimum required for a loan.'**
  String issueLoanCapitalIneligible(String current, String minimum);

  /// No description provided for @issueLoanCapitalBlocked.
  ///
  /// In en, this message translates to:
  /// **'This member has not met the ₱{minimum} minimum capital contribution required to be issued a loan.'**
  String issueLoanCapitalBlocked(String minimum);

  /// No description provided for @addMemberTitle.
  ///
  /// In en, this message translates to:
  /// **'Add New Member'**
  String get addMemberTitle;

  /// No description provided for @addMemberSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get addMemberSave;

  /// No description provided for @addMemberAdminNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin Notice'**
  String get addMemberAdminNoticeTitle;

  /// No description provided for @addMemberAdminNoticeBody.
  ///
  /// In en, this message translates to:
  /// **'The member will be created with active status and can log in immediately using the credentials below.'**
  String get addMemberAdminNoticeBody;

  /// No description provided for @addMemberSectionCredentials.
  ///
  /// In en, this message translates to:
  /// **'Account Credentials'**
  String get addMemberSectionCredentials;

  /// No description provided for @addMemberUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'SAGANA Username'**
  String get addMemberUsernameLabel;

  /// No description provided for @addMemberUsernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Username is required'**
  String get addMemberUsernameRequired;

  /// No description provided for @addMemberUsernameHelp.
  ///
  /// In en, this message translates to:
  /// **'Automatically generated — Admin-created Farmer accounts are reserved for official SP3 members.'**
  String get addMemberUsernameHelp;

  /// No description provided for @addMemberPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Temporary Password'**
  String get addMemberPasswordLabel;

  /// No description provided for @addMemberPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get addMemberPasswordRequired;

  /// No description provided for @addMemberPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Minimum 8 characters'**
  String get addMemberPasswordTooShort;

  /// No description provided for @addMemberSectionPersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal Information'**
  String get addMemberSectionPersonal;

  /// No description provided for @addMemberFullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get addMemberFullNameLabel;

  /// No description provided for @addMemberFullNameHint.
  ///
  /// In en, this message translates to:
  /// **'As it appears in cooperative records'**
  String get addMemberFullNameHint;

  /// No description provided for @addMemberFullNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Full name is required'**
  String get addMemberFullNameRequired;

  /// No description provided for @addMemberRegistryMatch.
  ///
  /// In en, this message translates to:
  /// **'Matched the SP3 member registry — Purok and phone auto-filled.'**
  String get addMemberRegistryMatch;

  /// No description provided for @addMemberRegistryNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Not in the SP3 member registry. You can still create the account.'**
  String get addMemberRegistryNoMatch;

  /// No description provided for @addMemberPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Number (optional)'**
  String get addMemberPhoneLabel;

  /// No description provided for @addMemberPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid PH number'**
  String get addMemberPhoneInvalid;

  /// No description provided for @addMemberPurokLabel.
  ///
  /// In en, this message translates to:
  /// **'Purok'**
  String get addMemberPurokLabel;

  /// No description provided for @addMemberSelectHint.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get addMemberSelectHint;

  /// No description provided for @addMemberDobLabel.
  ///
  /// In en, this message translates to:
  /// **'Date of Birth (18+)'**
  String get addMemberDobLabel;

  /// No description provided for @addMemberGenderLabel.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get addMemberGenderLabel;

  /// No description provided for @addMemberSectionMembership.
  ///
  /// In en, this message translates to:
  /// **'Cooperative Membership'**
  String get addMemberSectionMembership;

  /// No description provided for @addMemberMemberIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Member ID'**
  String get addMemberMemberIdLabel;

  /// No description provided for @addMemberMemberIdHelp.
  ///
  /// In en, this message translates to:
  /// **'Auto-generated (SP3-year-sequence) — assigned on save, cannot be edited. Distinct from the login username.'**
  String get addMemberMemberIdHelp;

  /// No description provided for @addMemberShareValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Share Value (₱)'**
  String get addMemberShareValueLabel;

  /// No description provided for @addMemberInitialContributionLabel.
  ///
  /// In en, this message translates to:
  /// **'Initial Contribution (₱)'**
  String get addMemberInitialContributionLabel;

  /// No description provided for @addMemberInvalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Invalid number'**
  String get addMemberInvalidNumber;

  /// No description provided for @addMemberContributionHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional opening capital. Members build toward the ₱2,000 annual share; ₱100/month minimum. More payments are recorded later from the member\'s record.'**
  String get addMemberContributionHelp;

  /// No description provided for @addMemberSectionCrops.
  ///
  /// In en, this message translates to:
  /// **'Initial Crops'**
  String get addMemberSectionCrops;

  /// No description provided for @addMemberAddCrop.
  ///
  /// In en, this message translates to:
  /// **'Add Crop'**
  String get addMemberAddCrop;

  /// No description provided for @addMemberNoCropsYet.
  ///
  /// In en, this message translates to:
  /// **'No crops added yet'**
  String get addMemberNoCropsYet;

  /// No description provided for @addMemberSelectCropTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Crop'**
  String get addMemberSelectCropTitle;

  /// No description provided for @addMemberNoCatalogCrops.
  ///
  /// In en, this message translates to:
  /// **'No active crops in Crop Management yet.'**
  String get addMemberNoCatalogCrops;

  /// No description provided for @addMemberAllCropsAdded.
  ///
  /// In en, this message translates to:
  /// **'All catalog crops have been added.'**
  String get addMemberAllCropsAdded;

  /// No description provided for @addMemberClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get addMemberClose;

  /// No description provided for @addMemberSelectPurok.
  ///
  /// In en, this message translates to:
  /// **'Please select a purok.'**
  String get addMemberSelectPurok;

  /// No description provided for @addMemberAgeRequirement.
  ///
  /// In en, this message translates to:
  /// **'The member must be at least 18 years old.'**
  String get addMemberAgeRequirement;

  /// No description provided for @addMemberCreatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'{name} was added successfully.'**
  String addMemberCreatedSuccess(String name);

  /// No description provided for @addMemberPartialIssue.
  ///
  /// In en, this message translates to:
  /// **'{step} step had an issue: {message}'**
  String addMemberPartialIssue(String step, String message);

  /// No description provided for @addMemberCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create member. Please try again.'**
  String get addMemberCreateFailed;

  /// No description provided for @addMemberUsernameTakenRetry.
  ///
  /// In en, this message translates to:
  /// **'That username was just taken — a new one has been generated. Please try again.'**
  String get addMemberUsernameTakenRetry;

  /// No description provided for @addMemberOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline — Cannot Create Account'**
  String get addMemberOffline;

  /// No description provided for @addMemberCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating Account...'**
  String get addMemberCreating;

  /// No description provided for @addMemberCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Create Farmer Account'**
  String get addMemberCreateButton;

  /// No description provided for @pendingNavHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get pendingNavHome;

  /// No description provided for @pendingNavUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get pendingNavUpdates;

  /// No description provided for @pendingNavHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get pendingNavHelp;

  /// No description provided for @pendingNavProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get pendingNavProfile;

  /// No description provided for @pendingHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'SP3 Cooperative'**
  String get pendingHomeTitle;

  /// No description provided for @pendingWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}!'**
  String pendingWelcome(String name);

  /// No description provided for @pendingBannerApproved.
  ///
  /// In en, this message translates to:
  /// **'Your membership has been approved. Tap Continue below to activate your farmer access.'**
  String get pendingBannerApproved;

  /// No description provided for @pendingBannerRejected.
  ///
  /// In en, this message translates to:
  /// **'Your application was not approved. Review your details below and resubmit when ready.'**
  String get pendingBannerRejected;

  /// No description provided for @pendingBannerDraft.
  ///
  /// In en, this message translates to:
  /// **'Your account is ready. Review the details below, then send your application to the cooperative.'**
  String get pendingBannerDraft;

  /// No description provided for @pendingBannerPending.
  ///
  /// In en, this message translates to:
  /// **'Your application has been received and is being reviewed by the cooperative administration. You\'ll be notified here once a decision is made.'**
  String get pendingBannerPending;

  /// No description provided for @pendingOfflineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — updates to your application won\'t come through until you\'re reconnected.'**
  String get pendingOfflineBanner;

  /// No description provided for @pendingApplicationStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Application Status'**
  String get pendingApplicationStatusTitle;

  /// No description provided for @pendingBadgeApproved.
  ///
  /// In en, this message translates to:
  /// **'APPROVED'**
  String get pendingBadgeApproved;

  /// No description provided for @pendingBadgeRejected.
  ///
  /// In en, this message translates to:
  /// **'NOT APPROVED'**
  String get pendingBadgeRejected;

  /// No description provided for @pendingBadgeDraft.
  ///
  /// In en, this message translates to:
  /// **'NOT SUBMITTED'**
  String get pendingBadgeDraft;

  /// No description provided for @pendingBadgePending.
  ///
  /// In en, this message translates to:
  /// **'PENDING REVIEW'**
  String get pendingBadgePending;

  /// No description provided for @pendingYourUsername.
  ///
  /// In en, this message translates to:
  /// **'Your username: {username}'**
  String pendingYourUsername(String username);

  /// No description provided for @pendingApprovedMessage.
  ///
  /// In en, this message translates to:
  /// **'Welcome to the SP3 Agriculture Cooperative, {name}! Tap Continue to acknowledge and unlock your farmer features.'**
  String pendingApprovedMessage(String name);

  /// No description provided for @pendingContinueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue to SAGANA'**
  String get pendingContinueButton;

  /// No description provided for @pendingRejectedReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'Reason from the cooperative'**
  String get pendingRejectedReasonTitle;

  /// No description provided for @pendingNoReasonProvided.
  ///
  /// In en, this message translates to:
  /// **'No reason was provided.'**
  String get pendingNoReasonProvided;

  /// No description provided for @pendingAttemptsRemaining.
  ///
  /// In en, this message translates to:
  /// **'Review and update your details, then resubmit. Attempts remaining: {count} of 3.'**
  String pendingAttemptsRemaining(int count);

  /// No description provided for @pendingAttemptsExhausted.
  ///
  /// In en, this message translates to:
  /// **'You have used all 3 application attempts. Please visit the SP3 Cooperative office to continue.'**
  String get pendingAttemptsExhausted;

  /// No description provided for @pendingReviewEditButton.
  ///
  /// In en, this message translates to:
  /// **'Review & Edit Details'**
  String get pendingReviewEditButton;

  /// No description provided for @pendingResubmitButton.
  ///
  /// In en, this message translates to:
  /// **'Resubmit Application'**
  String get pendingResubmitButton;

  /// No description provided for @pendingDraftMessage.
  ///
  /// In en, this message translates to:
  /// **'Your application has not been sent yet. Check that your details below are correct, then submit to the cooperative for review.'**
  String get pendingDraftMessage;

  /// No description provided for @pendingSubmitButton.
  ///
  /// In en, this message translates to:
  /// **'Submit Application'**
  String get pendingSubmitButton;

  /// No description provided for @pendingStepSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Application Submitted'**
  String get pendingStepSubmitted;

  /// No description provided for @pendingStepSubmittedSub.
  ///
  /// In en, this message translates to:
  /// **'Sent to the cooperative for review'**
  String get pendingStepSubmittedSub;

  /// No description provided for @pendingStepReview.
  ///
  /// In en, this message translates to:
  /// **'Under Review'**
  String get pendingStepReview;

  /// No description provided for @pendingStepReviewSub.
  ///
  /// In en, this message translates to:
  /// **'SP3 Admin is reviewing your application'**
  String get pendingStepReviewSub;

  /// No description provided for @pendingStepDecision.
  ///
  /// In en, this message translates to:
  /// **'Decision'**
  String get pendingStepDecision;

  /// No description provided for @pendingStepDecisionSub.
  ///
  /// In en, this message translates to:
  /// **'You are notified here — approved or not'**
  String get pendingStepDecisionSub;

  /// No description provided for @pendingContactAddress.
  ///
  /// In en, this message translates to:
  /// **'Barangay Payanas, Torrijos, Marinduque'**
  String get pendingContactAddress;

  /// No description provided for @pendingContactBod.
  ///
  /// In en, this message translates to:
  /// **'BOD Meetings: Every 1st Saturday of the month'**
  String get pendingContactBod;

  /// No description provided for @pendingContactMembers.
  ///
  /// In en, this message translates to:
  /// **'52 registered cooperative members'**
  String get pendingContactMembers;

  /// No description provided for @pendingSubmittedToast.
  ///
  /// In en, this message translates to:
  /// **'Application submitted (attempt {attempt} of 3).'**
  String pendingSubmittedToast(int attempt);

  /// No description provided for @pendingDetailsUpdatedToast.
  ///
  /// In en, this message translates to:
  /// **'Details updated.'**
  String get pendingDetailsUpdatedToast;

  /// No description provided for @pendingNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get pendingNotificationsTitle;

  /// No description provided for @pendingNoNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get pendingNoNotifications;

  /// No description provided for @pendingNoNotificationsSub.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be notified here when your\nmembership application is updated.'**
  String get pendingNoNotificationsSub;

  /// No description provided for @pendingHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & FAQ'**
  String get pendingHelpTitle;

  /// No description provided for @pendingHelpIntro.
  ///
  /// In en, this message translates to:
  /// **'Your application is under review. Here are answers to common questions while you wait.'**
  String get pendingHelpIntro;

  /// No description provided for @pendingFaq1Q.
  ///
  /// In en, this message translates to:
  /// **'Why can\'t I access Harvest, Loans, or Marketplace?'**
  String get pendingFaq1Q;

  /// No description provided for @pendingFaq1A.
  ///
  /// In en, this message translates to:
  /// **'These features are exclusive to official SP3 cooperative members. They will become available automatically once an Administrator approves your membership application.'**
  String get pendingFaq1A;

  /// No description provided for @pendingFaq2Q.
  ///
  /// In en, this message translates to:
  /// **'How long does the approval process take?'**
  String get pendingFaq2Q;

  /// No description provided for @pendingFaq2A.
  ///
  /// In en, this message translates to:
  /// **'The cooperative administrator reviews applications at their earliest convenience, usually during or after BOD meetings held on the first Saturday of every month. If your application has been pending for more than one month, please contact the cooperative office directly.'**
  String get pendingFaq2A;

  /// No description provided for @pendingFaq3Q.
  ///
  /// In en, this message translates to:
  /// **'Will I be notified when my application is approved?'**
  String get pendingFaq3Q;

  /// No description provided for @pendingFaq3A.
  ///
  /// In en, this message translates to:
  /// **'Yes. You will receive an in-app notification the moment your application is reviewed. If it is approved, the Home tab shows a Continue button — tap it to acknowledge and unlock your farmer features. If it is not approved, the reason appears on the Home tab and you can update your details and resubmit (3 attempts total).'**
  String get pendingFaq3A;

  /// No description provided for @pendingFaq4Q.
  ///
  /// In en, this message translates to:
  /// **'What is the SP3 Agriculture Cooperative?'**
  String get pendingFaq4Q;

  /// No description provided for @pendingFaq4A.
  ///
  /// In en, this message translates to:
  /// **'SP3 (Samahan ng mga Produktibong Pamilyang Pilipino sa Payanas) is a CDA-registered agricultural cooperative located in Barangay Payanas, Torrijos, Marinduque. It was established on February 1, 2017 and currently serves 52 member-farmers.'**
  String get pendingFaq4A;

  /// No description provided for @pendingFaq5Q.
  ///
  /// In en, this message translates to:
  /// **'What is my SAGANA username for?'**
  String get pendingFaq5Q;

  /// No description provided for @pendingFaq5A.
  ///
  /// In en, this message translates to:
  /// **'Your SAGANA username is your permanent login identifier for this application. Keep it safe and do not share it. If you were recognized as an official SP3 member during registration, your username follows the format SP3-XXXX.'**
  String get pendingFaq5A;

  /// No description provided for @pendingFaq6Q.
  ///
  /// In en, this message translates to:
  /// **'How do I contact the cooperative?'**
  String get pendingFaq6Q;

  /// No description provided for @pendingFaq6A.
  ///
  /// In en, this message translates to:
  /// **'Visit the SP3 Cooperative office at Barangay Payanas, Torrijos, Marinduque. BOD meetings are held every first Saturday of the month and are open to applicants.'**
  String get pendingFaq6A;

  /// No description provided for @pendingProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get pendingProfileTitle;

  /// No description provided for @pendingVerificationBadge.
  ///
  /// In en, this message translates to:
  /// **'PENDING VERIFICATION'**
  String get pendingVerificationBadge;

  /// No description provided for @pendingAccountInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Account Information'**
  String get pendingAccountInfoTitle;

  /// No description provided for @pendingPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get pendingPhoneLabel;

  /// No description provided for @pendingNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get pendingNotSet;

  /// No description provided for @pendingPurokLabel.
  ///
  /// In en, this message translates to:
  /// **'Purok'**
  String get pendingPurokLabel;

  /// No description provided for @pendingLockedFeatures.
  ///
  /// In en, this message translates to:
  /// **'Farm Details, Input Loans, Harvest Summary, Expenses, and Cooperative Contributions will be available after your membership is approved.'**
  String get pendingLockedFeatures;

  /// No description provided for @pendingSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get pendingSignOut;

  /// No description provided for @pendingSignOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to sign out?'**
  String get pendingSignOutConfirm;

  /// No description provided for @pendingCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get pendingCancel;

  /// No description provided for @pendingDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Details'**
  String get pendingDetailsTitle;

  /// No description provided for @pendingFullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get pendingFullNameLabel;

  /// No description provided for @pendingFullNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your full name'**
  String get pendingFullNameRequired;

  /// No description provided for @pendingPhoneOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Number (optional)'**
  String get pendingPhoneOptionalLabel;

  /// No description provided for @pendingPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid PH number'**
  String get pendingPhoneInvalid;

  /// No description provided for @pendingEmailOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get pendingEmailOptionalLabel;

  /// No description provided for @pendingPurokOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Purok (optional)'**
  String get pendingPurokOptionalLabel;

  /// No description provided for @pendingDobLabel.
  ///
  /// In en, this message translates to:
  /// **'Date of Birth (18+)'**
  String get pendingDobLabel;

  /// No description provided for @pendingSelectHint.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get pendingSelectHint;

  /// No description provided for @pendingGenderOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Gender (optional)'**
  String get pendingGenderOptionalLabel;

  /// No description provided for @pendingAgeError.
  ///
  /// In en, this message translates to:
  /// **'You must be at least 18 years old.'**
  String get pendingAgeError;

  /// No description provided for @pendingSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get pendingSave;

  /// No description provided for @createOfficerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Officer Account'**
  String get createOfficerTitle;

  /// No description provided for @createOfficerNotice.
  ///
  /// In en, this message translates to:
  /// **'An Officer gets every Admin module except the Members tab. The person must already be in the Officer Registry.'**
  String get createOfficerNotice;

  /// No description provided for @createOfficerSectionOfficer.
  ///
  /// In en, this message translates to:
  /// **'Officer'**
  String get createOfficerSectionOfficer;

  /// No description provided for @createOfficerFullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get createOfficerFullNameLabel;

  /// No description provided for @createOfficerFullNameHint.
  ///
  /// In en, this message translates to:
  /// **'As recorded in the Officer Registry'**
  String get createOfficerFullNameHint;

  /// No description provided for @createOfficerFullNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Full name is required'**
  String get createOfficerFullNameRequired;

  /// No description provided for @createOfficerNotInRegistry.
  ///
  /// In en, this message translates to:
  /// **'This name is not in the Officer Registry. Add it to the registry first.'**
  String get createOfficerNotInRegistry;

  /// No description provided for @createOfficerAlreadyHasAccount.
  ///
  /// In en, this message translates to:
  /// **'This Officer Registry record already has an account.'**
  String get createOfficerAlreadyHasAccount;

  /// No description provided for @createOfficerMatched.
  ///
  /// In en, this message translates to:
  /// **'Matched the Officer Registry — details auto-filled.'**
  String get createOfficerMatched;

  /// No description provided for @createOfficerEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get createOfficerEmailLabel;

  /// No description provided for @createOfficerPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Number (optional)'**
  String get createOfficerPhoneLabel;

  /// No description provided for @createOfficerPositionLabel.
  ///
  /// In en, this message translates to:
  /// **'Position (optional)'**
  String get createOfficerPositionLabel;

  /// No description provided for @createOfficerPositionHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Operations Officer'**
  String get createOfficerPositionHint;

  /// No description provided for @createOfficerEmployeeIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Employee ID'**
  String get createOfficerEmployeeIdLabel;

  /// No description provided for @createOfficerEmployeeIdHelp.
  ///
  /// In en, this message translates to:
  /// **'Auto-generated (EMP-###), assigned on save — cannot be edited.'**
  String get createOfficerEmployeeIdHelp;

  /// No description provided for @createOfficerSectionLogin.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get createOfficerSectionLogin;

  /// No description provided for @createOfficerUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'SAGANA Username'**
  String get createOfficerUsernameLabel;

  /// No description provided for @createOfficerUsernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Username is required'**
  String get createOfficerUsernameRequired;

  /// No description provided for @createOfficerUsernameHelp.
  ///
  /// In en, this message translates to:
  /// **'Automatically generated — cannot be edited.'**
  String get createOfficerUsernameHelp;

  /// No description provided for @createOfficerPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Temporary Password'**
  String get createOfficerPasswordLabel;

  /// No description provided for @createOfficerPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Type one, or tap AUTO'**
  String get createOfficerPasswordHint;

  /// No description provided for @createOfficerPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Minimum 8 characters'**
  String get createOfficerPasswordTooShort;

  /// No description provided for @createOfficerWaitForCheck.
  ///
  /// In en, this message translates to:
  /// **'Wait for the Officer Registry check to finish.'**
  String get createOfficerWaitForCheck;

  /// No description provided for @createOfficerCreated.
  ///
  /// In en, this message translates to:
  /// **'Officer account created.'**
  String get createOfficerCreated;

  /// No description provided for @createOfficerCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating account...'**
  String get createOfficerCreating;

  /// No description provided for @createOfficerCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Create Officer Account'**
  String get createOfficerCreateButton;

  /// No description provided for @farmerMgmtRejectDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Reject {name}'**
  String farmerMgmtRejectDialogTitle(String name);

  /// No description provided for @farmerMgmtRejectHint.
  ///
  /// In en, this message translates to:
  /// **'Explain why the application is not approved. The applicant sees this and can resubmit (3 attempts total).'**
  String get farmerMgmtRejectHint;

  /// No description provided for @farmerMgmtNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get farmerMgmtNext;

  /// No description provided for @farmerMgmtConfirmRejectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Rejection'**
  String get farmerMgmtConfirmRejectionTitle;

  /// No description provided for @farmerMgmtRejectApplicantLine.
  ///
  /// In en, this message translates to:
  /// **'Applicant: {name}'**
  String farmerMgmtRejectApplicantLine(String name);

  /// No description provided for @farmerMgmtRejectOutcomeLine.
  ///
  /// In en, this message translates to:
  /// **'Outcome: Application rejected (they keep their account, no farmer access)'**
  String get farmerMgmtRejectOutcomeLine;

  /// No description provided for @farmerMgmtReasonLine.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String farmerMgmtReasonLine(String reason);

  /// No description provided for @farmerMgmtRejectResubmitLine.
  ///
  /// In en, this message translates to:
  /// **'They can review their details and resubmit.'**
  String get farmerMgmtRejectResubmitLine;

  /// No description provided for @farmerMgmtRejectApplicationAction.
  ///
  /// In en, this message translates to:
  /// **'Reject Application'**
  String get farmerMgmtRejectApplicationAction;

  /// No description provided for @farmerMgmtRejectedToast.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s application was rejected.'**
  String farmerMgmtRejectedToast(String name);

  /// No description provided for @farmerMgmtSuspendDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Suspend {name}'**
  String farmerMgmtSuspendDialogTitle(String name);

  /// No description provided for @farmerMgmtSuspendHint.
  ///
  /// In en, this message translates to:
  /// **'Explain why this account is being suspended. The member sees this and cannot log in until reactivated.'**
  String get farmerMgmtSuspendHint;

  /// No description provided for @farmerMgmtConfirmSuspensionTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Suspension'**
  String get farmerMgmtConfirmSuspensionTitle;

  /// No description provided for @farmerMgmtSuspendMemberLine.
  ///
  /// In en, this message translates to:
  /// **'Member: {name}'**
  String farmerMgmtSuspendMemberLine(String name);

  /// No description provided for @farmerMgmtSuspendOutcomeLine.
  ///
  /// In en, this message translates to:
  /// **'Outcome: Suspended — blocked from logging in'**
  String get farmerMgmtSuspendOutcomeLine;

  /// No description provided for @farmerMgmtSuspendReactivateLine.
  ///
  /// In en, this message translates to:
  /// **'You can reactivate them at any time.'**
  String get farmerMgmtSuspendReactivateLine;

  /// No description provided for @farmerMgmtSuspendAccountAction.
  ///
  /// In en, this message translates to:
  /// **'Suspend Account'**
  String get farmerMgmtSuspendAccountAction;

  /// No description provided for @farmerMgmtSuspendedToast.
  ///
  /// In en, this message translates to:
  /// **'{name} has been suspended.'**
  String farmerMgmtSuspendedToast(String name);

  /// No description provided for @farmerMgmtCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get farmerMgmtCancel;

  /// No description provided for @farmerMgmtBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get farmerMgmtBack;
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
