import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/farmer_profile_model.dart';
import 'package:sagana/data/models/program_model.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/data/services/staff_permission_service.dart';
import 'package:sagana/presentation/screens/admin/program_management_screen.dart';
import 'package:sagana/presentation/screens/admin/program_products_screen.dart';
import 'package:sagana/presentation/widgets/admin_program_card.dart';
import 'package:sagana/presentation/screens/farmer/my_programs_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/stand_in_fonts.dart';
import 'support/test_storage_mocks.dart';

/// Layout checks that stand in for looking at the cards on different phones: five screen
/// sizes, three text sizes (normal, large, and the largest accessibility size), English and
/// Tagalog, with the awkward data a real cooperative has (very long names, long item names,
/// big quantities, many orders, every status).
///
/// This is NOT a physical device and does not use the real Inter / Poppins fonts: it draws
/// the real screens with a stand-in system font (see support/stand_in_fonts.dart) and fails
/// on any overflow or clipped card. Set SAGANA_SHOT_DIR to also save PNG pictures.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();
  var realFonts = false;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_devices');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
    await HiveService.init();
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key', httpClient: fake);
    realFonts = await loadStandInFonts();
  });

  const sizes = <String, Size>{
    'small phone 320x568': Size(320, 568),
    'phone 360x640': Size(360, 640),
    'phone 390x844': Size(390, 844),
    'large phone 412x915': Size(412, 915),
    'tablet 600x960': Size(600, 960),
  };
  const scales = <double>[1.0, 1.3, 2.0];
  const locales = <Locale>[Locale('en'), Locale('tl')];

  final shotDir = Platform.environment['SAGANA_SHOT_DIR'];
  final shotKey = GlobalKey();

  String iso(int daysAgo) => DateTime.now().subtract(Duration(days: daysAgo)).toUtc().toIso8601String();
  const longName = 'Maria Esperanza Dela Cruz-Villanueva y Fernandez Jr.';
  const longItem = 'Certified Hybrid Rice Seeds Premium Grade A (Early Maturing)';

  CooperativeProgram program(String purpose) => CooperativeProgram(
        id: 'p1',
        programName: 'Cooperative Agricultural Inputs and Livestock Dispersal Support Program',
        programType: 'Processed Products',
        benefitType: 'grant',
        programPurpose: purpose,
        seasonYear: 2026,
        status: 'active',
        memberCount: 4,
        sourceCategories: const ['Seeds'],
      );

  Map<String, Object?> member(String id, String farmer, int daysAgo, {double qty = 1234567.89, String unit = 'head'}) => {
        'id': id,
        'program_id': 'p1',
        'farmer_id': farmer,
        'status': 'active',
        'enrolled_at': iso(400),
        'inventory_item_id': 'i1',
        'quantity_given': qty,
        'distributed_at': iso(daysAgo),
        'distributed_item_name': longItem,
        'distributed_unit': unit,
        'distribution_outcome': null,
      };

  Map<String, Object?> report(String member, String farmer, {bool reviewed = false, bool verified = false}) => {
        'id': 'r-$member',
        'program_member_id': member,
        'program_id': 'p1',
        'farmer_id': farmer,
        'reported_outcome': 'successful',
        'status': 'pending_validation',
        'submitted_at': iso(1),
        if (reviewed) 'review_decision': 'validated',
        if (reviewed) 'reviewed_by': 'u1',
        if (verified) 'verified_by': 'u2',
        if (verified) 'verified_at': iso(0),
      };

  Future<void> shot(WidgetTester tester, String name) async {
    if (shotDir == null) return;
    await tester.runAsync(() async {
      final boundary = shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      File('$shotDir/$name.png').writeAsBytesSync(data.buffer.asUint8List());
    });
  }

  Future<void> pumpApp(WidgetTester tester, Size size, double scale, Locale locale, Widget home) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(key: shotKey, child: child),
      ),
      home: home,
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  // Waits (real time passes too) until the member cards are on screen.
  Future<void> waitForCards(WidgetTester tester) async {
    for (var i = 0; i < 80; i++) {
      if (find.byKey(const Key('memberCard_m1')).evaluate().isNotEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // Every card must sit inside the screen: nothing clipped at the sides.
  void expectCardsInside(WidgetTester tester, Size size, Pattern keyPrefix) {
    final cards = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith(keyPrefix as String));
    expect(cards, findsWidgets);
    for (final e in cards.evaluate()) {
      final r = tester.getRect(find.byElementPredicate((x) => x == e));
      expect(r.left, greaterThanOrEqualTo(-0.5), reason: 'card clipped on the left');
      expect(r.right, lessThanOrEqualTo(size.width + 0.5), reason: 'card clipped on the right');
    }
  }

  Future<void> staffCase(WidgetTester tester, {required String purpose, required Size size, required double scale, required Locale locale, String? shotName}) async {
    fake.reset();
    final members = purpose == 'sales'
        ? [member('m1', 'f1', 0), member('m2', 'f2', 0), member('m3', 'f3', 0)]
        : [member('m1', 'f1', 400), member('m2', 'f2', 12), member('m3', 'f3', 3), member('m4', 'f4', 1)];
    fake.on('GET /rest/v1/program_members', (_) => members);
    fake.on('GET /rest/v1/user_information', (_) => [
      {'user_id': 'f1', 'full_name': longName},
      {'user_id': 'f2', 'full_name': 'Ellen Angela Rosal'},
      {'user_id': 'f3', 'full_name': 'Jhon Drhy M. Salangsang'},
      {'user_id': 'f4', 'full_name': 'Marc Louie M. Yañez'},
    ]);
    fake.on('GET /rest/v1/cooperative_inventory', (_) => []);
    fake.on('POST /rest/v1/rpc/get_program_outcome_reports', (_) => [
      report('m3', 'f3', reviewed: true),
      report('m4', 'f4', reviewed: true, verified: true),
    ]);
    fake.on('GET /rest/v1/program_report_reminders', (_) => [
      {'program_member_id': 'm1', 'created_at': iso(2), 'sent_by_role': 'officer'},
    ]);
    fake.on('GET /rest/v1/program_product_purchases', (_) => [
      for (var i = 0; i < 118; i++) {'farmer_id': 'f1', 'status': 'completed', 'total_amount': 104773.5, 'discount_amount': 10477.35},
      for (var i = 0; i < 12; i++) {'farmer_id': 'f1', 'status': 'pending', 'total_amount': 80, 'discount_amount': 0},
      {'farmer_id': 'f2', 'status': 'completed', 'total_amount': 1240, 'discount_amount': 124},
    ]);
    await tester.runAsync(() => HiveService.saveUserSession(userId: 'u-admin', email: 'x@y.z', role: 'admin'));
    StaffPermissions.instance.debugSet(const {});
    await pumpApp(tester, size, scale, locale, ProgramMembersScreen(program: program(purpose)));
    if (purpose != 'sales') {
      // The tabs appear once the members are loaded; the second tab is "Distributed".
      for (var i = 0; i < 80 && find.byType(Tab).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byType(Tab).at(1), warnIfMissed: false);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
    await waitForCards(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull, reason: 'overflow or layout error');
    expectCardsInside(tester, size, 'memberCard_');
    if (shotName != null) await shot(tester, shotName);
  }


  // ── the other member sections (To Distribute, Successful, Failed), both program types ──
  Future<void> sectionCase(WidgetTester tester, {required int tab, required bool harvestReturn, required Size size, required double scale, required Locale locale, String? shotName}) async {
    fake.reset();
    final members = [
      {...member('m1', 'f1', 400), 'enrolled_at': iso(400), 'inventory_item_id': tab == 0 ? null : 'i1', 'quantity_given': tab == 0 ? null : 1234567.89, 'distributed_at': tab == 0 ? null : iso(60), 'distribution_outcome': tab == 2 ? 'thriving' : (tab == 3 ? 'failed' : null), 'outcome_recorded_at': tab >= 2 ? iso(3) : null},
      {...member('m2', 'f2', 12), 'enrolled_at': iso(12), 'inventory_item_id': tab == 0 ? null : 'i1', 'quantity_given': tab == 0 ? null : 2, 'distributed_at': tab == 0 ? null : iso(30), 'distribution_outcome': tab == 2 ? 'thriving' : (tab == 3 ? 'failed' : null), 'outcome_recorded_at': tab >= 2 ? iso(8) : null},
    ];
    Map<String, Object?> finalReport(String m, String f, bool ok) => {
          'id': 'r-$m',
          'program_member_id': m,
          'program_id': 'p1',
          'farmer_id': f,
          'reported_outcome': ok ? 'successful' : 'failed',
          'status': 'finalized',
          'final_outcome': ok ? 'successful' : 'failed',
          'finalized_at': iso(3),
          'submitted_at': iso(9),
          'review_decision': 'validated',
          'reviewed_by': 'u1',
          'verified_by': 'u2',
          'verified_at': iso(5),
          if (ok) 'verified_quantity': 1234567.89,
          if (ok) 'verified_unit': 'head',
          if (!ok) 'failure_cause': 'A long period of heavy rain flooded the whole field and the seedlings rotted before they could take root',
        };
    fake.on('GET /rest/v1/program_members', (_) => members);
    fake.on('GET /rest/v1/user_information', (_) => [
      {'user_id': 'f1', 'full_name': longName},
      {'user_id': 'f2', 'full_name': 'Ellen Angela Rosal'},
    ]);
    fake.on('GET /rest/v1/cooperative_inventory', (_) => []);
    fake.on('POST /rest/v1/rpc/get_program_outcome_reports', (_) => tab >= 2 ? [finalReport('m1', 'f1', tab == 2), finalReport('m2', 'f2', tab == 2)] : []);
    fake.on('POST /rest/v1/rpc/get_program_returns', (_) => tab == 2 && harvestReturn
        ? [
            for (final m in ['m1', 'm2'])
              {'id': 'ret-$m', 'program_id': 'p1', 'program_member_id': m, 'crop_name': longItem, 'unit': 'head', 'original_quantity': 1234567.89, 'due_quantity': 1234567.89, 'received_quantity': 1000000, 'status': 'partial'}
          ]
        : []);
    fake.on('GET /rest/v1/program_report_reminders', (_) => []);
    await tester.runAsync(() => HiveService.saveUserSession(userId: 'u-admin', email: 'x@y.z', role: 'admin'));
    StaffPermissions.instance.debugSet(const {});
    final prog = CooperativeProgram(
      id: 'p1',
      programName: 'Cooperative Agricultural Inputs and Livestock Dispersal Support Program',
      programType: 'Livestock',
      benefitType: harvestReturn ? 'revenue_share' : 'grant',
      returnQuantity: harvestReturn ? 1234567.89 : null,
      seasonYear: 2026,
      status: 'active',
      memberCount: 2,
      sourceCategories: const ['Seeds'],
    );
    await pumpApp(tester, size, scale, locale, ProgramMembersScreen(program: prog));
    for (var i = 0; i < 80 && find.byType(Tab).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.ensureVisible(find.byType(Tab).at(tab));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(Tab).at(tab), warnIfMissed: false);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await waitForCards(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull, reason: 'overflow or layout error');
    expectCardsInside(tester, size, 'memberCard_');
    if (shotName != null) await shot(tester, shotName);
  }

  // ── Manage Products: long names, big numbers, several categories, every state ──
  Future<void> productsCase(WidgetTester tester, {required String status, required Size size, required double scale, required Locale locale, String? shotName}) async {
    fake.reset();
    Map<String, Object?> row(String id, String name, String cat, double qty, bool on) => {
          'id': id,
          'program_id': 'p1',
          'inventory_item_id': 'i-$id',
          'unit_price': 1234567.5,
          'is_available': on,
          'cooperative_inventory': {'item_name': name, 'category': cat, 'unit': 'sack', 'quantity_on_hand': qty, 'image_url': null},
        };
    fake.on('GET /rest/v1/program_products', (_) => [
      row('a', 'Certified Hybrid Rice Seeds Premium Grade A (Early Maturing)', 'Seeds', 1234567.89, true),
      row('b', 'Peanut Cookies', 'Harvest Stock', 90, true),
      row('c', 'Granola Bar', 'Harvest Stock', 0, true),
      row('d', 'Coconut Jam', 'Harvest Stock', 12, false),
      row('e', 'Corn Seeds', 'Seeds', 5, true),
      row('f', 'Mungbean Seeds', 'Seeds', 5, true),
      row('g', 'Sesame', 'Seeds', 5, true),
      row('h', 'Ginger Tea', 'Harvest Stock', 5, true),
    ]);
    fake.on('GET /rest/v1/cooperative_programs', (r) => r.url.query.contains('source_categories') ? {'source_categories': ['Seeds']} : [{'id': 'p1', 'status': status}]);
    fake.on('GET /rest/v1/cooperative_inventory', (_) => []);
    fake.on('GET /rest/v1/program_product_purchases', (_) => [
      for (var i = 0; i < 40; i++) {'product_id': 'a', 'farmer_id': 'f$i', 'status': 'completed', 'quantity': 31000, 'total_amount': 1234567.5, 'discount_amount': 123456.75},
      {'product_id': 'b', 'farmer_id': 'f1', 'status': 'pending', 'quantity': 1, 'total_amount': 45, 'discount_amount': 5},
    ]);
    await tester.runAsync(() => HiveService.saveUserSession(userId: 'u-admin', email: 'x@y.z', role: 'admin'));
    StaffPermissions.instance.debugSet(const {});
    await pumpApp(tester, size, scale, locale, const ProgramProductsScreen(programId: 'p1', programName: 'Cooperative Agricultural Inputs and Livestock Dispersal Support Program', memberDiscountPercent: 12.5));
    for (var i = 0; i < 80 && find.byKey(const Key('productCard_b')).evaluate().isEmpty && find.byKey(const Key('productCard_a')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull, reason: 'overflow or layout error');
    // The list builds cards as they scroll into view: walk down it, measuring each screenful.
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 24; i++) {
      final onScreen = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('productCard_'));
      if (onScreen.evaluate().isNotEmpty) expectCardsInside(tester, size, 'productCard_');
      expect(tester.takeException(), isNull, reason: 'overflow or layout error while scrolling');
      await tester.drag(list, Offset(0, -(size.height * 0.6)), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(tester.takeException(), isNull, reason: 'overflow or layout error while scrolling');
    // Back to the top for the picture.
    for (var i = 0; i < 24; i++) {
      await tester.drag(list, Offset(0, size.height * 0.6), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 60));
    }
    if (shotName != null) await shot(tester, shotName);
  }

  // ── Program Management: the dimmed card of a completed program ──
  Future<void> completedCardCase(WidgetTester tester, {required Size size, required double scale, required Locale locale, String? shotName}) async {
    await pumpApp(
      tester,
      size,
      scale,
      locale,
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: AdminProgramCard(
            program: CooperativeProgram(
              id: 'p9',
              programName: 'Cooperative Agricultural Inputs and Livestock Dispersal Support Program',
              programType: 'Processed Products',
              benefitType: 'revenue_share',
              returnQuantity: 1234567.89,
              seasonYear: 2026,
              status: 'completed',
              memberCount: 1234,
              description: 'A long description of what this program does for the Farmers who join it and how it works.',
              budget: 12345678,
              sourceCategories: const ['Seeds', 'Harvest Stock'],
              createdAt: DateTime(2026, 9, 5),
            ),
            accent: Colors.green,
            icon: Icons.eco,
            statusLabel: 'COMPLETED',
            statusColor: Colors.grey,
            memberCountLabel: '1,234 enrolled members',
            onMembers: () {},
            onHistory: () {},
            onEdit: () {},
            onComplete: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull, reason: 'overflow or layout error');
    if (shotName != null) await shot(tester, shotName);
  }

  MyProgramEntry entry(int daysAgo, {String? outcome}) => MyProgramEntry.fromMap({
        'id': 'm1',
        'program_id': 'p1',
        'status': 'active',
        'enrolled_at': iso(400),
        'quantity_given': 1234567.89,
        'distributed_at': iso(daysAgo),
        'distributed_item_name': longItem,
        'distribution_outcome': outcome,
        'cooperative_programs': {
          'program_name': 'Cooperative Agricultural Inputs and Livestock Dispersal Support Program',
          'benefit_type': 'revenue_share',
          'program_purpose': 'distribution',
          'status': 'active',
          'return_quantity': 1234567.89,
        },
        'cooperative_inventory': {'item_name': longItem, 'unit': 'head'},
      });

  Future<void> farmerCase(WidgetTester tester, {required int days, required Size size, required double scale, required Locale locale, String? shotName}) async {
    await pumpApp(
      tester,
      size,
      scale,
      locale,
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MyProgramCard(
            entry: entry(days),
            report: null,
            onReport: () {},
            formatDate: (d) => '${d.month}/${d.day}/${d.year}',
            statusLabel: (s) => s,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull, reason: 'overflow or layout error');
    if (shotName != null) await shot(tester, shotName);
  }

  test('the stand-in font was found (otherwise the checks still run, with block letters)', () {
    // ignore: avoid_print
    print('stand-in font loaded: $realFonts');
  });

  for (final sizeEntry in sizes.entries) {
    for (final scale in scales) {
      for (final locale in locales) {
        final label = '${sizeEntry.key}, text x$scale, ${locale.languageCode}';
        final shotBase = '${sizeEntry.key.split(' ').last}_x${scale}_${locale.languageCode}';
        final wantShot = (scale == 1.0 && locale.languageCode == 'en') || (scale == 2.0 && sizeEntry.key.startsWith('small'));
        testWidgets('Distribution cards: $label', (tester) async {
          await runIgnoringFontErrors(() => staffCase(tester, purpose: 'distribution', size: sizeEntry.value, scale: scale, locale: locale, shotName: wantShot ? 'staff_distribution_$shotBase' : null));
        });
        testWidgets('Product Sales cards: $label', (tester) async {
          await runIgnoringFontErrors(() => staffCase(tester, purpose: 'sales', size: sizeEntry.value, scale: scale, locale: locale, shotName: wantShot ? 'staff_sales_$shotBase' : null));
        });
        for (final hr in [false, true]) {
          final kind = hr ? 'Harvest Return' : 'Free Distribution';
          // A Free Distribution has two tabs (To Distribute, Distributed): it has no outcome
          // report, so there is no Successful/Failed tab. Harvest Return has all four.
          final tabs = hr ? {0: 'To Distribute', 2: 'Successful', 3: 'Failed'} : {0: 'To Distribute', 1: 'Distributed'};
          for (final e in tabs.entries) {
            testWidgets('$kind, $label: ${e.value} cards', (tester) async {
              await runIgnoringFontErrors(() => sectionCase(tester, tab: e.key, harvestReturn: hr, size: sizeEntry.value, scale: scale, locale: locale, shotName: wantShot && locale.languageCode == 'en' && scale == 1.0 ? 'staff_${e.value.replaceAll(' ', '').toLowerCase()}_${hr ? 'hr' : 'free'}_$shotBase' : null));
            });
          }
        }
        testWidgets('Manage Products: $label', (tester) async {
          await runIgnoringFontErrors(() => productsCase(tester, status: 'active', size: sizeEntry.value, scale: scale, locale: locale, shotName: wantShot ? 'products_$shotBase' : null));
        });
        testWidgets('Manage Products (completed program): $label', (tester) async {
          await runIgnoringFontErrors(() => productsCase(tester, status: 'completed', size: sizeEntry.value, scale: scale, locale: locale, shotName: wantShot && scale == 1.0 ? 'products_completed_$shotBase' : null));
        });
        testWidgets('Completed program card: $label', (tester) async {
          await runIgnoringFontErrors(() => completedCardCase(tester, size: sizeEntry.value, scale: scale, locale: locale, shotName: wantShot && scale == 1.0 ? 'program_card_completed_$shotBase' : null));
        });
        testWidgets('Farmer card: $label', (tester) async {
          await runIgnoringFontErrors(() => farmerCase(tester, days: 400, size: sizeEntry.value, scale: scale, locale: locale, shotName: wantShot ? 'farmer_$shotBase' : null));
        });
      }
    }
  }
}
