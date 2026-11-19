import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/chunked_in.dart';
import '../../core/constants/farmer_registration_address.dart';
import '../../core/utils/person_name.dart';
import 'admin_activity_repository.dart';
import '../models/admin_log_message.dart';
import '../models/farmer_member_model.dart';
import '../services/staff_permission_service.dart';

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
    required Map<StaffModule, StaffAccess> access,
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
        'p_permissions': {
          for (final m in StaffModule.values)
            m.key: (access[m] ?? StaffAccess.view).key,
        },
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

  /// An Officer's View Only / Manage level for every module.
  Future<Map<StaffModule, StaffAccess>> fetchOfficerAccess(String userId) async {
    try {
      final result = await _client.rpc(
        'get_officer_permissions',
        params: {'p_user_id': userId},
      );
      return StaffPermissions.parse(result);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Saves an Officer's access. The database refuses it unless the caller is the
  /// Manager (script 20); the change is recorded in the accountability log by the
  /// database. It is offered on an Officer's Cooperative ID Card (Manager only).
  Future<Map<StaffModule, StaffAccess>> saveOfficerAccess(
    String userId,
    Map<StaffModule, StaffAccess> access,
  ) async {
    try {
      final result = await _client.rpc(
        'set_officer_permissions',
        params: {
          'p_user_id': userId,
          'p_permissions': {
            for (final m in StaffModule.values)
              m.key: (access[m] ?? StaffAccess.view).key,
          },
        },
      );
      return StaffPermissions.parse(result);
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
    final infoRows = await chunkedIn(userIds, (slice) => _client.from('user_information').select(
          'user_id, full_name, username, profile_photo_url, '
          'contact_email, phone_number, last_active_at',
        ).inFilter('user_id', slice));
    final infoMap = {for (final r in infoRows) r['user_id'] as String: r};

    // The Manager signs in with a real e-mail and has no separate contact
    // e-mail, so it only exists on the sign-in record (script 19).
    final managerEmails = role == 'admin' ? await _managerSignInEmails() : const <String, String>{};

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
        email: _clean(info?['contact_email'] as String?) ?? managerEmails[userId],
        phone: _clean(info?['phone_number'] as String?),
        lastActiveAt: info?['last_active_at'] == null
            ? null
            : DateTime.tryParse(info!['last_active_at'] as String),
      );
    }).toList();
    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return entries;
  }

  /// Manager user id -> sign-in e-mail (real addresses only). Empty if the call
  /// fails, so the list still loads and the e-mail reads "Not set".
  Future<Map<String, String>> _managerSignInEmails() async {
    try {
      final rows = await _client.rpc('get_manager_sign_in_emails');
      return {
        for (final r in rows as List)
          (r as Map)['account_id'] as String: r['sign_in_email'] as String,
      };
    } catch (_) {
      return const {};
    }
  }

  /// What the Cooperative ID Card shows beyond the account row: personal details,
  /// address and, for a Farmer, the farm and capital shares. Each part is read on its
  /// own, so one that cannot be read (a row the signed-in person has no access to)
  /// is simply left out; [failedParts] says how many.
  Future<AccountCardDetails> fetchCardDetails(AccountEntry account) async {
    var failed = 0;
    Future<T?> part<T>(Future<T?> Function() read) async {
      try {
        return await read();
      } catch (_) {
        failed++;
        return null;
      }
    }

    final id = account.userId;
    Map<String, dynamic>? profile;
    if (account.role == 'farmer') {
      profile = await part(
        () => _client
            .from('farmer_profiles')
            .select(
              'date_of_birth, gender, farm_name, land_area_hectares, years_farming, '
              'farm_address, farm_house_no, farm_building, farm_street, member_since',
            )
            .eq('user_id', id)
            .maybeSingle(),
      );
    } else if (account.role == 'officer') {
      profile = await part(
        () => _client
            .from('officer_profiles')
            .select('position, date_of_birth, gender')
            .eq('user_id', id)
            .maybeSingle(),
      );
    } else {
      profile = await part(
        () => _client
            .from('admin_profiles')
            .select('position, date_of_birth, gender, created_at')
            .eq('user_id', id)
            .maybeSingle(),
      );
    }

    List<String> crops = const [];
    if (account.role == 'farmer') {
      final cropRows = await part(
        () => _client
            .from('farmer_crops')
            .select('crop_name')
            .eq('farmer_id', id),
      );
      crops = [
        for (final r in cropRows ?? const [])
          if ((r['crop_name'] as String?)?.trim().isNotEmpty ?? false)
            (r['crop_name'] as String).trim(),
      ];
    }

    final addressRows = await part(
      () => _client
          .from('buyer_addresses')
          .select('address_line, barangay_name, city_municipality_name')
          .eq('user_id', id)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false)
          .limit(1),
    );
    String? address;
    if (addressRows != null && addressRows.isNotEmpty) {
      final a = addressRows.first;
      final parts =
          [
                a['barangay_name'] as String?,
                a['city_municipality_name'] as String?,
              ]
              .where((p) => (p ?? '').trim().isNotEmpty)
              .map((p) => p!.trim())
              .toList();
      // A Farmer's card shows the complete address; staff cards keep the short form.
      address = account.role == 'farmer'
          ? (_clean(a['address_line'] as String?) ??
                (parts.isNotEmpty ? parts.join(', ') : null))
          : (parts.isNotEmpty
                ? parts.join(', ')
                : _clean(a['address_line'] as String?));
    }

    // The farm's address as one line: the one saved with the farm, else built from its parts.
    String? farmAddress;
    if (account.role == 'farmer') {
      farmAddress = _clean(profile?['farm_address'] as String?);
      if (farmAddress == null) {
        final houseNo = (profile?['farm_house_no'] as String?) ?? '';
        final street = (profile?['farm_street'] as String?) ?? '';
        if (houseNo.trim().isNotEmpty || street.trim().isNotEmpty) {
          farmAddress = FarmerRegistrationAddress.composeLine(
            houseNo: houseNo,
            building: profile?['farm_building'] as String?,
            street: street,
          );
        }
      }
    }

    // Date Joined: when a Farmer became a member, else when the account was created.
    final roleRow = await part(
      () => _client
          .from('user_roles')
          .select('created_at')
          .eq('user_id', id)
          .eq('role', account.role)
          .maybeSingle(),
    );

    final info = await part(
      () => _client
          .from('user_information')
          .select('verified_contact_email')
          .eq('user_id', id)
          .maybeSingle(),
    );
    final verified = _clean(
      info?['verified_contact_email'] as String?,
    )?.toLowerCase();
    final email = account.email?.toLowerCase();

    DateTime? date(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return AccountCardDetails(
      dateOfBirth: date(profile?['date_of_birth']),
      gender: _clean(profile?['gender'] as String?),
      position: _clean(profile?['position'] as String?),
      memberSince:
          date(profile?['member_since']) ??
          date(roleRow?['created_at']) ??
          date(profile?['created_at']),
      farmName: _clean(profile?['farm_name'] as String?),
      farmHectares: (profile?['land_area_hectares'] as num?)?.toDouble(),
      crops: crops,
      yearsFarming: (profile?['years_farming'] as num?)?.toInt(),
      farmAddress: farmAddress,
      address: address,
      emailVerified: email != null && verified != null && verified == email,
      failedParts: failed,
    );
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
    final infoRows = await chunkedIn(userIds, (slice) => _client.from('user_information').select('user_id, full_name, profile_photo_url').inFilter('user_id', slice));
    final infoMap = {for (final r in infoRows) r['user_id'] as String: r};
    // Farmers, Officers and Buyers can all ask for assistance, so the role is
    // looked up to tell the Manager who is asking.
    final roleRows = await chunkedIn(userIds, (slice) => _client.from('user_roles').select('user_id, role').inFilter('user_id', slice));
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

/// The extra details on a Cooperative ID Card (see
/// AccountManagementRepository.fetchCardDetails). Every field is optional: what a
/// person has not filled in, or the signed-in person cannot read, is null.
class AccountCardDetails {
  final DateTime? dateOfBirth;
  final String? gender;
  final String? position;
  final DateTime? memberSince;
  final String? farmName;
  final double? farmHectares;
  final List<String> crops;
  final int? yearsFarming;
  final String? farmAddress;
  final String? address;
  final bool emailVerified;

  /// How many of the separate reads could not be completed.
  final int failedParts;

  const AccountCardDetails({
    this.dateOfBirth,
    this.gender,
    this.position,
    this.memberSince,
    this.farmName,
    this.farmHectares,
    this.crops = const [],
    this.yearsFarming,
    this.farmAddress,
    this.address,
    this.emailVerified = false,
    this.failedParts = 0,
  });
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