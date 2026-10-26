import '../../core/utils/contact_email.dart';

/// Combines user_information (shared profile fields) and admin_profiles
/// (admin-specific organizational fields) into one display model.
class AdminProfileModel {
  final String userId;
  final String email;
  final String fullName;
  // The name as entered in parts. Null for an account created before the name
  // was split.
  final String? surname;
  final String? firstName;
  final String? middleInitial;
  final String? suffix;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final String? contactEmail;
  // The last email address proven with a code (see ContactEmail).
  final String? verifiedContactEmail;
  // A new email the person asked to switch to; it is theirs only once verified.
  final String? pendingContactEmail;
  final String? position;
  final String? department;
  final DateTime? adminSince;
  final DateTime? dateOfBirth;
  final String? gender;

  const AdminProfileModel({
    required this.userId,
    required this.email,
    required this.fullName,
    this.surname,
    this.firstName,
    this.middleInitial,
    this.suffix,
    this.phoneNumber,
    this.profilePhotoUrl,
    this.contactEmail,
    this.verifiedContactEmail,
    this.pendingContactEmail,
    this.position,
    this.department,
    this.adminSince,
    this.dateOfBirth,
    this.gender,
  });

  /// The email to show for this person: the contact email on the profile, else
  /// the sign-in address when it is a real one. A generated sign-in address
  /// (username@sagana.local) is not an email anyone can write to, so it gives
  /// null. Always read from the account, never fixed in the app.
  String? get displayEmail {
    final contact = contactEmail?.trim() ?? '';
    if (contact.isNotEmpty) return contact;
    final signIn = email.trim();
    if (signIn.isEmpty || signIn.toLowerCase().endsWith('@sagana.local')) {
      return null;
    }
    return signIn;
  }

  /// The address verification is about: the contact email, else a real sign-in
  /// email (the Manager signs in with theirs).
  String? get verifiableEmail =>
      ContactEmail.effective(contactEmail: contactEmail, signInEmail: email);

  bool get isContactEmailVerified => ContactEmail.isVerified(
    contactEmail: contactEmail,
    signInEmail: email,
    verifiedEmail: verifiedContactEmail,
  );

  AdminProfileModel copyWith({
    String? fullName,
    String? phoneNumber,
    String? profilePhotoUrl,
    DateTime? dateOfBirth,
    String? gender,
  }) {
    return AdminProfileModel(
      userId: userId,
      email: email,
      fullName: fullName ?? this.fullName,
      contactEmail: contactEmail,
      verifiedContactEmail: verifiedContactEmail,
      pendingContactEmail: pendingContactEmail,
      surname: surname,
      firstName: firstName,
      middleInitial: middleInitial,
      suffix: suffix,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      position: position,
      department: department,
      adminSince: adminSince,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
    );
  }
}