import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/models/farmer_crop_model.dart' show FarmerCropModel, marketTypeLabelFor;
import '../../data/repositories/crop_repository.dart';
import 'crop_photo_capture.dart';
import 'management_modal.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EditCropSheet
// Shown from Crop Roster's 3-dot menu, replacing the old Delete Crop flow.
// Crop Name / Category / Market Type are locked (read-only display) — only
// the crop's own photo can be changed. The photo is taken with the camera only
// (no gallery or file choice) and saved to farmer_crops.photo_url — the
// Farmer's own picture of their own crop. The Crop Master image is never shown
// here and never takes its place.
// ─────────────────────────────────────────────────────────────────────────────

Future<bool?> showEditCropSheet(
  BuildContext context, {
  required CropRepository repo,
  required FarmerCropModel crop,
}) {
  return showManagementModal<bool>(
    context: context,
    builder: (_) => _EditCropModal(repo: repo, crop: crop),
  );
}

class _EditCropModal extends StatefulWidget {
  final CropRepository repo;
  final FarmerCropModel crop;

  const _EditCropModal({required this.repo, required this.crop});

  @override
  State<_EditCropModal> createState() => _EditCropModalState();
}

class _EditCropModalState extends State<_EditCropModal> {
  Uint8List? _pickedImageBytes;
  String? _pickedImageExt;
  bool _isSaving = false;

  Future<void> _takePhoto() async {
    final photo = await captureCropPhoto(context);
    if (photo == null || !mounted) return;
    setState(() {
      _pickedImageBytes = photo.bytes;
      _pickedImageExt = photo.extension;
    });
  }

  Future<void> _save() async {
    if (_pickedImageBytes == null) return;
    setState(() => _isSaving = true);
    final result = await widget.repo.setCropPhoto(
      bytes: _pickedImageBytes!,
      fileExtension: _pickedImageExt ?? 'jpg',
      cropId: widget.crop.id,
      cropName: widget.crop.cropName,
    );
    if (!mounted) return;
    if (result.failed) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save photo. Please try again.',
              style: GoogleFonts.inter(fontSize: 13)),
        ),
      );
      return;
    }
    if (result.queued) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).savedOnDeviceSyncLater,
              style: GoogleFonts.inter(fontSize: 13)),
        ),
      );
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final crop = widget.crop;
    return ManagementModalShell(
      title: 'Edit Crop',
      subtitle: 'Name, category, and market type are set by SP3 and can\'t be changed here.',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LockedField(label: 'Crop name', value: crop.cropName),
          const SizedBox(height: 12),
          _LockedField(label: 'Category', value: crop.category),
          const SizedBox(height: 12),
          _LockedField(
            label: 'Market type',
            value: crop.cropMasterId != null
                ? marketTypeLabelFor(crop.cropType)
                : 'Pending approval',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Photo of your crop',
                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
              const SizedBox(width: 8),
              if (!crop.hasPhoto && _pickedImageBytes == null)
                const PhotoRequiredBadge(compact: true),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _isSaving ? null : _takePhoto,
            child: Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppConstants.offWhite,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                  color: (!crop.hasPhoto && _pickedImageBytes == null)
                      ? AppConstants.errorRed.withValues(alpha: 0.45)
                      : AppConstants.outline.withValues(alpha: 0.20),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _pickedImageBytes != null
                  ? Image.memory(_pickedImageBytes!, fit: BoxFit.cover)
                  : (crop.hasPhoto
                      ? Image.network(crop.photoUrl!, fit: BoxFit.cover)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.photo_camera_outlined,
                                size: 30, color: AppConstants.errorRed),
                            const SizedBox(height: 6),
                            Text('Tap to take a photo',
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppConstants.errorRed)),
                          ],
                        )),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 14, color: AppConstants.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _pickedImageBytes != null || crop.hasPhoto
                      ? 'Taken with your camera. Tap the photo to retake it.'
                      : 'Take a photo of your actual crop with your camera. It is needed to '
                          'sell on the Marketplace, to the Cooperative, or through Market '
                          'Linking. You can record harvests and Informal Sales without it.',
                  style: GoogleFonts.inter(
                      fontSize: 11.5, height: 1.4, color: AppConstants.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: 'Save Photo',

        isLoading: _isSaving,
        onPrimary: _pickedImageBytes == null ? null : _save,
      ),
    );
  }
}

class _LockedField extends StatelessWidget {
  final String label;
  final String value;
  const _LockedField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppConstants.offWhite,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: AppConstants.outline.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(value,
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w600, color: AppConstants.charcoal)),
              ),
              Icon(Icons.lock_outline_rounded,
                  size: 16, color: AppConstants.outline.withValues(alpha: 0.60)),
            ],
          ),
        ),
      ],
    );
  }
}

