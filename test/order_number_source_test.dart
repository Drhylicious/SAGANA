import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A query that forgets `order_number` would quietly keep showing the old
/// ORD-xxxxxxxx reference, and nothing would fail. These read the source and
/// make that impossible to miss.
String read(String path) => File(path).readAsStringSync();

int count(String source, String needle) => needle.allMatches(source).length;

void main() {
  test('Buyer and Farmer orders: list and detail both select order_number', () {
    final src = read('lib/data/repositories/buyer_order_repository.dart');
    expect(count(src, 'id, order_number, listing_id'), 2);
  });

  test('Manager orders: list and detail both select order_number', () {
    final src = read('lib/data/repositories/admin_order_repository.dart');
    expect(count(src, 'id, order_number, listing_id, buyer_id'), 2);
  });

  test('Sales Report, Farmer Transaction History and Analytics select it', () {
    expect(read('lib/data/repositories/admin_reports_repository.dart'), contains('id, order_number, listing_id, buyer_id'));
    expect(read('lib/data/repositories/farmer_transaction_repository.dart'), contains('id, order_number, quantity_kg'));
    expect(read('lib/data/repositories/analytics_repository.dart'), contains('id, order_number, quantity_kg'));
  });

  test('the checkout result looks the numbers up', () {
    expect(read('lib/data/repositories/buyer_order_repository.dart'), contains("select('id, order_number')"));
    expect(read('lib/presentation/screens/buyer/cart_checkout_result_screen.dart'), contains('fetchOrderNumbers'));
    expect(read('lib/presentation/screens/buyer/order_success_screen.dart'), contains('orderNumber: _orders[i].orderNumber'));
  });

  test('nobody builds an order reference from the id by hand any more', () {
    for (final f in [
      'lib/data/models/buyer_order_model.dart',
      'lib/data/repositories/admin_order_repository.dart',
      'lib/presentation/widgets/order_result_pieces.dart',
      'lib/data/repositories/analytics_repository.dart',
    ]) {
      // The old pattern was 'ORD-${...substring...}'.
      expect(RegExp(r"'ORD-\$\{").hasMatch(read(f)), isFalse, reason: f);
    }
  });

  test('the SQL and the app agree on the order number shape', () {
    final sql = read('supabase_schema/supabase_schema_order_number.sql');
    expect(sql, contains(r"'^ORD-[0-9]{8}-[A-Z]+[0-9]{3}$'"));
    expect(sql, contains("'Asia/Manila'"));
    expect(read('lib/core/utils/order_reference.dart'), contains("'ORD-"));
  });
}
