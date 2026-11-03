import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/utils/order_status.dart';
import 'package:sagana/data/models/buyer_order_model.dart';
import 'package:sagana/data/repositories/admin_order_repository.dart';

String src(String p) => File(p).readAsStringSync();

Map<String, dynamic> orderRow(String status, {String? method = 'pickup'}) => {
  'id': 'o1',
  'listing_id': 'l1',
  'buyer_id': 'b1',
  'buyer_name': 'Ana',
  'crop_name': 'Palay',
  'quantity_kg': 3,
  'price_per_kg': 10,
  'total_price': 30,
  'status': status,
  'fulfillment_method': method,
  'created_at': DateTime(2026, 10, 1).toIso8601String(),
  'updated_at': DateTime(2026, 10, 2).toIso8601String(),
};

void main() {
  group('the journey of an order', () {
    test('pickup: pending, approved, ready for pickup, completed', () {
      expect(orderJourney('pickup'), ['pending', 'approved', 'ready_for_pickup', 'completed']);
    });

    test('delivery: pending, approved, out for delivery, delivered, completed', () {
      expect(
        orderJourney('delivery'),
        ['pending', 'approved', 'out_for_delivery', 'delivered', 'completed'],
      );
    });

    test('there is no Preparing status anywhere', () {
      expect(kOrderStatuses.any((s) => s.contains('prepar')), isFalse);
      expect(kOrderStatuses.contains('rejected'), isFalse);
      expect(kOrderStatuses.length, 7);
    });
  });

  group('the consumer confirms receipt only at the right moment', () {
    test('pickup: only when Ready for Pickup', () {
      for (final s in kOrderStatuses) {
        expect(canConfirmReceiptFor(s, 'pickup'), s == 'ready_for_pickup', reason: s);
      }
    });

    test('delivery: only when Delivered', () {
      for (final s in kOrderStatuses) {
        expect(canConfirmReceiptFor(s, 'delivery'), s == 'delivered', reason: s);
      }
    });

    test('an order with no recorded method is a pickup order', () {
      expect(canConfirmReceiptFor('ready_for_pickup', null), isTrue);
      expect(canConfirmReceiptFor('delivered', null), isFalse);
    });

    test('the model agrees, for a Buyer or a Farmer consumer alike', () {
      expect(BuyerOrderModel.fromMap(orderRow('ready_for_pickup')).canConfirmReceipt, isTrue);
      expect(BuyerOrderModel.fromMap(orderRow('approved')).canConfirmReceipt, isFalse);
      expect(BuyerOrderModel.fromMap(orderRow('out_for_delivery', method: 'delivery')).canConfirmReceipt, isFalse);
      expect(BuyerOrderModel.fromMap(orderRow('delivered', method: 'delivery')).canConfirmReceipt, isTrue);
      expect(BuyerOrderModel.fromMap(orderRow('completed')).canConfirmReceipt, isFalse);
    });
  });

  group('the Manager / Officer\'s next step', () {
    test('after approval: Ready for Pickup (pickup) or Out for Delivery (delivery)', () {
      expect(nextStaffOrderAction('approved', 'pickup'), StaffOrderAction.readyForPickup);
      expect(nextStaffOrderAction('approved', 'delivery'), StaffOrderAction.outForDelivery);
      expect(nextStaffOrderAction('approved', null), StaffOrderAction.readyForPickup);
    });

    test('Out for Delivery is followed by Mark as Delivered', () {
      expect(nextStaffOrderAction('out_for_delivery', 'delivery'), StaffOrderAction.markDelivered);
    });

    test('nothing else is the Manager\'s to do', () {
      for (final s in ['pending', 'ready_for_pickup', 'delivered', 'completed', 'cancelled']) {
        expect(nextStaffOrderAction(s, 'pickup'), isNull, reason: s);
        expect(nextStaffOrderAction(s, 'delivery'), isNull, reason: s);
      }
    });

    test('the admin model exposes it', () {
      final o = AdminOrderModel.fromMap({...orderRow('approved', method: 'delivery')});
      expect(o.nextAction, StaffOrderAction.outForDelivery);
      expect(AdminOrderModel.fromMap(orderRow('ready_for_pickup')).nextAction, isNull);
    });
  });

  group('fulfillment evidence', () {
    test('the delivery photo and times are read', () {
      final o = BuyerOrderModel.fromMap({
        ...orderRow('delivered', method: 'delivery'),
        'delivery_photo_url': 'https://x.invalid/p.jpg',
        'delivered_at': '2026-10-03T01:02:03Z',
        'out_for_delivery_at': '2026-10-03T00:00:00Z',
        'delivery_evidence_note': 'Left at the gate',
      });
      expect(o.deliveryPhotoUrl, isNotNull);
      expect(o.deliveredAt, isNotNull);
      expect(o.deliveryEvidenceNote, 'Left at the gate');
      expect(o.statusLabel, 'Delivered');
    });
  });

  group('Needs Action (Manager / Officer dashboard)', () {
    test('counts Pending, Approved and Out for Delivery only', () {
      for (final s in kOrderStatuses) {
        expect(
          orderNeedsStaffAction(s),
          const ['pending', 'approved', 'out_for_delivery'].contains(s),
          reason: s,
        );
      }
    });

    test('orders waiting only for the consumer are left out', () {
      expect(orderNeedsStaffAction('ready_for_pickup'), isFalse);
      expect(orderNeedsStaffAction('delivered'), isFalse);
      expect(orderNeedsStaffAction('completed'), isFalse);
      expect(orderNeedsStaffAction('cancelled'), isFalse);
    });

    test('the dashboard total is the sum of those three statuses', () {
      final stats = OrderSummaryStats.fromCountRows([
        {'status': 'total', 'n': 20},
        {'status': 'pending', 'n': 2},
        {'status': 'approved', 'n': 3},
        {'status': 'ready_for_pickup', 'n': 4},
        {'status': 'out_for_delivery', 'n': 1},
        {'status': 'delivered', 'n': 5},
        {'status': 'completed', 'n': 4},
        {'status': 'cancelled', 'n': 1},
      ]);
      expect(stats.needsAction, 6); // 2 + 3 + 1, not the 9 waiting on the consumer
      expect(stats.readyForPickup + stats.delivered, 9);
    });

    test('the dashboard and the order list use it', () {
      final dash = src('lib/presentation/screens/admin/marketplace_dashboard_screen.dart');
      expect(dash, contains('orderStats.needsAction'));
      expect(dash, contains('kOrderNeedsActionFilter'));
      final list = src('lib/presentation/screens/admin/order_management_screen.dart');
      expect(list, contains('kOrderNeedsActionFilter'));
      expect(list, contains('orderNeedsStaffAction'));
      expect(src('lib/presentation/navigation/app_router.dart'), contains("extra?['filter']"));
    });
  });

  group('Officer access and the final rules (source)', () {
    test('approval and the fulfillment steps are for any staff role', () {
      final officer = src('supabase_schema/supabase_schema_officer_order_access.sql');
      expect(officer, contains('public.is_staff()'));
      expect(officer, contains('Unauthorized: only a Manager or Officer can approve orders'));
      final wf = src('supabase_schema/supabase_schema_order_fulfillment_workflow.sql');
      expect(RegExp(r'IF NOT public\.is_staff\(\)').allMatches(wf).length, 3);
    });

    test('there is no reject, no override and no auto-complete anywhere', () {
      for (final f in [
        'supabase_schema/supabase_schema_order_fulfillment_workflow.sql',
        'supabase_schema/supabase_schema_officer_order_access.sql',
      ]) {
        final sql = src(f).toLowerCase();
        expect(sql.contains('reject_order'), isFalse, reason: f);
        expect(sql.contains('pg_cron'), isFalse, reason: f);
        expect(sql.contains('auto-complete') && sql.contains('create trigger') && sql.contains('interval'), isFalse, reason: f);
      }
      final admin = src('lib/data/repositories/admin_order_repository.dart');
      expect(admin.contains('rejectOrder'), isFalse);
      expect(admin.contains('completeOrder'), isFalse);
      expect(admin.contains('cancelOrder'), isFalse);
    });
  });

  group('wiring (source)', () {
    test('the Manager records each step through its own database function', () {
      final repo = src('lib/data/repositories/admin_order_repository.dart');
      expect(repo, contains("'mark_order_ready_for_pickup'"));
      expect(repo, contains("'mark_order_out_for_delivery'"));
      expect(repo, contains("'mark_order_delivered'"));
      // The photo is uploaded before Delivered is recorded.
      final fn = repo.substring(repo.indexOf('Future<void> markDelivered'));
      expect(fn.indexOf('uploadBinary') < fn.indexOf("'mark_order_delivered'"), isTrue);
    });

    test('the Manager screen offers the next step and no automatic change', () {
      final s = src('lib/presentation/screens/admin/admin_order_detail_screen.dart');
      expect(s, contains('order.nextAction'));
      expect(s, contains('_markDelivered'));
      expect(s, isNot(contains('Timer')));
    });

    test('the consumer screen confirms only when allowed', () {
      final s = src('lib/presentation/screens/buyer/order_detail_screen.dart');
      expect(s, contains('order.canConfirmReceipt'));
    });

    test('the migration enforces the workflow in the database', () {
      final sql = src('supabase_schema/supabase_schema_order_fulfillment_workflow.sql');
      for (final needle in [
        "'ready_for_pickup'",
        "'out_for_delivery'",
        "'delivered'",
        'mark_order_ready_for_pickup',
        'mark_order_out_for_delivery',
        'mark_order_delivered',
        'orders_delivered_needs_photo',
        'An order cannot move from',
        'Upload a photo of the delivery first.',
      ]) {
        expect(sql, contains(needle), reason: needle);
      }
      expect(sql.toLowerCase(), isNot(contains("'preparing'")));
      // No Manager rejection comes back, and cancellation stays a consumer action.
      expect(sql, isNot(contains("'rejected'")));
    });

    test('new strings exist in English and Tagalog', () {
      Map<String, dynamic> arb(String p) => jsonDecode(src(p)) as Map<String, dynamic>;
      final en = arb('lib/core/l10n/app_en.arb');
      final tl = arb('lib/core/l10n/app_tl.arb');
      for (final k in [
        'orderStatusReadyForPickup',
        'orderStatusOutForDelivery',
        'orderStatusDelivered',
        'orderActionReadyForPickup',
        'orderActionOutForDelivery',
        'orderActionMarkDelivered',
        'buyerOrderMsgReady',
        'buyerOrderMsgDelivered',
        'ordersEmptyStatus',
      ]) {
        expect(en.containsKey(k), isTrue, reason: 'en $k');
        expect(tl.containsKey(k), isTrue, reason: 'tl $k');
      }
      expect(en['buyerOrderReceivedAction'], 'Confirm Receipt');
    });
  });
}
