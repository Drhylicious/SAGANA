import 'dart:async' show unawaited;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../core/constants/app_constants.dart';
import '../../core/utils/input_validation_utils.dart';
import '../models/suspension_notice.dart';
import '../models/user_model.dart';
import 'account_status_watcher.dart';
import 'app_settings_service.dart';
import 'hive_service.dart';
import 'market_types_service.dart';

/// Thrown when a failed self-registration could not be rolled back. The
/// account may still exist, so the user is asked to contact the cooperative.
/// Carries no technical detail; the cause is logged where it happened.
class RegistrationNotCancelledException implements Exception {
  const RegistrationNotCancelledException();
}

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
      // suspension_reason wasn't previously selected here at all, so the
      // reason branch below always read null even though the column was
      // populated — the suspended-farmer message never actually showed
      // the admin's reason. Fixed alongside extending this guard to buyer.
      final statusRow = await _client
          .from('user_roles')
          .select(
            'status, must_change_password, pending_acknowledgement, suspension_reason, suspended_until',
          )
          .eq('user_id', response.user!.id)
          .single();

        memberStatus = statusRow['status'] as String? ?? 'active';
      if (role == 'farmer') {
        pendingAcknowledgement =
            statusRow['pending_acknowledgement'] as bool? ?? false;
      }

      // Blocked statuses — Suspended stops login with the recorded reason
      // (Issue 5 / Decision D17), for any role that can be suspended by
      // suspend_member/reactivate_member (Farmer and Buyer both write
      // through those same RPCs onto this same user_roles.status column —
      // this check was previously farmer-only, meaning a suspended buyer
      // could still log in freely; Admin's "Suspend Account" action was a
      // UI-only status flip with no actual access control behind it).
      // Draft/Pending/Rejected are farmer-application-only statuses and
      // still log in (they land on the Pending Applicant screen); a buyer
      // is always created directly as 'active', so 'suspended' is the
      // only non-'active' status that can ever occur for one. Inactive is
      // derived, never a stored value, and never blocks either role.
      if ((role == 'farmer' || role == 'buyer') &&
          memberStatus == 'suspended') {
          final reason = statusRow['suspension_reason'] as String?;
          final until = statusRow['suspended_until'] as String?;
          await _client.auth.signOut();
          // The login screen shows the red suspension notice from this.
          throw AccountSuspendedException(
            SuspensionNotice(
              reason: reason?.trim(),
              suspendedUntil: until == null
                  ? null
                  : DateTime.parse(until).toLocal(),
            ),
          );
        }
      mustChangePassword = statusRow['must_change_password'] as bool? ?? false;
    } catch (e) {
      // Re-throw a suspension (AccountSuspendedException); swallow only
      // genuine connectivity/shape failures (the original behaviour).
      if (e is AuthException || e is AccountSuspendedException) rethrow;
    }

    // Stamp last activity for the derived "Inactive" indicator (Decision
    // D8). Fire-and-forget — never let this block or fail a login.
    unawaited(_client.rpc('touch_last_active').catchError((_) {}));

    // Officer capability is a fixed role (every Admin module except the
    // Members tab) — no per-account permission scope to fetch (Decision D12).

    final infoResponse = await _client
        .from('user_information')
        .select('full_name, phone_number, profile_photo_url, username')
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

    // Market types and selling channels are database data; load them for this
    // user before the first screen needs a label.
    await MarketTypes.instance.refresh();
    MarketTypes.instance.start();

    AccountStatusWatcher.instance.start();

    return userModel;
  }

  // ── Self-Registration (Farmers + Buyers) ─────────────────────────────────────
  // Creates the sign-in identity, then hands everything else to the database:
  // register_account() decides the role/status, validates every field, writes
  // the profile rows and the fixed Farmer address, and issues the member
  // identifier in one transaction. Registration does not look the person up in
  // any registry; the full name is ordinary text and need not be unique.
  //
  // A new Farmer lands in 'pending' (it appears in Manager > Members at once);
  // a Buyer is 'active' and never enters the Members approval workflow.

  static Future<UserModel> register({
    required String username,
    required String password,
    required String fullName,
    required String role, // 'farmer' | 'buyer'
    String? phoneNumber, // optional; Philippine mobile
    String? contactEmail, // optional; stored as a contact address, not verified
    DateTime? dateOfBirth, // farmers — 18+ enforced here and by the database
    String? gender, // male | female | prefer_not_to_say
    // Farmers only. Region, province, city, barangay and postal code are fixed
    // by the database, so only these three are sent.
    String? street,
    String? building,
    String? houseNo,
  }) async {
    final trimmedName = fullName.trim();
    final normalizedUsername = normalizeUsername(username);
    final trimmedContactEmail = contactEmail?.trim();
    final trimmedPhone = phoneNumber?.trim();

    if (trimmedName.length < 2) {
      throw const AuthException('Please enter your full name.');
    }
    if (!isValidUsernameFormat(normalizedUsername)) {
      throw const AuthException(
        'Username must be 3 to 30 characters: letters, numbers, dots, '
        'underscores or hyphens.',
      );
    }

    // 18+ membership rule (farmers only — not Buyers).
    if (role == AppConstants.roleFarmer && dateOfBirth != null) {
      final now = DateTime.now();
      final eighteenthBirthday = DateTime(
        dateOfBirth.year + 18,
        dateOfBirth.month,
        dateOfBirth.day,
      );
      if (eighteenthBirthday.isAfter(now)) {
        throw const AuthException(
          'You must be at least 18 years old to register as a cooperative member.',
        );
      }
    }

    String? normalizedPhone;
    if (trimmedPhone != null && trimmedPhone.isNotEmpty) {
      normalizedPhone = normalizePhilippineMobile(trimmedPhone);
      if (normalizedPhone == null) {
        throw const AuthException(
          'Please enter a valid Philippine mobile number.',
        );
      }
    }
    if (trimmedContactEmail != null && trimmedContactEmail.isNotEmpty) {
      if (!isValidEmailFormat(trimmedContactEmail)) {
        throw const AuthException('Please enter a valid email address.');
      }
    }

    // Pre-checks, so an unavailable username or email is reported before any
    // sign-in identity exists. They are a convenience only: the database
    // re-checks username, email and phone and is the final authority, so a
    // check that cannot run never blocks registration.
    final usernameStatus = await checkUsernameAvailability(normalizedUsername);
    if (usernameStatus == UsernameStatus.taken) {
      throw const AuthException('This username is already taken.');
    }
    if (trimmedContactEmail != null && trimmedContactEmail.isNotEmpty) {
      final emailFree = await isEmailAvailable(trimmedContactEmail);
      if (!emailFree) {
        throw const AuthException(
          'This email address is already used by another account.',
        );
      }
      // The domain after the @ must be able to receive mail. This catches a
      // mistyped or made-up domain; it does not prove the mailbox exists or
      // is the person's (see supabase/functions/validate-contact). A lookup
      // that cannot run is not a "no".
      if (await checkEmailDomain(trimmedContactEmail) ==
          EmailDomainStatus.noMailServer) {
        throw const AuthException(
          'This email address cannot receive mail. Please check it for '
          'typing mistakes.',
        );
      }
    }

    final authEmail = toAuthEmail(normalizedUsername);

    final response = await _client.auth.signUp(
      email: authEmail,
      password: password,
    );

    if (response.user == null) {
      throw const AuthException('Registration failed. Please try again.');
    }

    final userId = response.user!.id;

    try {
      final result = await _client.rpc(
        'register_account',
        params: {
          'p_role': role,
          'p_full_name': trimmedName,
          'p_username': normalizedUsername,
          'p_phone_number': normalizedPhone,
          'p_contact_email':
              (trimmedContactEmail != null && trimmedContactEmail.isNotEmpty)
              ? trimmedContactEmail
              : null,
          'p_date_of_birth': role == AppConstants.roleFarmer
              ? dateOfBirth?.toIso8601String().split('T').first
              : null,
          'p_gender': role == AppConstants.roleFarmer ? gender : null,
          'p_street': role == AppConstants.roleFarmer ? street?.trim() : null,
          'p_building': role == AppConstants.roleFarmer
              ? building?.trim()
              : null,
          'p_house_no': role == AppConstants.roleFarmer
              ? houseNo?.trim()
              : null,
        },
      );

      final data = result is Map ? result : const <String, dynamic>{};
      return UserModel(
        id: userId,
        email: authEmail,
        role: role,
        status: data['status'] as String? ?? 'pending',
        fullName: trimmedName,
        phoneNumber: normalizedPhone,
      );
    } catch (e) {
      // Technical detail stays in the log only.
      debugPrint('AuthService.register failed after signup: $e');
      // Roll back the account created above, so its username and email are
      // freed and no unusable account is left behind.
      final rolledBack = await _cancelFailedRegistration();
      await _client.auth.signOut();
      if (!rolledBack) throw const RegistrationNotCancelledException();
      // The database's own validation messages (raised with RAISE EXCEPTION,
      // SQLSTATE P0001) are written for people; anything else is not.
      if (e is PostgrestException && e.code == 'P0001' && e.message.isNotEmpty) {
        throw AuthException(e.message);
      }
      rethrow;
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────────

  static Future<void> logout() async {
    AccountStatusWatcher.instance.stop();
    MarketTypes.instance.stop();
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
      final result = await _client.rpc(
        'can_use_otp_reset',
        params: {'p_identifier': identifier.trim()},
      );
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
    await _client.rpc(
      'request_password_assistance',
      params: {'p_username': username.trim()},
    );
  }

  // ── Check username availability ───────────────────────────────────────────────

  /// Asks the database whether [username] can be used. The database is the one
  /// place that can answer: it sees every account (a signed-out caller cannot
  /// read account rows) and applies the same case-insensitive rule the unique
  /// index enforces. [UsernameStatus.error] means the check could not run.
  static Future<UsernameStatus> checkUsernameAvailability(
    String username,
  ) async {
    try {
      final result = await _client.rpc(
        'check_username_available',
        params: {'p_username': username.trim()},
      );
      switch (result) {
        case 'available':
          return UsernameStatus.available;
        case 'taken':
          return UsernameStatus.taken;
        case 'invalid':
          return UsernameStatus.invalid;
      }
      return UsernameStatus.error;
    } catch (_) {
      return UsernameStatus.error;
    }
  }

  // ── Duplicate-contact guards ──────────────────────────────────────────────────
  // Full names are ordinary text and are NOT checked for duplicates: two
  // people may share a name. Only the username, email and phone number are
  // unique.

  /// Asks the validate-contact Edge Function whether the domain of [email]
  /// can receive mail at all (it publishes a mail server). This is a check of
  /// the DOMAIN only: it cannot tell whether the mailbox exists or whether the
  /// person owns it. [EmailDomainStatus.unknown] means the check could not run
  /// (offline, function not deployed, DNS trouble) and must not block anyone.
  static Future<EmailDomainStatus> checkEmailDomain(String email) async {
    try {
      final response = await _client.functions
          .invoke('validate-contact', body: {'email': email.trim()})
          .timeout(const Duration(seconds: 6));
      final data = response.data;
      final status = data is Map ? data['status'] : null;
      if (status == 'ok') return EmailDomainStatus.ok;
      if (status == 'no_mail_server') return EmailDomainStatus.noMailServer;
      return EmailDomainStatus.unknown;
    } catch (_) {
      return EmailDomainStatus.unknown;
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

  /// Phone counterpart of [isEmailAvailable]: false when another account
  /// already has this phone number. Fails open, like the email check.
  static Future<bool> isPhoneAvailable(String phone) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return true;
    try {
      final result = await _client.rpc(
        'check_phone_available',
        params: {'p_phone': trimmed},
      );
      return result as bool? ?? false;
    } catch (_) {
      // Fail closed: if the check cannot run, the number is treated as taken
      // and registration asks for admin help, rather than skipping the check.
      return false;
    }
  }

  /// Deletes the account created by the registration attempt that just
  /// failed. Runs server-side (cancel_failed_registration) and only for the
  /// signed-in user. Best-effort: a failure is logged, not thrown, so the
  /// original error still reaches the user.
  static Future<bool> _cancelFailedRegistration() async {
    try {
      await _client.rpc('cancel_failed_registration');
      return true;
    } catch (e) {
      debugPrint('AuthService: could not roll back failed registration: $e');
      return false;
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
          .select(
            'status, pending_acknowledgement, rejection_reason, '
            'suspension_reason',
          )
          .eq('user_id', userId)
          .single();
      status = row['status'] as String? ?? 'pending';
      pendingAck = row['pending_acknowledgement'] as bool? ?? false;
      reason =
          (row['suspension_reason'] as String?) ??
          (row['rejection_reason'] as String?);
    } catch (e) {
      debugPrint(
        'AuthService.requireActiveMembership: could not reach '
        'user_roles ($e) — falling back to cached status',
      );
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
        return 'Your account has been suspended by the SP3 Manager.$r '
            'Please contact the cooperative for assistance.';
      case 'rejected':
        return 'Your membership application was disapproved.$r '
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
            'This feature will be available once the SP3 Manager '
            'approves your application.';
    }
  }

  // ── Application lifecycle wrappers (Issue 5) ─────────────────────────────────

  /// Applicant submits (or resubmits) their membership application:
  /// draft|rejected -> pending. Returns the attempt number just used
  /// (no limit on resubmissions). Throws with a human message if the
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
      final result = await _client.rpc(
        'resolve_login_email',
        params: {'p_identifier': identifier},
      );
      if (result is String && result.isNotEmpty) return result;
    } catch (_) {}
    return toAuthEmail(identifier);
  }
}

// ─── Username availability ────────────────────────────────────────────────────

/// Result of [AuthService.checkUsernameAvailability].
/// [invalid] = not 3-30 characters of letters, numbers, dots, underscores or
/// hyphens. [error] = the check could not run (offline, server error); it is
/// not a verdict, and the database still decides at registration.
enum UsernameStatus { available, taken, invalid, error }

/// Result of [AuthService.checkEmailDomain]. [ok] = the domain can receive
/// mail (not proof the mailbox exists or is the person's). [noMailServer] = it
/// cannot. [unknown] = the check could not run.
enum EmailDomainStatus { ok, noMailServer, unknown }