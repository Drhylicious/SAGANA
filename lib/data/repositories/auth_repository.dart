import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/hive_service.dart';

class AuthRepository {
  // ─── Login ───────────────────────────────────────────────────────────────────

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    return AuthService.login(email: email, password: password);
  }

  // ─── Register ────────────────────────────────────────────────────────────────

  Future<UserModel> register({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
    required String role,
    String? sitio,
  }) async {
    return AuthService.register(
      email: email,
      password: password,
      fullName: fullName,
      phoneNumber: phoneNumber,
      role: role,
      sitio: sitio,
    );
  }

  // ─── Logout ──────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await AuthService.logout();
  }

  // ─── Password Reset ──────────────────────────────────────────────────────────

  Future<void> sendPasswordReset(String email) async {
    await AuthService.sendPasswordReset(email);
  }

  // ─── Cached User (Offline) ───────────────────────────────────────────────────

  UserModel? getCachedUser() {
    final userId = HiveService.getUserId();
    final email = HiveService.getUserEmail();
    final role = HiveService.getUserRole();
    final name = HiveService.getUserName();

    if (userId == null || email == null || role == null) return null;

    return UserModel(
      id: userId,
      email: email,
      role: role,
      status: 'active',
      fullName: name,
    );
  }

  // ─── Session Check ───────────────────────────────────────────────────────────

  bool get isLoggedIn => AuthService.isLoggedIn;

  Future<String?> getCurrentUserRole() => AuthService.getCurrentUserRole();
}
