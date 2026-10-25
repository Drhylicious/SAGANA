import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/utils/quantity_utils.dart';

TextEditingValue _v(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);

void main() {
  group('parseDecimal accepts valid decimal quantities', () {
    test('the examples from the requirement', () {
      expect(parseDecimal('0.45'), 0.45);
      expect(parseDecimal('1.25'), 1.25);
      expect(parseDecimal('10.75'), 10.75);
    });

    test('whole numbers, a bare leading point and trailing zeros', () {
      expect(parseDecimal('12'), 12);
      expect(parseDecimal('.5'), 0.5);
      expect(parseDecimal('1.500'), 1.5); // 1.500 is 1.5: not 3 decimals
      expect(parseDecimal(' 7.25 '), 7.25);
      expect(parseDecimal('99999999.99'), 99999999.99);
    });
  });

  group('parseDecimal rejects invalid quantities', () {
    test('empty, zero, negative and non-numeric input', () {
      expect(parseDecimal(null), isNull);
      expect(parseDecimal(''), isNull);
      expect(parseDecimal('   '), isNull);
      expect(parseDecimal('0'), isNull);
      expect(parseDecimal('0.00'), isNull);
      expect(parseDecimal('-1'), isNull);
      expect(parseDecimal('-0.45'), isNull);
      expect(parseDecimal('abc'), isNull);
      expect(parseDecimal('12abc'), isNull);
      expect(parseDecimal('1.2.3'), isNull);
      expect(parseDecimal('1e5'), isNull);
      expect(parseDecimal('1,5'), isNull);
      expect(parseDecimal('.'), isNull);
    });

    test('more than 2 decimals would be rounded by the database', () {
      expect(parseDecimal('0.456'), isNull);
      expect(parseDecimal('1.255'), isNull);
    });

    test('above the column limit or the stock on hand', () {
      expect(parseDecimal('100000000'), isNull);
      expect(parseDecimal('5.01', max: 5), isNull);
      expect(parseDecimal('5', max: 5), 5);
      expect(parseDecimal('0.45', max: 0.45), 0.45);
    });
  });

  group('checkDecimal says why', () {
    test('each reason', () {
      expect(checkDecimal(''), DecimalIssue.empty);
      expect(checkDecimal('abc'), DecimalIssue.notANumber);
      expect(checkDecimal('0'), DecimalIssue.notPositive);
      expect(checkDecimal('0.456'), DecimalIssue.tooManyDecimals);
      expect(checkDecimal('1000000000'), DecimalIssue.tooLarge);
      expect(checkDecimal('6', max: 5), DecimalIssue.overMax);
      expect(checkDecimal('0.45'), isNull);
    });
  });

  group('messages', () {
    test('quantity', () {
      expect(quantityErrorText(''), 'Quantity is required');
      expect(quantityErrorText('abc'), contains('valid number'));
      expect(quantityErrorText('0'), 'Quantity must be greater than 0');
      expect(quantityErrorText('1.234'), contains('2 decimal'));
      expect(
        quantityErrorText('6', max: 5, unit: 'sack'),
        'Only 5 sack available',
      );
      expect(quantityErrorText('0.45'), isNull);
    });

    test('price', () {
      expect(priceErrorText(''), 'Price is required');
      expect(priceErrorText('0'), 'Price must be greater than 0');
      expect(priceErrorText('12.50'), isNull);
      expect(
        priceErrorText('', label: 'Asking price'),
        'Asking price is required',
      );
    });
  });

  group('formatting never rounds a quantity to a whole number', () {
    test('formatQuantity', () {
      expect(formatQuantity(0.45), '0.45');
      expect(formatQuantity(1.25), '1.25');
      expect(formatQuantity(10.75), '10.75');
      expect(formatQuantity(10), '10');
      expect(formatQuantity(10.5), '10.50');
      expect(formatQuantity(0.1 + 0.2), '0.30'); // no 0.30000000000000004
      expect(formatQuantity(1234.5), '1234.50');
    });

    test('formatQuantityUnit falls back to kg', () {
      expect(formatQuantityUnit(0.45, 'kg'), '0.45 kg');
      expect(formatQuantityUnit(10.75, 'sack'), '10.75 sack');
      expect(formatQuantityUnit(3, null), '3 kg');
      expect(formatQuantityUnit(3, '  '), '3 kg');
    });

    test('prices keep their centavos', () {
      expect(formatPesos(12.5), '₱12.50');
      expect(formatPesos(12), '₱12.00');
      expect(formatPricePerUnit(12.5, 'kg'), '₱12.50/kg');
      expect(formatPricePerUnit(12.5, 'sack'), '₱12.50/sack');
    });

    test('roundQuantity removes the binary-float tail', () {
      expect(roundQuantity(0.1 + 0.2), 0.3);
      expect(roundQuantity(10.75 * 3), 32.25);
      expect(roundQuantity(12.5 * 0.45), 5.63); // 5.625 -> 2 decimals
    });
  });

  group('batch number display', () {
    test('gets a leading # once', () {
      expect(
        formatBatchNumber('BATCH-POTATO-261025-A0001'),
        '#BATCH-POTATO-261025-A0001',
      );
      expect(
        formatBatchNumber('#BATCH-POTATO-261025-A0001'),
        '#BATCH-POTATO-261025-A0001',
      );
      // An old number keeps its identity, with the same # in front.
      expect(
        formatBatchNumber('BATCH-POTA-20261025-1234'),
        '#BATCH-POTA-20261025-1234',
      );
    });

    test('nothing to show before a number is issued', () {
      expect(formatBatchNumber(null), '');
      expect(formatBatchNumber('  '), '');
    });
  });

  group('units are never added together', () {
    test('isKg treats a missing unit as kg (every old row)', () {
      expect(isKg(null), isTrue);
      expect(isKg(''), isTrue);
      expect(isKg('kg'), isTrue);
      expect(isKg('sack'), isFalse);
    });

    test('formatQuantitiesByUnit sums per unit', () {
      expect(
        formatQuantitiesByUnit([
          (quantity: 10.5, unit: 'kg'),
          (quantity: 2.0, unit: 'sack'),
          (quantity: 1.5, unit: 'kg'),
        ]),
        '12 kg + 2 sack',
      );
      expect(formatQuantitiesByUnit([(quantity: 0.45, unit: null)]), '0.45 kg');
      expect(formatQuantitiesByUnit([]), '0');
    });
  });

  group('DecimalInputFormatter checks the whole value on every edit', () {
    const f = DecimalInputFormatter();

    String type(String from, String to) =>
        f.formatEditUpdate(_v(from), _v(to)).text;

    test('lets a decimal be typed one character at a time', () {
      var text = '';
      for (final ch in '0.45'.split('')) {
        final next = text + ch;
        text = type(text, next);
      }
      expect(text, '0.45');
    });

    test('allows 10.75 and 12.50', () {
      expect(type('10.7', '10.75'), '10.75');
      expect(type('12.5', '12.50'), '12.50');
    });

    test('refuses a third decimal, a second point and letters', () {
      expect(type('0.45', '0.456'), '0.45');
      expect(type('1.2', '1.2.'), '1.2');
      expect(type('12', '12a'), '12');
      expect(type('1', '1-'), '1');
      expect(type('', '-'), '');
    });

    test('a field that already holds 20.00 still takes an edit before it', () {
      // The case the old per-character filter dropped silently.
      expect(type('20.00', '120.00'), '120.00');
    });

    test('a ceiling refuses a value above the stock on hand', () {
      const capped = DecimalInputFormatter(max: 0.45);
      expect(capped.formatEditUpdate(_v('0.4'), _v('0.45')).text, '0.45');
      expect(capped.formatEditUpdate(_v('0.4'), _v('0.46')).text, '0.4');
      expect(capped.formatEditUpdate(_v('0'), _v('5')).text, '0');
    });

    test('empty is always allowed (the field can be cleared)', () {
      expect(type('0.45', ''), '');
    });
  });
}
