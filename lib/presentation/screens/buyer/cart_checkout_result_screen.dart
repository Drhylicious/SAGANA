import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/cart_item_model.dart';
import '../../widgets/fulfillment_info_card.dart';
import '../../widgets/order_result_pieces.dart';

class CartCheckoutResultScreen extends StatelessWidget {
  // Each succeeded item carries the orderId place_order() returned — fed
  // straight into the same OrderReferenceCard Buy Now's Order Success
  // uses, with no extra fetch needed: status is always freshly 'pending'
  // right after placement.
  final List<(CartItemModel, String)> succeeded;
  final List<(CartItemModel, String)> failed;
  // Shared by the whole batch (Checkout only offers one fulfillment
  // choice per checkout), so it's rendered once below the item cards
  // instead of once per item.
  final String? fulfillmentMethod;
  final String? deliveryAddress;
  final String? deliveryContactNumber;
  final String? deliveryRecipientName;
  final String? deliveryLabel;
  final String? deliveryNotes;
  // Phase 9 — farmer-as-buyer has no "My Orders" destination yet (that's
  // Phase 13), so the farmer variant shows only the "back to Marketplace"
  // action instead of both buttons.
  final bool isFarmerContext;

  const CartCheckoutResultScreen({
    super.key,
    required this.succeeded,
    required this.failed,
    this.fulfillmentMethod,
    this.deliveryAddress,
    this.deliveryContactNumber,
    this.deliveryRecipientName,
    this.deliveryLabel,
    this.deliveryNotes,
    this.isFarmerContext = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final allSucceeded = failed.isEmpty;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSafeH, vertical: 24),
          children: [
            const SizedBox(height: 12),
            // Same OrderResultIcon Buy Now's Order Success uses — just a
            // different icon/color for the partial-failure case, not a
            // different treatment altogether.
            Center(
              child: OrderResultIcon(
                icon: allSucceeded ? Icons.check_rounded : Icons.info_rounded,
                color: allSucceeded ? AppConstants.successGreen : AppConstants.warningAmber,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              allSucceeded ? l10n.buyerOrderSuccessTitle : l10n.buyerCheckoutResultPartialTitle(succeeded.length, succeeded.length + failed.length),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen),
            ),
            const SizedBox(height: 8),
            Text(
              allSucceeded ? l10n.buyerOrderSuccessSubtitle : l10n.buyerCheckoutResultPartialBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (succeeded.isNotEmpty) ...[
              // Same fixed reading order as Buy Now's Order Success —
              // fulfillment first, then the order(s) — no separate
              // "ORDERED" section caption here either; a list of order
              // cards reads the same way whether there's one of them
              // (Buy Now) or several (Cart).
              if (fulfillmentMethod != null) ...[
                FulfillmentInfoCard(
                  fulfillmentMethod: fulfillmentMethod,
                  deliveryAddress: deliveryAddress,
                  deliveryContactNumber: deliveryContactNumber,
                  deliveryRecipientName: deliveryRecipientName,
                  deliveryLabel: deliveryLabel,
                  deliveryNotes: deliveryNotes,
                ),
                const SizedBox(height: 10),
              ],
              for (int i = 0; i < succeeded.length; i++) ...[
                OrderReferenceCard(
                  orderId: succeeded[i].$2,
                  status: 'pending',
                  photoUrl: succeeded[i].$1.photoUrl,
                  displayName: succeeded[i].$1.displayName,
                  quantityKg: succeeded[i].$1.quantityKg,
                  pricePerKg: succeeded[i].$1.pricePerKg,
                  totalPrice: succeeded[i].$1.subtotal,
                ),
                // Only *between* cards, not after the last one — a
                // trailing gap here would leave a bigger space before the
                // buttons than Buy Now's single-card screen has.
                if (i < succeeded.length - 1) const SizedBox(height: 10),
              ],
            ],
            if (failed.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(l10n.buyerCheckoutResultFailedLabel,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppConstants.errorRed, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              ...failed.map((f) => _resultRow(f.$1.displayName, f.$2, AppConstants.errorRed, Icons.error_outline_rounded)),
            ],
          ],
        ),
      ),
      bottomNavigationBar: OrderResultActions(isFarmerContext: isFarmerContext),
    );
  }

  Widget _resultRow(String title, String subtitle, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 13))),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
