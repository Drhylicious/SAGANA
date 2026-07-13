import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared profile-photo upload logic for both Admin and Farmer profiles —
/// a standalone, role-agnostic function rather than duplicated inside
/// either role's repository, since the underlying operation (upload to
/// the profile_photos bucket, return the public URL) is identical
/// regardless of who's uploading. Mirrors the exact Storage upload idiom
/// already established in ListingRepository.uploadListingPhoto() —
/// uploadBinary with upsert, then getPublicUrl.
///
/// Does not delete the previous photo on replace — same as the existing
/// listing-photo convention elsewhere in the app (each upload gets a
/// unique timestamped path; old objects are left orphaned rather than
/// actively cleaned up).
Future<String?> uploadProfilePhoto({
  required SupabaseClient client,
  required String userId,
  required Uint8List imageBytes,
  required String fileExtension,
}) async {
  try {
    final path = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    await client.storage.from('profile_photos').uploadBinary(
          path,
          imageBytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return client.storage.from('profile_photos').getPublicUrl(path);
  } catch (_) {
    return null;
  }
}