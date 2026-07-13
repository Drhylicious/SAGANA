bool isValidCurrencyValue(String? value) {
  if (value == null) return false;
  final normalized = value.trim();
  if (normalized.isEmpty) return false;
  return RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized);
}

bool isValidWholeNumberValue(String? value) {
  if (value == null) return false;
  final normalized = value.trim();
  if (normalized.isEmpty) return false;
  return RegExp(r'^\d+$').hasMatch(normalized);
}
