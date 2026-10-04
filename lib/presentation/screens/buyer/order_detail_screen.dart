import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/buyer_order_model.dart';
import '../../../data/repositories/buyer_order_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/fulfillment_info_card.dart';
import '../../widgets/shared_widgets.dart';

// Local bypasses, duplicated from my_orders_screen.dart's 3a addendum
// pattern — BuyerOrderModel.statusLabel/.harvestedLabel hardcode English.
// Same ARB keys reused across both files for consistency.
String _orderStatusBadge(String status, AppLocalizations l10n) {
  switch (status) {
    case 'pending':   return l10n.buyerOrdersStatusPending;
    case 'approved':  return l10n.buyerOrdersStatusApproved;
    case 'completed': return l10n.buyerOrdersStatusCompleted;
    case 'cancelled': return l10n.buyerOrdersStatusCancelled;
    default:          return status.toUpperCase();
  }
}

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  // Phase 13 — reused as-is for Farmer's "My Orders" (farmer-as-buyer);
  // only the "Browse More" destination below differs, same isFarmerContext
  // pattern as ListingDetailsScreen/CartScreen (Phase 9).
  final bool isFarmerContext;
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.isFarmerContext = false,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _repository = BuyerOrderRepository();
  bool _isLoading = true;
  BuyerOrderModel? _order;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final order = await _repository.fetchOrderById(widget.orderId);
    if (!mounted) return;
    setState(() {
      _order = order;
      _isLoading = false;
    });
  }

  Color get _statusColor {
    switch (_order?.status) {
      case 'approved': return AppConstants.successGreen;
      case 'pending': return AppConstants.warningAmber;
      case 'completed': return AppConstants.primaryGreen;
      default: return AppConstants.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_order == null) {
      return Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
        body: Center(child: Text(l10n.buyerOrderDetailNotFound)),
      );
    }

    final order = _order!;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        leading: BackButton(onPressed: () => context.pop(), color: AppConstants.primaryGreen),
        title: Text(l10n.buyerOrderDetailTitle(order.orderReference),
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 8, AppConstants.spacingSafeH, 32),
        children: [
          // Fulfillment first — how the order arrives is the thing a buyer
          // checking a pending/approved order most wants confirmed, so it
          // leads instead of sitting after the summary/payment info.
          if (order.hasFulfillmentChoice) ...[
            FulfillmentInfoCard(
              fulfillmentMethod: order.fulfillmentMethod,
              deliveryAddress: order.deliveryAddress,
              deliveryContactNumber: order.deliveryContactNumber,
              deliveryRecipientName: order.deliveryRecipientName,
              deliveryLabel: order.deliveryLabel,
              deliveryNotes: order.deliveryNotes,
            ),
            const SizedBox(height: 16),
          ],
          _buildStatusSection(order, l10n),
          const SizedBox(height: 16),
          if (!order.isCancelled) ...[
            _buildTimeline(order, l10n),
            const SizedBox(height: 16),
          ],
          _buildProductSection(order, l10n),
          const SizedBox(height: 16),
          _buildOrderSummary(order, l10n),
          const SizedBox(height: 16),
          _buildPaymentInfo(l10n),
          // Browse More Products doesn't belong once an order is approved —
          // Pickup/Delivery are the only appropriate actions left at that
          // point. Still shown for pending/completed/cancelled orders,
          // where there's no fulfillment choice to make.
          if (order.status != 'approved') ...[
            const SizedBox(height: 20),
            _buildSupportSection(context, l10n),
          ],
        ],
      ),
    );
  }

  // Two clearly separated zones, not one paragraph stacked under a small
  // pill: a headline zone (icon + status name + short subtitle) that reads
  // at a glance, and an explanation zone below a divider that's there to
  // be read, not skimmed. A cancelled order additionally surfaces the
  // admin's own typed reason, if any — same "Reason: …" treatment Admin's
  // own detail screen already gives it, so the buyer actually sees why.
  Widget _buildStatusSection(BuyerOrderModel order, AppLocalizations l10n) {
    final subtitle = switch (order.status) {
      'approved' => l10n.buyerOrderDetailReadyPickup,
      'pending' => l10n.buyerOrdersAwaitingReview,
      'completed' => l10n.buyerOrderDetailPickedUp,
      _ => l10n.buyerOrderDetailCancelledStatus,
    };
    final message = switch (order.status) {
      'approved' => l10n.buyerOrderDetailMsgApproved(AppConstants.cooperativeName),
      'pending' => l10n.buyerOrderDetailMsgPending(AppConstants.cooperativeName),
      'completed' => l10n.buyerOrderDetailMsgCompleted,
      _ => l10n.buyerOrderDetailMsgCancelled,
    };
    final statusIcon = switch (order.status) {
      'approved' => Icons.task_alt_rounded,
      'pending' => Icons.hourglass_top_rounded,
      'completed' => Icons.check_circle_rounded,
      _ => Icons.cancel_rounded,
    };

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40, height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _statusColor.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: Icon(statusIcon, size: 20, color: _statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_orderStatusBadge(order.status, l10n),
                          style: GoogleFonts.poppins(fontSize: 15.5, fontWeight: FontWeight.w800, color: _statusColor)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppConstants.outline.withValues(alpha: 0.10)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: AppConstants.onSurfaceVariant)),
                if (order.isCancelled && order.notes != null && order.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('${l10n.adminOrderDetailReasonLabel}: ${order.notes}',
                      style: GoogleFonts.inter(fontSize: 12.5, fontStyle: FontStyle.italic, color: AppConstants.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(BuyerOrderModel order, AppLocalizations l10n) {
    // Honest simplification: only "Order Placed" (created_at) and the
    // current status (updated_at) have real timestamps. Everything in
    // between is complete-but-untimestamped; everything after is upcoming.
    final steps = [
      l10n.buyerOrderDetailStepPlaced,
      l10n.buyerOrderDetailStepPendingReview,
      l10n.buyerOrderDetailStepApproved,
      l10n.buyerOrderDetailStepCompleted,
    ];
    final currentIndex = switch (order.status) {
      'pending' => 1,
      'approved' => 2,
      'completed' => 3,
      _ => 0,
    };

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_rounded, size: 16, color: AppConstants.primaryGreen),
              const SizedBox(width: 6),
              Text(l10n.buyerOrderDetailJourney, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < steps.length; i++)
            _timelineStep(
              label: steps[i],
              isDone: i < currentIndex,
              isCurrent: i == currentIndex,
              isLast: i == steps.length - 1,
              timestamp: i == 0
                  ? _formatDateTime(order.createdAt, l10n)
                  : i == currentIndex
                      ? _formatDateTime(order.updatedAt, l10n)
                      : (i < currentIndex ? null : l10n.buyerOrderDetailPendingTimestamp),
            ),
        ],
      ),
    );
  }

  Widget _timelineStep({
    required String label,
    required bool isDone,
    required bool isCurrent,
    required bool isLast,
    String? timestamp,
  }) {
    final color = isDone || isCurrent ? AppConstants.primaryGreen : AppConstants.outline.withValues(alpha: 0.3);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: isDone ? AppConstants.primaryGreen : (isCurrent ? AppConstants.primaryGreen.withValues(alpha: 0.1) : Colors.transparent),
                  shape: BoxShape.circle,
                  border: isCurrent ? Border.all(color: AppConstants.primaryGreen, width: 2) : null,
                ),
                child: isDone
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : isCurrent
                        ? Center(child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppConstants.primaryGreen, shape: BoxShape.circle)))
                        : null,
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: color)),
            ],
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                  color: isDone || isCurrent ? AppConstants.onSurface : AppConstants.onSurfaceVariant.withValues(alpha: 0.5),
                )),
                if (timestamp != null)
                  Text(timestamp, style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Header (image + crop name only — no cooperative subtitle here; that
  // badge used to sit in exactly the spot a Market Type reads, which
  // read as if "SP3 Agriculture Cooperative" WAS the market type). Below
  // it, Market Type and Category sit side by side as a simple two-up
  // row, then Description underneath — matches the same structure used
  // on the Admin Order Detail screen (that one adds Batch Reference/
  // Freshness on top, since that's admin-only inventory context).
  Widget _buildProductSection(BuyerOrderModel order, AppLocalizations l10n) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  child: order.listingPhotoUrl != null
                      ? Image.network(order.listingPhotoUrl!, width: 64, height: 64, fit: BoxFit.cover)
                      : Container(width: 64, height: 64, color: AppConstants.limeGreen),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(order.displayName, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          if (order.marketType != null || order.category != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  if (order.marketType != null) Expanded(child: _miniField('Market Type', order.marketTypeLabel)),
                  if (order.marketType != null && order.category != null) const SizedBox(width: 20),
                  if (order.category != null) Expanded(child: _miniField(l10n.buyerListingCategory, order.category!)),
                ],
              ),
            ),
          ],
          if (order.description != null && order.description!.isNotEmpty) ...[
            Divider(height: 1, color: AppConstants.outline.withValues(alpha: 0.10)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(order.description!,
                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant, height: 1.5)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniField(String label, String value, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant)),
        Text(value, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildOrderSummary(BuyerOrderModel order, AppLocalizations l10n) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 16, color: AppConstants.primaryGreen),
              const SizedBox(width: 6),
              Text(l10n.buyerOrderDetailSummary, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          _summaryRow(l10n.buyerOrdersQuantityLabel, '${order.quantityKg.toStringAsFixed(0)} kg'),
          _summaryRow(l10n.buyerPricePerKg, '₱${order.pricePerKg.toStringAsFixed(2)}'),
          const Divider(height: 20),
          _summaryRow(l10n.buyerOrdersTotalLabel, '₱${order.totalPrice.toStringAsFixed(2)}', bold: true),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.buyerOrderDetailReferenceLabel, style: GoogleFonts.inter(fontSize: 9, letterSpacing: 0.5, color: AppConstants.onSurfaceVariant)),
                  Text(order.orderReference, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(l10n.buyerOrderDetailDateLabel, style: GoogleFonts.inter(fontSize: 9, letterSpacing: 0.5, color: AppConstants.onSurfaceVariant)),
                  Text(AppUtils.formatDate(order.createdAt, l10n.localeName), style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: bold ? 15 : 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: bold ? AppConstants.primaryGreen : AppConstants.onSurfaceVariant)),
          Text(value, style: GoogleFonts.poppins(fontSize: bold ? 18 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: bold ? AppConstants.primaryGreen : AppConstants.onSurface)),
        ],
      ),
    );
  }

  Widget _buildPaymentInfo(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.gold.withValues(alpha: 0.08),
        border: Border.all(color: AppConstants.gold.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.payments_rounded, color: AppConstants.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.buyerOrderDetailPaymentInfo, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(
                  l10n.buyerOrderDetailPaymentBody,
                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Contact/Call SP3 Cooperative and "Need help with this order?" removed
  // per explicit direction — neither is a real, working contact channel
  // (both were snackbar placeholders). Browse More is the one real action
  // left, now in its own bordered container instead of a floating
  // TextButton sitting directly on the page background.
  Widget _buildSupportSection(BuildContext context, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.outline.withValues(alpha: 0.15)),
      ),
      child: TextButton.icon(
        icon: const Icon(Icons.shopping_basket_outlined, size: 18),
        label: Text(l10n.buyerOrderDetailBrowseMore),
        onPressed: () => context.go(
          widget.isFarmerContext ? AppRoutes.myListings : AppRoutes.marketplaceBrowse,
        ),
      ),
    );
  }

  String _formatDateTime(DateTime d, AppLocalizations l10n) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final minute = d.minute.toString().padLeft(2, '0');
    return '${AppUtils.formatDate(d, l10n.localeName)}, $hour:$minute $ampm';
  }
}