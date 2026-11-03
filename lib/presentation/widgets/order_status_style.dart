import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Accent colour for a stored order status (see kOrderStatuses). Shared by Buyer,
/// Farmer and Admin order screens
/// so one status reads the same colour everywhere. Cancelled uses the error red:
/// an order that will not be fulfilled. (An old stored 'rejected' is read as
/// cancelled, see canonicalOrderStatus.)
Color orderStatusColor(String status) {
  switch (status) {
    case 'pending':
      return AppConstants.warningAmber;
    case 'approved':
      return AppConstants.successGreen;
    case 'ready_for_pickup':
      return AppConstants.buyerBlue;
    case 'out_for_delivery':
      return AppConstants.programPurple;
    case 'delivered':
      return AppConstants.midGreen;
    case 'completed':
      return AppConstants.primaryGreen;
    case 'cancelled':
    case 'rejected': // legacy stored value, shown as cancelled
      return AppConstants.errorRed;
    default:
      return AppConstants.outline;
  }
}

/// Buyer- and farmer-facing label for a stored order status. Admin uses
/// adminOrderStatusLabel() in management_modal.dart, which has its own wording.
String buyerOrderStatusLabel(String status, AppLocalizations l10n) {
  switch (status) {
    case 'pending':
      return l10n.buyerOrdersStatusPending;
    case 'approved':
      return l10n.buyerOrdersStatusApproved;
    case 'ready_for_pickup':
      return l10n.orderStatusReadyForPickup;
    case 'out_for_delivery':
      return l10n.orderStatusOutForDelivery;
    case 'delivered':
      return l10n.orderStatusDelivered;
    case 'completed':
      return l10n.buyerOrdersStatusCompleted;
    case 'cancelled':
    case 'rejected': // legacy stored value, shown as cancelled
      return l10n.buyerOrdersStatusCancelled;
    default:
      return status.toUpperCase();
  }
}
