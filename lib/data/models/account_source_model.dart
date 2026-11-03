/// Where a Farmer account came from, when an Officer created it. A Farmer who
/// registered on their own has no source row, and a Farmer the Manager created
/// is active at once, so only Officer-created applicants appear here.
///
/// Read from the database view account_creation_sources, which shows staff only
/// the creator and the date. Who decided, when and why stays Manager-only.
class AccountSource {
  final String userId;
  final String? createdByName;
  final DateTime? createdAt;

  const AccountSource({
    required this.userId,
    required this.createdByName,
    required this.createdAt,
  });

  factory AccountSource.fromMap(Map<String, dynamic> m) => AccountSource(
        userId: m['user_id'] as String,
        createdByName: m['requested_by_name'] as String?,
        createdAt: DateTime.tryParse(m['requested_at'] as String? ?? ''),
      );
}
