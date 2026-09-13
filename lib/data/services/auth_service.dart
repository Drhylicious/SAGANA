import 'dart:async' show unawaited;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../core/constants/app_constants.dart';
import '../models/user_model.dart';
import 'app_settings_service.dart';
import 'hive_service.dart';
import 'sync_service.dart';

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
  // Accepts either a real email (admin) or a SAGANA username (officer/farmer/buyer).
  // Usernames are stored with the @sagana.local suffix in Supabase Auth.

  static Future<UserModel> login({
    required String identifier, // email or username
    required String password,
  }) async {
    final email = await _resolveLoginEmail(identifier.trim());

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

    // Officer never gets a promoted email (that flow is Farmer/Buyer only —
    // see promote_contact_email) — so an Officer must always authenticate
    // with the synthetic OFF-XXXX@sagana.local address.
    final authEmail = response.user!.email ?? email;
    if (role == 'officer' && !authEmail.endsWith('@sagana.local')) {
      await _client.auth.signOut();
      throw const AuthException(
        'Officer accounts must log in with a SAGANA username, '
        'not an email address. Please use your OFF-XXXX username.',
      );
    }

    // Fetch membership status (farmers) and the forced-password-change
    // flag (all roles — an admin-issued temporary password can apply to
    // Farmer/Officer/Buyer/Admin alike, see AccountManagementRepository)
    // in one query.
    String memberStatus = 'active';
    bool mustChangePassword = false;
    bool pendingAcknowledgement = false;
    try {
      final statusRow = await _client
          .from('user_roles')
          .select('status, must_change_password, pending_acknowledgement')
          .eq('user_id', response.user!.id)
          .single();
      if (role == 'farmer') {
        memberStatus = statusRow['status'] as String? ?? 'active';
        pendingAcknowledgement =
            statusRow['pending_acknowledgement'] as bool? ?? false;

        // Blocked statuses — Suspended stops login with the recorded
        // reason (Issue 5 / Decision D17). Draft/Pending/Rejected still
        // log in: they land on the Pending Applicant screen. Inactive is
        // derived, never a stored value, and never blocks.
        if (memberStatus == 'suspended') {
          final reason = statusRow['suspension_reason'] as String?;
          await _client.auth.signOut();
          throw AuthException(
            (reason != null && reason.trim().isNotEmpty)
                ? 'Your account has been suspended. Reason: ${reason.trim()} '
                    'Please contact the SP3 Cooperative.'
                : 'Your account has been suspended by the SP3 Administrator. '
                    'Please contact the cooperative for assistance.',
          );
        }
      }
      mustChangePassword = statusRow['must_change_password'] as bool? ?? false;
    } catch (e) {
      // Re-throw a suspension AuthException; swallow only genuine
      // connectivity/shape failures (the original behaviour).
      if (e is AuthException) rethrow;
    }

    // Stamp last activity for the derived "Inactive" indicator (Decision
    // D8). Fire-and-forget — never let this block or fail a login.
    unawaited(_client.rpc('touch_last_active').catchError((_) {}));

    // Officer capability is a fixed role (every Admin module except the
    // Members tab) — no per-account permission scope to fetch (Decision D12).

    final infoResponse = await _client
        .from('user_information')
        .select('full_name, phone_number, profile_photo_url, purok, username')
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
      purok: infoResponse?['purok'] as String?,
    );

    await HiveService.saveUserSession(
      userId: userModel.id,
      email: authEmail,
      role: userModel.role,
      fullName: userModel.fullName,
    );

    // Cache membership status for offline splash routing
    await HiveService.saveMemberStatus(memberStatus);
    await HiveService.savePendingAcknowledgement(pendingAcknowledgement);
    await HiveService.saveMustChangePassword(mustChangePassword);

    await AppSettingsService.instance.reloadForUser(userModel.id);

    return userModel;
  }

  // ── Self-Registration (Farmers not in SP3 registry + Buyers) ─────────────────
  // For official SP3 members, admin creates accounts via add_new_member_screen.
  // This method handles non-member farmer self-registration and buyer registration.

  static Future<UserModel> register({
    required String username, // chosen by user or SP3-XXXX if verified member
    required String password,
    required String fullName,
    required String role, // 'farmer' | 'buyer'
    String? phoneNumber, // optional (Issue 1)
    String? contactEmail, // optional (Issue 1) — stored in user_information only
    String? purok,
    DateTime? dateOfBirth, // farmer personal info (Phase B) — 18+ enforced
    String? gender, // male | female | prefer_not_to_say
    String? registryId, // non-null if user matched SP3 registry
  }) async {
    final trimmedName = fullName.trim();
    final trimmedPhone = phoneNumber?.trim();
    final trimmedContactEmail = contactEmail?.trim();

    // 18+ membership rule (farmers/members only — not Buyers).
    if (role == AppConstants.roleFarmer && dateOfBirth != null) {
      final now = DateTime.now();
      final eighteenthBirthday = DateTime(
          dateOfBirth.year + 18, dateOfBirth.month, dateOfBirth.day);
      if (eighteenthBirthday.isAfter(now)) {
        throw const AuthException(
          'You must be at least 18 years old to register as a cooperative member.',
        );
      }
    }

    // ── Duplicate-account guard (Issue 3) ──────────────────────────────────
    // Belt-and-braces: the register screen already blocks on this, but a
    // stale UI or a race could still get here. 'error' (RPC unreachable)
    // is NOT treated as a conflict — the row inserts below have their own
    // uniqueness constraints as the final authority.
    final nameStatus = await checkFullNameAvailability(trimmedName);
    if (nameStatus == 'taken_account' || nameStatus == 'taken_registry') {
      throw const AuthException(
        'This full name is already registered. Please log in instead, or '
        'contact the SP3 Cooperative if you believe this is a mistake.',
      );
    }
    if (trimmedContactEmail != null && trimmedContactEmail.isNotEmpty) {
      final emailFree = await isEmailAvailable(trimmedContactEmail);
      if (!emailFree) {
        throw const AuthException(
          'This email address is already used by another account.',
        );
      }
    }

    final authEmail = toAuthEmail(username.trim());

    final response = await _client.auth.signUp(
      email: authEmail,
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
        // SP3-verified farmers become active immediately.
        // Buyers self-activate on registration — no admin verification.
        // Outsider farmers now start in 'draft' (Issue 5 / Decision D5):
        // the account exists but the application is NOT sent until they
        // tap "Submit Application" on the Pending Applicant screen. They
        // stay hidden from the Admin Members list while in draft.
        'status': (role == AppConstants.roleBuyer || registryId != null)
            ? 'active'
            : 'draft',
      });

      await _client.from('user_information').insert({
        'user_id': userId,
        'full_name': trimmedName,
        // Phone and email are both optional now (Issue 1). Store NULL
        // rather than an empty string when not provided.
        'phone_number':
            (trimmedPhone != null && trimmedPhone.isNotEmpty) ? trimmedPhone : null,
        'contact_email':
            (trimmedContactEmail != null && trimmedContactEmail.isNotEmpty)
                ? trimmedContactEmail
                : null,
        'purok': purok,
        'username': username.trim().toLowerCase(),
      });

      if (role == 'farmer') {
        // Member ID (SP3-<year>-<seq>) is assigned ONLY to already-verified
        // official members here. Outsiders stay NULL until an Admin
        // approves their application (Phase C). This also removes the old
        // bug where the login username was written as the Member ID.
        String? memberId;
        if (registryId != null) {
          try {
            final generated = await _client.rpc('generate_member_id');
            if (generated is String && generated.isNotEmpty) {
              memberId = generated;
            }
          } catch (_) {
            // Non-fatal — Admin can assign it later from the member record.
          }
        }

        await _client.from('farmer_profiles').insert({
          'user_id': userId,
          'member_id': memberId,
          'is_verified': registryId != null,
          'date_of_birth':
              dateOfBirth?.toIso8601String().split('T').first,
          'gender': gender,
        });
        // Mark registry as registered if applicable — via a SECURITY
        // DEFINER RPC, not a direct table update. sp3_member_registry's
        // RLS only grants write access to admins, so a plain client-side
        // update here is silently dropped by RLS (0 rows affected, no
        // error) — the account still gets created correctly, but the
        // registry row is left stale (is_registered stays false). The RPC
        // performs the same update bypassing RLS, scoped to the caller's
        // own new account.
        if (registryId != null) {
          try {
            await _client.rpc('link_sp3_registry', params: {
              'p_registry_id': registryId,
            });
          } catch (_) {
            // Non-fatal — the account is still valid; an Admin can link
            // the registry row manually if this ever fails.
          }
        }
      } else if (role == 'buyer') {
        await _client.from('buyer_profiles').insert({'user_id': userId});
      }

      return UserModel(
        id: userId,
        email: authEmail,
        role: role,
        status: registryId != null ? 'active' : 'pending',
        fullName: trimmedName,
        phoneNumber:
            (trimmedPhone != null && trimmedPhone.isNotEmpty) ? trimmedPhone : null,
        purok: purok,
      );
    } catch (e) {
      await _client.auth.signOut();
      rethrow;
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────────

  static Future<void> logout() async {
    // Stop the periodic sync timer before signing out — otherwise it
    // keeps firing every 5 minutes until app restart, each tick failing
    // silently (no authenticated user) via SyncService's own try/catch.
    // Harmless in practice, but wasteful and adjacent to Profile's Sign
    // Out action (Phase 4 / W3).
    SyncService.stopAutoSync();
    await _client.auth.signOut();
    await HiveService.clearUserSession();
  }

  // ── Password Change ───────────────────────────────────────────────────────────

  // Used by the forced-password-change flow only (an admin-issued
  // temporary password the user doesn't know a "current" value for).
  // For the user-initiated Settings > change-password flow, see
  // SettingsRepository.changePassword(), which re-authenticates with the
  // current password first — a deliberately different method in a
  // different class for a deliberately different flow, not a duplicate.
  static Future<void> changePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Clears the forced-password-change flag after a successful update via
  /// ForcePasswordChangeScreen.
  static Future<void> clearMustChangePassword() async {
    await _client.rpc('clear_must_change_password');
    await HiveService.saveMustChangePassword(false);
  }

  // ── Password Reset ───────────────────────────────────────────────────────────
  //
  // Admin-only in practice (see LoginScreen — farmers/officers/buyers are routed
  // to a "contact SP3" message instead of this, since they authenticate with
  // usernames, not real inboxes).
  //
  // Uses an OTP code, not a clickable link. A clickable magic link requires
  // the PKCE code_verifier to still be present in the local storage of
  // whichever browser/device completes the exchange — which fails whenever
  // the request and the click happen on different devices or browsers
  // (e.g. requesting on a phone, opening the email on a desktop). That's
  // normal behavior for email, not an edge case, so a link-based flow was
  // never going to be reliable here. A manually-entered code has no such
  // requirement — see ResetPasswordScreen for the verification step.

  static Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  /// Fails safe toward FALSE — if this check itself fails, we route to
  /// the Admin-assisted fallback rather than risk sending someone into
  /// an OTP flow we couldn't actually confirm they're eligible for.
  static Future<bool> canUseOtpReset(String identifier) async {
    try {
      final result = await _client.rpc('can_use_otp_reset', params: {
        'p_identifier': identifier.trim(),
      });
      return result as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> verifyPasswordResetOtp({
    required String email,
    required String token,
  }) async {
    await _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.recovery,
    );
  }

  // ── Request Password Assistance (Farmer/Officer/Buyer, pre-authentication) ─────
  // Called from the Login screen's Contact Admin sheet — no logged-in user
  // exists at this point, unlike every other method in this section. See
  // request_password_assistance() in
  // supabase_schema_password_assistance_requests.sql for the enumeration-
  // safety reasoning behind why this returns void with no success/failure
  // signal either way.

  static Future<void> requestPasswordAssistance(String username) async {
    await _client.rpc('request_password_assistance', params: {
      'p_username': username.trim(),
    });
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

  /// Looks up [fullName] in the SP3 member registry.
  ///
  /// Returns `null` only when there is NO matching registry row. When a
  /// row matches but is already registered, a result is still returned
  /// with [Sp3RegistryResult.alreadyRegistered] == true so the caller
  /// can show a "please log in instead" error rather than treating the
  /// person as an outsider (Issue 3).
  static Future<Sp3RegistryResult?> checkSp3Registry(String fullName) async {
    try {
      final result = await _client.rpc(
        'check_sp3_registry',
        params: {'p_full_name': fullName.trim()},
      );
      if (result == null || (result as List).isEmpty) return null;
      final row = result.first as Map<String, dynamic>;
      final isAvailable = row['is_available'] as bool? ?? false;
      return Sp3RegistryResult(
        registryId: row['registry_id'] as String,
        suggestedPurok: row['suggested_purok'] as String?,
        phone: (row['phone_number'] as String?)?.trim().isEmpty ?? true
            ? null
            : (row['phone_number'] as String).trim(),
        email: (row['email'] as String?)?.trim().isEmpty ?? true
            ? null
            : (row['email'] as String).trim(),
        alreadyRegistered: !isAvailable,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Duplicate-account guards (Issue 3, Decision D10) ─────────────────────────

  /// Global, case-insensitive full-name uniqueness check across the SP3
  /// registry (registered rows) AND existing accounts. Returns one of
  /// `'available'`, `'taken_account'`, `'taken_registry'`, or `'error'`
  /// (network/RPC failure — the caller should not hard-block on `'error'`,
  /// the server-side inserts remain the final authority).
  static Future<String> checkFullNameAvailability(String fullName) async {
    try {
      final result = await _client.rpc(
        'check_full_name_available',
        params: {'p_full_name': fullName.trim()},
      );
      final value = result as String?;
      if (value == 'taken_account' ||
          value == 'taken_registry' ||
          value == 'available') {
        return value!;
      }
      return 'error';
    } catch (_) {
      return 'error';
    }
  }

  /// TRUE when [email] is not already used by another account's
  /// `contact_email`. An empty string is treated as available (email is
  /// optional). Fails safe toward TRUE on error — the server-side insert
  /// still enforces uniqueness.
  static Future<bool> isEmailAvailable(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return true;
    try {
      final result = await _client.rpc(
        'check_email_available',
        params: {'p_email': trimmed},
      );
      return result as bool? ?? true;
    } catch (_) {
      return true;
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

  /// Throws if the current user's membership/account status is not active.
  /// Call at the top of any repository method that writes cooperative data.
  /// Message is status-aware: 'pending' (farmers awaiting admin approval)
  /// and 'suspended' (any role an admin has suspended) get distinct,
  /// accurate copy rather than one generic message.
  static Future<void> requireActiveMembership() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated.');

    // Previously, the status-fetch and the active/inactive enforcement were
    // both inside one try block, and the catch distinguished "real" status
    // exceptions from genuine connectivity failures by string-matching the
    // exception's toString() for 'pending approval'/'suspended'. Any other
    // unexpected failure here — including a missing user_roles row, which
    // would never match either substring — fell through to the same
    // cache-fallback path as an offline device, silently. Splitting the
    // fetch from the enforcement removes the need for that string-matching
    // entirely: enforcement now always runs on a successfully-fetched
    // status, so it can never be accidentally short-circuited by the catch
    // meant for connectivity. This is a fallback only — place_order()'s own
    // server-side status check (supabase_schema_place_order_admin_notify.sql)
    // is the actual authority regardless of what happens here.
    String status;
    bool pendingAck = false;
    String? reason;
    try {
      final row = await _client
          .from('user_roles')
          .select('status, pending_acknowledgement, rejection_reason, '
              'suspension_reason')
          .eq('user_id', userId)
          .single();
      status = row['status'] as String? ?? 'pending';
      pendingAck = row['pending_acknowledgement'] as bool? ?? false;
      reason = (row['suspension_reason'] as String?) ??
          (row['rejection_reason'] as String?);
    } catch (e) {
      debugPrint('AuthService.requireActiveMembership: could not reach '
          'user_roles ($e) — falling back to cached status');
      final cached = HiveService.getMemberStatus();
      if (cached != null && cached != 'active') {
        throw Exception(_statusMessage(cached, null));
      }
      if (HiveService.getPendingAcknowledgement()) {
        throw Exception(_statusMessage('active', null));
      }
      return;
    }

    if (status != 'active') {
      throw Exception(_statusMessage(status, reason));
    }
    // An approved member who has not yet tapped "Continue" (Decision D7)
    // does not have farmer write access yet.
    if (pendingAck) {
      throw Exception(_statusMessage('active', null));
    }
  }

  static String _statusMessage(String status, String? reason) {
    final r = (reason != null && reason.trim().isNotEmpty)
        ? ' Reason: ${reason.trim()}'
        : '';
    switch (status) {
      case 'suspended':
        return 'Your account has been suspended by the SP3 Administrator.$r '
            'Please contact the cooperative for assistance.';
      case 'rejected':
        return 'Your membership application was not approved.$r '
            'Open the app to review your details and resubmit.';
      case 'draft':
        return 'Please finish and submit your membership application first. '
            'Open the app and tap "Submit Application".';
      case 'active':
        // Only reached when pending_acknowledgement is still true.
        return 'Please open the app and tap "Continue" to activate your '
            'SP3 farmer access.';
      default: // 'pending'
        return 'Your membership is pending approval. '
            'This feature will be available once the SP3 Administrator '
            'approves your application.';
    }
  }

  // ── Application lifecycle wrappers (Issue 5) ─────────────────────────────────

  /// Applicant submits (or resubmits) their membership application:
  /// draft|rejected -> pending. Returns the attempt number just used
  /// (1..3). Throws with a human message if all attempts are spent or the
  /// status does not allow submitting.
  static Future<int> submitApplication() async {
    final result = await _client.rpc('submit_application');
    final used = (result as num?)?.toInt() ?? 1;
    await HiveService.saveMemberStatus('pending');
    return used;
  }

  /// Approved member taps "Continue" — clears the acknowledgement gate so
  /// farmer features unlock (Decision D7).
  static Future<void> acknowledgeMembership() async {
    await _client.rpc('acknowledge_membership');
    await HiveService.savePendingAcknowledgement(false);
    await HiveService.saveMemberStatus('active');
  }

  // ── Internal helpers ──────────────────────────────────────────────────────────

  /// Converts a username or email to the Supabase auth email format.
  /// Real emails (containing @) are passed through unchanged.
  /// Usernames are suffixed with @sagana.local.
  static String toAuthEmail(String identifier) {
    if (identifier.contains('@')) return identifier.toLowerCase();
    return '${identifier.toLowerCase()}@sagana.local';
  }

  /// Resolves whatever was typed (username or email) to the account's
  /// actual current Supabase Auth email — needed because a promoted
  /// contact email breaks the pure username@sagana.local formula for
  /// that one account. Falls back to the algorithmic toAuthEmail() if
  /// the RPC fails for any reason: a transient failure here must
  /// degrade to "promoted-email users temporarily can't log in by
  /// email" rather than blocking login for everyone.
  static Future<String> _resolveLoginEmail(String identifier) async {
    try {
      final result = await _client.rpc('resolve_login_email', params: {
        'p_identifier': identifier,
      });
      if (result is String && result.isNotEmpty) return result;
    } catch (_) {}
    return toAuthEmail(identifier);
  }
}

// ─── SP3 Registry Result ──────────────────────────────────────────────────────

class Sp3RegistryResult {
  final String registryId;
  final String? suggestedPurok;

  /// Official contact phone from the registry, if recorded. Auto-filled
  /// into the Register screen (editable).
  final String? phone;

  /// Official contact email from the registry, if recorded. Auto-filled
  /// into the Register screen (editable).
  final String? email;

  /// TRUE when the matched registry row is already marked registered —
  /// the person should log in instead of creating another account.
  final bool alreadyRegistered;

  const Sp3RegistryResult({
    required this.registryId,
    this.suggestedPurok,
    this.phone,
    this.email,
    this.alreadyRegistered = false,
  });
}