import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_constants.dart';
import '../../data/repositories/crop_repository.dart';
import 'app_dialog.dart';
import 'app_toast.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Farmer crop photos — camera only
//
// A Farmer's crop photo is a picture of their own actual crop, taken at the
// time. It is always captured with the device camera: there is no gallery or
// file option anywhere. (On a desktop browser the "camera" is whatever the
// browser offers for a capture request; a phone opens its camera app.)
// The Crop Master image is a reference for the catalog and never takes the
// place of this photo.
// ─────────────────────────────────────────────────────────────────────────────

class CapturedCropPhoto {
  final Uint8List bytes;
  final String extension;
  const CapturedCropPhoto(this.bytes, this.extension);
}

/// Opens the camera and returns the photo taken, or null if the Farmer closed
/// the camera. A camera that cannot be opened (permission denied, no camera)
/// shows a short message and also returns null.
Future<CapturedCropPhoto?> captureCropPhoto(BuildContext context) async {
  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera, // the camera only: there is no gallery or file source
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final ext = picked.name.contains('.')
        ? picked.name.split('.').last.toLowerCase()
        : 'jpg';
    return CapturedCropPhoto(bytes, ext);
  } catch (_) {
    if (context.mounted) {
      AppToast.show(
        context,
        'The camera could not be opened. Allow camera access and try again.',
        isError: true,
      );
    }
    return null;
  }
}

/// The red "Photo Required" mark shown on a crop that has no actual photo yet.
class PhotoRequiredBadge extends StatelessWidget {
  final bool compact;
  const PhotoRequiredBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        color: AppConstants.errorRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(color: AppConstants.errorRed.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_camera_rounded,
              size: compact ? 10 : 12, color: AppConstants.errorRed),
          const SizedBox(width: 4),
          Text(
            'Photo Required',
            style: GoogleFonts.inter(
              fontSize: compact ? 9.5 : 10.5,
              fontWeight: FontWeight.w700,
              color: AppConstants.errorRed,
            ),
          ),
        ],
      ),
    );
  }
}

/// True when a server message is the database's "photo required" refusal.
bool isPhotoRequiredError(Object error) =>
    error.toString().contains('PHOTO_REQUIRED');

/// Asks the Farmer to take the missing crop photo before selling, and saves it.
/// Returns the saved photo's url, or null if they cancelled or it could not be
/// saved (a message is shown in that case).
///
/// [why] completes "To <why>, ..." — e.g. "list this on the Marketplace".
Future<String?> requireCropPhotoToSell(
  BuildContext context, {
  required CropRepository repo,
  required String cropId,
  required String cropName,
  required String why,
}) async {
  final take = await AppDialog.show<bool>(
    context: context,
    child: _PhotoRequiredDialog(cropName: cropName, why: why),
  );
  if (take != true || !context.mounted) return null;

  final photo = await captureCropPhoto(context);
  if (photo == null || !context.mounted) return null;

  try {
    // Online on purpose: the sale is checked by the database right after, so a
    // photo that is only queued on the device would not help yet.
    await repo.setCropPhotoOnline(
      bytes: photo.bytes,
      fileExtension: photo.extension,
      cropId: cropId,
      cropName: cropName,
    );
  } catch (_) {
    if (context.mounted) {
      AppToast.show(
        context,
        'Could not save the photo. Check your connection and try again.',
        isError: true,
      );
    }
    return null;
  }
  return repo.fetchCropPhotoUrl(cropId);
}

class _PhotoRequiredDialog extends StatelessWidget {
  final String cropName;
  final String why;
  const _PhotoRequiredDialog({required this.cropName, required this.why});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppConstants.errorRed.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.photo_camera_rounded,
                  color: AppConstants.errorRed, size: 24),
            ),
            const SizedBox(height: 14),
            Text('Photo Required',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'To $why, take a photo of your actual $cropName. '
              'It is taken with your camera, and it stays on this crop for every batch.',
              style: GoogleFonts.inter(
                  fontSize: 13.5, height: 1.45, color: AppConstants.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: cs.outline.withValues(alpha: 0.30)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Not Now',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700, color: cs.onSurface)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.photo_camera_rounded, size: 18),
                    label: Text('Take Photo',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
