import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/models/admin_dashboard_model.dart';
import 'package:sagana/data/repositories/admin_dashboard_repository.dart';
import 'package:sagana/data/services/hive_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/test_storage_mocks.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// The Cooperative Performance card covers ALL farmer-members, however many there are: exact
/// counts from the database, every page of the rows (the server stops at 1,000 per request),
/// stock added up per unit, and a sales figure that is the Farmers' sales across every channel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    mockStorageChannels();
    mockConnectivityOnline();
    final dir = Directory.systemTemp.createTempSync('sagana_coop_perf');
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

  /// The rows a "page" of the request asks for (the server gives 1,000 at most).
  List<Map<String, Object?>> page(
    RecordedRequest r,
    List<Map<String, Object?>> all,
  ) {
    final offset = int.tryParse(r.url.queryParameters['offset'] ?? '0') ?? 0;
    final limit =
        int.tryParse(r.url.queryParameters['limit'] ?? '1000') ?? 1000;
    return all.skip(offset).take(limit).toList();
  }

  test(
    'Harvests is the exact count of every harvest record (not rows downloaded, so no 1,000 stop)',
    () async {
      fake.on('HEAD /rest/v1/harvest_records', (_) => const FakeCount(2500));
      fake.on('GET /rest/v1/harvest_records', (_) => const FakeCount(2500));
      final s = await AdminDashboardRepository().fetchCoopPerformance();
      expect(s.totalHarvests, 2500);
    },
  );

  test(
    'Farmer Stock is added up PER UNIT: available plus reserved, never kilograms mixed with sacks',
    () async {
      fake.on(
        'GET /rest/v1/inventory_batches',
        (r) => page(r, [
          {
            'available_kg': 40,
            'reserved_kg': 20,
            'unit': 'kg',
            'status': 'available',
          },
          {
            'available_kg': 5,
            'reserved_kg': 0,
            'unit': 'sack',
            'status': 'available',
          },
          {
            'available_kg': 3.5,
            'reserved_kg': 0.5,
            'unit': 'sack',
            'status': 'reserved',
          },
          {
            'available_kg': 0,
            'reserved_kg': 0,
            'unit': 'kg',
            'status': 'sold_out',
          },
        ]),
      );
      final s = await AdminDashboardRepository().fetchCoopPerformance();
      expect(s.farmerStock.map((e) => (e.unit, e.quantity)).toList(), [
        ('kg', 60.0),
        ('sack', 9.0),
      ]);
      // A withdrawn batch is not stock: the database is asked to leave it out.
      expect(
        fake.calls('GET /rest/v1/inventory_batches').first.url.query,
        contains('status=neq.withdrawn'),
      );
    },
  );

  test(
    'Farmer Stock reads EVERY page (1,005 batches, not just the first 1,000)',
    () async {
      final all = [
        for (var i = 0; i < 1005; i++)
          {
            'available_kg': 1,
            'reserved_kg': 0,
            'unit': 'kg',
            'status': 'available',
          },
      ];
      fake.on('GET /rest/v1/inventory_batches', (r) => page(r, all));
      final s = await AdminDashboardRepository().fetchCoopPerformance();
      expect(s.farmerStock.single.quantity, 1005);
      expect(fake.calls('GET /rest/v1/inventory_batches').length, 2);
    },
  );

  test(
    'Listings counts every approved listing of this year, sold out ones included (so it matches All Listings)',
    () async {
      fake.on('HEAD /rest/v1/marketplace_listings', (_) => const FakeCount(8));
      fake.on('GET /rest/v1/marketplace_listings', (_) => const FakeCount(8));
      final s = await AdminDashboardRepository().fetchCoopPerformance();
      expect(s.activeListings, 8);
      final q = [
        ...fake.calls('HEAD /rest/v1/marketplace_listings'),
        ...fake.calls('GET /rest/v1/marketplace_listings'),
      ].first.url.query;
      expect(Uri.decodeQueryComponent(q).replaceAll('"', ''), contains('status=in.(approved,sold)'));
      expect(q, contains('created_at=gte.'));
      expect(
        q.contains('remaining_kg'),
        isFalse,
      ); // a sold out listing is still an approved listing
    },
  );

  test(
    'every figure is for the CURRENT YEAR: it starts again each January',
    () async {
      fake.on('HEAD /rest/v1/harvest_records', (_) => const FakeCount(3));
      fake.on('GET /rest/v1/harvest_records', (_) => const FakeCount(3));
      await AdminDashboardRepository().fetchCoopPerformance();
      final year = DateTime.now().year;
      String q(String table) => [
        ...fake.calls('HEAD /rest/v1/$table'),
        ...fake.calls('GET /rest/v1/$table'),
      ].map((r) => r.url.query).join(' | ');
      expect(q('harvest_records'), contains('harvest_date=gte.$year-01-01'));
      expect(q('inventory_batches'), contains('created_at=gte.'));
      expect(q('marketplace_listings'), contains('created_at=gte.'));
    },
  );

  test(
    'participation: farmer-members who harvested this season, of all active members',
    () async {
      fake.on(
        'GET /rest/v1/user_roles',
        (_) => [
          for (var i = 1; i <= 8; i++) {'user_id': 'f$i', 'status': 'active'},
          {'user_id': 'p1', 'status': 'pending'},
        ],
      );
      fake.on(
        'GET /rest/v1/harvest_records',
        (r) => page(r, [
          {'farmer_id': 'f1'},
          {'farmer_id': 'f1'},
          {'farmer_id': 'f2'},
          {'farmer_id': 'p1'}, // not an active member: not counted
        ]),
      );
      final s = await AdminDashboardRepository().fetchCoopPerformance();
      expect(s.activeMembersThisSeason, 2);
      expect(s.totalMembers, 8);
    },
  );

  group('what the card says (read from the code)', () {
    final repo = _read('lib/data/repositories/admin_dashboard_repository.dart');
    final fn = repo.substring(
      repo.indexOf('Future<CoopPerformanceSummary> fetchCoopPerformance()'),
      repo.indexOf('Future<String?> fetchAdminFirstName()'),
    );

    test(
      'Sales (all-time) is the Farmers\' sales across all four channels, in pesos',
      () {
        expect(fn, contains('ReportPeriod.thisYear.range()'));
        expect(
          fn,
          contains(
            'fetchSalesReportForRange(window.startDate, window.endDate)',
          ),
        );
        expect(fn, contains('salesAmount = report.totalRevenue'));
        expect(
          fn.contains("from('orders')"),
          isFalse,
        ); // no longer a count of Marketplace orders
        final screen = _read(
          'lib/presentation/screens/admin/admin_dashboard_screen.dart',
        );
        expect(screen, contains('formatPesosCompact(summary.salesAmount)'));
      },
    );

    test('Farmer Stock shows one line per unit', () {
      final screen = _read(
        'lib/presentation/screens/admin/admin_dashboard_screen.dart',
      );
      expect(screen, contains('formatQuantitiesByUnit(summary.farmerStock)'));
      expect(screen.contains('formatKgTotal(summary.totalStockKg)'), isFalse);
    });

    test('the model has no kilogram-only stock field any more', () {
      const s = CoopPerformanceSummary.empty;
      expect(s.farmerStock, isEmpty);
      expect(s.salesAmount, 0);
    });
  });
}
