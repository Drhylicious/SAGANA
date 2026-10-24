import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Accent colour for a stored order status ('pending' | 'approved' |
/// 'completed' | 'cancelled' | 'rejected'). Shared by Buyer, Farmer and Admin
/// order screens so one status reads the same colour everywhere.
/// Cancelled and rejected both use the error red: each is an order that will
/// not be fulfilled.
Color orderStatusColor(String status) {
  switch (status) {
    case 'pending':
      return AppConstants.warningAmber;
    case 'approved':
      return AppConstants.successGreen;
    case 'completed':
      return AppConstants.primaryGreen;
    case 'cancelled':
    case 'rejected':
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
    case 'completed':
      return l10n.buyerOrdersStatusCompleted;
    case 'cancelled':
      return l10n.buyerOrdersStatusCancelled;
    case 'rejected':
      return l10n.orderStatusRejected;
    default:
      return status.toUpperCase();
  }
}
