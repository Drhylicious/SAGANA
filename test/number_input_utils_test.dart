import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/utils/input_validation_utils.dart';

void main() {
  group('numeric input validation', () {
    test('accepts decimal currency values', () {
      expect(isValidCurrencyValue('12.50'), isTrue);
      expect(isValidCurrencyValue('0.99'), isTrue);
      expect(isValidCurrencyValue('100'), isTrue);
    });

    test('rejects invalid currency values', () {
      expect(isValidCurrencyValue('12abc'), isFalse);
      expect(isValidCurrencyValue('1.2.3'), isFalse);
      expect(isValidCurrencyValue('abc'), isFalse);
      expect(isValidCurrencyValue(''), isFalse);
    });

    test('accepts whole-number reorder values', () {
      expect(isValidWholeNumberValue('0'), isTrue);
      expect(isValidWholeNumberValue('10'), isTrue);
      expect(isValidWholeNumberValue('001'), isTrue);
    });

    test('rejects non-whole-number values', () {
      expect(isValidWholeNumberValue('10.5'), isFalse);
      expect(isValidWholeNumberValue('abc'), isFalse);
      expect(isValidWholeNumberValue('1,000'), isFalse);
      expect(isValidWholeNumberValue(''), isFalse);
    });
  });
}
