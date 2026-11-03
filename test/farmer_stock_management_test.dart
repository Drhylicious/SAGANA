import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/data/models/admin_reports_model.dart';
import 'package:sagana/data/models/cooperative_offer_model.dart';
import 'package:sagana/data/models/inventory_batch_model.dart';
import 'package:sagana/data/models/stock_movement_model.dart';

String src(String p) => File(p).readAsStringSync();

Map<String, dynamic> offerRow(String status) => {
  'id': 'o1',
  'farmer_id': 'f1',
  'crop_name': 'Palay',
  'offered_quantity_kg': 10,
  'offered_at': DateTime(2026, 10, 1).toIso8601String(),
  'status': status,
  'delivery_photo_url': status == 'approved' ? null : 'https://x.invalid/p.jpg',
  'delivered_at': DateTime(2026, 10, 3).toIso8601String(),
  'received_at': status == 'completed'
      ? DateTime(2026, 10, 4).toIso8601String()
      : null,
};

void main() {
  group('batch figures', () {
    test('committed stock excludes what the Farmer adjusted away', () {
      expect(
        committedBatchKg(quantityKg: 20, availableKg: 5, soldKg: 9, adjustedKg: 1),
        5,
      );
      // Rows read without the adjusted column behave as before.
      expect(committedBatchKg(quantityKg: 20, availableKg: 5, soldKg: 9), 6);
    });

    test('the batch model reads reserved and adjusted', () {
      final b = InventoryBatchModel.fromMap({
        'id': 'b',
        'farmer_id': 'f',
        'harvest_record_id': 'h',
        'crop_id': 'c',
        'crop_name': 'Palay',
        'batch_number': 'BATCH-P-261029-0001',
        'quantity_kg': 20,
        'available_kg': 5,
        'reserved_kg': 5,
        'sold_kg': 9,
        'adjusted_kg': 1,
        'created_at': DateTime(2026, 10, 1).toIso8601String(),
      });
      expect(b.availableKg + b.reservedKg + b.soldKg + b.adjustedKg, b.quantityKg);
      expect(b.withPhoto('u').adjustedKg, 1);
    });
  });

  group('offer hand-over states', () {
    test('approved waits for the Farmer to deliver', () {
      final o = CooperativeOfferModel.fromMap({...offerRow('approved'), 'farmer_name': 'J'});
      expect(o.awaitingDelivery, isTrue);
      expect(o.awaitingReceipt, isFalse);
      expect(o.isAgreed, isTrue);
      expect(o.settledAmount, isNull);
    });

    test('delivered waits for the Manager / Officer to confirm receipt', () {
      final o = CooperativeOfferModel.fromMap({...offerRow('delivered'), 'farmer_name': 'J'});
      expect(o.awaitingReceipt, isTrue);
      expect(o.awaitingDelivery, isFalse);
      expect(o.deliveryPhotoUrl, isNotNull);
    });

    test('only a completed offer is settled', () {
      final o = CooperativeOfferModel.fromMap({
        ...offerRow('completed'),
        'farmer_name': 'J',
        'confirmed_amount': 500,
      });
      expect(o.isCompleted, isTrue);
      expect(o.settledAmount, 500);
      expect(o.receivedAt, isNotNull);
    });
  });

  group('stock movement model', () {
    test('parses a ledger row', () {
      final m = StockMovementModel.fromMap({
        'id': 'm',
        'batch_id': 'b',
        'movement_type': 'sold',
        'channel': 'marketplace',
        'reference_type': 'order',
        'reference_id': 'r',
        'quantity': 3,
        'unit': 'kg',
        'available_after': 12,
        'reserved_after': 5,
        'sold_after': 3,
        'adjusted_after': 0,
        'created_at': '2026-10-29T01:02:03Z',
      });
      expect(m.movementType, 'sold');
      expect(m.channel, 'marketplace');
      expect(m.quantity, 3);
      expect(m.availableAfter + m.reservedAfter + m.soldAfter, 20);
    });
  });

  group('wiring (source)', () {
    test('the consumer confirms receipt; the Manager has no complete call', () {
      final buyer = src('lib/data/repositories/buyer_order_repository.dart');
      expect(buyer, contains("'confirm_order_received'"));
      final admin = src('lib/data/repositories/admin_order_repository.dart');
      expect(admin, isNot(contains("'complete_order'")));
      final detail = src('lib/presentation/screens/buyer/order_detail_screen.dart');
      expect(detail, contains('_confirmReceived'));
      expect(detail, contains('order.canConfirmReceipt'));
    });

    test('offers use deliver and confirm-receipt functions', () {
      final repo = src('lib/data/repositories/cooperative_offer_repository.dart');
      expect(repo, contains("'deliver_cooperative_offer'"));
      expect(repo, contains("'confirm_cooperative_offer_receipt'"));
      // Active offers include the hand-over states, not just pending.
      expect(repo, contains("['pending', 'approved', 'delivered']"));
    });

    test('inventory summary reads the stored reserved figure', () {
      final repo = src('lib/data/repositories/inventory_repository.dart');
      expect(repo, contains("reserved_kg"));
      expect(repo, isNot(contains('quantity - avail - soldKg')));
    });

    test('the migration enforces the stock rules in the database', () {
      final sql = src('supabase_schema/supabase_schema_farmer_stock_management.sql');
      for (final needle in [
        'CREATE TABLE IF NOT EXISTS public.stock_movements',
        '_inventory_batch_stock_guard',
        'confirm_order_received',
        '_orders_require_receipt',
        'deliver_cooperative_offer',
        'confirm_cooperative_offer_receipt',
        '_coop_offer_status_flow',
        'uq_inventory_tx_offer_receipt',
        "c.status = 'completed'",
      ]) {
        expect(sql, contains(needle), reason: needle);
      }
      // An accepted offer must not settle or sell any more.
      final accept = sql.substring(sql.indexOf('FUNCTION public.accept_cooperative_offer'));
      final acceptBody = accept.substring(0, accept.indexOf('REVOKE ALL'));
      expect(acceptBody, isNot(contains('INSERT INTO member_sales_transactions')));
    });

    test('new strings exist in English and Tagalog', () {
      Map<String, dynamic> arb(String p) =>
          jsonDecode(src(p)) as Map<String, dynamic>;
      final en = arb('lib/core/l10n/app_en.arb');
      final tl = arb('lib/core/l10n/app_tl.arb');
      for (final k in [
        'coopStatusApproved',
        'coopStatusDelivered',
        'coopStatusCompleted',
        'coopActionDeliver',
        'coopActionConfirmReceipt',
        'buyerOrderReceivedAction',
        'stockHistoryTitle',
        'stockMovSold',
        'adminLogCoopOfferReceived',
      ]) {
        expect(en.containsKey(k), isTrue, reason: 'en $k');
        expect(tl.containsKey(k), isTrue, reason: 'tl $k');
      }
    });
  });
}
