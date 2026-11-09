import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/constants/app_constants.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/utils/app_error_message.dart';
import 'package:sagana/data/models/farmer_profile_model.dart';
import 'package:sagana/data/models/program_model.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/data/services/staff_permission_service.dart';
import 'package:sagana/presentation/screens/admin/program_management_screen.dart';
import 'package:sagana/presentation/screens/farmer/my_programs_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// The "Remind" button (staff) and the "Outcome report pending" line (Farmer).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_reminders');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
    await HiveService.init();
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key', httpClient: fake);
  });

  // ── the database rules (read from the script; the script is not run) ─────────
  final sql = _read('supabase_schema/supabase_schema_program_rework_p18_report_reminders.sql');
  final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
  final fn = code.substring(code.indexOf('FUNCTION public.remind_program_report'), code.indexOf(r'$function$;', code.indexOf('FUNCTION public.remind_program_report')));

  group('p18 SQL: the reminder rules are enforced in the database', () {
    test('one reminder per distributed item per calendar day, decided by a UNIQUE constraint', () {
      expect(code, contains('CONSTRAINT program_report_reminders_one_per_day UNIQUE (program_member_id, reminded_on)'));
      expect(code, contains("reminded_on       DATE        NOT NULL DEFAULT ((NOW() AT TIME ZONE 'Asia/Manila')::DATE)"));
      expect(fn, contains('ON CONFLICT (program_member_id, reminded_on) DO NOTHING'));
      expect(fn, contains('GET DIAGNOSTICS v_rows = ROW_COUNT'));
      expect(fn, contains('REMINDER_TODAY'));
      // The notice is sent only after the row was accepted.
      expect(fn.indexOf('REMINDER_TODAY'), lessThan(fn.indexOf('INSERT INTO notifications')));
    });

    test('only a Manager or Officer, and only while the Farmer is waiting to report', () {
      expect(fn, contains('public.is_staff()'));
      expect(fn, contains("v_m.status <> 'active'"));
      expect(fn, contains('v_m.distributed_at IS NULL'));
      expect(fn, contains('v_m.distribution_outcome IS NOT NULL'));
      expect(fn, contains('FROM program_outcome_reports r WHERE r.program_member_id = v_m.id'));
      expect(fn, contains('REMINDER_NOT_NEEDED'));
      expect(fn, contains('FOR UPDATE'));
    });

    test('the Farmer\'s notice says "the cooperative" and never names or hints at who sent it', () {
      final notice = fn.substring(fn.indexOf('INSERT INTO notifications'));
      expect(notice, contains("'Outcome report pending'"));
      expect(notice, contains("'The cooperative reminds you"));
      for (final secret in ['v_name', 'v_role', 'sent_by', 'auth.uid', 'full_name']) {
        expect(notice.contains(secret), isFalse, reason: secret);
      }
      expect(notice, contains("'/farmer/profile/programs'"));
    });

    test('every reminder is in the Accountability Log with the sender\'s role, and cannot be changed', () {
      expect(code, contains('AFTER INSERT OR UPDATE OR DELETE ON public.program_report_reminders'));
      expect(code, contains("audit_staff_change('programs', '')"));
      expect(code, contains('BEFORE UPDATE OR DELETE ON public.program_report_reminders'));
      expect(code, contains('_program_record_immutable()'));
      expect(fn, contains('public._outcome_actor()')); // name and role are kept on the row too
      expect(fn, contains('sent_by_role'));
    });

    test('nobody writes the table directly; staff read it; the Officer gate lists it', () {
      expect(code, contains('ENABLE ROW LEVEL SECURITY'));
      expect(code, contains('FOR SELECT TO authenticated USING (public.is_staff())'));
      expect(code, contains('GRANT SELECT ON public.program_report_reminders TO authenticated'));
      expect(code.contains('GRANT INSERT'), isFalse);
      expect(code, contains("('rpc',   'remind_program_report',    'dashboard')"));
      expect(code, contains("('table', 'program_report_reminders', 'dashboard')"));
    });

    test('nothing is deleted or changed, and it needs p17 first', () {
      for (final w in ['DELETE FROM', 'DROP TABLE', 'TRUNCATE', 'DROP COLUMN', 'ALTER TABLE public.program_members']) {
        expect(code.contains(w), isFalse, reason: w);
      }
      expect(code, contains('Apply p17 first.'));
    });

    test('there is no automatic or scheduled reminder', () {
      for (final w in ['cron', 'pg_net', 'schedule']) {
        expect(code.toLowerCase().contains(w), isFalse, reason: w);
      }
    });
  });

  group('reminder data', () {
    test('the newest reminder per member wins', () {
      final m = ProgramReportReminder.latest([
        {'program_member_id': 'a', 'created_at': '2026-11-01T10:00:00Z', 'sent_by_role': 'officer'},
        {'program_member_id': 'a', 'created_at': '2026-11-03T10:00:00Z', 'sent_by_role': 'admin'},
        {'program_member_id': 'b', 'created_at': '2026-11-02T10:00:00Z', 'sent_by_role': 'officer'},
      ]);
      expect(m['a']!.sentAt.toUtc().day, 3);
      expect(m['a']!.sentByRole, 'admin');
      expect(m['b']!.sentAt.toUtc().day, 2);
    });

    test('"today" is the local calendar day', () {
      final r = ProgramReportReminder(programMemberId: 'a', sentAt: DateTime(2026, 11, 6, 8));
      expect(r.isToday(DateTime(2026, 11, 6, 23, 59)), isTrue);
      expect(r.isToday(DateTime(2026, 11, 7, 0, 1)), isFalse);
    });

    test('the two database refusals are explained in plain words', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(messageForDatabaseText(en, 'REMINDER_TODAY: x'), en.errReminderToday);
      expect(messageForDatabaseText(en, 'REMINDER_NOT_NEEDED: x'), en.errReminderNotNeeded);
    });
  });

  // ── the staff card ────────────────────────────────────────────────────────
  CooperativeProgram program({String purpose = 'distribution'}) => CooperativeProgram(
        id: 'p1',
        programName: 'Peanut Seed Distribution',
        programType: 'Crop',
        benefitType: 'grant',
        programPurpose: purpose,
        seasonYear: 2026,
        status: 'active',
        memberCount: 1,
        sourceCategories: const ['Seeds'],
      );

  String iso(int daysAgo) => DateTime.now().subtract(Duration(days: daysAgo)).toUtc().toIso8601String();

  Map<String, Object?> member(String id, {int givenDaysAgo = 12}) => {
        'id': id,
        'program_id': 'p1',
        'farmer_id': 'f1',
        'status': 'active',
        'enrolled_at': iso(40),
        'inventory_item_id': 'i1',
        'quantity_given': 10,
        'distributed_at': iso(givenDaysAgo),
        'distributed_item_name': 'Rice Seeds',
        'distributed_unit': 'kg',
        'distribution_outcome': null,
      };

  List<Map<String, Object?>> reminders = [];

  Future<void> pumpMembers(WidgetTester tester, CooperativeProgram prog, List<Map<String, Object?>> members,
      {List<Map<String, Object?>> reports = const []}) async {
    fake.reset();
    fake.on('GET /rest/v1/program_members', (_) => members);
    fake.on('GET /rest/v1/user_information', (_) => [
      {'user_id': 'f1', 'full_name': 'Ellen Angela Rosal'},
    ]);
    fake.on('GET /rest/v1/cooperative_inventory', (_) => []);
    fake.on('POST /rest/v1/rpc/get_program_outcome_reports', (_) => reports);
    fake.on('GET /rest/v1/program_report_reminders', (_) => reminders);
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
    await tester.tap(find.textContaining('Distributed ('));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  AppLocalizations l10nOf(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  testWidgets('a waiting Farmer has a Remind button; tapping sends it for that member and shows when', (tester) async {
    await runIgnoringFontErrors(() async {
      reminders = [];
      await pumpMembers(tester, program(), [member('m1')]);
      final l10n = l10nOf(tester);
      expect(find.byKey(const Key('remind_m1')), findsOneWidget);
      expect(find.text(l10n.memRemindAction), findsOneWidget);
      expect(find.byKey(const Key('lastReminded_m1')), findsNothing);

      // The database accepts it; afterwards the reminder is listed.
      fake.on('POST /rest/v1/rpc/remind_program_report', (_) {
        reminders = [
          {'program_member_id': 'm1', 'created_at': DateTime.now().toUtc().toIso8601String(), 'sent_by_role': 'officer'},
        ];
        return null;
      });
      await tester.tap(find.byKey(const Key('remind_m1')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      final sent = fake.calls('POST /rest/v1/rpc/remind_program_report');
      expect(sent, hasLength(1));
      expect(sent.first.jsonMap['p_program_member_id'], 'm1');
      expect(find.text(l10n.memRemindSent('Ellen Angela Rosal')), findsOneWidget);
      // It now says when, and the button is spent for today.
      expect(find.byKey(const Key('lastReminded_m1')), findsOneWidget);
      expect(find.text(l10n.memRemindedToday), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('remind_m1'))).onPressed, isNull);
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('already reminded today: the button is spent and sends nothing', (tester) async {
    await runIgnoringFontErrors(() async {
      reminders = [
        {'program_member_id': 'm1', 'created_at': DateTime.now().toUtc().toIso8601String(), 'sent_by_role': 'admin'},
      ];
      await pumpMembers(tester, program(), [member('m1')]);
      final l10n = l10nOf(tester);
      expect(find.text(l10n.memRemindedToday), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('remind_m1'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('remind_m1')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(fake.calls('POST /rest/v1/rpc/remind_program_report'), isEmpty);
    });
  });

  testWidgets('a reminder from an earlier day does not block today\'s', (tester) async {
    await runIgnoringFontErrors(() async {
      reminders = [
        {'program_member_id': 'm1', 'created_at': DateTime.now().subtract(const Duration(days: 2)).toUtc().toIso8601String(), 'sent_by_role': 'admin'},
      ];
      await pumpMembers(tester, program(), [member('m1')]);
      final l10n = l10nOf(tester);
      expect(find.text(l10n.memRemindAction), findsOneWidget);
      expect(find.byKey(const Key('lastReminded_m1')), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('remind_m1'))).onPressed, isNotNull);
    });
  });

  testWidgets('if the database refuses (another person reminded first), the reason is shown and nothing breaks', (tester) async {
    await runIgnoringFontErrors(() async {
      reminders = [];
      await pumpMembers(tester, program(), [member('m1')]);
      final l10n = l10nOf(tester);
      fake.on('POST /rest/v1/rpc/remind_program_report', (_) => const FakeError(400, 'REMINDER_TODAY: A reminder was already sent today for this item. Try again tomorrow.'));
      await tester.tap(find.byKey(const Key('remind_m1')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text(l10n.errReminderToday), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    });
  });

  // The look of the waiting row after N days, kept to compare across two runs.
  final looks = <int, (Color?, Color?, Color?)>{};
  Future<void> recordLook(WidgetTester tester, int days) async {
    await runIgnoringFontErrors(() async {
      reminders = [];
      await pumpMembers(tester, program(), [member('m1', givenDaysAgo: days)]);
      final l10n = l10nOf(tester);
      final text = tester.widget<Text>(find.text(l10n.memWaitingDays(days)));
      final icon = tester.widget<Icon>(find.descendant(of: find.byKey(const Key('waitingDays_m1')), matching: find.byIcon(Icons.hourglass_empty_rounded)));
      final button = tester.widget<OutlinedButton>(find.byKey(const Key('remind_m1')));
      looks[days] = (text.style?.color, icon.color, button.style?.foregroundColor?.resolve({}));
    });
  }

  testWidgets('the waiting row after 3 days', (tester) => recordLook(tester, 3));
  testWidgets('the waiting row after 400 days', (tester) => recordLook(tester, 400));

  test('the waiting row looks the same after 3 days and after 400: no colour thresholds', () {
    expect(looks[3], isNotNull);
    expect(looks[400], isNotNull);
    expect(looks[3], looks[400]);
    final screen = _read('lib/presentation/screens/admin/program_management_screen.dart');
    expect(RegExp(r'days\s*(>|>=|<|<=)\s*\d').hasMatch(screen), isFalse);
  });

  testWidgets('no Remind for a Farmer who has reported, or on a Product Sales program', (tester) async {
    await runIgnoringFontErrors(() async {
      reminders = [];
      await pumpMembers(tester, program(), [member('m1')], reports: [
        {
          'id': 'r1',
          'program_member_id': 'm1',
          'program_id': 'p1',
          'farmer_id': 'f1',
          'reported_outcome': 'successful',
          'status': 'pending_validation',
          'submitted_at': iso(1),
        }
      ]);
      expect(find.byKey(const Key('remind_m1')), findsNothing);
    });
    await runIgnoringFontErrors(() async {
      fake.reset();
      fake.on('GET /rest/v1/program_members', (_) => [member('m2')]);
      fake.on('GET /rest/v1/user_information', (_) => [{'user_id': 'f1', 'full_name': 'Ellen'}]);
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProgramMembersScreen(program: program(purpose: 'sales')),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.byKey(const Key('remind_m2')), findsNothing);
      expect(fake.calls('GET /rest/v1/program_report_reminders'), isEmpty);
    });
  });

  test('a database without p18 still lists the members: the reminders read fails quietly', () {
    final repo = _read('lib/data/repositories/program_repository.dart');
    final read = repo.substring(repo.indexOf('fetchLastReminders'), repo.indexOf('remindReport'));
    expect(read, contains('} catch (_) {'));
    expect(read, contains('return {};'));
  });

  // ── the Farmer ────────────────────────────────────────────────────────────
  MyProgramEntry entry({int? givenDaysAgo = 12, String? outcome}) => MyProgramEntry.fromMap({
        'id': 'm1',
        'program_id': 'p1',
        'status': 'active',
        'enrolled_at': iso(40),
        'quantity_given': givenDaysAgo == null ? null : 2,
        'distributed_at': givenDaysAgo == null ? null : iso(givenDaysAgo),
        'distributed_item_name': 'Pig',
        'distribution_outcome': outcome,
        'cooperative_programs': {
          'program_name': 'Livestock Dispersal Program',
          'benefit_type': 'grant',
          'program_purpose': 'distribution',
          'status': 'active',
        },
        'cooperative_inventory': {'item_name': 'Pig', 'unit': 'head'},
      });

  Future<void> pumpFarmerCard(WidgetTester tester, MyProgramEntry e, {Locale locale = const Locale('en')}) async {
    tester.view.physicalSize = const Size(380, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MyProgramCard(
            entry: e,
            report: null,
            onReport: () {},
            formatDate: (d) => '${d.month}/${d.day}/${d.year}',
            statusLabel: (s) => s,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Farmer: "Outcome report pending · Received 12 days ago", counted live, with the report button', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpFarmerCard(tester, entry(givenDaysAgo: 12));
      final l10n = l10nOf(tester);
      expect(find.text('Outcome report pending · Received 12 days ago'), findsOneWidget);
      expect(find.text(l10n.farmerProgReportPending(12)), findsOneWidget);
      // Not "due": no deadline is implied.
      expect(find.textContaining('due'), findsNothing);
      expect(find.textContaining('overdue'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Farmer: today and yesterday read naturally, and any number of days counts', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpFarmerCard(tester, entry(givenDaysAgo: 0));
      expect(find.text('Outcome report pending · Received today'), findsOneWidget);
      await pumpFarmerCard(tester, entry(givenDaysAgo: 1));
      expect(find.text('Outcome report pending · Received 1 day ago'), findsOneWidget);
      await pumpFarmerCard(tester, entry(givenDaysAgo: 400));
      expect(find.text('Outcome report pending · Received 400 days ago'), findsOneWidget);
    });
  });

  testWidgets('Farmer: the line is neutral at 3 days and at 400 (no warning colour)', (tester) async {
    await runIgnoringFontErrors(() async {
      Future<Color?> colour(int d) async {
        await pumpFarmerCard(tester, entry(givenDaysAgo: d));
        return tester.widget<Text>(find.byKey(const Key('reportPendingLine'))).style?.color;
      }

      expect(await colour(3), await colour(400));
      expect(await colour(3), AppConstants.onSurfaceVariant);
    });
  });

  testWidgets('Farmer: nothing received yet, or an outcome already recorded, shows no pending line', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpFarmerCard(tester, entry(givenDaysAgo: null));
      expect(find.byKey(const Key('reportPendingLine')), findsNothing);
      await pumpFarmerCard(tester, entry(givenDaysAgo: 12, outcome: 'thriving'));
      expect(find.byKey(const Key('reportPendingLine')), findsNothing);
    });
  });

  testWidgets('Farmer: Tagalog fits', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpFarmerCard(tester, entry(givenDaysAgo: 45), locale: const Locale('tl'));
      expect(find.textContaining('45 araw'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('the Farmer reminder notice and the in-app line use the same words, with no deadline', () {
    final en = jsonDecode(_read('lib/core/l10n/app_en.arb')) as Map<String, dynamic>;
    expect(en['farmerProgReportPending'] as String, contains('Outcome report pending · Received'));
    expect((en['farmerProgReportPending'] as String).toLowerCase().contains('due'), isFalse);
    expect(code, contains("'Outcome report pending'"));
  });
}

