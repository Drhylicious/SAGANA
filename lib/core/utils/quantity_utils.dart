import 'package:flutter/services.dart';

/// Quantities and prices are stored as DECIMAL(10,2): at most 2 decimal places
/// and a value below 100,000,000.
const double kMaxQuantity = 99999999.99;
const int kQuantityDecimals = 2;

/// The unit every row had before units existed, and the fallback whenever a
/// row carries none.
const String kDefaultUnit = 'kg';

/// Why a typed quantity (or price) is not acceptable. Null from [checkDecimal]
/// means it is.
enum DecimalIssue {
  empty,
  notANumber,
  notPositive,
  tooManyDecimals,
  tooLarge,
  overMax,
}

final RegExp _decimalShape = RegExp(r'^(\d+\.?\d*|\.\d+)$');

/// Parses [raw] as a plain positive decimal with at most [decimals] places.
/// Returns null for anything else (empty, text, `1.2.3`, `1e5`, `-1`, `0`,
/// `0.456`). Use [checkDecimal] when the reason matters.
double? parseDecimal(
  String? raw, {
  int decimals = kQuantityDecimals,
  double max = kMaxQuantity,
}) {
  if (checkDecimal(raw, decimals: decimals, max: max) != null) return null;
  return double.parse(raw!.trim());
}

/// The reason [raw] is not a valid positive decimal, or null when it is.
/// [max] is the largest accepted value (for example the stock on hand).
DecimalIssue? checkDecimal(
  String? raw, {
  int decimals = kQuantityDecimals,
  double max = kMaxQuantity,
}) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return DecimalIssue.empty;
  if (!_decimalShape.hasMatch(text)) return DecimalIssue.notANumber;

  final dot = text.indexOf('.');
  if (dot >= 0) {
    // 1.500 is 1.5, so trailing zeros do not count as extra places.
    final fraction = text.substring(dot + 1).replaceFirst(RegExp(r'0+$'), '');
    if (fraction.length > decimals) return DecimalIssue.tooManyDecimals;
  }

  final value = double.tryParse(text);
  if (value == null) return DecimalIssue.notANumber;
  if (value <= 0) return DecimalIssue.notPositive;
  if (value > kMaxQuantity) return DecimalIssue.tooLarge;
  if (value > max + 1e-9) return DecimalIssue.overMax;
  return null;
}

/// The message for a quantity field. [max] and [unit] are only used for the
/// "more than you have" message.
String? quantityErrorText(
  String? raw, {
  double max = kMaxQuantity,
  String? unit,
  String label = 'Quantity',
}) {
  switch (checkDecimal(raw, max: max)) {
    case null:
      return null;
    case DecimalIssue.empty:
      return '$label is required';
    case DecimalIssue.notANumber:
      return 'Enter a valid number, like 0.45 or 12.5';
    case DecimalIssue.notPositive:
      return '$label must be greater than 0';
    case DecimalIssue.tooManyDecimals:
      return 'Use at most $kQuantityDecimals decimal places';
    case DecimalIssue.tooLarge:
      return '$label is too large';
    case DecimalIssue.overMax:
      return 'Only ${formatQuantityUnit(max, unit)} available';
  }
}

/// The message for a price field.
String? priceErrorText(String? raw, {String label = 'Price'}) {
  switch (checkDecimal(raw)) {
    case null:
      return null;
    case DecimalIssue.empty:
      return '$label is required';
    case DecimalIssue.notANumber:
      return 'Enter a valid amount, like 12.50';
    case DecimalIssue.notPositive:
      return '$label must be greater than 0';
    case DecimalIssue.tooManyDecimals:
      return 'Use at most $kQuantityDecimals decimal places';
    case DecimalIssue.tooLarge:
    case DecimalIssue.overMax:
      return '$label is too large';
  }
}

/// Quantity × price in pesos, rounded to the centavo exactly as the database
/// does for a NUMERIC(…,2) column (half away from zero). It multiplies whole
/// hundredths, so 3.45 × 45.50 is 156.98 and never 156.97 because of a
/// binary-float tail.
double moneyOf(num quantity, num price) {
  final q = (quantity * 100).round();
  final p = (price * 100).round();
  return ((q * p + 50) ~/ 100) / 100;
}

/// Rounds to the 2 decimals the database stores, so Dart arithmetic never
/// shows or sends 0.30000000000000004.
double roundQuantity(num value) => (value * 100).round() / 100;

/// `0.45`, `1.25`, `10.75`, `12` — a whole quantity shows no decimals, anything
/// else shows exactly 2 (`2.50`), the app's existing convention. A quantity is
/// never rounded to a whole number.
String formatQuantity(num value) {
  final rounded = roundQuantity(value);
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(kQuantityDecimals);
}

/// A unit that is safe to print: trimmed, and kg when there is none.
String unitOrDefault(String? unit) {
  final u = unit?.trim() ?? '';
  return u.isEmpty ? kDefaultUnit : u;
}

/// True when a quantity is in kg (a missing unit means kg, as every row had
/// before units existed). Totals labelled "kg" add only these rows: SAGANA does
/// not convert between units, so a sack is never added to a kilogram.
bool isKg(String? unit) => unitOrDefault(unit) == kDefaultUnit;

/// `0.45 kg`, `10.75 sack`.
String formatQuantityUnit(num value, String? unit) =>
    '${formatQuantity(value)} ${unitOrDefault(unit)}';

/// Several lines added up WITHOUT mixing units: quantities are summed per unit
/// and listed together, `12.5 kg + 3 sack`. One unit gives `12.5 kg`.
String formatQuantitiesByUnit(Iterable<({double quantity, String? unit})> lines) {
  final totals = <String, double>{};
  for (final line in lines) {
    final unit = unitOrDefault(line.unit);
    totals[unit] = (totals[unit] ?? 0) + line.quantity;
  }
  if (totals.isEmpty) return '0';
  return totals.entries
      .map((e) => formatQuantityUnit(e.value, e.key))
      .join(' + ');
}

/// An amount in pesos, always 2 decimals: `₱12.50`.
String formatPesos(num value) => '₱${value.toStringAsFixed(2)}';

/// A price per unit: `₱12.50/kg`.
String formatPricePerUnit(num value, String? unit) =>
    '${formatPesos(value)}/${unitOrDefault(unit)}';

/// The batch number as people see it, with the leading `#`
/// (`#BATCH-POTATO-261025-A0001`). Old numbers get it too. Empty when there is
/// no number yet (an offline harvest is numbered when it syncs).
String formatBatchNumber(String? batchNumber) {
  final n = batchNumber?.trim() ?? '';
  if (n.isEmpty) return '';
  // A placeholder such as "—" is not a number: leave it alone.
  if (!RegExp(r'[A-Za-z0-9]').hasMatch(n)) return n;
  return n.startsWith('#') ? n : '#$n';
}

/// A quantity as one export cell. A kg quantity stays a plain number (`12.50`)
/// so the column can still be summed in a spreadsheet; a quantity in another
/// unit carries its unit (`12.50 sack`), because a "(kg)" column must never
/// hold a bare number that is really sacks.
String exportQuantity(num value, String? unit) => isKg(unit)
    ? value.toStringAsFixed(2)
    : '${value.toStringAsFixed(2)} ${unitOrDefault(unit)}';

/// Accepts only a decimal being typed: digits with one optional point and at
/// most [decimals] places. The WHOLE new value is checked on every edit and the
/// edit is refused if it does not fit (a per-character
/// `FilteringTextInputFormatter.allow(RegExp(r'^…'))` cannot do this reliably).
/// [max], when set, also refuses a value above it, such as the stock on hand.
class DecimalInputFormatter extends TextInputFormatter {
  final int decimals;
  final double? max;
  final int maxWholeDigits;

  const DecimalInputFormatter({
    this.decimals = kQuantityDecimals,
    this.max,
    this.maxWholeDigits = 8,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final shape = RegExp('^\\d{0,$maxWholeDigits}(\\.\\d{0,$decimals})?\$');
    if (!shape.hasMatch(text)) return oldValue;
    final ceiling = max;
    if (ceiling != null) {
      final parsed = double.tryParse(text);
      if (parsed != null && parsed > ceiling + 1e-9) return oldValue;
    }
    return newValue;
  }
}
