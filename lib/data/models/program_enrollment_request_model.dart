/// A farmer's self-service request to enroll in a cooperative program —
/// see supabase_schema_program_enrollment_requests.sql. Modeled after the
/// existing DA-AMAD enrollment request shape (market_linking_repository
/// .dart's enrollment fields) for the same farmer-request/admin-review
/// pattern applied to Programs instead of Market Linking.
class ProgramEnrollmentRequest {
  final String id;
  final String programId;
  final String programName;
  final String? programImageUrl;
  final String status; // 'pending' | 'approved' | 'rejected'
  final String? adminNotes;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  // Only present on the Admin-facing fetch (joined from user_information);
  // null on the farmer-facing fetch, which has no reason to know its own name.
  final String? farmerName;

  const ProgramEnrollmentRequest({
    required this.id,
    required this.programId,
    required this.programName,
    this.programImageUrl,
    required this.status,
    this.adminNotes,
    required this.submittedAt,
    this.reviewedAt,
    this.farmerName,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory ProgramEnrollmentRequest.fromMap(Map<String, dynamic> map) {
    final program = map['cooperative_programs'] as Map<String, dynamic>?;
    final userInfo = map['user_information'] as Map<String, dynamic>?;
    return ProgramEnrollmentRequest(
      id: map['id'] as String,
      programId: map['program_id'] as String,
      programName: program?['program_name'] as String? ?? 'Program',
      programImageUrl: program?['image_url'] as String?,
      status: map['status'] as String? ?? 'pending',
      adminNotes: map['admin_notes'] as String?,
      submittedAt: DateTime.parse(map['submitted_at'] as String),
      reviewedAt: map['reviewed_at'] != null
          ? DateTime.parse(map['reviewed_at'] as String)
          : null,
      farmerName: userInfo?['full_name'] as String?,
    );
  }
}
