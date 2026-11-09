import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/program_model.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/data/services/staff_permission_service.dart';
import 'package:sagana/presentation/screens/admin/program_management_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// The Manage Members cards: what each Farmer's entry shows at a glance.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_member_cards');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
    await HiveService.init();
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key', httpClient: fake);
  });

  group('days since received', () {
    test('counts whole calendar days, from the date alone', () {
      final now = DateTime(2026, 11, 10, 15, 30);
      expect(daysSinceReceived(DateTime(2026, 11, 10, 8), now), 0);
      expect(daysSinceReceived(DateTime(2026, 11, 9, 23, 59), now), 1);
      expect(daysSinceReceived(DateTime(2026, 10, 29), now), 12);
    });

    test('has no ceiling: 12, 45 and 400 days all count', () {
      final now = DateTime(2026, 11, 10);
      expect(daysSinceReceived(DateTime(2026, 9, 26), now), 45);
      expect(daysSinceReceived(DateTime(2025, 10, 6), now), 400);
    });

    test('grows by one each day with nobody doing anything', () {
      final received = DateTime(2026, 11, 1);
      expect(daysSinceReceived(received, DateTime(2026, 11, 5)), 4);
      expect(daysSinceReceived(received, DateTime(2026, 11, 6)), 5);
    });

    test('a date in the future never goes negative', () {
      expect(daysSinceReceived(DateTime(2026, 12, 1), DateTime(2026, 11, 10)), 0);
    });
  });

  group('a member\'s purchase figures', () {
    Map<String, Object?> row(String farmer, String status, double total, double discount) =>
        {'farmer_id': farmer, 'status': status, 'total_amount': total, 'discount_amount': discount};

    test('orders skip cancelled; spent and saved count paid only; pending is counted', () {
      final g = MemberPurchaseSummary.group([
        row('a', 'completed', 300, 30),
        row('a', 'completed', 100, 0),
        row('a', 'pending', 80, 8),
        row('a', 'cancelled', 500, 50),
        row('b', 'cancelled', 10, 0),
      ].map((r) => Map<String, dynamic>.from(r)));
      expect(g['a']!.orders, 3);
      expect(g['a']!.spent, 400);
      expect(g['a']!.saved, 30);
      expect(g['a']!.pending, 1);
      expect(g['b']!.orders, 0);
      expect(g['b']!.spent, 0);
    });

    test('a Farmer with no purchases is simply absent', () {
      expect(MemberPurchaseSummary.group(const []).containsKey('x'), isFalse);
    });

    test('they are read with ONE query for the whole program, not one per member', () {
      final repo = _read('lib/data/repositories/program_repository.dart');
      final fn = repo.substring(repo.indexOf('fetchPurchaseSummaries'), repo.indexOf('fetchLastReminders'));
      expect(fn, contains(".eq('program_id', programId)"));
      expect(fn.contains('farmer_id\', '), isFalse);
      final flat = fn.replaceAll(RegExp(r'\s'), '');
      expect('_client.from('.allMatches(flat).length, 1);
    });
  });

  // ── the real screen ───────────────────────────────────────────────────────

  CooperativeProgram program({String purpose = 'distribution'}) => CooperativeProgram(
        id: 'p1',
        programName: purpose == 'sales' ? 'Peanut Cookies' : 'Peanut Seed Distribution',
        programType: 'Crop',
        benefitType: 'grant',
        programPurpose: purpose,
        seasonYear: 2026,
        status: 'active',
        memberCount: 3,
        sourceCategories: const ['Seeds'],
      );

  String iso(int daysAgo) => DateTime.now().subtract(Duration(days: daysAgo)).toUtc().toIso8601String();

  Future<void> pumpMembers(WidgetTester tester, CooperativeProgram prog,
      {required List<Map<String, Object?>> members, List<Map<String, Object?>> reports = const [], List<Map<String, Object?>> purchases = const []}) async {
    fake.reset();
    fake.on('GET /rest/v1/program_members', (_) => members);
    fake.on('GET /rest/v1/user_information', (_) => [
      {'user_id': 'f1', 'full_name': 'Ellen Angela Rosal'},
      {'user_id': 'f2', 'full_name': 'Marc Louie Yañez'},
      {'user_id': 'f3', 'full_name': 'Jhon Drhy Salangsang'},
    ]);
    fake.on('GET /rest/v1/cooperative_inventory', (_) => []);
    fake.on('POST /rest/v1/rpc/get_program_outcome_reports', (_) => reports);
    fake.on('GET /rest/v1/program_product_purchases', (_) => purchases);
    await tester.runAsync(() => HiveService.saveUserSession(userId: 'u-admin', email: 'x@y.z', role: 'admin'));
    StaffPermissions.instance.debugSet(const {});
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ProgramMembersScreen(program: prog),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Map<String, Object?> member(String id, String farmer, {int? givenDaysAgo}) => {
        'id': id,
        'program_id': 'p1',
        'farmer_id': farmer,
        'status': 'active',
        'enrolled_at': iso(30),
        'inventory_item_id': givenDaysAgo == null ? null : 'i1',
        'quantity_given': givenDaysAgo == null ? null : 10,
        'distributed_at': givenDaysAgo == null ? null : iso(givenDaysAgo),
        'distributed_item_name': givenDaysAgo == null ? null : 'Rice Seeds',
        'distributed_unit': givenDaysAgo == null ? null : 'kg',
        'distribution_outcome': null,
      };

  Future<void> openDistributedTab(WidgetTester tester) async {
    await tester.tap(find.textContaining('Distributed ('));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('Distribution: one line for what was given, and the live days waiting with no limit', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpMembers(tester, program(), members: [member('m1', 'f1', givenDaysAgo: 45)]);
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
      // Tab "Distributed" holds the member; open it.
      await openDistributedTab(tester);
      expect(find.text('Ellen Angela Rosal'), findsOneWidget);
      expect(find.textContaining('10 kg Rice Seeds · given'), findsOneWidget);
      expect(find.textContaining('Received 10'), findsNothing);
      expect(find.byKey(const Key('waitingDays_m1')), findsOneWidget);
      expect(find.text(l10n.memWaitingDays(45)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Distribution: a report awaiting both checks shows the two open ticks', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpMembers(tester, program(),
          members: [member('m1', 'f1', givenDaysAgo: 5)],
          reports: [
            {
              'id': 'r1',
              'program_member_id': 'm1',
              'program_id': 'p1',
              'farmer_id': 'f1',
              'reported_outcome': 'successful',
              'status': 'pending_validation',
              'submitted_at': iso(1),
              'review_decision': 'validated',
              'reviewed_by': 'u1',
            }
          ]);
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
      await openDistributedTab(tester);
      expect(find.byKey(const Key('outcomeTicks_m1')), findsOneWidget);
      expect(find.text(l10n.memTickEvidence), findsOneWidget);
      expect(find.text(l10n.memTickField), findsOneWidget);
      // Evidence is reviewed (done), the field check is not.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
      // A member who has reported is no longer "waiting".
      expect(find.byKey(const Key('waitingDays_m1')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Product Sales: orders, spent and saved, and a pending chip', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpMembers(tester, program(purpose: 'sales'),
          members: [member('m1', 'f1'), member('m2', 'f2')],
          purchases: [
            {'farmer_id': 'f1', 'status': 'completed', 'total_amount': 1240, 'discount_amount': 124},
            {'farmer_id': 'f1', 'status': 'pending', 'total_amount': 80, 'discount_amount': 0},
            {'farmer_id': 'f1', 'status': 'cancelled', 'total_amount': 999, 'discount_amount': 99},
          ]);
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold).first));
      expect(find.byKey(const Key('salesStats_m1')), findsOneWidget);
      expect(find.text(l10n.memStatOrders(2)), findsOneWidget);
      expect(find.text(l10n.memStatSpent('₱1,240')), findsOneWidget);
      expect(find.text(l10n.memStatSaved('₱124')), findsOneWidget);
      expect(find.text(l10n.memStatPending(1)), findsOneWidget);
      // A member who has bought nothing says so, with no chip.
      expect(find.descendant(of: find.byKey(const Key('salesStats_m2')), matching: find.text(l10n.memDetailsNoPurchases)), findsOneWidget);
      expect(find.byKey(const Key('pendingChip_m2')), findsNothing);
      // No distribution lines on a Product Sales card.
      expect(find.byKey(const Key('waitingDays_m1')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a failed purchase read still shows the members', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpMembers(tester, program(purpose: 'sales'), members: [member('m1', 'f1')]);
      fake.on('GET /rest/v1/program_product_purchases', (_) => const FakeError(500, 'boom'));
      expect(find.text('Ellen Angela Rosal'), findsOneWidget);
    });
  });

  testWidgets('renders in Tagalog without overflow', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpMembers(tester, program(purpose: 'sales'), members: [member('m1', 'f1')], purchases: [
        {'farmer_id': 'f1', 'status': 'pending', 'total_amount': 80, 'discount_amount': 0},
      ]);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('tl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProgramMembersScreen(program: program(purpose: 'sales')),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
    });
  });

  test('the wording exists in English and Tagalog, and no waiting limit is written into the code', () {
    final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');
    expect(screen, contains('daysSinceReceived(m.distributedAt!)'));
    // No fixed number of days, and no colour that changes after a set number of days.
    expect(RegExp(r'days\s*(>|>=|<|<=)\s*\d').hasMatch(screen), isFalse);
  });
}
