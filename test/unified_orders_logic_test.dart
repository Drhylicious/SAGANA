import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/utils/order_reference.dart';
import 'package:sagana/core/utils/order_status.dart';
import 'package:sagana/data/models/buyer_order_model.dart';
import 'package:sagana/data/models/cart_item_model.dart';
import 'package:sagana/data/models/consumer_order_row.dart';
import 'package:sagana/data/models/cooperative_delivery_model.dart';
import 'package:sagana/data/models/cooperative_product_model.dart';
import 'package:sagana/data/models/program_model.dart';
import 'package:sagana/data/models/staff_order_row.dart';
import 'package:sagana/data/repositories/admin_order_repository.dart';

/// The rules of the unified Marketplace / Cooperative orders that need no screen:
/// statuses, who confirms what and when, the one staff list, the cart line, the Cooperative
/// Product price and the delivery fee bands.

Map<String, dynamic> _coopOrder({
  String id = 'c1',
  String status = 'pending',
  String method = 'pickup',
  String payment = 'unpaid',
  double qty = 2,
  double unit = 45,
  String requested = '2026-11-06T10:00:00Z',
  String farmer = 'Maria Santos',
}) => {
  'id': id,
  'program_id': 'p1',
  'program_name': 'Peanut Cookies Sale',
  'product_id': 'pp1',
  'item_name': 'Peanut Cookies',
  'unit': 'pack',
  'farmer_id': 'f1',
  'farmer_name': farmer,
  'quantity': qty,
  'unit_price': unit,
  'total_amount': qty * unit,
  'status': status,
  'requested_at': requested,
  'order_number': 'PSO-20261106-A001',
  'fulfillment_method': method,
  'payment_status': payment,
};

AdminOrderModel _marketOrder({
  String id = 'm1',
  String status = 'pending',
  String? method = 'pickup',
  String payment = 'unpaid',
  String created = '2026-11-05T10:00:00Z',
}) => AdminOrderModel.fromMap({
  'id': id,
  'listing_id': 'l1',
  'buyer_id': 'b1',
  'buyer_name': 'Juan Dela Cruz',
  'crop_name': 'Tomato',
  'quantity_kg': 10,
  'price_per_kg': 30,
  'unit': 'kg',
  'total_price': 300,
  'status': status,
  'created_at': created,
  'updated_at': created,
  'fulfillment_method': method,
  'payment_status': payment,
});

void main() {
  group('statuses staff work with', () {
    test('six operational statuses: delivered is not one of them', () {
      expect(kStaffOrderStatuses, [
        'pending',
        'approved',
        'ready_for_pickup',
        'out_for_delivery',
        'completed',
        'cancelled',
      ]);
      expect(kStaffOrderStatuses.contains('delivered'), isFalse);
    });

    test(
      'a handed-over delivery is filed under Out for Delivery and says it awaits confirmation',
      () {
        expect(orderDisplayStatus('delivered'), 'out_for_delivery');
        for (final s in kStaffOrderStatuses) {
          expect(orderDisplayStatus(s), s);
        }
        expect(isHandedOverAwaitingConfirmation('delivered'), isTrue);
        expect(isHandedOverAwaitingConfirmation('out_for_delivery'), isFalse);
      },
    );

    test(
      'the Marketplace stored statuses are unchanged (Buyer lists keep their seven)',
      () {
        expect(kOrderStatuses.length, 7);
        expect(kOrderStatuses.contains('delivered'), isTrue);
      },
    );
  });

  group('payment gates the consumer\'s confirmation', () {
    test('Confirm Receipt needs the status AND the recorded cash', () {
      expect(
        canConfirmReceiptFor('ready_for_pickup', 'pickup'),
        isTrue,
      ); // default keeps the old callers working
      expect(
        canConfirmReceiptFor(
          'ready_for_pickup',
          'pickup',
          paymentRecorded: false,
        ),
        isFalse,
      );
      expect(
        canConfirmReceiptFor('delivered', 'delivery', paymentRecorded: true),
        isTrue,
      );
      expect(
        canConfirmReceiptFor('delivered', 'delivery', paymentRecorded: false),
        isFalse,
      );
      expect(
        canConfirmReceiptFor(
          'out_for_delivery',
          'delivery',
          paymentRecorded: true,
        ),
        isFalse,
      );
      expect(
        canConfirmReceiptFor('approved', 'pickup', paymentRecorded: true),
        isFalse,
      );
    });

    test(
      'a Buyer\'s order says it is waiting for payment, and stops saying it once paid',
      () {
        BuyerOrderModel o(String payment) => BuyerOrderModel.fromMap({
          'id': 'x',
          'listing_id': 'l',
          'quantity_kg': 1,
          'price_per_kg': 10,
          'total_price': 10,
          'status': 'ready_for_pickup',
          'created_at': '2026-11-05T10:00:00Z',
          'updated_at': '2026-11-05T10:00:00Z',
          'fulfillment_method': 'pickup',
          'payment_status': payment,
        });
        expect(o('unpaid').isWaitingForPayment, isTrue);
        expect(o('unpaid').canConfirmReceipt, isFalse);
        expect(o('paid').isWaitingForPayment, isFalse);
        expect(o('paid').canConfirmReceipt, isTrue);
        // An order from before the column existed reads as unpaid: it waits for the cooperative.
        expect(
          BuyerOrderModel.fromMap({
            'id': 'x',
            'listing_id': 'l',
            'quantity_kg': 1,
            'price_per_kg': 10,
            'total_price': 10,
            'status': 'ready_for_pickup',
            'created_at': '2026-11-05T10:00:00Z',
            'updated_at': '2026-11-05T10:00:00Z',
          }).isPaymentRecorded,
          isFalse,
        );
      },
    );

    test(
      'staff steps follow the cash: record it, then (only if the customer cannot confirm) complete for them',
      () {
        expect(
          nextStaffOrderAction('ready_for_pickup', 'pickup'),
          StaffOrderAction.recordPayment,
        );
        expect(
          nextStaffOrderAction(
            'ready_for_pickup',
            'pickup',
            paymentStatus: 'paid',
          ),
          StaffOrderAction.completeForCustomer,
        );
        expect(
          nextStaffOrderAction('out_for_delivery', 'delivery'),
          StaffOrderAction.recordHandover,
        );
        expect(
          nextStaffOrderAction('delivered', 'delivery'),
          StaffOrderAction.recordPayment,
        ); // an older delivery
        expect(
          nextStaffOrderAction('completed', 'pickup', paymentStatus: 'paid'),
          isNull,
        );
      },
    );
  });

  group('one staff list over both engines', () {
    final rows = mergeStaffOrders(
      [
        _marketOrder(
          id: 'm1',
          status: 'pending',
          created: '2026-11-05T09:00:00Z',
        ),
        _marketOrder(
          id: 'm2',
          status: 'delivered',
          method: 'delivery',
          payment: 'paid',
          created: '2026-11-03T09:00:00Z',
        ),
        _marketOrder(
          id: 'm3',
          status: 'completed',
          payment: 'paid',
          created: '2026-11-01T09:00:00Z',
        ),
      ],
      [
        ProgramPurchase.fromMap(
          _coopOrder(
            id: 'c1',
            status: 'ready_for_pickup',
            requested: '2026-11-06T10:00:00Z',
          ),
        ),
        ProgramPurchase.fromMap(
          _coopOrder(
            id: 'c2',
            status: 'out_for_delivery',
            method: 'delivery',
            requested: '2026-11-04T10:00:00Z',
          ),
        ),
        ProgramPurchase.fromMap(
          _coopOrder(
            id: 'c3',
            status: 'cancelled',
            requested: '2026-11-02T10:00:00Z',
          ),
        ),
      ],
    );

    test('merged newest first, each row knows its source and reference', () {
      expect(rows.map((r) => r.id), ['c1', 'm1', 'c2', 'm2', 'c3', 'm3']);
      expect(rows.first.isCooperative, isTrue);
      expect(rows.first.reference, 'PSO-20261106-A001');
      expect(rows[1].source, kOrderSourceMarketplace);
      expect(rows[1].customerName, 'Juan Dela Cruz');
    });

    test('filter by source', () {
      expect(
        filterStaffOrders(
          rows,
          source: kOrderSourceCooperative,
        ).map((r) => r.id),
        ['c1', 'c2', 'c3'],
      );
      expect(
        filterStaffOrders(
          rows,
          source: kOrderSourceMarketplace,
        ).map((r) => r.id),
        ['m1', 'm2', 'm3'],
      );
    });

    test(
      'a delivered order is under Out for Delivery, never a status of its own',
      () {
        expect(
          filterStaffOrders(rows, status: 'out_for_delivery').map((r) => r.id),
          ['c2', 'm2'],
        );
        expect(filterStaffOrders(rows, status: 'delivered'), isEmpty);
        final delivered = rows.firstWhere((r) => r.id == 'm2');
        expect(delivered.awaitingConfirmation, isTrue);
        expect(delivered.displayStatus, 'out_for_delivery');
      },
    );

    test(
      'Needs Action: pending, approved, out for delivery, and anything handed over whose cash is not recorded',
      () {
        // m1 pending, c1 ready-for-pickup unpaid, c2 out for delivery. m2 is paid and waits for the customer.
        expect(
          filterStaffOrders(
            rows,
            status: kOrderNeedsActionFilter,
          ).map((r) => r.id),
          // A work queue: oldest first, so what has waited longest is handled first.
          ['c2', 'm1', 'c1'],
        );
      },
    );

    test('search covers customer, item, reference and program', () {
      expect(filterStaffOrders(rows, query: 'maria').length, 3);
      expect(filterStaffOrders(rows, query: 'pso-20261106').map((r) => r.id), [
        'c1',
        'c2',
        'c3',
      ]);
      expect(filterStaffOrders(rows, query: 'tomato').length, 3);
      expect(filterStaffOrders(rows, query: 'peanut cookies sale').length, 3);
    });

    test('the source filter and the status filter combine', () {
      expect(
        filterStaffOrders(
          rows,
          source: kOrderSourceCooperative,
          status: 'cancelled',
        ).map((r) => r.id),
        ['c3'],
      );
    });
  });

  group('a Farmer\'s My Orders lists both kinds', () {
    test(
      'merged newest first; the Cooperative one is labelled and its cash gates confirmation',
      () {
        final list = mergeConsumerOrders(
          [
            BuyerOrderModel.fromMap({
              'id': 'm1',
              'listing_id': 'l1',
              'quantity_kg': 5,
              'price_per_kg': 20,
              'total_price': 100,
              'status': 'completed',
              'created_at': '2026-11-01T10:00:00Z',
              'updated_at': '2026-11-02T10:00:00Z',
              'fulfillment_method': 'pickup',
              'payment_status': 'paid',
            }),
          ],
          [
            ProgramPurchase.fromMap(
              _coopOrder(status: 'delivered', method: 'delivery'),
            ),
          ],
        );
        expect(list.map((r) => r.id), ['c1', 'm1']);
        expect(list.first.isCooperative, isTrue);
        expect(list.first.isWaitingForPayment, isTrue);
        expect(list.first.canConfirmReceipt, isFalse);
        expect(
          list.last.listingId,
          'l1',
        ); // "Order again" works for a Marketplace order
        final paid = ConsumerOrderRow.fromCooperative(
          ProgramPurchase.fromMap(
            _coopOrder(
              status: 'delivered',
              method: 'delivery',
              payment: 'paid',
            ),
          ),
        );
        expect(paid.canConfirmReceipt, isTrue);
      },
    );
  });

  group('order references', () {
    test(
      'a Cooperative order id travels with its prefix so each screen reads the right table',
      () {
        final token = programOrderToken('abc-123');
        expect(isProgramOrderToken(token), isTrue);
        expect(programOrderIdOf(token), 'abc-123');
        expect(isProgramOrderToken('abc-123'), isFalse);
      },
    );

    test(
      'the Cooperative order shows its PSO number, or a short id when it has none',
      () {
        expect(
          ProgramPurchase.fromMap(_coopOrder()).reference,
          'PSO-20261106-A001',
        );
        final noNumber = Map<String, dynamic>.from(
          _coopOrder(id: 'abcdef12-0000'),
        )..remove('order_number');
        expect(ProgramPurchase.fromMap(noNumber).reference, 'PSO-ABCDEF12');
      },
    );
  });

  group('the cart line', () {
    test(
      'a line saved before Cooperative Products is a Marketplace line, and keeps one request id',
      () {
        final legacy = {
          'listing_id': 'l1',
          'crop_name': 'Tomato',
          'price_per_kg': 30,
          'available_kg_snapshot': 10,
          'quantity_kg': 2,
        };
        final line = CartItemModel.fromMap(legacy);
        expect(line.source, kCartSourceMarketplace);
        expect(line.isCooperative, isFalse);
        expect(line.requestId, isNotEmpty);
        // The id is written back with the line, so loading it again gives the SAME id.
        expect(CartItemModel.fromMap(line.toMap()).requestId, line.requestId);
      },
    );

    test('a Cooperative line round-trips with its program and request id', () {
      final line = CartItemModel(
        listingId: 'product-1',
        cropName: 'Peanut Cookies',
        pricePerKg: 45,
        unit: 'pack',
        availableKgSnapshot: 20,
        quantityKg: 3,
        source: kCartSourceCooperative,
        programId: 'prog-1',
        programName: 'Peanut Cookies Sale',
        regularPrice: 50,
      );
      final back = CartItemModel.fromMap(line.toMap());
      expect(back.isCooperative, isTrue);
      expect(back.programId, 'prog-1');
      expect(back.regularPrice, 50);
      expect(back.requestId, line.requestId);
      expect(back.subtotal, 135);
    });

    test('every new line gets its own request id', () {
      CartItemModel mk() => CartItemModel(
        listingId: 'l',
        cropName: 'x',
        pricePerKg: 1,
        availableKgSnapshot: 1,
        quantityKg: 1,
      );
      expect(mk().requestId == mk().requestId, isFalse);
    });
  });

  group('Cooperative Product price and availability', () {
    Map<String, dynamic> row({
      bool on = true,
      String status = 'active',
      String purpose = 'sales',
      num allocated = 10,
      num reserved = 4,
      num discount = 10,
    }) => {
      'id': 'pp1',
      'program_id': 'p1',
      'unit_price': 50,
      'is_available': on,
      'stock_allocated': allocated,
      'stock_reserved': reserved,
      'cooperative_inventory': {
        'item_name': 'Peanut Cookies',
        'category': 'Harvest Stock',
        'unit': 'pack',
        'image_url': null,
      },
      'cooperative_programs': {
        'program_name': 'Peanut Cookies Sale',
        'member_discount_percent': discount,
        'status': status,
        'program_purpose': purpose,
      },
    };

    test(
      'an enrolled member pays the member price; anyone else pays the regular price',
      () {
        final member = CooperativeProduct.fromRow(row(), isMember: true)!;
        final other = CooperativeProduct.fromRow(row(), isMember: false)!;
        expect(member.memberPriceApplies, isTrue);
        expect(member.payPrice, 45);
        expect(member.memberPrice, 45);
        expect(other.memberPriceApplies, isFalse);
        expect(other.payPrice, 50);
        expect(other.hasMemberDiscount, isTrue); // still told what members pay
      },
    );

    test('no discount in the program: everyone pays the regular price', () {
      final p = CooperativeProduct.fromRow(row(discount: 0), isMember: true)!;
      expect(p.memberPriceApplies, isFalse);
      expect(p.payPrice, 50);
    });

    test(
      'what can be ordered is the allocation minus what open orders reserved',
      () {
        expect(
          CooperativeProduct.fromRow(row(), isMember: false)!.availableToSell,
          6,
        );
        expect(
          CooperativeProduct.fromRow(
            row(allocated: 4, reserved: 4),
            isMember: false,
          )!.isOutOfStock,
          isTrue,
        );
        expect(
          CooperativeProduct.fromRow(
            row(allocated: 0, reserved: 0),
            isMember: false,
          )!.isOutOfStock,
          isTrue,
        );
      },
    );

    test(
      'a switched-off product, or one of a completed or non-sales program, is not offered',
      () {
        expect(
          CooperativeProduct.fromRow(row(on: false), isMember: false),
          isNull,
        );
        expect(
          CooperativeProduct.fromRow(row(status: 'completed'), isMember: false),
          isNull,
        );
        expect(
          CooperativeProduct.fromRow(
            row(purpose: 'distribution'),
            isMember: false,
          ),
          isNull,
        );
      },
    );

    test('a saved cart line is checked against the live product', () {
      expect(evaluateCooperativeCartLine(row()), CooperativeCartIssue.none);
      expect(
        evaluateCooperativeCartLine(null),
        CooperativeCartIssue.unavailable,
      );
      expect(
        evaluateCooperativeCartLine(row(on: false)),
        CooperativeCartIssue.unavailable,
      );
      expect(
        evaluateCooperativeCartLine(row(allocated: 4, reserved: 4)),
        CooperativeCartIssue.soldOut,
      );
    });

    test('the program stock figure follows the allocation, not the shelf', () {
      final p = ProgramProduct.fromMap({
        'id': 'a',
        'program_id': 'p',
        'inventory_item_id': 'i',
        'unit_price': 50,
        'is_available': true,
        'item_name': 'x',
        'unit': 'pack',
        'quantity_on_hand': 90,
        'stock_allocated': 30,
        'stock_reserved': 5,
      });
      expect(p.availableToSell, 25);
      expect(p.isOutOfStock, isFalse);
      expect(
        ProgramProduct.fromMap({
          'id': 'a',
          'program_id': 'p',
          'inventory_item_id': 'i',
          'unit_price': 50,
          'is_available': true,
          'quantity_on_hand': 90,
          'stock_allocated': 5,
          'stock_reserved': 5,
        }).isOutOfStock,
        isTrue,
      );
    });
  });

  group('delivery fee bands (no invented rates)', () {
    DeliveryFeeBand b(double from, double to, double fee) =>
        DeliveryFeeBand(minKm: from, maxKm: to, fee: fee);

    test('valid: starts at 0 and each band starts where the last one ends', () {
      expect(checkFeeBands([b(0, 1, 20), b(1, 3, 35), b(3, 5, 60)]), isNull);
      expect(
        checkFeeBands([b(1, 3, 35), b(0, 1, 20)]),
        isNull,
      ); // order typed does not matter
      expect(
        checkFeeBands([b(0, 2, 0)]),
        isNull,
      ); // a free band is a real choice the Manager may make
    });

    test('nothing is valid by default: an empty set is refused', () {
      expect(checkFeeBands(const []), BandsProblem.empty);
    });

    test('refuses a missing start, a gap, an overlap and a bad row', () {
      expect(checkFeeBands([b(1, 2, 10)]), BandsProblem.notFromZero);
      expect(
        checkFeeBands([b(0, 1, 10), b(2, 3, 10)]),
        BandsProblem.gapOrOverlap,
      );
      expect(
        checkFeeBands([b(0, 2, 10), b(1, 3, 10)]),
        BandsProblem.gapOrOverlap,
      );
      expect(checkFeeBands([b(0, 0, 10)]), BandsProblem.badRow);
      expect(checkFeeBands([b(0, 2, -1)]), BandsProblem.badRow);
    });

    test('the farthest delivery is where the last band ends', () {
      expect(farthestDeliveryKm([b(0, 1, 20), b(1, 4.5, 35)]), 4.5);
      expect(farthestDeliveryKm(const []), 0);
    });

    test(
      'Delivery is off until the database says it is on, and Payanas is the only area',
      () {
        expect(DeliveryStatus.off.enabled, isFalse);
        expect(DeliveryStatus.off.ready, isFalse);
        expect(DeliveryStatus.off.allowedBarangayCodes, ['1704006019']);
        final on = DeliveryStatus.fromMap({
          'enabled': true,
          'ready': true,
          'allowed_barangay_codes': ['1704006019'],
          'missing': [],
        });
        expect(on.enabled, isTrue);
        final missing = DeliveryStatus.fromMap({
          'enabled': false,
          'ready': false,
          'missing': [kDeliveryMissingPin, kDeliveryMissingBands],
        });
        expect(missing.missing, [kDeliveryMissingPin, kDeliveryMissingBands]);
      },
    );

    test(
      'a refusal is recognised by the code at the start of the database message',
      () {
        expect(
          deliveryRefusalOf(
            Exception('OUTSIDE_AREA: We deliver only within Barangay Payanas.'),
          ),
          DeliveryRefusal.outsideArea,
        );
        expect(
          deliveryRefusalOf('NO_PIN: Add the location'),
          DeliveryRefusal.noPin,
        );
        expect(deliveryRefusalOf('TOO_FAR: x'), DeliveryRefusal.tooFar);
        expect(deliveryRefusalOf('NO_BAND: x'), DeliveryRefusal.noBand);
        expect(deliveryRefusalOf('DELIVERY_OFF: x'), DeliveryRefusal.off);
        expect(deliveryRefusalOf('something else'), DeliveryRefusal.other);
      },
    );
  });

  group('Cooperative Details', () {
    test(
      'a placeholder number is never shown as the contact and never counts as a real one',
      () {
        final d = CooperativeDetails.fromMap({
          'cooperative_name': 'SP3 Agriculture Cooperative',
          'contact_number': null,
          'contact_is_placeholder': true,
        });
        expect(d.hasRealContact, isFalse);
        expect(d.contactVerified, isFalse);
        expect(d.hasPin, isFalse);
      },
    );

    test(
      'a real number and a pin; the address reads as a rural one with Sitio / Purok',
      () {
        final d = CooperativeDetails.fromMap({
          'cooperative_name': 'SP3 Agriculture Cooperative',
          'sitio_purok': 'Purok 3',
          'contact_number': '09171234567',
          'contact_is_placeholder': false,
          'contact_verified': true,
          'latitude': 13.32,
          'longitude': 122.04,
        });
        expect(d.hasRealContact, isTrue);
        expect(d.contactVerified, isTrue);
        expect(d.hasPin, isTrue);
        // The address is the fixed one: a Sitio / Purok left in the record is not part of it.
        expect(
          d.addressLine,
          'Barangay Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903',
        );
      },
    );

    test(
      'without a Sitio / Purok the address is still complete: no street or house number is needed',
      () {
        final d = CooperativeDetails.fromMap({'cooperative_name': 'x'});
        expect(
          d.addressLine,
          'Barangay Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903',
        );
      },
    );
  });
}
