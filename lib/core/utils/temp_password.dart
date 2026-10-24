import 'dart:math';

// Letters and digits that cannot be confused with one another when a Manager
// reads the password out or writes it down (no I, O, l, 0 or 1).
const String _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const String _lower = 'abcdefghijkmnpqrstuvwxyz';
const String _digits = '23456789';

/// A random temporary password for an account a Manager creates.
///
/// Drawn from the operating system's cryptographically secure random source
/// ([Random.secure]), so it cannot be guessed from the time it was made. It
/// always holds at least one upper-case letter, one lower-case letter and one
/// digit, in an unpredictable order.
///
/// [length] must be at least 8, the app's minimum password length. [random] is
/// only for tests.
String generateTemporaryPassword({int length = 10, Random? random}) {
  if (length < 8) {
    throw ArgumentError.value(length, 'length', 'must be at least 8');
  }
  final r = random ?? Random.secure();
  const all = _upper + _lower + _digits;
  final chars = <String>[
    _upper[r.nextInt(_upper.length)],
    _lower[r.nextInt(_lower.length)],
    _digits[r.nextInt(_digits.length)],
  ];
  while (chars.length < length) {
    chars.add(all[r.nextInt(all.length)]);
  }
  // Fisher–Yates shuffle, so the three guaranteed characters are not always
  // in the first three positions.
  for (var i = chars.length - 1; i > 0; i--) {
    final j = r.nextInt(i + 1);
    final tmp = chars[i];
    chars[i] = chars[j];
    chars[j] = tmp;
  }
  return chars.join();
}
