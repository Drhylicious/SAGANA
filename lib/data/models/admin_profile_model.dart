/// Combines user_information (shared profile fields) and admin_profiles
/// (admin-specific organizational fields) into one display model — joined
/// at the repository level, not the DB level, same pattern as
/// AdminLoanSummary denormalizing farmer identity from two sibling tables
/// via farmer_lookup.dart.
class AdminProfileModel {
  final String userId;
  final String email;
  final String fullName;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final String? sitio;
  final String? employeeId;
  final String? position;
  final String? department;
  final DateTime? adminSince;

  const AdminProfileModel({
    required this.userId,
    required this.email,
    required this.fullName,
    this.phoneNumber,
    this.profilePhotoUrl,
    this.sitio,
    this.employeeId,
    this.position,
    this.department,
    this.adminSince,
  });

  AdminProfileModel copyWith({
    String? fullName,
    String? phoneNumber,
    String? profilePhotoUrl,
    String? sitio,
  }) {
    return AdminProfileModel(
      userId: userId,
      email: email,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      sitio: sitio ?? this.sitio,
      employeeId: employeeId,
      position: position,
      department: department,
      adminSince: adminSince,
    );
  }
}