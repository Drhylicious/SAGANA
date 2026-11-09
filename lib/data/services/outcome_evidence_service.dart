import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A photo chosen on the device, not uploaded yet.
class PickedPhoto {
  final Uint8List bytes;
  final String extension;
  const PickedPhoto(this.bytes, this.extension);
}

/// Uploads and reads outcome evidence photos in the PRIVATE `program_evidence`
/// bucket. A photo lives in its uploader's own folder (`<user id>/<file>`), and
/// is shown through a short-lived signed link, never a public URL.
class OutcomeEvidenceService {
  static const bucket = 'program_evidence';
  final SupabaseClient _client = Supabase.instance.client;

  static String contentTypeFor(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  /// Uploads one photo and returns its storage path. Throws if it fails.
  Future<String> upload(Uint8List bytes, String extension) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');
    final ext = extension.isEmpty ? 'jpg' : extension.toLowerCase();
    // 0x100000000 (2^32) written out: in the browser build "1 << 32" is evaluated with 32-bit shifts and
    // becomes 0, which made every photo upload fail with "max must be in range 0 < max <= 2^32, was 0".
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(0x100000000)}.$ext';
    final path = '$uid/$name';
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentTypeFor(ext)),
        );
    return path;
  }

  /// Best effort: removes photos that were uploaded but never submitted.
  Future<void> removeAll(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _client.storage.from(bucket).remove(paths);
    } catch (_) {}
  }

  /// Signed links for [paths], keyed by path. A photo that cannot be signed is
  /// simply missing from the map.
  Future<Map<String, String>> signedUrls(List<String> paths) async {
    if (paths.isEmpty) return {};
    final out = <String, String>{};
    // One link per photo: a photo that cannot be signed is skipped, it does
    // not stop the others from showing.
    await Future.wait(
      paths.map((p) async {
        try {
          out[p] = await _client.storage.from(bucket).createSignedUrl(p, 3600);
        } catch (_) {}
      }),
    );
    return out;
  }
}
