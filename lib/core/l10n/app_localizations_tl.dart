// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tagalog (`tl`).
class AppLocalizationsTl extends AppLocalizations {
  AppLocalizationsTl([String locale = 'tl']) : super(locale);

  @override
  String get appName => 'SAGANA';

  @override
  String get appSubtitle => 'Pinasimpleng Agricultural Gateway';

  @override
  String get cooperativeName => 'SP3 Agriculture Cooperative';

  @override
  String get secureGatewayActive => 'Aktibo ang Secure Gateway';

  @override
  String get comingSoon => 'Malapit Na';

  @override
  String comingSoonMessage(String routeName) {
    return 'Ang screen na ito ($routeName) ay ginagawa pa.';
  }

  @override
  String get navHome => 'Home';

  @override
  String get navHarvest => 'Ani';

  @override
  String get navMarketplace => 'Pamilihan';

  @override
  String get navListings => 'Mga Listing';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navProfile => 'Profile';

  @override
  String get greetingMorning => 'Magandang umaga';

  @override
  String get greetingAfternoon => 'Magandang hapon';

  @override
  String get greetingEvening => 'Magandang gabi';

  @override
  String get defaultFarmerName => 'Magsasaka';

  @override
  String get offlineBanner =>
      'Offline ka ngayon. Maaaring hindi available ang ilang feature.';

  @override
  String get login => 'Mag-log In';

  @override
  String get register => 'Magparehistro';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get confirmPassword => 'Kumpirmahin ang Password';

  @override
  String get fullName => 'Buong Pangalan';

  @override
  String get phoneNumber => 'Numero ng Telepono';

  @override
  String get forgotPassword => 'Nakalimutan ang Password?';

  @override
  String get noAccount => 'Wala pang account?';

  @override
  String get haveAccount => 'May account na?';

  @override
  String get signUp => 'Mag-sign Up';

  @override
  String get signOut => 'Mag-sign Out';

  @override
  String get signOutConfirmTitle => 'Mag-sign Out?';

  @override
  String get signOutConfirmMessage =>
      'Maa-log out ka sa SAGANA. Mananatili ang offline records sa device na ito.';

  @override
  String get cancel => 'Kanselahin';

  @override
  String get close => 'Isara';

  @override
  String get commonClose => 'Isara';

  @override
  String get save => 'I-save';

  @override
  String get saveChanges => 'I-save ang mga Pagbabago';

  @override
  String get saving => 'Sine-save...';

  @override
  String get settingsTitle => 'Mga Setting';

  @override
  String get sectionPersonalInformation => 'Personal na Impormasyon';

  @override
  String get sectionSecurity => 'Seguridad';

  @override
  String get emailAddress => 'Address ng Email';

  @override
  String get emailCannotBeChanged => 'Hindi mababago ang email address.';

  @override
  String get updateYourPassword => 'I-update ang iyong password';

  @override
  String get sectionAccount => 'Akawnt';

  @override
  String get sectionNotifications => 'Mga Notification';

  @override
  String get sectionAppPreferences => 'Mga Kagustuhan sa App';

  @override
  String get sectionDataExport => 'Data Export';

  @override
  String get sectionStorage => 'Imbakan';

  @override
  String get sectionSupportInfo => 'Suporta at Impormasyon';

  @override
  String get editProfile => 'I-edit ang Profile';

  @override
  String get editProfileSubtitle => 'Pangalan, telepono, purok';

  @override
  String get editFarmDetails => 'I-edit ang Detalye ng Bukid';

  @override
  String get editFarmDetailsSubtitle =>
      'Pangalan ng bukid, laki ng lupa, lokasyon';

  @override
  String get changePassword => 'Palitan ang Password';

  @override
  String get changePasswordSubtitle => 'I-update ang password ng account';

  @override
  String get language => 'Wika';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTagalog => 'Tagalog';

  @override
  String get appearance => 'Itsura';

  @override
  String get themeLight => 'Maliwanag na Mode';

  @override
  String get themeDark => 'Madilim na Mode';

  @override
  String get backgroundSync => 'Awtomatikong Pag-sync';

  @override
  String get backgroundSyncDescription =>
      'Awtomatikong i-sync ang data kapag bumalik ang internet';

  @override
  String get clearCachedData => 'Burahin ang Cached Data';

  @override
  String get clearCachedDataDescription =>
      'Tinatanggal ang naka-cache na presyo at market data. Hindi maaapektuhan ang harvest at inventory records.';

  @override
  String get clearCachedDataConfirmTitle => 'Burahin ang Cached Data?';

  @override
  String get clearCachedDataConfirmMessage =>
      'Tinatanggal ang naka-cache na presyo at market data. Hindi maaapektuhan ang harvest, inventory, at expenses.';

  @override
  String get clear => 'Burahin';

  @override
  String get notifNewOrder => 'Bagong Order';

  @override
  String get currentPassword => 'Kasalukuyang Password';

  @override
  String get newPassword => 'Bagong Password';

  @override
  String get confirmNewPassword => 'Kumpirmahin ang Bagong Password';

  @override
  String get updatePassword => 'I-update ang Password';

  @override
  String get updating => 'Ina-update...';

  @override
  String get passwordMinLength =>
      'Dapat ay hindi bababa sa 8 character ang password.';

  @override
  String get currentPasswordRequired => 'Kailangan ang kasalukuyang password.';

  @override
  String get passwordsDoNotMatch => 'Hindi magkatugma ang mga password.';

  @override
  String get passwordUpdatedSigningOut =>
      'Na-update ang password. Nilalabas ka…';

  @override
  String get accountCreated => 'Nagawa na ang Account!';

  @override
  String get selectLanguage => 'Pumili ng Wika';

  @override
  String get selectAppearance => 'Pumili ng Itsura';

  @override
  String get adminProfileTitle => 'Profile ng Admin';

  @override
  String get adminProfileLoadError =>
      'Hindi mai-load ang iyong profile. Subukan muli.';

  @override
  String get adminProfileDefaultRole => 'Administrator ng Kooperatiba';

  @override
  String get adminProfileFullName => 'Buong Pangalan';

  @override
  String get adminProfilePhoneNumber => 'Numero ng Telepono';

  @override
  String get adminProfilePurok => 'Purok';

  @override
  String get adminProfileSaveChanges => 'I-save ang Pagbabago';

  @override
  String get adminProfileSaving => 'Nag-save...';

  @override
  String get adminProfileNameRequired => 'Kailangan ang buong pangalan.';

  @override
  String get adminProfileUpdated => 'Matagumpay na na-update ang profile.';

  @override
  String get adminProfileSaveError => 'Hindi na-save. Subukan muli.';

  @override
  String get adminProfileChangePhoto => 'Palitan ang Larawan';

  @override
  String get adminProfileRemovePhoto => 'Alisin ang Larawan';

  @override
  String get adminProfilePhotoUpdated => 'Na-update ang larawan ng profile.';

  @override
  String get adminProfilePhotoError =>
      'Hindi na-update ang larawan. Subukan muli.';

  @override
  String get adminProfileCurrentPassword => 'Kasalukuyang Password';

  @override
  String get adminProfileNewPassword => 'Bagong Password';

  @override
  String get adminProfileConfirmPassword => 'Kumpirmahin ang Bagong Password';

  @override
  String get adminProfilePasswordHint =>
      'Dapat hindi bababa sa 8 karakter ang password.';

  @override
  String get adminProfileAllFieldsRequired => 'Kailangan ang lahat ng field.';

  @override
  String get adminProfilePasswordTooShort =>
      'Dapat hindi bababa sa 8 karakter ang password.';

  @override
  String get adminProfilePasswordMismatch => 'Hindi tugma ang password.';

  @override
  String get adminProfileUpdating => 'Nag-update...';

  @override
  String get adminProfileUpdatePassword => 'I-update ang Password';

  @override
  String get adminProfilePasswordUpdated =>
      'Na-update ang password. Mag-login muli.';

  @override
  String get adminProfileOrganizationalInfo => 'Impormasyon ng Organisasyon';

  @override
  String get adminProfileEmployeeId => 'Employee ID';

  @override
  String get adminProfilePosition => 'Posisyon';

  @override
  String get adminProfileDepartment => 'Departamento';

  @override
  String get adminProfileAdminSince => 'Administrator Mula';

  @override
  String get adminProfileOrgInfoHint =>
      'Ang detalye ng organisasyon ay pinamamahalaan sa pamamagitan ng talaan ng administrasyon ng kooperatiba.';

  @override
  String get adminProfileFarmerAccounts => 'Mga Account ng Magsasaka';

  @override
  String get adminProfileFarmerAccountsSubtitle =>
      'Pamahalaan ang mga Miyembrong Magsasaka';

  @override
  String get adminProfileOfficerAccounts => 'Mga Officer Account';

  @override
  String get adminProfileOfficerAccountsSubtitle =>
      'Pamahalaan ang mga officer ng kooperatiba';

  @override
  String get adminProfileSystemOverview => 'Pangkalahatang-tanaw ng Sistema';

  @override
  String get adminProfileSystemOverviewSubtitle =>
      'Buksan ang mga operational dashboard';

  @override
  String get adminProfileYourActivity => 'Iyong Aktibidad';

  @override
  String get adminProfileActivitySummary => 'Buod ng Aktibidad';

  @override
  String get adminProfileActivitySummaryCaption =>
      'Tingnan ang kamakailang administratibong gawain nang mabilis.';

  @override
  String get adminProfileQuickAccess => 'Mabilis na Pag-access';

  @override
  String get adminProfileQuickAccessCaption =>
      'Buksan ang karaniwang mga workflow ng admin nang direkta.';

  @override
  String get adminProfileOrganizationalInfoCaption =>
      'Ang impormasyong ito ay nauugnay sa talaan ng administrasyon ng kooperatiba.';

  @override
  String get adminProfileEmail => 'Email';

  @override
  String get adminProfileAccountStatus => 'Katayuan ng Account';

  @override
  String get adminProfileManageAdminAccounts =>
      'Pamahalaan ang Mga Admin Account';

  @override
  String get adminProfileManageAdminAccountsSubtitle =>
      'Lumikha at suriin ang access ng administrator';

  @override
  String get adminProfileManageOfficerAccounts =>
      'Pamahalaan ang Mga Officer Account';

  @override
  String get adminProfileManageOfficerAccountsSubtitle =>
      'Magdagdag at pamahalaan ang mga officer';

  @override
  String get adminProfileRecentActivity => 'Kamakailang Aktibidad';

  @override
  String get adminProfileRecentActivitySubtitle =>
      'Suriin ang kamakailang mga aksyon ng admin';

  @override
  String get adminProfilePricesUpdated => 'Na-update ang Presyo';

  @override
  String get adminProfilePricesUpdatedCaption =>
      'Bilang ng price records na iyong naipasok';

  @override
  String get adminProfilePricesUpdatedSubtitle =>
      'Bilang ng price records na iyong naipasok';

  @override
  String get adminProfileBroadcastsSent => 'Mga Naipadalang Broadcast';

  @override
  String get adminProfileBroadcastsSentCaption =>
      'Bilang ng mga broadcast na iyong naipadala';

  @override
  String get adminProfilePreferences => 'Mga Kagustuhan';

  @override
  String get adminProfileDataAndStorage => 'Data at Imbakan';

  @override
  String get adminProfileClearCache => 'I-clear ang Cached Data';

  @override
  String get adminProfileClearCacheTitle => 'I-clear ang Cached Data?';

  @override
  String get adminProfileClearCacheMessage =>
      'Aalisin nito ang lokal na cache ng presyo at datos ng merkado. Hindi maaapektuhan ang iyong mga ulat at talaan.';

  @override
  String get adminProfileClearCacheConfirm => 'I-clear';

  @override
  String get adminProfileCacheCleared => 'Na-clear ang cache.';

  @override
  String get adminProfileSignOut => 'Mag-sign Out';

  @override
  String get adminProfileSignOutTitle => 'Mag-sign Out?';

  @override
  String get adminProfileSignOutMessage => 'Ma-sign out ka sa SAGANA.';

  @override
  String get adminProfileSignOutConfirm => 'Mag-sign Out';

  @override
  String adminProfileAppVersion(String version) {
    return 'SAGANA v$version';
  }

  @override
  String get adminNavDashboard => 'Dashboard';

  @override
  String get adminNavMembers => 'Mga Miyembro';

  @override
  String get adminNavListings => 'Mga Listing';

  @override
  String get listingsPendingTitle => 'Mga Listing';

  @override
  String get listingsAllButton => 'Tingnan Lahat';

  @override
  String get adminNavLoans => 'Mga Utang';

  @override
  String get adminNavReports => 'Mga Ulat';

  @override
  String get reportsHubTitle => 'Mga Ulat sa Operasyon';

  @override
  String get reportsPerformanceSummary => 'Buod ng Pagganap';

  @override
  String get reportsTotalHarvest => 'Kabuuang Ani';

  @override
  String get reportsCoopSales => 'Benta sa Kooperatiba';

  @override
  String get reportsMarketplaceRevenue => 'Kita sa Marketplace';

  @override
  String get reportsActiveLoans => 'Aktibong Pautang';

  @override
  String get reportsTotalExpenses => 'Kabuuang Gastos';

  @override
  String get reportsMemberParticipation => 'Partisipasyon ng Miyembro';

  @override
  String get reportsDetailedReports => 'Detalyadong Ulat';

  @override
  String get reportsManagementTools => 'Mga Kasangkapan sa Pamamahala';

  @override
  String get reportsRecentReports => 'Kamakailang Ulat';

  @override
  String get reportsNoExportsYet =>
      'Wala pang na-export. Gumawa ng isa sa Export Center.';

  @override
  String get reportsReminderTitle =>
      'Ipadala ang paalala sa mga inactive na miyembro';

  @override
  String get reportsReminderBody =>
      'Aalisin nito ang paalala sa mga inactive na miyembro para i-update ang kanilang aktibidad.';

  @override
  String get reportsReminderSent => 'Naipadala ang mga paalala.';

  @override
  String get reportsReminderFailed => 'Hindi maipadala ang mga paalala.';

  @override
  String get reportsNeedsAttention => 'Kailangan ng Pansin';

  @override
  String get reportsReportingTools => 'Mga Tool sa Ulat';

  @override
  String get reportsExportHistory => 'Kasaysayan ng Export';

  @override
  String get reportsExecutiveSnapshot => 'Buod sa Pamamahala';

  @override
  String get reportsOverdueLoans => 'Mga Overdue na Pautang';

  @override
  String get reportsInactiveMembers => 'Mga Inactive na Miyembro';

  @override
  String get reportsRemindInactiveMembers => 'Paalalahanan';

  @override
  String get reportsAllClear => 'Walang problema';

  @override
  String get reportsLastExport => 'Huling export';

  @override
  String get reportsQuickInsights => 'Mga Mabilis na Insight';

  @override
  String get reportsInsightTopCrop => 'Pinakamahusay na Pananim';

  @override
  String get reportsInsightTopFarmer => 'Pinakamahusay na Kontributor';

  @override
  String get reportsInsightTopExpense => 'Pinakamalaking Gastos';

  @override
  String get reportsViewAllExports => 'Tingnan Lahat sa Export Center';

  @override
  String get reportsSalesReport => 'Ulat ng Benta';

  @override
  String get reportsExportComingSoon => 'Malapit na ang Export';

  @override
  String get reportsTotalRevenue => 'Kabuuang Kita';

  @override
  String get reportsAvgSale => 'Karaniwang Benta';

  @override
  String get reportsTotalVolume => 'Kabuuang Dami';

  @override
  String get reportsTransactions => 'Transaksyon';

  @override
  String get reportsCropBreakdown => 'Palay vs. Mani';

  @override
  String get reportsRevenueTrend => 'Takbo ng Kita';

  @override
  String get reportsNotEnoughTrendData =>
      'Hindi pa sapat ang datos para sa takbo.';

  @override
  String get reportsTransactionDetails => 'Detalye ng Transaksyon';

  @override
  String get reportsSearchTransactions =>
      'Maghanap ng magsasaka, pananim, o reference';

  @override
  String get reportsNoSalesRecorded =>
      'Walang naitalang benta sa kooperatiba para sa panahong ito.';

  @override
  String get reportsNoSearchResults =>
      'Walang transaksyong tumugma sa iyong hinanap.';

  @override
  String get reportsCoopStockReport => 'Ulat ng Stock ng Kooperatiba';

  @override
  String get reportsCoopStockByCategory => 'Stock ayon sa Kategorya';

  @override
  String get reportsCoopStockItems => 'Mga Item sa Stock';

  @override
  String get reportsTotalItems => 'Kabuuang Item';

  @override
  String get reportsLowStockItems => 'Mababang Stock';

  @override
  String get reportsCategories => 'Mga Kategorya';

  @override
  String get reportsSearchItems => 'Maghanap ng item…';

  @override
  String get reportsNoCoopStockYet =>
      'Wala pang naitalang stock ng kooperatiba';

  @override
  String get reportsAll => 'Lahat';

  @override
  String get reportsSoldOut => 'Ubos na Stock';

  @override
  String get reportsInventoryReport => 'Ulat ng Ani ng Magsasaka';

  @override
  String get reportsHarvestReport => 'Ulat ng Ani';

  @override
  String get reportsTotalYield => 'Kabuuang Ani';

  @override
  String get reportsUnsyncedEntries => 'Hindi Pa Nasync';

  @override
  String get reportsYieldByCrop => 'Ani kada Pananim';

  @override
  String get reportsYieldTrend => 'Takbo ng Ani';

  @override
  String get reportsHarvestEntries => 'Mga Talaan ng Ani';

  @override
  String get reportsSearchHarvests => 'Maghanap ng magsasaka o pananim';

  @override
  String get reportsNoHarvestsRecorded =>
      'Walang naitalang ani para sa panahong ito.';

  @override
  String get reportsToCoop => 'Sa Kooperatiba';

  @override
  String get reportsNotToCoop => 'Hindi sa Kooperatiba';

  @override
  String get reportsSynced => 'Na-sync';

  @override
  String get reportsPendingSync => 'Naghihintay ng Sync';

  @override
  String get reportsExpenseReport => 'Ulat ng Gastos';

  @override
  String get reportsFarmerFundedTotal => 'Kabuuang Gastos ng Magsasaka';

  @override
  String get reportsSubsidizedItems => 'Mga Subsidized na Item';

  @override
  String get reportsTotalEntries => 'Kabuuang Talaan';

  @override
  String get reportsExpensesByCategory => 'Gastos kada Kategorya';

  @override
  String get reportsSubsidizedTag => 'SUBSIDIZED';

  @override
  String get reportsSpendingTrend => 'Takbo ng Gastos';

  @override
  String get reportsExpenseEntries => 'Mga Talaan ng Gastos';

  @override
  String get reportsSearchExpenses =>
      'Maghanap ng magsasaka, kategorya, o paglalarawan';

  @override
  String get reportsNoExpensesRecorded =>
      'Walang naitalang gastos para sa panahong ito.';

  @override
  String get reportsCollectionTrend => 'Takbo ng Koleksyon';

  @override
  String get reportsNoSearchResultsOrLoans =>
      'Walang pautang na tumugma sa mga filter na ito.';

  @override
  String get reportsLoanReport => 'Ulat ng Pautang';

  @override
  String get reportsMemberContributionReport => 'Ulat ng Patronage ng Miyembro';

  @override
  String reportsTotalCoopSalesLabel(int year) {
    return 'Kabuuang Benta sa Kooperatiba ($year)';
  }

  @override
  String get reportsContributingMembers => 'Mga Miyembrong Nag-aambag';

  @override
  String get reportsParticipationRate => 'Rate ng Partisipasyon';

  @override
  String get reportsMemberBreakdown => 'Detalye ng Miyembro';

  @override
  String get reportsSearchMembers => 'Maghanap ng pangalan o ID ng miyembro';

  @override
  String reportsSharePercent(String percent) {
    return '$percent% na bahagi';
  }

  @override
  String get reportsPalay => 'Palay';

  @override
  String get reportsPeanut => 'Mani';

  @override
  String get reportsNoContributionYet =>
      'Walang naitalang benta sa kooperatiba ngayong taon.';

  @override
  String get reportsAnalyticsDashboard => 'Analytics Dashboard';

  @override
  String get reportsBalikTangkilikManagement => 'Pamamahala ng Balik-Tangkilik';

  @override
  String get balikTangkilikSettingsTab => 'Mga Setting';

  @override
  String get balikTangkilikDistributionTab => 'Distribusyon';

  @override
  String get balikTangkilikHistoryTab => 'Kasaysayan';

  @override
  String get balikTangkilikHistoryTitle => 'Kasaysayan ng Distribusyon';

  @override
  String get balikTangkilikNoHistoryYet => 'Wala pang naitalang distribusyon.';

  @override
  String balikTangkilikYearLogTitle(int year) {
    return 'Distribusyon ng $year';
  }

  @override
  String balikTangkilikYearLogSubtitle(int count) {
    return '$count miyembro ang nabayaran';
  }

  @override
  String get balikTangkilikDistributionComingSoon =>
      'Malapit na ang pagpaplano ng distribusyon.';

  @override
  String get balikTangkilikHistoryComingSoon =>
      'Malapit na ang pagsubaybay sa kasaysayan.';

  @override
  String get balikTangkilikTotalCoopSales => 'Kabuuang Benta sa Kooperatiba';

  @override
  String get balikTangkilikPoolAmount =>
      'Halaga ng Pool na Maaaring I-distribute';

  @override
  String get balikTangkilikInterestRate => 'Interest Rate (%)';

  @override
  String balikTangkilikLiveTotalHint(String amount) {
    return 'Live total mula sa mga naitalang benta: $amount';
  }

  @override
  String balikTangkilikReconciliationHint(String entered, String liveTotal) {
    return 'Pagkakaiba ang halaga na pinasok ($entered) at ang live total ($liveTotal). Pakisuri bago mag-save.';
  }

  @override
  String get balikTangkilikUseThisValue => 'Gamitin ang live total na ito';

  @override
  String get balikTangkilikPoolHint =>
      'Ilagay ang halaga na available para sa pag-distribute sa mga miyembro.';

  @override
  String get balikTangkilikInterestHint =>
      'Ilagay ang taunang interest rate para sa pool.';

  @override
  String get balikTangkilikAfsFinalized => 'AFS Finalized';

  @override
  String get balikTangkilikAfsFinalizedHint =>
      'Markahan ito bilang finalized matapos aprubahan ang taunang financial statement.';

  @override
  String get balikTangkilikSaveSettings => 'I-save ang Mga Setting';

  @override
  String get balikTangkilikInvalidValues =>
      'Pakituloy ang valid at non-negative na halaga sa lahat ng field.';

  @override
  String get balikTangkilikZeroPoolWarningTitle => 'Zero pool amount?';

  @override
  String get balikTangkilikZeroPoolWarningMessage =>
      'Ang pag-save ng zero distributable pool habang finalized ang AFS ay maaaring hadlangan ang future distribution. Ituloy pa rin?';

  @override
  String get balikTangkilikContinueAnyway => 'Ituloy Pa Rin';

  @override
  String balikTangkilikSettingsSaved(int year) {
    return 'Na-save ang mga setting para sa $year.';
  }

  @override
  String get balikTangkilikSaveError =>
      'Hindi ma-save ang Balik-Tangkilik settings. Subukan muli.';

  @override
  String get balikTangkilikMemberBreakdown => 'Detalye ng Miyembro';

  @override
  String get balikTangkilikRefreshEstimates => 'I-refresh ang Estimate';

  @override
  String get balikTangkilikEstimatesRefreshed => 'Na-refresh ang estimate.';

  @override
  String get balikTangkilikRefreshError =>
      'Hindi na-refresh ang estimate. Subukan muli.';

  @override
  String get balikTangkilikAfsNotFinalizedWarning =>
      'Hindi pa tapos ang AFS para sa taong ito. Pumunta sa Settings tab para itapos ito bago maitala ang distribusyon.';

  @override
  String balikTangkilikAlreadyDistributedBanner(int year) {
    return 'Naipamahagi na ang Balik-Tangkilik para sa $year.';
  }

  @override
  String balikTangkilikTotalEstimated(int year) {
    return 'Kabuuang Tinatayang Bayad ($year)';
  }

  @override
  String balikTangkilikTotalDistributed(int year) {
    return 'Kabuuang Naipamahagi ($year)';
  }

  @override
  String get balikTangkilikRecordDistribution => 'Itala ang Distribusyon';

  @override
  String balikTangkilikAlreadyDistributed(int year) {
    return 'Naipamahagi na para sa $year';
  }

  @override
  String get balikTangkilikConfirmTitle => 'Kumpirmahin ang Distribusyon';

  @override
  String balikTangkilikConfirmMessage(int year, int count, String amount) {
    return 'Itatapos mo na ang Balik-Tangkilik para sa $year para sa $count na nag-ambag na miyembro, na may kabuuang $amount.';
  }

  @override
  String get balikTangkilikIrreversibleWarning =>
      'Permanente ang aksyon na ito at hindi na maibabalik.';

  @override
  String get balikTangkilikConfirmDistribute => 'Ipamahagi Na';

  @override
  String balikTangkilikDistributionSuccess(String amount) {
    return 'Naitala ang distribusyon. Kabuuang naibayad: $amount.';
  }

  @override
  String get balikTangkilikDistributionError =>
      'Hindi naitala ang distribusyon. Subukan muli.';

  @override
  String get exportSelectReports => 'Pumili ng Ulat';

  @override
  String get exportPeriod => 'Panahon';

  @override
  String get exportYearForContributionReport =>
      'Ang Ulat ng Patronage ng Miyembro ay gumagamit ng partikular na taon, hindi panahon:';

  @override
  String get exportSelectAtLeastOne =>
      'Pumili ng kahit isang ulat na i-export.';

  @override
  String get exportGenerateButton => 'Bumuo ng Export';

  @override
  String exportGenerated(int count) {
    return '$count file ang nabuo.';
  }

  @override
  String get exportGenerateError => 'Hindi nabuo ang export. Subukan muli.';

  @override
  String get exportFileMissing => 'Wala na ang file na ito sa device na ito.';

  @override
  String get exportSummaryEmpty =>
      'Pumili ng isa o higit pang ulat na i-export bilang CSV.';

  @override
  String exportSummary(int count) {
    return '$count ulat ang i-export bilang hiwalay na CSV file.';
  }

  @override
  String get exportRecentExports => 'Kamakailang Export';

  @override
  String get exportNoHistoryYet => 'Wala pang nabuong export sa device na ito.';

  @override
  String get reportsExportCenter => 'Export Center';

  @override
  String get adminUrgentActions => 'Mga Pangangailangan sa Aksyon';

  @override
  String get adminQuickActions => 'Mga Mabilisang Aksyon';

  @override
  String get adminToolsManagement => 'Mga Tool at Pamamahala';

  @override
  String get adminRecentActivity => 'Kamakailang Aktibidad';

  @override
  String get adminGoToLoanPayments => 'Pumunta sa Loan Payments →';

  @override
  String get analyticsMemberParticipation => 'Partisipasyon ng Miyembro';

  @override
  String get analyticsActiveHarvested => 'Nag-ani';

  @override
  String get analyticsActiveListed => 'Nag-listing Lang';

  @override
  String get analyticsInactive => 'Hindi Aktibo';

  @override
  String analyticsSendReminder(int count) {
    return 'Magpadala ng Paalala ($count)';
  }

  @override
  String get analyticsSendReminderTitle => 'Magpadala ng paalala?';

  @override
  String analyticsSendReminderMessage(int count) {
    return 'Ito ay magpapaalam sa $count hindi aktibong miyembro na makipag-ugnayan sa kooperatiba.';
  }

  @override
  String get analyticsSendReminderConfirm => 'Ipadala';

  @override
  String get analyticsReminderNotifTitle => 'Miss ka namin sa SP3!';

  @override
  String get analyticsReminderNotifBody =>
      'Matagal na mula sa huli mong ani o listing. Makipag-ugnayan sa kooperatiba kung kailangan mo ng tulong.';

  @override
  String analyticsReminderSent(int count) {
    return 'Naipadala ang paalala sa $count miyembro.';
  }

  @override
  String get analyticsReminderError =>
      'Hindi maipadala ang paalala. Subukan muli.';

  @override
  String get analyticsLoanHealth => 'Kalusugan ng Koleksyon ng Pautang';

  @override
  String get analyticsCollectionRate => 'collection rate';

  @override
  String get analyticsPriceSnapshot => 'Snapshot ng Presyo';

  @override
  String get analyticsViewFullPrices => 'Tingnan ang Buong Takbo ng Presyo →';

  @override
  String get analyticsNoForecastsYet =>
      'Lalabas ang forecast kapag sapat na ang naitalang kasaysayan ng ani sa kooperatiba.';

  @override
  String get adminCoopPerformanceTitle => 'Buod ng Pagganap ng Kooperatiba';

  @override
  String get adminUrgentActionsTitle => 'Mga Kailangang Aksyon';

  @override
  String get adminInventoryAlertsTitle => 'Mga Alerto sa Imbentaryo';

  @override
  String get adminCalendarTitle => 'Kalendaryo ng Kooperatibo';

  @override
  String get adminManagementModulesTitle => 'Mga Module ng Pamamahala';

  @override
  String get adminRecentActivityTitle => 'Kamakailang Aktibidad';

  @override
  String get adminViewInventory => 'Tingnan ang Imbentaryo';

  @override
  String get adminViewFullCalendar => 'Buong Kalendaryo';

  @override
  String get adminNoRecentActivity => 'Walang kamakailang aktibidad';

  @override
  String get reportsAvailable => 'Available';

  @override
  String get reportsReserved => 'Nareserba';

  @override
  String get reportsSold => 'Nabenta';

  @override
  String reportsLowStockAlert(int count) {
    return '$count batch ang mababa na ang stock.';
  }

  @override
  String get reportsStockByCrop => 'Stock kada Pananim';

  @override
  String get reportsInventoryBatches => 'Mga Batch ng Imbentaryo';

  @override
  String get reportsSearchBatches =>
      'Maghanap ng magsasaka, pananim, o batch number';

  @override
  String get reportsNoInventoryYet => 'Walang naitalang imbentaryo.';

  @override
  String get reportsLowStockBadge => 'MABABANG STOCK';

  @override
  String get reportsHarvestManagement => 'Pamamahala ng Ani';

  @override
  String get reportsActivityTrendsTab => 'Aktibidad at Trend';

  @override
  String get reportsBatchesStockTab => 'Mga Batch at Stock';

  @override
  String get reportsViewBatch => 'Tingnan ang Batch';

  @override
  String get reportsViewHarvest => 'Tingnan ang Ani';

  @override
  String get reportsHarvestedQty => 'Naani';

  @override
  String get reportsTotalAvailableStock => 'Kabuuang Available na Stock';

  @override
  String get reportsLiveLabel => 'Live';

  @override
  String get reportsNoBatchFound =>
      'Walang natagpuang batch ng imbentaryo para sa aning ito.';

  @override
  String get reportsNoHarvestFound =>
      'Hindi natagpuan ang orihinal na ani para sa batch na ito.';

  @override
  String get reportsSearchHarvestsWithBatch =>
      'Maghanap ng magsasaka, pananim, o batch number';

  @override
  String get loanDashTitle => 'Pamamahala ng Pautang';

  @override
  String get loanDashNextCollection => 'Susunod na Koleksyon ng Bayad';

  @override
  String loanDashFarmersOutstanding(int count) {
    return '$count magsasaka ang may natitirang balanse';
  }

  @override
  String loanDashTotalExpected(String amount) {
    return 'Inaasahang kabuuan: $amount';
  }

  @override
  String get loanDashActiveLoans => 'Aktibong Pautang';

  @override
  String get loanDashTotalOutstanding => 'Kabuuang Balanse';

  @override
  String get loanDashOverdueLoans => 'Overdue na Pautang';

  @override
  String get loanDashPaidThisMonth => 'Nabayaran Ngayong Buwan';

  @override
  String get loanDashActionIssue => 'Magbigay ng Bagong Pautang';

  @override
  String get loanDashActionRecordPayment => 'Itala ang Bayad';

  @override
  String get loanDashActionViewHistory => 'Tingnan ang Kasaysayan';

  @override
  String loanDashOverdueSection(int count) {
    return 'Mga Overdue na Pautang ($count)';
  }

  @override
  String get loanDashOverdueHeroSubtitle =>
      'Suriin at sundan bago ang susunod na miting ng BOD.';

  @override
  String get loanDashReviewOverdue => 'Suriin ang mga Overdue na Pautang';

  @override
  String get loanDashActiveSection => 'Mga Aktibong Pautang';

  @override
  String get loanDashRecentActivitySection => 'Kasaysayan ng Pautang';

  @override
  String get loanDashSeeAll => 'Tingnan lahat';

  @override
  String get loanDashNoOverdue => 'Walang overdue na pautang sa ngayon.';

  @override
  String get loanDashNoActive => 'Walang aktibong pautang sa ngayon.';

  @override
  String get loanDashNoRecentActivity =>
      'Walang aktibo o overdue na pautang sa ngayon.';

  @override
  String get loanDashSyncIssueIssuanceTitle =>
      'Problema sa Pag-sync ng Pautang';

  @override
  String get loanDashSyncIssuePaymentTitle => 'Problema sa Pag-sync ng Bayad';

  @override
  String loanDashSyncIssueLastAttempt(String when) {
    return 'Huling pagtatangka: $when';
  }

  @override
  String get loanDashValue => 'Halaga';

  @override
  String get loanDashPaid => 'Nabayaran';

  @override
  String get loanDashBalance => 'Balanse';

  @override
  String get loanDashNext => 'Susunod';

  @override
  String loanDashOverdueSince(String date) {
    return 'Overdue mula $date';
  }

  @override
  String get loanHistoryTitle => 'Kasaysayan ng Pautang';

  @override
  String get loanHistoryExportUnavailable => 'Malapit na ang Export';

  @override
  String get loanHistoryUnavailableOffline =>
      'Kailangan ng internet para makita ang kasaysayan ng pautang.';

  @override
  String get loanHistoryNoResults =>
      'Walang pautang na tumugma sa mga filter na ito.';

  @override
  String get loanHistoryNoResultsForFilter =>
      'Wala pang pautang na tumugma sa napiling status o panahon.';

  @override
  String get loanHistoryAllTimeSummary => 'Kabuuang Kasaysayan ng Pautang';

  @override
  String get loanHistoryRate => 'Rate';

  @override
  String loanHistoryTotalIssued(int count) {
    return '$count Pautang';
  }

  @override
  String get loanHistoryTotalCollected => 'Kabuuang Nakolekta';

  @override
  String get loanHistoryHealthy => 'Malusog';

  @override
  String get loanHistoryNeedsAttention => 'Kailangan ng Atensyon';

  @override
  String get loanHistoryNoActivity => 'Walang Aktibidad';

  @override
  String get loanHistoryFilterAll => 'Lahat';

  @override
  String get loanHistoryFilterPaid => 'Bayad na';

  @override
  String get loanHistoryThisMonth => 'Ngayong Buwan';

  @override
  String get loanHistoryThisQuarter => 'Ngayong Quarter';

  @override
  String get loanHistoryThisYear => 'Ngayong Taon';

  @override
  String get loanHistoryAllTime => 'Lahat ng Panahon';

  @override
  String get loanHistorySearchHint =>
      'Maghanap ng magsasaka, reference, o member ID';

  @override
  String get loanHistoryFilterTitle => 'I-filter ang Mga Pautang';

  @override
  String get loanHistoryApplyFilter => 'I-apply';

  @override
  String get loanDashActionPayments => 'Itala ang Bayad';

  @override
  String get loanDashNoRecentActivitySubtitle =>
      'Ang mga bagong pautang at paparating na bayarin ay lalabas dito kapag naitala na.';

  @override
  String get adminPriceManagement => 'Pamamahala ng Presyo';

  @override
  String get adminPriceManagementSubtitle =>
      'I-update ang pagbili at presyo ng pananim para sa lahat ng miyembro';

  @override
  String get adminNotificationBroadcast => 'Broadcast ng Notification';

  @override
  String get adminNotificationBroadcastSubtitle =>
      'Magpadala ng anunsyo sa mga magsasaka, bumibili, o partikular na grupo';

  @override
  String get adminSupplyChainMap => 'Mapa ng Supply Chain';

  @override
  String get adminSupplyChainMapSubtitle =>
      'Tingnan ang lahat ng lokasyon ng magsasaka at distribusyon ng pananim';

  @override
  String get adminReviewListings => 'Suriin\nang Mga Listing';

  @override
  String get adminRecordPayment => 'Itala\nang Bayad';

  @override
  String get adminUpdatePrice => 'I-update\nang Presyo';

  @override
  String get adminIssueLoan => 'Magbigay\nng Utang';

  @override
  String get adminViewReports => 'Tingnan\nang Mga Ulat';

  @override
  String get adminManageFarmers => 'Pamahalaan\nang Mga Magsasaka';

  @override
  String get issueLoanTitle => 'Magbigay ng Bagong Pautang';

  @override
  String get issueLoanSelectFarmer => 'Pumili ng Magsasaka';

  @override
  String get issueLoanSearchFarmerHint =>
      'Maghanap gamit ang pangalan o member ID';

  @override
  String get issueLoanNoFarmerSelected => 'Pindutin para pumili ng magsasaka';

  @override
  String get issueLoanNoFarmerResults =>
      'Walang magsasakang tumugma sa iyong hinahanap.';

  @override
  String get issueLoanOutstandingBalance => 'Natitirang Balanse';

  @override
  String get issueLoanOverdueWarning =>
      'May overdue na pautang ang magsasakang ito.';

  @override
  String get issueLoanStandingUnavailableOffline =>
      'Hindi makuha ang balanse habang offline.';

  @override
  String get issueLoanStandingLoading => 'Sinusuri ang natitirang balanse…';

  @override
  String get issueLoanInputItems => 'Mga Input na Ibinigay';

  @override
  String get issueLoanAddItem => 'Magdagdag ng Input';

  @override
  String get issueLoanNoItemsYet => 'Wala pang naidagdag na item.';

  @override
  String get issueLoanSelectItem => 'Pumili ng Item';

  @override
  String get issueLoanItemName => 'Pangalan ng Item';

  @override
  String get issueLoanQuantity => 'Dami';

  @override
  String get issueLoanUnit => 'Yunit';

  @override
  String get issueLoanUnitPrice => 'Presyo bawat Yunit';

  @override
  String get issueLoanLineTotal => 'Kabuuan ng Item';

  @override
  String get issueLoanConfirmItem => 'Kumpirmahin';

  @override
  String get issueLoanCancel => 'Kanselahin';

  @override
  String get issueLoanTotalValue => 'Kabuuang Halaga ng Pautang';

  @override
  String get issueLoanPaymentSchedule => 'Iskedyul ng Bayad';

  @override
  String get issueLoanIssuedDate => 'Petsa ng Pagbibigay';

  @override
  String get issueLoanMonthlyPayment => 'Buwanang Bayad';

  @override
  String get issueLoanNextPaymentDue => 'Susunod na Takdang Bayad';

  @override
  String get issueLoanFrequency => 'Dalas: Buwanan';

  @override
  String get issueLoanVenue => 'Lugar: Barangay Payanas';

  @override
  String get issueLoanNotes => 'Tala (opsyonal)';

  @override
  String get issueLoanSubmit => 'Ibigay ang Pautang';

  @override
  String issueLoanSuccess(String reference) {
    return 'Matagumpay na naibigay ang pautang $reference.';
  }

  @override
  String get issueLoanQueuedOffline =>
      'Na-save nang lokal. Awtomatikong bibigyan ng reference number pagka-sync online.';

  @override
  String get issueLoanErrorNoFarmer => 'Pumili muna ng magsasaka.';

  @override
  String get issueLoanErrorNoItems => 'Magdagdag ng kahit isang input item.';

  @override
  String get issueLoanErrorInvalidMonthly =>
      'Ang buwanang bayad ay dapat higit sa zero.';

  @override
  String get issueLoanErrorGeneric => 'May naganap na problema. Subukan muli.';

  @override
  String get paymentTitle => 'Itala ang Bayad';

  @override
  String paymentContextualTitle(String name) {
    return 'Pautang ni $name';
  }

  @override
  String get paymentChangeFarmer => 'Palitan';

  @override
  String get paymentSwitchFarmer => 'Palitan ng Magsasaka';

  @override
  String get paymentSearchHint => 'Maghanap gamit ang pangalan o member ID';

  @override
  String get paymentNoFarmersFound => 'Walang nahanap na magsasaka.';

  @override
  String get paymentNoActiveLoans => 'Walang aktibong pautang';

  @override
  String get paymentSelectLoan => 'Piliin kung aling pautang babayaran';

  @override
  String get paymentDetailsSectionTitle => 'Detalye ng Bayad';

  @override
  String get paymentAmountReceived => 'Natanggap na Halaga';

  @override
  String get paymentOverpaymentNotice => 'Lampas ito sa natitirang balanse.';

  @override
  String get paymentRemainingAfter => 'Matitira Pagkatapos';

  @override
  String get paymentDate => 'Petsa ng Bayad';

  @override
  String get paymentNotes => 'Tala (opsyonal)';

  @override
  String get paymentSubmit => 'Itala ang Bayad';

  @override
  String paymentSubmitWithAmount(String amount) {
    return 'Itala ang $amount na Bayad';
  }

  @override
  String paymentSuccess(String name) {
    return 'Naitala ang bayad ni $name.';
  }

  @override
  String get paymentQueuedOffline =>
      'Na-save nang lokal. Mag-sy-sync pagka-online.';

  @override
  String get paymentQueuedTag => 'nakapila';

  @override
  String paymentSessionSummary(int count, String total) {
    return '$count bayad ang naitala — $total nakolekta ngayong session';
  }

  @override
  String get paymentErrorInvalidAmount => 'Maglagay ng halagang higit sa zero.';

  @override
  String get paymentErrorGeneric => 'May naganap na problema. Subukan muli.';

  @override
  String get paymentOverpaymentTitle => 'Lampas sa balanse ang halaga';

  @override
  String paymentOverpaymentMessage(String excess) {
    return 'Ang bayad na ito ay $excess na higit sa natitirang balanse. Ituturing na fully paid ang pautang. Magpatuloy?';
  }

  @override
  String get paymentOverpaymentConfirm => 'Oo, magpatuloy';

  @override
  String get loanDetailsTitle => 'Detalye ng Pautang';

  @override
  String loanDetailsContextualTitle(String reference) {
    return 'Pautang $reference';
  }

  @override
  String get loanDetailsNotFound => 'Hindi nahanap ang pautang.';

  @override
  String get loanDetailsUnavailableOffline =>
      'Kailangan ng internet para makita ang detalye ng pautang.';

  @override
  String get loanDetailsMarkPaid => 'Markahang Bayad na';

  @override
  String get loanDetailsMarkPaidCaption =>
      'Para sa mga pagwawasto o inaprubahang pagkansela ng utang lamang.';

  @override
  String get loanDetailsMarkPaidTitle =>
      'Markahan bang bayad na ang pautang na ito?';

  @override
  String get loanDetailsMarkPaidMessage =>
      'Aayusin nito ang pautang nang hindi nagtatala ng karagdagang bayad. Gamitin lamang ito para sa mga pagwawasto o inaprubahang pagkansela ng utang.';

  @override
  String get loanDetailsMarkPaidReasonHint => 'Dahilan (opsyonal)';

  @override
  String get loanDetailsMarkPaidConfirm => 'Markahang Bayad na';

  @override
  String get loanDetailsMarkPaidSuccess =>
      'Naitala bilang bayad na ang pautang.';

  @override
  String get loanDetailsMarkPaidError =>
      'Hindi na-update ang pautang. Subukan muli.';

  @override
  String get loanDetailsPaymentHistory => 'Kasaysayan ng Bayad';

  @override
  String get loanDetailsNoPayments => 'Wala pang naitalang bayad.';

  @override
  String get loanDetailsNotesLabel => 'Mga Tala';

  @override
  String loanDetailsBalanceAfter(String amount) {
    return 'Balanse pagkatapos: $amount';
  }

  @override
  String loanDetailsPaidBy(String name) {
    return 'Ni $name';
  }

  @override
  String get farmerMgmtTitle => 'Pamamahala ng Mga Magsasaka';

  @override
  String get farmerMgmtAdd => 'Idagdag';

  @override
  String get seeAll => 'Tingnan Lahat';

  @override
  String get priceManagementTitle => 'Pamamahala ng Presyo';

  @override
  String get supplyChainTitle => 'Pamamahala ng Supply Chain';

  @override
  String get supplyChainOpsSummary => 'Buod ng Operasyon';

  @override
  String get supplyChainInsights => 'Mga Dapat Pansinin';

  @override
  String get supplyChainFlow => 'Daloy ng Kooperatiba';

  @override
  String get supplyChainPlannedOps => 'Nakaplanong Operasyon';

  @override
  String get supplyChainPlannedOpsDesc =>
      'Ang iskedyul ng pagkolekta, pagsubaybay sa galaw ng bodega, at logistics ng paghahatid ay lalabas dito kapag nakumpirma na ang aktwal na proseso ng kooperatiba sa personal na pagbisita.';

  @override
  String get supplyChainMapSection => 'Lokasyon ng mga Magsasaka';

  @override
  String get supplyChainRefresh => 'I-refresh';

  @override
  String get supplyChainAllMapped =>
      'Ang lahat ng miyembro ay may nakatakdang lokasyon ng bukid.';

  @override
  String get supplyChainAllSubmitted =>
      'Naisumite na ang lahat ng ani sa kooperatiba.';

  @override
  String get priceLiveRates => 'Live Market Rates';

  @override
  String get priceMarketTrends => 'Mga Trend sa Market';

  @override
  String get priceAddNew => 'Magdagdag ng Presyo';

  @override
  String get priceOfflineWarning =>
      'Hindi pinapayagang mag-update ng presyo habang offline.';

  @override
  String get broadcastCompose => 'Bumuo ng Mensahe';

  @override
  String get broadcastUseTemplate => 'Gumamit ng Template';

  @override
  String get broadcastPreview => 'Preview';

  @override
  String get broadcastRecent => 'Mga Huling Broadcast';

  @override
  String get broadcastTitle => 'Mga Anunsyo sa Broadcast';

  @override
  String get broadcastSchedule => 'I-schedule';

  @override
  String get broadcastScheduleSub => 'Magpadala sa ibang oras';

  @override
  String get buyerNavBrowse => 'Mamili';

  @override
  String get buyerNavOrders => 'Mga Order';

  @override
  String get buyerNavPrices => 'Presyo';

  @override
  String get buyerNavAccount => 'Akawnt';

  @override
  String get buyerBrowseTitle => 'Palengke';

  @override
  String get buyerBrowseSubtitle => 'Sariwang ani mula sa mga magsasaka ng SP3';

  @override
  String get buyerBrowseSearchHint => 'Maghanap ng pananim o uri';

  @override
  String get buyerBrowseEmptyTitle => 'Tahimik pa ang palengke';

  @override
  String get buyerBrowseEmptyBody =>
      'Bumalik-balik para sa mga bagong listahan mula sa SP3.';

  @override
  String get buyerBrowseNoResultsTitle => 'Walang tumutugmang listahan';

  @override
  String get buyerBrowseNoResultsBody =>
      'Subukan ang ibang salita o kategorya.';

  @override
  String get buyerBrowseSoldOut => 'Naubos Na';

  @override
  String get buyerBrowseLowStock => 'Paubos Na';

  @override
  String get buyerBrowseOrderNow => 'Umorder Ngayon';

  @override
  String get buyerBrowseAvailableSuffix => 'natitira';

  @override
  String get buyerBrowseAboveMarketRange =>
      'Presyo laban sa karaniwang market rate';

  @override
  String get dashboardAllClearTitle => 'Maayos ang Lahat';

  @override
  String get dashboardAllClearMessage =>
      'Walang mahalagang bagay ngayon. Magpatuloy sa mahusay na gawain!';

  @override
  String get dashboardQuickActions => 'Mabilisang Aksyon';

  @override
  String get quickActionRecordHarvest => 'Itala ang Ani';

  @override
  String get quickActionCreateListing => 'Gumawa ng Listahan';

  @override
  String get quickActionCheckPrices => 'Tingnan ang Presyo';

  @override
  String get purchaseSummary => 'Buod ng Bili';

  @override
  String get recentActivity => 'Kamakailang Aktibidad';

  @override
  String get account => 'Akawnt';

  @override
  String get buyerDefaultName => 'Buyer';

  @override
  String get statOrders => 'Mga Order';

  @override
  String get statCompleted => 'Nakompleto';

  @override
  String get statSpent => 'Nagastos';

  @override
  String get buyerNoOrdersTitle => 'Wala pang order';

  @override
  String get buyerNoOrdersSubtitle =>
      'Simulan ang pag-browse sa marketplace para maglagay ng unang order.';

  @override
  String get browseMarketplace => 'Tingnan ang Marketplace';

  @override
  String get buyerOrdersTitle => 'Aking mga Order';

  @override
  String buyerOrdersTabPending(int count) {
    return 'Naghihintay ($count)';
  }

  @override
  String buyerOrdersTabApproved(int count) {
    return 'Aprubado ($count)';
  }

  @override
  String buyerOrdersTabCompleted(int count) {
    return 'Tapos na ($count)';
  }

  @override
  String buyerOrdersTabCancelled(int count) {
    return 'Kinansela ($count)';
  }

  @override
  String get buyerOrdersEmptyPending => 'Walang naghihintay na order';

  @override
  String get buyerOrdersEmptyApproved => 'Wala pang aprubadong order';

  @override
  String get buyerOrdersEmptyCompleted => 'Wala pang tapos na order';

  @override
  String get buyerOrdersEmptyCancelled => 'Walang kinanselang order';

  @override
  String get buyerOrdersPickupBannerTitle => 'Handa nang Kunin ang Order!';

  @override
  String buyerOrdersPickupBannerBody(int count, String cooperative) {
    return 'May $count aprubadong order kang hinihintay kunin sa $cooperative.';
  }

  @override
  String get buyerOrdersQuantityLabel => 'Dami';

  @override
  String get buyerOrdersTotalLabel => 'Kabuuang Halaga';

  @override
  String buyerOrdersCancelledOn(String date) {
    return 'Kinansela noong $date';
  }

  @override
  String get buyerOrdersViewPickupDetails => 'Tingnan ang Detalye ng Pickup';

  @override
  String get buyerOrdersReorder => 'Mag-order Muli';

  @override
  String get buyerOrdersBrowseAgain => 'Mamili Muli';

  @override
  String get buyerOrdersAwaitingReview =>
      'Hinihintay ang pagsusuri ng kooperatiba';

  @override
  String get buyerNotifMenuMarkAllRead => 'Markahan lahat bilang nabasa';

  @override
  String get buyerNotifMenuClearAll => 'Burahin lahat';

  @override
  String get buyerNotifFilterAll => 'Lahat';

  @override
  String get buyerNotifFilterListings => 'Mga Listing';

  @override
  String get buyerNotifEmptyTitle => 'Walang notification';

  @override
  String get buyerNotifEmptyBody =>
      'Makikita mo rito ang mga update sa order at marketplace.';

  @override
  String get buyerNotifClearDialogTitle => 'Burahin Lahat ng Notification?';

  @override
  String get buyerNotifClearDialogMessage => 'Hindi na ito maibabalik.';

  @override
  String get buyerNotifDialogClearAll => 'Burahin Lahat';

  @override
  String buyerNotifTimeMinutesAgo(int count) {
    return '$count minuto ang nakalipas';
  }

  @override
  String buyerNotifTimeHoursAgo(int count) {
    return '$count oras ang nakalipas';
  }

  @override
  String get buyerNotifTimeYesterday => 'Kahapon';

  @override
  String buyerNotifTimeDaysAgo(int count) {
    return '$count araw ang nakalipas';
  }

  @override
  String get buyerActivityTitle => 'Kamakailang Aktibidad';

  @override
  String get buyerActivityViewAll => 'Tingnan Lahat';

  @override
  String get buyerActivityEmpty => 'Walang kamakailang aktibidad';

  @override
  String get buyerPriceTitle => 'Presyo sa Merkado';

  @override
  String get buyerPriceSearchLabel => 'Maghanap';

  @override
  String get buyerPriceSearchHint => 'Maghanap ng pananim...';

  @override
  String get buyerPriceFilterAll => 'Lahat';

  @override
  String get buyerPriceTypeSp3 => 'Presyo ng Cooperative Market';

  @override
  String get buyerPriceTypeMarketRef => 'Presyo ng Public Market';

  @override
  String get buyerPriceEmptyTitle => 'Wala pang datos ng presyo';

  @override
  String get buyerPriceEmptyBody =>
      'Lalabas dito ang datos ng presyo kapag nairehistro na ng SP3 Cooperative ang market rate ng isang pananim.';

  @override
  String get buyerPriceNoResultsTitle =>
      'Walang pananim na tumutugma sa iyong paghahanap o filter';

  @override
  String get buyerPriceClearFilters => 'I-clear ang mga filter';

  @override
  String get buyerPriceListedTag => 'Available ngayon sa marketplace';

  @override
  String get buyerPriceNotListedTag => 'Hindi kasalukuyang nakalista';

  @override
  String get buyerPriceNoTrendHistory =>
      'Hindi pa sapat ang history para sa trend chart';

  @override
  String get buyerPriceStatHigh => 'Pinakamataas';

  @override
  String get buyerPriceStatLow => 'Pinakamababa';

  @override
  String get buyerPriceStatCurrent => 'Kasalukuyan';

  @override
  String get buyerPriceFilterPanelTitle => 'I-filter ang Presyo sa Merkado';

  @override
  String get buyerPriceFilterPanelSubtitle =>
      'I-refine ang listahan ayon sa kategorya o pananim';

  @override
  String get buyerPriceFilterCategoryLabel => 'KATEGORYA NG PANANIM';

  @override
  String get buyerPriceFilterCropLabel => 'PANANIM';

  @override
  String get buyerPriceResetAll => 'I-reset Lahat';

  @override
  String get buyerPriceApplyFilters => 'I-apply ang mga Filter';

  @override
  String get buyerOrdersStatusPending => 'HINIHINTAY SURIIN';

  @override
  String get buyerOrdersStatusApproved => 'APRUBADO';

  @override
  String get buyerOrdersStatusCompleted => 'TAPOS NA';

  @override
  String get buyerOrdersStatusCancelled => 'KINANSELA';

  @override
  String get buyerActivityFilterProfile => 'Profile';

  @override
  String get buyerActivityOrderApproved => 'Inaprubahan ang Order';

  @override
  String get buyerActivityOrderCompleted => 'Tapos na ang Order';

  @override
  String get buyerActivityOrderCancelled => 'Kinansela ang Order';

  @override
  String get buyerActivityOrderUpdated => 'Na-update ang Order';

  @override
  String get buyerActivityStatusCancelled => 'Kinansela';

  @override
  String get buyerActivityAllEmptyTitle => 'Wala pang aktibidad';

  @override
  String get buyerActivityAllEmptyBody =>
      'Makikita rito ang mga order na inilagay mo at mga pagbabago sa iyong profile.';

  @override
  String get buyerCartTitle => 'Aking Cart';

  @override
  String get buyerCartEmptyTitle => 'Walang laman ang iyong cart';

  @override
  String get buyerCartEmptyBody =>
      'Magdagdag ng ani mula sa marketplace — puwede kang mag-ipon ng maraming item at mag-checkout nang sabay.';

  @override
  String buyerCartPlacingOrder(int index, int total) {
    return 'Inilalagay ang order $index ng $total';
  }

  @override
  String buyerCartItemCount(int count) {
    return '$count item';
  }

  @override
  String buyerCartItemsFrom(int count, String cooperative) {
    return '$count item mula sa $cooperative';
  }

  @override
  String get buyerCartProceedCheckout => 'Magpatuloy sa Checkout';

  @override
  String buyerCartAdjustedRemoved(String name) {
    return 'Hindi na available ang $name kaya inalis ito sa iyong cart.';
  }

  @override
  String buyerCartAdjustedReduced(String name, String qty) {
    return 'Binawasan ang $name sa ${qty}kg — iyon na lang ang natitira.';
  }

  @override
  String get buyerCartStockChangedTitle => 'Na-update ang iyong cart';

  @override
  String get buyerCartStockChangedBody =>
      'Nagbago ang stock mula nang idagdag ang mga item na ito:';

  @override
  String get buyerCartReviewCart => 'Suriin ang Cart';

  @override
  String get buyerCartConfirmOrderTitle => 'Kumpirmahin ang Order';

  @override
  String get buyerCartTotalLabel => 'Kabuuan';

  @override
  String buyerCartPickupNotice(String location) {
    return 'Kunin sa $location. Walang delivery — kailangan mong mag-ayos ng sariling transportasyon.';
  }

  @override
  String get buyerCartConfirm => 'Kumpirmahin';

  @override
  String get photoUploadFailed => 'Hindi na-upload ang larawan. Subukan muli.';

  @override
  String get fullNameEmpty => 'Kailangan ang buong pangalan.';

  @override
  String get profileUpdated => 'Na-update ang profile.';

  @override
  String get saveChangesFailed =>
      'Hindi ma-save ang mga pagbabago. Subukan muli.';

  @override
  String get changePhoto => 'Palitan ang Larawan';

  @override
  String get personalInformation => 'Personal na Impormasyon';

  @override
  String get updatePasswordSubtitle => 'I-update ang password ng account';

  @override
  String get aboutSagana => 'Tungkol sa SAGANA';

  @override
  String get aboutSaganaBody =>
      'Tinutulungan ng SAGANA ang mga buyer na makipag-ugnayan sa mga pinagkakatiwalaang magsasaka ng SP3 at pamahalaan ang kanilang mga pagbili sa isang lugar.';

  @override
  String get adminAboutSaganaBody =>
      'Tinutulungan ng SAGANA ang mga admin ng kooperatiba na pamahalaan ang mga miyembro, listahan sa marketplace, pautang, imbentaryo, at ulat sa iisang lugar.';

  @override
  String get contactSp3 => 'Makipag-ugnayan sa SP3';

  @override
  String get contactSp3Body =>
      'Para sa mga tanong tungkol sa account, order, o bayad, pumunta sa opisina ng kooperatiba o makipag-ugnayan sa inyong coordinator.';

  @override
  String get privacyPolicy => 'Patakaran sa Privacy';

  @override
  String get privacyPolicyBody =>
      'Ang iyong account, detalye ng order, at impormasyon sa pakikipag-ugnayan ay secure at ma-access lamang ng awtorisadong tauhan ng kooperatiba.';

  @override
  String get termsOfUse => 'Mga Tuntunin ng Paggamit';

  @override
  String get termsOfUseBody =>
      'Sa paggamit ng SAGANA, sumasang-ayon kang gumamit ng platform nang responsable at sundin ang mga patakaran ng kooperatiba.';

  @override
  String get logOut => 'Mag-log Out';

  @override
  String buyerListingAddedToCart(String name) {
    return 'Naidagdag sa cart — $name';
  }

  @override
  String get buyerListingViewCart => 'Tingnan ang Cart';

  @override
  String get buyerListingNotAvailable =>
      'Hindi na available ang listing na ito.';

  @override
  String get buyerListingSp3Badge => '✓ SP3 Cooperative';

  @override
  String get buyerListingBatchNo => 'Blg. ng Batch';

  @override
  String get buyerListingHarvestDate => 'Petsa ng Ani';

  @override
  String get buyerListingAvailable => 'Natitira';

  @override
  String get buyerListingCategory => 'Kategorya';

  @override
  String get buyerListingSellingPrice => 'Presyo ng Pagbebenta';

  @override
  String get buyerListingWithinRange => 'Nasa saklaw ng merkado';

  @override
  String get buyerListingAboveRange => 'Higit sa saklaw ng merkado';

  @override
  String buyerListingMarketRate(String price) {
    return 'Presyo sa Merkado: ₱$price/kg';
  }

  @override
  String get buyerListingMoreFromSp3 => 'Iba pa mula sa SP3';

  @override
  String get buyerListingAddToCart => 'Idagdag sa Cart';

  @override
  String buyerListingPlaceOrder(String total) {
    return 'Mag-order — ₱$total';
  }

  @override
  String get buyerListingOrderQty => 'Dami ng Order (kg)';

  @override
  String buyerListingMaxAvailable(String kg) {
    return 'Max: $kg kg ang natitira';
  }

  @override
  String get buyerListingPickupLocation => '📍 Lokasyon ng Pickup';

  @override
  String get buyerListingNoDelivery =>
      'Walang delivery. Kailangan mag-ayos ng sariling transportasyon ang buyer.';

  @override
  String get buyerPricePerKg => 'Presyo bawat kg';

  @override
  String get buyerHarvestedToday => 'Inani ngayon';

  @override
  String get buyerHarvestedYesterday => 'Inani kahapon';

  @override
  String buyerHarvestedDaysAgo(int count) {
    return 'Inani $count araw na ang nakalipas';
  }

  @override
  String buyerOrderDetailTitle(String ref) {
    return 'Order #$ref';
  }

  @override
  String get buyerOrderDetailNotFound => 'Hindi nahanap ang order.';

  @override
  String get buyerOrderDetailReadyPickup => 'Handa nang Kunin';

  @override
  String get buyerOrderDetailPickedUp => 'Nakuha na';

  @override
  String get buyerOrderDetailCancelledStatus => 'Kinansela ang order';

  @override
  String buyerOrderDetailMsgApproved(String cooperative) {
    return 'Inaprubahan na ang iyong order ng $cooperative. Makipag-ugnayan sa SP3 para sa iskedyul ng pickup.';
  }

  @override
  String buyerOrderDetailMsgPending(String cooperative) {
    return 'Hinihintay pa ang pagsusuri ng iyong order ng $cooperative. Aabisuhan ka kapag naaprubahan na.';
  }

  @override
  String get buyerOrderDetailMsgCompleted =>
      'Nakuha na ang order na ito. Salamat sa pagsuporta sa mga magsasaka ng SP3!';

  @override
  String get buyerOrderDetailMsgCancelled =>
      'Kinansela na ang order na ito at hindi na aktibo.';

  @override
  String get buyerOrderDetailContactCoop =>
      'Makipag-ugnayan sa SP3 Cooperative';

  @override
  String get buyerOrderDetailComingSoon =>
      'Malapit nang available ang numero ng SP3.';

  @override
  String get buyerOrderDetailStepPlaced => 'Inilagay ang Order';

  @override
  String get buyerOrderDetailStepPendingReview => 'Hinihintay Suriin';

  @override
  String get buyerOrderDetailStepApproved => 'Aprubado';

  @override
  String get buyerOrderDetailStepCompleted => 'Tapos na';

  @override
  String get buyerOrderDetailPendingTimestamp => 'Hinihintay';

  @override
  String get buyerOrderDetailJourney => 'Paglalakbay ng Order';

  @override
  String get buyerOrderDetailBatchRef => 'Reference ng Batch';

  @override
  String get buyerOrderDetailFreshness => 'Sariwa';

  @override
  String get buyerOrderDetailSummary => 'Buod ng Order';

  @override
  String get buyerOrderDetailReferenceLabel => 'SANGGUNIAN';

  @override
  String get buyerOrderDetailDateLabel => 'PETSA NG ORDER';

  @override
  String get buyerOrderDetailPaymentInfo => 'IMPORMASYON SA BAYAD';

  @override
  String get buyerOrderDetailPaymentBody =>
      'Kokolektahin ang bayad para sa order na ito sa oras ng pickup sa kooperatiba. Tumatanggap ang SP3 ng cash payment sa pagkuha.';

  @override
  String get buyerOrderDetailPickupLocationTitle => 'Lokasyon ng Pickup';

  @override
  String get buyerOrderDetailBodSchedule => 'Iskedyul ng BOD Meeting';

  @override
  String get buyerOrderDetailBodBody =>
      'Tuwing unang Sabado ng buwan — puwedeng ayusin ang bayad at pickup sa meeting na ito.';

  @override
  String get buyerOrderDetailNeedHelp => 'Kailangan ng tulong sa order na ito?';

  @override
  String get buyerOrderDetailSupportBody =>
      'Direktang makipag-ugnayan sa SP3 Agriculture Cooperative para sa tulong.';

  @override
  String get buyerOrderDetailCallCoop => 'Tawagan ang SP3 Cooperative';

  @override
  String get buyerOrderDetailBrowseMore => 'Tingnan pa ang Iba Pang Produkto';

  @override
  String get buyerOrderSuccessTitle => 'Nailagay ang Order!';

  @override
  String get buyerOrderSuccessSubtitle =>
      'Susuriin ng SP3 Agriculture Cooperative ang iyong order sa lalong madaling panahon.';

  @override
  String get buyerOrderSuccessViewOrders => 'Tingnan ang Aking mga Order';

  @override
  String get buyerOrderSuccessContinueShopping => 'Magpatuloy sa Pamimili';

  @override
  String buyerCheckoutResultPartialTitle(int succeeded, int total) {
    return '$succeeded sa $total Item ang Na-order';
  }

  @override
  String get buyerCheckoutResultPartialBody =>
      'May mga item na hindi na-order — tingnan ang detalye sa ibaba.';

  @override
  String get buyerCheckoutResultOrderedLabel => 'NA-ORDER';

  @override
  String get buyerCheckoutResultFailedLabel => 'HINDI NA-ORDER';

  @override
  String buyerMemberSince(String date) {
    return 'Miyembro simula $date';
  }

  @override
  String get brandingTagline =>
      'Streamlined Agricultural Gateway for\nAgribusiness, Networking, and Analytics';

  @override
  String get brandingDevelopedBy =>
      'Ginawa ng Marinduque State University — BSIT';

  @override
  String get brandingPartner => 'Kasosyo: SP3 Agriculture Cooperative';

  @override
  String get registerFullNameHintFarmer =>
      'Gaya ng nakatala sa mga rekord ng kooperatiba';

  @override
  String get registerFullNameHintBuyer => 'Ang buo mong pangalan';

  @override
  String get registerEnterFullName => 'Ilagay ang buo mong pangalan';

  @override
  String get registerCheckingName =>
      'Sandali lang — sinusuri ang pangalang ito…';

  @override
  String get registerCheckingRegistry =>
      'Sandali lang — sinusuri ang rehistro ng miyembro ng SP3…';

  @override
  String get registerChooseAvailableUsername =>
      'Pumili ng username na available.';

  @override
  String get registerNameTakenTitle => 'Nakarehistro Na ang Pangalan';

  @override
  String get registerNameAlreadyRegistered =>
      'Nakarehistro na ang buong pangalang ito. Mag-log in na lang, o makipag-ugnayan sa SP3 Agriculture Cooperative kung sa tingin mo ay may pagkakamali.';

  @override
  String get registerRegistryMatchMessage =>
      'Natagpuan ang iyong pangalan sa opisyal na rehistro ng miyembro ng SP3. Awtomatikong itinalaga ang iyong SAGANA username.';

  @override
  String get registerRegistryNoMatchMessage =>
      'Hindi natagpuan ang iyong pangalan sa rehistro ng miyembro ng SP3. Maaari ka pa ring magrehistro — susuriin ng SP3 Cooperative ang iyong aplikasyon.';

  @override
  String get registerPhoneOptional => 'Numero ng Telepono (opsyonal)';

  @override
  String get registerInvalidPhone =>
      'Maglagay ng wastong PH number (09XXXXXXXXX)';

  @override
  String get registerEmailOptional => 'Email (opsyonal)';

  @override
  String get registerInvalidEmail => 'Maglagay ng wastong email address';

  @override
  String get registerEmailTaken =>
      'Ginagamit na ng ibang account ang email address na ito.';

  @override
  String get registerPurokOptional => 'Purok (opsyonal)';

  @override
  String get registerDob => 'Petsa ng Kapanganakan *';

  @override
  String get registerDobSelect => 'Piliin ang iyong petsa ng kapanganakan';

  @override
  String get registerDobHelp => 'Kailangang 18 taong gulang pataas para sumali';

  @override
  String get registerGenderOptional => 'Kasarian (opsyonal)';

  @override
  String get registerTitle => 'Gumawa ng Account';

  @override
  String get registerSubtitle => 'Sumali sa network ng kooperatiba ng SP3';

  @override
  String get registerRoleFarmer => 'Magsasaka';

  @override
  String get registerRoleBuyer => 'Mamimili';

  @override
  String get registerUsernameLabel => 'Pumili ng Username *';

  @override
  String get registerUsernameHint => 'hal. juandelacruz';

  @override
  String get registerUsernameRequired => 'Pumili ng username';

  @override
  String get registerUsernameTooShort =>
      'Dapat hindi bababa sa 3 karakter ang username';

  @override
  String get registerUsernameTaken => 'Nagamit na ang username na ito';

  @override
  String get registerUsernameAvailable => 'Available ang username!';

  @override
  String get registerUsernameNotAvailable => 'Nagamit na ang username na iyan.';

  @override
  String get registerPasswordLabel => 'Password *';

  @override
  String get registerPasswordTooShort =>
      'Dapat hindi bababa sa 8 karakter ang password';

  @override
  String get registerConfirmPasswordLabel => 'Kumpirmahin ang Password *';

  @override
  String get registerPasswordMismatch => 'Hindi magkatugma ang mga password';

  @override
  String get registerWelcomeOfficialTitle => 'Maligayang pagdating sa SP3! 🌾';

  @override
  String get registerAccountCreatedTitle => 'Nagawa ang Account';

  @override
  String registerWelcomeOfficialMessage(String username) {
    return 'Maligayang pagdating, opisyal na miyembro ng SP3!\n\nAng iyong SAGANA username ay:\n$username\n\nPakitandaan ang username na ito para mag-log in.';
  }

  @override
  String registerFarmerCreatedMessage(String username) {
    return 'Matagumpay na nagawa ang account.\n\nAng iyong username ay:\n$username\n\nNakabinbin ang iyong pagiging miyembro para sa pagpapatunay ng SP3 Agriculture Cooperative. Aabisuhan ka pagkatapos maaprubahan.';
  }

  @override
  String registerBuyerCreatedMessage(String username) {
    return 'Matagumpay na nagawa ang account.\n\nMaaari ka nang mag-log in gamit ang iyong username:\n$username';
  }

  @override
  String get registerGoToLogin => 'Pumunta sa Login';

  @override
  String get registerAlreadyHaveAccount => 'May account ka na? ';

  @override
  String get registerSignIn => 'Mag-sign In';

  @override
  String get registerOfficialMemberFound =>
      'Natagpuan ang Opisyal na Miyembro ng SP3 ✓';

  @override
  String get registerNotInRegistry => 'Wala sa Rehistro ng SP3';

  @override
  String get registerYourUsernameLabel => 'Ang Iyong SAGANA Username';

  @override
  String get registerUsernameAutoGenerated =>
      'Awtomatikong nabuo · Hindi na mababago';

  @override
  String get registerGenderMale => 'Lalaki';

  @override
  String get registerGenderFemale => 'Babae';

  @override
  String get registerGenderPreferNotToSay => 'Mas gustong hindi sabihin';

  @override
  String issueLoanCapitalIneligible(String current, String minimum) {
    return 'Kontribusyon sa kapital ₱$current — mas mababa sa ₱$minimum na minimum na kailangan para makautang.';
  }

  @override
  String issueLoanCapitalBlocked(String minimum) {
    return 'Hindi pa naaabot ng miyembrong ito ang ₱$minimum na minimum na kontribusyon sa kapital para mabigyan ng loan.';
  }

  @override
  String get addMemberTitle => 'Magdagdag ng Bagong Miyembro';

  @override
  String get addMemberSave => 'I-save';

  @override
  String get addMemberAdminNoticeTitle => 'Paalala ng Admin';

  @override
  String get addMemberAdminNoticeBody =>
      'Gagawin ang miyembro nang may aktibong katayuan at maaari nang mag-log in agad gamit ang mga kredensyal sa ibaba.';

  @override
  String get addMemberSectionCredentials => 'Kredensyal ng Account';

  @override
  String get addMemberUsernameLabel => 'SAGANA Username';

  @override
  String get addMemberUsernameRequired => 'Kailangan ang username';

  @override
  String get addMemberUsernameHelp =>
      'Awtomatikong nabuo — ang mga Farmer account na ginawa ng Admin ay para lamang sa opisyal na miyembro ng SP3.';

  @override
  String get addMemberPasswordLabel => 'Pansamantalang Password';

  @override
  String get addMemberPasswordRequired => 'Kailangan ang password';

  @override
  String get addMemberPasswordTooShort => 'Minimum 8 na karakter';

  @override
  String get addMemberSectionPersonal => 'Personal na Impormasyon';

  @override
  String get addMemberFullNameLabel => 'Buong Pangalan';

  @override
  String get addMemberFullNameHint =>
      'Gaya ng nakatala sa mga rekord ng kooperatiba';

  @override
  String get addMemberFullNameRequired => 'Kailangan ang buong pangalan';

  @override
  String get addMemberRegistryMatch =>
      'Natugma sa rehistro ng miyembro ng SP3 — awtomatikong napunan ang Purok at telepono.';

  @override
  String get addMemberRegistryNoMatch =>
      'Wala sa rehistro ng miyembro ng SP3. Maaari mo pa ring gawin ang account.';

  @override
  String get addMemberPhoneLabel => 'Numero ng Telepono (opsyonal)';

  @override
  String get addMemberPhoneInvalid => 'Hindi wastong PH number';

  @override
  String get addMemberPurokLabel => 'Purok';

  @override
  String get addMemberSelectHint => 'Pumili';

  @override
  String get addMemberDobLabel => 'Petsa ng Kapanganakan (18+)';

  @override
  String get addMemberGenderLabel => 'Kasarian';

  @override
  String get addMemberSectionMembership => 'Pagiging Miyembro ng Kooperatiba';

  @override
  String get addMemberMemberIdLabel => 'Member ID';

  @override
  String get addMemberMemberIdHelp =>
      'Awtomatikong nabuo (SP3-taon-sunod-sunod) — itinatalaga sa pag-save, hindi na mababago. Iba ito sa username sa pag-log in.';

  @override
  String get addMemberShareValueLabel => 'Halaga ng Share (₱)';

  @override
  String get addMemberInitialContributionLabel => 'Paunang Kontribusyon (₱)';

  @override
  String get addMemberInvalidNumber => 'Hindi wastong numero';

  @override
  String get addMemberContributionHelp =>
      'Opsyonal na paunang kapital. Umaabot ang mga miyembro sa ₱2,000 na taunang share; ₱100/buwan minimum. Ang karagdagang bayad ay itatala mamaya mula sa rekord ng miyembro.';

  @override
  String get addMemberSectionCrops => 'Paunang mga Pananim';

  @override
  String get addMemberAddCrop => 'Magdagdag ng Pananim';

  @override
  String get addMemberNoCropsYet => 'Wala pang naidagdag na pananim';

  @override
  String get addMemberSelectCropTitle => 'Pumili ng Pananim';

  @override
  String get addMemberNoCatalogCrops =>
      'Wala pang aktibong pananim sa Crop Management.';

  @override
  String get addMemberAllCropsAdded =>
      'Naidagdag na lahat ng pananim sa katalogo.';

  @override
  String get addMemberClose => 'Isara';

  @override
  String get addMemberSelectPurok => 'Pumili ng purok.';

  @override
  String get addMemberAgeRequirement =>
      'Dapat 18 taong gulang pataas ang miyembro.';

  @override
  String addMemberCreatedSuccess(String name) {
    return 'Matagumpay na naidagdag si $name.';
  }

  @override
  String addMemberPartialIssue(String step, String message) {
    return 'May isyu sa hakbang na $step: $message';
  }

  @override
  String get addMemberCreateFailed =>
      'Hindi nagawa ang miyembro. Pakisubukang muli.';

  @override
  String get addMemberUsernameTakenRetry =>
      'Nakuha na ang username na iyon — may bago nang nabuo. Pakisubukang muli.';

  @override
  String get addMemberOffline => 'Offline — Hindi Magawa ang Account';

  @override
  String get addMemberCreating => 'Ginagawa ang Account...';

  @override
  String get addMemberCreateButton => 'Gumawa ng Farmer Account';

  @override
  String get pendingNavHome => 'Home';

  @override
  String get pendingNavUpdates => 'Update';

  @override
  String get pendingNavHelp => 'Tulong';

  @override
  String get pendingNavProfile => 'Profile';

  @override
  String get pendingHomeTitle => 'SP3 Cooperative';

  @override
  String pendingWelcome(String name) {
    return 'Maligayang pagdating, $name!';
  }

  @override
  String get pendingBannerApproved =>
      'Naaprubahan na ang iyong pagiging miyembro. Pindutin ang Continue sa ibaba para i-activate ang iyong access bilang magsasaka.';

  @override
  String get pendingBannerRejected =>
      'Hindi naaprubahan ang iyong aplikasyon. Suriin ang iyong mga detalye sa ibaba at magsumite muli kapag handa na.';

  @override
  String get pendingBannerDraft =>
      'Handa na ang iyong account. Suriin ang mga detalye sa ibaba, pagkatapos ay ipadala ang iyong aplikasyon sa kooperatiba.';

  @override
  String get pendingBannerPending =>
      'Natanggap na ang iyong aplikasyon at kasalukuyang sinusuri ng administrasyon ng kooperatiba. Aabisuhan ka rito kapag may desisyon na.';

  @override
  String get pendingOfflineBanner =>
      'Offline ka — hindi darating ang mga update sa iyong aplikasyon hangga\'t hindi ka nakakonekta muli.';

  @override
  String get pendingApplicationStatusTitle => 'Katayuan ng Aplikasyon';

  @override
  String get pendingBadgeApproved => 'NAAPRUBAHAN';

  @override
  String get pendingBadgeRejected => 'HINDI NAAPRUBAHAN';

  @override
  String get pendingBadgeDraft => 'HINDI PA NAISUSUMITE';

  @override
  String get pendingBadgePending => 'SINUSURI';

  @override
  String pendingYourUsername(String username) {
    return 'Ang iyong username: $username';
  }

  @override
  String pendingApprovedMessage(String name) {
    return 'Maligayang pagdating sa SP3 Agriculture Cooperative, $name! Pindutin ang Continue para kumpirmahin at i-unlock ang iyong mga feature bilang magsasaka.';
  }

  @override
  String get pendingContinueButton => 'Magpatuloy sa SAGANA';

  @override
  String get pendingRejectedReasonTitle => 'Dahilan mula sa kooperatiba';

  @override
  String get pendingNoReasonProvided => 'Walang naibigay na dahilan.';

  @override
  String pendingAttemptsRemaining(int count) {
    return 'Suriin at i-update ang iyong mga detalye, pagkatapos ay magsumite muli. Natitirang pagsubok: $count ng 3.';
  }

  @override
  String get pendingAttemptsExhausted =>
      'Nagamit mo na ang lahat ng 3 pagkakataon sa pagsumite ng aplikasyon. Bisitahin ang tanggapan ng SP3 Cooperative para magpatuloy.';

  @override
  String get pendingReviewEditButton => 'Suriin at I-edit ang mga Detalye';

  @override
  String get pendingResubmitButton => 'Isumite Muli ang Aplikasyon';

  @override
  String get pendingDraftMessage =>
      'Hindi pa naipapadala ang iyong aplikasyon. Tiyaking tama ang mga detalye sa ibaba, pagkatapos ay isumite sa kooperatiba para sa pagsusuri.';

  @override
  String get pendingSubmitButton => 'Isumite ang Aplikasyon';

  @override
  String get pendingStepSubmitted => 'Naisumite ang Aplikasyon';

  @override
  String get pendingStepSubmittedSub =>
      'Naipadala sa kooperatiba para sa pagsusuri';

  @override
  String get pendingStepReview => 'Sinusuri';

  @override
  String get pendingStepReviewSub =>
      'Sinusuri ng SP3 Admin ang iyong aplikasyon';

  @override
  String get pendingStepDecision => 'Desisyon';

  @override
  String get pendingStepDecisionSub =>
      'Aabisuhan ka rito — naaprubahan man o hindi';

  @override
  String get pendingContactAddress => 'Barangay Payanas, Torrijos, Marinduque';

  @override
  String get pendingContactBod => 'Pulong ng BOD: Tuwing unang Sabado ng buwan';

  @override
  String get pendingContactMembers => '52 rehistradong miyembro ng kooperatiba';

  @override
  String pendingSubmittedToast(int attempt) {
    return 'Naisumite ang aplikasyon (pagsubok $attempt ng 3).';
  }

  @override
  String get pendingDetailsUpdatedToast => 'Na-update ang mga detalye.';

  @override
  String get pendingNotificationsTitle => 'Mga Notification';

  @override
  String get pendingNoNotifications => 'Wala pang notification';

  @override
  String get pendingNoNotificationsSub =>
      'Aabisuhan ka rito kapag na-update ang\naplikasyon ng iyong pagiging miyembro.';

  @override
  String get pendingHelpTitle => 'Tulong at Mga Tanong';

  @override
  String get pendingHelpIntro =>
      'Kasalukuyang sinusuri ang iyong aplikasyon. Narito ang mga sagot sa karaniwang tanong habang naghihintay ka.';

  @override
  String get pendingFaq1Q =>
      'Bakit hindi ko ma-access ang Harvest, Loans, o Marketplace?';

  @override
  String get pendingFaq1A =>
      'Ang mga feature na ito ay para lamang sa opisyal na miyembro ng SP3 cooperative. Awtomatiko itong magiging available kapag inaprubahan ng Administrator ang iyong aplikasyon.';

  @override
  String get pendingFaq2Q => 'Gaano katagal ang proseso ng pag-apruba?';

  @override
  String get pendingFaq2A =>
      'Sinusuri ng administrator ng kooperatiba ang mga aplikasyon sa kanilang pagkakataon, karaniwan sa panahon o pagkatapos ng mga pulong ng BOD tuwing unang Sabado ng buwan. Kung mahigit isang buwan nang nakabinbin ang iyong aplikasyon, direktang makipag-ugnayan sa tanggapan ng kooperatiba.';

  @override
  String get pendingFaq3Q =>
      'Aabisuhan ba ako kapag naaprubahan ang aking aplikasyon?';

  @override
  String get pendingFaq3A =>
      'Oo. Makakatanggap ka ng in-app na notification sa sandaling masuri ang iyong aplikasyon. Kung naaprubahan, may lalabas na Continue button sa Home tab — pindutin ito para kumpirmahin at i-unlock ang mga feature bilang magsasaka. Kung hindi naaprubahan, lalabas ang dahilan sa Home tab at maaari mong i-update ang iyong mga detalye at magsumite muli (3 pagkakataon lahat-lahat).';

  @override
  String get pendingFaq4Q => 'Ano ang SP3 Agriculture Cooperative?';

  @override
  String get pendingFaq4A =>
      'Ang SP3 (Samahan ng mga Produktibong Pamilyang Pilipino sa Payanas) ay isang CDA-registered na kooperatibang pang-agrikultura na matatagpuan sa Barangay Payanas, Torrijos, Marinduque. Itinatag ito noong Pebrero 1, 2017 at kasalukuyang naglilingkod sa 52 miyembrong magsasaka.';

  @override
  String get pendingFaq5Q => 'Para saan ang aking SAGANA username?';

  @override
  String get pendingFaq5A =>
      'Ang iyong SAGANA username ay ang permanenteng identifier mo sa pag-log in para sa application na ito. Panatilihin itong ligtas at huwag ibahagi. Kung nakilala kang opisyal na miyembro ng SP3 sa pagpaparehistro, ang iyong username ay may format na SP3-XXXX.';

  @override
  String get pendingFaq6Q => 'Paano ako makikipag-ugnayan sa kooperatiba?';

  @override
  String get pendingFaq6A =>
      'Bisitahin ang tanggapan ng SP3 Cooperative sa Barangay Payanas, Torrijos, Marinduque. Ang mga pulong ng BOD ay ginaganap tuwing unang Sabado ng buwan at bukas sa mga aplikante.';

  @override
  String get pendingProfileTitle => 'Aking Profile';

  @override
  String get pendingVerificationBadge => 'NAKABINBIN ANG BERIPIKASYON';

  @override
  String get pendingAccountInfoTitle => 'Impormasyon ng Account';

  @override
  String get pendingPhoneLabel => 'Telepono';

  @override
  String get pendingNotSet => 'Wala pa';

  @override
  String get pendingPurokLabel => 'Purok';

  @override
  String get pendingLockedFeatures =>
      'Ang Farm Details, Input Loans, Harvest Summary, Expenses, at Cooperative Contributions ay magiging available pagkatapos maaprubahan ang iyong pagiging miyembro.';

  @override
  String get pendingSignOut => 'Mag-sign Out';

  @override
  String get pendingSignOutConfirm =>
      'Sigurado ka bang gusto mong mag-sign out?';

  @override
  String get pendingCancel => 'Kanselahin';

  @override
  String get pendingDetailsTitle => 'Ang Iyong mga Detalye';

  @override
  String get pendingFullNameLabel => 'Buong Pangalan';

  @override
  String get pendingFullNameRequired => 'Ilagay ang iyong buong pangalan';

  @override
  String get pendingPhoneOptionalLabel => 'Numero ng Telepono (opsyonal)';

  @override
  String get pendingPhoneInvalid => 'Hindi wastong PH number';

  @override
  String get pendingEmailOptionalLabel => 'Email (opsyonal)';

  @override
  String get pendingPurokOptionalLabel => 'Purok (opsyonal)';

  @override
  String get pendingDobLabel => 'Petsa ng Kapanganakan (18+)';

  @override
  String get pendingSelectHint => 'Pumili';

  @override
  String get pendingGenderOptionalLabel => 'Kasarian (opsyonal)';

  @override
  String get pendingAgeError => 'Dapat 18 taong gulang pataas.';

  @override
  String get pendingSave => 'I-save';

  @override
  String get createOfficerTitle => 'Magdagdag ng Officer Account';

  @override
  String get createOfficerNotice =>
      'Nakukuha ng Officer ang lahat ng Admin module maliban sa Members tab. Dapat nasa Officer Registry na ang tao.';

  @override
  String get createOfficerSectionOfficer => 'Officer';

  @override
  String get createOfficerFullNameLabel => 'Buong Pangalan';

  @override
  String get createOfficerFullNameHint =>
      'Gaya ng nakatala sa Officer Registry';

  @override
  String get createOfficerFullNameRequired => 'Kailangan ang buong pangalan';

  @override
  String get createOfficerNotInRegistry =>
      'Wala sa Officer Registry ang pangalang ito. Idagdag muna ito sa rehistro.';

  @override
  String get createOfficerAlreadyHasAccount =>
      'May account na ang record na ito sa Officer Registry.';

  @override
  String get createOfficerMatched =>
      'Natugma sa Officer Registry — awtomatikong napunan ang mga detalye.';

  @override
  String get createOfficerEmailLabel => 'Email (opsyonal)';

  @override
  String get createOfficerPhoneLabel => 'Numero ng Telepono (opsyonal)';

  @override
  String get createOfficerPositionLabel => 'Posisyon (opsyonal)';

  @override
  String get createOfficerPositionHint => 'hal. Operations Officer';

  @override
  String get createOfficerEmployeeIdLabel => 'Employee ID';

  @override
  String get createOfficerEmployeeIdHelp =>
      'Awtomatikong nabuo (EMP-###), itinatalaga sa pag-save — hindi na mababago.';

  @override
  String get createOfficerSectionLogin => 'Login';

  @override
  String get createOfficerUsernameLabel => 'SAGANA Username';

  @override
  String get createOfficerUsernameRequired => 'Kailangan ang username';

  @override
  String get createOfficerUsernameHelp =>
      'Awtomatikong nabuo — hindi na mababago.';

  @override
  String get createOfficerPasswordLabel => 'Pansamantalang Password';

  @override
  String get createOfficerPasswordHint => 'Mag-type o pindutin ang AUTO';

  @override
  String get createOfficerPasswordTooShort => 'Minimum 8 na karakter';

  @override
  String get createOfficerWaitForCheck =>
      'Hintayin munang matapos ang pagsusuri ng Officer Registry.';

  @override
  String get createOfficerCreated => 'Nagawa ang Officer account.';

  @override
  String get createOfficerCreating => 'Ginagawa ang account...';

  @override
  String get createOfficerCreateButton => 'Gumawa ng Officer Account';

  @override
  String farmerMgmtRejectDialogTitle(String name) {
    return 'Tanggihan si $name';
  }

  @override
  String get farmerMgmtRejectHint =>
      'Ipaliwanag kung bakit hindi naaprubahan ang aplikasyon. Makikita ito ng aplikante at maaari siyang magsumite muli (3 pagkakataon lahat-lahat).';

  @override
  String get farmerMgmtNext => 'Susunod';

  @override
  String get farmerMgmtConfirmRejectionTitle => 'Kumpirmahin ang Pagtanggi';

  @override
  String farmerMgmtRejectApplicantLine(String name) {
    return 'Aplikante: $name';
  }

  @override
  String get farmerMgmtRejectOutcomeLine =>
      'Resulta: Tinanggihan ang aplikasyon (mananatili ang account nila, walang farmer access)';

  @override
  String farmerMgmtReasonLine(String reason) {
    return 'Dahilan: $reason';
  }

  @override
  String get farmerMgmtRejectResubmitLine =>
      'Maaari nilang suriin ang kanilang mga detalye at magsumite muli.';

  @override
  String get farmerMgmtRejectApplicationAction => 'Tanggihan ang Aplikasyon';

  @override
  String farmerMgmtRejectedToast(String name) {
    return 'Tinanggihan ang aplikasyon ni $name.';
  }

  @override
  String farmerMgmtSuspendDialogTitle(String name) {
    return 'Suspindihin si $name';
  }

  @override
  String get farmerMgmtSuspendHint =>
      'Ipaliwanag kung bakit sinuspinde ang account na ito. Makikita ito ng miyembro at hindi siya makaka-log in hangga\'t hindi na-reactivate.';

  @override
  String get farmerMgmtConfirmSuspensionTitle => 'Kumpirmahin ang Pagsuspinde';

  @override
  String farmerMgmtSuspendMemberLine(String name) {
    return 'Miyembro: $name';
  }

  @override
  String get farmerMgmtSuspendOutcomeLine =>
      'Resulta: Nasuspinde — hindi makakapag-log in';

  @override
  String get farmerMgmtSuspendReactivateLine =>
      'Maaari mo silang i-reactivate anumang oras.';

  @override
  String get farmerMgmtSuspendAccountAction => 'Suspindihin ang Account';

  @override
  String farmerMgmtSuspendedToast(String name) {
    return 'Nasuspinde na si $name.';
  }

  @override
  String get farmerMgmtCancel => 'Kanselahin';

  @override
  String get farmerMgmtBack => 'Bumalik';
}
