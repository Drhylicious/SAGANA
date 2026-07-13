import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import 'hive_service.dart';

class AuthService {
  AuthService._();

  static final SupabaseClient _client = Supabase.instance.client;

  // ── Session ──────────────────────────────────────────────────────────────────

  static bool get isLoggedIn => _client.auth.currentSession != null;
  static User? get currentUser => _client.auth.currentUser;
  static Session? get currentSession => _client.auth.currentSession;

  static Future<String?> getCurrentUserRole() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final response = await _client
          .from('user_roles')
          .select('role')
          .eq('user_id', user.id)
          .single();
      return response['role'] as String?;
    } catch (_) {
      return HiveService.getUserRole();
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────────
  // Accepts either a real email (admin) or a SAGANA username (staff/farmer/buyer).
  // Usernames are stored with the @sagana.local suffix in Supabase Auth.

  static Future<UserModel> login({
    required String identifier, // email or username
    required String password,
  }) async {
    final email = toAuthEmail(identifier.trim());

    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.user == null) {
      throw const AuthException('Login failed. Please check your credentials.');
    }

    final role = await getCurrentUserRole();
    if (role == null) {
      await _client.auth.signOut();
      throw const AuthException(
        'Account role not found. Contact SP3 Cooperative.',
      );
    }

    // Enforce: farmers and staff must use username auth (sagana.local email).
    // If a farmer/staff somehow logs in with a real email, block them.
    final authEmail = response.user!.email ?? email;
    if ((role == 'farmer' || role == 'staff') &&
        !authEmail.endsWith('@sagana.local')) {
      await _client.auth.signOut();
      throw const AuthException(
        'Farmer and Staff accounts must log in with a SAGANA username, '
        'not an email address. Please use your SP3-XXXX or STF-XXXX username.',
      );
    }

    // Fetch membership status for farmers — needed for routing
    String memberStatus = 'active';
    if (role == 'farmer') {
      try {
        final statusRow = await _client
            .from('user_roles')
            .select('status')
            .eq('user_id', response.user!.id)
            .single();
        memberStatus = statusRow['status'] as String? ?? 'active';
      } catch (_) {}
    }

    final infoResponse = await _client
        .from('user_information')
        .select('full_name, phone_number, profile_photo_url, sitio, username')
        .eq('user_id', response.user!.id)
        .maybeSingle();

    final userModel = UserModel(
      id: response.user!.id,
      email: authEmail,
      role: role,
      status: memberStatus,
      fullName: infoResponse?['full_name'] as String?,
      phoneNumber: infoResponse?['phone_number'] as String?,
      profilePhotoUrl: infoResponse?['profile_photo_url'] as String?,
      sitio: infoResponse?['sitio'] as String?,
    );

    await HiveService.saveUserSession(
      userId: userModel.id,
      email: authEmail,
      role: userModel.role,
      fullName: userModel.fullName,
    );

    // Cache membership status for offline splash routing
    await HiveService.saveMemberStatus(memberStatus);

    return userModel;
  }

  // ── Self-Registration (Farmers not in SP3 registry + Buyers) ─────────────────
  // For official SP3 members, admin creates accounts via add_new_member_screen.
  // This method handles non-member farmer self-registration and buyer registration.

  static Future<UserModel> register({
    required String username, // chosen by user or SP3-XXXX if verified member
    required String password,
    required String fullName,
    required String phoneNumber,
    required String role, // 'farmer' | 'buyer'
    String? sitio,
    String? registryId, // non-null if user matched SP3 registry
    String? memberId, // non-null if SP3 registry match
  }) async {
    final email = toAuthEmail(username.trim());

    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );

    if (response.user == null) {
      throw const AuthException('Registration failed. Please try again.');
    }

    final userId = response.user!.id;

    try {
      await _client.from('user_roles').insert({
        'user_id': userId,
        'role': role,
        // SP3-verified farmers become active immediately
        // Non-member farmers and buyers default to pending
        'status': registryId != null ? 'active' : 'pending',
      });

      await _client.from('user_information').insert({
        'user_id': userId,
        'full_name': fullName.trim(),
        'phone_number': phoneNumber.trim(),
        'sitio': sitio,
        'username': username.trim().toLowerCase(),
      });

      if (role == 'farmer') {
        await _client.from('farmer_profiles').insert({
          'user_id': userId,
          'member_id': memberId,
          'is_verified': registryId != null,
        });
        // Mark registry as registered if applicable
        if (registryId != null) {
          await _client
              .from('sp3_member_registry')
              .update({'is_registered': true, 'registered_user_id': userId})
              .eq('id', registryId);
        }
      } else if (role == 'buyer') {
        await _client.from('buyer_profiles').insert({'user_id': userId});
      }

      return UserModel(
        id: userId,
        email: email,
        role: role,
        status: registryId != null ? 'active' : 'pending',
        fullName: fullName.trim(),
        phoneNumber: phoneNumber.trim(),
        sitio: sitio,
      );
    } catch (e) {
      await _client.auth.signOut();
      rethrow;
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────────

  static Future<void> logout() async {
    await _client.auth.signOut();
    await HiveService.clearUserSession();
  }

  // ── Password Change ───────────────────────────────────────────────────────────

  static Future<void> changePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  // ── Password Reset ───────────────────────────────────────────────────────────

  static Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  // ── Check username availability ───────────────────────────────────────────────

  static Future<bool> isUsernameAvailable(String username) async {
    try {
      final rows = await _client
          .from('user_information')
          .select('user_id')
          .eq('username', username.trim().toLowerCase());
      return rows.isEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── SP3 Registry check ────────────────────────────────────────────────────────

  static Future<Sp3RegistryResult?> checkSp3Registry(String fullName) async {
    try {
      final result = await _client.rpc(
        'check_sp3_registry',
        params: {'p_full_name': fullName.trim()},
      );
      if (result == null || (result as List).isEmpty) return null;
      final row = result.first as Map<String, dynamic>;
      if (!(row['is_available'] as bool? ?? false)) {
        return null; // Already registered
      }
      return Sp3RegistryResult(
        registryId: row['registry_id'] as String,
        suggestedSitio: row['suggested_sitio'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Suggest next username from server ────────────────────────────────────────

  static Future<String> suggestNextUsername(String prefix) async {
    try {
      final result = await _client.rpc(
        'suggest_next_username',
        params: {'p_prefix': prefix.toUpperCase()},
      );
      return result as String;
    } catch (_) {
      // Fallback client-side
      return '${prefix.toUpperCase()}-0001';
    }
  }

  // ── Error Parser ──────────────────────────────────────────────────────────────

  static String parseAuthError(Object error) {
    if (error is AuthException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('invalid login credentials') ||
          msg.contains('invalid credentials')) {
        return 'Incorrect username or password. Please try again.';
      }
      if (msg.contains('already registered') ||
          msg.contains('already been registered')) {
        return 'This username is already taken.';
      }
      if (msg.contains('password should be at least')) {
        return 'Password must be at least 8 characters.';
      }
      if (msg.contains('rate limit')) {
        return 'Too many attempts. Please wait a moment and try again.';
      }
      return error.message;
    }
    return 'An unexpected error occurred. Please try again.';
  }

  // ── Membership Guard ─────────────────────────────────────────────────────
  // Server-side second layer of defense against pending farmers writing
  // cooperative data — the router redirect handles normal navigation, but a
  // deep link or stale UI state could still reach a write method directly.

  /// Throws if the current farmer's membership is not active.
  /// Call at the top of any repository method that writes cooperative data.
  static Future<void> requireActiveMembership() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated.');

    try {
      final row = await _client
          .from('user_roles')
          .select('status')
          .eq('user_id', userId)
          .single();
      final status = row['status'] as String? ?? 'pending';
      if (status != 'active') {
        throw Exception(
            'Your membership is pending approval. '
            'This feature will be available once the SP3 Administrator '
            'approves your application.');
      }
    } catch (e) {
      if (e.toString().contains('pending approval')) rethrow;
      // On network error, fall back to Hive cache
      final cached = HiveService.getMemberStatus();
      if (cached != null && cached != 'active') {
        throw Exception(
            'Your membership is pending approval. '
            'Connect to the internet to check your status.');
      }
    }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────────

  /// Converts a username or email to the Supabase auth email format.
  /// Real emails (containing @) are passed through unchanged.
  /// Usernames are suffixed with @sagana.local.
  static String toAuthEmail(String identifier) {
    if (identifier.contains('@')) return identifier.toLowerCase();
    return '${identifier.toLowerCase()}@sagana.local';
  }
}

// ─── SP3 Registry Result ──────────────────────────────────────────────────────

class Sp3RegistryResult {
  final String registryId;
  final String? suggestedSitio;
  const Sp3RegistryResult({required this.registryId, this.suggestedSitio});
}