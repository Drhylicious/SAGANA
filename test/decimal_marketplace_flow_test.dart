import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sagana/core/l10n/app_localizations_en.dart';
import 'package:sagana/core/l10n/app_localizations_tl.dart';
import 'package:sagana/core/utils/app_error_message.dart';
import 'package:sagana/core/utils/quantity_utils.dart';
import 'package:sagana/data/models/buyer_listing_model.dart';
import 'package:sagana/data/models/cart_item_model.dart';
import 'package:sagana/presentation/widgets/quantity_stepper.dart';

import 'support/ignore_font_errors.dart';

/// Decimal quantities and prices, followed through the Marketplace flow the way a
/// Buyer or Farmer meets them: the quantity box, the cart line, the subtotal,
/// what a listing returns from the database, and how it is shown.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the quantity box accepts decimals', () {
    Future<List<double>> typeInto(
      WidgetTester tester,
      String text, {
      double max = 50,
      double from = 1,
    }) async {
      final reported = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuantityStepper(value: from, max: max, onChanged: reported.add),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      return reported;
    }

    for (final v in ['0.45', '1.25', '10.75', '0.01', '2.5', '49.99']) {
      testWidgets('$v is accepted exactly', (tester) async {
        await runIgnoringFontErrors(() async {
          final reported = await typeInto(tester, v);
          expect(reported.last, double.parse(v));
        });
      });
    }

    testWidgets('a third decimal place is refused (the field keeps what was valid)', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final reported = await typeInto(tester, '1.255');
        expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
            isNot('1.255'));
        expect(reported.every((v) => v != 1.255), isTrue);
      });
    });

    testWidgets('a decimal above the stock is refused (50.01 when 50 is left)', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final reported = await typeInto(tester, '50.01');
        expect(reported.every((v) => v <= 50), isTrue);
      });
    });

    testWidgets('a fractional stock is respected (9.55 left: 9.55 ok, 9.56 not)', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final ok = await typeInto(tester, '9.55', max: 9.55);
        expect(ok.last, 9.55);
      });
      await runIgnoringFontErrors(() async {
        final no = await typeInto(tester, '9.56', max: 9.55);
        expect(no.every((v) => v <= 9.55), isTrue);
      });
    });

    testWidgets('stepping from a decimal stays exact: 0.45 + 1 = 1.45, 10.75 - 1 = 9.75', (
      tester,
    ) async {
      await runIgnoringFontErrors(() async {
        final reported = <double>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QuantityStepper(value: 0.45, max: 50, onChanged: reported.add),
            ),
          ),
        );
        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
        expect(reported.last, 1.45);
        // No binary tail such as 1.4500000000000002.
        expect(reported.last.toString(), '1.45');
      });
    });
  });

  group('money and display stay exact', () {
    test('quantity x price is rounded to the centavo, never off by one', () {
      expect(moneyOf(3.45, 45.50), 156.98);
      expect(moneyOf(0.45, 100), 45.0);
      expect(moneyOf(10.75, 99.99), 1074.89); // 1074.8925 -> .89
      expect(moneyOf(0.01, 0.01), 0.0); // 0.0001 -> 0.00
      expect(moneyOf(0.05, 0.50), 0.03); // 0.025 -> 0.03: half away from zero, like the database
    });

    test('a fraction is shown with 2 places, a whole number with none, never rounded to a whole', () {
      expect(formatQuantity(0.45), '0.45');
      expect(formatQuantity(10.75), '10.75');
      expect(formatQuantity(2.5), '2.50');
      expect(formatQuantity(10), '10');
      expect(formatQuantityUnit(0.45, 'sack'), '0.45 sack');
      expect(formatQuantityUnit(10.75, 'pack'), '10.75 pack');
      expect(formatPesos(1074.89), '₱1074.89');
    });

    test('Dart arithmetic noise is removed before it is shown or sent', () {
      expect(roundQuantity(0.1 + 0.2), 0.3);
      expect(roundQuantity(10.75 - 1), 9.75);
      expect(roundQuantity(9.55 - 0.45), 9.1);
    });

    test('quantity rules: 2 decimals, above 0, within the stock', () {
      expect(checkDecimal('0.45'), isNull);
      expect(checkDecimal('0.456'), DecimalIssue.tooManyDecimals);
      expect(checkDecimal('0'), DecimalIssue.notPositive);
      expect(checkDecimal('9.56', max: 9.55), DecimalIssue.overMax);
      expect(checkDecimal('1.500'), isNull); // 1.5, trailing zeros are not extra places
    });
  });

  group('summary cards keep the centavos', () {
    test('below 1,000 the amount is exact, never rounded to a whole peso', () {
      expect(formatPesosCompact(156.98), '₱156.98');
      expect(formatPesosCompact(45.5), '₱45.50');
      expect(formatPesosCompact(0), '₱0.00');
      expect(formatPesosCompact(999.99), '₱999.99');
    });

    test('from 1,000 up it is shortened', () {
      expect(formatPesosCompact(1000), '₱1.0k');
      expect(formatPesosCompact(1234.56), '₱1.2k');
    });

    test('the Farmer Listing Overview uses it', () {
      final src = File('lib/presentation/screens/farmer/my_listings_screen.dart')
          .readAsStringSync();
      expect(src, contains('formatPesosCompact(totalSold)'));
      expect(src.contains('toStringAsFixed(0)'), isFalse);
    });
  });

  group('the database says "at most 2 decimal places" in the app\'s language', () {
    final en = AppLocalizationsEn();
    final tl = AppLocalizationsTl();

    test('quantity and price messages are translated, not shown raw', () {
      for (final raw in [
        'Use at most 2 decimal places for the quantity.',
        'Use at most 2 decimal places for the price.',
        'Quantity must be greater than zero (two decimals at most).',
      ]) {
        expect(messageForDatabaseText(en, raw, 'P0001'), 'Use at most 2 decimal places.');
        expect(messageForDatabaseText(tl, raw, 'P0001'), isNot('Use at most 2 decimal places.'));
        expect(messageForDatabaseText(tl, raw, 'P0001'), contains('2 decimal'));
      }
    });

    test('other refusals are untouched', () {
      expect(messageForDatabaseText(en, 'Not enough stock available. Only 5 kg remaining.', 'P0001'),
          en.errNoStock);
    });
  });

  group('the Marketplace decimal guard script', () {
    final sql = File('supabase_schema/supabase_schema_marketplace_decimal_guards.sql')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final code = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

    test('it patches the two live functions in place and never rewrites them whole', () {
      expect(code, contains('pg_get_functiondef'));
      expect(code, contains('regexp_replace'));
      expect(code.contains('CREATE OR REPLACE FUNCTION public.place_order'), isFalse);
      expect(code.contains('CREATE OR REPLACE FUNCTION public.create_listing_with_reservation'), isFalse);
    });

    test('it stops without changing anything when the expected line is missing', () {
      expect(code, contains('RAISE EXCEPTION'));
      expect(code, contains('could not find'));
    });

    test('it is safe to re-run (already-patched functions are skipped)', () {
      expect(code, contains('already has it'));
    });

    test('the same wording as the Harvest / Listing reference functions', () {
      expect(code, contains("'Use at most 2 decimal places for the quantity.'"));
      expect(code, contains("'Use at most 2 decimal places for the price.'"));
    });

    test('it changes no table, policy or grant and leaves Cooperative Products alone', () {
      for (final w in ['CREATE TABLE', 'ALTER TABLE', 'CREATE POLICY', 'GRANT ', 'REVOKE ', 'place_program_order']) {
        expect(code.contains(w), isFalse, reason: w);
      }
    });
  });

  group('decimals survive the cart and the database rows', () {
    test('a cart line keeps 0.45 and 10.75 exactly through storage', () {
      for (final q in [0.45, 1.25, 10.75]) {
        final item = CartItemModel(
          listingId: 'l',
          cropName: 'Peanut Cookies',
          pricePerKg: 45.5,
          unit: 'sack',
          availableKgSnapshot: 90.5,
          quantityKg: q,
        );
        final back = CartItemModel.fromMap(item.toMap());
        expect(back.quantityKg, q);
        expect(back.availableKgSnapshot, 90.5);
        expect(back.subtotal, moneyOf(q, 45.5));
      }
    });

    test('a listing row with decimal stock, price and sales reads exactly', () {
      final m = BuyerListingModel.fromMap({
        'id': 'l1',
        'crop_name': 'Potato',
        'volume_kg': 100.5,
        'remaining_kg': 9.55,
        'price_per_kg': 45.75,
        'unit': 'sack',
        'created_at': '2026-11-05T00:00:00Z',
        'sold_kg': 3.25,
      });
      expect(m.remainingKg, 9.55);
      expect(m.pricePerKg, 45.75);
      expect(m.soldKg, 3.25);
      expect(m.unit, 'sack');
      expect(m.isOrderable, isTrue);
      // Under 15% of the listing left: low stock, with a fractional remainder.
      expect(m.isLowStock, isTrue);
    });

    test('a listing with under 1 of the unit left is still orderable', () {
      final m = BuyerListingModel.fromMap({
        'id': 'l1',
        'crop_name': 'Potato',
        'volume_kg': 10,
        'remaining_kg': 0.45,
        'price_per_kg': 45,
        'created_at': '2026-11-05T00:00:00Z',
      });
      expect(m.isOrderable, isTrue);
      expect(m.isSoldOut, isFalse);
      expect(m.displayAvailableKg, 0.45);
    });
  });
}
