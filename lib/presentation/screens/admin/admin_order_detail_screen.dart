import '../../widgets/view_only_banner.dart';
import '../../../data/services/staff_permission_service.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../data/services/connectivity_service.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/admin_order_repository.dart';
import '../../widgets/coop_offer_widgets.dart' show CoopDeliveryPhoto, showCoopDeliveryDialog;
import '../../widgets/fulfillment_info_card.dart';
import '../../widgets/order_status_style.dart';
import '../../widgets/app_toast.dart';
import '../../../core/utils/order_status.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/shared_widgets.dart';
import 'order_delivery_map_screen.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/workflow_history_sheet.dart';
import '../../widgets/sub_page_top_bar.dart';

/// Admin-facing order detail — approve / cancel / complete a single order.
/// Rebuilt from scratch after admin_order_detail_screen.dart was found to be
/// an accidental copy of the buyer-facing order_detail_screen.dart (still
/// importing BuyerOrderModel/BuyerOrderRepository, no admin actions at all).
/// This version is AdminOrderModel/AdminOrderRepository end to end, and
/// matches the header/card conventions confirmed against
/// order_management_screen.dart and program_management_screen.dart.
class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  // When true (opened from Buyer Details' read-only Order History), no
  // Approve/Cancel/Complete action is ever shown, regardless of status —
  // closes the bug where those actions were reachable from inside a
  // buyer's profile. See M-marketplace-4.
  final bool readOnly;
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.readOnly = false,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _repo = AdminOrderRepository();
  bool _isLoading = true;
  AdminOrderModel? _order;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final order = await _repo.fetchOrderById(widget.orderId);
    if (!mounted) return;
    setState(() {
      _order = order;
      _isLoading = false;
    });
  }

  Color _statusColor(String status) => orderStatusColor(status);

  // ─── Delivery pinpoint ──────────────────────────────────────────────────

  // Read-only: the map screen has no edit path, so opening it never changes
  // the order's saved coordinates.
  void _openDeliveryMap(LatLng point) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDeliveryMapScreen(point: point),
      ),
    );
  }

  // ─── Actions ────────────────────────────────────────────────────────────

  Future<void> _confirmApprove() async {
    if (!requireManage(context, StaffModule.marketplace)) return;
    final l10n = AppLocalizations.of(context);
    await _runAction(
      title: l10n.adminOrderDetailApproveTitle,
      subtitle: l10n.adminOrderDetailApproveSubtitle,
      body: Text(l10n.adminOrderDetailApproveBody),
      primaryLabel: l10n.adminOrderDetailApproveTitle,
      isDestructive: false,
      action: () => _repo.approveOrder(widget.orderId),
      successMessage: l10n.adminOrderDetailApprovedToast,
    );
  }

  // ─── Fulfillment steps ──────────────────────────────────────────────────
  // The Manager / Officer records each step by hand: Ready for Pickup (pickup
  // order), Out for Delivery then Mark as Delivered with a photo (delivery
  // order). The database re-checks the role, the method and the order of steps.

  Future<void> _confirmReady() async {
    if (!requireManage(context, StaffModule.marketplace)) return;
    final l10n = AppLocalizations.of(context);
    await _runAction(
      title: l10n.orderReadyDialogTitle,
      subtitle: l10n.adminOrderDetailOrderNumber(_order!.orderReference),
      body: Text(l10n.orderReadyDialogBody),
      primaryLabel: l10n.orderActionReadyForPickup,
      isDestructive: false,
      action: () => _repo.markReadyForPickup(widget.orderId),
      successMessage: l10n.orderToastReady,
    );
  }

  Future<void> _confirmOut() async {
    if (!requireManage(context, StaffModule.marketplace)) return;
    final l10n = AppLocalizations.of(context);
    await _runAction(
      title: l10n.orderOutDialogTitle,
      subtitle: l10n.adminOrderDetailOrderNumber(_order!.orderReference),
      body: Text(l10n.orderOutDialogBody),
      primaryLabel: l10n.orderActionOutForDelivery,
      isDestructive: false,
      action: () => _repo.markOutForDelivery(widget.orderId),
      successMessage: l10n.orderToastOut,
    );
  }

  /// Photo evidence is required: the dialog will not submit without one.
  Future<void> _markDelivered() async {
    if (!requireManage(context, StaffModule.marketplace)) return;
    final l10n = AppLocalizations.of(context);
    final order = _order!;
    final input = await showCoopDeliveryDialog(
      context,
      subtitle: '${order.orderReference} · ${formatQuantityUnit(order.quantityKg, order.unit)} ${order.displayName}',
      title: l10n.orderDeliveredDialogTitle,
      body: l10n.orderDeliveredDialogBody,
      confirmLabel: l10n.orderActionMarkDelivered,
    );
    if (input == null || !mounted) return;
    try {
      await _repo.markDelivered(
        orderId: widget.orderId,
        photoBytes: input.photo.bytes,
        photoExtension: input.photo.extension,
        note: input.note,
      );
      if (!mounted) return;
      AppToast.show(context, l10n.orderToastDelivered);
      _load();
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, l10n.adminOrderDetailFailedTryAgain, isError: true);
    }
  }

  /// Confirm → call repository → feedback → reload flow for the Manager's one
  /// order action, Approve. (The Manager neither cancels nor completes an order:
  /// the Buyer or Farmer cancels their own pending order, and the consumer
  /// confirms receipt to complete an approved one.)
  Future<void> _runAction({
    required String title,
    required String subtitle,
    required Widget body,
    required String primaryLabel,
    required bool isDestructive,
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    final l10n = AppLocalizations.of(context);
    bool isSaving = false;
    await showManagementModal(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
        return ManagementModalShell(
          title: title,
          subtitle: subtitle,
          body: body,
          footer: ManagementModalActions(
            primaryLabel: primaryLabel,
            isDestructive: isDestructive,
            isLoading: isSaving,
            onPrimary: () async {
              setSheet(() => isSaving = true);
              String? error;
              try {
                await action();
              } catch (_) {
                error = l10n.adminOrderDetailFailedTryAgain;
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                content: Text(error ?? successMessage),
                    backgroundColor: error != null
                        ? AppConstants.errorRed
                        : AppConstants.midGreen,
                behavior: SnackBarBehavior.floating,
                  ),
                );
              if (error == null) _load();
            },
          ),
        );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _TopBar(
            title: _order != null
                ? l10n.adminOrderDetailOrderNumber(_order!.orderReference)
                : l10n.adminOrderDetailOrderDetailsTitle,
            onBack: () => context.pop(),
          ),
          Expanded(
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                : _order == null
                    ? Center(
                    child: Text(
                      l10n.adminOrderDetailNotFound,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                      )
                    : RefreshIndicator(
                        color: AppConstants.primaryGreen,
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          children: [
                        // Fulfillment first — the very first thing an
                        // admin needs to know about an order is whether
                        // it needs to be delivered, and where.
                        if (_order!.hasFulfillmentChoice) ...[
                          FulfillmentInfoCard(
                            fulfillmentMethod: _order!.fulfillmentMethod,
                            deliveryAddress: _order!.deliveryAddress,
                            deliveryContactNumber:
                                _order!.deliveryContactNumber,
                            deliveryRecipientName:
                                _order!.deliveryRecipientName,
                            deliveryLabel: _order!.deliveryLabel,
                            deliveryNotes: _order!.deliveryNotes,
                            onViewMap: _order!.deliveryLatitude == null ||
                                    _order!.deliveryLongitude == null
                                ? null
                                : () => _openDeliveryMap(
                                      LatLng(
                                        _order!.deliveryLatitude!,
                                        _order!.deliveryLongitude!,
                                      ),
                                    ),
                          ),
                          const SizedBox(height: 12),
                        ],
                            _buildStatusCard(_order!, cs, l10n),
                        const SizedBox(height: 12),
                            if (_order!.deliveryPhotoUrl != null) ...[
                              _SectionCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(l10n.buyerOrderDeliveryPhotoTitle,
                                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 10),
                                    CoopDeliveryPhoto(url: _order!.deliveryPhotoUrl!),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (!_order!.isCancelled) ...[
                              _buildTimeline(_order!),
                              const SizedBox(height: 16),
                            ],
                            _buildBuyerCard(_order!, cs),
                            const SizedBox(height: 16),
                            _buildProductCard(_order!, cs, l10n),
                            const SizedBox(height: 16),
                            _buildSummaryCard(_order!, cs, l10n),
                            const SizedBox(height: 16),
                            // Who did each step, with name, role and time. Staff only:
                            // the Buyer and Farmer see statuses, never staff identities.
                            WorkflowActivityCard(
                              entityType: 'order',
                              entityId: _order!.id,
                              refreshKey: _order!.status,
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // A pending order offers Approve. Every other order shows no action: an
  // approved one waits for the consumer to confirm receipt (which completes it),
  // and completed and cancelled ones are finished. The Manager has no Cancel
  // (only the Buyer or Farmer cancels, and only while the order is pending) and
  // no Complete.
  Widget? _buildBottomBar() {
    if (widget.readOnly) return null;
    final order = _order;
    if (order == null) return null;
    final l10n = AppLocalizations.of(context);
    final online = ConnectivityService.instance.isOnline;

    // After approval the next step depends on the fulfillment method.
    final next = order.nextAction;
    if (next != null) {
      final (label, icon, onTap) = switch (next) {
        StaffOrderAction.readyForPickup => (l10n.orderActionReadyForPickup, Icons.storefront_rounded, _confirmReady),
        StaffOrderAction.outForDelivery => (l10n.orderActionOutForDelivery, Icons.local_shipping_outlined, _confirmOut),
        StaffOrderAction.markDelivered => (l10n.orderActionMarkDelivered, Icons.photo_camera_outlined, _markDelivered),
      };
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: PrimaryButton(
            height: 46,
            icon: icon,
            label: label,
            onPressed: online ? onTap : null,
          ),
        ),
      );
    }
    if (!order.isPending) return null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: PrimaryButton(
          height: 46,
          icon: Icons.check_circle_outline_rounded,
          label: l10n.adminOrderDetailApproveTitle,
          onPressed: ConnectivityService.instance.isOnline
              ? _confirmApprove
              : null,
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    AdminOrderModel order,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    final color = _statusColor(order.status);
    final subtitle = switch (order.status) {
      'pending' => l10n.adminOrderDetailAwaitingReview,
      'approved' => order.isDelivery ? l10n.adminOrderNextOut : l10n.adminOrderNextReady,
      'ready_for_pickup' => l10n.adminOrderWaitingPickup,
      'out_for_delivery' => l10n.adminOrderNextDelivered,
      'delivered' => l10n.adminOrderWaitingReceipt,
      'completed' => l10n.statCompleted,
      _ => l10n.buyerActivityStatusCancelled,
    };
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  adminOrderStatusLabel(l10n, order.status).toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '— $subtitle',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (order.isReadyForPickup || order.isDelivered) ...[
            const SizedBox(height: 10),
            Text(
              l10n.adminOrderWaitingForBuyerNote,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (order.isCancelled && order.cancelledBy != null) ...[
            const SizedBox(height: 10),
            Text(
              order.cancelledBy == 'farmer'
                  ? l10n.adminOrderCancelledByFarmer
                  : l10n.adminOrderCancelledByBuyer,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (order.isCancelled &&
              order.notes != null &&
              order.notes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Reason: ${order.notes}',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeline(AdminOrderModel order) {
    final l10n = AppLocalizations.of(context);
    // The journey follows the fulfillment method (see orderJourney).
    final journey = orderJourney(order.fulfillmentMethod);
    final steps = [for (final s in journey) adminOrderStatusLabel(l10n, s)];
    final currentIndex = journey.indexOf(order.status).clamp(0, journey.length - 1);
    return _SectionCard(
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final lineIndex = i ~/ 2;
            final isDone = lineIndex < currentIndex;
            return Expanded(
              child: Container(
                height: 2,
                color: isDone
                    ? AppConstants.primaryGreen
                    : AppConstants.outline.withValues(alpha: 0.20),
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final isDone = stepIndex <= currentIndex;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? AppConstants.primaryGreen
                      : AppConstants.outline.withValues(alpha: 0.25),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[stepIndex],
                  style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDone
                      ? AppConstants.primaryGreen
                      : AppConstants.outline,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildBuyerCard(AdminOrderModel order, ColorScheme cs) {
    return _SectionCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppConstants.buyerBlue.withValues(alpha: 0.12),
            backgroundImage: order.buyerPhotoUrl != null
                ? NetworkImage(order.buyerPhotoUrl!)
                : null,
            onBackgroundImageError: order.buyerPhotoUrl != null
                ? (_, __) {}
                : null,
            child: order.buyerPhotoUrl != null
                ? null
                : Text(
                    order.buyerName.isNotEmpty
                        ? order.buyerName[0].toUpperCase()
                        : 'B',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      color: AppConstants.buyerBlue,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.buyerName,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                if (order.buyerPhone != null)
                  Text(
                    order.buyerPhone!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(
    AdminOrderModel order,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    return _SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header — image + crop name only. Previously carried a "✓ SP3
          // Agriculture Cooperative" subtitle in the exact spot a Market
          // Type reads, which made it look like that WAS the market
          // type. Market Type now has its own proper field below.
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  child: order.listingPhotoUrl != null
                      ? Image.network(
                          order.listingPhotoUrl!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 64,
                          height: 64,
                          color: AppConstants.limeGreen,
                ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    order.displayName,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Market Type + Category — a simple two-up row, evenly split.
          if (order.marketType != null || order.category != null) ...[
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  if (order.marketType != null)
                Expanded(
                      child: _miniField(
                        'Market Type',
                        order.marketTypeLabel,
                        cs,
                      ),
                    ),
                  if (order.marketType != null && order.category != null)
                    const SizedBox(width: 20),
                  if (order.category != null)
                    Expanded(
                      child: _miniField(
                        l10n.adminOrderDetailCategory,
                        order.category!,
                        cs,
                      ),
                ),
              ],
            ),
          ),
          ],
          // Batch Reference + Freshness — admin-only inventory context,
          // same two-up row shape as above.
          if (order.batchNumber != null || order.harvestDate != null) ...[
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  if (order.batchNumber != null)
                    Expanded(
                      child: _miniField(
                        l10n.adminOrderDetailBatchReference,
                        formatBatchNumber(order.batchNumber),
                        cs,
                      ),
                    ),
                  if (order.batchNumber != null && order.harvestDate != null)
                    const SizedBox(width: 20),
                  if (order.harvestDate != null)
                    Expanded(
                      child: _miniField(
                        l10n.adminOrderDetailFreshness,
                        order.harvestedLabel,
                        cs,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (order.description != null && order.description!.isNotEmpty) ...[
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                order.description!,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniField(String label, String value, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    AdminOrderModel order,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.adminOrderDetailOrderSummary,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _summaryRow(
            l10n.adminOrderDetailQuantity,
            formatQuantityUnit(order.quantityKg, order.unit),
            cs,
          ),
          _summaryRow(
            l10n.adminOrderDetailPricePerKg(unitOrDefault(order.unit)),
            formatPesos(order.pricePerKg),
            cs,
          ),
          Divider(height: 20, color: cs.outline.withValues(alpha: 0.10)),
          _summaryRow(
            l10n.adminOrderDetailTotalAmount,
            '₱${order.totalPrice.toStringAsFixed(2)}',
            cs,
            bold: true,
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.adminOrderDetailReferenceLabel,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      letterSpacing: 0.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    order.orderReference,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    l10n.adminOrderDetailOrderDateLabel,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      letterSpacing: 0.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    _formatDate(order.createdAt),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value,
    ColorScheme cs, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  color: bold ? AppConstants.primaryGreen : cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
              style: GoogleFonts.poppins(
                fontSize: bold ? 18 : 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: bold ? AppConstants.primaryGreen : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }
}

// ─── Top App Bar ──────────────────────────────────────────────────────────────
// Same blurred-glass pattern as OrderManagementScreen's own _TopAppBar and
// ProgramManagementScreen's inline top bar — copied rather than shared, same
// convention order_management_screen.dart already documents for this exact
// widget shape.

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _TopBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {

    return SubPageTopBar(title: title, onBack: onBack);
  }
}

// ─── Section Card ─────────────────────────────────────────────────────────────
// Plain bordered card — matches the convention actually used across admin
// screens (program cards in ProgramManagementScreen, list rows in
// CropRequestApprovalScreen, AllListingsScreen, BuyerManagementScreen).
// GlassCard's heavy blur is a buyer-facing look in this codebase, not an
// admin one — deliberately not used here.

class _SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _SectionCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: child,
    );
  }
}
