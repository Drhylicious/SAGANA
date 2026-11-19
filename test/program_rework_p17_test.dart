import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/utils/app_error_message.dart';
import 'package:sagana/data/models/farmer_profile_model.dart';
import 'package:sagana/data/models/program_model.dart';
import 'package:sagana/data/models/staff_action_model.dart';
import 'package:sagana/data/repositories/farmer_details_repository.dart';
import 'package:sagana/data/repositories/program_repository.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/presentation/widgets/admin_program_card.dart';
import 'package:sagana/presentation/widgets/program_member_details.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// The Farmer's profile without the offline cache (which writes to disk), so the view
/// can be tested without waiting on real file work.
class _FakeFarmerRepo extends FarmerDetailsRepository {
  _FakeFarmerRepo({this.contactEmail, this.verifiedEmail});
  final String? contactEmail;
  final String? verifiedEmail;
  @override
  Future<FarmerProfileModel?> fetchFarmerProfile(String farmerId) async =>
      FarmerProfileModel.fromMap({
        'user_id': farmerId,
        'full_name': 'Ellen Angela Rosal',
        'phone_number': '09171234567',
        'farm_address': 'Purok 1, Payanas',
        'contact_email': contactEmail,
        'verified_contact_email': verifiedEmail,
      });
}

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
Map<String, dynamic> _arb(String f) =>
    jsonDecode(_read('lib/core/l10n/$f')) as Map<String, dynamic>;

/// p17: the Inventory item's unit is the only unit; join requests are approved and never
/// declined; Benefit Type is locked after creation; the Program card shows the creation
/// date; the Member details view; and creation stays in the Accountability Log.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_p17');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
    await HiveService.init();
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key', httpClient: fake);
  });

  final sql = _read('supabase_schema/supabase_schema_program_rework_p17_units_join_benefit_lock.sql');
  final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
  String fn(String name) {
    final start = code.indexOf('FUNCTION public.$name');
    expect(start, greaterThan(0), reason: name);
    final end = code.indexOf(r'$function$;', start + 10);
    final end2 = code.indexOf(r'$$;', start + 10);
    return code.substring(start, [end, end2].where((e) => e > 0).reduce((a, b) => a < b ? a : b));
  }

  group('p17 SQL: the unit is the Inventory item\'s', () {
    test('a Harvest Return program needs a quantity only; the old unit column is kept, not read', () {
      final f = fn('program_missing_fields');
      expect(f, contains("'return_quantity'"));
      expect(f.contains("'return_unit'"), isFalse);
      expect(f.contains('p.return_unit'), isFalse);
      expect(code.contains('DROP COLUMN'), isFalse);
    });

    test('every distribution keeps the unit it was given in, and existing ones are filled from the item', () {
      expect(code, contains('ADD COLUMN IF NOT EXISTS distributed_unit TEXT'));
      expect(code, contains('SET distributed_unit = btrim(ci.unit)'));
      expect(code, contains('pm.distributed_unit IS NULL')); // never overwrites a recorded one
      final f = fn('distribute_program_benefit');
      expect(f, contains('distributed_unit = v_unit'));
      expect(f, contains('FOR UPDATE'));
      expect(f, contains('Insufficient stock'));
      expect(f, contains('This member has already received a distribution'));
      expect(f, contains('is_staff()'));
    });

    test('nothing is deleted or removed', () {
      for (final w in ['DELETE FROM', 'DROP TABLE', 'TRUNCATE', 'DROP COLUMN']) {
        expect(code.contains(w), isFalse, reason: w);
      }
    });
  });

  group('p17 SQL: Benefit Type is locked', () {
    test('a trigger refuses any change after creation, for every caller that is signed in', () {
      final f = fn('lock_program_benefit_type');
      expect(f, contains('NEW.benefit_type IS DISTINCT FROM OLD.benefit_type'));
      expect(f, contains('auth.uid() IS NOT NULL'));
      expect(f, contains('BENEFIT_TYPE_LOCKED'));
      expect(code, contains('BEFORE UPDATE OF benefit_type ON public.cooperative_programs'));
    });
  });

  group('p17 SQL: a join request is approved, never declined', () {
    test('both approval functions refuse a decline, before touching anything', () {
      for (final name in ['respond_to_program_enrollment_request', 'respond_to_da_amad_enrollment']) {
        final f = fn(name);
        expect(f, contains('DECLINE_NOT_ALLOWED'), reason: name);
        expect(f.indexOf('DECLINE_NOT_ALLOWED'), lessThan(f.indexOf('UPDATE')), reason: name);
        expect(f, contains("SET status = 'approved'"), reason: name);
        expect(f.contains("'rejected'"), isFalse, reason: name);
        expect(f, contains('is_staff()'), reason: name);
      }
    });

    test('an approval still needs an open program, and re-joining still reactivates the member', () {
      final f = fn('respond_to_program_enrollment_request');
      expect(f, contains("status = 'active'"));
      expect(f, contains('PROGRAM_COMPLETED'));
      expect(f, contains('UPDATE program_members'));
      expect(f, contains('INSERT INTO program_members'));
      expect(f, contains('FOR UPDATE'));
      expect(f, contains("Request already reviewed"));
    });

    test('completing a program still closes its pending requests, with a notice', () {
      final f = fn('complete_program');
      expect(f, contains("status = 'pending'"));
      expect(f, contains("SET status = 'rejected'"));
      expect(f, contains('Join Request Closed'));
      expect(f, contains('program_completion_blockers'));
    });

    test('the staff and Farmer notices say join, not enroll', () {
      expect(code, contains("'Join Request Approved'"));
      expect(code, contains("'New Join Request'"));
      expect(code.toLowerCase().contains('enrollment approved'), isFalse);
    });

    test('the app has no Decline for a join request, and the error is explained', () {
      final enrollScreen = _read('lib/presentation/screens/admin/program_enrollment_requests_screen.dart');
      expect(enrollScreen.contains('reqDecline'), isFalse);
      expect(enrollScreen.contains('TextField('), isFalse); // no reason box
      expect(_read('lib/presentation/screens/admin/da_amad_enrollment_screen.dart').contains('mlEnrollDecline'), isFalse);
      final repo = _read('lib/data/repositories/program_repository.dart');
      expect(repo, contains("'p_approve': true"));
      final en = lookupAppLocalizations(const Locale('en'));
      expect(messageForDatabaseText(en, 'DECLINE_NOT_ALLOWED: x'), en.errDeclineNotAllowed);
      expect(messageForDatabaseText(en, 'BENEFIT_TYPE_LOCKED: x'), en.errBenefitLocked);
    });
  });

  group('one wording for joining, in English and Tagalog', () {
    test('no visible English text says enroll / enrollment', () {
      final en = _arb('app_en.arb');
      final bad = <String>[];
      en.forEach((k, v) {
        if (k.startsWith('@') || v is! String) return;
        // systemNotice* are lookup keys for old stored notification titles (shown only in Tagalog,
        // translated); the English value is never displayed, so it may keep the stored wording.
        if (k.startsWith('systemNotice') || RegExp(r'^sn[A-Z]').hasMatch(k)) return;
        final text = v.replaceAll(RegExp(r'\{[^}]*\}'), '');
        if (RegExp('enrol', caseSensitive: false).hasMatch(text)) bad.add('$k: $v');
      });
      expect(bad, isEmpty);
    });

    test('no visible Tagalog text keeps the old enrollment wording', () {
      final tl = _arb('app_tl.arb');
      final bad = <String>[];
      tl.forEach((k, v) {
        if (k.startsWith('@') || v is! String) return;
        final text = v.replaceAll(RegExp(r'\{[^}]*\}'), '');
        if (RegExp('enrol|patala', caseSensitive: false).hasMatch(text)) bad.add('$k: $v');
      });
      expect(bad, isEmpty);
    });

    test('the screens use Join Requests, Request to Join and Joined', () {
      final en = _arb('app_en.arb');
      expect(en['reqEnrollTitle'], 'Join Requests');
      expect(en['mlkManageEnrollments'], 'Join Requests');
      expect(en['joinRequestAction'], 'Request to Join');
      expect(en['reqStatusEnrolled'], 'Joined');
      expect(en['marketLinkKpiEnrolled'], 'Joined');
      expect(en['joinStatusTitle'], 'Membership');
    });

    test('the Farmer screens no longer hard-code the old words', () {
      for (final f in [
        'lib/presentation/screens/farmer/program_details_screen.dart',
        'lib/presentation/screens/farmer/browse_programs_screen.dart',
        'lib/presentation/screens/farmer/my_market_linking_screen.dart',
        'lib/presentation/screens/farmer/manage_inventory_screen.dart',
      ]) {
        final lines = _read(f).split('\n').where((l) => !l.trimLeft().startsWith('//'));
        final shown = lines.where((l) => RegExp(r"'[^']*[Ee]nroll[^']*'").hasMatch(l) && !RegExp(r'Key\(|route|Route|import|_enrolled').hasMatch(l));
        expect(shown, isEmpty, reason: f);
      }
    });
  });

  group('Benefit Type is chosen once', () {
    test('Create offers the choice; Edit shows it locked and never sends it', () {
      final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');
      final flat = screen.replaceAll(RegExp(r'\s+'), '');
      expect(flat, contains('if(existing==null)AppDropdownField<String>(value:selectedBenefitType'));
      expect(screen, contains('Icons.lock_outline_rounded'));
      final repo = _read('lib/data/repositories/program_repository.dart');
      final update = repo.substring(repo.indexOf('Future<bool> updateProgram'), repo.indexOf('// ─── Program completion'));
      expect(update.contains("'benefit_type'"), isFalse);
      expect(update.contains("'program_purpose'"), isFalse);
      expect(update.contains("'return_unit'"), isFalse);
    });

    test('the form has no helper text under a field (the standing rule)', () {
      // The only helper text is the "Returns: <item>" line under the return quantity in the Distribute
      // panel (it says which item comes back). The create / edit form has none.
      final src = _read('lib/presentation/screens/admin/program_management_screen.dart');
      expect('helperText'.allMatches(src).length, lessThanOrEqualTo(1));
      expect(src.indexOf('helperText'), greaterThan(src.indexOf("Key('distReturnQuantityField')")));
    });
  });

  group('Program card: type and creation date', () {
    CooperativeProgram p({DateTime? created}) => CooperativeProgram(
          id: 'p1',
          programName: 'Peanut Seed Distribution',
          programType: 'Crop',
          benefitType: 'grant',
          seasonYear: 2026,
          status: 'active',
          memberCount: 4,
          createdAt: created,
        );

    test('MM/DD/YY, two digits each, from the creation date', () {
      expect(AdminProgramCard.programCardDate(p(created: DateTime(2026, 9, 5))), '09/05/26');
      expect(AdminProgramCard.programCardDate(p(created: DateTime(2027, 12, 31))), '12/31/27');
      expect(AdminProgramCard.programCardDate(p(created: DateTime(2030, 1, 2))), '01/02/30');
    });

    test('an older row without a date falls back to its season year', () {
      expect(AdminProgramCard.programCardDate(p()), '2026');
    });

    test('created_at is read from the program row, local time', () {
      final prog = CooperativeProgram.fromMap({
        'id': 'p',
        'program_name': 'X',
        'program_type': 'Crop',
        'season_year': 2026,
        'created_at': '2026-09-15T12:00:00Z',
      });
      expect(prog.createdAt, isNotNull);
      expect(prog.createdAt!.month, 9);
    });

    test('the card shows no creator name or role', () {
      final card = _read('lib/presentation/widgets/admin_program_card.dart');
      expect(card.contains('created_by'), isFalse);
      expect(card.contains('createdBy'), isFalse);
    });
  });

  group('Creation is in the Accountability Log with the creator\'s role', () {
    final audit = _read('supabase_schema/supabase_schema_officer_permissions_05_accountability.sql');

    test('every insert on cooperative_programs by a Manager or Officer is recorded by the database', () {
      expect(audit, contains("('cooperative_programs',        'programs',  '')"));
      expect(audit, contains('AFTER INSERT OR UPDATE OR DELETE'));
      expect(audit, contains("v_role NOT IN ('admin', 'officer')"));
      expect(audit, contains('actor_role, actor_name, table_name, operation, record_id, reference_label'));
      expect(audit, contains("WHEN 'INSERT' THEN 'created'"));
      expect(audit, contains("'program_name'")); // the log names the program
    });

    test('the log entry carries the Manager or Officer role the screen shows', () {
      final e = StaffActionEntry.fromMap({
        'id': 'l1',
        'admin_id': 'u1',
        'actor_name': 'Maria Cruz',
        'actor_role': 'officer',
        'module': 'programs',
        'operation': 'created',
        'table_name': 'cooperative_programs',
        'reference_label': 'Peanut Cookies',
        'description': 'Created cooperative programs: Peanut Cookies',
        'new_values': {'created_by': 'u1'},
        'created_at': '2026-11-05T12:00:00Z',
      });
      expect(e.staffRole, 'officer');
      expect(e.operation, 'created');
      expect(e.reference, 'Peanut Cookies');
      expect(e.newValues!['created_by'], 'u1');
      expect(_read('lib/presentation/screens/admin/staff_accountability_screen.dart'), contains('l10n.staffRoleOfficer'));
    });

    test('the program is saved with its creator, and creating one is also logged by the app', () {
      final repo = _read('lib/data/repositories/program_repository.dart');
      expect(repo, contains("'created_by': _client.auth.currentUser?.id"));
      expect(repo, contains("actionType: 'created'"));
    });
  });

  // ── Member details ────────────────────────────────────────────────────────

  CooperativeProgram program({String purpose = 'distribution', double discount = 0}) => CooperativeProgram(
        id: 'p1',
        programName: purpose == 'sales' ? 'Peanut Cookies' : 'Livestock Dispersal',
        programType: 'Livestock',
        benefitType: 'grant',
        programPurpose: purpose,
        seasonYear: 2026,
        status: 'active',
        memberCount: 1,
        memberDiscountPercent: discount,
      );

  ProgramMember member({bool distributed = true, String farmer = 'f1'}) => ProgramMember(
        id: 'm1',
        programId: 'p1',
        farmerId: farmer,
        farmerName: 'Ellen Angela Rosal',
        status: 'active',
        enrolledAt: DateTime(2026, 10, 28, 12),
        inventoryItemId: distributed ? 'i1' : null,
        quantityGiven: distributed ? 2 : null,
        distributedAt: distributed ? DateTime(2026, 11, 4, 12) : null,
        distributedItemName: distributed ? 'Pig' : null,
        distributedUnit: distributed ? 'head' : null,
      );

  // The loads read the offline cache (real file work), so let real time pass, then repaint.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pumpDetails(WidgetTester tester, CooperativeProgram prog, ProgramMember m, {FarmerDetailsRepository? farmerRepo}) async {
    fake.reset();
    fake.on('GET /rest/v1/user_information', (_) => [{'user_id': 'staff-1', 'full_name': 'Maria Cruz'}]);
    fake.on('GET /rest/v1/user_roles', (_) => [{'role': 'officer', 'status': 'active'}]);
    fake.on('GET /rest/v1/program_enrollment_requests', (_) => [
      {'submitted_at': '2026-10-27T12:00:00Z', 'reviewed_at': '2026-10-28T12:00:00Z', 'reviewed_by': 'staff-1'},
    ]);
    fake.on('GET /rest/v1/program_product_purchases', (_) => [
      _purchase('a', 'completed', 300, 30),
      _purchase('b', 'pending', 100, 0),
    ]);
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProgramMemberDetails(
            program: prog,
            member: m,
            repo: ProgramRepository(),
            farmerRepo: farmerRepo ?? _FakeFarmerRepo(),
          ),
        ),
      ),
    ));
    await settle(tester);
  }

  testWidgets('Distribution: contact, who approved, and what was given in the item\'s unit', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpDetails(tester, program(), member());
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
      expect(find.text('Ellen Angela Rosal'), findsOneWidget);
      expect(find.text('09171234567'), findsOneWidget);
      expect(find.text('Purok 1, Payanas'), findsOneWidget);
      expect(find.text('Oct 27, 2026'), findsOneWidget); // asked to join
      expect(find.text(l10n.memDetailsByLine('Maria Cruz', l10n.staffRoleOfficer, 'Oct 28, 2026')), findsOneWidget);
      // What was given: the unit kept with the distribution, no ".0".
      expect(find.text('2 head Pig · Nov 4, 2026'), findsOneWidget);
      expect(find.textContaining('piece'), findsNothing);
      expect(find.textContaining('2.0'), findsNothing);
      // No outcome reported yet.
      expect(find.text(l10n.memDetailsNoReport), findsOneWidget);
      // A distribution program shows no purchases.
      expect(find.text(l10n.memDetailsPurchases), findsNothing);
      expect(find.byKey(const Key('memberViewProfile')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a verified e-mail address is shown', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpDetails(tester, program(), member(farmer: 'f5'), farmerRepo: _FakeFarmerRepo(contactEmail: 'ellen@example.com', verifiedEmail: 'ellen@example.com'));
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
      expect(find.byKey(const Key('memberVerifiedEmail')), findsOneWidget);
      expect(find.text('ellen@example.com'), findsOneWidget);
      expect(find.text(l10n.memDetailsEmail), findsOneWidget);
      expect(find.text('09171234567'), findsOneWidget); // the number is still there
    });
  });

  testWidgets('an unverified e-mail address is not shown (changed since it was verified, or never verified)', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpDetails(tester, program(), member(farmer: 'f6'), farmerRepo: _FakeFarmerRepo(contactEmail: 'new-address@example.com', verifiedEmail: 'old-address@example.com'));
      expect(find.byKey(const Key('memberVerifiedEmail')), findsNothing);
      expect(find.textContaining('example.com'), findsNothing);
    });
  });

  testWidgets('an e-mail that was never verified, and a Farmer with none, show nothing', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpDetails(tester, program(), member(farmer: 'f7'), farmerRepo: _FakeFarmerRepo(contactEmail: 'ellen@example.com'));
      expect(find.byKey(const Key('memberVerifiedEmail')), findsNothing);
      expect(find.textContaining('example.com'), findsNothing);
      expect(find.text('09171234567'), findsOneWidget);
    });
  });

  testWidgets('Distribution: nothing received yet says so', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpDetails(tester, program(), member(distributed: false, farmer: 'f2'));
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
      expect(find.text(l10n.memDetailsNotYetReceived), findsOneWidget);
      expect(find.text(l10n.memDetailsOutcome), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Product Sales: orders, total spent, discount saved and recent purchases, not distribution', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpDetails(tester, program(purpose: 'sales', discount: 10), member(distributed: false, farmer: 'f3'));
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
      expect(find.text(l10n.memDetailsPurchases), findsOneWidget);
      expect(find.text(l10n.memDetailsDistribution), findsNothing);
      expect(find.text(l10n.memDetailsOutcome), findsNothing);
      expect(find.text('2'), findsOneWidget); // orders
      expect(find.text('₱300.00'), findsWidgets); // total spent: only the paid one
      expect(find.text('₱30.00'), findsOneWidget); // saved by the member discount
      expect(find.text(l10n.memDetailsRecent), findsOneWidget);
      expect(find.textContaining(l10n.purchStatusPending), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the details view renders in Tagalog without overflow', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpDetails(tester, program(), member());
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('tl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProgramMemberDetails(
              program: program(),
              member: member(),
              repo: ProgramRepository(),
              farmerRepo: _FakeFarmerRepo(),
            ),
          ),
        ),
      ));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Manage Members opens the details on tap', () {
    test('every member card is tappable, shows the item\'s unit, and keeps its own actions', () {
      final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');
      expect(screen, contains('showProgramMemberDetails('));
      expect(screen, contains("Key('memberCard_"));
      expect(screen, contains('m.distributedUnit ?? item?.unit'));
      expect(screen.contains('quantityGiven?.toStringAsFixed(1)'), isFalse);
      expect(screen, contains('_startDistribute(m)'));
    });

    test('the members read falls back if the unit column does not exist yet', () {
      final repo = _read('lib/data/repositories/program_repository.dart');
      expect(repo, contains('distributed_item_name, distributed_unit'));
      expect(repo, contains('rows = await read(baseCols);'));
    });
  });

  group('Field Verification: only the measured quantity, in the item\'s unit', () {
    final src = _read('lib/presentation/screens/admin/program_outcome_detail_screen.dart');
    // The verification inputs, from the hint to the Farmer's figure.
    final block = src.substring(
      src.indexOf("key: const Key('measuredQuantityField')") - 200,
      src.indexOf('if (r.quantityHarvested != null)', src.indexOf("key: const Key('measuredQuantityField')")),
    );

    test('there is no unit to choose: just the quantity, with the unit shown beside it', () {
      expect(block, contains("Key('measuredQuantityField')"));
      expect(block, contains('suffixText: _measuredUnit'));
      expect(block.contains('QuantityUnitField'), isFalse);
      expect(block.contains('AppDropdownField'), isFalse);
      expect(block.contains('onUnitChanged'), isFalse);
      expect(block.contains('_addUnit'), isFalse);
      // The unit is only ever set from the item (once, at the start), never from a picker.
      expect(RegExp(r'_measuredUnit = (u|v)\b').hasMatch(src), isFalse);
    });

    test('the unit is the item that was given, else (old record) what the Farmer reported', () {
      expect(src, contains('_measuredUnit = unitOrDefault(_r.itemUnit ?? _r.quantityUnit)'));
    });

    test('clearer wording', () {
      final en = _arb('app_en.arb');
      expect(en['outcMeasuredLabel'], 'Measured quantity *');
      expect(en['outcMeasured'], 'Verified quantity');
      expect(en['outcMeasured'], isNot(contains('field')));
    });

    test('the Harvest Return after a Successful outcome is also locked to the item\'s unit', () {
      // The unit is taken from the item itself and there is no unit picker on this screen.
      expect(src, contains('_r.itemUnit ?? _r.quantityUnit'));
      expect(src, isNot(contains('QuantityUnitField(')));
    });

    test('the Farmer\'s report also starts from the item\'s unit, not kg', () {
      final report = _read('lib/presentation/screens/farmer/report_outcome_screen.dart');
      expect(report, contains('widget.entry.itemUnit'));
    });
  });

  group('the Farmer sees the item\'s unit', () {
    test('the return and the received line use the Inventory item\'s unit', () {
      expect(_read('lib/presentation/screens/farmer/my_programs_screen.dart'), contains('entry.itemUnit'));
      final details = _read('lib/presentation/screens/farmer/program_details_screen.dart');
      // returnUnitShown = the return item's unit, else the given item's unit (never the old program-level unit).
      expect(RegExp(r'entry\.returnUnit\b').hasMatch(details), isFalse);
      expect(details, anyOf(contains('entry.itemUnit'), contains('entry.returnUnitShown')));
    });
  });
}

Map<String, Object?> _purchase(String id, String status, double total, double discount) => {
      'id': id,
      'program_id': 'p1',
      'product_id': 'prod',
      'farmer_id': 'f1',
      'quantity': 3,
      'unit_price': total / 3,
      'total_amount': total,
      'status': status,
      'requested_at': '2026-11-01T12:00:00Z',
      'regular_unit_price': (total + discount) / 3,
      'discount_percent': discount > 0 ? 10 : 0,
      'discount_amount': discount,
      'is_member_price': discount > 0,
      'program_products': {
        'cooperative_inventory': {'item_name': 'Peanut Cookies', 'unit': 'pack', 'image_url': null},
      },
    };
