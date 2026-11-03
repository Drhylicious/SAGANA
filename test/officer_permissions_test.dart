import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/utils/db_error_utils.dart';
import 'package:sagana/data/models/account_source_model.dart';
import 'package:sagana/data/models/staff_action_model.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/data/services/staff_permission_service.dart';
import 'package:sagana/presentation/navigation/app_router.dart';
import 'package:sagana/presentation/widgets/staff_access_matrix.dart';
import 'package:sagana/presentation/widgets/view_only_banner.dart';
import 'package:sagana/routes/app_routes.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    final dir = Directory.systemTemp.createTempSync('sagana_officer_perms');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    await HiveService.init();
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-key',
    );
    await HiveService.saveUserSession(
      userId: 'officer-1',
      email: 'o@x.y',
      role: 'officer',
    );
  });

  void ftest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) => runIgnoringFontErrors(() => body(tester)));

  group('StaffPermissions.parse', () {
    test('reads the object get_my_staff_permissions returns', () {
      final parsed = StaffPermissions.parse({
        'dashboard': 'manage',
        'members': 'view',
        'marketplace': 'view',
        'loans': 'manage',
        'reports': 'view',
      });
      expect(parsed[StaffModule.dashboard], StaffAccess.manage);
      expect(parsed[StaffModule.members], StaffAccess.view);
      expect(parsed[StaffModule.loans], StaffAccess.manage);
      expect(parsed.length, 5);
    });

    test('ignores unknown modules and treats anything but manage as view', () {
      final parsed = StaffPermissions.parse({
        'dashboard': 'manage',
        'nonsense': 'manage',
        'loans': 'admin',
        'reports': null,
      });
      expect(parsed.containsKey(StaffModule.dashboard), isTrue);
      expect(parsed[StaffModule.loans], StaffAccess.view);
      expect(parsed[StaffModule.reports], StaffAccess.view);
      expect(parsed.length, 3);
    });

    test('a non-object result is no permissions at all', () {
      expect(StaffPermissions.parse(null), isEmpty);
      expect(StaffPermissions.parse('manage'), isEmpty);
    });
  });

  group('module keys match the database', () {
    test('the five module keys are the officer_permissions CHECK values', () {
      expect(StaffModule.values.map((m) => m.key).toList(), [
        'dashboard',
        'members',
        'marketplace',
        'loans',
        'reports',
      ]);
      expect(StaffAccess.manage.key, 'manage');
      expect(StaffAccess.view.key, 'view');
    });
  });

  group('who may manage what', () {
    tearDown(() async {
      StaffPermissions.instance.debugSet(const {});
      await HiveService.saveUserSession(
        userId: 'officer-1',
        email: 'o@x.y',
        role: 'officer',
      );
    });

    test('an Officer is View Only until a module is granted Manage', () {
      StaffPermissions.instance.debugSet({
        StaffModule.dashboard: StaffAccess.manage,
      });
      expect(StaffPermissions.instance.canManage(StaffModule.dashboard), isTrue);
      expect(StaffPermissions.instance.canManage(StaffModule.members), isFalse);
      expect(StaffPermissions.instance.canManage(StaffModule.loans), isFalse);
      // Every Officer can still open and read every module.
      for (final m in StaffModule.values) {
        expect(StaffPermissions.instance.canView(m), isTrue);
      }
    });

    test('a missing or unreadable level never falls back to Manage', () {
      StaffPermissions.instance.debugSet(const {});
      for (final m in StaffModule.values) {
        expect(StaffPermissions.instance.levelFor(m), StaffAccess.view);
      }
    });

    test('the Manager manages every module whatever is stored', () async {
      await HiveService.saveUserSession(
        userId: 'manager-1',
        email: 'm@x.y',
        role: 'admin',
      );
      StaffPermissions.instance.debugSet(const {});
      for (final m in StaffModule.values) {
        expect(StaffPermissions.instance.canManage(m), isTrue);
      }
    });

    test('asJson is the map the RPCs take', () {
      StaffPermissions.instance.debugSet({
        StaffModule.reports: StaffAccess.manage,
      });
      expect(StaffPermissions.instance.asJson, {
        'dashboard': 'view',
        'members': 'view',
        'marketplace': 'view',
        'loans': 'view',
        'reports': 'manage',
      });
    });
  });

  group('router', () {
    test('screens that only make changes need Manage in their module', () {
      expect(AppRouter.manageOnlyPaths, {
        AppRoutes.addNewMember: StaffModule.members,
        AppRoutes.issueNewLoan: StaffModule.loans,
        AppRoutes.recordPayment: StaffModule.loans,
      });
    });
  });

  group('database refusal message', () {
    test('the gate message is shown to the Officer as written', () {
      const message =
          'Your Officer account has view-only access to the loans module. '
          'Ask the Manager to give you Manage access.';
      expect(
        readableDatabaseMessage(
          const PostgrestException(message: message, code: '42501'),
        ),
        message,
      );
    });

    test('another permission error stays technical', () {
      expect(
        readableDatabaseMessage(
          const PostgrestException(
            message: 'permission denied for table x',
            code: '42501',
          ),
        ),
        isNull,
      );
    });
  });

  group('StaffAccessMatrix', () {
    ftest('shows every module and reports a change', (tester) async {
      final value = {for (final m in StaffModule.values) m: StaffAccess.view};
      StaffModule? changedModule;
      StaffAccess? changedTo;

      await tester.pumpWidget(
        _host(
          StaffAccessMatrix(
            value: value,
            onChanged: (m, a) {
              changedModule = m;
              changedTo = a;
            },
          ),
        ),
      );

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Members'), findsOneWidget);
      expect(find.text('Loans'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('View Only'), findsNWidgets(5));

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('access-dashboard')),
          matching: find.text('Manage'),
        ),
      );
      await tester.pump();

      expect(changedModule, StaffModule.dashboard);
      expect(changedTo, StaffAccess.manage);
    });
  });

  group('View Only strip', () {
    tearDown(() => StaffPermissions.instance.debugSet(const {}));

    ftest('appears for a View Only module and not for a managed one', (
      tester,
    ) async {
      // No signed-in user in a unit test: an unknown role is not a Manager, so
      // the loaded levels decide.
      StaffPermissions.instance.debugSet({
        StaffModule.members: StaffAccess.view,
        StaffModule.loans: StaffAccess.manage,
      });

      await tester.pumpWidget(
        _host(
          const Column(
            children: [
              ViewOnlyStrip(module: StaffModule.members),
              ViewOnlyStrip(module: StaffModule.loans),
            ],
          ),
        ),
      );

      expect(find.text('Members · View Only'), findsOneWidget);
      expect(find.text('Loans · View Only'), findsNothing);

      // The strip follows a live permission change.
      StaffPermissions.instance.debugSet({
        StaffModule.members: StaffAccess.manage,
        StaffModule.loans: StaffAccess.view,
      });
      await tester.pump();
      expect(find.text('Members · View Only'), findsNothing);
      expect(find.text('Loans · View Only'), findsOneWidget);
    });

    test('canManageModule defaults to View Only when nothing is loaded', () {
      StaffPermissions.instance.debugSet(const {});
      expect(canManageModule(StaffModule.dashboard), isFalse);
    });
  });

  group('StaffActionEntry', () {
    test('lists the changed columns with before and after', () {
      final entry = StaffActionEntry.fromMap({
        'id': 'a1',
        'admin_id': 'u1',
        'actor_name': 'Maria Santos',
        'actor_role': 'officer',
        'module': 'prices',
        'operation': 'updated',
        'table_name': 'price_records',
        'record_id': 'r1',
        'reference_label': 'Tomato',
        'description': 'Updated price records: Tomato',
        'old_values': {'price_per_kg': 40},
        'new_values': {'price_per_kg': 45},
        'created_at': '2026-11-02T08:30:00Z',
      });

      expect(entry.staffName, 'Maria Santos');
      expect(entry.staffRole, 'officer');
      expect(entry.changes.length, 1);
      expect(entry.changes.first.column, 'price_per_kg');
      expect(entry.changes.first.before, 40);
      expect(entry.changes.first.after, 45);
    });

    test('a create has only new values', () {
      final entry = StaffActionEntry.fromMap({
        'id': 'a2',
        'module': 'crops',
        'action_type': 'created',
        'description': 'Created crop master: Ginger',
        'new_values': {'crop_name': 'Ginger'},
        'created_at': '2026-11-02T08:30:00Z',
      });

      expect(entry.operation, 'created');
      expect(entry.oldValues, isNull);
      expect(entry.changes.single.after, 'Ginger');
    });
  });

  group('Manager-only screens', () {
    test('Balik, Staff Accountability and creating an Officer stay with the Manager', () {
      expect(AppRouter.managerOnlyPaths, {
        AppRoutes.balikTangkilikManagement,
        AppRoutes.staffAccountability,
        AppRoutes.createOfficerAccount,
      });
    });
  });

  group('AccountSource', () {
    test('reads who created an applicant and when', () {
      final src = AccountSource.fromMap({
        'user_id': 'u2',
        'requested_by_name': 'Maria Santos',
        'requested_at': '2026-11-03T01:00:00Z',
      });
      expect(src.userId, 'u2');
      expect(src.createdByName, 'Maria Santos');
      expect(src.createdAt, DateTime.utc(2026, 11, 3, 1));
    });

    test('a missing name or date is empty, not an error', () {
      final src = AccountSource.fromMap({'user_id': 'u3'});
      expect(src.createdByName, isNull);
      expect(src.createdAt, isNull);
    });
  });

  group('the SQL scripts say what the rules require', () {
    // The script's code only: whole-line and trailing -- comments are removed,
    // so a rule explained in a comment cannot satisfy or break a check.
    String sql(String name) => File('supabase_schema/$name')
        .readAsLinesSync()
        .map((l) => l.replaceFirst(RegExp(r'--.*$'), ''))
        .join('\n');

    test('01: nothing is assigned automatically; only the agreed rules remain', () {
      final s = sql('supabase_schema_officer_permissions_01_foundation.sql');
      // No backfill: no rows are inserted into officer_permissions here.
      expect(RegExp(r'INSERT INTO public\.officer_permissions').hasMatch(s), isFalse);
      // The earlier guards are gone.
      expect(s.contains('CREATE OR REPLACE FUNCTION public.user_roles_staff_guard'), isFalse);
      expect(s.contains('Only the Manager can reset'), isFalse);
      expect(s.contains('You can only change access for modules you manage'), isFalse);
      // Kept: no role change from the app, and nobody edits their own access.
      expect(s, contains('trg_user_roles_no_role_change'));
      expect(s, contains('You cannot change your own access.'));
      // The approval history table is not opened to Officers.
      expect(s.contains("'member_status_events'"), isFalse);
    });

    test('02: Broadcast was first put under the Dashboard permission (script 11 opens it)', () {
      final s = sql('supabase_schema_officer_permissions_02_enforcement.sql');
      expect(s, contains("('rpc',   'send_broadcast',              'dashboard')"));
      expect(s, contains("('table', 'broadcast_logs',              'dashboard')"));
    });

    test('11: Broadcast is open to every Officer; only its two gate rows are removed', () {
      final s = sql('supabase_schema_officer_permissions_11_broadcast_open.sql');
      expect(RegExp(r'^\s*DELETE FROM public\.staff_permission_targets', multiLine: true).allMatches(s).length, 1);
      expect(s, contains("name = 'send_broadcast'"));
      expect(s, contains("name = 'broadcast_logs'"));
      // Nothing else is touched: no other target, no insert, no policy change.
      expect(s.contains('INSERT INTO'), isFalse);
      expect(s.contains('notify_price_update'), isFalse);
      expect(s.contains('POLICY'), isFalse);
    });

    test('08: the Officer is told the outcome without any Manager identity', () {
      final s = sql('supabase_schema_officer_permissions_08_farmer_creation_approval.sql');
      expect(s, contains("'The Farmer account you created was approved.'"));
      expect(s, contains("'The Farmer account you created was not approved. Reason: '"));
      expect(s.contains('approved by the Manager'), isFalse);
      // Both the Farmer and the creating Officer are notified of either outcome.
      expect(s, contains("'Membership Approved'"));
      expect(s, contains("'Application Disapproved'"));
      expect(s, contains("'Account approved'"));
      expect(s, contains("'Account not approved'"));
    });

    test('wording cleanup: Admin -> Manager in messages only, never "database administrator"', () {
      final s = sql('supabase_schema_manager_wording_cleanup.sql');
      expect(s, contains('(?<!database )'));
      expect(s, contains("'\\1\\2 Manager'"));
      expect(s, contains("p.proname NOT IN ('_tmp_manager_wording_cleanup'"));
      // It rewrites quoted text of RAISE lines only; no role literal is replaced.
      expect(s.contains("role = 'admin'"), isFalse);
    });

    test('12: the Members logbook covers member edits, names the module, and cannot be altered', () {
      final s = sql('supabase_schema_officer_permissions_12_member_activity_logbook.sql');
      // Edits of member information by staff are audited (updates only, own edits skipped).
      expect(s, contains("ARRAY['user_information', 'farmer_profiles']"));
      expect(s, contains('AFTER UPDATE ON public.%I'));
      expect(s, contains("'members', 'skip_self'"));
      // Officer access rows always say which module.
      expect(s, contains("jsonb_build_object('module', v_row ->> 'module'"));
      // The history: no longer a gated table, Manager-read-only, no API writes.
      expect(s, contains("WHERE kind = 'table' AND name = 'member_status_events'"));
      expect(
        RegExp(r'CREATE POLICY "mse: manager reads"\s+ON public\.member_status_events FOR SELECT\s+USING \(public\.is_manager\(\)\)').hasMatch(s),
        isTrue,
      );
      expect(s, contains('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.member_status_events FROM anon, authenticated'));
      expect(s, contains('REVOKE UPDATE, DELETE, TRUNCATE ON public.admin_activity_log FROM anon, authenticated'));
      expect(s.contains('CREATE POLICY "mse: admin manages all"'), isFalse);
    });

    test('13: only Buyers lose the yearly totals; the other roles read as before', () {
      final s = sql('supabase_schema_officer_permissions_13_annual_totals_no_buyers.sql');
      expect(s, contains("r.role = 'buyer'"));
      expect(s, contains('FOR SELECT'));
      expect(RegExp(r'FOR (INSERT|UPDATE|DELETE|ALL)').hasMatch(s), isFalse, reason: 'no write rule is touched');
      expect(s.contains('is_staff'), isFalse, reason: 'the staff read rule is untouched');
    });

    test('14: inventory photos follow Dashboard = Manage, for that one folder only', () {
      final s = sql('supabase_schema_officer_permissions_14_inventory_photo_permissions.sql');
      expect(s, contains("staff_access_level('dashboard') = 'manage'"));
      for (final op in ['upload', 'update', 'delete']) {
        expect(s, contains('"Inventory images staff $op"'));
      }
      expect(s, contains('public.can_manage_inventory_photos()'));
      // Insert stays inside the person's own folder.
      expect(s, contains('(storage.foldername(name))[1] = (auth.uid())::text'));
      // No other folder is mentioned in any rule.
      for (final other in ['crop_images', 'listing_photos', 'profile_photos']) {
        expect(s.contains("bucket_id = '$other'"), isFalse, reason: other);
      }
      // Viewing stays public: no SELECT rule is created or dropped.
      expect(RegExp(r'POLICY[^;]*FOR SELECT').hasMatch(s), isFalse);
    });

    test('15: only a missing size limit is filled; file types are never set', () {
      final s = sql('supabase_schema_officer_permissions_15_photo_bucket_limits.sql');
      expect(s, contains('SET file_size_limit = 10485760'));
      expect(s, contains('AND file_size_limit IS NULL'));
      expect(s.contains('allowed_mime_types ='), isFalse);
    });

    test('16: a Farmer share is worked out in the database and only that share is returned', () {
      final s = sql('supabase_schema_officer_permissions_16_farmer_own_share_function.sql');
      expect(s, contains('RETURNS TABLE (selling_share_percent numeric, buying_share_percent numeric)'));
      expect(s, contains('SECURITY DEFINER'));
      // The live function takes one uuid argument with a default; the check must name that signature.
      expect(s, contains("to_regprocedure('public.is_unapproved_applicant(uuid)')"));
      expect(s.contains("is_unapproved_applicant()')"), isFalse, reason: 'no zero-argument form exists');
      expect(s, contains('NOT public.is_unapproved_applicant(auth.uid())'));
      expect(s, contains('mc.farmer_id = auth.uid()'), reason: 'it always answers for the caller');
      expect(s.contains('p_farmer_id') || s.contains('p_user_id'), isFalse, reason: 'nobody can ask about another member');
      expect(s, contains('REVOKE ALL ON FUNCTION public.get_my_activity_share(integer) FROM PUBLIC, anon'));
      expect(s, contains('GRANT EXECUTE ON FUNCTION public.get_my_activity_share(integer) TO authenticated'));
      // Only the two percentages come back: no cooperative total in the result.
      expect(RegExp(r'RETURNS TABLE \(([^)]*)\)').firstMatch(s)!.group(1)!.split(',').length, 2);
    });

    test('17: only after script 16, and it leaves staff as the only readers', () {
      final s = sql('supabase_schema_officer_permissions_17_annual_totals_staff_only.sql');
      expect(s, contains('get_my_activity_share(integer)'), reason: 'refuses to run before script 16');
      expect(s, contains('DROP POLICY IF EXISTS "cooperative_annual_totals: signed-in non-buyers read"'));
      expect(s, contains('DROP POLICY IF EXISTS "cooperative_annual_totals: authenticated reads"'));
      expect(s.contains('CREATE POLICY'), isFalse, reason: 'the staff read rule and the Manager-only write rules stay as they are');
    });

    test('22: Marketplace, Balik-Tangkilik and the BOD reminder join the accountability trail', () {
      final s = sql('supabase_schema_officer_permissions_22_accountability_coverage.sql');
      expect(s, contains("to_regprocedure('public.audit_staff_change()')"));
      for (final t in ['marketplace_listings', 'listing_edit_requests', 'orders', 'cooperative_purchase_offers', 'member_sales_transactions', 'market_linking_programs', 'market_linking_sales', 'da_amad_enrollments']) {
        expect(
          RegExp("sagana_set_audit\\('$t',\\s+'CREATE TRIGGER[^;]*audit_staff_change\\(''marketplace''").hasMatch(s),
          isTrue,
          reason: t,
        );
      }
      expect(
        RegExp(r"sagana_set_audit\('cooperative_annual_totals',\s+'CREATE TRIGGER[^;]*audit_staff_change\(''reports''").hasMatch(s),
        isTrue,
      );
      // The payout result is audited on UPDATE only, and only when it changes.
      expect(s, contains('AFTER UPDATE ON public.member_contributions'));
      expect(s, contains('OLD.status IS DISTINCT FROM NEW.status'));
      expect(s, contains("audit_staff_change(''reports'', '''')"));
      // Locks: each table is its own short transaction, never waited on for long, retried when busy.
      expect(s, contains("set_config('lock_timeout', '4s', true)"));
      expect(s, contains('WHEN deadlock_detected OR lock_not_available THEN'));
      expect(s, contains('CREATE OR REPLACE TRIGGER'));
      expect('BEGIN;'.allMatches(s).length, greaterThanOrEqualTo(11), reason: 'one transaction per table, plus the BOD job');
      expect(RegExp(r"BEGIN;\s*SELECT pg_temp\.sagana_set_audit\([^;]*;\s*COMMIT;").allMatches(s).length, 10);
      // The BOD job: same notices plus one System line; replaced only if it is the known one.
      expect(s, contains("'BOD Meeting in 3 Days'"));
      expect(s, contains('bod_system_log'));
      expect(s, contains("NULL, 'system', 'bod_reminder'"));
      expect(s, contains('is not the batch10_01 version'));
      // It records staff only: the audit function itself skips Farmers, Buyers and no-user changes.
      expect(sql('supabase_schema_officer_permissions_05_accountability.sql'), contains("v_role NOT IN ('admin', 'officer')"));
    });

    test('21: contributions are recorded by a named person and only ever reversed, never edited or deleted', () {
      final s = sql('supabase_schema_officer_permissions_21_contribution_reversal.sql');
      expect(s, contains("to_regprocedure('public.is_platform_admin(uuid)')"), reason: 'real signature');
      expect(s, contains("to_regprocedure('public.recompute_member_capital()')"));
      // The new facts on the ledger.
      expect(s, contains('reverses_event_id uuid'));
      expect(s, contains('reversal_reason text'));
      expect(s, contains('CREATE UNIQUE INDEX IF NOT EXISTS ux_cce_one_reversal'));
      expect(s, contains('BETWEEN 3 AND 500'));
      // Recording: a named recorder, and no reversal through the API.
      expect(s, contains('AND recorded_by = auth.uid()'));
      expect(s, contains('AND reverses_event_id IS NULL'));
      // Nobody signed in changes or deletes a record.
      expect(s, contains('DROP POLICY IF EXISTS "cce: manager changes"'));
      expect(s, contains('DROP POLICY IF EXISTS "cce: manager removes"'));
      expect(s.contains('CREATE POLICY "cce: manager'), isFalse, reason: 'no API rule to edit or delete');
      expect(s, contains('BEFORE UPDATE OR DELETE ON public.capital_contribution_events'));
      expect(s, contains('Cancel the entry instead.'));
      // The reversal function.
      expect(s, contains('reverse_capital_contribution(p_event_id uuid, p_reason text)'));
      expect(s, contains('SECURITY DEFINER'));
      expect(s, contains('IF auth.uid() IS NULL OR NOT public.is_platform_admin(auth.uid()) THEN'));
      expect(s, contains('already been cancelled'));
      expect(s, contains('A cancellation cannot be cancelled.'));
      expect(s, contains('can cancel a contribution.'));
      expect(s, contains("v_orig.source = 'patronage_capital'"));
      expect(s, contains('-v_orig.amount'));
      expect(s, contains('REVOKE ALL ON FUNCTION public.reverse_capital_contribution(uuid, text) FROM PUBLIC, anon'));
      expect(s, contains('GRANT EXECUTE ON FUNCTION public.reverse_capital_contribution(uuid, text) TO authenticated'));
      // A View Only Officer is stopped by the gate.
      expect(s, contains("('rpc', 'reverse_capital_contribution', 'members')"));
      // The member's notice for a cancellation has no minus sign and no staff name.
      expect(s, contains("to_regprocedure('public.fn_notify_capital_recorded()')"));
      expect(s, contains('Capital Contribution Cancelled'));
      expect(s, contains("TO_CHAR(ABS(NEW.amount), 'FM999999990.00')"));
      // A Farmer cannot add capital through the old self-service function either.
      expect(s, contains('REVOKE ALL ON FUNCTION public.reinvest_patronage_capital(integer, numeric, text) FROM PUBLIC, anon, authenticated'));
      // Nothing deletes a record.
      expect(RegExp(r'DELETE\s+FROM\s+public\.capital_contribution_events', caseSensitive: false).hasMatch(s), isFalse);
    });

    test('20: only the Manager changes an Officer\'s access', () {
      final s = sql('supabase_schema_officer_permissions_20_officer_access_manager_only.sql');
      expect(s, contains("to_regprocedure('public.is_manager(uuid)')"), reason: 'checks the real signature');
      expect(s, contains('IF NOT public.is_manager() THEN'));
      expect(s, contains('Only the Manager can change an Officer'));
      expect(s.contains("staff_access_level('members')"), isFalse, reason: 'a Members = Manage Officer no longer qualifies');
      expect(s, contains('You cannot change your own access.'));
      expect(s, contains('Permissions can only be set for an Officer account.'));
      expect(s, contains('_apply_officer_permissions'));
    });

    test('19: staff read only the Manager sign-in e-mail, real addresses only', () {
      final s = sql('supabase_schema_officer_permissions_19_manager_email_in_accounts.sql');
      expect(s, contains("to_regprocedure('public.is_staff()')"), reason: 'checks the real zero-argument signature');
      expect(s, contains('RETURNS TABLE (account_id uuid, sign_in_email text)'));
      expect(s, contains('SECURITY DEFINER'));
      expect(s, contains("r.role = 'admin'"), reason: 'Managers only: no other account is exposed');
      expect(s, contains('public.is_staff()'));
      expect(s, contains("NOT LIKE '%@sagana.local'"));
      expect(s, contains('REVOKE ALL ON FUNCTION public.get_manager_sign_in_emails() FROM PUBLIC, anon'));
      expect(s, contains('GRANT EXECUTE ON FUNCTION public.get_manager_sign_in_emails() TO authenticated'));
    });

    test('18: adding stays open; changing or deleting a contribution is the Manager alone', () {
      final s = sql('supabase_schema_officer_permissions_18_contribution_ledger_protection.sql');
      expect(s, contains('CREATE POLICY "cce: staff add"'));
      expect(s, contains('recorded_by IS NULL OR recorded_by = auth.uid()'));
      final changes = RegExp(r'CREATE POLICY "cce: manager changes"[\s\S]*?FOR UPDATE[\s\S]*?USING \(public\.is_manager\(\)\)');
      final removes = RegExp(r'CREATE POLICY "cce: manager removes"[\s\S]*?FOR DELETE[\s\S]*?USING \(public\.is_manager\(\)\)');
      expect(changes.hasMatch(s), isTrue);
      expect(removes.hasMatch(s), isTrue);
      expect(s, contains('BEFORE UPDATE OR DELETE ON public.capital_contribution_events'));
      expect(s, contains('Contribution records cannot be changed or deleted. Add a correction entry instead.'));
      // The total is kept in step by an owner-rights trigger; nothing here may block it.
      expect(RegExp(r'CREATE TRIGGER[^;]*member_capital_shares').hasMatch(s), isFalse);
      // The old rule that let Officers edit and delete is replaced.
      expect(s, contains('DROP POLICY IF EXISTS "cce: admin manages all"'));
      expect(s.contains('CREATE POLICY "cce: admin manages all"'), isFalse);
    });

    test('03: Officers can schedule, edit and delete broadcasts', () {
      final s = sql('supabase_schema_officer_permissions_03_broadcast_access.sql');
      for (final op in ['insert', 'update', 'delete']) {
        expect(s, contains('"broadcast_logs: staff $op"'));
      }
      expect(s, contains('WITH CHECK (public.is_staff())'));
      expect(s.contains('is_platform_admin'), isFalse);
    });

    test('04 (superseded by 08): the original ban-until-approved design', () {
      final s = sql('supabase_schema_officer_permissions_04_account_approval.sql');
      expect(s, contains('banned_until = NOW() + INTERVAL'));
      expect(s, contains("v_actor_role IS DISTINCT FROM 'officer'"));
      // Both decisions check the Manager role, not the Members permission.
      expect(RegExp(r'IF NOT public\.is_manager\(\) THEN').allMatches(s).length, 2);
      expect(s.contains('is_platform_admin()'), isTrue); // create_officer_account's own gate only
      final approve = s.substring(s.indexOf('FUNCTION public.approve_account_creation'));
      expect(approve.substring(0, approve.indexOf(r'$$;')), isNot(contains('is_platform_admin')));
      // The account is never deleted by a decision and 'pending' status is not reused.
      expect(s.contains('DELETE FROM'), isFalse);
      expect(s, contains("p_permissions, 'manage'"));
      expect(s.contains('p_position'), isFalse);
    });

    test('05: the trail is Manager-only and the approval history names the staff member', () {
      final s = sql('supabase_schema_officer_permissions_05_accountability.sql');
      expect(s, contains('USING (public.is_manager() OR (public.is_staff() AND source = \'app\'))'));
      expect(s, contains('ADD COLUMN IF NOT EXISTS actor_name TEXT'));
      expect(s, contains('trg_member_status_events_fill_actor'));
    });

    test('07: the broad staff notification insert policy is dropped', () {
      final s = sql('supabase_schema_officer_permissions_07_notification_policy.sql');
      expect(s, contains('DROP POLICY IF EXISTS "Staff insert notifications" ON public.notifications'));
      expect(s.contains('CREATE POLICY'), isFalse);
    });

    test('08: only the Manager creates Officers; an Officer-created Farmer is pending, not banned', () {
      final s = sql('supabase_schema_officer_permissions_08_farmer_creation_approval.sql');
      // An Officer creating an Officer account is refused by the database.
      expect(s, contains("IF NEW.role = 'officer' THEN"));
      expect(s, contains('Only the Manager can create an Officer account.'));
      // Pending applicant, request row, status history, Manager notified. No ban.
      expect(s, contains("SET status = 'pending'"));
      expect(s, contains('INSERT INTO account_creation_requests'));
      expect(s, contains("'member_pending', 'New Membership Application'"));
      expect(s.contains('banned_until = NOW()'), isFalse);
      // Only the Manager decides an Officer-created account, in both functions.
      expect(RegExp(r'IF FOUND AND NOT public\.is_manager\(\) THEN').allMatches(s).length, 2);
      // Decision details are Manager-only; staff read a narrow view.
      expect(s, contains('USING (public.is_manager())'));
      expect(s, contains('CREATE OR REPLACE VIEW public.account_creation_sources'));
      expect(s, isNot(contains('decision_reason, r.')));
      // The address is required like registration; every old parameter stays.
      expect(s, contains("RAISE EXCEPTION 'Street is required.'"));
      expect(s, contains("RAISE EXCEPTION 'House number is required.'"));
      for (final p in ['p_share_value_per_unit', 'p_initial_contribution', 'p_initial_crops', 'p_membership_year']) {
        expect(s, contains(p));
      }
      // Unverified until the Manager approves; the old approval RPCs are gone.
      expect(s, contains('VALUES (v_user_id, NOT v_by_officer, p_date_of_birth, p_gender)'));
      expect(s, contains('DROP FUNCTION IF EXISTS public.approve_account_creation(uuid)'));
      expect(s, contains('DROP FUNCTION IF EXISTS public.disapprove_account_creation(uuid, text)'));
    });

    test('09: deleting a disapproved account is Manager-only, checks history, and logs first', () {
      final s = sql('supabase_schema_officer_permissions_09_delete_disapproved_accounts.sql');
      expect(s, contains('IF NOT public.is_manager() THEN'));
      expect(s.contains('is_platform_admin'), isFalse);
      for (final t in ['harvest_records', 'orders', 'farmer_loans', 'loan_requests', 'capital_contribution_events', 'member_contributions']) {
        expect(s, contains("('$t'"));
      }
      // The accountability entry is written BEFORE the delete.
      expect(s.indexOf('INSERT INTO admin_activity_log'), lessThan(s.indexOf('DELETE FROM auth.users')));
      expect(s, contains("'created_by'"));
      expect(s, contains("'disapproved_by'"));
    });

    test('10: a Farmer cannot read the status history', () {
      final s = sql('supabase_schema_officer_permissions_10_status_history_privacy.sql');
      expect(s, contains('DROP POLICY IF EXISTS "mse: member reads own" ON public.member_status_events'));
      expect(s.contains('CREATE POLICY'), isFalse);
    });

    test('06: the gate switch is the last permission script', () {
      final s = sql('supabase_schema_officer_permissions_06_enable_gate.sql');
      expect(s, contains("pgrst.db_pre_request = 'public.staff_permission_gate'"));
    });

    test('the old Officer is removed by one named UID with a plain delete', () {
      final s = sql('supabase_schema_officer_remove_old_account.sql');
      const uid = '32dbca85-d93e-49bc-a468-06d08e70a6ed';
      expect(s, contains(uid));
      expect(RegExp(r'^\s*DELETE FROM auth\.users WHERE id = v_id;', multiLine: true).allMatches(s).length, 1);
      // No other UID, no archive, no soft delete.
      final uids = RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
          .allMatches(s)
          .map((m) => m.group(0))
          .toSet();
      expect(uids, {uid});
      expect(s.toLowerCase().contains('soft'), isFalse);
      expect(s.toLowerCase().contains('archive'), isFalse);
      expect(RegExp(r'update\s+public\.user_roles', caseSensitive: false).hasMatch(s), isFalse);
      // It cannot run until the username from the read-only block is typed in.
      expect(s, contains('REPLACE_WITH_USERNAME_FROM_BLOCK_1A'));
    });
  });
}
