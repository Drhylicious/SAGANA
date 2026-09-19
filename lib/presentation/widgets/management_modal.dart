import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import 'app_dialog.dart';

/// Localized label for an admin-facing order status ('pending' / 'approved'
/// / 'completed' / 'cancelled') — kept here (a widely-imported shared
/// widgets file) rather than on AdminOrderModel, which has no
/// BuildContext, so every admin order screen shares one translation
/// instead of AdminOrderModel.statusLabel's hardcoded English.
String adminOrderStatusLabel(AppLocalizations l10n, String status) {
  switch (status) {
    case 'pending':
      return l10n.adminOrderStatusPendingReview;
    case 'approved':
      return l10n.buyerOrderDetailStepApproved;
    case 'completed':
      return l10n.statCompleted;
    case 'cancelled':
      return l10n.buyerActivityStatusCancelled;
    default:
      return status;
  }
}

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
  // Nullable, not a hardcoded 'Cancel' default: a compile-time-constant
  // default can't call AppLocalizations, and nearly every call site across
  // the admin screens relies on this default rather than passing its own
  // cancelLabel — so leaving it hardcoded English meant almost every
  // management sheet's Cancel button ignored the selected locale. Falls
  // back to l10n.cancel in build() instead. See M-l10n-cancel-default.
  final String? cancelLabel;
  final String primaryLabel;
  final VoidCallback? onCancel;
  final VoidCallback? onPrimary;
  final bool isLoading;
  final bool isDestructive;

  const ManagementModalActions({
    super.key,
    this.cancelLabel,
    required this.primaryLabel,
    this.onCancel,
    required this.onPrimary,
    this.isLoading = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedCancelLabel = cancelLabel ?? AppLocalizations.of(context).cancel;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: isLoading ? null : (onCancel ?? () => Navigator.pop(context)),
            // FittedBox + maxLines: 1: this button only gets 1/3 of the
            // row's width (see the primary button's flex: 2 below), and
            // Tagalog "Kanselahin" is long enough next to the default
            // English "Cancel" that it used to wrap onto two lines here,
            // making the button taller and visually misaligned against the
            // single-line primary button beside it. Shrinking to fit keeps
            // it on one line instead.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(resolvedCancelLabel,
                  maxLines: 1, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
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
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(primaryLabel,
                        maxLines: 1, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  ),
          ),
        ),
      ],
    );
  }
}