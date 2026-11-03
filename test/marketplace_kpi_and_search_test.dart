import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/repositories/admin_listing_repository.dart';
import 'package:sagana/data/repositories/admin_order_repository.dart';
import 'package:sagana/data/repositories/market_linking_repository.dart';

String read(String path) => File(path).readAsStringSync();

MarketLinkingModel request(Map<String, dynamic> extra) => MarketLinkingModel.fromMap({
      'id': 'p1',
      'farmer_id': 'f1',
      'farmer_name': 'Juan Dela Cruz',
      'crop_name': 'Ginger',
      'season_year': 2026,
      'status': 'buyer_found',
      'volume_kg': 80,
      'submitted_at': '2026-10-01T00:00:00Z',
      ...extra,
    });

void main() {
  const dashboard = 'lib/presentation/screens/admin/marketplace_dashboard_screen.dart';
  const manager = 'lib/presentation/screens/admin/market_linking_screen.dart';

  group('Marketplace KPI figures', () {
    test('listings: All = every non-withdrawn listing, Pending = pending_review', () {
      final s = ListingSummaryStats.fromCountRows([
        {'status': 'total', 'n': 12},
        {'status': 'pending_review', 'n': 3},
        {'status': 'approved', 'n': 6},
        {'status': 'sold', 'n': 2},
        {'status': 'rejected', 'n': 1},
      ]);
      expect([s.total, s.pending, s.approved, s.sold, s.rejected], [12, 3, 6, 2, 1]);
      expect(ListingSummaryStats.fromCountRows(const []).total, 0);
    });

    test('orders: Total is every order; legacy rejected counts as cancelled', () {
      final s = OrderSummaryStats.fromCountRows([
        {'status': 'total', 'n': 20},
        {'status': 'pending', 'n': 4},
        {'status': 'approved', 'n': 3},
        {'status': 'completed', 'n': 10},
        {'status': 'cancelled', 'n': 3},
      ]);
      expect([s.total, s.pending, s.approved, s.completed, s.cancelled], [20, 4, 3, 10, 3]);
    });

    test('Market Linking: total equals the screen\'s All chip; alerts count farmers and cancellations', () {
      final s = MarketLinkingSummaryStats.fromRows([
        {'status': 'submitted', 'farmer_id': 'a'},
        {'status': 'buyer_found', 'farmer_id': 'a'}, // same farmer, second open request
        {'status': 'buyer_found', 'farmer_id': 'b', 'cancellation_status': 'requested'},
        {'status': 'completed', 'farmer_id': 'c'},
        {'status': 'cancelled', 'farmer_id': 'd'},
        {'status': 'requested', 'farmer_id': 'e'}, // legacy: not counted
        // a cancellation request on a closed request is not waiting for anyone
        {'status': 'completed', 'farmer_id': 'f', 'cancellation_status': 'requested'},
      ]);
      expect(s.total, 6);
      expect(s.waitingForBuyer, 1);
      expect(s.buyerFound, 2);
      expect(s.active, 3);
      expect(s.activeFarmers, 2); // a and b, a counted once
      expect(s.cancellationRequests, 1);
      expect(MarketLinkingSummaryStats.fromRows(const []).total, 0);
    });

    test('every figure is an exact database count, not a capped download', () {
      final listings = read('lib/data/repositories/admin_listing_repository.dart');
      final orders = read('lib/data/repositories/admin_order_repository.dart');
      for (final src in [listings, orders]) {
        expect(src, contains('.count()'));
      }
      final listingFn = listings.substring(listings.indexOf('Future<ListingSummaryStats> fetchSummaryStats'),
          listings.indexOf('Future<List<String>> fetchActiveCropNames'));
      expect(listingFn, isNot(contains(".select('status')")));
      expect(listingFn, contains(".neq('status', 'withdrawn')"));
      final orderFn = orders.substring(orders.indexOf('Future<OrderSummaryStats> fetchSummaryStats'),
          orders.indexOf('Future<AdminOrderModel?> fetchOrderById'));
      expect(orderFn, isNot(contains(".select('status')")));
      expect(orderFn, contains("['cancelled', 'rejected']"));
      expect(read('lib/data/repositories/buyer_profile_repository.dart'),
          contains(".count().eq('role', 'buyer')"));
    });

    test('Coop Offers counts exactly the offers waiting for the Cooperative', () {
      final repo = read('lib/data/repositories/cooperative_offer_repository.dart');
      final fn = repo.substring(repo.indexOf('Future<int> fetchAwaitingCooperativeCount'));
      expect(fn, contains(".eq('status', 'pending')"));
      expect(fn, contains(".eq('last_proposed_by', 'farmer')"));
      // the same rule as the model's awaitingCooperative
      expect(read('lib/data/models/cooperative_offer_model.dart'),
          contains("bool get awaitingCooperative => isPending && lastProposedBy == 'farmer';"));
    });

    test('the dashboard shows those figures and refreshes when any of their tables change', () {
      final src = read(dashboard);
      for (final t in [
        'marketplace_listings',
        'orders',
        'cooperative_purchase_offers',
        'market_linking_programs',
        'user_roles',
      ]) {
        expect(src, contains("'$t'"), reason: t);
      }
      expect(src, contains('_marketLinkingCount = marketLinkingStats.total;'));
      expect(src, contains('fetchAwaitingCooperativeCount()'));
      expect(src, contains('l10n.marketDashCancellationRequests'));
      // the old, wrong inputs are gone
      expect(src, isNot(contains('marketLinkingStats.enrolledFarmers')));
      expect(src, isNot(contains('marketLinkingStats.submitted')));
    });
  });

  group('Market Linking search', () {
    final r = request({
      'buyer_name': 'Maria Santos',
      'buyer_contact': '0917 555 1234',
      'buyer_email': 'maria@example.com',
      'batch_number': 'BATCH-GING-261001-G0007',
    });

    test('finds a request by farmer, crop, batch, buyer name, contact or email', () {
      for (final q in ['juan', 'dela cruz', 'ginger', 'G0007', 'maria', 'santos', '0917 555', 'maria@example', 'MARIA SANTOS']) {
        expect(r.matchesSearch(q), isTrue, reason: q);
      }
    });

    test('every word must match, and an empty search matches everything', () {
      expect(r.matchesSearch('juan zzz'), isFalse);
      expect(r.matchesSearch('banana'), isFalse);
      expect(r.matchesSearch(''), isTrue);
      expect(r.matchesSearch('   '), isTrue);
    });

    test('a request with no buyer yet is still found by its farmer', () {
      final waiting = request({'status': 'submitted'});
      expect(waiting.matchesSearch('juan'), isTrue);
      expect(waiting.matchesSearch('maria'), isFalse);
    });

    test('layout: Search bar, then Filter chips, then the list; no enrolled-farmers text', () {
      final src = read(manager);
      final searchAt = src.indexOf('controller: _searchCtrl');
      final chipsAt = src.indexOf('MarketplaceFilterBar<_MlFilter>(');
      final listAt = src.indexOf('...visible.map(');
      expect(searchAt, greaterThan(0));
      expect(chipsAt, greaterThan(searchAt));
      expect(listAt, greaterThan(chipsAt));
      expect(src, isNot(contains('mlkEnrolledFarmers')));
      // the list is filtered by the search; the chip counts are totals (see marketplace_filter_counts_test.dart)
      expect(src, contains('.where((e) => e.matchesSearch(_query))'));
      expect(src, contains('.mlkSearchHint'));

    });
  });
}
