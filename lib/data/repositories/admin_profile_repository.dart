import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_profile_model.dart';
import '../services/profile_photo_service.dart';

/// Repository for the logged-in admin's own profile — user_information +
/// admin_profiles, joined at this layer. Every method operates on the
/// current auth user's own row only; there is no "view another admin's
/// profile" concept here.
class AdminProfileRepository {
  final SupabaseClient _client = Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<AdminProfileModel?> fetchProfile() async {
    try {
      final infoRow = await _client
          .from('user_information')
          .select('full_name, phone_number, profile_photo_url, sitio')
          .eq('user_id', _userId)
          .maybeSingle();
      if (infoRow == null) return null;

      final adminRow = await _client
          .from('admin_profiles')
          .select('employee_id, position, department, created_at')
          .eq('user_id', _userId)
          .maybeSingle();

      return AdminProfileModel(
        userId: _userId,
        email: _client.auth.currentUser?.email ?? '',
        fullName: infoRow['full_name'] as String? ?? 'Admin',
        phoneNumber: infoRow['phone_number'] as String?,
        profilePhotoUrl: infoRow['profile_photo_url'] as String?,
        sitio: infoRow['sitio'] as String?,
        employeeId: adminRow?['employee_id'] as String?,
        position: adminRow?['position'] as String?,
        department: adminRow?['department'] as String?,
        adminSince: adminRow?['created_at'] != null
            ? DateTime.tryParse(adminRow!['created_at'] as String)
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> updateBasicInfo({
    required String fullName,
    String? phoneNumber,
    String? sitio,
  }) async {
    await _client.from('user_information').update({
      'full_name': fullName.trim(),
      'phone_number': phoneNumber?.trim(),
      'sitio': sitio,
    }).eq('user_id', _userId);
  }

  /// Uploads a new photo via the shared profile_photo_service and updates
  /// user_information.profile_photo_url. Returns the new public URL, or
  /// null if the upload failed — the screen decides how to inform the
  /// admin rather than this throwing, since a failed photo upload is a
  /// retryable, non-critical action, not a financial write.
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

  /// Clears the photo reference so the UI falls back to initials. Does
  /// not delete the storage object — same laxness already established
  /// for photo replacement elsewhere in the app.
  Future<void> removePhoto() async {
    await _client
        .from('user_information')
        .update({'profile_photo_url': null}).eq('user_id', _userId);
  }
}