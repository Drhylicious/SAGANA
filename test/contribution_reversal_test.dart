import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/contribution_model.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/data/services/staff_permission_service.dart';
import 'package:sagana/presentation/screens/admin/farmer_details_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// Contribution recording and reversal as the staff see it in Farmer Details:
/// each ledger entry shows who recorded it, a reversed entry is marked, and a
/// reversal asks for a reason and goes through the database function. The REAL
/// screen and repository run; only the network is replaced.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_reversal');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    await HiveService.init();
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-key',
      httpClient: fake,
    );
  });

  void ftest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (t) => runIgnoringFontErrors(() => body(t)));

  Map<String, Object?> entry(String id, num amount, String by, String at,
          {String source = 'member_payment', String? reverses, String? reason, String? note}) =>
      {
        'id': id,
        'farmer_id': 'farmer-1',
        'amount': amount,
        'source': source,
        'note': note,
        'recorded_by': by,
        'created_at': at,
        'reverses_event_id': reverses,
        'reversal_reason': reason,
      };

  void seed() {
    fake.reset();
    fake.on('GET /rest/v1/user_information', (r) {
      final q = Uri.decodeQueryComponent(r.url.query);
      // The recorder names are asked for with an "in" filter; the profile with "eq".
      if (q.contains('user_id=in.')) {
        return [
          {'user_id': 'off-1', 'full_name': 'Olivia One'},
          {'user_id': 'mgr-1', 'full_name': 'The Manager'},
        ];
      }
      return [
        {'user_id': 'farmer-1', 'full_name': 'Nora Five', 'username': 'nora', 'phone_number': '09170000000'},
      ];
    });
    fake.on('GET /rest/v1/user_roles', (_) => [{'status': 'active'}]);
    fake.on('GET /rest/v1/capital_contribution_events', (_) => [
      entry('e-pay', 100, 'mgr-1', '2026-03-03T08:00:00Z', note: 'March dues'),
      entry('e-rev', -2000, 'mgr-1', '2026-03-02T08:00:00Z', reverses: 'e-wrong', reason: 'Wrong member'),
      entry('e-wrong', 2000, 'off-1', '2026-03-01T08:00:00Z'),
      entry('e-pat', 700, 'mgr-1', '2026-02-20T08:00:00Z', source: 'patronage_capital'),
      entry('e-open', 300, 'off-1', '2026-02-10T08:00:00Z', source: 'opening_balance'),
      entry('e-extra', 50, 'off-1', '2026-02-01T08:00:00Z'),
    ]);
    fake.on('POST /rest/v1/rpc/reverse_capital_contribution', (_) => 'new-reversal-id');
  }

  Future<void> open(WidgetTester t) async {
    const members = StaffAccess.manage;
    const role = 'officer';
    await t.runAsync(() => HiveService.saveUserSession(userId: 'u-$role', email: 'x@y.z', role: role));
    StaffPermissions.instance.debugSet({StaffModule.members: members});
    seed();
    t.view.physicalSize = const Size(900, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FarmerDetailsScreen(farmerId: 'farmer-1'),
      ),
    );
    // The screen reads through a local cache (real file IO), so give it real time.
    for (var i = 0; i < 60 && find.text('Contribution').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));
      await t.pump(const Duration(milliseconds: 300));
    }
    t.takeException();
    await t.tap(find.widgetWithText(Tab, 'Contribution'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    t.takeException();
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 100));
    t.takeException();
  }

  // One widget test on purpose: the screen reads through a local cache (real file
  // IO), and a second widget test in the same file would stall on it (the Members
  // screen test is isolated for the same reason). The steps below follow one
  // visit to the Contribution tab.
  ftest('the ledger shows who recorded what; a reversal asks for a reason and goes through the database', (t) async {
    await open(t);
    List<RecordedRequest> reverseCalls() => fake.calls('POST /rest/v1/rpc/reverse_capital_contribution');
    Future<void> closeSheet() async {
      await t.tap(find.byIcon(Icons.close_rounded).last);
      await settle(t);
    }

    // ── The list: a reversed entry and its reversal are tagged; the rest are not.
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Cancellation'), findsOneWidget);
    expect(find.text('View all entries (6)'), findsOneWidget, reason: 'only four are previewed');

    // ── An entry: who recorded it and when, its note, and the way to reverse it.
    await t.tap(find.text('+₱100.00'));
    await settle(t);
    expect(find.text('Contribution Details'), findsOneWidget);
    expect(find.textContaining('Recorded by The Manager'), findsOneWidget);
    expect(find.text('Note: March dues'), findsOneWidget);
    expect(find.text('Cancel Contribution'), findsOneWidget);
    await closeSheet();

    // ── A reversed entry: who reversed it, when and why; it cannot be reversed again.
    await t.tap(find.text('+₱2000.00'));
    await settle(t);
    expect(find.textContaining('Recorded by Olivia One'), findsOneWidget);
    expect(find.textContaining('Cancelled by The Manager'), findsOneWidget);
    expect(find.text('Reason: Wrong member'), findsOneWidget);
    expect(find.text('Cancel Contribution'), findsNothing);
    await closeSheet();

    // ── The reversal itself: what it cancels; not reversible.
    await t.tap(find.text('−₱2000.00'));
    await settle(t);
    expect(find.textContaining('Cancels the ₱2,000.00 entry recorded by Olivia One'), findsOneWidget);
    expect(find.text('Reason: Wrong member'), findsOneWidget);
    expect(find.text('Cancel Contribution'), findsNothing);
    await closeSheet();

    // ── Older entries are reachable; a payout added to capital points to Balik-Tangkilik.
    await t.tap(find.text('View all entries (6)'));
    await settle(t);
    expect(find.text('Contribution History'), findsOneWidget);
    expect(find.text('+₱50.00'), findsOneWidget);
    await t.tap(find.text('+₱700.00').last);
    await settle(t);
    expect(find.textContaining('Balik-Tangkilik'), findsOneWidget);
    expect(find.text('Cancel Contribution'), findsNothing);
    await closeSheet();

    // ── An Officer with Members = View Only is told, and nothing is sent.
    StaffPermissions.instance.debugSet({StaffModule.members: StaffAccess.view});
    await t.tap(find.text('+₱100.00'));
    await settle(t);
    await t.tap(find.text('Cancel Contribution'));
    await settle(t);
    expect(find.text('You have view-only access to this module.'), findsOneWidget);
    expect(find.text('Reason for cancellation'), findsNothing);
    expect(reverseCalls(), isEmpty);
    await t.pump(const Duration(seconds: 4));
    StaffPermissions.instance.debugSet({StaffModule.members: StaffAccess.manage});

    // ── Manage: a reason is required (too short is refused in the dialog), cancel sends nothing.
    await t.tap(find.text('+₱100.00'));
    await settle(t);
    await t.tap(find.text('Cancel Contribution'));
    await settle(t);
    expect(find.text('Reason for cancellation'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'ab');
    await t.tap(find.text('Cancel Contribution').last);
    await settle(t);
    expect(find.text('Enter a reason (at least 3 characters).'), findsOneWidget);
    expect(reverseCalls(), isEmpty);
    await t.tap(find.text('Keep Contribution'));
    await settle(t);
    expect(reverseCalls(), isEmpty);

    // ── The database refuses (already reversed): its own words are shown.
    fake.on('POST /rest/v1/rpc/reverse_capital_contribution',
        (_) => const FakeError(400, 'This contribution has already been cancelled.'));
    await t.tap(find.text('+₱100.00'));
    await settle(t);
    await t.tap(find.text('Cancel Contribution'));
    await settle(t);
    await t.enterText(find.byType(TextField), 'Entered twice');
    await t.tap(find.text('Cancel Contribution').last);
    await settle(t);
    expect(find.text('This contribution has already been cancelled.'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));

    // ── It works: the entry and the trimmed reason go to the database function.
    fake.on('POST /rest/v1/rpc/reverse_capital_contribution', (_) => 'new-reversal-id');
    fake.requests.clear();
    await t.tap(find.text('+₱100.00'));
    await settle(t);
    await t.tap(find.text('Cancel Contribution'));
    await settle(t);
    await t.enterText(find.byType(TextField), '  Entered twice  ');
    await t.tap(find.text('Cancel Contribution').last);
    await settle(t);
    expect(reverseCalls(), hasLength(1));
    expect(reverseCalls().single.jsonMap, {'p_event_id': 'e-pay', 'p_reason': 'Entered twice'});
    expect(find.text('Contribution cancelled.'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  test('the model knows a reversal and what cannot be reversed', () {
    final normal = CapitalContributionEvent.fromMap(entry('a', 10, 'x', '2026-01-01T00:00:00Z'));
    final reversal = CapitalContributionEvent.fromMap(
        entry('b', -10, 'x', '2026-01-02T00:00:00Z', reverses: 'a', reason: 'oops'));
    final payout = CapitalContributionEvent.fromMap(
        entry('c', 5, 'x', '2026-01-03T00:00:00Z', source: 'patronage_capital'));
    expect(normal.canBeReversed, isTrue);
    expect(reversal.isReversal, isTrue);
    expect(reversal.canBeReversed, isFalse);
    expect(payout.canBeReversed, isFalse);
    expect(reversal.reversalReason, 'oops');
  });
}
