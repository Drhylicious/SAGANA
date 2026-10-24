import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagana/core/utils/temp_password.dart';

void main() {
  const allowed =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';

  test('has the requested length (10 by default) and only readable characters', () {
    expect(generateTemporaryPassword().length, 10);
    expect(generateTemporaryPassword(length: 16).length, 16);
    for (var i = 0; i < 500; i++) {
      final p = generateTemporaryPassword();
      for (final ch in p.split('')) {
        expect(allowed.contains(ch), isTrue, reason: '"$ch" in $p');
      }
      // Never the look-alike characters.
      expect(RegExp(r'[IOl01]').hasMatch(p), isFalse, reason: p);
    }
  });

  test('always contains an upper-case letter, a lower-case letter and a digit', () {
    for (var i = 0; i < 2000; i++) {
      final p = generateTemporaryPassword();
      expect(RegExp(r'[A-Z]').hasMatch(p), isTrue, reason: p);
      expect(RegExp(r'[a-z]').hasMatch(p), isTrue, reason: p);
      expect(RegExp(r'[0-9]').hasMatch(p), isTrue, reason: p);
    }
  });

  test('meets the app minimum of 8 characters and refuses anything shorter', () {
    expect(generateTemporaryPassword(length: 8).length, 8);
    expect(() => generateTemporaryPassword(length: 7), throwsArgumentError);
  });

  test('is not derived from the clock: calls in the same instant all differ', () {
    // The old generator was built from one millisecond timestamp, so two calls
    // in the same millisecond were identical and anyone who knew roughly when
    // it ran could guess it. Generate many in a tight loop.
    final seen = <String>{};
    for (var i = 0; i < 5000; i++) {
      seen.add(generateTemporaryPassword());
    }
    expect(seen.length, 5000);
  });

  test('is not predictable from a time-like seed', () {
    // The previous formula, for comparison: chars[(ms + i * 17) % 56].
    String old(int ms) {
      const chars = allowed;
      final b = StringBuffer();
      for (var i = 0; i < 10; i++) {
        b.write(chars[(ms + i * 17) % chars.length]);
      }
      return b.toString();
    }

    final base = DateTime.now().millisecondsSinceEpoch;
    final guesses = <String>{for (var d = -60000; d <= 60000; d++) old(base + d)};
    // Only 56 distinct outputs exist for the old formula, whatever the time.
    expect(guesses.length, lessThanOrEqualTo(56));
    // A one-minute window of guesses finds none of the new passwords.
    for (var i = 0; i < 1000; i++) {
      expect(guesses.contains(generateTemporaryPassword()), isFalse);
    }
  });

  test('the first character is not always the same kind (the order is shuffled)', () {
    final kinds = <String>{};
    for (var i = 0; i < 400; i++) {
      final c = generateTemporaryPassword()[0];
      kinds.add(RegExp(r'[A-Z]').hasMatch(c)
          ? 'upper'
          : RegExp(r'[a-z]').hasMatch(c)
              ? 'lower'
              : 'digit');
    }
    expect(kinds, containsAll(['upper', 'lower', 'digit']));
  });

  test('a supplied random source is used (so tests can be repeatable)', () {
    expect(
      generateTemporaryPassword(random: Random(42)),
      generateTemporaryPassword(random: Random(42)),
    );
    expect(
      generateTemporaryPassword(random: Random(1)),
      isNot(generateTemporaryPassword(random: Random(2))),
    );
  });
}
