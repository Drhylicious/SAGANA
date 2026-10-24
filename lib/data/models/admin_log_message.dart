import 'package:flutter/widgets.dart' show Locale;

import '../../core/l10n/app_localizations.dart';

/// A structured admin activity entry. The log stores [key] and [params]
/// (admin_activity_log.message_key / message_params) so the text can be
/// rendered in the reader's language. Legacy rows have no key and keep their
/// stored English description.
class AdminLogMessage {
  final String key;
  final Map<String, String> params;

  const AdminLogMessage(this.key, [this.params = const {}]);
}

/// English text for storage in the legacy `description` column.
String adminLogEnglish(AdminLogMessage message) =>
    renderAdminLogMessage(lookupAppLocalizations(const Locale('en')), message);

String renderAdminLogMessage(AppLocalizations l, AdminLogMessage m) {
  final p = m.params;
  String v(String name) => p[name] ?? '';
  switch (m.key) {
    case 'adminLogAccountOfficerCreated':
      return l.adminLogAccountOfficerCreated(v('fullName'));
    case 'adminLogAccountPasswordReset':
      return l.adminLogAccountPasswordReset;
    case 'adminLogAccountResetResolved':
      return l.adminLogAccountResetResolved;
    case 'adminLogMemberAdded':
      return l.adminLogMemberAdded(v('fullName'));
    case 'adminLogListingApproved':
      return l.adminLogListingApproved;
    case 'adminLogListingRejected':
      return l.adminLogListingRejected;
    case 'adminLogLoanItemUpdated':
      return l.adminLogLoanItemUpdated(v('price'));
    case 'adminLogLoanIssued':
      return l.adminLogLoanIssued(v('monthly'));
    case 'adminLogLoanPaymentRecorded':
      return l.adminLogLoanPaymentRecorded(v('amount'));
    case 'adminLogLoanMarkedPaid':
      return l.adminLogLoanMarkedPaid;
    case 'adminLogOrderApproved':
      return l.adminLogOrderApproved;
    case 'adminLogOrderCancelled':
      return l.adminLogOrderCancelled;
    case 'adminLogOrderCompleted':
      return l.adminLogOrderCompleted;
    case 'adminLogProfileUpdated':
      return l.adminLogProfileUpdated(v('fullName'));
    case 'adminLogProfilePhotoUpdated':
      return l.adminLogProfilePhotoUpdated;
    case 'adminLogProfilePhotoRemoved':
      return l.adminLogProfilePhotoRemoved;
    case 'adminLogBalikPayoutConfirmed':
      return l.adminLogBalikPayoutConfirmed(v('year'));
    case 'adminLogBalikPayoutRejected':
      return l.adminLogBalikPayoutRejected(v('year'));
    case 'adminLogBroadcastScheduled':
      return l.adminLogBroadcastScheduled(v('title'), v('when'));
    case 'adminLogBroadcastSent':
      return l.adminLogBroadcastSent(v('title'), int.tryParse(v('count')) ?? 0);
    case 'adminLogBuyerSuspended':
      return l.adminLogBuyerSuspended;
    case 'adminLogBuyerReactivated':
      return l.adminLogBuyerReactivated;
    case 'adminLogContributionRecorded':
      return l.adminLogContributionRecorded(v('amount'));
    case 'adminLogInventoryCategoryAdded':
      return l.adminLogInventoryCategoryAdded(v('name'));
    case 'adminLogUnitAdded':
      return l.adminLogUnitAdded(v('name'));
    case 'adminLogCropCategoryAdded':
      return l.adminLogCropCategoryAdded(v('name'));
    case 'adminLogCoopOfferConfirmed':
      return l.adminLogCoopOfferConfirmed(v('kg'), v('amount'));
    case 'adminLogCoopOfferDeclined':
      return l.adminLogCoopOfferDeclined;
    case 'adminLogCoopOfferCountered':
      return l.adminLogCoopOfferCountered(v('price'));
    case 'adminLogMemberSuspended':
      return l.adminLogMemberSuspended;
    case 'adminLogMemberReactivated':
      return l.adminLogMemberReactivated;
    case 'adminLogMembershipApproved':
      return l.adminLogMembershipApproved(v('fullName'));
    case 'adminLogMembershipRejected':
      return l.adminLogMembershipRejected;
    case 'adminLogLoanCatalogPublished':
      return l.adminLogLoanCatalogPublished(v('price'));
    case 'adminLogMarketLinkingCompleted':
      return l.adminLogMarketLinkingCompleted;
    case 'adminLogMarketLinkingStatus':
      return l.adminLogMarketLinkingStatus(v('status'));
    case 'adminLogMarketLinkingDeleted':
      return l.adminLogMarketLinkingDeleted;
    case 'adminLogMarketLinkingBatchAttached':
      return l.adminLogMarketLinkingBatchAttached;
    case 'adminLogEnrollmentApproved':
      return l.adminLogEnrollmentApproved;
    case 'adminLogEnrollmentDeclined':
      return l.adminLogEnrollmentDeclined;
    case 'adminLogPriceRecorded':
      return l.adminLogPriceRecorded(v('priceType'), v('crop'), v('price'), v('unit'));
    case 'adminLogPriceDeleted':
      return l.adminLogPriceDeleted;
    case 'adminLogCoopListingPriceUpdated':
      return l.adminLogCoopListingPriceUpdated(v('price'));
    case 'adminLogProgramCreated':
      return l.adminLogProgramCreated(v('name'));
    case 'adminLogProgramUpdated':
      return l.adminLogProgramUpdated(v('name'));
    case 'adminLogProgramDeleted':
      return l.adminLogProgramDeleted(v('name'));
    case 'adminLogProgramEnrollmentApproved':
      return l.adminLogProgramEnrollmentApproved;
    case 'adminLogProgramEnrollmentDeclined':
      return l.adminLogProgramEnrollmentDeclined;
    case 'adminLogProgramMemberRemoved':
      return l.adminLogProgramMemberRemoved;
    case 'adminLogProgramBenefitDistributed':
      return l.adminLogProgramBenefitDistributed;
    case 'adminLogProgramProductAdded':
      return l.adminLogProgramProductAdded;
    case 'adminLogProgramProductUpdated':
      return l.adminLogProgramProductUpdated;
    case 'adminLogProgramProductRemoved':
      return l.adminLogProgramProductRemoved;
    case 'adminLogProgramPurchaseConfirmed':
      return l.adminLogProgramPurchaseConfirmed;
    case 'adminLogProgramPurchaseCancelled':
      return l.adminLogProgramPurchaseCancelled;
    case 'adminLogProgramReturnConfirmed':
      return l.adminLogProgramReturnConfirmed(v('amount'));
    case 'adminLogProgramOutcomeThriving':
      return l.adminLogProgramOutcomeThriving;
    case 'adminLogProgramConvertedToLoan':
      return l.adminLogProgramConvertedToLoan;
    case 'adminLogProgramActivityCreated':
      return l.adminLogProgramActivityCreated(v('title'));
    case 'adminLogProgramActivityDeleted':
      return l.adminLogProgramActivityDeleted;
    case 'adminLogPasswordChanged':
      return l.adminLogPasswordChanged;
    case 'adminLogInventoryItemAdded':
      return l.adminLogInventoryItemAdded(v('name'), v('category'));
    case 'adminLogStockAdded':
      return l.adminLogStockAdded(v('qty'), v('type'));
    case 'adminLogStockDeducted':
      return l.adminLogStockDeducted(v('qty'), v('type'));
    case 'adminLogReorderLevelUpdated':
      return l.adminLogReorderLevelUpdated;
    case 'adminLogInventoryItemUpdated':
      return l.adminLogInventoryItemUpdated(v('name'));
    case 'adminLogInventoryDeactivated':
      return l.adminLogInventoryDeactivated;
    case 'adminLogInventoryDeleted':
      return l.adminLogInventoryDeleted;
    case 'adminLogCropCatalogAdded':
      return l.adminLogCropCatalogAdded(v('name'), v('category'));
    case 'adminLogCropCatalogUpdated':
      return l.adminLogCropCatalogUpdated(v('name'), v('category'));
    case 'adminLogCropReactivated':
      return l.adminLogCropReactivated;
    case 'adminLogCropDeactivated':
      return l.adminLogCropDeactivated;
    case 'adminLogCropDeleted':
      return l.adminLogCropDeleted;
    case 'adminLogCropRequestApproved':
      return l.adminLogCropRequestApproved(v('farmer'), v('crop'));
    case 'adminLogCropRequestRejected':
      return l.adminLogCropRequestRejected(v('farmer'), v('crop'));
    case 'adminLogExportGenerated':
      return l.adminLogExportGenerated(v('format'), int.tryParse(v('count')) ?? 0);
    default:
      return m.key;
  }
}
