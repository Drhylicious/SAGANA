import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The database is the final authority on what an Officer may change: the gate
/// (supabase_schema_officer_permissions_02_enforcement.sql) refuses a write in a
/// module where the Officer is View Only, and the table policies and functions
/// refuse the rest. The app's own guards only keep the screens honest.
///
/// This test keeps the two from drifting apart:
///   1. Every database write the app can make (an RPC call, or an insert /
///      update / delete / upsert on a table) is either governed by the gate or
///      accounted for below, with the reason. A new write nobody classified
///      fails here, so it cannot reach an Officer unnoticed.
///   2. Each admin screen guards its actions with the module that owns it.
///
/// It reads the SQL and the Dart source; it needs no database.
void main() {
  String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

  // kind:name -> module, from the INSERT in script 02, less what script 11
  // later removed (Broadcast is open to every Officer).
  final mapped = <String, String>{
    // Script 21 adds reverse_capital_contribution under Members.
    for (final script in [
      'supabase_schema/supabase_schema_officer_permissions_02_enforcement.sql',
      'supabase_schema/supabase_schema_officer_permissions_21_contribution_reversal.sql',
      // Phase 3 registers the three outcome actions under Dashboard.
      'supabase_schema/supabase_schema_program_rework_p3_outcome_workflow.sql',
      // Phase 5 registers complete_program under Dashboard.
      'supabase_schema/supabase_schema_program_rework_p5_completion_rules.sql',
      // Proposal 12 registers the return and resolution actions under Dashboard.
      'supabase_schema/supabase_schema_program_rework_p6_harvest_return_resolutions.sql',
      // Phase 6 registers assistance review under Loans.
      'supabase_schema/supabase_schema_program_rework_p7_failed_program_assistance.sql',
      // p18 registers the outcome-report reminder (remind_program_report) under Dashboard.
      'supabase_schema/supabase_schema_program_rework_p18_report_reminders.sql',
      // Unified purchasing: Cooperative orders, allocation (m04) and the Marketplace payment steps (m05).
      'supabase_schema/supabase_schema_unify_m04_cooperative_order_engine.sql',
      'supabase_schema/supabase_schema_unify_m05_marketplace_payment_place_order.sql',
      // m07 adds the separate Pickup switch (Manager-only function, registered under Marketplace).
      'supabase_schema/supabase_schema_unify_m07_pickup_switch_location_guards.sql',
      // 22 registers the shelf-life, crop-request and newer program actions under Dashboard.
      'supabase_schema/supabase_schema_officer_permissions_22_shelf_life_and_program_actions.sql',
    ])
      for (final m in RegExp(r"\('(table|rpc)',\s*'(\w+)',\s*'(\w+)'\)").allMatches(read(script)))
        '${m.group(1)}:${m.group(2)}': m.group(3)!,
  }..removeWhere((key, _) => {
      'rpc:send_broadcast',
      'table:broadcast_logs',
    }.contains(key));

  /// Every write target named in a repository (rpc:name or table:name).
  Map<String, Set<String>> writesByRepository() {
    final out = <String, Set<String>>{};
    final dir = Directory('lib/data/repositories');
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync().replaceAll('\r\n', '\n');
      final found = <String>{
        for (final m in RegExp(r"\.rpc\(\s*'(\w+)'").allMatches(src)) 'rpc:${m.group(1)}',
        for (final m in RegExp(r"\.from\(\s*'(\w+)'\s*\)\s*\.(insert|update|delete|upsert)\b").allMatches(src))
          'table:${m.group(1)}',
      };
      if (found.isNotEmpty) out[f.uri.pathSegments.last] = found;
    }
    return out;
  }

  // ── What is NOT governed by the gate, and why ──────────────────────────────

  /// Done by a Farmer, a Buyer or a signed-in person to their OWN records (or a
  /// public read). The gate only ever applies to Officers, and none of this is
  /// something staff do for the cooperative.
  const ownOrPublic = <String>{
    // public reads
    'rpc:public_marketplace_listings', 'rpc:public_listed_crop_names',
    'rpc:public_latest_prices', 'rpc:public_price_trend',
    // Buyer
    'rpc:place_order', 'rpc:cancel_my_order', 'rpc:confirm_order_received',
    'table:buyer_profiles', 'table:buyer_profile_activity', 'table:buyer_addresses',
    // own contact e-mail, own profile, own notifications
    'rpc:promote_contact_email', 'rpc:set_pending_contact_email', 'rpc:verify_contact_email',
    'table:user_information', 'table:notifications',
    // Farmer: own harvest, crops, expenses, profile, activity feeds
    'table:harvest_records', 'table:inventory_batches', 'table:farmer_crops',
    'table:farmer_crop_activity', 'table:farmer_home_activity', 'table:farmer_expenses',
    'table:farmer_profiles', 'table:farmer_profile_activity',
    'rpc:record_informal_sale', 'rpc:update_batch_available_quantity',
    'rpc:get_my_marketplace_buyer_names',
    // Farmer: own listings
    'rpc:create_listing_with_reservation', 'rpc:update_my_listing', 'rpc:request_listing_edit',
    'rpc:cancel_listing_edit_request', 'rpc:get_my_listing_edit_requests',
    'rpc:get_my_listing_history', 'rpc:withdraw_listing', 'rpc:delete_listing',
    // Farmer: own loan requests, offers, market linking, programs, payout request
    'rpc:list_loanable_items', 'rpc:get_my_loan_requests', 'rpc:submit_loan_request',
    'rpc:cancel_loan_request', 'rpc:offer_batch_to_cooperative', 'rpc:deliver_cooperative_offer',
    'rpc:request_market_linking_cancellation', 'rpc:submit_ginger_for_sale',
    'rpc:acknowledge_da_amad_enrollment', 'rpc:submit_da_amad_enrollment',
    'rpc:submit_program_enrollment_request',
    // Farmer: orders a Cooperative Product, delivery quote and group, confirms receipt (all their own)
    'rpc:place_program_order', 'rpc:confirm_program_order_received',
    'rpc:create_checkout_group', 'rpc:get_delivery_quote',
    // reads for every signed-in role: the cooperative's own details and whether Delivery is on
    'rpc:get_cooperative_details', 'rpc:get_delivery_status',
    'rpc:request_payout_decision',
    'rpc:get_my_activity_share', // read: only the caller's own two percentages
    'rpc:get_my_outcome_reports', // read: the Farmer's own outcome reports; no staff identity
    'rpc:submit_program_outcome_report', // a Farmer files their own outcome report
    'rpc:request_program_redistribution', // a Farmer asks for another item after their own failed outcome
    // Farmer: their own harvest batches (still good / rotten) and the price rule of their own batch
    'rpc:confirm_batch_still_good', 'rpc:report_batch_rotten', 'rpc:get_listing_price_rule',
    // The daily shelf-life pass, also run when a screen opens. Idempotent; it acts on dates only.
    'rpc:process_shelf_life',
  };

  /// Staff can do these and the gate does not stop a View Only Officer, on
  /// purpose: they read, or write only the signed-in person's own audit rows.
  const staffOpenOnPurpose = <String>{
    'rpc:get_officer_permissions', // read
    'rpc:get_program_returns', 'rpc:get_failed_resolutions', // reads: staff only, checked inside the function
    'rpc:get_assistance_requests', // read: staff only, checked inside the function
    'rpc:get_my_assistance_options', 'rpc:get_my_assistance_requests', // reads: the Farmer's own, no staff identity
    'rpc:submit_assistance_request', 'rpc:cancel_my_assistance_request', // a Farmer asks for / cancels their own request
    'rpc:get_program_product_stats', // read: buyers and quantity sold per product, totals only (no names or prices)
    'rpc:get_my_program_returns', // read: the Farmer's own returns and the plain status of their failed outcomes
    'rpc:get_programs_completion_status', // read: which active programs are ready to complete; staff only, checked inside the function
    'rpc:get_program_history', // read: one program's accountability history; staff only, checked inside the function
    'rpc:get_program_outcome_reports', // read: outcome reports with photos and who did what; staff only, checked inside the function
    'rpc:preview_broadcast_recipients', // a count
    'rpc:get_manager_sign_in_emails', // read: Manager accounts' e-mail for Manage Accounts (script 19)
    // Broadcast is a primary screen (top bar): every Officer can send and schedule,
    // whatever their module access. Accountability, not permission: the audit
    // trigger on broadcast_logs records who made each one (script 05).
    'rpc:send_broadcast', 'table:broadcast_logs',
    'table:admin_activity_log', // own audit rows only (policy: admin_id = auth.uid(), source = 'app')
    // Runs when the Loans screens open (marks loans past their grace period
    // overdue); staff-only in the database. Governing it would break opening
    // Loans for a View Only Officer.
    'rpc:transition_overdue_loans',
    // Sends the inspection notices that are due when Inventory opens; idempotent, changes no stock.
    'rpc:process_cooperative_shelf_life',
    'rpc:get_price_update_required_listings', // read: listings priced outside their Reference Price
    'rpc:get_supply_chain_records', 'rpc:get_supply_chain_totals', // reads: the Supply Chain tracking view
  };

  /// Staff screens that only the Manager can use, refused by the database itself
  /// (the function checks the role, or the table policy excludes Officers).
  const managerOnlyInDatabase = <String>{
    'rpc:confirm_payout_decision', 'rpc:reject_payout_decision', // Balik-Tangkilik
    'table:cooperative_annual_totals', 'table:member_contributions', // Balik-Tangkilik
    // Cooperative Details and Delivery Settings: the functions check is_manager(); an Officer only reads.
    'rpc:save_cooperative_details', 'rpc:verify_cooperative_contact',
    'rpc:save_delivery_fee_bands', 'rpc:set_delivery_enabled',
  };

  group('every database write the app can make is accounted for', () {
    test('the mapping was read (script 02, less script 11)', () {
      expect(mapped.length, greaterThan(70));
      // Script 11 removes exactly these two rows; the test above removes them
      // by name, so keep the two in step.
      final s11 = read('supabase_schema/supabase_schema_officer_permissions_11_broadcast_open.sql');
      expect(s11, contains("name = 'send_broadcast'"));
      expect(s11, contains("name = 'broadcast_logs'"));
      const modules = {'dashboard', 'members', 'marketplace', 'loans', 'reports'};
      expect(mapped.values.toSet().difference(modules), isEmpty, reason: 'only the five Officer modules');
    });

    test('each write is governed by the gate, or listed above with its reason', () {
      final accounted = {...mapped.keys, ...ownOrPublic, ...staffOpenOnPurpose, ...managerOnlyInDatabase};
      final unaccounted = <String>[];
      writesByRepository().forEach((file, targets) {
        for (final t in targets.where((t) => !accounted.contains(t))) {
          unaccounted.add('$file -> $t');
        }
      });
      expect(
        unaccounted,
        isEmpty,
        reason: 'A write the gate does not govern and nobody classified. Either add it to '
            'staff_permission_targets (script 02) with its module, or list it in this test '
            'with the reason it is safe:\n${unaccounted.join('\n')}',
      );
    });

    test('the lists above hold no stale or contradictory entries', () {
      final used = writesByRepository().values.expand((s) => s).toSet();
      for (final entry in {...ownOrPublic, ...staffOpenOnPurpose, ...managerOnlyInDatabase}) {
        expect(mapped.containsKey(entry), isFalse, reason: '$entry is governed by the gate; remove it from the list');
        expect(used.contains(entry), isTrue, reason: '$entry is no longer written by any repository; remove it from the list');
      }
    });

    test('the Manager-only Balik targets are not given to any Officer module', () {
      for (final t in managerOnlyInDatabase) {
        expect(mapped.containsKey(t), isFalse, reason: t);
      }
      expect(mapped.keys.where((k) => RegExp('balik|patronage|payout|annual_totals').hasMatch(k)), isEmpty);
    });
  });

  group('each admin screen guards its actions with the module that owns it', () {
    // The module whose Manage access each screen's guards check. A screen is
    // listed once, with every module it may use.
    const expected = <String, Set<String>>{
      'lib/presentation/screens/admin/admin_inventory_screen.dart': {'dashboard'},
      'lib/presentation/screens/admin/crop_management_screen.dart': {'dashboard'},
      'lib/presentation/screens/admin/crop_request_approval_screen.dart': {'dashboard'},
      'lib/presentation/screens/admin/loan_item_management_screen.dart': {'dashboard'},
      'lib/presentation/screens/admin/price_management_screen.dart': {'dashboard'},
      'lib/presentation/screens/admin/program_enrollment_requests_screen.dart': {'dashboard'},
      'lib/presentation/screens/admin/program_management_screen.dart': {'dashboard'},
      'lib/presentation/screens/admin/program_outcome_detail_screen.dart': {'dashboard'},
      'lib/presentation/screens/admin/program_products_screen.dart': {'dashboard'},
      'lib/presentation/widgets/assistance_request_card.dart': {'loans'},
      'lib/presentation/screens/admin/farmer_details_screen.dart': {'members'},
      'lib/presentation/screens/admin/farmer_management_screen.dart': {'members'}, // plus the loan actions (variable)
      'lib/presentation/screens/admin/manage_accounts_screen.dart': {'members'},
      'lib/presentation/screens/admin/admin_order_detail_screen.dart': {'marketplace'},
      'lib/presentation/screens/admin/admin_program_order_detail_screen.dart': {'marketplace'},
      'lib/presentation/screens/admin/all_listings_screen.dart': {'marketplace'},
      'lib/presentation/screens/admin/da_amad_enrollment_screen.dart': {'marketplace'},
      'lib/presentation/screens/admin/listing_edit_request_screen.dart': {'marketplace'},
      'lib/presentation/screens/admin/listing_review_screen.dart': {'marketplace'},
      'lib/presentation/screens/admin/market_linking_screen.dart': {'marketplace'},
      'lib/presentation/screens/shared/coop_offer_negotiation_screen.dart': {'marketplace'},
      'lib/presentation/screens/admin/loan_dashboard_screen.dart': {'loans'},
      'lib/presentation/screens/admin/loan_details_screen.dart': {'loans'},
      'lib/presentation/screens/admin/loan_requests_screen.dart': {'loans'},
      'lib/presentation/screens/admin/export_center_screen.dart': {'reports'},
    };

    Set<String> used(String src) => {
      for (final m in RegExp(r'requireManage\(\s*(?:context|ctx),\s*StaffModule\.(\w+)\)').allMatches(src))
        m.group(1)!,
      for (final m in RegExp(r'canManageModule\(\s*StaffModule\.(\w+)\)').allMatches(src)) m.group(1)!,
    };

    test('every guarded screen is listed, and no screen uses another module', () {
      final guardedFiles = <String>[];
      for (final dir in ['lib/presentation/screens/admin', 'lib/presentation/screens/shared']) {
        for (final f in Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
          if (used(f.readAsStringSync()).isNotEmpty) {
            guardedFiles.add(f.path.replaceAll('\\', '/'));
          }
        }
      }
      expect(guardedFiles.toSet().difference(expected.keys.toSet()), isEmpty,
          reason: 'a screen guards actions but is not listed here with its module');
      for (final entry in expected.entries) {
        final actual = used(read(entry.key));
        expect(actual, isNotEmpty, reason: '${entry.key} has no guard');
        expect(actual.difference(entry.value), isEmpty, reason: '${entry.key} guards with the wrong module');
      }
    });

    test('Members screens that start a loan action check the Loans module', () {
      final src = read('lib/presentation/screens/admin/farmer_management_screen.dart');
      expect(src, contains("const loanActions = {'payment', 'issueLoan'};"));
      expect(src, contains('? StaffModule.loans'));
    });
  });
}
