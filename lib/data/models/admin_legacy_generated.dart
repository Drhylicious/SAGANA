// GENERATED from .claude-scratch/admin_log_keys.txt. Do not edit by hand.
import 'admin_log_message.dart';

/// Recovers the key and parameters from an English admin_activity_log
/// description written before message keys existed. Null if no template matches.
AdminLogMessage? parseLegacyAdminLog(String text) {
  final checks = <(RegExp, String, List<String>)>[
    (RegExp('^Created Officer account for (.+?)\\.\$'), 'adminLogAccountOfficerCreated', ['fullName']),
    (RegExp('^Reset an account\'s password\\.\$'), 'adminLogAccountPasswordReset', []),
    (RegExp('^Resolved a pending password reset request\\.\$'), 'adminLogAccountResetResolved', []),
    (RegExp('^Added "(.+?)" as a new member\\.\$'), 'adminLogMemberAdded', ['fullName']),
    (RegExp('^Approved a marketplace listing\\.\$'), 'adminLogListingApproved', []),
    (RegExp('^Rejected a marketplace listing\\.\$'), 'adminLogListingRejected', []),
    (RegExp('^Updated a loan catalog item \\(₱(.+?)\\)\\.\$'), 'adminLogLoanItemUpdated', ['price']),
    (RegExp('^Issued a loan \\(₱(.+?)\\/month\\)\\.\$'), 'adminLogLoanIssued', ['monthly']),
    (RegExp('^Recorded a loan payment \\(₱(.+?)\\)\\.\$'), 'adminLogLoanPaymentRecorded', ['amount']),
    (RegExp('^Manually marked a loan as paid\\.\$'), 'adminLogLoanMarkedPaid', []),
    (RegExp('^Approved an order\\.\$'), 'adminLogOrderApproved', []),
    (RegExp('^Cancelled an order\\.\$'), 'adminLogOrderCancelled', []),
    (RegExp('^Completed an order\\.\$'), 'adminLogOrderCompleted', []),
    (RegExp('^(.+?) updated their profile information\\.\$'), 'adminLogProfileUpdated', ['fullName']),
    (RegExp('^Updated their profile picture\\.\$'), 'adminLogProfilePhotoUpdated', []),
    (RegExp('^Removed their profile picture\\.\$'), 'adminLogProfilePhotoRemoved', []),
    (RegExp('^Confirmed a (.+?) Balik Tangkilik payout decision\\.\$'), 'adminLogBalikPayoutConfirmed', ['year']),
    (RegExp('^Rejected a (.+?) Balik Tangkilik payout decision\\.\$'), 'adminLogBalikPayoutRejected', ['year']),
    (RegExp('^Broadcast "(.+?)" scheduled for (.+?)\\.\$'), 'adminLogBroadcastScheduled', ['title', 'when']),
    (RegExp('^Suspended a buyer account\\.\$'), 'adminLogBuyerSuspended', []),
    (RegExp('^Reactivated a buyer account\\.\$'), 'adminLogBuyerReactivated', []),
    (RegExp('^Recorded a capital contribution \\(₱(.+?)\\)\\.\$'), 'adminLogContributionRecorded', ['amount']),
    (RegExp('^Added "(.+?)" as an inventory category\\.\$'), 'adminLogInventoryCategoryAdded', ['name']),
    (RegExp('^Added "(.+?)" as a crop category\\.\$'), 'adminLogCropCategoryAdded', ['name']),
    (RegExp('^Confirmed a cooperative offer for (.+?)kg \\(₱(.+?)\\)\\.\$'), 'adminLogCoopOfferConfirmed', ['kg', 'amount']),
    (RegExp('^Declined a cooperative offer\\.\$'), 'adminLogCoopOfferDeclined', []),
    (RegExp('^Suspended a member\\.\$'), 'adminLogMemberSuspended', []),
    (RegExp('^Reactivated a member\\.\$'), 'adminLogMemberReactivated', []),
    (RegExp('^Approved (.+?)\'s membership application\\.\$'), 'adminLogMembershipApproved', ['fullName']),
    (RegExp('^Rejected a membership application\\.\$'), 'adminLogMembershipRejected', []),
    (RegExp('^Published an inventory item to the loan catalog \\(₱(.+?)\\)\\.\$'), 'adminLogLoanCatalogPublished', ['price']),
    (RegExp('^Completed a market linking round\\.\$'), 'adminLogMarketLinkingCompleted', []),
    (RegExp('^Updated a market linking status to "(.+?)"\\.\$'), 'adminLogMarketLinkingStatus', ['status']),
    (RegExp('^Deleted a cancelled market linking entry\\.\$'), 'adminLogMarketLinkingDeleted', []),
    (RegExp('^Updated the linked batch on a market linking entry\\.\$'), 'adminLogMarketLinkingBatchAttached', []),
    (RegExp('^Approved a farmer\'s DA-AMAD Market Linking enrollment\\.\$'), 'adminLogEnrollmentApproved', []),
    (RegExp('^Declined a farmer\'s DA-AMAD Market Linking enrollment\\.\$'), 'adminLogEnrollmentDeclined', []),
    (RegExp('^Recorded a (.+?) price for "(.+?)" \\(₱(.+?)\\/(.+?)\\)\\.\$'), 'adminLogPriceRecorded', ['priceType', 'crop', 'price', 'unit']),
    (RegExp('^Deleted a price record\\.\$'), 'adminLogPriceDeleted', []),
    (RegExp('^Updated a cooperative market listing price to ₱(.+?)\\.\$'), 'adminLogCoopListingPriceUpdated', ['price']),
    (RegExp('^Created program "(.+?)"\\.\$'), 'adminLogProgramCreated', ['name']),
    (RegExp('^Updated program "(.+?)"\\.\$'), 'adminLogProgramUpdated', ['name']),
    (RegExp('^Deleted program "(.+?)"\\.\$'), 'adminLogProgramDeleted', ['name']),
    (RegExp('^Approved a farmer\'s program enrollment request\\.\$'), 'adminLogProgramEnrollmentApproved', []),
    (RegExp('^Declined a farmer\'s program enrollment request\\.\$'), 'adminLogProgramEnrollmentDeclined', []),
    (RegExp('^Removed a member from a program\\.\$'), 'adminLogProgramMemberRemoved', []),
    (RegExp('^Distributed a program benefit to a member\\.\$'), 'adminLogProgramBenefitDistributed', []),
    (RegExp('^Added a product to a sales program\\.\$'), 'adminLogProgramProductAdded', []),
    (RegExp('^Updated a sales program product\\.\$'), 'adminLogProgramProductUpdated', []),
    (RegExp('^Removed a product from a sales program\\.\$'), 'adminLogProgramProductRemoved', []),
    (RegExp('^Confirmed payment for a program product purchase\\.\$'), 'adminLogProgramPurchaseConfirmed', []),
    (RegExp('^Cancelled a program product purchase\\.\$'), 'adminLogProgramPurchaseCancelled', []),
    (RegExp('^Confirmed a revenue-share return \\(₱(.+?)\\)\\.\$'), 'adminLogProgramReturnConfirmed', ['amount']),
    (RegExp('^Recorded a distribution outcome as thriving\\.\$'), 'adminLogProgramOutcomeThriving', []),
    (RegExp('^Converted a failed distribution into a loan\\.\$'), 'adminLogProgramConvertedToLoan', []),
    (RegExp('^Scheduled "(.+?)" for a program\\.\$'), 'adminLogProgramActivityCreated', ['title']),
    (RegExp('^Deleted a program activity\\.\$'), 'adminLogProgramActivityDeleted', []),
    (RegExp('^Changed their account password\\.\$'), 'adminLogPasswordChanged', []),
    (RegExp('^Added inventory item "(.+?)" \\((.+?)\\)\\.\$'), 'adminLogInventoryItemAdded', ['name', 'category']),
    (RegExp('^Added (.+?) units of stock \\((.+?)\\)\\.\$'), 'adminLogStockAdded', ['qty', 'type']),
    (RegExp('^Deducted (.+?) units of stock \\((.+?)\\)\\.\$'), 'adminLogStockDeducted', ['qty', 'type']),
    (RegExp('^Updated the reorder level for an inventory item\\.\$'), 'adminLogReorderLevelUpdated', []),
    (RegExp('^Updated inventory item "(.+?)"\\.\$'), 'adminLogInventoryItemUpdated', ['name']),
    (RegExp('^Deactivated an inventory item\\.\$'), 'adminLogInventoryDeactivated', []),
    (RegExp('^Deleted inventory item\\.\$'), 'adminLogInventoryDeleted', []),
    (RegExp('^Added "(.+?)" to the crop catalog \\((.+?)\\)\\.\$'), 'adminLogCropCatalogAdded', ['name', 'category']),
    (RegExp('^Updated "(.+?)" in the crop catalog \\((.+?)\\)\\.\$'), 'adminLogCropCatalogUpdated', ['name', 'category']),
    (RegExp('^Reactivated a crop in the catalog\\.\$'), 'adminLogCropReactivated', []),
    (RegExp('^Deactivated a crop in the catalog\\.\$'), 'adminLogCropDeactivated', []),
    (RegExp('^Deleted a crop from the catalog\\.\$'), 'adminLogCropDeleted', []),
    (RegExp('^Approved (.+?)\'s crop request for "(.+?)"\\.\$'), 'adminLogCropRequestApproved', ['farmer', 'crop']),
    (RegExp('^Rejected (.+?)\'s crop request for "(.+?)"\\.\$'), 'adminLogCropRequestRejected', ['farmer', 'crop']),
  ];
  // Plural templates, matched by hand: the count word differs by number.
  final broadcast = RegExp(r'^Broadcast "(.+?)" sent to (\d+) recipients?\.$')
      .firstMatch(text);
  if (broadcast != null) {
    return AdminLogMessage('adminLogBroadcastSent', {
      'title': broadcast.group(1)!,
      'count': broadcast.group(2)!,
    });
  }
  final export = RegExp(r'^Generated a (.+?) export \((\d+) reports?\)\.$')
      .firstMatch(text);
  if (export != null) {
    return AdminLogMessage('adminLogExportGenerated', {
      'format': export.group(1)!,
      'count': export.group(2)!,
    });
  }
  for (final (regex, key, names) in checks) {
    final match = regex.firstMatch(text);
    if (match == null) continue;
    final params = <String, String>{
      for (var i = 0; i < names.length; i++) names[i]: match.group(i + 1)!,
    };
    return AdminLogMessage(key, params);
  }
  return null;
}
