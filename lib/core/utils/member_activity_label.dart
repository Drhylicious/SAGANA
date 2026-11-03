import 'package:intl/intl.dart';

import '../../data/models/activity_text.dart';
import '../../data/models/admin_legacy_generated.dart';
import '../../data/models/staff_action_model.dart';
import '../../data/services/staff_permission_service.dart';
import '../../presentation/widgets/staff_access_matrix.dart';
import '../l10n/app_localizations.dart';

/// A plain sentence for a Members-tab action in the staff accountability
/// logbook, e.g. "Suspended Nora Five". The logbook rows come from database
/// triggers and describe a change to a table ("Updated user roles: Nora Five");
/// this reads the table, the operation and the changed columns and says what the
/// person actually did, to whom. Who did it and when are shown beside it.
///
/// Returns null for a row it does not recognise; the screen then shows the
/// database's own description, so nothing is ever hidden.
String? memberActionHeadline(StaffActionEntry e, AppLocalizations l10n) {
  if (e.module != 'members') return null;
  final who = (e.reference ?? '').trim();
  final name = who.isEmpty ? '—' : who;
  final before = e.oldValues ?? const <String, dynamic>{};
  final after = e.newValues ?? const <String, dynamic>{};

  switch (e.tableName) {
    case 'user_roles':
      switch (e.operation) {
        case 'created':
          if (after['role'] == 'officer') return l10n.staffActCreatedOfficer(name);
          if (after['role'] == 'farmer') return l10n.staffActCreatedFarmer(name);
          return null;
        case 'deleted':
          return l10n.staffActDeletedAccount(name);
        case 'updated':
          if (after.containsKey('status')) {
            final from = before['status'];
            final to = after['status'];
            if (to == 'suspended') return l10n.staffActSuspended(name);
            if (to == 'active' && from == 'suspended') return l10n.staffActReactivated(name);
            if (to == 'active' && from == 'pending') return l10n.staffActApproved(name);
            if (to == 'rejected') return l10n.staffActDisapproved(name);
            return null;
          }
          if (after['must_change_password'] == true) return l10n.staffActPasswordReset(name);
          return null;
      }
      return null;

    case 'capital_contribution_events':
      if (e.operation != 'created') return null;
      final amount = num.tryParse('${after['amount']}');
      if (amount == null) return null;
      String money(num v) => '₱${NumberFormat('#,##0.00').format(v)}';
      if (after['reverses_event_id'] != null) {
        return l10n.staffActContributionReversed(money(amount.abs()), name);
      }
      return l10n.staffActContribution(money(amount), name);

    case 'officer_permissions':
      final module = StaffModule.fromKey(after['module'] as String?);
      final level = StaffAccess.fromKey(after['access_level'] as String?);
      if (module == null) return null;
      return l10n.staffActAccessChanged(
        name,
        staffModuleLabel(l10n, module),
        level == StaffAccess.manage ? l10n.staffAccessManage : l10n.staffAccessView,
      );

    case 'password_reset_requests':
      return e.operation == 'updated' ? l10n.staffActPasswordRequest(name) : null;

    case 'user_information':
    case 'farmer_profiles':
      return e.operation == 'updated' ? l10n.staffActInfoEdited(name) : null;
  }
  return null;
}

/// The reason or note that goes with an action, as a ready-to-show line: the
/// reason given when a member was suspended or disapproved, or the note on a
/// contribution. Null when there is none.
String? memberActionDetail(StaffActionEntry e, AppLocalizations l10n) {
  if (e.module != 'members') return null;
  final after = e.newValues ?? const <String, dynamic>{};
  String? text(String key) {
    final v = after[key];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  if (e.tableName == 'user_roles') {
    final reason = text('rejection_reason') ?? text('suspension_reason');
    return reason == null ? null : l10n.staffActReason(reason);
  }
  if (e.tableName == 'capital_contribution_events') {
    final reason = text('reversal_reason');
    if (reason != null) return l10n.staffActReason(reason);
    final note = text('note');
    return note == null ? null : l10n.staffActNote(note);
  }
  return null;
}

/// What each audited table is called inside a sentence ("Changed price: Tomato").
String? staffThingLabel(AppLocalizations l10n, String? table) {
  switch (table) {
    case 'cooperative_inventory':
      return l10n.staffThingCooperativeInventory;
    case 'inventory_transactions':
      return l10n.staffThingInventoryTransactions;
    case 'inventory_categories':
      return l10n.staffThingInventoryCategories;
    case 'units':
      return l10n.staffThingUnits;
    case 'crop_master':
      return l10n.staffThingCropMaster;
    case 'crop_categories':
      return l10n.staffThingCropCategories;
    case 'crop_requests':
      return l10n.staffThingCropRequests;
    case 'cooperative_programs':
      return l10n.staffThingCooperativePrograms;
    case 'program_activities':
      return l10n.staffThingProgramActivities;
    case 'program_members':
      return l10n.staffThingProgramMembers;
    case 'program_products':
      return l10n.staffThingProgramProducts;
    case 'program_product_purchases':
      return l10n.staffThingProgramProductPurchases;
    case 'program_enrollment_requests':
      return l10n.staffThingProgramEnrollmentRequests;
    case 'price_records':
      return l10n.staffThingPriceRecords;
    case 'loan_items_master':
      return l10n.staffThingLoanItemsMaster;
    case 'user_roles':
      return l10n.staffThingUserRoles;
    case 'user_information':
      return l10n.staffThingUserInformation;
    case 'farmer_profiles':
      return l10n.staffThingFarmerProfiles;
    case 'password_reset_requests':
      return l10n.staffThingPasswordResetRequests;
    case 'account_creation_requests':
      return l10n.staffThingAccountCreationRequests;
    case 'capital_contribution_events':
      return l10n.staffThingCapitalContributionEvents;
    case 'member_capital_shares':
      return l10n.staffThingMemberCapitalShares;
    case 'officer_permissions':
      return l10n.staffThingOfficerPermissions;
    case 'marketplace_listings':
      return l10n.staffThingMarketplaceListings;
    case 'listing_edit_requests':
      return l10n.staffThingListingEditRequests;
    case 'orders':
      return l10n.staffThingOrders;
    case 'cooperative_purchase_offers':
      return l10n.staffThingCooperativePurchaseOffers;
    case 'member_sales_transactions':
      return l10n.staffThingMemberSalesTransactions;
    case 'market_linking_programs':
      return l10n.staffThingMarketLinkingPrograms;
    case 'market_linking_sales':
      return l10n.staffThingMarketLinkingSales;
    case 'da_amad_enrollments':
      return l10n.staffThingDaAmadEnrollments;
    case 'farmer_loans':
      return l10n.staffThingFarmerLoans;
    case 'farmer_loan_payments':
      return l10n.staffThingFarmerLoanPayments;
    case 'loan_requests':
      return l10n.staffThingLoanRequests;
    case 'loan_policy_settings':
      return l10n.staffThingLoanPolicySettings;
    case 'cooperative_annual_totals':
      return l10n.staffThingCooperativeAnnualTotals;
    case 'member_contributions':
      return l10n.staffThingMemberContributions;
    case 'broadcast_logs':
      return l10n.staffThingBroadcastLogs;
  }
  return null;
}

/// The sentence for ANY row of the log: the specific Members wording where there
/// is one, otherwise "Added / Changed / Deleted <thing>: <record>" in the current
/// language, the BOD reminder line for the system, and the app's own text for an
/// export. Falls back to the database's description, so nothing is ever hidden.
String staffActionHeadline(StaffActionEntry e, AppLocalizations l10n) {
  final specific = memberActionHeadline(e, l10n);
  if (specific != null) return specific;

  if (e.module == 'system') {
    final v = e.newValues ?? const <String, dynamic>{};
    final meeting = DateTime.tryParse('${v['meeting_date']}');
    if (meeting != null) {
      String date;
      try {
        date = DateFormat.yMMMMd(l10n.localeName).format(meeting);
      } catch (_) {
        date = '${meeting.year}-${meeting.month.toString().padLeft(2, '0')}-${meeting.day.toString().padLeft(2, '0')}';
      }
      return l10n.staffActBodReminder(
        date,
        num.tryParse('${v['farmers']}')?.toInt() ?? 0,
        num.tryParse('${v['staff']}')?.toInt() ?? 0,
      );
    }
    return e.description;
  }

  // Written by the app (a report export): no table; the stored English text is
  // translated from its key.
  if (e.tableName == null) {
    final message = parseLegacyAdminLog(e.description);
    return message == null ? e.description : renderActivityMessage(l10n, message);
  }

  final thing = staffThingLabel(l10n, e.tableName);
  if (thing == null) return e.description;
  final ref = (e.reference ?? '').trim();
  switch (e.operation) {
    case 'created':
      return ref.isEmpty ? l10n.staffActGenericAddedNoRef(thing) : l10n.staffActGenericAdded(thing, ref);
    case 'deleted':
      return ref.isEmpty ? l10n.staffActGenericDeletedNoRef(thing) : l10n.staffActGenericDeleted(thing, ref);
    default:
      return ref.isEmpty ? l10n.staffActGenericChangedNoRef(thing) : l10n.staffActGenericChanged(thing, ref);
  }
}

/// The line under the sentence: the Members reason or note, or for any other
/// update that moved a status, "Status: pending → approved".
String? staffActionDetail(StaffActionEntry e, AppLocalizations l10n) {
  final specific = memberActionDetail(e, l10n);
  if (specific != null) return specific;
  if (e.operation == 'updated') {
    final before = e.oldValues ?? const <String, dynamic>{};
    final after = e.newValues ?? const <String, dynamic>{};
    if (after['status'] != null && before['status'] != after['status']) {
      return l10n.staffLogStatusChange('${before['status'] ?? '—'}', '${after['status']}');
    }
  }
  return null;
}
