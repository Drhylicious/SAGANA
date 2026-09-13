import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/sagana_colors.dart';
import 'app_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ManagementModal
// Centered, card-style overlay for management-style interactions across
// roles — replaces showModalBottomSheet() across Admin's Inventory, Crop
// Management, Program Management, Loan Item Management, and Price
// Management, and Buyer's Settings screen (language/theme pickers). The
// original comment predated Buyer's usage and undersold what this covers.
//
// Built on AppDialog.show(), so it inherits the existing fade + spring-scale
// entrance instead of introducing a new animation system. Three shapes share
// one shell (ManagementModalShell):
//   - showManagementModal()      — general entry point, caller supplies the
//     full StatefulBuilder + shell composition (used when the caller needs
//     tight control over its own isSaving/local state, matching how the
//     original bottom sheets were built).
//   - ManagementModalShell       — header (title/subtitle + close ✕) +
//     scrollable body + optional pinned footer.
//   - ManagementModalActions     — standard Cancel / Primary footer row.
// ─────────────────────────────────────────────────────────────────────────────

/// Opens [child] inside the centered modal transition. This is the direct
/// replacement for `showModalBottomSheet(context: ..., builder: ...)` —
/// same "caller owns the content" shape, different presentation.
Future<T?> showManagementModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return AppDialog.show<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    child: Builder(builder: builder),
  );
}

/// The card shell itself: centered, rounded on all corners, header with
/// close button, scrollable body, optional pinned footer.
///
/// Set [bodyIsScrollable] to false when [body] already manages its own
/// scrolling (e.g. a ListView, as in a history/list variant) — the shell
/// will then give it a fixed height via [listHeightFraction] instead of
/// wrapping it in a second scroll view.
class ManagementModalShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  final Widget body;
  final Widget? footer;
  final bool bodyIsScrollable;
  final double maxWidth;
  final double maxHeightFraction;
  final double listHeightFraction;

  const ManagementModalShell({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
    required this.body,
    this.footer,
    this.bodyIsScrollable = false,
    this.maxWidth = 440,
    this.maxHeightFraction = 0.82,
    this.listHeightFraction = 0.62,
  });

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final maxHeight = mq.size.height * maxHeightFraction;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: onClose ?? () => Navigator.pop(context),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close_rounded, size: 18, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );

    final divider = Divider(height: 1, color: cs.outline.withValues(alpha: 0.10));

    final Widget bodyArea = bodyIsScrollable
        ? SizedBox(
            height: mq.size.height * listHeightFraction,
            child: body,
          )
        : Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: body,
            ),
          );

    return Center(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: mq.viewInsets.bottom + 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: Material(
            color: Colors.transparent,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: sagana.cardBackground,
                borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    header,
                    divider,
                    bodyArea,
                    if (footer != null) ...[
                      divider,
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                        child: footer!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Standard Cancel / Primary footer row for [ManagementModalShell].
class ManagementModalActions extends StatelessWidget {
  final String cancelLabel;
  final String primaryLabel;
  final VoidCallback? onCancel;
  final VoidCallback? onPrimary;
  final bool isLoading;
  final bool isDestructive;

  const ManagementModalActions({
    super.key,
    this.cancelLabel = 'Cancel',
    required this.primaryLabel,
    this.onCancel,
    required this.onPrimary,
    this.isLoading = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: isLoading ? null : (onCancel ?? () => Navigator.pop(context)),
            child: Text(cancelLabel, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPrimary,
            style: isDestructive
                ? ElevatedButton.styleFrom(backgroundColor: AppConstants.errorRed)
                : null,
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Text(primaryLabel, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}