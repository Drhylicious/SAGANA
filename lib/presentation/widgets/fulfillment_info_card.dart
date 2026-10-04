import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';

/// Shared fulfillment display — same structure on Checkout's selected-
/// address summary, Buyer Order Detail, Order Success/Cart Result, and
/// Admin Order Detail, so all five present Pickup/Delivery information
/// identically instead of each screen inventing its own layout.
///
/// Pickup shows just the method + the cooperative's own pickup location.
/// Delivery shows recipient name and contact number on one row, then the
/// complete address, the saved-address label, and — only when present,
/// with no "Optional" placeholder text — delivery notes. Every delivery
/// field shares the exact same left edge; none is indented, badged, or
/// otherwise offset from the others.
///
/// Pass [onTap] to make the whole card tappable with a trailing chevron
/// (Checkout uses this to reuse the exact same layout for its own
/// selected-address summary, which opens the address picker on tap) — omit
/// it for the read-only, post-order-placement uses elsewhere.
class FulfillmentInfoCard extends StatelessWidget {
  final String? fulfillmentMethod; // 'pickup' | 'delivery' | null
  final String? deliveryAddress;
  final String? deliveryContactNumber;
  final String? deliveryRecipientName;
  final String? deliveryLabel;
  final String? deliveryNotes;
  final VoidCallback? onTap;

  const FulfillmentInfoCard({
    super.key,
    required this.fulfillmentMethod,
    this.deliveryAddress,
    this.deliveryContactNumber,
    this.deliveryRecipientName,
    this.deliveryLabel,
    this.deliveryNotes,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final method = fulfillmentMethod;
    if (method == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final isPickup = method == 'pickup';
    final notes = deliveryNotes?.trim();

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: AppConstants.cardBorder,
        boxShadow: AppConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30, height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPickup ? Icons.storefront_rounded : Icons.local_shipping_outlined,
                  size: 16, color: AppConstants.primaryGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isPickup ? l10n.checkoutFulfillmentPickup : l10n.checkoutFulfillmentDelivery,
                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, size: 20, color: AppConstants.outline.withValues(alpha: 0.7)),
            ],
          ),
          if (isPickup) ...[
            const SizedBox(height: 10),
            Text(
              '${AppConstants.cooperativeName}, ${AppConstants.cooperativeLocation}',
              style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant, height: 1.4),
            ),
          ] else ...[
            const SizedBox(height: 12),
            // Every field below starts at the same left edge — no icons,
            // no badge/pill on Label, nothing indented differently from
            // the rest, so the block reads as one clean, aligned stack.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    deliveryRecipientName?.trim().isNotEmpty == true ? deliveryRecipientName! : '—',
                    style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
                if (deliveryContactNumber != null && deliveryContactNumber!.trim().isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Text(deliveryContactNumber!,
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppConstants.onSurfaceVariant)),
                ],
              ],
            ),
            if (deliveryAddress != null && deliveryAddress!.trim().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(deliveryAddress!, style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurface, height: 1.4)),
            ],
            if (deliveryLabel != null && deliveryLabel!.trim().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(deliveryLabel!,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
            ],
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: AppConstants.outline.withValues(alpha: 0.10)),
              const SizedBox(height: 10),
              Text(notes, style: GoogleFonts.inter(fontSize: 12.5, color: AppConstants.onSurfaceVariant, height: 1.4)),
            ],
          ],
        ],
      ),
    );

    return onTap == null ? card : GestureDetector(onTap: onTap, child: card);
  }
}
