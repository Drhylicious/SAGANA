import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/services/outcome_evidence_service.dart';
import 'app_toast.dart';

/// Take photos with the camera or choose them from the gallery, up to [max].
/// Photos are only held here; the screen uploads them when the form is sent.
class OutcomePhotoPicker extends StatelessWidget {
  final List<PickedPhoto> photos;
  final int max;
  final ValueChanged<List<PickedPhoto>> onChanged;
  final bool hasError;

  const OutcomePhotoPicker({
    super.key,
    required this.photos,
    required this.onChanged,
    this.max = 5,
    this.hasError = false,
  });

  Future<void> _add(BuildContext context, ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    try {
      final picker = ImagePicker();
      final List<XFile> picked;
      if (source == ImageSource.gallery) {
        final room = max - photos.length;
        if (room <= 0) return;
        picked = await picker.pickMultiImage(imageQuality: 80, maxWidth: 1600);
      } else {
        final one = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 80,
          maxWidth: 1600,
        );
        picked = one == null ? [] : [one];
      }
      if (picked.isEmpty) return;
      final next = [...photos];
      for (final x in picked) {
        if (next.length >= max) break;
        final bytes = await x.readAsBytes();
        final ext = x.name.contains('.')
            ? x.name.split('.').last.toLowerCase()
            : 'jpg';
        next.add(PickedPhoto(bytes, ext));
      }
      if (picked.length + photos.length > max && context.mounted) {
        AppToast.show(context, l10n.outcPhotoMax(max), isError: true);
      }
      onChanged(next);
    } catch (_) {
      if (context.mounted) {
        AppToast.show(context, l10n.outcPhotoPickFailed, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final full = photos.length >= max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: full ? null : () => _add(context, ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(l10n.outcPhotoCamera),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: full ? null : () => _add(context, ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(l10n.outcPhotoGallery),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l10n.outcPhotoCount(photos.length, max),
          style: GoogleFonts.inter(
            fontSize: 11,
            color: hasError ? AppConstants.errorRed : cs.onSurfaceVariant,
          ),
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < photos.length; i++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                      child: Image.memory(
                        photos[i].bytes,
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () {
                          final next = [...photos]..removeAt(i);
                          onChanged(next);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
