import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/data/models/admin_reports_model.dart';
import 'package:sagana/data/models/farmer_transaction_model.dart';
import 'package:sagana/data/repositories/market_linking_repository.dart';
import 'package:sagana/presentation/widgets/market_linking_sale_widgets.dart';

import 'support/ignore_font_errors.dart';

String read(String path) => File(path).readAsStringSync();

String sqlCode(String path) =>
    read(path).split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

String classSource(String src, String name) {
  final start = src.indexOf('class $name ');
  if (start < 0) throw StateError('class $name not found');
  final next = src.indexOf('\nclass ', start + 1);
  return src.substring(start, next < 0 ? src.length : next);
}

Widget localized(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      theme: AppTheme.lightTheme,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

MarketLinkingModel request(
  String status, {
  double volume = 80,
  double sold = 0,
  Map<String, dynamic> extra = const {},
}) =>
    MarketLinkingModel.fromMap({
      'id': 'p-$status-$volume-$sold',
      'farmer_id': 'f1',
      'farmer_name': 'Juan Dela Cruz',
      'crop_name': 'Ginger',
      'season_year': 2026,
      'status': status,
      'volume_kg': volume,
      'sold_kg': sold,
      'submitted_at': '2026-10-01T00:00:00Z',
      ...extra,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const managerScreen = 'lib/presentation/screens/admin/market_linking_screen.dart';
  const farmerScreen = 'lib/presentation/screens/farmer/my_market_linking_screen.dart';

  group('Buyer Details: no address', () {
    test('the form, the repository call and the buyer block have no address', () {
      final manager = read(managerScreen);
      expect(classSource(manager, '_BuyerDetailsSheetState'), isNot(contains('_addressCtrl')));;
      final repo = read('lib/data/repositories/market_linking_repository.dart');
      final save = repo.substring(repo.indexOf('Future<void> saveBuyerDetails'),
          repo.indexOf('Future<String> recordSale'));
      expect(save, isNot(contains('_addressCtrl')));;
      expect(save, contains("'p_buyer_email'"));
      expect(read('lib/presentation/widgets/market_linking_sale_widgets.dart'), isNot(contains('buyerAddress')));
      expect(read('lib/core/l10n/app_en.arb'), isNot(contains('mlkBuyerAddress')));
    });
  });

  group('Complete Sale: Quantity and Price line up', () {
    test('the two fields are laid out with the shared aligned label, responsive to width', () {
      final sale = classSource(read(managerScreen), '_CompleteSaleSheetState');
      expect(sale, contains('AlignedLabeledField('));
      expect(sale, contains('LayoutBuilder('));
      expect(sale, contains('constraints.maxWidth < 300'));
      expect(sale, isNot(contains('_FieldLabel(label: l10n.mlkSaleQty')));
      expect(sale, isNot(contains('_FieldLabel(label: l10n.mlkSalePrice')));
    });

    for (final width in [320.0, 360.0, 420.0]) {
      testWidgets('input boxes share a top edge and a height at $width px, even when one label wraps', (tester) async {
        await runIgnoringFontErrors(() async {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(localized(
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AlignedLabeledField(
                      label: 'Quantity purchased (kg) *',
                      child: TextFormField(key: const Key('qty'), decoration: const InputDecoration(suffixText: 'kg', hintText: '0.00')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AlignedLabeledField(
                      label: 'Price',
                      child: TextFormField(key: const Key('price'), decoration: const InputDecoration(prefixText: '₱ ', hintText: '0.00')),
                    ),
                  ),
                ],
              ),
            ),
          ));
          final qty = tester.getRect(find.byKey(const Key('qty')));
          final price = tester.getRect(find.byKey(const Key('price')));
          expect(qty.top, price.top);
          expect(qty.height, price.height);
          expect(qty.width, price.width);
          expect(tester.takeException(), isNull);
        });
      });
    }
  });

  group('Summary card: four real figures', () {
    final entries = [
      request('buyer_found', volume: 80, sold: 50), // active, 30 left
      request('submitted', volume: 10), // active, 10 left
      request('completed', volume: 20, sold: 20),
      request('completed', volume: 50, sold: 20), // closed early: 20 sold
      request('cancelled', volume: 15),
    ];

    test('In Progress, Kg Sold, Kg Remaining, Completed come from the actual records', () {
      final s = MarketLinkingSummary.of(entries);
      expect(s.inProgress, 2);
      expect(s.kgSold, 90); // 50 + 0 + 20 + 20 + 0
      expect(s.kgRemaining, 40); // only the two active requests: 30 + 10
      expect(s.completed, 2); // the cancelled one is not counted
    });

    test('decimals stay exact and nothing is estimated', () {
      final s = MarketLinkingSummary.of([request('buyer_found', volume: 10.75, sold: 4.45)]);
      expect(s.kgSold, 4.45);
      expect(s.kgRemaining, 6.3);
      final empty = MarketLinkingSummary.of(const []);
      expect([empty.inProgress, empty.kgSold, empty.kgRemaining, empty.completed], [0, 0, 0, 0]);
    });

    test('the card is a 2 x 2 grid of those four labels', () {
      final src = classSource(read(farmerScreen), '_SummaryCard');
      expect(src, contains('MarketLinkingSummary.of(entries)'));
      for (final k in ['mlkStatInProgress', 'mlkStatKgSold', 'mlkStatKgRemaining', 'statCompleted']) {
        expect(src, contains('l10n.$k'), reason: k);
      }
      // two rows of two tiles
      expect(RegExp(r'\n\s+Row\(\n\s+children: \[\n\s+tile\(').allMatches(src).length, 2);
      expect(RegExp(r'\btile\(').allMatches(src).length, greaterThanOrEqualTo(4));
    });

    testWidgets('the English labels', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(localized(const SizedBox()));
        final l10n = AppLocalizations.of(tester.element(find.byType(SizedBox)));
        expect(l10n.mlkStatInProgress, 'In Progress');
        // Unit-neutral: the card shows the quantity with each request's own unit.
        expect(l10n.mlkStatKgSold, 'Sold');
        expect(l10n.mlkStatKgRemaining, 'Remaining');
        expect(l10n.statCompleted, 'Completed');
      });
    });
  });

  group('Farmer screen: swipeable In Progress / Completed tabs', () {
    final src = read(farmerScreen);

    test('two tabs in a swipeable view, the summary card above them', () {
      expect(src, contains('TabController(length: 2'));
      expect(src, contains('TabBarView('));
      expect(src, contains('SingleTickerProviderStateMixin'));
      final summaryAt = src.indexOf('_SummaryCard(entries: _entries)');
      final tabBarAt = src.indexOf('_RequestTabBar(');
      final viewAt = src.indexOf('TabBarView(');
      expect(summaryAt, greaterThan(0));
      expect(tabBarAt, greaterThan(summaryAt));
      expect(viewAt, greaterThan(tabBarAt));
      // tapping a tab is the TabBar's own behaviour on the same controller
      expect(classSource(src, '_RequestTabBar'), contains('TabBar('));
    });

    test('In Progress holds the active requests; Completed holds the completed ones (cancelled kept below, labelled)', () {
      expect(src, contains('final inProgress = _entries.where((e) => e.isActive).toList();'));
      expect(src, contains('e.status == MarketLinkingStatus.completed'));
      expect(src, contains('l10n.mlkStatusCancelled'));
      // each tab refreshes on its own and has an empty state
      expect(classSource(src, '_RequestList'), contains('RefreshIndicator('));
      expect(src, contains('l10n.mlkEmptyInProgress'));
      expect(src, contains('l10n.mlkEmptyCompleted'));
    });

    test('cancellation actions and progress stay on the request card', () {
      final card = classSource(src, '_RequestCard');
      expect(card, contains('l10n.mlkRequestCancellation'));
      expect(card, contains('MarketLinkingSaleProgress'));
      expect(card, contains('MarketLinkingSalesList'));
    });
  });

  group('Buyer Details are visible to the Farmer, read-only', () {
    final src = read(farmerScreen);

    test('a Buyer Details section, or "Awaiting Buyer Details" before there is one', () {
      final section = classSource(src, '_FarmerBuyerSection');
      expect(section, contains('MarketLinkingBuyerBlock(entry: entry)'));
      expect(section, contains('l10n.mlkAwaitingBuyer'));
      expect(section, contains('l10n.mlkAwaitingBuyerBody'));
      // read-only: nothing to type into
      expect(section, isNot(contains('TextField')));
      expect(section, isNot(contains('TextFormField')));
      // shown on every request that is not cancelled, so it stays after Completed
      expect(classSource(src, '_RequestCard'), contains('_FarmerBuyerSection(entry: entry)'));
      expect(classSource(src, '_RequestCard'), contains('if (!isCancelled) ...['));
    });

    test('saved changes reach the Farmer by themselves', () {
      expect(src, contains("tables: const ['market_linking_programs', 'market_linking_sales']"));
      expect(src, contains('_loadEntries(quiet: true)'));
      expect(src, contains('_watcher?.dispose()'));
    });

    testWidgets('the saved buyer shows to the Farmer with name, contact and email', (tester) async {
      await runIgnoringFontErrors(() async {
        final e = request('buyer_found', extra: {
          'buyer_name': 'Buyer A',
          'buyer_contact': '0917 000 0001',
          'buyer_email': 'buyer.a@example.com',
        });
        await tester.pumpWidget(localized(MarketLinkingBuyerBlock(entry: e)));
        for (final t in ['Buyer A', '0917 000 0001', 'buyer.a@example.com']) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
      });
    });

    test('the Manager edit leaves the transaction alone (no status, quantity, price or stock in the call)', () {
      final repo = read('lib/data/repositories/market_linking_repository.dart');
      final save = repo.substring(repo.indexOf('Future<void> saveBuyerDetails'),
          repo.indexOf('Future<String> recordSale'));
      for (final p in ['status', 'quantity', 'price', 'volume', 'stock', 'inventory']) {
        expect(save.toLowerCase(), isNot(contains("'p_$p")), reason: p);
      }
    });
  });

  group('Completed sales show their buyer and price in both transaction views', () {
    test('the sale rows carry price, contact and email through the offline cache', () {
      final row = SalesTransactionRow(
        id: 's1',
        farmerName: 'Juan',
        cropType: 'ginger',
        cropName: 'Ginger',
        quantityKg: 50,
        amount: 2275,
        saleDate: DateTime.utc(2026, 10, 20),
        sellingType: 'da_amad_market_linking',
        buyerName: 'Buyer A',
        buyerContact: '0917 000 0001',
        buyerEmail: 'a@example.com',
        pricePerKg: 45.5,
      );
      final back = SalesTransactionRow.fromMap(row.toMap());
      expect(back.buyerName, 'Buyer A');
      expect(back.buyerContact, '0917 000 0001');
      expect(back.buyerEmail, 'a@example.com');
      expect(back.pricePerKg, 45.5);
      expect(back.amount, 2275);
      final f = FarmerTransactionModel(
        id: 's1',
        sellingType: 'da_amad_market_linking',
        cropName: 'Ginger',
        quantityKg: 50,
        amount: 2275,
        transactionDate: _epoch,

        buyerName: 'Buyer A',
        buyerContact: '0917',
        buyerEmail: 'a@example.com',
        pricePerKg: 45.5,
      );
      expect(f.pricePerKg, 45.5);
    });

    test('both repositories read the buyer and price from the sale, tolerating a missing email column', () {
      for (final f in [
        'lib/data/repositories/farmer_transaction_repository.dart',
        'lib/data/repositories/admin_reports_repository.dart',
      ]) {
        final src = read(f);
        expect(src, contains('buyer_contact'), reason: f);
        expect(src, contains('buyer_email'), reason: f);
        expect(src, contains("buyerContact: r"), reason: f);
      }
    });

    test('both detail views show the agreed price, the buyer, contact and email', () {
      final farmer = read('lib/presentation/screens/farmer/farmer_transaction_history_screen.dart');
      final report = read('lib/presentation/screens/admin/sales_report_screen.dart');
      for (final src in [farmer, report]) {
        for (final k in ['mlkDetailAgreedPrice', 'mlkDetailBuyerContact', 'mlkDetailBuyerEmail']) {
          expect(src, contains(k), reason: k);
        }
      }
      // Both name the buyer under the same "Sold To" label.
      expect(farmer, contains('l10n.rptSoldTo'));
      expect(report, contains('l10n.rptSoldTo'));
    });
  });

  group('Enrollment congratulations: once, and remembered', () {
    final src = read(farmerScreen);

    test('shown only for a newly approved enrollment that is not acknowledged anywhere', () {
      expect(src, contains('enrollment.status == DaAmadEnrollmentStatus.approved &&'));
      expect(src, contains('enrollment.acknowledgedAt == null &&'));
      expect(src, contains('!HiveService.getDaAmadApprovalSeen(enrollment.id'));
    });

    test('Continue remembers it on the device and on the server, for that enrollment', () {
      final dismiss = src.substring(src.indexOf('Future<void> _dismissApprovalCelebration'),
          src.indexOf('Future<void> _loadEntries'));
      expect(dismiss, contains('HiveService.setDaAmadApprovalSeen(enrollment.id'));
      expect(dismiss, contains('_repo.acknowledgeEnrollment(enrollment.id)'));
      final repo = read('lib/data/repositories/market_linking_repository.dart');
      expect(repo, contains("'acknowledge_da_amad_enrollment'"));
      expect(repo, contains("acknowledgedAt: row['acknowledged_at']"));
    });

    test('the database acknowledges only the owner\'s approved enrollment, once; existing approvals are marked done', () {
      final sql = sqlCode('supabase_schema/supabase_schema_market_linking_visibility_and_ack.sql');
      expect(sql, contains('ADD COLUMN IF NOT EXISTS acknowledged_at'));
      expect(sql, contains("WHERE status = 'approved' AND acknowledged_at IS NULL"));
      final fn = sql.substring(sql.indexOf('FUNCTION public.acknowledge_da_amad_enrollment'));
      expect(fn, contains('farmer_id = auth.uid()'));
      expect(fn, contains("status = 'approved'"));
      expect(fn, contains('COALESCE(acknowledged_at, NOW())'));
    });
  });

  group('Buyer visibility in the database', () {
    final sql = sqlCode('supabase_schema/supabase_schema_market_linking_visibility_and_ack.sql');

    test('Buyer Details have no address and change only the buyer', () {
      final fn = sql.substring(sql.indexOf('FUNCTION public.save_market_linking_buyer_details'),
          sql.indexOf('ALTER TABLE public.market_linking_sales'));
      expect(fn, isNot(contains('buyer_address')));
      expect(fn, isNot(contains('p_buyer_address')));
      for (final untouched in ['sold_kg', 'reserved_kg', 'price_per_kg', 'inventory_batches', 'volume_kg']) {
        expect(fn, isNot(contains(untouched)), reason: untouched);
      }
      expect(fn, contains('IF NOT public.is_staff()'));
    });

    test('no new access is granted: the Farmer\'s own rows only, and realtime for both tables', () {
      expect(sql, isNot(contains('CREATE POLICY')));
      expect(sql, contains("tablename = 'market_linking_programs'"));
      expect(sql, contains("tablename = 'market_linking_sales'"));
    });

    test('each sale keeps the buyer\'s email as it was when recorded', () {
      expect(sql, contains('ALTER TABLE public.market_linking_sales ADD COLUMN IF NOT EXISTS buyer_email'));
      expect(sql, contains('trg_market_linking_sales_buyer_snapshot'));
      expect(sql, contains('BEFORE INSERT ON public.market_linking_sales'));
    });
  });
}

final _epoch = DateTime.utc(2026, 10, 20);
