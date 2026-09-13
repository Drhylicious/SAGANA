class UserModel {
  final String id;
  final String email;
  final String role;
  final String status;
  final String? fullName;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final String? purok;
  final DateTime? createdAt;

  const UserModel({
    required this.id,
    required this.email,
    required this.role,
    required this.status,
    this.fullName,
    this.phoneNumber,
    this.profilePhotoUrl,
    this.purok,
    this.createdAt,
  });

  // ─── Role Helpers ────────────────────────────────────────────────────────────

  bool get isFarmer => role == 'farmer';
  bool get isAdmin => role == 'admin';
  bool get isBuyer => role == 'buyer';
  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';

  String get displayName => fullName ?? email.split('@').first;

  // ─── Serialization ───────────────────────────────────────────────────────────

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String,
      email: map['email'] as String? ?? '',
      role: map['role'] as String? ?? 'farmer',
      status: map['status'] as String? ?? 'pending',
      fullName: map['full_name'] as String?,
      phoneNumber: map['phone_number'] as String?,
      profilePhotoUrl: map['profile_photo_url'] as String?,
      purok: map['purok'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'role': role,
      'status': status,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'profile_photo_url': profilePhotoUrl,
      'purok': purok,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? role,
    String? status,
    String? fullName,
    String? phoneNumber,
    String? profilePhotoUrl,
    String? purok,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      role: role ?? this.role,
      status: status ?? this.status,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      purok: purok ?? this.purok,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'UserModel(id: $id, email: $email, role: $role, status: $status)';
}
