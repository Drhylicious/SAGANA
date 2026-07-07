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
  String get navAnalytics => 'Analytics';

  @override
  String get navProfile => 'Profile';

  @override
  String get greetingMorning => 'Magandang Umaga';

  @override
  String get greetingAfternoon => 'Magandang Hapon';

  @override
  String get greetingEvening => 'Magandang Gabi';

  @override
  String get defaultFarmerName => 'Magsasaka';

  @override
  String get offlineBanner =>
      'Offline ka — masi-sync ang mga pagbabago kapag may koneksyon';

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
  String get save => 'I-save';

  @override
  String get saveChanges => 'I-save ang mga Pagbabago';

  @override
  String get saving => 'Sine-save...';

  @override
  String get settingsTitle => 'Mga Setting';

  @override
  String get sectionAccount => 'Account';

  @override
  String get sectionNotifications => 'Mga Notification';

  @override
  String get sectionAppPreferences => 'Mga Kagustuhan sa App';

  @override
  String get sectionDataExport => 'Data Export';

  @override
  String get sectionSupportInfo => 'Suporta at Impormasyon';

  @override
  String get editProfile => 'I-edit ang Profile';

  @override
  String get editProfileSubtitle => 'Pangalan, telepono, sitio';

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
  String get themeLight => 'Light Mode';

  @override
  String get themeDark => 'Dark Mode';

  @override
  String get backgroundSync => 'Background Sync';

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
  String get notifListingApproved => 'Naaprubahan ang Listing';

  @override
  String get notifListingChanges => 'Kailangan ng Pagbabago sa Listing';

  @override
  String get notifLoanReminder => 'Paalala sa Bayad sa Utang';

  @override
  String get notifPriceUpdates => 'Update sa Presyo';

  @override
  String get notifSyncCompleted => 'Tapos na ang Sync';

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
  String get accountCreated => 'Nagawa na ang Account!';

  @override
  String get selectLanguage => 'Pumili ng Wika';

  @override
  String get selectAppearance => 'Pumili ng Itsura';

  @override
  String get adminNavDashboard => 'Dashboard';

  @override
  String get adminNavFarmers => 'Mga Magsasaka';

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
  String get adminUrgentActions => 'Mga Pangangailangan sa Aksyon';

  @override
  String get adminQuickActions => 'Mga Mabilisang Aksyon';

  @override
  String get adminToolsManagement => 'Mga Tool at Pamamahala';

  @override
  String get adminRecentActivity => 'Kamakailang Aktibidad';

  @override
  String get adminGoToLoanPayments => 'Punta sa Mga Bayad sa Utang';

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
  String get loanDashActiveSection => 'Mga Aktibong Pautang';

  @override
  String get loanDashSeeAll => 'Tingnan lahat';

  @override
  String get loanDashNoOverdue => 'Walang overdue na pautang sa ngayon.';

  @override
  String get loanDashNoActive => 'Walang aktibong pautang sa ngayon.';

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
  String get issueLoanOutstandingBalance => 'Natitirang Balanse';

  @override
  String get issueLoanOverdueWarning =>
      'May overdue na pautang ang magsasakang ito.';

  @override
  String get issueLoanStandingUnavailableOffline =>
      'Hindi makuha ang balanse habang offline.';

  @override
  String get issueLoanInputItems => 'Mga Input na Ibinigay';

  @override
  String get issueLoanAddItem => 'Magdagdag ng Input';

  @override
  String get issueLoanNoItemsYet => 'Wala pang naidagdag na item.';

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
  String get farmerMgmtTitle => 'Pamamahala ng Mga Magsasaka';

  @override
  String get farmerMgmtAdd => 'Idagdag';

  @override
  String get adminCoopPerformanceTitle => 'Buod ng Pagganap ng Kooperatiba';

  @override
  String get seeAll => 'Tingnan Lahat';

  @override
  String get priceManagementTitle => 'Pamamahala ng Presyo';

  @override
  String get supplyChainTitle => 'Mapa ng Supply Chain';

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
  String get broadcastTitle => 'Pamagat';

  @override
  String get broadcastSchedule => 'I-schedule';

  @override
  String get broadcastScheduleSub => 'Magpadala sa ibang oras';
}
