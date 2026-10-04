import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/farmer_crop_model.dart' show FarmerCropModel, marketTypeLabelFor;
import '../../data/repositories/crop_repository.dart';
import 'management_modal.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EditCropSheet
// Shown from Crop Roster's 3-dot menu, replacing the old Delete Crop flow.
// Crop Name / Category / Market Type are locked (read-only display) — only
// the crop's own photo can be changed. Saves to farmer_crops.photo_url, the
// same field FarmerCropModel.displayImageUrl already reads first (ahead of
// crop_master.image_url).
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

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PhotoSourceSheet(),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _pickedImageBytes = bytes;
      _pickedImageExt =
          picked.name.contains('.') ? picked.name.split('.').last.toLowerCase() : 'jpg';
    });
  }

  Future<void> _save() async {
    if (_pickedImageBytes == null) return;
    setState(() => _isSaving = true);
    final photoUrl = await widget.repo
        .uploadCropPhoto(_pickedImageBytes!, _pickedImageExt ?? 'jpg');
    if (photoUrl == null) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not upload photo. Please try again.',
                style: GoogleFonts.inter(fontSize: 13)),
          ),
        );
      }
      return;
    }
    final saved = await widget.repo
        .updateCropPhoto(widget.crop.id, widget.crop.cropName, photoUrl);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context, true);
    } else {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save photo. Please try again.',
              style: GoogleFonts.inter(fontSize: 13)),
        ),
      );
    }
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
          Text('Photo',
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _isSaving ? null : _pickImage,
            child: Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppConstants.offWhite,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: AppConstants.outline.withValues(alpha: 0.20)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _pickedImageBytes != null
                  ? Image.memory(_pickedImageBytes!, fit: BoxFit.cover)
                  : (crop.hasDisplayImage
                      ? Image.network(crop.displayImageUrl!, fit: BoxFit.cover)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_photo_alternate_outlined,
                                color: AppConstants.onSurfaceVariant),
                            const SizedBox(height: 4),
                            Text('Tap to add a photo',
                                style: GoogleFonts.inter(
                                    fontSize: 12, color: AppConstants.onSurfaceVariant)),
                          ],
                        )),
            ),
          ),
          if (_pickedImageBytes != null) ...[
            const SizedBox(height: 6),
            Text('Tap the photo again to choose a different one.',
                style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
          ],
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

// Mirrors CropCatalogSheet's own _PhotoSourceSheet exactly (same
// camera/gallery choice, same styling) — kept as its own private copy per
// this codebase's existing convention (each screen that picks a photo owns
// its own source-sheet widget rather than sharing one).
class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded, color: AppConstants.primaryGreen),
                title: Text('Take Photo', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppConstants.primaryGreen),
                title: Text('Upload Photo', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
