import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/utils/order_status.dart';
import 'package:sagana/data/models/buyer_order_model.dart';
import 'package:sagana/data/repositories/admin_order_repository.dart';
import 'package:sagana/data/services/table_change_watcher.dart';
import 'package:sagana/presentation/widgets/listing_status_badge.dart';
import 'package:sagana/presentation/widgets/order_status_style.dart';

String src(String path) => File(path).readAsStringSync();

Map<String, dynamic> orderRow(String status) => {
      'id': 'o1',
      'order_number': 'ORD-20261027-A001',
      'listing_id': 'l1',
      'buyer_id': 'b1',
      'crop_name': 'Tomato',
      'quantity_kg': 5,
      'price_per_kg': 40,
      'total_price': 200,
      'status': status,
      'notes': 'Out of stock',
      'created_at': '2026-10-27T01:00:00Z',
      'updated_at': '2026-10-27T02:00:00Z',
    };

void main() {
  group('no Disapproved order: a stored "rejected" is read as cancelled', () {
    test('canonicalOrderStatus', () {
      expect(canonicalOrderStatus('rejected'), 'cancelled');
      expect(canonicalOrderStatus('cancelled'), 'cancelled');
      expect(canonicalOrderStatus('pending'), 'pending');
      expect(canonicalOrderStatus('approved'), 'approved');
      expect(canonicalOrderStatus('completed'), 'completed');
      expect(canonicalOrderStatus(null), 'pending');
      expect(canonicalOrderStatus(''), 'pending');
    });

    test('Buyer / Farmer order model', () {
      final old = BuyerOrderModel.fromMap(orderRow('rejected'));
      expect(old.status, 'cancelled');
      expect(old.isCancelled, isTrue);
      expect(old.statusLabel, 'Cancelled');
      expect(old.notes, 'Out of stock', reason: 'the reason is kept');
      for (final s in ['pending', 'approved', 'completed', 'cancelled']) {
        expect(BuyerOrderModel.fromMap(orderRow(s)).status, s);
      }
    });

    test('Manager order model', () {
      final old = AdminOrderModel.fromMap(orderRow('rejected'));
      expect(old.status, 'cancelled');
      expect(old.statusLabel, 'Cancelled');
      expect(AdminOrderModel.fromMap(orderRow('approved')).statusLabel, 'Approved');
    });

    test('a legacy status never gets its own colour or wording', () {
      expect(orderStatusColor('rejected'), orderStatusColor('cancelled'));
    });
  });

  group('no Disapprove action or chip is left in the order screens', () {
    final screens = {
      'Manager Order Management': 'lib/presentation/screens/admin/order_management_screen.dart',
      'Manager Order Detail': 'lib/presentation/screens/admin/admin_order_detail_screen.dart',
      'Buyer My Orders': 'lib/presentation/screens/buyer/my_orders_screen.dart',
      'Buyer Order Detail': 'lib/presentation/screens/buyer/order_detail_screen.dart',
      'Farmer Orders': 'lib/presentation/screens/farmer/farmer_orders_screen.dart',
    };
    for (final e in screens.entries) {
      test(e.key, () {
        final s = src(e.value);
        expect(s.contains("'rejected'"), isFalse, reason: 'no rejected chip/branch');
        expect(s.contains('isRejected'), isFalse);
        expect(s.contains('Disapprov'), isFalse);
        expect(s.contains('Rejected'), isFalse);
      });
    }

    test('the Manager has no cancel / disapprove call', () {
      final repo = src('lib/data/repositories/admin_order_repository.dart');
      expect(repo.contains("rpc('cancel_order'"), isFalse);
      expect(repo.contains('Future<void> cancelOrder'), isFalse);
      final detail = src('lib/presentation/screens/admin/admin_order_detail_screen.dart');
      expect(detail.contains('_confirmCancel'), isFalse);
      expect(detail.contains('cancelOrder'), isFalse);
      expect(detail.contains('_confirmApprove'), isTrue, reason: 'Approve stays');
      expect(detail.contains('_confirmComplete'), isFalse, reason: 'the consumer completes an order, not the Manager');
      expect(repo.contains('completeOrder'), isFalse);
      final buyerRepo = src('lib/data/repositories/buyer_order_repository.dart');
      expect(buyerRepo.contains("'confirm_order_received'"), isTrue);
    });

    test('Buyer and Farmer can still cancel their own order', () {
      final repo = src('lib/data/repositories/buyer_order_repository.dart');
      expect(repo.contains("'cancel_my_order'"), isTrue);
    });

    test('the order screens list the real statuses and never Disapproved', () {
      final status = src('lib/core/utils/order_status.dart');
      expect(status.contains("'pending', 'approved', 'ready_for_pickup', 'out_for_delivery'") || status.contains("'ready_for_pickup'"), isTrue);
      expect(status.contains("const List<String> kOrderStatuses"), isTrue);
      final list = status.substring(status.indexOf("const List<String> kOrderStatuses"), status.indexOf("];", status.indexOf("const List<String> kOrderStatuses")));
      expect(list.contains('rejected'), isFalse);
      for (final f in [
        'lib/presentation/screens/buyer/my_orders_screen.dart',
        'lib/presentation/screens/farmer/farmer_orders_screen.dart',
        'lib/presentation/screens/admin/order_management_screen.dart',
      ]) {
        expect(src(f).contains('kOrderStatuses'), isTrue, reason: f);
      }
    });

    test('the cleanup SQL deletes nothing and is run by hand', () {
      final sql = src('supabase_schema/supabase_schema_remove_order_rejection.sql');
      expect(RegExp(r'^\s*(DELETE\s+FROM|TRUNCATE)\b', multiLine: true, caseSensitive: false).hasMatch(sql), isFalse);
      expect(sql.contains('orders_rejection_backup'), isTrue);
      expect(sql.contains("SET status = 'cancelled'"), isTrue);
    });
  });

  group('quantity left shown on listing cards', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    test('a 5 kg order from 20 kg reads 15 of 20 kg left', () {
      expect(
        listingQuantityLabel(l10n, status: 'approved', remainingKg: 15, volumeKg: 20, unit: 'kg'),
        '15 of 20 kg left',
      );
    });

    test('sold out reads 0 left, not the listed volume', () {
      expect(
        listingQuantityLabel(l10n, status: 'approved', remainingKg: 0, volumeKg: 20, unit: 'kg'),
        '0 of 20 kg left',
      );
    });

    test('a listing with no balance yet shows what was listed', () {
      expect(
        listingQuantityLabel(l10n, status: 'pending_review', remainingKg: 20, volumeKg: 20, unit: 'kg'),
        '20 kg',
      );
      expect(
        listingQuantityLabel(l10n, status: 'rejected', remainingKg: 0, volumeKg: 20, unit: 'kg'),
        '20 kg',
      );
    });

    test('every listing card uses it, none prints the listed volume for a live listing', () {
      for (final f in [
        'lib/presentation/screens/admin/all_listings_screen.dart',
        'lib/presentation/screens/admin/pending_approvals_screen.dart',
        'lib/presentation/screens/farmer/my_listings_screen.dart',
      ]) {
        expect(src(f).contains('listingQuantityLabel('), isTrue, reason: f);
      }
    });
  });

  group('live stock updates', () {
    test('a burst of changes causes one reload', () async {
      var calls = 0;
      final w = TableChangeWatcher(
        tables: const ['orders'],
        debounce: const Duration(milliseconds: 30),
        onChange: () => calls++,
      );
      for (var i = 0; i < 5; i++) {
        w.notifyChanged();
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(calls, 1);
      w.notifyChanged();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(calls, 2);
      w.dispose();
    });

    test('nothing fires after dispose', () async {
      var calls = 0;
      final w = TableChangeWatcher(
        tables: const ['orders'],
        debounce: const Duration(milliseconds: 30),
        onChange: () => calls++,
      );
      w.notifyChanged();
      w.dispose();
      w.notifyChanged();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, 0);
    });

    test('starting without Supabase does not throw (offline / tests)', () {
      final w = TableChangeWatcher(tables: const ['orders'], onChange: () {});
      expect(w.start, returnsNormally);
      w.dispose();
    });

    test('stock screens of every role watch the database', () {
      const watchers = {
        'lib/presentation/screens/admin/all_listings_screen.dart': 'marketplace_listings',
        'lib/presentation/screens/admin/pending_approvals_screen.dart': 'marketplace_listings',
        'lib/presentation/screens/admin/order_management_screen.dart': "'orders'",
        'lib/presentation/screens/admin/marketplace_dashboard_screen.dart': 'marketplace_listings',
        'lib/presentation/screens/farmer/my_listings_screen.dart': 'marketplace_listings',
        'lib/presentation/screens/farmer/farmer_orders_screen.dart': "'orders'",
        'lib/presentation/screens/buyer/marketplace_browse_screen.dart': 'marketplace_listings',
        'lib/presentation/screens/buyer/listing_details_screen.dart': 'marketplace_listings',
        'lib/presentation/screens/buyer/my_orders_screen.dart': "'orders'",
      };
      for (final e in watchers.entries) {
        final s = src(e.key);
        expect(s.contains('TableChangeWatcher('), isTrue, reason: e.key);
        expect(s.contains(e.value), isTrue, reason: e.key);
        expect(s.contains('.dispose()'), isTrue, reason: '${e.key} must stop watching');
      }
    });

    test('a quiet reload does not flash the loading spinner', () {
      for (final f in [
        'lib/presentation/screens/farmer/my_listings_screen.dart',
        'lib/presentation/screens/farmer/farmer_orders_screen.dart',
        'lib/presentation/screens/buyer/my_orders_screen.dart',
        'lib/presentation/screens/buyer/marketplace_browse_screen.dart',
        'lib/presentation/screens/buyer/listing_details_screen.dart',
        'lib/presentation/screens/admin/marketplace_dashboard_screen.dart',
      ]) {
        expect(src(f).contains('if (!silent) setState(() => _isLoading = true)'), isTrue, reason: f);
      }
    });
  });

  group('no double order from a double tap', () {
    test('Place Order ignores a second tap while the first is running', () {
      final s = src('lib/presentation/screens/buyer/checkout_screen.dart');
      final start = s.indexOf('Future<void> _placeOrder()');
      expect(start, greaterThan(0));
      final body = s.substring(start, start + 400);
      expect(body.contains('if (_isSubmitting) return;'), isTrue);
    });
  });

  group('the server rules the app relies on', () {
    test('only place_order / cancel_my_order move remaining_kg in the current scripts', () {
      final sql = src('supabase_schema/supabase_schema_stock_integrity_test.sql');
      expect(sql.contains('place_order(v_listing, 5)'), isTrue);
      expect(sql.contains('confirm_order_received'), isTrue);
      expect(sql.contains('RAISE EXCEPTION E\'STOCK TEST REPORT (nothing was saved)'), isTrue);
    });
  });
}
