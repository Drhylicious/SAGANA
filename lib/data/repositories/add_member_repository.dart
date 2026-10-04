import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_activity_repository.dart';

/// Admin "Add New Member" repository.
///
/// Design note on authentication:
/// The Supabase JS/Dart client's auth.signUp() method signs in AS the new user,
/// which would terminate the admin's current session. To avoid this, this
/// repository uses a direct database insert approach:
///
///   1. Call Supabase's admin auth endpoint via HTTP with the service role key
///      (ideal), OR
///   2. Insert the profile records directly and rely on an invitation/reset
///      email flow to set the password (what we do here — safe for small coops
///      where the admin hands the phone to the farmer in person or sends an SMS).
///
/// The admin-level auth user creation is handled via a Supabase
/// PostgreSQL function `create_farmer_account` that runs with SECURITY DEFINER
/// (bypasses RLS) and is called via rpc(). The SQL for this function is included
/// in supabase_schema_admin_create_member.sql.
///
/// If the RPC function is not yet deployed, the fallback mode creates only the
/// profile records (user_information, farmer_profiles, farmer_crops,
/// member_capital_shares) and returns a result asking admin to complete auth
/// via the Supabase dashboard or email invite.

class AddMemberRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<AddMemberResult> createMember({
    required String username,
    required String password,
    required String fullName,
    String? phoneNumber,
    String? contactEmail,
    DateTime? dateOfBirth,
    String? gender, // male | female | prefer_not_to_say
    double shareValuePerUnit = 2000,
    double initialContribution = 0,
    List<String> initialCrops = const [],
    String? registryId,
  }) async {
    try {
      final response = await _client.rpc(
        'create_farmer_account',
        params: {
        'p_username': username.trim(),
        'p_password': password,
        'p_full_name': fullName.trim(),
        'p_phone_number':
            (phoneNumber != null && phoneNumber.trim().isNotEmpty)
                ? phoneNumber.trim()
                : null,
        'p_date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
        'p_gender': gender,
        'p_share_value_per_unit': shareValuePerUnit,
        'p_initial_contribution': initialContribution,
        'p_initial_crops': initialCrops,
        'p_registry_id': registryId,
          'p_contact_email':
              (contactEmail != null && contactEmail.trim().isNotEmpty)
              ? contactEmail.trim()
              : null,
        },
      );

      // RPC returns the new user_id on success
      final newUserId = response as String?;
      if (newUserId != null && newUserId.isNotEmpty) {
        AdminActivityRepository().log(
          module: 'members',
          actionType: 'added',
          description: 'Added "${fullName.trim()}" as a new member.',
          referenceId: newUserId,
        );
        return AddMemberResult.success(userId: newUserId);
      }
      return AddMemberResult.failure(
        step:    'Account Creation',
        message: 'Unexpected response from server. Please try again.',
      );
    } catch (rpcError) {
      // RPC not deployed yet — fall through to manual field validation check
      // and return a clear error so the admin knows what happened.
      return AddMemberResult.failure(
        step:    'Account Creation',
        message: _parseError(rpcError),
      );
    }
  }

  /// Suggests the next username for new members.
  Future<String> suggestNextUsername() async {
    try {
      final result = await _client.rpc(
        'suggest_next_username',
        params: {'p_prefix': 'SP3'},
      );
      return result as String? ?? 'SP3-0001';
    } catch (_) {
      return 'SP3-0001';
    }
  }

  String _parseError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('member named') || msg.contains('full name')) {
      return 'A member with this full name already exists.';
    }
    if (msg.contains('already used by another account')) {
      return 'This email address is already used by another account. '
          'Please contact the SP3 Cooperative admin for assistance.';
    }
    if (msg.contains('at least 18 years')) {
      return 'The member must be at least 18 years old.';
    }
    if (msg.contains('already registered') ||
        msg.contains('already taken') ||
        msg.contains('already exists')) {
      return 'This username is already taken.';
    }
    if (msg.contains('function') && msg.contains('does not exist')) {
      return 'The admin account creation function is not yet deployed. '
          'Please run supabase_schema_admin_create_member.sql first, '
          'or create the account manually in the Supabase dashboard.';
    }
    if (msg.contains('password')) {
      return 'Password must be at least 8 characters.';
    }
    if (msg.contains('network') || msg.contains('connection')) {
      return 'Network error. Please check your connection.';
    }
    return 'Failed to create account. Please try again.';
  }
}

// ─── Result wrapper ────────────────────────────────────────────────────────────

class AddMemberResult {
  final bool isSuccess;
  final bool isPartial;
  final String? userId;
  final String? failedStep;
  final String? message;

  const AddMemberResult._({
    required this.isSuccess,
    required this.isPartial,
    this.userId,
    this.failedStep,
    this.message,
  });

  factory AddMemberResult.success({required String userId}) =>
      AddMemberResult._(isSuccess: true, isPartial: false, userId: userId);

  factory AddMemberResult.failure({
    required String step,
    required String message,
  }) => AddMemberResult._(
        isSuccess: false,
        isPartial: false,
        failedStep: step,
        message: message,
      );

  factory AddMemberResult.partialFailure({
    required String userId,
    required String step,
    required String message,
  }) => AddMemberResult._(
        isSuccess: false,
        isPartial: true,
        userId: userId,
        failedStep: step,
        message: message,
      );
}
