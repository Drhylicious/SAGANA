import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/buyer_activity_model.dart';
import '../../data/models/dashboard_summary_model.dart';
import '../../data/models/admin_dashboard_model.dart';
import '../../routes/app_routes.dart';
import 'member_access.dart';

/// Where tapping a Recent Activity record goes, so every record opens the screen
/// that shows it. Recent Activity is the history of what the user already did;
/// the destination is where that thing lives today (the order, the offer, the
/// list the record belongs to).

/// Farmer Recent Activity: opens the screen for the record.
void openFarmerActivity(BuildContext context, ActivityItem item) {
  switch (item.type) {
    case ActivityType.harvest:
      context.push(AppRoutes.harvestHistory);
    case ActivityType.listing:
      context.push(AppRoutes.myListings);
    case ActivityType.orderPlaced:
      // The Farmer's own Marketplace purchase: its order details.
      context.push(AppRoutes.farmerOrderDetail, extra: item.id);
    case ActivityType.cropRequest:
    case ActivityType.cropAdded:
    case ActivityType.cropPhotoUpdated:
      context.push(AppRoutes.cropListing);
    case ActivityType.informalSale:
      context.push(AppRoutes.myTransactionHistory);
    case ActivityType.cooperativeOffer:
      context.push(AppRoutes.farmerCoopOfferDetail, extra: item.id);
    case ActivityType.marketLinkingEnrollment:
    case ActivityType.gingerBatchSubmission:
      context.push(AppRoutes.myMarketLinking);
    case ActivityType.profile:
      context.push(AppRoutes.farmerEditProfile);
    case ActivityType.addressUpdated:
      context.push(AppRoutes.farmerProfile);
    case ActivityType.expenseAdded:
      context.push(AppRoutes.myExpenses);
    case ActivityType.programEnrollment:
      context.push(AppRoutes.myProgramsEnrolled);
    case ActivityType.programPurchase:
      context.push(AppRoutes.farmerMyOrders);
    case ActivityType.capitalReinvestment:
      context.push(AppRoutes.benefitsTracking);
    case ActivityType.listingEditRequested:
      context.push(AppRoutes.myListings);
    case ActivityType.quantityAdjusted:
    case ActivityType.shelfLifeChecked:
    case ActivityType.produceRotten:
      context.push(AppRoutes.manageInventory);
    case ActivityType.loanRequested:
      context.push(AppRoutes.myLoanRequests);
    case ActivityType.outcomeReported:
      context.push(AppRoutes.myProgramsEnrolled);
    case ActivityType.assistanceRequested:
      context.push(AppRoutes.myProgramsEnrolled);
    case ActivityType.syncCompleted:
      context.go(AppRoutes.farmerDashboard);
  }
}

/// Buyer Recent Activity: an order opens that order's details; a profile entry
/// opens the screen it changed.
void openBuyerActivity(BuildContext context, BuyerActivityItem item) {
  if (item.type == BuyerActivityType.order) {
    context.push(AppRoutes.orderDetail, extra: item.id);
    return;
  }
  switch (item.messageKey) {
    case 'activityAddressAdded':
    case 'activityAddressDeleted':
    case 'activityAddressDefault':
    case 'activityAddressUpdated':
      context.push(AppRoutes.myAddresses);
    case 'activityPasswordChanged':
      context.push(AppRoutes.buyerSettings);
    default:
      context.push(AppRoutes.buyerEditProfile);
  }
}

/// Manager/Officer Recent Activity rows written by the app (admin_activity_log):
/// opens the screen of the module the action belonged to. A row that carries
/// the id of its record (a loan, a farmer) is opened by the caller first.
void openLoggedAdminActivity(BuildContext context, AdminActivityItem item) {
  switch (item.sourceModule) {
    case 'inventory':
      context.push(AppRoutes.adminInventory);
    case 'crops':
      context.push(AppRoutes.cropManagement);
    case 'programs':
      context.push(AppRoutes.programManagement);
    case 'loans':
      context.push(AppRoutes.loanItemManagement);
    case 'prices':
      context.push(AppRoutes.priceManagement);
    case 'market_linking':
      context.push(AppRoutes.marketLinking);
    case 'offers':
      context.push(AppRoutes.offerToCooperative);
    case 'broadcast':
      context.push(AppRoutes.broadcastHistory);
    case 'profile':
      context.push(AppRoutes.adminProfile);
    case 'listings':
      // A reviewed listing opens that listing; an edit decision (no record id)
      // opens the listings.
      if (item.referenceId != null &&
          item.actionType != null &&
          item.actionType!.startsWith('edit_') == false) {
        context.push(AppRoutes.listingReview, extra: item.referenceId);
      } else {
        context.push(AppRoutes.allListings);
      }
    case 'orders':
      // The order the action was done on. Cooperative product orders (Farmer
      // purchases from the cooperative) have their own details screen.
      if (item.referenceId != null) {
        final coop =
            item.actionType != null &&
            item.actionType!.startsWith('coop_order');
        context.push(
          coop ? AppRoutes.adminProgramOrderDetail : AppRoutes.adminOrderDetail,
          extra: item.referenceId,
        );
      } else {
        context.push(AppRoutes.adminOrders);
      }
    case 'marketplace':
      final a = item.actionType ?? '';
      context.push(
        a == 'cooperative_details' || a == 'contact_verified'
            ? AppRoutes.adminCooperativeDetails
            : AppRoutes.adminDeliverySettings,
      );
    case 'members':
      if (item.referenceId != null) {
        pushFarmerDetails(context, item.referenceId);
      } else {
        goMembersList(context);
      }
    case 'reports':
      context.push(AppRoutes.operationalReports);
    case 'system':
    default:
      context.push(AppRoutes.staffAccountability);
  }
}
