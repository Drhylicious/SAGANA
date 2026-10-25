import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one-batch restock script must stay narrow: it may only rewrite the
/// figures of the one batch, and only after re-checking that no record backs
/// the "sold" kilograms.
void main() {
  final sql = File('supabase_schema/supabase_schema_ginger_batch_restock.sql')
      .readAsStringSync();
  final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  test('touches only the figures of one batch', () {
    expect(RegExp(r'\bUPDATE\s+\w+', caseSensitive: false).allMatches(code).length, 1);
    expect(code, contains('UPDATE inventory_batches'));
    expect(code, contains('SET sold_kg = 0, available_kg = quantity_kg'));
    expect(code, contains("WHERE id = c_batch"));
    expect(RegExp(r'\b(DELETE|INSERT|TRUNCATE|DROP)\b', caseSensitive: false).hasMatch(code), isFalse);
    // never the identity columns the protect-identity trigger guards
    expect(RegExp(r'SET[^;]*\b(batch_number|unit)\b', caseSensitive: false).hasMatch(code), isFalse);
  });

  test('refuses unless every record that could back the stock is absent', () {
    for (final t in [
      'informal_sales',
      'cooperative_purchase_offers',
      'market_linking_programs',
      'orders',
      'marketplace_listings',
    ]) {
      expect(code, contains(t), reason: t);
    }
    expect(code, contains('b.quantity_kg = 20 AND b.available_kg = 10 AND b.sold_kg = 10'));
    expect(code, contains('b.available_kg + b.sold_kg <> b.quantity_kg'));
    expect(code, contains("b.status = 'withdrawn'"));
    expect(RegExp('Nothing changed').allMatches(code).length, greaterThanOrEqualTo(5));
  });
}
