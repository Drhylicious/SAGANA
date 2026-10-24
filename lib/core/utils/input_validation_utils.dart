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

// ─── Account fields (registration, Manager-created accounts) ────────────────
//
// These mirror the server-side rules in
// supabase_schema_registration_01_foundation.sql so the app and the database
// accept and reject the same input. The database is the authority; these
// exist so a person sees the problem before the request is sent.

/// Normalizes a Philippine mobile number to `09XXXXXXXXX`, or returns null
/// when it is not one. Accepts `09XXXXXXXXX`, `+639XXXXXXXXX` and
/// `639XXXXXXXXX`; spaces, dashes, dots and brackets are ignored.
String? normalizePhilippineMobile(String? value) {
  final v = (value ?? '').replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
  if (v.isEmpty) return null;
  if (RegExp(r'^\+639\d{9}$').hasMatch(v)) return '0${v.substring(3)}';
  if (RegExp(r'^639\d{9}$').hasMatch(v)) return '0${v.substring(2)}';
  if (RegExp(r'^09\d{9}$').hasMatch(v)) return v;
  return null;
}

final RegExp _emailPattern = RegExp(
  r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"
  r"(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$",
);

/// True when [value] is a well-formed email address with a real-looking
/// domain (labels, a dot and a letters-only top-level domain). This checks
/// format only; it does not prove the person owns the address.
bool isValidEmailFormat(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty || v.length > 254 || v.contains('..')) return false;
  return _emailPattern.hasMatch(v);
}

/// The stored form of a username: trimmed and lower-cased, so uniqueness is
/// case-insensitive everywhere.
String normalizeUsername(String value) => value.trim().toLowerCase();

/// 3 to 30 characters: letters, numbers, dots, underscores and hyphens.
/// (No `@`: a username containing it would be read as an email address.)
bool isValidUsernameFormat(String? value) {
  return RegExp(r'^[a-z0-9._-]{3,30}$').hasMatch(normalizeUsername(value ?? ''));
}

/// Rule for the sign-in field, which takes a username or an email address.
/// Anything containing `@` is read as an email address and must be well
/// formed. Evaluated when the form is validated, from the text itself, so it
/// does not depend on when the screen last rebuilt.
String? validateLoginIdentifier(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return 'Username or email is required';
  if (v.contains('@') && !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) {
    return 'Enter a valid email address';
  }
  return null;
}

/// Longest Source an inventory item may carry. The database enforces the same
/// limit (enforce_inventory_source); this is the form's first line of defence.
const int kInventorySourceMaxLength = 150;

/// What is wrong with an inventory item's Source, if anything.
enum InventorySourceIssue { empty, tooLong }

/// Source is required for every inventory item: where it came from (supplier,
/// donation, board resolution...). Surrounding spaces do not count.
InventorySourceIssue? checkInventorySource(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return InventorySourceIssue.empty;
  if (v.length > kInventorySourceMaxLength) return InventorySourceIssue.tooLong;
  return null;
}

// ─── Units of measure (Inventory and Price Management) ──────────────────────
//
// Mirrors the units_name_format check in supabase_schema_units.sql: lower-case,
// 1-20 characters, starting with a letter, then letters, digits, space, dot,
// slash or hyphen. The database is the authority.

const int kUnitMaxLength = 20;

enum UnitIssue { empty, tooLong, invalidCharacters }

/// A unit name as it is stored: trimmed, inner runs of spaces collapsed to one,
/// lower-case ("  Kg " and "kg" are the same unit).
String normalizeUnitName(String? value) =>
    (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// What is wrong with a proposed unit name, if anything.
UnitIssue? checkUnitName(String? value) {
  final v = normalizeUnitName(value);
  if (v.isEmpty) return UnitIssue.empty;
  if (v.length > kUnitMaxLength) return UnitIssue.tooLong;
  if (!RegExp(r'^[a-z][a-z0-9 ./-]*$').hasMatch(v)) {
    return UnitIssue.invalidCharacters;
  }
  return null;
}
