import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uploads the photo that proves a handover or a staff-assisted completion, to the signed-in
/// staff member's own folder of the photo bucket, and returns its public URL.
///
/// The database refuses the step without a photo URL, so a failed upload stops the action.
Future<String> uploadOrderEvidence({
  SupabaseClient? client,
  required String kind,
  required String orderId,
  required Uint8List bytes,
  required String extension,
}) async {
  final c = client ?? Supabase.instance.client;
  final userId = c.auth.currentUser!.id;
  final path =
      '$userId/order_${kind}_${orderId}_${DateTime.now().millisecondsSinceEpoch}.$extension';
  await c.storage
      .from('crop_images')
      .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
  return c.storage.from('crop_images').getPublicUrl(path);
}
