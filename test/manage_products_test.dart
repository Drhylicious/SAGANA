import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/constants/app_constants.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/program_model.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/data/services/staff_permission_service.dart';
import 'package:sagana/presentation/screens/admin/program_products_screen.dart';
import 'package:sagana/presentation/widgets/admin_program_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/ignore_font_errors.dart';
import 'support/stand_in_fonts.dart';
import 'support/test_storage_mocks.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

ProgramProduct _p(String name, {bool on = true, double qty = 10, String cat = 'Seeds', String id = ''}) => ProgramProduct(
      id: id.isEmpty ? name : id,
      programId: 'p1',
      inventoryItemId: 'i-$name',
      itemName: name,
      category: cat,
      unit: 'sack',
      quantityOnHand: qty,
      stockAllocated: qty,
      unitPrice: 50,
      isAvailable: on,
    );

/// Manage Products: its figures, order, filters and read-only state, and the dimmed card of
/// a completed program.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_products');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir.path);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
    await HiveService.init();
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key', httpClient: fake);
    // Letters take real room (not the solid blocks tests draw), so lines wrap as on a phone.
    await loadStandInFonts();
  });

  // ── the rules (pure) ──────────────────────────────────────────────────────
  group('order, filters and groups', () {
    test('on sale first, then out of stock, then turned off; by name inside each', () {
      final sorted = sortProductsForDisplay([
        _p('Zebra beans', on: false),
        _p('Apple seeds', qty: 0),
        _p('mango'),
        _p('Banana'),
        _p('Cacao', on: false, qty: 0),
      ]);
      expect(sorted.map((p) => p.itemName), ['Banana', 'mango', 'Apple seeds', 'Cacao', 'Zebra beans']);
    });

    test('out of stock is judged on the quantity, and a turned-off product is off whatever its stock', () {
      expect(_p('a', qty: 0).isOutOfStock, isTrue);
      expect(_p('a', qty: 0.5).isOutOfStock, isFalse);
      expect(productSortRank(_p('a', on: false, qty: 0)), 2);
      expect(productSortRank(_p('a', qty: 0)), 1);
      expect(productSortRank(_p('a')), 0);
    });

    test('filters overlap: a product can be on sale and out of stock at once', () {
      final p = _p('a', qty: 0);
      expect(productMatchesFilter(p, ProductFilter.onSale), isTrue);
      expect(productMatchesFilter(p, ProductFilter.outOfStock), isTrue);
      expect(productMatchesFilter(p, ProductFilter.off), isFalse);
      expect(productMatchesFilter(p, ProductFilter.all), isTrue);
    });

    test('categories are A to Z, ignoring case and spaces', () {
      expect(productCategories([_p('a', cat: 'seeds'), _p('b', cat: 'Seeds '), _p('c', cat: 'Harvest Stock')]), ['Harvest Stock', 'seeds']);
      expect(productCategories([_p('a'), _p('b')]).length, 1);
    });
  });

  group('the program\'s sales figures', () {
    Map<String, Object?> row(String product, String farmer, String status, double qty, double total, double saved) =>
        {'product_id': product, 'farmer_id': farmer, 'status': status, 'quantity': qty, 'total_amount': total, 'discount_amount': saved};

    test('paid purchases are the sales; pending are only counted; cancelled count for nothing', () {
      final s = ProgramSalesSummary.fromRows([
        row('a', 'f1', 'completed', 3, 135, 15),
        row('a', 'f2', 'completed', 2, 100, 0),
        row('b', 'f1', 'completed', 1, 45, 5),
        row('a', 'f3', 'pending', 9, 400, 40),
        row('a', 'f4', 'cancelled', 9, 400, 40),
      ].map((r) => Map<String, dynamic>.from(r)));
      expect(s.totalSales, 280);
      expect(s.savings, 20);
      expect(s.buyers, 2); // f1 and f2: distinct, paid only
      expect(s.pending, 1);
      expect(s.byProduct['a']!.sold, 5);
      expect(s.byProduct['a']!.buyers, 2);
      expect(s.byProduct['b']!.sold, 1);
      expect(s.byProduct.containsKey('c'), isFalse);
    });

    test('they are read with ONE query', () {
      final repo = _read('lib/data/repositories/program_repository.dart');
      final fn = repo.substring(repo.indexOf('fetchProgramSalesSummary'), repo.indexOf('fetchProgramStatus'));
      expect('_client.from('.allMatches(fn.replaceAll(RegExp(r'\s'), '')).length, 1);
    });
  });

  // ── the real screen ───────────────────────────────────────────────────────
  Map<String, Object?> productRow(ProgramProduct p) => {
        'id': p.id,
        'program_id': 'p1',
        'inventory_item_id': p.inventoryItemId,
        'unit_price': p.unitPrice,
        'is_available': p.isAvailable,
        'stock_allocated': p.stockAllocated,
        'stock_reserved': p.stockReserved,
        'cooperative_inventory': {'item_name': p.itemName, 'category': p.category, 'unit': p.unit, 'quantity_on_hand': p.quantityOnHand, 'image_url': null},
      };

  Future<void> pumpProducts(WidgetTester tester, List<ProgramProduct> products,
      {String status = 'active', double discount = 10, List<Map<String, Object?>> purchases = const [], Size size = const Size(420, 1400), double scale = 1.0, Locale locale = const Locale('en')}) async {
    fake.reset();
    fake.on('GET /rest/v1/program_products', (_) => products.map(productRow).toList());
    fake.on('GET /rest/v1/cooperative_programs', (r) => r.url.query.contains('source_categories')
        ? {'source_categories': ['Seeds']}
        : [{'id': 'p1', 'status': status}]);
    fake.on('GET /rest/v1/cooperative_inventory', (_) => []);
    fake.on('GET /rest/v1/program_product_purchases', (_) => purchases);
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
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: ProgramProductsScreen(programId: 'p1', programName: 'Peanut Cookies', memberDiscountPercent: discount),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  AppLocalizations l10nOf(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  final purchases = <Map<String, Object?>>[
    {'product_id': 'Peanut Cookies', 'farmer_id': 'f1', 'status': 'completed', 'quantity': 300, 'total_amount': 13500, 'discount_amount': 1500},
    {'product_id': 'Peanut Cookies', 'farmer_id': 'f2', 'status': 'completed', 'quantity': 40, 'total_amount': 1800, 'discount_amount': 200},
    {'product_id': 'Peanut Cookies', 'farmer_id': 'f3', 'status': 'pending', 'quantity': 5, 'total_amount': 225, 'discount_amount': 25},
  ];

  testWidgets('four figures that scroll sideways: total sales, buyers, member savings, pending', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Peanut Cookies')], purchases: purchases);
      final l10n = l10nOf(tester);
      final kpis = find.byKey(const Key('productKpis'));
      expect(kpis, findsOneWidget);
      expect(tester.widget<ListView>(find.descendant(of: kpis, matching: find.byType(ListView))).scrollDirection, Axis.horizontal);
      for (final label in [l10n.prodKpiSales, l10n.prodKpiBuyers]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('₱15,300'), findsOneWidget); // 13,500 + 1,800 paid
      expect(find.text('2'), findsWidgets); // buyers
      // The row scrolls sideways: swipe to reach the rest.
      await tester.drag(kpis, const Offset(-500, 0));
      await tester.pump(const Duration(milliseconds: 400));
      for (final label in [l10n.prodKpiSavings, l10n.prodKpiPending]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('₱1,700'), findsOneWidget); // saved
      expect(find.text('1'), findsWidgets); // pending
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the member discount sits at the right of the product name; the old header lines are gone', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Peanut Cookies', id: 'pc')], purchases: purchases);
      final l10n = l10nOf(tester);
      final pill = find.byKey(const Key('discountPill_pc'));
      expect(find.text('Members Get 10% Off'), findsOneWidget);
      final name = find.descendant(of: find.byKey(const Key('productCard_pc')), matching: find.text('Peanut Cookies'));
      final pr = tester.getRect(pill);
      final nr = tester.getRect(name);
      expect(pr.left, greaterThan(nr.right), reason: 'the discount is to the right of the name');
      expect((pr.center.dy - nr.center.dy).abs(), lessThan(14), reason: 'on the same line');
      // The old header discount line and the turned-off note no longer sit on the page.
      expect(find.text(l10n.prodMemberDiscountInfo('10')), findsNothing);
      expect(find.text(l10n.prodOffNote), findsNothing);
      // Member price first and bold, the regular price beside it.
      expect(find.text(l10n.prodMemberPrice('₱45.00')), findsOneWidget);
      expect(find.text(l10n.prodRegularPrice('₱50.00')), findsOneWidget);
    });
  });

  testWidgets('on a 360-wide phone a short name still has the discount at its right (two short lines)', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Peanut Cookies', id: 'pc')], size: const Size(360, 1400));
      final pr = tester.getRect(find.byKey(const Key('discountPill_pc')));
      final nr = tester.getRect(find.descendant(of: find.byKey(const Key('productCard_pc')), matching: find.text('Peanut Cookies')));
      expect(pr.left, greaterThan(nr.right));
      expect((pr.center.dy - nr.center.dy).abs(), lessThan(16));
      expect(pr.right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a long name keeps its room: the discount drops below it', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Certified Hybrid Rice Seeds Premium Grade A Early Maturing Variety', id: 'long')], size: const Size(360, 1400));
      final pr = tester.getRect(find.byKey(const Key('discountPill_long')));
      final nr = tester.getRect(find.descendant(of: find.byKey(const Key('productCard_long')), matching: find.textContaining('Certified Hybrid')));
      expect(pr.top, greaterThanOrEqualTo(nr.bottom - 1));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('no discount: no pill and only the regular price', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Peanut Cookies', id: 'pc')], discount: 0);
      final l10n = l10nOf(tester);
      expect(find.byKey(const Key('discountPill_pc')), findsNothing);
      expect(find.textContaining('Members Get'), findsNothing);
      expect(find.text(l10n.prodRegularPrice('₱50.00')), findsOneWidget);
      expect(find.textContaining('Member ₱'), findsNothing);
    });
  });

  testWidgets('sold line, or "No sales yet"; out of stock in red; an archived product is dimmed and says so', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Peanut Cookies'), _p('Granola', id: 'gr', qty: 0), _p('Coconut Jam', id: 'cj', on: false)], purchases: purchases);
      final l10n = l10nOf(tester);
      expect(find.text('2 buyers · 340 sack sold'), findsOneWidget);
      expect(find.text(l10n.prodNoSalesYet), findsNWidgets(2));
      final oos = tester.widget<Text>(find.text(l10n.prodOutOfStock));
      expect(oos.style?.color, AppConstants.errorRed);
      expect(find.text(l10n.prodOffHidden), findsOneWidget);
      // Dimmed: the product's top part at 60%, a product on sale at full strength.
      double opacityOf(String id) => tester
          .widgetList<Opacity>(find.descendant(of: find.byKey(Key('productCard_$id')), matching: find.byType(Opacity)))
          .map((o) => o.opacity)
          .first;
      expect(opacityOf('cj'), 0.6);
      expect(opacityOf('Peanut Cookies'), 1.0);
      // The switch itself is not dimmed: still easy to turn back on.
      expect(find.ancestor(of: find.byKey(const Key('productSwitch_cj')), matching: find.byType(Opacity)), findsNothing);
      // Order on the page: on sale, out of stock, then the archived one last.
      double y(String id) => tester.getTopLeft(find.byKey(Key('productCard_$id'))).dy;
      expect(y('Peanut Cookies'), lessThan(y('gr')));
      expect(y('gr'), lessThan(y('cj')));
    });
  });

  testWidgets('the page is KPI cards, then the search bar, then the filter chips, then the products: no name header', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Peanut Cookies', id: 'pc')], size: const Size(380, 1400));
      final l10n = l10nOf(tester);
      // No "Peanut Cookies | 1 product | 1 on sale" header.
      expect(find.byKey(const Key('productHeader')), findsNothing);
      expect(find.textContaining(' on sale'), findsNothing);
      expect(find.byKey(const Key('productSummary')), findsNothing);
      // The order down the page.
      final kpi = tester.getTopLeft(find.byKey(const Key('productKpis'))).dy;
      final search = tester.getTopLeft(find.byType(TextField).first).dy;
      final chips = tester.getTopLeft(find.text('${l10n.prodChipAll} (1)')).dy;
      final card = tester.getTopLeft(find.byKey(const Key('productCard_pc'))).dy;
      expect(kpi, lessThan(search));
      expect(search, lessThan(chips));
      expect(chips, lessThan(card));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('search and chips are there even for one product: All, On Sale, Out of Stock, Archived', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Peanut Cookies')], size: const Size(900, 1400));
      final l10n = l10nOf(tester);
      expect(find.byKey(const Key('productControls')), findsOneWidget);
      expect(find.text(l10n.prodSearchHint), findsOneWidget);
      expect(find.text('${l10n.prodChipAll} (1)'), findsOneWidget);
      expect(find.text('${l10n.prodChipOnSale} (1)'), findsOneWidget);
      expect(find.text('${l10n.prodChipOutOfStock} (0)'), findsOneWidget);
      expect(find.text('${l10n.prodChipOff} (0)'), findsOneWidget);
      expect(l10n.prodChipOff, 'Archived');
      expect(find.textContaining('Turned Off'), findsNothing);
    });
  });

  testWidgets('no products: just the empty message, nothing to search or filter', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, const []);
      final l10n = l10nOf(tester);
      expect(find.text(l10n.prodEmpty), findsOneWidget);
      expect(find.byKey(const Key('productControls')), findsNothing);
      expect(find.byKey(const Key('productKpis')), findsNothing);
    });
  });

  testWidgets('the On sale switch and Edit price never touch: a clear gap, or the button below', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Peanut Cookies', id: 'pc'), _p('Coconut Jam', id: 'cj', on: false)], size: const Size(380, 1400));
      final l10n = l10nOf(tester);
      // On sale: side by side, label and button separated by at least 8 px.
      final onLabel = tester.getRect(find.text(l10n.prodOnSale));
      final onBtn = tester.getRect(find.byKey(const Key('editPrice_pc')));
      expect(onBtn.left - onLabel.right, greaterThanOrEqualTo(8));
      expect(onBtn.right, lessThanOrEqualTo(380));
      // Off: the longer label would crowd the button, so it goes below, at the right.
      final offLabel = tester.getRect(find.text(l10n.prodOffHidden));
      final offBtn = tester.getRect(find.byKey(const Key('editPrice_cj')));
      final noOverlap = offBtn.top >= offLabel.bottom || offBtn.left - offLabel.right >= 8;
      expect(noOverlap, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the discount pill is at most two lines on a phone', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Peanut Cookies', id: 'pc')], size: const Size(380, 1400));
      final pill = tester.getRect(find.byKey(const Key('discountPill_pc')));
      expect(pill.height, lessThan(46)); // two lines of 10.5 pt text plus padding
      expect(pill.width, lessThanOrEqualTo(88));
    });
  });

  testWidgets('chips and search filter the list, with counts that follow the products', (tester) async {
    await runIgnoringFontErrors(() async {
      final items = [
        for (var i = 1; i <= 5; i++) _p('Item $i'),
        _p('Granola Bar', qty: 0),
        _p('Coconut Jam', on: false),
        _p('Peanut Butter'),
      ];
      await pumpProducts(tester, items, size: const Size(900, 1600));
      final l10n = l10nOf(tester);
      expect(find.byKey(const Key('productControls')), findsOneWidget);
      expect(find.text('${l10n.prodChipAll} (8)'), findsOneWidget);
      expect(find.text('${l10n.prodChipOnSale} (7)'), findsOneWidget);
      expect(find.text('${l10n.prodChipOutOfStock} (1)'), findsOneWidget);
      expect(find.text('${l10n.prodChipOff} (1)'), findsOneWidget);

      await tester.tap(find.text('${l10n.prodChipOff} (1)'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('productCard_Coconut Jam')), findsOneWidget);
      expect(find.byKey(const Key('productCard_Item 1')), findsNothing);

      await tester.tap(find.text('${l10n.prodChipAll} (8)'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, 'butter');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('productCard_Peanut Butter')), findsOneWidget);
      expect(find.byKey(const Key('productCard_Item 1')), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(l10n.prodNoMatch), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('products from more than one category are grouped under headers with counts', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Peanut Cookies', cat: 'Harvest Stock'), _p('Rice Seeds', cat: 'Seeds'), _p('Corn Seeds', cat: 'Seeds')]);
      expect(find.byKey(const Key('category_harvest stock')), findsOneWidget);
      expect(find.byKey(const Key('category_seeds')), findsOneWidget);
      expect(find.text('Seeds · 2'), findsOneWidget);
      expect(find.text('Harvest Stock · 1'), findsOneWidget);
    });
  });

  testWidgets('archived products are dimmed and last, below every category, never between active ones', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [
        _p('Rice Seeds', cat: 'Seeds'),
        _p('Old Seeds', cat: 'Seeds', on: false),
        _p('Peanut Cookies', cat: 'Harvest Stock'),
        _p('Old Jam', cat: 'Harvest Stock', on: false),
      ], size: const Size(420, 2600));
      final l10n = l10nOf(tester);
      double y(String id) => tester.getTopLeft(find.byKey(Key('productCard_$id'))).dy;
      // Both active products come before the archived section, whatever their category.
      expect(y('Rice Seeds'), lessThan(y('Old Seeds')));
      expect(y('Peanut Cookies'), lessThan(y('Old Seeds')));
      expect(y('Peanut Cookies'), lessThan(y('Old Jam')));
      expect(find.byKey(const Key('archivedSection')), findsOneWidget);
      expect(find.text('${l10n.prodChipOff} · 2'), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('archivedSection'))).dy, greaterThan(y('Rice Seeds')));
      expect(tester.getTopLeft(find.byKey(const Key('archivedSection'))).dy, lessThan(y('Old Jam')));
      // They are dimmed.
      final dim = tester.widgetList<Opacity>(find.descendant(of: find.byKey(const Key('productCard_Old Seeds')), matching: find.byType(Opacity))).first;
      expect(dim.opacity, 0.6);
      expect(find.text(l10n.prodOffHidden), findsNWidgets(2));
    });
  });

  testWidgets('products from one category have no group headers', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Rice Seeds'), _p('Corn Seeds')]);
      expect(find.byKey(const Key('category_seeds')), findsNothing);
      expect(find.byKey(const Key('productCard_Rice Seeds')), findsOneWidget);
    });
  });

  testWidgets('an active program changes normally: the switch saves, Edit price and + are there', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Peanut Cookies', id: 'pc')]);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byKey(const Key('editPrice_pc')), findsOneWidget);
      expect(find.byKey(const Key('completedBanner')), findsNothing);
      expect(tester.widget<Switch>(find.byKey(const Key('productSwitch_pc'))).onChanged, isNotNull);
    });
  });

  testWidgets('a completed program: banner, no +, no Edit price, switch disabled, nothing is sent', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Peanut Cookies', id: 'pc'), _p('Coconut Jam', id: 'cj', on: false)], status: 'completed');
      final l10n = l10nOf(tester);
      expect(find.byKey(const Key('completedBanner')), findsOneWidget);
      expect(find.text(l10n.prodCompletedBanner), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byKey(const Key('editPrice_pc')), findsNothing);
      expect(tester.widget<Switch>(find.byKey(const Key('productSwitch_pc'))).onChanged, isNull);
      expect(tester.widget<Switch>(find.byKey(const Key('productSwitch_cj'))).onChanged, isNull);
      await tester.tap(find.byKey(const Key('productSwitch_pc')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(fake.calls('PATCH /rest/v1/program_products'), isEmpty);
      // The figures and the products are still there to read.
      expect(find.byKey(const Key('productKpis')), findsOneWidget);
    });
  });

  // ── stock for this program (allocation) ───────────────────────────────────
  ProgramProduct allocated(String name, {double onHand = 90, double stock = 30, double reserved = 0, String id = 'pc'}) => ProgramProduct(
        id: id,
        programId: 'p1',
        inventoryItemId: 'i-$name',
        itemName: name,
        category: 'Seeds',
        unit: 'sack',
        quantityOnHand: onHand,
        stockAllocated: stock,
        stockReserved: reserved,
        unitPrice: 50,
        isAvailable: true,
      );

  testWidgets('the card shows what is set aside for the program, not the whole shelf, and what open orders reserved', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [allocated('Peanut Cookies', onHand: 90, stock: 30, reserved: 4)]);
      final l10n = l10nOf(tester);
      expect(find.text(l10n.prodStockAvailable('26', 'sack')), findsOneWidget); // 30 - 4 reserved, not the 90 on hand
      expect(find.text(l10n.prodStockReserved('4', 'sack')), findsOneWidget);
      expect(find.textContaining('90'), findsNothing);
    });
  });

  testWidgets('a product with all its program stock reserved shows as out of stock', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [allocated('Peanut Cookies', onHand: 90, stock: 5, reserved: 5)]);
      expect(find.text(l10nOf(tester).prodOutOfStock), findsOneWidget);
    });
  });

  testWidgets('Edit shows the program stock beside the price, and saving a new figure calls the guarded function', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [allocated('Peanut Cookies', stock: 30)]);
      await tester.ensureVisible(find.byKey(const Key('editPrice_pc')));
      await tester.tap(find.byKey(const Key('editPrice_pc')));
      await tester.pump();
      final field = find.byKey(const Key('editStock_pc'));
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, '30');
      await tester.enterText(field, '40');
      await tester.tap(find.text(l10nOf(tester).prodSave));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 300));
      final calls = fake.calls('POST /rest/v1/rpc/set_program_product_allocation');
      expect(calls.length, 1);
      expect(calls.single.jsonMap['p_product_id'], 'pc');
      expect(calls.single.jsonMap['p_allocated'], 40);
      await tester.pump(const Duration(seconds: 4));
    });
  });


  testWidgets('the unsold program stock can be released to the cooperative stock', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [allocated('Peanut Cookies', stock: 30, reserved: 4)]);
      await tester.ensureVisible(find.byKey(const Key('editPrice_pc')));
      await tester.tap(find.byKey(const Key('editPrice_pc')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('releaseStock_pc')));
      await tester.tap(find.byKey(const Key('releaseStock_pc')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 300));
      final calls = fake.calls('POST /rest/v1/rpc/release_program_product_allocation');
      expect(calls.length, 1);
      expect(calls.single.jsonMap['p_product_id'], 'pc');
      await tester.pump(const Duration(seconds: 4));
    });
  });

  testWidgets('a product with nothing left to release has no Release button', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [allocated('Peanut Cookies', stock: 4, reserved: 4)]);
      await tester.ensureVisible(find.byKey(const Key('editPrice_pc')));
      await tester.tap(find.byKey(const Key('editPrice_pc')));
      await tester.pump();
      expect(find.byKey(const Key('releaseStock_pc')), findsNothing);
    });
  });

  testWidgets('Tagalog fits', (tester) async {
    await runIgnoringFontErrors(() async {
      await pumpProducts(tester, [_p('Peanut Cookies', id: 'pc')], purchases: purchases, locale: const Locale('tl'));
      expect(find.textContaining('Diskwento'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ── Program Management: a completed program is dimmed ───────────────────────
  Widget card(String status) => MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminProgramCard(
              program: CooperativeProgram(
                id: 'p9',
                programName: 'Peanut Seed Distribution',
                programType: 'Crop',
                benefitType: 'grant',
                seasonYear: 2026,
                status: status,
                memberCount: 4,
                sourceCategories: const ['Seeds'],
                description: 'x',
                budget: 500,
                imageUrl: null,
              ),
              accent: Colors.green,
              icon: Icons.eco,
              statusLabel: status == 'completed' ? 'COMPLETED' : 'ACTIVE',
              statusColor: Colors.grey,
              memberCountLabel: '4 members',
              onMembers: () {},
              onHistory: () {},
              onEdit: () {},
              onComplete: () {},
            ),
          ),
        ),
      );

  testWidgets('a completed program card is dimmed; its badge and buttons are not; an active one is not dimmed', (tester) async {
    await runIgnoringFontErrors(() async {
      await tester.pumpWidget(card('completed'));
      await tester.pump(const Duration(milliseconds: 300));
      final body = tester.widget<Opacity>(find.byKey(const Key('programBody_p9')));
      expect(body.opacity, kCompletedProgramOpacity);
      expect(kCompletedProgramOpacity, 0.6);
      // The badge is outside any dimming Opacity, so it stays at full strength.
      expect(find.ancestor(of: find.text('COMPLETED'), matching: find.byType(Opacity)), findsNothing);
      // So are the Manage Members and History buttons.
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
      expect(find.ancestor(of: find.text(l10n.programMgmtManageMembersAction), matching: find.byKey(const Key('programBody_p9'))), findsNothing);
      expect(find.ancestor(of: find.text(l10n.programMgmtHistoryAction), matching: find.byKey(const Key('programBody_p9'))), findsNothing);
      // The name is inside the dimmed part, and there is no Mark as Completed button any more.
      expect(find.ancestor(of: find.text('Peanut Seed Distribution'), matching: find.byKey(const Key('programBody_p9'))), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(card('active'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Opacity>(find.byKey(const Key('programBody_p9'))).opacity, 1.0);
    });
  });

  // ── p19 ───────────────────────────────────────────────────────────────────
  group('p19 SQL: a completed program\'s products are read-only', () {
    final sql = _read('supabase_schema/supabase_schema_program_rework_p19_completed_products_readonly.sql');
    final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

    test('a trigger refuses any insert or update once the program is completed, for signed-in callers', () {
      expect(code, contains('BEFORE INSERT OR UPDATE ON public.program_products'));
      expect(code, contains("cp.status = 'completed'"));
      expect(code, contains('auth.uid() IS NOT NULL'));
      expect(code, contains('PROGRAM_COMPLETED'));
    });

    test('nothing is deleted or rewritten', () {
      for (final w in ['DELETE FROM', 'DROP TABLE', 'TRUNCATE', 'DROP COLUMN', 'UPDATE public.program_products']) {
        expect(code.contains(w), isFalse, reason: w);
      }
    });

    test('the refusal is explained in plain words', () {
      expect(_read('lib/core/utils/app_error_message.dart'), contains("case 'PROGRAM_COMPLETED':"));
    });
  });
}
