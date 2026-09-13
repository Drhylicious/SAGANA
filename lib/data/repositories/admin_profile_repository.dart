import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_profile_model.dart';
import '../services/profile_photo_service.dart';

/// Repository for the logged-in admin's own profile — user_information +
/// admin_profiles, joined at this layer. Every method operates on the
/// current auth user's own row only.
class AdminProfileRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<AdminProfileModel?> fetchProfile() async {
    try {
      final infoRow = await _client
          .from('user_information')
          .select('full_name, phone_number, profile_photo_url, purok')
          .eq('user_id', _userId)
          .maybeSingle();
      if (infoRow == null) return null;

      final adminRow = await _client
          .from('admin_profiles')
          .select('employee_id, position, department, created_at')
          .eq('user_id', _userId)
          .maybeSingle();

      // Cosmetic fix (verification pass): an Officer's admin_profiles row
      // (Phase D-2 — grants operational RPC/RLS access) has no
      // employee_id — their real EMP-### lives on officer_profiles. Fall
      // back to it so an Officer viewing this shared profile screen sees
      // their actual Employee ID / position instead of blanks. No-op for
      // a real Admin (no officer_profiles row).
      Map<String, dynamic>? officerRow;
      try {
        officerRow = await _client
            .from('officer_profiles')
            .select('employee_id, position')
            .eq('user_id', _userId)
            .maybeSingle();
      } catch (_) {}

      return AdminProfileModel(
        userId: _userId,
        email: _client.auth.currentUser?.email ?? '',
        fullName: infoRow['full_name'] as String? ?? 'Admin',
        phoneNumber: infoRow['phone_number'] as String?,
        profilePhotoUrl: infoRow['profile_photo_url'] as String?,
        purok: infoRow['purok'] as String?,
        employeeId: (adminRow?['employee_id'] as String?) ??
            (officerRow?['employee_id'] as String?),
        position: (adminRow?['position'] as String?) ??
            (officerRow?['position'] as String?),
        department: adminRow?['department'] as String?,
        adminSince: adminRow?['created_at'] != null
            ? DateTime.tryParse(adminRow!['created_at'] as String)
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Count of price_records this admin has personally entered — confirmed
  /// attributable via price_records.recorded_by, already permitted by the
  /// "authenticated users read" SELECT policy.
  Future<int> fetchPricesUpdatedCount() async {
    try {
      final rows =
          await _client.from('price_records').select('id').eq('recorded_by', _userId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// Count of broadcasts this admin has personally sent — confirmed
  /// attributable via broadcast_logs.created_by, already permitted by the
  /// "Admin full access to broadcast_logs" policy.
  Future<int> fetchBroadcastsSentCount() async {
    try {
      final rows =
          await _client.from('broadcast_logs').select('id').eq('created_by', _userId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> updateBasicInfo({
    required String fullName,
    String? phoneNumber,
    String? purok,
  }) async {
    await _client.from('user_information').update({
      'full_name': fullName.trim(),
      'phone_number': phoneNumber?.trim(),
      'purok': purok,
    }).eq('user_id', _userId);
  }

  Future<String?> updatePhoto({
    required Uint8List imageBytes,
    required String fileExtension,
  }) async {
    final url = await uploadProfilePhoto(
      client: _client,
      userId: _userId,
      imageBytes: imageBytes,
      fileExtension: fileExtension,
    );
    if (url == null) return null;

    try {
      await _client
          .from('user_information')
          .update({'profile_photo_url': url}).eq('user_id', _userId);
      return url;
    } catch (_) {
      return null;
    }
  }

  Future<void> removePhoto() async {
    await _client
        .from('user_information')
        .update({'profile_photo_url': null}).eq('user_id', _userId);
  }
}