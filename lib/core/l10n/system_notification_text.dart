import 'app_localizations.dart';
import 'localized_labels.dart';

/// Localizes known system-generated notices without changing stored messages.
/// Names, amounts, references and user-written reasons remain intact.
String localizedNotificationTitle(AppLocalizations l10n, String raw) {
  if (!l10n.localeName.startsWith('tl')) return raw;
  return switch (raw.toLowerCase()) {
    "account created" => l10n.systemNoticeAccountCreated0,
    "account reactivated" => l10n.systemNoticeAccountReactivated1,
    "account suspended" => l10n.systemNoticeAccountSuspended2,
    "account approved" => l10n.systemNoticeAccountApproved3,
    "account not approved" => l10n.systemNoticeAccountNotApproved4,
    "another distribution" => l10n.systemNoticeAnotherDistribution5,
    "application disapproved" => l10n.systemNoticeApplicationDisapproved6,
    "application not approved" => l10n.systemNoticeApplicationNotApproved7,
    "application submitted" => l10n.systemNoticeApplicationSubmitted8,
    "assistance approved" => l10n.systemNoticeAssistanceApproved9,
    "assistance request not approved" =>
      l10n.systemNoticeAssistanceRequestNotApproved10,
    "bod meeting coming up" => l10n.systemNoticeBODMeetingComingUp11,
    "bod meeting in 3 days" => l10n.systemNoticeBODMeetingInDays12,
    "balik-tangkilik payout recorded" =>
      l10n.systemNoticeBalikTangkilikPayoutRecorded13,
    "benefit distributed" => l10n.systemNoticeBenefitDistributed14,
    "buyer found for your ginger" => l10n.systemNoticeBuyerFoundForYourGinger15,
    "cancellation approved" => l10n.systemNoticeCancellationApproved16,
    "cancellation declined" => l10n.systemNoticeCancellationDeclined17,
    "capital contribution cancelled" =>
      l10n.systemNoticeCapitalContributionCancelled18,
    "capital contribution recorded" =>
      l10n.systemNoticeCapitalContributionRecorded19,
    "changes requested" => l10n.systemNoticeChangesRequested20,
    "cooperative price updated" => l10n.systemNoticeCooperativePriceUpdated21,
    "cooperative purchase confirmed" =>
      l10n.systemNoticeCooperativePurchaseConfirmed22,
    "cooperative purchase offer declined" =>
      l10n.systemNoticeCooperativePurchaseOfferDeclined23,
    "crop request approved" => l10n.systemNoticeCropRequestApproved24,
    "crop request declined" => l10n.systemNoticeCropRequestDeclined25,
    "eligible for another distribution" =>
      l10n.systemNoticeEligibleForAnotherDistribution26,
    "ginger sale completed" => l10n.systemNoticeGingerSaleCompleted27,
    "harvest added to your records" =>
      l10n.systemNoticeHarvestAddedToYourRecords28,
    "harvest return due" => l10n.systemNoticeHarvestReturnDue29,
    "harvest return received" => l10n.systemNoticeHarvestReturnReceived30,
    "join request approved" => l10n.systemNoticeJoinRequestApproved31,
    "join request closed" => l10n.systemNoticeJoinRequestClosed32,
    "listing approved" => l10n.systemNoticeListingApproved33,
    "listing changes approved" => l10n.systemNoticeListingChangesApproved34,
    "listing changes disapproved" =>
      l10n.systemNoticeListingChangesDisapproved35,
    "listing rejected" => l10n.systemNoticeListingRejected36,
    "listing sold out" => l10n.systemNoticeListingSoldOut37,
    "listing status updated" => l10n.systemNoticeListingStatusUpdated38,
    "loan assessment referral" => l10n.systemNoticeLoanAssessmentReferral39,
    "assistance referral" => l10n.systemNoticeAssistanceReferral,
    "loan issued" => l10n.systemNoticeLoanIssued40,
    "loan payment due soon" => l10n.systemNoticeLoanPaymentDueSoon41,
    "loan request disapproved" => l10n.systemNoticeLoanRequestDisapproved42,
    "monthly contribution reminder" =>
      l10n.systemNoticeMonthlyContributionReminder,
    "monthly contribution announcement" =>
      l10n.systemNoticeMonthlyContributionAnnouncement,
    "monthly contribution overdue" =>
      l10n.systemNoticeMonthlyContributionOverdue,
    "market linking cancellation requested" =>
      l10n.systemNoticeMarketLinkingCancellationRequested43,
    "market linking join request approved" =>
      l10n.systemNoticeMarketLinkingJoinRequestApproved44,
    "membership approved" => l10n.systemNoticeMembershipApproved45,
    "new cooperative offer" => l10n.systemNoticeNewCooperativeOffer46,
    "new crop request" => l10n.systemNoticeNewCropRequest47,
    "new join request" => l10n.systemNoticeNewJoinRequest48,
    "new listing submitted" => l10n.systemNoticeNewListingSubmitted49,
    "new market linking request" => l10n.systemNoticeNewMarketLinkingRequest50,
    "new membership application" => l10n.systemNoticeNewMembershipApplication51,
    "new order received" => l10n.systemNoticeNewOrderReceived52,
    "new program enrollment request" =>
      l10n.systemNoticeNewProgramEnrollmentRequest53,
    "new program purchase request" =>
      l10n.systemNoticeNewProgramPurchaseRequest54,
    "new order placed" => l10n.systemNoticeNewOrderPlaced55,
    "order approved" => l10n.systemNoticeOrderApproved56,
    "order cancelled" => l10n.systemNoticeOrderCancelled57,
    "order cancelled — produce unavailable" =>
      l10n.snOrderCancelledProduceUnavailable,
    "order completed" => l10n.systemNoticeOrderCompleted58,
    "order pending review" => l10n.systemNoticeOrderPendingReview59,
    "order rejected" => l10n.systemNoticeOrderRejected60,
    "outcome report returned" => l10n.systemNoticeOutcomeReportReturned61,
    "outcome report pending" => l10n.systemNoticeOutcomeReportPending62,
    "patronage capital reinvested" =>
      l10n.systemNoticePatronageCapitalReinvested63,
    "payment reminder" => l10n.systemNoticePaymentReminder64,
    "payout decision confirmed" => l10n.systemNoticePayoutDecisionConfirmed65,
    "payout decision not approved" =>
      l10n.systemNoticePayoutDecisionNotApproved66,
    "program enrollment declined" =>
      l10n.systemNoticeProgramEnrollmentDeclined67,
    "program outcome: failed" => l10n.systemNoticeProgramOutcomeFailed68,
    "program outcome: thriving" => l10n.systemNoticeProgramOutcomeThriving69,
    "program return settled" => l10n.systemNoticeProgramReturnSettled70,
    "purchase cancelled" => l10n.systemNoticePurchaseCancelled71,
    "purchase confirmed" => l10n.systemNoticePurchaseConfirmed72,
    "received from program" => l10n.systemNoticeReceivedFromProgram73,
    "return due" => l10n.systemNoticeReturnDue74,
    "assistance request" => l10n.snAssistanceRequest,
    "assistance request cancelled" => l10n.snAssistanceRequestCancelled,
    "buyer details updated" => l10n.snBuyerDetailsUpdated,
    "cooperative delivery to confirm" => l10n.snCoopDeliveryToConfirm,
    "cooperative offer cancelled" => l10n.snCoopOfferCancelled,
    "edit request price updated" => l10n.snEditRequestPriceUpdated,
    "edited listing for approval" => l10n.snEditedListingForApproval,
    "farmer accepted the price" => l10n.snFarmerAcceptedPrice,
    "farmer counteroffer" => l10n.snFarmerCounteroffer,
    "feature restricted" => l10n.snFeatureRestricted,
    "restriction lifted" => l10n.snRestrictionLifted,
    "ginger sale recorded" => l10n.snGingerSaleRecorded,
    "ginger submitted for sale" => l10n.snGingerSubmitted,
    "harvest loss reported" => l10n.snHarvestLossReported,
    "harvest quantity reduced" => l10n.snHarvestQuantityReduced,
    "harvest return closed" => l10n.snHarvestReturnClosed,
    "listing disapproved" => l10n.snListingDisapproved,
    "listing edit request" => l10n.snListingEditRequest,
    "listing price adjusted" => l10n.snListingPriceAdjusted,
    "listing price updated" => l10n.snListingPriceUpdated,
    "listing updated" => l10n.snListingUpdated,
    "listing withdrawn" => l10n.snListingWithdrawn,
    "loan fully paid" => l10n.snLoanFullyPaid,
    "loan request cancelled" => l10n.snLoanRequestCancelled,
    "market linking enrollment approved" => l10n.snMlEnrollmentApproved,
    "market linking enrollment declined" => l10n.snMlEnrollmentDeclined,
    "market linking request approved" => l10n.snMlRequestApproved,
    "market linking request cancelled" => l10n.snMlRequestCancelled,
    "market linking request closed" => l10n.snMlRequestClosed,
    "market linking request completed" => l10n.snMlRequestCompleted,
    "market linking request declined" => l10n.snMlRequestDeclined,
    "monthly contribution waived" => l10n.snMonthlyWaived,
    "monthly contribution waiver removed" => l10n.snMonthlyWaiverRemoved,
    "new cooperative order" => l10n.snNewCoopOrder,
    "new loan request" => l10n.snNewLoanRequest,
    "new market linking enrollment" => l10n.snNewMlEnrollment,
    "order cancelled by buyer" => l10n.snOrderCancelledByBuyer,
    "order disapproved" => l10n.snOrderDisapproved,
    "overdue loan" => l10n.snOverdueLoan,
    "payment recorded" => l10n.snPaymentRecorded,
    "pending order" => l10n.snPendingOrder,
    "price update required" => l10n.snPriceUpdateRequired,
    "reference price updated" => l10n.snReferencePriceUpdated,
    "program enrollment approved" => l10n.snProgramEnrollmentApproved,
    "program outcome report" => l10n.snProgramOutcomeReport,
    "program outcome: successful" => l10n.snProgramOutcomeSuccessful,
    "request for another distribution" => l10n.snRequestAnotherDistribution,
    "return quantity changed" => l10n.snReturnQuantityChanged,
    "shelf-life review for approval" => l10n.snShelfLifeReview,
    "your sp3 account was suspended" => l10n.snAccountSuspended,
    _ => _prefixedTitle(l10n, raw),
  };
}

/// Titles that end with a name the database adds (an item, a crop, a person).
String _prefixedTitle(AppLocalizations l10n, String raw) {
  const prefixes = <String, String Function(AppLocalizations, String)>{
    'Low Stock: ': _lowStock,
    'Out of Stock: ': _outOfStock,
    'Price Update: ': _priceUpdate,
    'Inspect ': _inspect,
    'Order Cancelled by ': _cancelledBy,
  };
  for (final e in prefixes.entries) {
    if (raw.startsWith(e.key)) {
      return e.value(l10n, raw.substring(e.key.length));
    }
  }
  return raw;
}

String _lowStock(AppLocalizations l, String v) => l.snLowStock(v);
String _outOfStock(AppLocalizations l, String v) => l.snOutOfStock(v);
String _priceUpdate(AppLocalizations l, String v) => l.snPriceUpdate(v);
String _inspect(AppLocalizations l, String v) => l.snInspect(v);
String _cancelledBy(AppLocalizations l, String v) =>
    l.snOrderCancelledBy(localizeBuiltinLabel(l, v));

const _knownTitles = {
  "monthly contribution reminder",
  "monthly contribution announcement",
  "monthly contribution overdue",
  "account created",
  "account reactivated",
  "account suspended",
  "account approved",
  "account not approved",
  "another distribution",
  "application disapproved",
  "application not approved",
  "application submitted",
  "assistance approved",
  "assistance request not approved",
  "bod meeting coming up",
  "bod meeting in 3 days",
  "balik-tangkilik payout recorded",
  "benefit distributed",
  "buyer found for your ginger",
  "cancellation approved",
  "cancellation declined",
  "capital contribution cancelled",
  "capital contribution recorded",
  "changes requested",
  "cooperative price updated",
  "cooperative purchase confirmed",
  "cooperative purchase offer declined",
  "crop request approved",
  "crop request declined",
  "eligible for another distribution",
  "ginger sale completed",
  "harvest added to your records",
  "harvest return due",
  "harvest return received",
  "join request approved",
  "join request closed",
  "listing approved",
  "listing changes approved",
  "listing changes disapproved",
  "listing rejected",
  "listing sold out",
  "listing status updated",
  "loan assessment referral",
  "assistance referral",
  "loan issued",
  "loan payment due soon",
  "loan request disapproved",
  "market linking cancellation requested",
  "market linking join request approved",
  "membership approved",
  "new cooperative offer",
  "new crop request",
  "new join request",
  "new listing submitted",
  "new market linking request",
  "new membership application",
  "new order received",
  "new program enrollment request",
  "new program purchase request",
  "new order placed",
  "order approved",
  "order cancelled",
  "order completed",
  "order pending review",
  "order rejected",
  "outcome report returned",
  "outcome report pending",
  "patronage capital reinvested",
  "payment reminder",
  "payout decision confirmed",
  "payout decision not approved",
  "program enrollment declined",
  "program outcome: failed",
  "program outcome: thriving",
  "program return settled",
  "purchase cancelled",
  "purchase confirmed",
  "received from program",
  "return due",
};

String localizedNotificationBody(
  AppLocalizations l10n,
  String title,
  String raw,
) {
  if (!l10n.localeName.startsWith('tl') ||
      !_knownTitles.contains(title.toLowerCase())) {
    return raw;
  }
  for (final entry in _bodyTemplates) {
    final match = entry.$1.firstMatch(raw);
    if (match != null) return entry.$2(l10n, match);
  }
  return raw;
}

String _parameter(AppLocalizations l10n, String value) =>
    localizeBuiltinLabel(l10n, value)
        .replaceFirst(RegExp(r'^\s*Reason:\s*'), ' Dahilan: ')
        .replaceFirst(RegExp(r'^\s*Note:\s*'), ' Paalala: ');

final _bodyTemplates = <(RegExp, String Function(AppLocalizations, RegExpMatch))>[
  (
    RegExp(
      "^The BOD meeting is tomorrow\\. The monthly contribution of ₱([\\s\\S]*?) for ([\\s\\S]*?) will be announced there\\. Remaining balance: ₱([\\s\\S]*?)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyMonthlyEve(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Today is the BOD meeting\\. The monthly contribution of ₱([\\s\\S]*?) for ([\\s\\S]*?) is part of the meeting announcement\\. Remaining balance: ₱([\\s\\S]*?)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyMonthlyMeeting(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your ([\\s\\S]*?) monthly contribution was due on ([\\s\\S]*?)\\. Remaining balance: ₱([\\s\\S]*?)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyMonthlyOverdue(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp(
      "^A buyer has been found for your Ginger harvest through Market Linking\\.\$",
    ),
    (l, m) => l.systemNoticeBodyABuyerHasBeenFoundForYour0,
  ),
  (
    RegExp(
      "^A buyer placed an order for ([\\s\\S]*?) kg of your ([\\s\\S]*?) listing\\.\$",
    ),
    (l, m) => l.systemNoticeBodyABuyerPlacedAnOrderForKg1(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^A capital contribution of ₱([\\s\\S]*?) recorded for you was cancelled\\.\$",
    ),
    (l, m) => l.systemNoticeBodyACapitalContributionOfRecordedForYou2(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^A farmer asked to cancel a ([\\s\\S]*?) request \\(([\\s\\S]*?) kg unsold\\)\\. Reason: ([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyAFarmerAskedToCancelARequest3(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp("^A farmer asked to join ([\\s\\S]*?)\\. Review the request\\.\$"),
    (l, m) => l.systemNoticeBodyAFarmerAskedToJoinReviewThe4(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp("^A farmer cancelled their pending program purchase\\.\$"),
    (l, m) => l.systemNoticeBodyAFarmerCancelledTheirPendingProgramPurchase5,
  ),
  (
    RegExp(
      "^A farmer requested to enroll in ([\\s\\S]*?) and needs review\\.\$",
    ),
    (l, m) => l.systemNoticeBodyAFarmerRequestedToEnrollInAnd6(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^A farmer requested to enroll ([\\s\\S]*?) in Market Linking and needs review\\.\$",
    ),
    (l, m) => l.systemNoticeBodyAFarmerRequestedToEnrollInMarket7(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^A new loan \\(([\\s\\S]*?)\\) worth ₱([\\s\\S]*?) has been issued to you\\.\$",
    ),
    (l, m) => l.systemNoticeBodyANewLoanWorthHasBeenIssued8(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^A new loan \\(([\\s\\S]*?)\\) worth ₱([\\s\\S]*?) has been issued to you: ([\\s\\S]*?)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyANewLoanWorthHasBeenIssued9(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp(
      "^A new order \\(([\\s\\S]*?) kg\\) has been placed and is awaiting approval\\.\$",
    ),
    (l, m) => l.systemNoticeBodyANewOrderKgHasBeenPlaced10(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp("^An order for your ([\\s\\S]*?) listing has been approved\\.\$"),
    (l, m) => l.systemNoticeBodyAnOrderForYourListingHasBeen11(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^An order for your ([\\s\\S]*?) listing was cancelled\\.([\\s\\S]*?)([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyAnOrderForYourListingWasCancelled12(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp(
      "^An order for your ([\\s\\S]*?) listing was rejected\\.([\\s\\S]*?)([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyAnOrderForYourListingWasRejected13(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp("^Someone completed a purchase of your ([\\s\\S]*?) listing\\.\$"),
    (l, m) => l.systemNoticeBodySomeoneCompletedAPurchaseOfYourListing14(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp("^The Farmer account you created was approved\\.\$"),
    (l, m) => l.systemNoticeBodyTheFarmerAccountYouCreatedWasApproved15,
  ),
  (
    RegExp(
      "^The Farmer account you created was not approved\\. Reason: ([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyTheFarmerAccountYouCreatedWasNot16(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^The account you created was approved by the Manager and can now sign in\\.\$",
    ),
    (l, m) => l.systemNoticeBodyTheAccountYouCreatedWasApprovedBy17,
  ),
  (
    RegExp(
      "^The account you created was not approved by the Manager\\. Reason: ([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyTheAccountYouCreatedWasNotApproved18(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^The cooperative changed the price of your ([\\s\\S]*?) listing to ₱([\\s\\S]*?)/kg\\.\$",
    ),
    (l, m) => l.systemNoticeBodyTheCooperativeChangedThePriceOfYour19(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^The cooperative recorded ([\\s\\S]*?) ([\\s\\S]*?) ([\\s\\S]*?) for ([\\s\\S]*?)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyTheCooperativeRecordedFor20(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
      _parameter(l, m.group(4) ?? ''),
    ),
  ),
  (
    RegExp(
      "^The cooperative referred you for an assistance assessment\\. You may request assistance items from the cooperative\\. This is not a loan: there is nothing to repay\\.\$",
    ),
    (l, m) => l.systemNoticeBodyTheCooperativeReferredYouForAssistance,
  ),
  (
    RegExp(
      "^The cooperative referred you for a loan assessment\\. You may request items on loan from the Loan Item Catalog\\. This is not a loan yet: your request will be assessed and approved as usual\\.\$",
    ),
    (l, m) => l.systemNoticeBodyTheCooperativeReferredYouForALoan21,
  ),
  (
    RegExp(
      "^The cooperative reminds you to report the outcome of the ([\\s\\S]*?) you received on ([\\s\\S]*?)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyTheCooperativeRemindsYouToReportThe22(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^The cooperative will give you another item in ([\\s\\S]*?) after your earlier outcome\\. You will be notified when it is handed to you\\.\$",
    ),
    (l, m) => l.systemNoticeBodyTheCooperativeWillGiveYouAnotherItem23(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^You can now submit your Ginger harvest for sale through Market Linking\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYouCanNowSubmitYourGingerHarvest24,
  ),
  (
    RegExp("^You received ([\\s\\S]*?) ([\\s\\S]*?) from your program\\.\$"),
    (l, m) => l.systemNoticeBodyYouReceivedFromYourProgram25(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^You received ([\\s\\S]*?)([\\s\\S]*?) ([\\s\\S]*?) from your program\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYouReceivedFromYourProgram26(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your Balik-Tangkilik payout decision for ([\\s\\S]*?) has been confirmed by the cooperative\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourBalikTangkilikPayoutDecisionForHas27(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your Balik-Tangkilik payout decision for ([\\s\\S]*?) was not approved\\. You may submit a new decision\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourBalikTangkilikPayoutDecisionForWas28(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your Balik-Tangkilik payout for ([\\s\\S]*?) of ₱([\\s\\S]*?) has been recorded\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourBalikTangkilikPayoutForOfHas29(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp("^Your Ginger sale through Market Linking has been completed\\.\$"),
    (l, m) => l.systemNoticeBodyYourGingerSaleThroughMarketLinkingHas30,
  ),
  (
    RegExp(
      "^Your SAGANA account was created by the cooperative Manager\\. Sign in with your temporary password and change it to continue\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourSAGANAAccountWasCreatedByThe31,
  ),
  (
    RegExp(
      "^Your SAGANA account was created by the cooperative admin\\. Sign in with your temporary password and change it to continue\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourSAGANAAccountWasCreatedByThe32,
  ),
  (
    RegExp("^Your SP3 account has been reactivated\\. Welcome back!\$"),
    (l, m) => l.systemNoticeBodyYourSPAccountHasBeenReactivatedWelcome33,
  ),
  (
    RegExp(
      "^Your SP3 account has been suspended\\. Reason: ([\\s\\S]*?) Please contact the SP3 Cooperative\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourSPAccountHasBeenSuspendedReason34(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your SP3 cooperative membership has been approved\\. Open SAGANA and tap Continue to activate your farmer access\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourSPCooperativeMembershipHasBeenApproved35,
  ),
  (
    RegExp(
      "^Your SP3 cooperative membership has been approved\\. Open SAGANA and tap Continue to activate your farmer access\\. Your Member ID is ([\\s\\S]*?)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourSPCooperativeMembershipHasBeenApproved36(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your SP3 membership application was disapproved\\. Reason: ([\\s\\S]*?) You may review your details and resubmit\\.\$",
    ),
    (l, m) =>
        l.systemNoticeBodyYourSPMembershipApplicationWasDisapprovedReason37(
          _parameter(l, m.group(1) ?? ''),
        ),
  ),
  (
    RegExp(
      "^Your SP3 membership application was not approved\\. Reason: ([\\s\\S]*?) You may review your details and resubmit\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourSPMembershipApplicationWasNotApproved38(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your assistance request ([\\s\\S]*?) for ([\\s\\S]*?) was approved \\(([\\s\\S]*?)\\)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourAssistanceRequestForWasApproved39(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp("^Your assistance request ([\\s\\S]*?) was not approved\\.\$"),
    (l, m) => l.systemNoticeBodyYourAssistanceRequestWasNotApproved40(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp("^Your capital contribution of ₱([\\s\\S]*?) was recorded\\.\$"),
    (l, m) => l.systemNoticeBodyYourCapitalContributionOfWasRecorded41(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your changes to the ([\\s\\S]*?) listing were approved and are now live\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourChangesToTheListingWereApproved42(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your distribution from ([\\s\\S]*?) was recorded as failed and converted to loan ([\\s\\S]*?)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourDistributionFromWasRecordedAsFailed43(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your earlier outcome in ([\\s\\S]*?) was reviewed and you are eligible for another distribution\\. You can request it from My Programs; you do not need to join again\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourEarlierOutcomeInWasReviewedAnd44(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your enrollment request for ([\\s\\S]*?) was declined because the program was completed\\. You may join other open programs\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourEnrollmentRequestForWasDeclinedBecause45(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your loan request ([\\s\\S]*?) was not approved\\. Reason: ([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyYourLoanRequestWasNotApprovedReason46(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your loan ([\\s\\S]*?) has a missed payment\\. Outstanding balance: ₱([\\s\\S]*?)\\. Please settle at the next BOD meeting or visit the cooperative office\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourLoanHasAMissedPaymentOutstanding47(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your loan ([\\s\\S]*?) has an installment of ₱([\\s\\S]*?) due on ([\\s\\S]*?)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourLoanHasAnInstallmentOfDue48(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your membership application has been sent to the SP3 Cooperative for review\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourMembershipApplicationHasBeenSentTo49,
  ),
  (
    RegExp(
      "^Your offer of ([\\s\\S]*?)kg ([\\s\\S]*?) was confirmed by SP3 for ₱([\\s\\S]*?)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourOfferOfKgWasConfirmedBy50(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your offer of ([\\s\\S]*?)kg ([\\s\\S]*?) was not accepted by SP3\\.([\\s\\S]*?)([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyYourOfferOfKgWasNotAccepted51(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
      _parameter(l, m.group(4) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your order for ([\\s\\S]*?) has been approved and is being prepared\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourOrderForHasBeenApprovedAnd54(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your order for ([\\s\\S]*?) has been completed\\. Thank you for supporting SP3 farmers!\$",
    ),
    (l, m) => l.systemNoticeBodyYourOrderForHasBeenCompletedThank55(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your order for ([\\s\\S]*?) was cancelled\\.([\\s\\S]*?)([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyYourOrderForWasCancelled56(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your order for ([\\s\\S]*?) was placed and is pending review\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourOrderForWasPlacedAndIs57(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your order for ([\\s\\S]*?) was rejected\\.([\\s\\S]*?)([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyYourOrderForWasRejected58(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your outcome for ([\\s\\S]*?) was confirmed as successful after the field verification\\. You are to return ([\\s\\S]*?) ([\\s\\S]*?) of your harvested ([\\s\\S]*?) to the cooperative\\. The rest of your harvest stays with you\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourOutcomeForWasConfirmedAsSuccessful59(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
      _parameter(l, m.group(4) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your outcome for ([\\s\\S]*?) was confirmed as successful after the field verification\\. You are to return ([\\s\\S]*?) ([\\s\\S]*?) ([\\s\\S]*?) to the cooperative\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourOutcomeForWasConfirmedAsSuccessful60(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
      _parameter(l, m.group(4) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your outcome for ([\\s\\S]*?) was successful\\. The cooperative will record your harvest return of ([\\s\\S]*?) ([\\s\\S]*?) ([\\s\\S]*?) when it is received\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourOutcomeForWasSuccessfulTheCooperative61(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
      _parameter(l, m.group(4) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your outcome report for ([\\s\\S]*?) needs more evidence: ([\\s\\S]*?) Please submit a new report\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourOutcomeReportForNeedsMoreEvidence62(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp("^Your participation in ([\\s\\S]*?) was recorded as thriving\\.\$"),
    (l, m) => l.systemNoticeBodyYourParticipationInWasRecordedAsThriving63(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your program purchase was cancelled by the SP3 Admin\\.([\\s\\S]*?)([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyYourProgramPurchaseWasCancelledByThe64(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your purchase of ([\\s\\S]*?) ([\\s\\S]*?) has been confirmed\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourPurchaseOfHasBeenConfirmed65(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your request to cancel the ([\\s\\S]*?) request was declined\\. Reason: ([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyYourRequestToCancelTheRequestWas66(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your request to join ([\\s\\S]*?) was approved\\. You are now a member\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourRequestToJoinWasApprovedYou67(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your request to join ([\\s\\S]*?) was closed because the program was completed\\. You may join other open programs\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourRequestToJoinWasClosedBecause68(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your requested changes to the ([\\s\\S]*?) listing were not approved\\. Your listing stays as it was\\. Reason: ([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyYourRequestedChangesToTheListingWere69(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your return of ₱([\\s\\S]*?) for ([\\s\\S]*?) has been recorded\\. Thank you!\$",
    ),
    (l, m) => l.systemNoticeBodyYourReturnOfForHasBeenRecorded70(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your ([\\s\\S]*?) listing has been marked Rejected\\. You can create a new listing for this batch\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourListingHasBeenMarkedRejectedYou71(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp("^Your ([\\s\\S]*?) listing has been sold out\\.\$"),
    (l, m) => l.systemNoticeBodyYourListingHasBeenSoldOut72(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp("^Your ([\\s\\S]*?) listing is now live on the Marketplace\\.\$"),
    (l, m) => l.systemNoticeBodyYourListingIsNowLiveOnThe73(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your ([\\s\\S]*?) listing needs changes before it can go live\\. Note: ([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyYourListingNeedsChangesBeforeItCan74(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp("^Your ([\\s\\S]*?) listing was rejected\\. Reason: ([\\s\\S]*?)\$"),
    (l, m) => l.systemNoticeBodyYourListingWasRejectedReason75(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^Your ([\\s\\S]*?) order has been approved and is being prepared for the buyer\\.\$",
    ),
    (l, m) => l.systemNoticeBodyYourOrderHasBeenApprovedAndIs76(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp("^Your ([\\s\\S]*?) order has been completed and sold\\.\$"),
    (l, m) => l.systemNoticeBodyYourOrderHasBeenCompletedAndSold77(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^([\\s\\S]*?) \\(([\\s\\S]*?) kg\\) was offered to the cooperative and needs review\\.\$",
    ),
    (l, m) => l.systemNoticeBodyKgWasOfferedToTheCooperativeAnd79(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp("^([\\s\\S]*?) \\(([\\s\\S]*?)kg\\) was submitted for review\\.\$"),
    (l, m) => l.systemNoticeBodyKgWasSubmittedForReview80(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^([\\s\\S]*?) cancelled their order for your ([\\s\\S]*?) listing\\.([\\s\\S]*?)([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyCancelledTheirOrderForYourListing81(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
      _parameter(l, m.group(4) ?? ''),
    ),
  ),
  (
    RegExp(
      "^([\\s\\S]*?) confirmed receiving ([\\s\\S]*?) ([\\s\\S]*?) of your ([\\s\\S]*?)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyConfirmedReceivingOfYour82(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
      _parameter(l, m.group(4) ?? ''),
    ),
  ),
  (
    RegExp(
      "^([\\s\\S]*?) confirmed receiving ([\\s\\S]*?) ([\\s\\S]*?) of ([\\s\\S]*?)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyConfirmedReceivingOf83(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
      _parameter(l, m.group(4) ?? ''),
    ),
  ),
  (
    RegExp(
      "^([\\s\\S]*?) has been added to the official crop list and is now fully approved\\.\$",
    ),
    (l, m) => l.systemNoticeBodyHasBeenAddedToTheOfficialCrop84(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp("^([\\s\\S]*?) registered and needs review\\.\$"),
    (l, m) => l.systemNoticeBodyRegisteredAndNeedsReview85(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^([\\s\\S]*?) reinvested ₱([\\s\\S]*?) of their ([\\s\\S]*?) Balik-Tangkilik payout into their capital share\\.\$",
    ),
    (l, m) => l.systemNoticeBodyReinvestedOfTheirBalikTangkilikPayoutInto86(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp(
      "^([\\s\\S]*?) requested to purchase ([\\s\\S]*?) ([\\s\\S]*?)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyRequestedToPurchase87(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
    ),
  ),
  (
    RegExp(
      "^([\\s\\S]*?) requested to purchase ([\\s\\S]*?) ([\\s\\S]*?)([\\s\\S]*?)([\\s\\S]*?)([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyRequestedToPurchase88(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
      _parameter(l, m.group(4) ?? ''),
      _parameter(l, m.group(5) ?? ''),
      _parameter(l, m.group(6) ?? ''),
    ),
  ),
  (
    RegExp(
      "^([\\s\\S]*?) submitted a membership application and needs review\\.\$",
    ),
    (l, m) => l.systemNoticeBodySubmittedAMembershipApplicationAndNeedsReview89(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^([\\s\\S]*?) was created by ([\\s\\S]*?) and needs your approval\\.\$",
    ),
    (l, m) => l.systemNoticeBodyWasCreatedByAndNeedsYourApproval90(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp(
      "^([\\s\\S]*?) was not added to the official list\\. Reason: ([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyWasNotAddedToTheOfficialList91(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
    ),
  ),
  (
    RegExp("^([\\s\\S]*?) was requested by a farmer and needs review\\.\$"),
    (l, m) => l.systemNoticeBodyWasRequestedByAFarmerAndNeeds92(
      _parameter(l, m.group(1) ?? ''),
    ),
  ),
  (
    RegExp(
      "^([\\s\\S]*?) ([\\s\\S]*?) of ([\\s\\S]*?) from ([\\s\\S]*?) was added to your Harvest records \\(([\\s\\S]*?)\\)\\.([\\s\\S]*?)\$",
    ),
    (l, m) => l.systemNoticeBodyOfFromWasAddedToYourHarvest93(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
      _parameter(l, m.group(4) ?? ''),
      _parameter(l, m.group(5) ?? ''),
      _parameter(l, m.group(6) ?? ''),
    ),
  ),
  (
    RegExp(
      "^([\\s\\S]*?) ([\\s\\S]*?) of ([\\s\\S]*?) from ([\\s\\S]*?) was added to your Harvest tab \\(([\\s\\S]*?)\\)\\.\$",
    ),
    (l, m) => l.systemNoticeBodyOfFromWasAddedToYourHarvest94(
      _parameter(l, m.group(1) ?? ''),
      _parameter(l, m.group(2) ?? ''),
      _parameter(l, m.group(3) ?? ''),
      _parameter(l, m.group(4) ?? ''),
      _parameter(l, m.group(5) ?? ''),
    ),
  ),
];
