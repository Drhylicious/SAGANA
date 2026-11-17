import 'package:flutter/material.dart';
import '../../navigation/connectivity_page_observer.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/utils/order_status.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/program_model.dart';
import '../../../data/repositories/admin_order_repository.dart';
import '../../../data/repositories/cooperative_order_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/staff_permission_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/coop_offer_widgets.dart'
    show CoopDeliveryPhoto, showCoopConfirmDialog;
import '../../widgets/fulfillment_info_card.dart';
import '../../widgets/management_modal.dart' show adminOrderStatusLabel;
import '../../widgets/order_payment_widgets.dart';
import '../../widgets/order_status_style.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/view_only_banner.dart';
import 'order_delivery_map_screen.dart';

/// Staff detail of one Cooperative Product order (program_product_purchases).
///
/// The same steps as a Marketplace order, in the same words: Approve, Ready for Pickup or Out
/// for Delivery, record the handover and cash, then the member confirms (or staff complete it
/// with a reason and a photo). A View Only Officer sees everything and can do nothing.
class AdminProgramOrderDetailScreen extends StatefulWidget {
  final String orderId;
  const AdminProgramOrderDetailScreen({super.key, required this.orderId});

  @override
  State<AdminProgramOrderDetailScreen> createState() =>
      _AdminProgramOrderDetailScreenState();
}

class _AdminProgramOrderDetailScreenState
    extends State<AdminProgramOrderDetailScreen> {
  final _repo = CooperativeOrderRepository();
  final _feeRepo = AdminOrderRepository();
  bool _isLoading = true;
  bool _busy = false;
  ProgramPurchase? _order;
  double _feeDue = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final order = await _repo.fetchOrderById(widget.orderId);
    final fee = (order != null && order.isDelivery && !order.isPaymentRecorded)
        ? await _feeRepo.fetchGroupFeeDue(order.checkoutGroupId)
        : 0.0;
    if (!mounted) return;
    setState(() {
      _order = order;
      _feeDue = fee;
      _isLoading = false;
    });
  }

  /// Runs one staff step: guards Manage access, shows the result, reloads.
  Future<void> _step(
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      AppToast.show(context, successMessage);
      await _load();
    } catch (e, st) {
      if (!mounted) return;
      AppToast.show(context, friendlyError(l10n, e, st), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    if (!requireManage(context, StaffModule.marketplace)) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showCoopConfirmDialog(
      context,
      title: l10n.adminOrderDetailApproveTitle,
      body: l10n.uoApproveBody,
      confirmLabel: l10n.adminOrderDetailApproveTitle,
    );
    if (ok == null || !mounted) return;
    await _step(() => _repo.approve(widget.orderId), l10n.uoToastApproved);
  }

  Future<void> _ready() async {
    if (!requireManage(context, StaffModule.marketplace)) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showCoopConfirmDialog(
      context,
      title: l10n.orderReadyDialogTitle,
      body: l10n.uoReadyBody,
      confirmLabel: l10n.orderActionReadyForPickup,
    );
    if (ok == null || !mounted) return;
    await _step(() => _repo.markReady(widget.orderId), l10n.uoToastReady);
  }

  Future<void> _out() async {
    if (!requireManage(context, StaffModule.marketplace)) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showCoopConfirmDialog(
      context,
      title: l10n.orderOutDialogTitle,
      body: l10n.uoOutBody,
      confirmLabel: l10n.orderActionOutForDelivery,
    );
    if (ok == null || !mounted) return;
    await _step(
      () => _repo.markOutForDelivery(widget.orderId),
      l10n.uoToastOut,
    );
  }

  Future<void> _handover() async {
    if (!requireManage(context, StaffModule.marketplace)) return;
    final l10n = AppLocalizations.of(context);
    final o = _order!;
    final needsPhoto = o.isDelivery;
    final input = await showCashHandoverDialog(
      context,
      subtitle:
          '${o.reference} · ${formatQuantityUnit(o.quantity, o.unit)} ${o.itemName}',
      itemsAmount: o.totalAmount,
      deliveryFee: o.isDelivery ? _feeDue : 0,
      needsPhoto: needsPhoto,
    );
    if (input == null || !mounted) return;
    await _step(
      () => _repo.recordHandover(
        orderId: widget.orderId,
        amount: input.amount,
        photoBytes: input.photo?.bytes,
        photoExtension: input.photo?.extension,
        note: input.note,
      ),
      needsPhoto ? l10n.uoToastHandoverRecorded : l10n.uoToastPaymentRecorded,
    );
  }

  Future<void> _completeForMember() async {
    if (!requireManage(context, StaffModule.marketplace)) return;
    final l10n = AppLocalizations.of(context);
    final o = _order!;
    final input = await showAssistedCompleteDialog(
      context,
      subtitle:
          '${o.reference} · ${formatQuantityUnit(o.quantity, o.unit)} ${o.itemName}',
    );
    if (input == null || !mounted) return;
    await _step(
      () => _repo.completeForMember(
        orderId: widget.orderId,
        reason: input.reason,
        photoBytes: input.photo.bytes,
        photoExtension: input.photo.extension,
      ),
      l10n.uoToastAssistedDone,
    );
  }

  // No Cancel here, the same as a Marketplace order: only the Farmer who placed the order can
  // cancel it, and only while it is Pending. Once it is Approved it goes on to Ready for Pickup
  // or Out for Delivery.

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final o = _order;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(
            title: o != null
                ? l10n.adminOrderDetailOrderNumber(o.reference)
                : l10n.uoCoopOrderTitle,
            onBack: () => context.pop(),
          ),
          const ViewOnlyBanner(module: StaffModule.marketplace),
          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : o == null
                ? Center(
                    child: Text(
                      l10n.uoOrderNotFound,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: Theme.of(context).colorScheme.primary,
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      children: [
                        FulfillmentInfoCard(
                          fulfillmentMethod: o.fulfillmentMethod,
                          deliveryAddress: o.deliveryAddress,
                          deliveryContactNumber: o.deliveryContact,
                          deliveryRecipientName: o.deliveryRecipient,
                          deliveryLabel: o.deliveryLabel,
                          deliveryNotes: o.deliveryNotes,
                          onViewMap:
                              o.deliveryLatitude == null ||
                                  o.deliveryLongitude == null
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    settings: RouteSettings(
                                      name: ConnectivityPage.deliveryMap.name,
                                    ),
                                    builder: (_) => OrderDeliveryMapScreen(
                                      point: LatLng(
                                        o.deliveryLatitude!,
                                        o.deliveryLongitude!,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        _statusCard(o, l10n, cs),
                        const SizedBox(height: 12),
                        if (!o.isPending &&
                            !o.isCancelled &&
                            o.status != 'approved') ...[
                          OrderPaymentCard(
                            paymentStatus: o.paymentStatus,
                            itemsTotal: o.totalAmount,
                            amountCollected: o.amountCollected,
                            deliveryFee: o.deliveryFeeCollected,
                            paidAt: o.paidAt,
                            recordedByName: o.paymentRecordedByName,
                            recordedByRole: o.paymentRecordedByRole,
                            staffView: true,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (o.completionMethod == 'staff' &&
                            !o.legacyMigrated) ...[
                          StaffCompletionCard(
                            reason: o.staffCompletionReason,
                            photoUrl: o.staffCompletionPhotoUrl,
                            byName: o.staffCompletedByName,
                            byRole: o.staffCompletedByRole,
                            at: o.staffCompletedAt,
                          ),
                          if (o.staffCompletionPhotoUrl != null) ...[
                            const SizedBox(height: 8),
                            CoopDeliveryPhoto(url: o.staffCompletionPhotoUrl!),
                          ],
                          const SizedBox(height: 12),
                        ],
                        if (o.handoverPhotoUrl != null) ...[
                          _card(
                            context,
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.buyerOrderDeliveryPhotoTitle,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                CoopDeliveryPhoto(url: o.handoverPhotoUrl!),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _memberCard(o, l10n, cs),
                        const SizedBox(height: 12),
                        _itemsCard(o, l10n, cs),
                        if (o.legacyMigrated) ...[
                          const SizedBox(height: 12),
                          Text(
                            l10n.uoLegacyNote,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontStyle: FontStyle.italic,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(l10n),
    );
  }

  Widget? _bottomBar(AppLocalizations l10n) {
    final o = _order;
    if (o == null) return null;
    final online = ConnectivityService.instance.isOnline && !_busy;
    final next = o.isPending
        ? null
        : nextStaffOrderAction(
            o.status,
            o.fulfillmentMethod,
            paymentStatus: o.paymentStatus,
          );
    final primary = o.isPending
        ? (
            l10n.adminOrderDetailApproveTitle,
            Icons.check_circle_outline_rounded,
            _approve,
          )
        : switch (next) {
            StaffOrderAction.readyForPickup => (
              l10n.orderActionReadyForPickup,
              Icons.storefront_rounded,
              _ready,
            ),
            StaffOrderAction.outForDelivery => (
              l10n.orderActionOutForDelivery,
              Icons.local_shipping_outlined,
              _out,
            ),
            StaffOrderAction.recordHandover => (
              l10n.uoActionRecordHandover,
              Icons.photo_camera_outlined,
              _handover,
            ),
            StaffOrderAction.recordPayment => (
              l10n.uoActionRecordPayment,
              Icons.payments_outlined,
              _handover,
            ),
            StaffOrderAction.completeForCustomer => (
              l10n.uoActionCompleteForCustomer,
              Icons.assignment_turned_in_outlined,
              _completeForMember,
            ),
            null => null,
          };
    if (primary == null) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(
              key: const Key('primaryStep'),
              height: 46,
              icon: primary.$2,
              label: primary.$1,
              isLoading: _busy,
              onPressed: online ? primary.$3 : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.saganaColors.cardBackground,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      border: AppConstants.cardBorder,
    ),
    child: child,
  );

  Widget _statusCard(ProgramPurchase o, AppLocalizations l10n, ColorScheme cs) {
    final shown = orderDisplayStatus(o.status);
    final color = orderStatusColor(shown);
    final subtitle = switch (o.status) {
      'pending' => l10n.adminOrderDetailAwaitingReview,
      'approved' =>
        o.isDelivery ? l10n.adminOrderNextOut : l10n.adminOrderNextReady,
      'ready_for_pickup' =>
        o.isPaymentRecorded
            ? l10n.adminOrderWaitingReceipt
            : l10n.adminOrderWaitingPickup,
      'out_for_delivery' => l10n.adminOrderNextDelivered,
      'delivered' => l10n.adminOrderWaitingReceipt,
      'completed' => l10n.statCompleted,
      _ => l10n.buyerActivityStatusCancelled,
    };
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const OrderSourceBadge(source: kOrderSourceCooperative),
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
                  adminOrderStatusLabel(l10n, shown).toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          if (o.status == 'delivered') ...[
            const SizedBox(height: 6),
            Text(
              l10n.uoHandedOver,
              key: const Key('handedOverNote'),
              style: GoogleFonts.inter(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (o.isCancelled) ...[
            if (o.cancelledByRole != null || o.cancelReason != null)
              const SizedBox(height: 8),
            if (o.cancelReason != null && o.cancelReason!.isNotEmpty)
              Text(
                '${l10n.uoReasonLabel}: ${o.cancelReason}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            AppUtils.formatDateTime(o.requestedAt),
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _memberCard(ProgramPurchase o, AppLocalizations l10n, ColorScheme cs) {
    return _card(
      context,
      Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppConstants.programPurple.withValues(alpha: 0.12),
            child: Text(
              o.farmerName.isNotEmpty ? o.farmerName[0].toUpperCase() : 'F',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: AppConstants.programPurple,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.uoMemberLabel,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  o.farmerName,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemsCard(ProgramPurchase o, AppLocalizations l10n, ColorScheme cs) {
    Widget row(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: bold ? 14 : 12.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.uoOrderDetailsTitle,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            o.itemName,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          row(l10n.uoProgram, o.programName),
          row(l10n.uoQuantity, formatQuantityUnit(o.quantity, o.unit)),
          if (o.hasDiscount)
            row(
              l10n.uoRegularPrice,
              formatPesos(o.regularUnitPrice ?? o.unitPrice),
            ),
          if (o.hasDiscount)
            row(
              l10n.uoMemberPriceLine(
                o.discountPercent.toStringAsFixed(
                  o.discountPercent % 1 == 0 ? 0 : 1,
                ),
              ),
              formatPesos(o.unitPrice),
            )
          else
            row(l10n.uoUnitPrice, formatPesos(o.unitPrice)),
          const Divider(height: 18),
          row(l10n.checkoutTotal, formatPesos(o.totalAmount), bold: true),
          if (o.isDelivery && _feeDue > 0)
            row(l10n.uoDeliveryFeeLine, formatPesos(_feeDue)),
        ],
      ),
    );
  }
}
