import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_activity_repository.dart';

/// Admin-side account management: creating Officer accounts, listing
/// non-Farmer accounts (Officer/Buyer), and admin-assisted password
/// resets. Consolidates what create_officer_account_screen.dart and
/// manage_accounts_screen.dart previously called directly against
/// Supabase.instance.client from widget code.
class AccountManagementRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Creates an Officer account. Email + phone are optional (Decision
  /// D23); [registryId] must reference an available officer_registry row
  /// (Decision D22); the Employee ID (EMP-###) is generated server-side.
  /// Date of birth / gender are also optional (Admin Profile & Settings
  /// Phase 2 correction) — the 18+ check only applies if a date is given.
  Future<void> createOfficerAccount({
    required String username,
    required String password,
    required String fullName,
    required String registryId,
    String? email,
    String? phoneNumber,
    String? position,
    DateTime? dateOfBirth,
    String? gender,
  }) async {
    try {
      await _client.rpc('create_officer_account', params: {
        'p_username': username,
        'p_password': password,
        'p_full_name': fullName,
        'p_email': email,
        'p_phone_number': phoneNumber,
        'p_position': position,
        'p_registry_id': registryId,
        'p_date_of_birth': dateOfBirth == null
            ? null
            : '${dateOfBirth.year.toString().padLeft(4, '0')}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}',
        'p_gender': gender,
      });
      AdminActivityRepository().log(
        module: 'members',
        actionType: 'created',
        description: 'Created Officer account for $fullName.',
      );
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Officer Registry lookup for the create form (Decision D22).
  Future<OfficerRegistryMatch?> checkOfficerRegistry(String fullName) async {
    try {
      final result = await _client.rpc('check_officer_registry',
          params: {'p_full_name': fullName.trim()});
      if (result == null || (result as List).isEmpty) return null;
      final row = result.first as Map<String, dynamic>;
      return OfficerRegistryMatch(
        registryId: row['registry_id'] as String,
        isAvailable: row['is_available'] as bool? ?? false,
        phone: (row['phone_number'] as String?)?.trim(),
        email: (row['email'] as String?)?.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Fetches all accounts for a given role in exactly two queries total,
  /// regardless of row count — replaces the previous per-row
  /// user_information lookup in manage_accounts_screen.dart.
  ///
  /// Confirmed bug fix (Admin Profile & Settings review): previously had
  /// no status filter at all, so Pending/Rejected/Draft applicants — who
  /// are not cooperative members — showed up here alongside real
  /// accounts. Restricted to 'active'/'suspended': both are genuine,
  /// already-approved members (Suspended just blocks login, per the
  /// SRS), while Pending/Rejected/Draft never completed or were denied
  /// membership and must not appear in a member-accounts list.
  Future<List<AccountEntry>> fetchAccountsByRole(String role) async {
    final roles = await _client
        .from('user_roles')
        .select('user_id, status')
        .eq('role', role)
        .inFilter('status', ['active', 'suspended']);

    if (roles.isEmpty) return [];

    final userIds = roles.map((r) => r['user_id'] as String).toList();
    final infoRows = await _client
        .from('user_information')
        .select('user_id, full_name, username, profile_photo_url')
        .inFilter('user_id', userIds);
    final infoMap = {for (final r in infoRows) r['user_id'] as String: r};

    return roles.map((r) {
      final userId = r['user_id'] as String;
      final info = infoMap[userId];
      return AccountEntry(
        userId: userId,
        name: info?['full_name'] as String? ?? 'Unknown',
        username: info?['username'] as String? ?? '—',
        role: role,
        status: r['status'] as String? ?? 'active',
        profilePhotoUrl: info?['profile_photo_url'] as String?,
      );
    }).toList();
  }

  /// Returns the generated temporary password exactly once. Nothing in
  /// this app stores it after this call returns — see
  /// admin_reset_user_password() in supabase_schema_admin_password_reset.sql.
  Future<String> resetUserPassword(String userId) async {
    try {
      final result = await _client.rpc('admin_reset_user_password', params: {
        'p_user_id': userId,
      });
      return result as String;
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// All pending admin-assisted password requests, with display names
  /// batched in — same two-query pattern as fetchAccountsByRole, avoiding
  /// an unsupported PostgREST embed (password_reset_requests has no
  /// direct FK to user_information, both merely FK to auth.users).
  Future<List<PasswordResetRequest>> fetchPendingPasswordRequests() async {
    final requests = await _client
        .from('password_reset_requests')
        .select('id, user_id, username, requested_at')
        .eq('status', 'pending')
        .order('requested_at');

    if (requests.isEmpty) return [];

    final userIds = requests.map((r) => r['user_id'] as String).toList();
    final infoRows = await _client
        .from('user_information')
        .select('user_id, full_name')
        .inFilter('user_id', userIds);
    final nameMap = {
      for (final r in infoRows) r['user_id'] as String: r['full_name'] as String?
    };

    return requests.map((r) {
      final userId = r['user_id'] as String;
      return PasswordResetRequest(
        id: r['id'] as String,
        userId: userId,
        username: r['username'] as String,
        fullName: nameMap[userId] ?? r['username'] as String,
        requestedAt: DateTime.parse(r['requested_at'] as String),
      );
    }).toList();
  }

  Future<void> resolvePasswordRequest(String requestId) async {
    try {
      await _client.rpc('resolve_password_reset_request', params: {
        'p_request_id': requestId,
      });
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }
}

class OfficerRegistryMatch {
  final String registryId;
  final bool isAvailable;
  final String? phone;
  final String? email;
  const OfficerRegistryMatch({
    required this.registryId,
    required this.isAvailable,
    this.phone,
    this.email,
  });
}

class AccountEntry {
  final String userId;
  final String name;
  final String username;
  final String role;
  final String status;
  final String? profilePhotoUrl;

  const AccountEntry({
    required this.userId,
    required this.name,
    required this.username,
    required this.role,
    required this.status,
    this.profilePhotoUrl,
  });
}

class PasswordResetRequest {
  final String id;
  final String userId;
  final String username;
  final String fullName;
  final DateTime requestedAt;

  const PasswordResetRequest({
    required this.id,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.requestedAt,
  });
}