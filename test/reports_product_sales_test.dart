import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/models/admin_reports_model.dart';
import 'package:sagana/data/repositories/admin_reports_repository.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:sagana/data/services/report_csv_serializers.dart';
import 'package:sagana/data/services/report_pdf_serializers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/test_storage_mocks.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// Cooperative Product sales in the reports: its own figure and its own Sales Report page (never
/// part of the selling channels or the Marketplace revenue), the Executive Snapshot as pairs,
/// a Dashboard Overview tied to the six Management Modules, and the exports that follow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_reports_ps');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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

  setUp(fake.reset);

  final sale = ProductSaleRow(
    id: 'p1',
    orderNumber: 'PSO-20261108-A001',
    farmerName: 'Maria Santos',
    itemName: 'Peanut Cookies',
    programName: 'Peanut Cookies Sale',
    quantity: 2.5,
    unit: 'sack',
    amount: 112.5,
    saleDate: DateTime(2026, 11, 8, 10, 30),
  );

  group('Cooperative Product sales figures', () {
    test(
      'adds up what members paid for completed orders: amount, orders, different buyers, average',
      () async {
        fake.on(
          'GET /rest/v1/program_product_purchases',
          (_) => [
            {'total_amount': 90, 'farmer_id': 'f1'},
            {'total_amount': 45.5, 'farmer_id': 'f1'},
            {'total_amount': 50, 'farmer_id': 'f2'},
          ],
        );
        final s = await AdminReportsRepository().fetchProductSalesForRange(
          DateTime(2026, 11, 1),
          DateTime(2026, 11, 30),
        );
        expect(s.amount, 185.5);
        expect(s.orders, 3);
        expect(s.buyers, 2);
        expect(s.averageOrder, closeTo(61.83, 0.01));
      },
    );

    test(
      'it asks only for COMPLETED orders, dated by the day they were completed, without the delivery fee',
      () async {
        await AdminReportsRepository().fetchProductSalesForRange(
          DateTime(2026, 11, 1),
          DateTime(2026, 11, 30),
        );
        final q = fake
            .calls('GET /rest/v1/program_product_purchases')
            .last
            .url
            .query;
        expect(q, contains('status=eq.completed'));
        expect(q, contains('completed_at=gte.'));
        expect(q, contains('completed_at=lt.'));
        expect(q.contains('delivery_fee'), isFalse);
      },
    );

    test('a failed read is zero rather than a crash', () async {
      fake.on(
        'GET /rest/v1/program_product_purchases',
        (_) => FakeError(500, 'boom'),
      );
      final s = await AdminReportsRepository().fetchProductSalesForRange(
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 31),
      );
      expect(s.amount, 0);
      expect(s.orders, 0);
    });

    test(
      'the report rows: newest first, with the member\'s name, product, quantity and unit',
      () async {
        fake.on(
          'GET /rest/v1/program_product_purchases',
          (_) => [
            {
              'id': 'p1',
              'order_number': 'PSO-20261108-A001',
              'farmer_id': 'f1',
              'item_name': 'Peanut Cookies',
              'program_name': 'Peanut Cookies Sale',
              'unit': 'sack',
              'quantity': 2.5,
              'total_amount': 112.5,
              'completed_at': '2026-11-08T02:30:00Z',
            },
          ],
        );
        fake.on(
          'GET /rest/v1/user_information',
          (_) => [
            {'user_id': 'f1', 'full_name': 'Maria Santos'},
          ],
        );
        final r = await AdminReportsRepository()
            .fetchProductSalesReportForRange(
              DateTime(2026, 11, 1),
              DateTime(2026, 11, 30),
            );
        expect(r.rows.single.farmerName, 'Maria Santos');
        expect(r.rows.single.quantity, 2.5);
        expect(r.summary.amount, 112.5);
        expect(r.summary.buyers, 1);
        expect(
          fake.calls('GET /rest/v1/program_product_purchases').last.url.query,
          contains('order=completed_at.desc'),
        );
      },
    );

    test(
      'the trend has one value per month, oldest first, zero where nothing was sold',
      () async {
        final now = DateTime.now();
        fake.on(
          'GET /rest/v1/program_product_purchases',
          (_) => [
            {
              'total_amount': 100,
              'completed_at': DateTime(
                now.year,
                now.month,
                2,
                12,
              ).toUtc().toIso8601String(),
            },
            {
              'total_amount': 50,
              'completed_at': DateTime(
                now.year,
                now.month,
                3,
                12,
              ).toUtc().toIso8601String(),
            },
          ],
        );
        final t = await AdminReportsRepository().fetchProductSalesTrend(
          months: 6,
        );
        expect(t.length, 6);
        expect(t.last, 150);
        expect(t.first, 0);
      },
    );
  });

  group(
    'the Dashboard Overview: one card per Management Module, with Revenue, for the year',
    () {
      test('every figure is read for the current year', () async {
        fake.on(
          'GET /rest/v1/orders',
          (_) => [
            {
              'total_price': 100,
              'created_at': '2026-02-02T01:00:00Z',
              'received_at': '2026-02-03T01:00:00Z',
            },
            {
              'total_price': 60,
              'created_at': '2026-03-02T01:00:00Z',
              'received_at': '2026-03-04T01:00:00Z',
            },
          ],
        );
        fake.on(
          'GET /rest/v1/program_product_purchases',
          (_) => [
            {'total_amount': 90, 'farmer_id': 'f1'},
            {'total_amount': 40, 'farmer_id': 'f2'},
          ],
        );
        // Supply Chain Management: Total Supplies from the read-only database function.
        fake.on(
          'POST /rest/v1/rpc/get_supply_chain_totals',
          (_) => [
            {'incoming': 5, 'outgoing': 3, 'in_progress': 2},
          ],
        );
        fake.on(
          'HEAD /rest/v1/cooperative_inventory',
          (_) => const FakeCount(12),
        );
        fake.on(
          'GET /rest/v1/cooperative_inventory',
          (_) => const FakeCount(12),
        );
        fake.on('HEAD /rest/v1/crop_master', (_) => const FakeCount(9));
        fake.on('GET /rest/v1/crop_master', (_) => const FakeCount(9));
        fake.on(
          'HEAD /rest/v1/cooperative_programs',
          (_) => const FakeCount(3),
        );
        fake.on('GET /rest/v1/cooperative_programs', (_) => const FakeCount(3));
        fake.on('HEAD /rest/v1/price_records', (_) => const FakeCount(40));
        fake.on('GET /rest/v1/price_records', (_) => const FakeCount(40));
        final o = await AdminReportsRepository().fetchDashboardOverview();
        expect(o.inventoryItems, 12);
        expect(o.crops, 9);
        expect(o.programs, 3);
        expect(o.revenue, 290); // 160 Marketplace + 130 Cooperative Products
        expect(o.suppliesIncoming, 5);
        expect(o.suppliesOutgoing, 3);
        expect(o.totalSupplies, 8); // incoming + outgoing; in-progress orders are not counted
        expect(o.retailPrices, 40);
        final year = DateTime.now().year;
        String q(String t) => [
          ...fake.calls('HEAD /rest/v1/$t'),
          ...fake.calls('GET /rest/v1/$t'),
        ].map((r) => r.url.query).join(' | ');
        expect(q('cooperative_programs'), contains('season_year=eq.$year'));
        expect(Uri.decodeQueryComponent(q('price_records')).replaceAll('"', ''), contains('price_type=in.(open_market,sp3_cooperative)')); // Public + Cooperative Market
        expect(q('price_records'), contains('recorded_at=gte.'));
      });

      test(
        'six cards in this order: Inventory, Crops, Programs, Revenue, Supply Chain, Prices; no month label',
        () {
          final src = _read(
            'lib/presentation/screens/admin/admin_dashboard_screen.dart',
          );
          final strip = src.substring(
            src.indexOf('class _KpiStrip'),
            src.indexOf('class _MiniCalendar'),
          );
          expect(RegExp(r'DashboardKpiTile\(').allMatches(strip).length, 6);
          final order = RegExp(
            r'label: l10n\.(\w+)',
          ).allMatches(strip).map((m) => m.group(1)).toList();
          expect(order, [
            'adminDashModInventory',
            'adminDashModCrops',
            'adminDashModPrograms',
            'adminDashKpiRevenue',
            'adminDashModSupplyChain',
            'adminDashModPrices',
          ]);
          final en = _read('lib/core/l10n/app_en.arb');
          expect(en, contains('"adminDashOverviewTitle": "Overview"'));
          expect(en.contains('(This Month)'), isFalse);
          expect(src, contains('fetchDashboardOverview()'));
        },
      );
    },
  );

  group('the report layouts stay balanced', () {
    test(
      'Executive Snapshot: related metrics are paired in the same row of the two-column grid',
      () {
        final src = _read(
          'lib/presentation/screens/admin/operational_reports_screen.dart',
        );
        final snapshot = src.substring(
          src.indexOf('Widget _buildExecutiveSnapshot'),
          src.indexOf('bool get _hasInsights'),
        );
        final order = RegExp(
          r'label: l10n\.(\w+)',
        ).allMatches(snapshot).map((m) => m.group(1)).toList();
        expect(order, [
          'reportsSnapTotalSales', 'reportsSnapTotalHarvested', //
          'reportsMarketplaceRevenue', 'reportsProductSales',
          'reportsCompletedOrders', 'reportsSnapActiveLoans',
          'reportsSnapTotalExpenses', 'reportsSnapParticipation',
        ]);
        expect(order.length.isEven, isTrue);
      },
    );

    test(
      'Sales Report: two swipeable pages, each with its own trend, search and transactions',
      () {
        final src = _read(
          'lib/presentation/screens/admin/sales_report_screen.dart',
        );
        expect(src, contains('PageView('));
        expect(src, contains("Key('salesPage_marketplace')"));
        expect(src, contains("Key('salesPage_product')"));
        expect(src, contains('rptTabMarketplaceSales'));
        expect(src, contains('rptTabProductSales'));
        final productPage = src.substring(
          src.indexOf("key: const Key('salesPage_product')"),
          src.indexOf('/// One swipeable page'),
        );
        expect(productPage, contains('_buildProductOverview'));
        expect(productPage, contains('ReportTrendCard('));
        expect(productPage, contains('_buildProductTransactions'));
        expect(
          productPage.contains('_buildChannelBreakdown'),
          isFalse,
        ); // the channels belong to the first page
        // Its own search, separate from the Marketplace one.
        expect(src, contains('_productSearch'));
        expect(src, contains('rptSearchProductSales'));
        // No subtitle on either overview card.
        expect(src.contains('rptSalesOverviewHint'), isFalse);
        expect(src.contains('rptProductSalesHint'), isFalse);
        // Cooperative Product sales never enter the selling channels or the Total Revenue.
        final repo = _read(
          'lib/data/repositories/admin_reports_repository.dart',
        );
        final channels = repo.substring(
          repo.indexOf('Future<SalesReportData> fetchSalesReportForRange'),
          repo.indexOf('Future<List<double>> fetchSalesTrend'),
        );
        expect(channels.contains('program_product_purchases'), isFalse);
        expect(channels.contains('ProductSales'), isFalse);
      },
    );
  });

  group('the exports follow the screen', () {
    final marketplace = SalesReportData(
      totalRevenue: 2500,
      totalQuantityKg: 100,
      transactionCount: 0,
      monthlyTrend: const [],
      transactions: const [],
    );
    final products = ProductSalesReportData(
      summary: const ProductSalesSummary(amount: 112.5, orders: 1, buyers: 1),
      rows: [sale],
    );

    test(
      'CSV: two titled sections, Marketplace Sales then Cooperative Product Sales',
      () {
        final lines = serializeSalesReportCsv(
          marketplace,
          products,
        ).trim().split('\n');
        expect(lines.first, 'Marketplace Sales');
        expect(lines[1], startsWith('Selling Channel,'));
        final at = lines.indexOf('Cooperative Product Sales');
        expect(at, greaterThan(1));
        expect(
          lines[at + 1],
          'Member Name,Product,Program,Quantity,Amount (PHP),Completed Date,Order Number',
        );
        expect(
          lines[at + 2],
          contains(
            'Maria Santos,Peanut Cookies,Peanut Cookies Sale,2.50 sack,112.50',
          ),
        );
        expect(lines[at + 2], endsWith('PSO-20261108-A001'));
      },
    );

    test(
      'CSV without the product part is exactly as before (no title rows)',
      () {
        final lines = serializeSalesReportCsv(marketplace).trim().split('\n');
        expect(lines.first, startsWith('Selling Channel,'));
      },
    );

    test('PDF builds with both sections', () async {
      final doc = await buildSalesReportPdf(
        marketplace,
        scopeText: 'This Month',
        products: products,
      );
      expect((await doc.save()).isNotEmpty, isTrue);
    });

    test('both export services read the product sales for the same period', () {
      expect(
        _read('lib/data/services/csv_export_service.dart'),
        contains('fetchProductSalesReport(period)'),
      );
      expect(
        _read('lib/data/services/pdf_export_service.dart'),
        contains('fetchProductSalesReport(period)'),
      );
      expect(
        _read('lib/data/services/csv_export_service.dart'),
        contains("'Cooperative Product Sales (PHP)'"),
      );
    });
  });
}
