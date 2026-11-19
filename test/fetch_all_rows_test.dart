import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/utils/fetch_all_rows.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_supabase.dart';
import 'support/test_storage_mocks.dart';

/// The database answers a plain select with at most 1,000 rows. The Manager's Order Management used to
/// stop at the newest 1,000 of 4,000+ orders. fetchAllRows reads page after page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = FakeSupabaseHttp();

  setUpAll(() async {
    mockStorageChannels();
    final dir = Directory.systemTemp.createTempSync('sagana_pages');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    await Supabase.initialize(url: 'http://localhost:54321', publishableKey: 'test-key', httpClient: fake);
  });

  List<Map<String, dynamic>> table(int n) => [for (var i = 0; i < n; i++) {'id': 'o$i'}];

  Future<List<Map<String, dynamic>>> run(int total) {
    fake.reset();
    final all = table(total);
    fake.on('GET /rest/v1/orders', (req) {
      final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
      final limit = int.parse(req.url.queryParameters['limit'] ?? '1000');
      return all.skip(offset).take(limit).toList();
    });
    return fetchAllRows((from, to) => Supabase.instance.client.from('orders').select('id').order('id').range(from, to));
  }

  test('4,200 rows come back in full and in order, read three pages at a time', () async {
    final rows = await run(4200);
    expect(rows, hasLength(4200));
    expect(rows.first['id'], 'o0');
    expect(rows.last['id'], 'o4199');
    expect(fake.requests.where((r) => r.method == 'GET').length, 6); // 3 + 3 pages (the last three are short)
  });

  test('under one page: the first round of three requests already has everything', () async {
    final rows = await run(37);
    expect(rows, hasLength(37));
    expect(fake.requests.where((r) => r.method == 'GET').length, 3);
  });

  test('exactly 1,000 rows: nothing is lost and nothing is doubled', () async {
    final rows = await run(1000);
    expect(rows, hasLength(1000));
    expect(rows.map((r) => r['id']).toSet(), hasLength(1000));
  });

  test('an empty table is an empty list', () async {
    expect(await run(0), isEmpty);
  });

  test('the Manager order, listing, cooperative-order and loan lists, the loan totals and the Buyer listings use it', () {
    for (final f in [
      'lib/data/repositories/admin_order_repository.dart',
      'lib/data/repositories/cooperative_order_repository.dart',
      'lib/data/repositories/admin_listing_repository.dart',
      'lib/data/repositories/admin_loan_repository.dart',
      'lib/data/repositories/buyer_marketplace_repository.dart',
    ]) {
      expect(File(f).readAsStringSync(), contains('fetchAllRows('), reason: f);
    }
  });
}
