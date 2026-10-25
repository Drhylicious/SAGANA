/// Which email address an account's verification is about, and whether it is
/// verified. The same two rules the database uses (effective_contact_email and
/// the comparison in verify_contact_email), so the app and the server agree.
class ContactEmail {
  ContactEmail._();

  /// The internal sign-in domain. An address on it cannot receive mail.
  static const String internalDomain = '@sagana.local';

  static String? _clean(String? value) {
    final v = value?.trim().toLowerCase() ?? '';
    return v.isEmpty ? null : v;
  }

  /// The address verification applies to: the contact email, else the sign-in
  /// email when it is a real address (the Manager signs in with theirs). Null
  /// when the account has neither.
  static String? effective({String? contactEmail, String? signInEmail}) {
    final contact = _clean(contactEmail);
    if (contact != null) return contact;
    final signIn = _clean(signInEmail);
    if (signIn == null || signIn.endsWith(internalDomain)) return null;
    return signIn;
  }

  /// Verified only while the address in use is the one that was proven. Change
  /// the address and this is false again; the old proof stays on record.
  static bool isVerified({
    String? contactEmail,
    String? signInEmail,
    String? verifiedEmail,
  }) {
    final current = effective(contactEmail: contactEmail, signInEmail: signInEmail);
    final proven = _clean(verifiedEmail);
    return current != null && proven != null && current == proven;
  }
}
