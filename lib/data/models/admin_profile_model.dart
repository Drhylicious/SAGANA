/// Combines user_information (shared profile fields) and admin_profiles
/// (admin-specific organizational fields) into one display model.
class AdminProfileModel {
  final String userId;
  final String email;
  final String fullName;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final String? purok;
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
    this.purok,
    this.employeeId,
    this.position,
    this.department,
    this.adminSince,
  });

  AdminProfileModel copyWith({
    String? fullName,
    String? phoneNumber,
    String? profilePhotoUrl,
    String? purok,
  }) {
    return AdminProfileModel(
      userId: userId,
      email: email,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      purok: purok ?? this.purok,
      employeeId: employeeId,
      position: position,
      department: department,
      adminSince: adminSince,
    );
  }
}