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
import 'support/stand_in_fonts.dart';
import 'support/test_storage_mocks.dart';

/// Distribution Members: what each section's card shows, for a Free Distribution program
/// and for a Harvest Return program.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_sections');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
    await HiveService.init();
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key', httpClient: fake);
    await loadStandInFonts();
  });

  String iso(int daysAgo) => DateTime.now().subtract(Duration(days: daysAgo)).toUtc().toIso8601String();

  CooperativeProgram program() => CooperativeProgram(
        id: 'p1',
        programName: 'Peanut Seed Distribution',
        programType: 'Crop',
        seasonYear: 2026,
        status: 'active',
        memberCount: 3,
        sourceCategories: const ['Seeds'],
      );

  Map<String, Object?> member(String id, String farmer, {int? givenDaysAgo, int joinedDaysAgo = 5, String? outcome, int? outcomeDaysAgo}) => {
        'id': id,
        'program_id': 'p1',
        'farmer_id': farmer,
        'status': 'active',
        'enrolled_at': iso(joinedDaysAgo),
        'inventory_item_id': givenDaysAgo == null ? null : 'i1',
        'quantity_given': givenDaysAgo == null ? null : 2,
        'distributed_at': givenDaysAgo == null ? null : iso(givenDaysAgo),
        'distributed_item_name': givenDaysAgo == null ? null : 'Pig',
        'distributed_unit': givenDaysAgo == null ? null : 'head',
        'distribution_outcome': outcome,
        'outcome_recorded_at': outcomeDaysAgo == null ? null : iso(outcomeDaysAgo),
      };

  Map<String, Object?> finalReport(String member, String farmer, {required bool success, double? verified, String? cause}) => {
        'id': 'r-$member',
        'program_member_id': member,
        'program_id': 'p1',
        'farmer_id': farmer,
        'reported_outcome': success ? 'successful' : 'failed',
        'status': 'finalized',
        'final_outcome': success ? 'successful' : 'failed',
        'finalized_at': iso(3),
        'submitted_at': iso(9),
        'review_decision': 'validated',
        'reviewed_by': 'u1',
        'verified_by': 'u2',
        'verified_at': iso(5),
        if (verified != null) 'verified_quantity': verified,
        if (verified != null) 'verified_unit': 'kg',
        if (cause != null) 'failure_cause': cause,
      };

  Future<void> pump(WidgetTester tester, CooperativeProgram prog, {required int tab, List<Map<String, Object?>> members = const [], List<Map<String, Object?>> reports = const [], List<Map<String, Object?>> returns = const [], List<Map<String, Object?>> resolutions = const [], Locale locale = const Locale('en'), Size size = const Size(420, 1400)}) async {
    fake.reset();
    fake.on('GET /rest/v1/program_members', (_) => members);
    fake.on('GET /rest/v1/user_information', (_) => [
      {'user_id': 'f1', 'full_name': 'Jhon Drhy M. Salangsang'},
      {'user_id': 'f2', 'full_name': 'John Harold Revilloza'},
      {'user_id': 'f3', 'full_name': 'Marc Louie M. Yañez'},
    ]);
    fake.on('GET /rest/v1/cooperative_inventory', (_) => []);
    fake.on('POST /rest/v1/rpc/get_program_outcome_reports', (_) => reports);
    fake.on('POST /rest/v1/rpc/get_program_returns', (_) => returns);
    fake.on('POST /rest/v1/rpc/get_failed_resolutions', (_) => resolutions);
    fake.on('GET /rest/v1/program_report_reminders', (_) => []);
    await tester.runAsync(() => HiveService.saveUserSession(userId: 'u-admin', email: 'x@y.z', role: 'admin'));
    StaffPermissions.instance.debugSet(const {});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ProgramMembersScreen(program: prog),
    ));
    for (var i = 0; i < 80 && find.byType(Tab).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(find.byType(Tab).at(tab));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(Tab).at(tab), warnIfMissed: false);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  AppLocalizations l10nOf(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  group('To Distribute', () {
    testWidgets('Free Distribution: how long they have waited since joining, then Distribute', (tester) async {
      await runIgnoringFontErrors(() async {
        await pump(tester, program(), tab: 0, members: [member('m1', 'f1', joinedDaysAgo: 5)]);
        final l10n = l10nOf(tester);
        expect(find.byKey(const Key('waitingToReceive_m1')), findsOneWidget);
        expect(find.text(l10n.memWaitingToReceive(5)), findsOneWidget);
        expect(find.text('Waiting to receive · 5 days since joining'), findsOneWidget);
        expect(find.byKey(const Key('expectedReturn_m1')), findsNothing); // nothing is owed
        expect(find.text(l10n.programMgmtDistributeAction), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('joined today, and the day count keeps growing with no limit and no warning colour', (tester) async {
      await runIgnoringFontErrors(() async {
        await pump(tester, program(), tab: 0, members: [member('m1', 'f1', joinedDaysAgo: 0)]);
        final l10n = l10nOf(tester);
        expect(find.text(l10n.memWaitingToReceive(0)), findsOneWidget);
        expect(find.text('Joined today · waiting to receive'), findsOneWidget);
      });
    });
  });
}
