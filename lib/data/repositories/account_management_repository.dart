import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/person_name.dart';
import 'admin_activity_repository.dart';
import '../models/admin_log_message.dart';
import '../models/farmer_member_model.dart';

/// Admin-side account management: creating Officer accounts, listing
/// non-Farmer accounts (Officer/Buyer), and admin-assisted password
/// resets. Consolidates what create_officer_account_screen.dart and
/// manage_accounts_screen.dart previously called directly against
/// Supabase.instance.client from widget code.
class AccountManagementRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Creates an Officer account. Nothing is looked up in a registry: the
  /// Manager enters the details, the username must be unique across all
  /// accounts, and the database issues the Officer ID (OFF-YYYY-NNN).
  /// Email + phone are optional. Date of birth / gender are also optional —
  /// the 18+ check only applies if a date is given.
  Future<void> createOfficerAccount({
    required String username,
    required String password,
    required String surname,
    required String firstName,
    String? middleInitial,
    String? suffix,
    String? email,
    String? phoneNumber,
    String? position,
    DateTime? dateOfBirth,
    String? gender,
  }) async {
    // The complete name, built the same way the database builds it (it
    // rebuilds it from the parts itself); used for the activity log here.
    final fullName = PersonName.compose(
      firstName: firstName,
      middleInitial: middleInitial,
      surname: surname,
      suffix: suffix,
    );
    try {
      await _client.rpc(
        'create_officer_account',
        params: {
        'p_username': username,
        'p_password': password,
        'p_surname': PersonName.clean(surname),
        'p_first_name': PersonName.clean(firstName),
        'p_middle_initial': PersonName.cleanInitial(middleInitial),
        'p_suffix': PersonName.cleanSuffix(suffix),
        'p_email': email,
        'p_phone_number': phoneNumber,
        'p_position': position,
        'p_date_of_birth': dateOfBirth == null
            ? null
            : '${dateOfBirth.year.toString().padLeft(4, '0')}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}',
        'p_gender': gender,
        },
      );
      AdminActivityRepository().log(
        module: 'members',
        actionType: 'created',
        message: AdminLogMessage('adminLogAccountOfficerCreated', {'fullName': fullName}),
      );
    } on PostgrestException catch (e) {
      throw Exception(e.message);
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
        .select(
          'user_id, full_name, username, profile_photo_url, '
          'contact_email, phone_number, last_active_at',
        )
        .inFilter('user_id', userIds);
    final infoMap = {for (final r in infoRows) r['user_id'] as String: r};

    final entries = roles.map((r) {
      final userId = r['user_id'] as String;
      final info = infoMap[userId];
      return AccountEntry(
        userId: userId,
        name: info?['full_name'] as String? ?? 'Unknown',
        username: info?['username'] as String? ?? '—',
        role: role,
        status: r['status'] as String? ?? 'active',
        profilePhotoUrl: info?['profile_photo_url'] as String?,
        email: _clean(info?['contact_email'] as String?),
        phone: _clean(info?['phone_number'] as String?),
        lastActiveAt: info?['last_active_at'] == null
            ? null
            : DateTime.tryParse(info!['last_active_at'] as String),
      );
    }).toList();
    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return entries;
  }

  /// Returns the generated temporary password exactly once. Nothing in
  /// this app stores it after this call returns — see
  /// admin_reset_user_password() in supabase_schema_admin_password_reset.sql.
  Future<String> resetUserPassword(String userId) async {
    try {
      final result = await _client.rpc(
        'admin_reset_user_password',
        params: {'p_user_id': userId},
      );
      AdminActivityRepository().log(
        module: 'members',
        actionType: 'password_reset',
        message: const AdminLogMessage('adminLogAccountPasswordReset'),
        referenceId: userId,
      );
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
        .select('user_id, full_name, profile_photo_url')
        .inFilter('user_id', userIds);
    final infoMap = {for (final r in infoRows) r['user_id'] as String: r};
    // Farmers, Officers and Buyers can all ask for assistance, so the role is
    // looked up to tell the Manager who is asking.
    final roleRows = await _client
        .from('user_roles')
        .select('user_id, role')
        .inFilter('user_id', userIds);
    final roleMap = {
      for (final r in roleRows) r['user_id'] as String: r['role'] as String?,
    };

    return requests.map((r) {
      final userId = r['user_id'] as String;
      final info = infoMap[userId];
      return PasswordResetRequest(
        id: r['id'] as String,
        userId: userId,
        username: r['username'] as String,
        fullName: (info?['full_name'] as String?) ?? r['username'] as String,
        requestedAt: DateTime.parse(r['requested_at'] as String),
        role: roleMap[userId],
        profilePhotoUrl: info?['profile_photo_url'] as String?,
      );
    }).toList();
  }

  Future<void> resolvePasswordRequest(String requestId) async {
    try {
      await _client.rpc(
        'resolve_password_reset_request',
        params: {'p_request_id': requestId},
      );
      AdminActivityRepository().log(
        module: 'members',
        actionType: 'password_request_resolved',
        message: const AdminLogMessage('adminLogAccountResetResolved'),
        referenceId: requestId,
      );
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }
}

/// A blank value counts as not set.
String? _clean(String? value) {
  final v = value?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

class AccountEntry {
  final String userId;
  final String name;
  final String username;
  final String role;
  final String status;
  final String? profilePhotoUrl;

  /// The person's own contact e-mail and phone number (never the internal
  /// username@sagana.local sign-in address). Null when not set.
  final String? email;
  final String? phone;

  /// user_information.last_active_at, stamped at every sign-in.
  final DateTime? lastActiveAt;

  const AccountEntry({
    required this.userId,
    required this.name,
    required this.username,
    required this.role,
    required this.status,
    this.profilePhotoUrl,
    this.email,
    this.phone,
    this.lastActiveAt,
  });

  /// What the badge shows. Inactive is derived, never stored: a stored status
  /// of 'active' whose last activity is older than 30 days. This is the same
  /// rule the Members list uses, so both screens always agree.
  MemberStatus get effectiveStatus =>
      MemberStatusExt.derive(status, lastActiveAt);
}

class PasswordResetRequest {
  final String id;
  final String userId;
  final String username;
  final String fullName;
  final DateTime requestedAt;

  /// 'farmer', 'officer' or 'buyer' (null if the role could not be read).
  final String? role;
  final String? profilePhotoUrl;

  const PasswordResetRequest({
    required this.id,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.requestedAt,
    this.role,
    this.profilePhotoUrl,
  });
}