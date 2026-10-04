import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../routes/app_routes.dart';
import 'shared_widgets.dart';

// Same bypass used across every order-status display in the app (My
// Orders, Order Detail, Order Success) — BuyerOrderModel.statusLabel
// hardcodes English.
String orderStatusBadge(String status, AppLocalizations l10n) {
  switch (status) {
    case 'pending':   return l10n.buyerOrdersStatusPending;
    case 'approved':  return l10n.buyerOrdersStatusApproved;
    case 'completed': return l10n.buyerOrdersStatusCompleted;
    case 'cancelled': return l10n.buyerOrdersStatusCancelled;
    default:          return status.toUpperCase();
  }
}

/// Shared result icon — an animated halo ring behind a solid colored
/// circle, used at the top of every "what just happened to my order(s)"
/// screen (Buy Now's Order Success, Cart's Checkout Result, in both its
/// all-succeeded and partial-failure states). Previously each screen had
/// its own bespoke treatment — this one duplicated it as a full
/// halo/circle/shadow build, that one was a bare Icon sitting on the page
/// background — which is exactly why the four checkout flows read as
/// differently designed even though the underlying content is the same
/// kind of confirmation.
class OrderResultIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const OrderResultIcon({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(scale: value, child: child),
      child: Container(
        width: 92, height: 92,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.10)),
        child: Container(
          width: 68, height: 68,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Icon(icon, color: Colors.white, size: 36),
        ),
      ),
    );
  }
}

/// Shared "one order" card — reference number, status badge, item row,
/// and a Total box, used identically whether it's the single order from
/// a Buy Now or one of several from a Cart checkout. Every checkout flow
/// (Buy Now/Cart × Pickup/Delivery) renders its order(s) through this one
/// widget, so there's exactly one layout to keep consistent instead of
/// two hand-maintained copies that can silently drift apart.
class OrderReferenceCard extends StatelessWidget {
  final String orderId;
  final String status;
  final String? photoUrl;
  final String displayName;
  final double quantityKg;
  final double pricePerKg;
  final double totalPrice;

  const OrderReferenceCard({
    super.key,
    required this.orderId,
    required this.status,
    this.photoUrl,
    required this.displayName,
    required this.quantityKg,
    required this.pricePerKg,
    required this.totalPrice,
  });

  Color get _statusColor {
    switch (status) {
      case 'approved': return AppConstants.successGreen;
      case 'completed': return AppConstants.primaryGreen;
      case 'cancelled': return AppConstants.errorRed;
      default: return AppConstants.warningAmber; // pending
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reference = 'ORD-${orderId.substring(0, 8).toUpperCase()}';
    final color = _statusColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: flatCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(reference, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppConstants.onSurfaceVariant)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
                child: Text(orderStatusBadge(status, l10n),
                    style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                child: photoUrl != null
                    ? Image.network(photoUrl!, width: 48, height: 48, fit: BoxFit.cover)
                    : Container(width: 48, height: 48, color: AppConstants.limeGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text('${quantityKg.toStringAsFixed(0)} kg × ₱${pricePerKg.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppConstants.successGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.buyerOrdersTotalLabel, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppConstants.onSurfaceVariant)),
                Text('₱${totalPrice.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(fontSize: 19, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed bottom action bar — shared by OrderSuccessScreen and
/// CartCheckoutResultScreen so "View My Orders" / "Continue Shopping"
/// stay pinned to the bottom of the screen (as a Scaffold
/// bottomNavigationBar, outside the scrollable content) at a fixed
/// position, regardless of how much scrollable content sits above them.
/// Continue Shopping is an outlined button, not plain text, so it reads
/// as a real secondary action with its own boundary rather than a loose
/// link floating under the primary button.
class OrderResultActions extends StatelessWidget {
  final bool isFarmerContext;
  const OrderResultActions({super.key, required this.isFarmerContext});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 12, AppConstants.spacingSafeH, 16),
        decoration: BoxDecoration(
          color: context.saganaColors.cardBackground,
          border: Border(top: BorderSide(color: AppConstants.outline.withValues(alpha: 0.10))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFarmerContext)
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: l10n.buyerOrderSuccessContinueShopping,
                  onPressed: () => context.go(AppRoutes.myListings),
                ),
              )
            else ...[
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: l10n.buyerOrderSuccessViewOrders,
                  onPressed: () => context.go(AppRoutes.myOrders),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => context.go(AppRoutes.marketplaceBrowse),
                  child: Text(l10n.buyerOrderSuccessContinueShopping,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
