/// Rules for a person's name, kept identical to the database
/// (supabase_schema_registration_12_name_components.sql): surname and first name
/// are required, the middle initial and suffix are optional, and the complete
/// name is built in one format: `First M. Surname Suffix`.
///
/// The database rebuilds `full_name` from the parts itself, so the app never has
/// to be trusted for it. [compose] exists so the app can show the same name
/// before it is saved (review step, success message, live preview).
enum NamePartProblem { required, length, characters }

class PersonName {
  PersonName._();

  /// The suffixes a person can choose, in the form they are stored and shown.
  static const List<String> suffixes = ['Jr.', 'Sr.', 'II', 'III', 'IV', 'V'];

  static const int minPartLength = 2;
  static const int maxPartLength = 60;

  // Letters (including accented ones such as ñ), spaces, hyphens, apostrophes
  // and periods; it must start with a letter. Same pattern as the database.
  static final RegExp _partPattern = RegExp(
    r"^[A-Za-zÀ-ɏ][A-Za-zÀ-ɏ .'’-]*$",
  );

  /// One character a name may contain, for an input formatter.
  static final RegExp allowedChar = RegExp(
    r"[A-Za-zÀ-ɏ .'’-]",
  );

  static final RegExp _initialPattern = RegExp(r'^[A-Za-zÀ-ɏ]\.?$');

  /// Trims, and collapses runs of spaces into one.
  static String clean(String? value) =>
      (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');

  /// What is wrong with a surname or first name, or null if it is acceptable.
  /// An empty value is a problem only when [required].
  static NamePartProblem? checkPart(String? value, {required bool required}) {
    final v = clean(value);
    if (v.isEmpty) return required ? NamePartProblem.required : null;
    if (v.length < minPartLength || v.length > maxPartLength) {
      return NamePartProblem.length;
    }
    if (!_partPattern.hasMatch(v)) return NamePartProblem.characters;
    return null;
  }

  /// A middle initial is empty, or one letter with or without a period.
  static bool isValidInitial(String? value) {
    final v = (value ?? '').trim();
    return v.isEmpty || _initialPattern.hasMatch(v);
  }

  /// The initial as it is stored: the capital letter alone, or null if blank.
  static String? cleanInitial(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    return v.substring(0, 1).toUpperCase();
  }

  /// A suffix as stored, or null for "none" (and for anything not in [suffixes]).
  static String? cleanSuffix(String? value) {
    final v = (value ?? '').trim();
    return suffixes.contains(v) ? v : null;
  }

  /// Two-letter initials for an avatar: the first letter of the first name and
  /// of the surname. A trailing suffix (Jr., III ...) is not a surname, so
  /// "Juan D. Cruz Jr." gives JC, not JJ.
  static String initials(String? fullName, {String fallback = '?'}) {
    final tokens = clean(fullName).split(' ').where((t) => t.isNotEmpty).toList();
    while (tokens.length > 1 && _isSuffixToken(tokens.last)) {
      tokens.removeLast();
    }
    if (tokens.isEmpty) return fallback;
    final first = tokens.first[0];
    final last = tokens.length > 1 ? tokens.last[0] : '';
    return (first + last).toUpperCase();
  }

  static bool _isSuffixToken(String token) {
    final t = token.toLowerCase().replaceAll('.', '');
    return const {'jr', 'sr', 'ii', 'iii', 'iv', 'v'}.contains(t);
  }

  /// The complete name: `First M. Surname Suffix`. A missing middle initial or
  /// suffix leaves no gap and no stray punctuation.
  static String compose({
    required String firstName,
    String? middleInitial,
    required String surname,
    String? suffix,
  }) {
    final initial = cleanInitial(middleInitial);
    return [
      clean(firstName),
      if (initial != null) '$initial.',
      clean(surname),
      cleanSuffix(suffix) ?? '',
    ].where((part) => part.isNotEmpty).join(' ');
  }
}

/// A name as it is stored: surname and first name always, middle initial and
/// suffix when given. This is what every Edit Profile screen sends; the
/// database rebuilds `full_name` from it, so the complete name is only ever
/// *displayed*, never typed.
class NameParts {
  final String surname;
  final String firstName;
  final String? middleInitial;
  final String? suffix;

  const NameParts._(
    this.surname,
    this.firstName,
    this.middleInitial,
    this.suffix,
  );

  /// Cleans each part the way the database does (trimmed, spaces collapsed, the
  /// initial as a capital letter, the suffix in its canonical form).
  factory NameParts({
    required String surname,
    required String firstName,
    String? middleInitial,
    String? suffix,
  }) => NameParts._(
    PersonName.clean(surname),
    PersonName.clean(firstName),
    PersonName.cleanInitial(middleInitial),
    PersonName.cleanSuffix(suffix),
  );

  /// The parts of a `user_information` row, or null for an account whose name
  /// has not been entered in parts (created before the split).
  static NameParts? fromRow(Map<dynamic, dynamic>? row) {
    final surname = row?['surname'] as String?;
    final first = row?['first_name'] as String?;
    if (surname == null || first == null) return null;
    if (surname.trim().isEmpty || first.trim().isEmpty) return null;
    return NameParts(
      surname: surname,
      firstName: first,
      middleInitial: row?['middle_initial'] as String?,
      suffix: row?['suffix'] as String?,
    );
  }

  /// `First M. Surname Suffix`, the same text the database stores in `full_name`.
  String get fullName => PersonName.compose(
    firstName: firstName,
    middleInitial: middleInitial,
    surname: surname,
    suffix: suffix,
  );

  /// The four `user_information` columns. The database trigger validates them
  /// and rebuilds `full_name`, so `full_name` is deliberately not sent.
  Map<String, dynamic> toColumns() => {
    'surname': surname,
    'first_name': firstName,
    'middle_initial': middleInitial,
    'suffix': suffix,
  };
}
