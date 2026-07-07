import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import 'hive_service.dart';

class AuthService {
  AuthService._();

  static final SupabaseClient _client = Supabase.instance.client;

  // ─── Session Checks ──────────────────────────────────────────────────────────

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
      // Fall back to Hive cache when offline
      return HiveService.getUserRole();
    }
  }

  // ─── Login ───────────────────────────────────────────────────────────────────

  static Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    if (response.user == null) {
      throw const AuthException('Login failed. Please check your credentials.');
    }

    final role = await getCurrentUserRole();
    if (role == null) {
      throw const AuthException('Account role not found. Contact SP3 Cooperative.');
    }

    // Fetch user information
    final infoResponse = await _client
        .from('user_information')
        .select('full_name, phone_number, profile_photo_url, sitio')
        .eq('user_id', response.user!.id)
        .maybeSingle();

    final userModel = UserModel(
      id: response.user!.id,
      email: response.user!.email ?? email,
      role: role,
      status: 'active',
      fullName: infoResponse?['full_name'] as String?,
      phoneNumber: infoResponse?['phone_number'] as String?,
      profilePhotoUrl: infoResponse?['profile_photo_url'] as String?,
      sitio: infoResponse?['sitio'] as String?,
    );

    // Cache to Hive for offline access
    await HiveService.saveUserSession(
      userId: userModel.id,
      email: userModel.email,
      role: userModel.role,
      fullName: userModel.fullName,
    );

    return userModel;
  }

  // ─── Register ────────────────────────────────────────────────────────────────

  static Future<UserModel> register({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
    required String role,
    String? sitio,
  }) async {
    // 1. Create auth user
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
    );

    if (response.user == null) {
      throw const AuthException('Registration failed. Please try again.');
    }

    final userId = response.user!.id;

    try {
      // 2. Insert user_roles
      await _client.from('user_roles').insert({
        'user_id': userId,
        'role': role,
        'status': role == 'farmer' ? 'pending' : 'active',
      });

      // 3. Insert user_information
      await _client.from('user_information').insert({
        'user_id': userId,
        'full_name': fullName.trim(),
        'phone_number': phoneNumber.trim(),
        'sitio': sitio,
      });

      // 4. Insert role-specific profile
      if (role == 'farmer') {
        await _client.from('farmer_profiles').insert({
          'user_id': userId,
        });
      } else if (role == 'buyer') {
        await _client.from('buyer_profiles').insert({
          'user_id': userId,
        });
      }

      return UserModel(
        id: userId,
        email: email.trim(),
        role: role,
        status: role == 'farmer' ? 'pending' : 'active',
        fullName: fullName.trim(),
        phoneNumber: phoneNumber.trim(),
        sitio: sitio,
      );
    } catch (e) {
      // Clean up auth user if profile creation fails
      await _client.auth.signOut();
      rethrow;
    }
  }

  // ─── Logout ──────────────────────────────────────────────────────────────────

  static Future<void> logout() async {
    await _client.auth.signOut();
    await HiveService.clearUserSession();
  }

  // ─── Password Reset ──────────────────────────────────────────────────────────

  static Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  // ─── Error Parser ────────────────────────────────────────────────────────────

  static String parseAuthError(Object error) {
    if (error is AuthException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('invalid login credentials') ||
          msg.contains('invalid credentials')) {
        return 'Incorrect email or password. Please try again.';
      }
      if (msg.contains('email not confirmed')) {
        return 'Please verify your email address before logging in.';
      }
      if (msg.contains('user already registered') ||
          msg.contains('already been registered')) {
        return 'An account with this email already exists.';
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
}
