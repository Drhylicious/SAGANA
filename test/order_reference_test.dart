import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/l10n/app_localizations.dart';
import 'package:sagana/core/theme/app_theme.dart';
import 'package:sagana/core/utils/order_reference.dart';
import 'package:sagana/data/models/buyer_order_model.dart';
import 'package:sagana/data/repositories/admin_order_repository.dart';
import 'package:sagana/presentation/widgets/order_result_pieces.dart';

import 'support/ignore_font_errors.dart';

const _id = '7d750007-1111-4222-8333-444455556666';

Map<String, dynamic> _orderRow({String? number}) => {
  'id': _id,
  if (number != null) 'order_number': number,
  'listing_id': 'l1',
  'buyer_id': 'b1',
  'crop_name': 'Eggplant',
  'quantity_kg': 10,
  'price_per_kg': 40,
  'total_price': 400,
  'status': 'completed',
  'created_at': DateTime(2026, 10, 24).toIso8601String(),
  'updated_at': DateTime(2026, 10, 24).toIso8601String(),
};

void main() {
  group('order reference', () {
    test('a stored order number is shown as it is', () {
      expect(orderReferenceOf(_id, 'ORD-20261024-A001'), 'ORD-20261024-A001');
    });

    test('an order with no number keeps the reference it always had', () {
      expect(orderReferenceOf(_id, null), 'ORD-7D750007');
      expect(orderReferenceOf(_id, ''), 'ORD-7D750007');
      expect(orderReferenceOf(_id, '   '), 'ORD-7D750007');
      expect(legacyOrderReference(_id), 'ORD-7D750007');
    });

    test('the Buyer / Farmer order model uses it', () {
      expect(BuyerOrderModel.fromMap(_orderRow(number: 'ORD-20261024-A001')).orderReference, 'ORD-20261024-A001');
      expect(BuyerOrderModel.fromMap(_orderRow()).orderReference, 'ORD-7D750007');
    });

    test('the Manager order model uses it', () {
      expect(AdminOrderModel.fromMap(_orderRow(number: 'ORD-20261024-A001')).orderReference, 'ORD-20261024-A001');
      expect(AdminOrderModel.fromMap(_orderRow()).orderReference, 'ORD-7D750007');
    });

    test('searching an order by the new number or its date part works', () {
      final o = AdminOrderModel.fromMap(_orderRow(number: 'ORD-20261024-A001'));
      final ref = o.orderReference.toLowerCase();
      expect(ref.contains('a001'), isTrue);
      expect(ref.contains('20261024'), isTrue);
    });

    test('all three screens see the same text for the same order', () {
      final b = BuyerOrderModel.fromMap(_orderRow(number: 'ORD-20261024-A001'));
      final a = AdminOrderModel.fromMap(_orderRow(number: 'ORD-20261024-A001'));
      expect(b.orderReference, a.orderReference);
    });
  });

  group('order reference card', () {
    Widget host(Widget child) => MaterialApp(
      theme: AppTheme.lightTheme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

    testWidgets('shows the new number, or the old reference without one', (tester) async {
      await runIgnoringFontErrors(() async {
        await tester.pumpWidget(
          host(
            Column(
              children: [
                OrderReferenceCard(
                  orderId: _id,
                  orderNumber: 'ORD-20261024-A001',
                  status: 'pending',
                  displayName: 'Eggplant',
                  quantityKg: 10,
                  pricePerKg: 40,
                  totalPrice: 400,
                ),
                OrderReferenceCard(
                  orderId: _id,
                  status: 'pending',
                  displayName: 'Eggplant',
                  quantityKg: 10,
                  pricePerKg: 40,
                  totalPrice: 400,
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        expect(find.text('ORD-20261024-A001'), findsOneWidget);
        expect(find.text('ORD-7D750007'), findsOneWidget);
      });
    });
  });
}
