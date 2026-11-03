import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/utils/db_error_utils.dart';
import 'package:sagana/data/models/farmer_member_model.dart';
import 'package:sagana/data/repositories/account_management_repository.dart';
import 'package:sagana/data/repositories/farmer_details_repository.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/data/services/staff_permission_service.dart';
import 'package:sagana/presentation/navigation/app_router.dart';
import 'package:sagana/presentation/screens/admin/add_new_member_screen.dart';
import 'package:sagana/presentation/screens/admin/buyer_management_screen.dart';
import 'package:sagana/presentation/screens/admin/create_officer_account_screen.dart';
import 'package:sagana/presentation/screens/admin/manage_accounts_screen.dart';
import 'package:sagana/presentation/screens/admin/staff_accountability_screen.dart';
import 'package:sagana/presentation/widgets/officer_approval_notice.dart';
import 'package:sagana/presentation/widgets/view_only_banner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/test_storage_mocks.dart';

/// Code-level verification of T1-T22 (Officer permissions). The REAL
/// repositories, services and screens run; only the network is replaced by
/// [FakeSupabaseHttp], which records exactly what the app sends. Server-side
/// behaviour (SQL, RLS) is verified separately in test/sql_harness.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_code_verify');
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

  setUp(() {
    fake.reset();
    StaffPermissions.instance.debugSet(const {});
  });

  void ftest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (t) => runIgnoringFontErrors(() => body(t)));

  Future<void> setRole(WidgetTester t, String role) => t.runAsync(
    () => HiveService.saveUserSession(userId: 'u-$role', email: 'x@y.z', role: role),
  );

  Widget app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
    theme: AppTheme.lightTheme,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  // A router with a Home page under the screen, so context.pop() has somewhere to go.
  Future<GoRouter> pumpRouted(
    WidgetTester t,
    Widget screen, {
    Locale locale = const Locale('en'),
    Size size = const Size(420, 2400),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Center(child: Text('HOME')))),
        GoRoute(path: '/screen', builder: (_, __) => screen),
      ],
    );
    await t.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.lightTheme,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await t.pump();
    router.push('/screen');
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    t.takeException();
    return router;
  }

  Future<void> settle(WidgetTester t, [int ms = 700]) async {
    await t.pump(Duration(milliseconds: ms));
    await t.pump(const Duration(milliseconds: 100));
    t.takeException(); // test-font overflow only (see ignore_font_errors.dart)
  }

  const modules = ['dashboard', 'members', 'marketplace', 'loans', 'reports'];

  // ─────────────────────────────── T1 ───────────────────────────────
  group('T1 Create Officer', () {
    test('repository sends the chosen levels as p_permissions and no p_position', () async {
      fake.on('POST /rest/v1/rpc/create_officer_account', (_) => 'new-user-id');
      await AccountManagementRepository().createOfficerAccount(
        username: 'juan.reyes',
        password: 'Temp12345',
        surname: 'Reyes',
        firstName: 'Ana',
        access: {
          for (final m in StaffModule.values)
            m: m == StaffModule.loans ? StaffAccess.view : StaffAccess.manage,
        },
      );
      final sent = fake.calls('POST /rest/v1/rpc/create_officer_account');
      expect(sent.length, 1);
      final body = sent.single.jsonMap;
      expect(body['p_permissions'], {
        'dashboard': 'manage',
        'members': 'manage',
        'marketplace': 'manage',
        'loans': 'view',
        'reports': 'manage',
      });
      expect(body.containsKey('p_position'), isFalse);
      expect(body['p_surname'], 'Reyes');
      expect(body['p_first_name'], 'Ana');
    });

    ftest('form: no Position field; all five modules start on Manage; Loans can be lowered', (t) async {
      await setRole(t, 'admin');
      await pumpRouted(t, const CreateOfficerAccountScreen());
      expect(find.text('Position'), findsNothing);
      expect(find.text('Module Access'), findsOneWidget);
      StaffAccess selected(String m) => t
          .widget<SegmentedButton<StaffAccess>>(find.byKey(ValueKey('access-$m')))
          .selected
          .single;
      for (final m in modules) {
        expect(selected(m), StaffAccess.manage, reason: m);
      }
      await t.tap(find.descendant(of: find.byKey(const ValueKey('access-loans')), matching: find.text('View Only')));
      await t.pump();
      expect(selected('loans'), StaffAccess.view);
      expect(selected('members'), StaffAccess.manage);
    });

    Future<void> fillAndSubmit(WidgetTester t) async {
      fake.on('POST /rest/v1/rpc/check_username_available', (_) => 'available');
      fake.on('POST /rest/v1/rpc/create_officer_account', (_) => 'new-user-id');
      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), 'juan.reyes'); // username
      await settle(t, 800); // availability check is debounced
      await t.tap(find.text('AUTO')); // temporary password
      await t.pump();
      await t.enterText(find.widgetWithText(TextFormField, 'e.g. Dela Cruz'), 'Reyes');
      await t.enterText(find.widgetWithText(TextFormField, 'e.g. Juan or Marc Louie'), 'Ana');
      // Date of birth: open the picker and accept its default (25 years ago).
      await t.ensureVisible(find.text('Select').first);
      await t.tap(find.text('Select').first);
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('OK'));
      await t.pump(const Duration(milliseconds: 400));
      // Gender.
      await t.tap(find.text('Select').last);
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Female').last);
      await t.pump(const Duration(milliseconds: 400));
      // Lower Loans to View Only.
      await t.ensureVisible(find.byKey(const ValueKey('access-loans')));
      await t.tap(find.descendant(of: find.byKey(const ValueKey('access-loans')), matching: find.text('View Only')));
      await t.pump();
      await t.ensureVisible(find.text('Create Officer Account'));
      await t.tap(find.text('Create Officer Account'));
      await t.pump(const Duration(milliseconds: 200));
    }

    ftest('Manager submits through the real form: the RPC carries the levels', (t) async {
      await setRole(t, 'admin');
      await pumpRouted(t, const CreateOfficerAccountScreen());
      await fillAndSubmit(t);
      await settle(t);
      final sent = fake.calls('POST /rest/v1/rpc/create_officer_account');
      expect(sent.length, 1, reason: 'one create call');
      final b = sent.single.jsonMap;
      expect(b['p_username'], 'juan.reyes');
      expect(b['p_permissions']['loans'], 'view');
      expect(b['p_permissions']['dashboard'], 'manage');
      expect(b.containsKey('p_position'), isFalse);
      expect(find.text('HOME'), findsOneWidget, reason: 'screen closed after success');
      expect(find.byType(AlertDialog), findsNothing, reason: 'the Manager is not asked to confirm');
    });
  });

  // ─────────────────────────── T5 / T10 confirm step ───────────────────────────
  group('T5 Officer confirmation before submitting', () {
    ftest('Officer sees the Submit-for-approval dialog; Cancel creates nothing', (t) async {
      await setRole(t, 'officer');
      StaffPermissions.instance.debugSet({for (final m in StaffModule.values) m: StaffAccess.manage});
      bool? result;
      await t.pumpWidget(app(Builder(builder: (c) => TextButton(onPressed: () async => result = await confirmOfficerSubmission(c), child: const Text('go')))));
      await t.tap(find.text('go'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Submit for Manager approval?'), findsOneWidget);
      expect(find.textContaining('cannot use Farmer features until the Manager approves'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pump(const Duration(milliseconds: 400));
      expect(result, isFalse);

      await t.tap(find.text('go'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Submit'));
      await t.pump(const Duration(milliseconds: 400));
      expect(result, isTrue);
    });

    ftest('Manager is not asked; the message differs by role', (t) async {
      await setRole(t, 'admin');
      late AppLocalizations l10n;
      bool? result;
      await t.pumpWidget(app(Builder(builder: (c) {
        l10n = AppLocalizations.of(c);
        return TextButton(onPressed: () async => result = await confirmOfficerSubmission(c), child: const Text('go'));
      })));
      await t.tap(find.text('go'));
      await t.pump(const Duration(milliseconds: 300));
      expect(result, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(accountCreatedMessage(l10n, 'Created.'), 'Created.');
      await setRole(t, 'officer');
      expect(accountCreatedMessage(l10n, 'Created.'), 'Account submitted for Manager approval.');
    });

  });

  // ──────────────────── Create Farmer Account: three steps ────────────────────
  group('Create Farmer Account (Personal, Address, Summary)', () {
    Future<void> fillPersonal(WidgetTester t, {String username = 'juan.reyes'}) async {
      fake.on('POST /rest/v1/rpc/check_username_available', (_) => 'available');
      await t.enterText(find.byType(TextFormField).at(0), username);
      await settle(t, 800); // the availability check is debounced
      await t.tap(find.text('AUTO')); // temporary password
      await t.pump();
      await t.enterText(find.widgetWithText(TextFormField, 'e.g. Dela Cruz'), 'Reyes');
      await t.enterText(find.widgetWithText(TextFormField, 'e.g. Juan or Marc Louie'), 'Ana');
      await t.ensureVisible(find.text('Select').first);
      await t.tap(find.text('Select').first);
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('OK'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Select').last);
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Female').last);
      await t.pump(const Duration(milliseconds: 400));
    }

    Future<void> next(WidgetTester t) async {
      await t.ensureVisible(find.text('Next'));
      await t.tap(find.text('Next'));
      await settle(t);
    }

    Future<void> fillAddress(WidgetTester t) async {
      await t.enterText(find.widgetWithText(TextFormField, 'Street *'), 'Rizal St.');
      await t.enterText(find.widgetWithText(TextFormField, 'House No. *'), '12');
    }

    ftest('step 1 has no Cooperative Membership or Initial Crops; Next opens the Address step', (t) async {
      await setRole(t, 'admin');
      await pumpRouted(t, const AddNewMemberScreen());
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('Personal Information'), findsWidgets);
      expect(find.text('Cooperative Membership'), findsNothing);
      expect(find.text('Initial Crops'), findsNothing);
      await fillPersonal(t);
      await next(t);
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Address Information'), findsWidgets);
      expect(find.widgetWithText(TextFormField, 'Street *'), findsOneWidget);
      // The fixed service area is shown, locked.
      expect(find.text('Payanas'), findsOneWidget);
    });

    ftest('the Address step will not continue with a blank street', (t) async {
      await setRole(t, 'admin');
      await pumpRouted(t, const AddNewMemberScreen());
      await fillPersonal(t);
      await next(t);
      await t.enterText(find.widgetWithText(TextFormField, 'House No. *'), '12');
      await next(t);
      expect(find.text('Step 2 of 3'), findsOneWidget, reason: 'stays on the address step');
    });

    ftest('Back keeps what was typed', (t) async {
      await setRole(t, 'admin');
      await pumpRouted(t, const AddNewMemberScreen());
      await fillPersonal(t);
      await next(t);
      await fillAddress(t);
      await t.ensureVisible(find.text('Back'));
      await t.tap(find.text('Back'));
      await settle(t);
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('juan.reyes'), findsOneWidget);
    });

    ftest('the Summary shows the details and never the password', (t) async {
      await setRole(t, 'admin');
      await pumpRouted(t, const AddNewMemberScreen());
      await fillPersonal(t);
      // Read the generated temporary password so we can prove it is not on screen.
      final password = t
          .widgetList<TextFormField>(find.byType(TextFormField))
          .map((w) => w.controller?.text ?? '')
          .firstWhere((v) => v.length >= 8 && v != 'juan.reyes');
      await next(t);
      await fillAddress(t);
      await next(t);
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Review and Confirm'), findsWidgets);
      expect(find.text('Ana Reyes'), findsOneWidget);
      expect(find.text('juan.reyes'), findsOneWidget);
      expect(find.textContaining('Rizal St.'), findsOneWidget);
      expect(find.textContaining(password), findsNothing);
      expect(find.text('Create Farmer Account'), findsOneWidget);
    });

    ftest('Manager: creating sends the address, no membership fields, then shows the username', (t) async {
      await setRole(t, 'admin');
      fake.on('POST /rest/v1/rpc/create_farmer_account', (_) => 'new-user-id');
      await pumpRouted(t, const AddNewMemberScreen());
      await fillPersonal(t);
      await next(t);
      await fillAddress(t);
      await next(t);
      await t.ensureVisible(find.text('Create Farmer Account'));
      await t.tap(find.text('Create Farmer Account'));
      await settle(t);

      final sent = fake.calls('POST /rest/v1/rpc/create_farmer_account');
      expect(sent.length, 1);
      final b = sent.single.jsonMap;
      expect(b['p_username'], 'juan.reyes');
      expect(b['p_street'], 'Rizal St.');
      expect(b['p_house_no'], '12');
      expect(b['p_building'], isNull);
      for (final removed in ['p_initial_contribution', 'p_initial_crops', 'p_share_value_per_unit', 'p_membership_year']) {
        expect(b.containsKey(removed), isFalse, reason: '$removed is no longer sent');
      }
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'the Manager is not asked first; the result dialog shows');
      expect(find.text('Account Created'), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      expect(find.descendant(of: dialog, matching: find.textContaining('juan.reyes')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.textContaining('temporary password')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.textContaining('waiting for the Manager')), findsNothing);
      await t.tap(find.text('Close'));
      await settle(t);
      expect(find.text('HOME'), findsOneWidget, reason: 'the form closes');
    });

    ftest('Officer: confirms first (Cancel sends nothing), then the account waits for the Manager', (t) async {
      await setRole(t, 'officer');
      StaffPermissions.instance.debugSet({for (final m in StaffModule.values) m: StaffAccess.manage});
      fake.on('POST /rest/v1/rpc/create_farmer_account', (_) => 'new-user-id');
      await pumpRouted(t, const AddNewMemberScreen());
      await fillPersonal(t, username: 'maria.cruz');
      await next(t);
      await fillAddress(t);
      await next(t);
      await t.ensureVisible(find.text('Create Farmer Account'));
      await t.tap(find.text('Create Farmer Account'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Submit for Manager approval?'), findsOneWidget);
      expect(fake.calls('POST /rest/v1/rpc/create_farmer_account'), isEmpty, reason: 'nothing sent before confirming');
      await t.tap(find.text('Cancel'));
      await t.pump(const Duration(milliseconds: 400));
      expect(fake.calls('POST /rest/v1/rpc/create_farmer_account'), isEmpty);

      await t.tap(find.text('Create Farmer Account'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Submit'));
      await settle(t);
      expect(fake.calls('POST /rest/v1/rpc/create_farmer_account').length, 1);
      expect(find.text('Account Created'), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      expect(find.descendant(of: dialog, matching: find.textContaining('waiting for the Manager')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.textContaining('maria.cruz')), findsOneWidget);
    });

    ftest('a taken username stops the first step', (t) async {
      await setRole(t, 'admin');
      await pumpRouted(t, const AddNewMemberScreen());
      await fillPersonal(t);
      fake.on('POST /rest/v1/rpc/check_username_available', (_) => 'taken');
      await t.enterText(find.byType(TextFormField).at(0), 'juan.reyes2');
      await settle(t, 800);
      await next(t);
      expect(find.text('Step 1 of 3'), findsOneWidget);
    });
  });

  // ─────────────────────────── T2 / T14 / T15 / T18 guards ───────────────────────────
  group('T2 View Only guards', () {
    ftest('requireManage: View Only -> toast and false; Manage -> true; Manager -> true', (t) async {
      bool? got;
      Future<void> pumpButton() => t.pumpWidget(app(Builder(builder: (c) => TextButton(
        onPressed: () => got = requireManage(c, StaffModule.loans),
        child: const Text('act'),
      ))));

      await setRole(t, 'officer');
      StaffPermissions.instance.debugSet({StaffModule.loans: StaffAccess.view});
      await pumpButton();
      await t.tap(find.text('act'));
      await t.pump(const Duration(milliseconds: 200));
      expect(got, isFalse);
      expect(find.text('You have view-only access to this module.'), findsOneWidget);
      await t.pump(const Duration(seconds: 4)); // toast timer

      StaffPermissions.instance.debugSet({StaffModule.loans: StaffAccess.manage});
      await t.tap(find.text('act'));
      await t.pump(const Duration(milliseconds: 200));
      expect(got, isTrue);
      expect(find.text('You have view-only access to this module.'), findsNothing);

      await setRole(t, 'admin');
      StaffPermissions.instance.debugSet(const {});
      await t.tap(find.text('act'));
      await t.pump(const Duration(milliseconds: 200));
      expect(got, isTrue, reason: 'the Manager always passes');
    });

    String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

    test('every named management handler starts with a guard for its module', () {
      const guards = <String, List<String>>{
        'lib/presentation/screens/admin/admin_inventory_screen.dart': ['_showAddSheet', '_showAdjustSheet', '_showEditSheet', '_confirmDeleteItem', '_showReorderLevelDialog'],
        'lib/presentation/screens/admin/crop_management_screen.dart': ['_showCropSheet', '_confirmDelete', '_archiveWithConfirm'],
        'lib/presentation/screens/admin/crop_request_approval_screen.dart': ['_showReviewModal'],
        'lib/presentation/screens/admin/program_management_screen.dart': ['_confirmDeleteProgram', '_showProgramSheet', '_showAddProductSheet', '_showDistributeSheet', '_showRecordReturnSheet', '_showRecordOutcomeSheet', '_showConvertToLoanSheet', '_showAddActivitySheet'],
        'lib/presentation/screens/admin/program_enrollment_requests_screen.dart': ['_showReviewModal'],
        'lib/presentation/screens/admin/program_purchase_review_screen.dart': ['_showReviewSheet'],
        'lib/presentation/screens/admin/price_management_screen.dart': ['_openUpdateSheet', '_openAddSheet'],
        'lib/presentation/screens/admin/loan_item_management_screen.dart': ['_archiveWithConfirm', '_restore', '_showLoanSettingsSheet'],
        'lib/presentation/screens/admin/farmer_management_screen.dart': ['_showAddMemberTypeSheet', '_confirmDeleteRejected', '_approveMember', '_rejectMember', '_suspendMemberFlow', '_onMenuSelected'],
        'lib/presentation/screens/admin/farmer_details_screen.dart': ['_recordContribution', '_reverseEntry'],
        'lib/presentation/screens/admin/manage_accounts_screen.dart': ['_resolveRequest'],
        'lib/presentation/screens/admin/listing_review_screen.dart': ['_confirmApprove', '_showRejectSheet'],
        'lib/presentation/screens/admin/all_listings_screen.dart': ['_quickApprove'],
        'lib/presentation/screens/admin/listing_edit_request_screen.dart': ['_approve', '_disapprove'],
        'lib/presentation/screens/admin/admin_order_detail_screen.dart': ['_confirmApprove', '_confirmReady', '_confirmOut', '_markDelivered'],
        'lib/presentation/screens/admin/market_linking_screen.dart': ['_showCompleteSale', '_reviewCancellation', '_confirmDelete'],
        'lib/presentation/screens/admin/da_amad_enrollment_screen.dart': ['_showReviewModal'],
        'lib/presentation/screens/admin/loan_details_screen.dart': ['_markAsPaid'],
        'lib/presentation/screens/admin/loan_requests_screen.dart': ['_approve', '_disapprove'],
        'lib/presentation/screens/admin/loan_dashboard_screen.dart': ['_goToIssueLoan', '_goToPayment'],
        'lib/presentation/screens/admin/export_center_screen.dart': ['_generate'],
        // Shared with the Farmer: the guard is staff-only (_cooperativeMayAct).
        'lib/presentation/screens/shared/coop_offer_negotiation_screen.dart': ['_accept', '_counter', '_confirmReceipt', '_end'],
      };
      final missing = <String>[];
      guards.forEach((file, handlers) {
        final src = read(file);
        for (final h in handlers) {
          // Find the DEFINITION (not a call site); the guard must open its body.
          final def = RegExp('(Future<[\\w<>?]+>|void|bool)\\s+$h\\(').firstMatch(src);
          final head = def == null
              ? ''
              : src.substring(def.start, (def.start + 700).clamp(0, src.length));
          final guarded = head.contains('requireManage(') ||
              head.contains('canManageModule(') ||
              head.contains('_cooperativeMayAct(');
          if (!guarded) missing.add('$file :: $h');
        }
      });
      expect(missing, isEmpty, reason: 'handlers without a guard:\n${missing.join('\n')}');
    });

    test('Record Payment is guarded at BOTH entry points (Loan Details button and Loan Dashboard)', () {
      final details = read('lib/presentation/screens/admin/loan_details_screen.dart');
      final at = details.indexOf('AppRoutes.recordPayment');
      expect(details.substring(at - 250, at), contains('requireManage(context, StaffModule.loans)'));
    });

    test('the shared offer screen blocks only the cooperative side, never the Farmer', () {
      final src = read('lib/presentation/screens/shared/coop_offer_negotiation_screen.dart');
      final at = src.indexOf('bool _cooperativeMayAct()');
      final body = src.substring(at, src.indexOf(';', at));
      expect(body, contains('_forFarmer ||'), reason: 'a Farmer always passes');
      expect(body, contains('requireManage(context, StaffModule.marketplace)'));
      // The Farmer-only actions are not guarded.
      expect(src.substring(src.indexOf('Future<void> _deliver('), src.indexOf('Future<void> _confirmReceipt(')), isNot(contains('_cooperativeMayAct')));
    });

    test('Broadcast has no module guard: every Officer can use it, any time', () {
      final src = read('lib/presentation/screens/admin/notification_broadcast_screen.dart');
      expect(src.contains('requireManage('), isFalse);
      expect(src.contains('canManageModule('), isFalse);
      expect(src.contains('StaffModule.'), isFalse);
    });

    test('Crop restore is guarded', () {
      final src = read('lib/presentation/screens/admin/crop_management_screen.dart');
      final at = src.indexOf('onRestore: () async {');
      expect(src.substring(at, at + 200), contains('requireManage(context, StaffModule.dashboard)'));
    });

    test('Add Member / Issue Loan / Record Payment routes close to View Only Officers; Add Officer to every Officer', () {
      expect(AppRouter.manageOnlyPaths.keys, containsAll(['/admin/farmers/add', '/admin/loans/issue', '/admin/loans/payment']));
      expect(AppRouter.manageOnlyPaths.keys, isNot(contains('/admin/members/add-officer')));
      expect(AppRouter.managerOnlyPaths, contains('/admin/members/add-officer'));
    });
  });

  // ─────────────────────────────── T3 ───────────────────────────────
  group('T3 live permission changes', () {
    ftest('refresh() reads the levels from the server and the strip follows a change', (t) async {
      await setRole(t, 'officer');
      var loans = 'view';
      fake.on('POST /rest/v1/rpc/get_my_staff_permissions', (_) => {
        'dashboard': 'manage', 'members': 'view', 'marketplace': 'manage', 'loans': loans, 'reports': 'manage',
      });
      await t.pumpWidget(app(const Scaffold(body: ViewOnlyStrip(module: StaffModule.loans))));
      await t.runAsync(() => StaffPermissions.instance.refresh());
      await t.pump();
      expect(StaffPermissions.instance.canManage(StaffModule.loans), isFalse);
      expect(StaffPermissions.instance.canManage(StaffModule.dashboard), isTrue);
      expect(find.text('Loans · View Only'), findsOneWidget);

      loans = 'manage'; // the Manager changes it
      await t.runAsync(() => StaffPermissions.instance.refresh());
      await t.pump();
      expect(StaffPermissions.instance.canManage(StaffModule.loans), isTrue);
      expect(find.text('Loans · View Only'), findsNothing, reason: 'the strip disappears with no sign-out');
      expect(HiveService.getStaffAccess()?['loans'], 'manage', reason: 'cached for offline use');
    });

    ftest('an unreadable answer keeps the last known levels (never grants Manage)', (t) async {
      await setRole(t, 'officer');
      StaffPermissions.instance.debugSet({StaffModule.loans: StaffAccess.view});
      fake.on('POST /rest/v1/rpc/get_my_staff_permissions', (_) => const FakeError(500, 'down'));
      await t.runAsync(() => StaffPermissions.instance.refresh());
      expect(StaffPermissions.instance.canManage(StaffModule.loans), isFalse);
    });

    test('the live listener watches only the signed-in Officer\'s own permission rows', () {
      final src = File('lib/data/services/staff_permission_service.dart').readAsStringSync();
      expect(src, contains(".from('officer_permissions')"));
      expect(src, contains(".stream(primaryKey: ['user_id', 'module'])"));
      expect(src, contains(".eq('user_id', uid)"));
      final hive = File('lib/data/services/hive_service.dart').readAsStringSync();
      expect(hive, contains("delete('staff_access_levels')"), reason: 'cache cleared on sign-out');
    });
  });

  // ─────────────────────────────── T4 ───────────────────────────────
  group('T4 view-only refusal reaches the person', () {
    test('a 403 from the gate becomes the readable message through the real client', () async {
      const msg = 'Your Officer account has view-only access to the dashboard module. Ask the Manager to give you Manage access.';
      fake.on('DELETE /rest/v1/broadcast_logs', (_) => const FakeError(403, msg, code: '42501'));
      Object? caught;
      try {
        await Supabase.instance.client
            .from('broadcast_logs')
            .delete()
            .eq('id', '00000000-0000-0000-0000-000000000000');
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<PostgrestException>());
      expect(friendlyErrorMessage(caught!), msg);
    });
  });

  // ──────────────── Sign-in of pending applicants (no login ban) ────────────────
  group('Pending applicants sign in; the password change comes first', () {
    String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

    test('only a suspended Farmer is stopped at sign-in; pending and disapproved are not', () {
      final src = read('lib/data/services/auth_service.dart');
      expect(src, contains("role == 'farmer' && memberStatus == 'suspended'"));
      expect(src.contains("memberStatus == 'pending'"), isFalse);
      expect(src.contains("memberStatus == 'rejected'"), isFalse);
      // The old ban message is gone.
      expect(src.contains('loginAwaitingApproval'), isFalse);
      expect(src.contains('user_banned'), isFalse);
    });

    test('the forced password change is checked before the Pending screen', () {
      final src = read('lib/presentation/navigation/app_router.dart');
      final mustChange = src.indexOf('HiveService.getMustChangePassword()');
      final held = src.indexOf("const held = {'draft', 'pending', 'rejected'};");
      expect(mustChange, greaterThan(0));
      expect(held, greaterThan(0));
      expect(mustChange, lessThan(held), reason: 'a temporary password is changed first, whatever the status');
    });

    test('an approved applicant still sees the Continue step', () {
      final src = read('lib/presentation/navigation/app_router.dart');
      expect(src, contains("cachedStatus == 'active' &&"));
      expect(src, contains('HiveService.getPendingAcknowledgement()'));
    });
  });

  // ──────────────── Members: applicants an Officer created ────────────────
  group('Members list: who may decide or delete an applicant', () {
    List<MemberListAction> offered(MemberStatus st, {required bool officer, required bool officerCreated}) =>
        st.listActionsFor(isOfficer: officer, officerCreated: officerCreated);

    test('Manager: decides every applicant (self-registered or Officer-created); deletes a disapproved one', () {
      for (final created in [false, true]) {
        expect(offered(MemberStatus.pending, officer: false, officerCreated: created),
            containsAll([MemberListAction.approve, MemberListAction.disapprove]), reason: 'created=$created');
        expect(offered(MemberStatus.rejected, officer: false, officerCreated: created),
            contains(MemberListAction.deleteApplicant), reason: 'created=$created');
      }
    });

    test('Officer: cannot decide an applicant an Officer created', () {
      final menu = offered(MemberStatus.pending, officer: true, officerCreated: true);
      expect(menu, isNot(contains(MemberListAction.approve)));
      expect(menu, isNot(contains(MemberListAction.disapprove)));
      expect(menu, contains(MemberListAction.viewProfile));
    });

    test('Officer: still decides a self-registered applicant', () {
      expect(offered(MemberStatus.pending, officer: true, officerCreated: false),
          containsAll([MemberListAction.approve, MemberListAction.disapprove]));
    });

    test('Officer: can never delete a disapproved account, whoever created it', () {
      for (final created in [false, true]) {
        expect(offered(MemberStatus.rejected, officer: true, officerCreated: created),
            isNot(contains(MemberListAction.deleteApplicant)), reason: 'created=$created');
      }
    });

    test('nothing else changes: every other action is offered as before', () {
      for (final st in MemberStatus.values) {
        final base = st.listActions.toSet();
        // The Manager sees exactly the original menu.
        expect(offered(st, officer: false, officerCreated: true).toSet(), base, reason: '$st manager');
        // An Officer sees the original menu minus the three restricted actions.
        final restricted = {
          MemberListAction.approve, MemberListAction.disapprove, MemberListAction.deleteApplicant,
        };
        expect(offered(st, officer: true, officerCreated: true).toSet(), base.difference(restricted), reason: '$st officer');
      }
    });

    String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

    test('the card builds its menu from that rule, and a stray action from an Officer is ignored', () {
      final src = read('lib/presentation/screens/admin/farmer_management_screen.dart');
      expect(src, contains('status.listActionsFor('));
      expect(src, contains('officerCreated: source != null'));
      for (final guard in [
        "case 'approve':\n        if (HiveService.isOfficer && _sources.containsKey(farmer.userId)) return;",
        "case 'reject':\n        if (HiveService.isOfficer && _sources.containsKey(farmer.userId)) return;",
        "case 'delete':\n        if (HiveService.isOfficer) return;",
      ]) {
        expect(src, contains(guard));
      }
    });

    test('an Officer going to Add Member opens the Farmer form directly (no Officer option)', () {
      final src = read('lib/presentation/screens/admin/farmer_management_screen.dart');
      final at = src.indexOf('void _showAddMemberTypeSheet()');
      final head = src.substring(at, at + 600);
      expect(head, contains('if (HiveService.isOfficer)'));
      expect(head, contains('AppRoutes.addNewMember'));
    });
  });

  // ─────────────────────────────── T11 ───────────────────────────────
  group('T11 Manager-only routes (real router redirect)', () {
    Future<String> resolve(WidgetTester t, BuildContext ctx, GoRouter router, String path) async {
      final match = await router.routeInformationParser.parseRouteInformationWithDependencies(
        RouteInformation(uri: Uri.parse(path), state: RouteInformationState<void>(type: NavigatingType.go)),
        ctx,
      );
      return match.uri.path;
    }

    Future<(GoRouter, BuildContext)> boot(WidgetTester t) async {
      late BuildContext ctx;
      await t.pumpWidget(app(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      final router = AppRouter.create();
      await resolve(t, ctx, router, '/'); // the first navigation of a boot goes through Splash
      return (router, ctx);
    }

    ftest('Officer is sent to the dashboard from Staff Accountability, Add Officer and Balik, even with Manage everywhere', (t) async {
      await setRole(t, 'officer');
      StaffPermissions.instance.debugSet({for (final m in StaffModule.values) m: StaffAccess.manage});
      final (router, ctx) = await boot(t);
      for (final p in ['/admin/accountability', '/admin/members/add-officer', '/admin/balik-tangkilik']) {
        expect(await resolve(t, ctx, router, p), '/admin/dashboard', reason: p);
      }
    });

    ftest('the Manager opens all three', (t) async {
      await setRole(t, 'admin');
      final (router, ctx) = await boot(t);
      for (final p in ['/admin/accountability', '/admin/members/add-officer', '/admin/balik-tangkilik']) {
        expect(await resolve(t, ctx, router, p), p, reason: p);
      }
    });

    ftest('an Officer opens the Members screens they used to be blocked from', (t) async {
      await setRole(t, 'officer');
      StaffPermissions.instance.debugSet({for (final m in StaffModule.values) m: StaffAccess.view});
      final (router, ctx) = await boot(t);
      for (final p in ['/admin/farmers', '/admin/members/farmer-accounts', '/admin/members/officer-accounts', '/admin/loans', '/admin/reports']) {
        expect(await resolve(t, ctx, router, p), p, reason: p);
      }
    });

    ftest('create-only screens close to View Only and open to Manage', (t) async {
      await setRole(t, 'officer');
      StaffPermissions.instance.debugSet({StaffModule.members: StaffAccess.view, StaffModule.loans: StaffAccess.view});
      final (router, ctx) = await boot(t);
      for (final p in ['/admin/farmers/add', '/admin/loans/issue', '/admin/loans/payment']) {
        expect(await resolve(t, ctx, router, p), '/admin/dashboard', reason: 'View Only $p');
      }
      StaffPermissions.instance.debugSet({StaffModule.members: StaffAccess.manage, StaffModule.loans: StaffAccess.manage});
      for (final p in ['/admin/farmers/add', '/admin/loans/issue', '/admin/loans/payment']) {
        expect(await resolve(t, ctx, router, p), p, reason: 'Manage $p');
      }
    });
  });

  // ─────────────────────────────── T12 ───────────────────────────────
  group('T12 approval history', () {
    test('the history query asks for the staff name and role and parses them', () async {
      fake.on('GET /rest/v1/member_status_events', (_) => [
        {'from_status': 'pending', 'to_status': 'active', 'reason': 'Application approved', 'created_at': '2026-11-03T01:00:00Z', 'actor_name': 'Olivia One', 'actor_role': 'officer'},
        {'from_status': 'active', 'to_status': 'suspended', 'reason': 'Late', 'created_at': '2026-11-04T01:00:00Z', 'actor_name': 'The Manager', 'actor_role': 'admin'},
      ]);
      final events = await FarmerDetailsRepository().fetchStatusHistory('farmer-1');
      final q = fake.calls('GET /rest/v1/member_status_events').single.url.queryParameters['select']!;
      expect(q, contains('actor_name'));
      expect(q, contains('actor_role'));
      expect(events.length, 2);
      expect(events.first.actorName, 'Olivia One');
      expect(events.first.actorRole, 'officer');
      expect(events.last.actorRole, 'admin');
      expect(MemberStatusEvent.fromMap({'to_status': 'active', 'created_at': '2026-11-03T01:00:00Z'}).actorName, isNull);
    });

    test('the history card is Manager-only and always visible to the Manager', () {
      final src = File('lib/presentation/screens/admin/farmer_details_screen.dart').readAsStringSync();
      final at = src.indexOf('_StatusHistoryCard(');
      final cond = src.substring(src.lastIndexOf('if (_statusHistory.isNotEmpty', at), at);
      expect(cond, contains('!HiveService.isOfficer'));
      expect(cond, isNot(contains('MemberStatus.pending')), reason: 'no longer hidden after approval');
      expect(src, contains('l10n.farmerDetailsHistoryBy('));
    });
  });

  // ─────────────────────────────── T13 / T14 ───────────────────────────────
  group('T13/T14 Manage Accounts (Members)', () {
    void seed() {
      fake.on('GET /rest/v1/user_roles', (r) {
        final role = r.url.queryParameters['role']?.replaceFirst('eq.', '');
        if (role == 'farmer') return [{'user_id': 'f-1', 'status': 'active'}];
        if (role == 'officer') return [{'user_id': 'o-9', 'status': 'active'}];
        if (role == 'admin') return [{'user_id': 'm-1', 'status': 'active'}];
        return <Object?>[];
      });
      fake.on('GET /rest/v1/user_information', (_) => [
        {'user_id': 'f-1', 'full_name': 'Farah Reyes', 'username': 'sp3-0009'},
        {'user_id': 'o-9', 'full_name': 'Olga Nine', 'username': 'off-0009'},
        {'user_id': 'm-1', 'full_name': 'Drhy Licious', 'username': null},
      ]);
    }

    ftest('Management tab: the Manager first and display-only, then the Officers; Requests tab kept', (t) async {
      for (final role in ['admin', 'officer']) {
        await setRole(t, role);
        StaffPermissions.instance.debugSet({StaffModule.members: StaffAccess.manage});
        seed();
        await pumpRouted(t, const ManageAccountsScreen(initialTab: 'officer'));
        await settle(t);
        expect(find.text('Management'), findsOneWidget, reason: role);
        expect(find.text('Officers'), findsNothing, reason: role);
        expect(find.text('Requests'), findsOneWidget, reason: role);
        // Manager above the Officer.
        final manager = t.getTopLeft(find.text('Drhy Licious'));
        final officer = t.getTopLeft(find.text('Olga Nine'));
        expect(manager.dy, lessThan(officer.dy), reason: role);
        expect(find.text('Manager'), findsOneWidget);
        expect(find.text('Officer'), findsOneWidget);
        // Tapping the Manager opens nothing.
        await t.tap(find.text('Drhy Licious'), warnIfMissed: false);
        await settle(t);
        expect(find.text('Reset Password'), findsNothing, reason: role);
        expect(find.text('Edit Access'), findsNothing, reason: role);
      }
    });

    ftest('Manage Accounts is display-only: tapping any account opens nothing', (t) async {
      for (final role in ['admin', 'officer']) {
        await setRole(t, role);
        StaffPermissions.instance.debugSet({StaffModule.members: StaffAccess.manage});
        seed();
        // Management tab: the Manager and the Officer.
        await pumpRouted(t, const ManageAccountsScreen(initialTab: 'officer'));
        await settle(t);
        for (final name in ['Drhy Licious', 'Olga Nine']) {
          await t.tap(find.text(name), warnIfMissed: false);
          await settle(t);
          expect(find.text('Reset Password'), findsNothing, reason: '$role / $name');
          expect(find.text('Edit Access'), findsNothing, reason: '$role / $name');
          expect(find.text('You have view-only access to this module.'), findsNothing, reason: '$role / $name');
        }
        // Farmers tab.
        await pumpRouted(t, const ManageAccountsScreen());
        await settle(t);
        await t.tap(find.text('Farah Reyes'), warnIfMissed: false);
        await settle(t);
        expect(find.text('Reset Password'), findsNothing, reason: '$role / farmer');
      }
    });

    test('the account list has no tap handler and no Reset Password / Edit Access modal', () {
      final src = File('lib/presentation/screens/admin/manage_accounts_screen.dart').readAsStringSync();
      expect(src.contains('_showAccountActions'), isFalse);
      expect(src.contains('showOfficerAccessSheet'), isFalse);
      expect(src.contains('showManagementModal'), isFalse);
      // The Requests tab (a person asked for help) still resets and resolves.
      expect(src, contains('_resolveRequest'));
    });
  });

  // ─────────────────────────────── T19 ───────────────────────────────
  group('T19 Buyers', () {
    ftest('Buyer Management filters are All / Active / Inactive only', (t) async {
      await setRole(t, 'admin');
      await pumpRouted(t, const BuyerManagementScreen());
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 400))); // Hive cache read is real IO
      await settle(t);
      expect(find.textContaining('All ('), findsOneWidget);
      expect(find.textContaining('Active ('), findsOneWidget);
      expect(find.textContaining('Inactive ('), findsOneWidget);
      expect(find.textContaining('Suspended'), findsNothing);
    });
  });

  // ─────────────────────────────── T20 ───────────────────────────────
  group('T20 Staff Accountability screen', () {
    final rows = [
      {
        'id': 'a1', 'admin_id': 'o-1', 'actor_name': 'Olivia One', 'actor_role': 'officer', 'module': 'prices',
        'action_type': 'updated', 'operation': 'updated', 'table_name': 'price_records', 'record_id': 'r-1',
        'reference_label': 'Tomato', 'description': 'Updated price records: Tomato',
        'old_values': {'price_per_kg': 40}, 'new_values': {'price_per_kg': 45}, 'created_at': '2026-11-03T08:30:00Z',
      },
      {
        'id': 'a2', 'admin_id': 'm-1', 'actor_name': 'The Manager', 'actor_role': 'admin', 'module': 'crops',
        'action_type': 'created', 'operation': 'created', 'table_name': 'crop_master', 'record_id': 'c-1',
        'reference_label': 'Ginger', 'description': 'Created crop master: Ginger',
        'old_values': null, 'new_values': {'crop_name': 'Ginger'}, 'created_at': '2026-11-03T07:00:00Z',
      },
      {
        'id': 'a3', 'admin_id': 'o-2', 'actor_name': 'Omar Two', 'actor_role': 'officer', 'module': 'members',
        'action_type': 'updated', 'operation': 'updated', 'table_name': 'user_roles', 'record_id': 'r-2',
        'reference_label': 'Farah One', 'description': 'Updated user roles: Farah One',
        'old_values': {'status': 'active', 'suspension_reason': null},
        'new_values': {'status': 'suspended', 'suspension_reason': 'Unpaid contributions'},
        'created_at': '2026-11-03T06:00:00Z',
      },
      {
        'id': 'a4', 'admin_id': 'o-2', 'actor_name': 'Omar Two', 'actor_role': 'officer', 'module': 'members',
        'action_type': 'created', 'operation': 'created', 'table_name': 'capital_contribution_events', 'record_id': 'r-3',
        'reference_label': 'Farah One', 'description': 'Created capital contribution events: Farah One',
        'old_values': null, 'new_values': {'amount': 250, 'source': 'member_payment', 'note': 'March'},
        'created_at': '2026-11-03T05:00:00Z',
      },
    ];

    void seed() {
      fake.on('GET /rest/v1/admin_activity_log', (r) {
        var out = rows;
        return out;
      });
      fake.on('GET /rest/v1/user_roles', (_) => [{'user_id': 'o-1', 'role': 'officer'}, {'user_id': 'm-1', 'role': 'admin'}]);
      fake.on('GET /rest/v1/user_information', (_) => [{'user_id': 'o-1', 'full_name': 'Olivia One'}, {'user_id': 'm-1', 'full_name': 'The Manager'}]);
    }

    ftest('shows who, role, what, module and time; expands to before and after', (t) async {
      await setRole(t, 'admin');
      seed();
      await pumpRouted(t, const StaffAccountabilityScreen());
      await settle(t);
      // Everything the database wrote, plus the report exports (which the app records).
      final or = fake.calls('GET /rest/v1/admin_activity_log').first.url.queryParameters['or']!;
      expect(or, contains('source.eq.db'));
      expect(or, contains('and(source.eq.app,module.eq.reports,action_type.eq.exported)'));
      expect(find.text('Changed price: Tomato'), findsOneWidget);
      expect(find.textContaining('Olivia One · Officer'), findsOneWidget);
      expect(find.textContaining('The Manager · Manager'), findsOneWidget);
      await t.tap(find.text('Changed price: Tomato'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Before: 40'), findsOneWidget);
      expect(find.textContaining('After: 45'), findsOneWidget);
      expect(find.textContaining('Record: Tomato'), findsOneWidget);
    });

    ftest('Members actions read as sentences: what, to whom, by whom, and the reason or note', (t) async {
      await setRole(t, 'admin');
      seed();
      await pumpRouted(t, const StaffAccountabilityScreen());
      await settle(t);
      expect(find.text('Suspended Farah One'), findsOneWidget);
      expect(find.text('Reason: Unpaid contributions'), findsOneWidget);
      expect(find.text('Recorded a contribution of ₱250.00 for Farah One'), findsOneWidget);
      expect(find.text('Note: March'), findsOneWidget);
      expect(find.textContaining('Omar Two · Officer'), findsNWidgets(2));
      // The database wording is replaced for these rows, and every other row reads as a sentence too.
      expect(find.text('Updated user roles: Farah One'), findsNothing);
      expect(find.text('Updated price records: Tomato'), findsNothing);
      expect(find.text('Changed price: Tomato'), findsOneWidget);
    });

    ftest('the chips work by tapping: tab, then feature, Broadcast, System; error and empty states are handled', (t) async {
      await setRole(t, 'admin');
      seed();
      await pumpRouted(t, const StaffAccountabilityScreen());
      await settle(t);
      final l10n = lookupAppLocalizations(const Locale('en'));
      Map<String, String> last() => fake.calls('GET /rest/v1/admin_activity_log').last.url.queryParameters;
      // A chip may be off to the side: scroll it into view, then tap it.
      Future<void> tap(String key) async {
        await t.ensureVisible(find.byKey(ValueKey(key)));
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(find.byKey(ValueKey(key)));
        await settle(t);
      }

      // The tabs and Broadcast / System are ONE row that scrolls sideways.
      final row = find.byKey(const ValueKey('log-chip-row'));
      final scroller = find.descendant(of: row, matching: find.byType(SingleChildScrollView));
      expect(scroller, findsOneWidget);
      expect(t.widget<SingleChildScrollView>(scroller).scrollDirection, Axis.horizontal);
      for (final label in ['All modules', 'Dashboard', 'Members', 'Marketplace', 'Loans', 'Reports', 'Broadcast', 'System']) {
        expect(find.widgetWithText(InkWell, label), findsOneWidget, reason: label);
      }
      final screenWidth = t.view.physicalSize.width / t.view.devicePixelRatio;
      // On a phone the last chips start off screen...
      expect(t.getRect(find.byKey(const ValueKey('log-chip-system'))).right, greaterThan(screenWidth));
      expect(t.getRect(find.byKey(const ValueKey('log-chip-all'))).left, greaterThanOrEqualTo(0));
      // ...swiping left brings them in, and the first chip leaves.
      await t.drag(row, const Offset(-1000, 0));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.getRect(find.byKey(const ValueKey('log-chip-system'))).right, lessThanOrEqualTo(screenWidth));
      expect(t.getRect(find.byKey(const ValueKey('log-chip-all'))).right, lessThan(0));
      // ...and swiping right brings the start back.
      await t.drag(row, const Offset(1000, 0));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.getRect(find.byKey(const ValueKey('log-chip-all'))).left, greaterThanOrEqualTo(0));
      expect(find.byKey(const ValueKey('log-feature-all')), findsNothing, reason: 'features appear once a tab is chosen');

      // A tab: every table of the tab, database rows only.
      await tap('log-chip-dashboard');
      expect(last()['source'], 'eq.db');
      expect(last()['table_name'], allOf(startsWith('in.('), contains('cooperative_inventory'), contains('crop_master'), contains('price_records'), contains('loan_items_master')));
      // ...its features appear, and a feature narrows it.
      final featureScroller = find.descendant(of: find.byKey(const ValueKey('log-feature-row')), matching: find.byType(SingleChildScrollView));
      expect(t.widget<SingleChildScrollView>(featureScroller).scrollDirection, Axis.horizontal, reason: 'the features swipe too');
      for (final label in [l10n.adminInvManagementTitle, l10n.cropMgmtTitle, l10n.programMgmtTitle, l10n.buyerNavPrices, l10n.loanItemCatalogTitle]) {
        expect(find.widgetWithText(InkWell, label), findsOneWidget, reason: label);
      }
      await tap('log-feature-prices');
      expect(last()['table_name'], 'in.("price_records")');
      await tap('log-feature-all');
      expect(last()['table_name'], contains('crop_master'));

      // Another tab replaces the first one's features.
      await tap('log-chip-marketplace');
      expect(last()['table_name'], allOf(contains('marketplace_listings'), contains('orders'), contains('market_linking_sales')));
      expect(find.byKey(const ValueKey('log-feature-prices')), findsNothing);
      await tap('log-feature-orders');
      expect(last()['table_name'], 'in.("orders")');

      await tap('log-chip-loans');
      expect(last()['table_name'], allOf(contains('farmer_loans'), contains('farmer_loan_payments')));
      expect(last()['table_name'], isNot(contains('loan_items_master')));

      // Reports: the Balik-Tangkilik tables AND the exports the app wrote.
      await tap('log-chip-reports');
      expect(last()['or'], allOf(contains('cooperative_annual_totals'), contains('action_type.eq.exported')));
      await tap('log-feature-exports');
      expect(last()['source'], 'eq.app');
      expect(last()['module'], 'eq.reports');

      // Broadcast and System.
      await tap('log-chip-broadcast');
      expect(last()['table_name'], 'in.("broadcast_logs")');
      await tap('log-chip-system');
      expect(last()['module'], 'eq.system');
      expect(last()['source'], 'eq.db');

      // Back to everything.
      await tap('log-chip-all');
      expect(last()['or'], contains('source.eq.db'));
      expect(last().containsKey('table_name'), isFalse);

      // The staff dropdown.
      await t.tap(find.byKey(const ValueKey('staff-filter')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Olivia One · Officer'), findsWidgets);
      expect(find.text('The Manager · Manager'), findsWidgets);
      await t.tap(find.text('Olivia One · Officer').last);
      await settle(t);
      expect(last()['admin_id'], 'eq.o-1');

      // Error and empty states.
      fake.on('GET /rest/v1/admin_activity_log', (_) => const FakeError(500, 'boom'));
      await tap('log-chip-members');
      expect(find.text('Could not load the log. Pull down to try again.'), findsOneWidget);

      fake.on('GET /rest/v1/admin_activity_log', (_) => <Object?>[]);
      await tap('log-chip-reports');
      expect(find.text('No staff actions recorded yet.'), findsOneWidget);
    });
  });

  // ─────────────────────────────── T22 ───────────────────────────────
  group('T22 localization', () {
    test('every new string exists in English and Tagalog with the same placeholders', () {
      final en = jsonDecode(File('lib/core/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>;
      final tl = jsonDecode(File('lib/core/l10n/app_tl.arb').readAsStringSync()) as Map<String, dynamic>;
      final mine = en.keys.where((k) => !k.startsWith('@') &&
          RegExp(r'^(staff|createAccountSubmit|farmerDetailsHistoryBy|addMemberCreated|farmerMgmtCreatedBy|manageAccountsManagementTab)').hasMatch(k)).toList();
      expect(mine.length, greaterThan(35));
      final missing = mine.where((k) => !tl.containsKey(k) || (tl[k] as String).trim().isEmpty).toList();
      expect(missing, isEmpty, reason: 'missing in Tagalog: $missing');
      Set<String> ph(String s) => RegExp(r'\{(\w+)').allMatches(s).map((m) => m.group(1)!).toSet();
      final mismatch = mine.where((k) => ph(en[k] as String).difference(ph(tl[k] as String)).isNotEmpty || ph(tl[k] as String).difference(ph(en[k] as String)).isNotEmpty).toList();
      expect(mismatch, isEmpty, reason: 'placeholder mismatch: $mismatch');
      // Strings left identical to English (allowed only for loan-words / the same word).
      final same = mine.where((k) => en[k] == tl[k]).toList();
      expect(same.toSet().difference({'staffAccessView', 'staffRoleManager', 'staffRoleOfficer',
        // Loan-words the Tagalog text keeps as they are.
        'staffLogBroadcast', 'staffThingUserRoles', 'staffThingMarketplaceListings', 'staffThingOrders', 'staffThingBroadcastLogs'}), isEmpty, reason: 'untranslated: $same');
    });

    ftest('Create Farmer Account renders in Tagalog', (t) async {
      await setRole(t, 'admin');
      await pumpRouted(t, const AddNewMemberScreen(), locale: const Locale('tl'));
      final tl = lookupAppLocalizations(const Locale('tl'));
      expect(find.text(tl.registerStepPersonal), findsWidgets);
      expect(find.text(tl.registerStepIndicator(1, 3)), findsOneWidget);
      expect(find.text('Step 1 of 3'), findsNothing);
    });

    ftest('Staff Accountability, the access matrix and the strip render in Tagalog', (t) async {
      await setRole(t, 'officer');
      StaffPermissions.instance.debugSet({StaffModule.loans: StaffAccess.view});
      await t.pumpWidget(app(const Scaffold(body: ViewOnlyStrip(module: StaffModule.loans)), locale: const Locale('tl')));
      expect(find.textContaining('View Only'), findsOneWidget);
      expect(find.text('Mga Utang · View Only'), findsOneWidget);

      await setRole(t, 'admin');
      fake.on('GET /rest/v1/admin_activity_log', (_) => <Object?>[]);
      await pumpRouted(t, const StaffAccountabilityScreen(), locale: const Locale('tl'));
      await settle(t);
      expect(find.text('Pananagutan ng Staff'), findsOneWidget);
      expect(find.text('Wala pang naitalang aksyon ng staff.'), findsOneWidget);
    });
  });
}
