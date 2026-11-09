import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/utils/order_status.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/program_model.dart';
import '../../../data/repositories/cooperative_order_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/coop_offer_widgets.dart' show showCoopConfirmDialog;
import '../../widgets/fulfillment_info_card.dart';
import '../../widgets/management_modal.dart' show adminOrderStatusLabel;
import '../../widgets/order_payment_widgets.dart';
import '../../widgets/order_status_style.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// A Farmer's own Cooperative Product order: where it is, what was paid, and the two things the
/// Farmer can do: cancel it while it is still Pending, and confirm receipt once the cooperative
/// has handed it over and recorded the cash. Staff names are never shown to the Farmer.
class FarmerProgramOrderDetailScreen extends StatefulWidget {
  final String orderId;
  const FarmerProgramOrderDetailScreen({super.key, required this.orderId});

  @override
  State<FarmerProgramOrderDetailScreen> createState() =>
      _FarmerProgramOrderDetailScreenState();
}

class _FarmerProgramOrderDetailScreenState
    extends State<FarmerProgramOrderDetailScreen> {
  final _repo = CooperativeOrderRepository();
  ProgramPurchase? _order;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final o = await _repo.fetchOrderById(widget.orderId);
    if (!mounted) return;
    setState(() {
      _order = o;
      _loading = false;
    });
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      AppToast.show(context, success);
      await _load();
    } catch (e, st) {
      if (!mounted) return;
      AppToast.show(context, friendlyError(l10n, e, st), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReceived() async {
    final l10n = AppLocalizations.of(context);
    await _run(
      () => _repo.confirmReceived(widget.orderId),
      l10n.buyerOrderReceivedToast,
    );
  }

  Future<void> _cancel() async {
    final l10n = AppLocalizations.of(context);
    final reason = await showCoopConfirmDialog(
      context,
      title: l10n.uoCancelTitle,
      body: l10n.uoFarmerCancelBody,
      confirmLabel: l10n.uoCancelOrder,
      reasonLabel: l10n.uoCancelReasonLabel,
      destructive: true,
    );
    if (reason == null || !mounted) return;
    await _run(
      () =>
          _repo.cancel(widget.orderId, reason: reason.isEmpty ? null : reason),
      l10n.uoToastCancelled,
    );
  }

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.saganaColors.cardBackground,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      border: AppConstants.cardBorder,
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final o = _order;
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Column(
        children: [
          SubPageTopBar(
            title: o != null
                ? l10n.adminOrderDetailOrderNumber(o.reference)
                : l10n.uoCoopOrderTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading
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
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        _statusCard(o, l10n, cs),
                        const SizedBox(height: 12),
                        FulfillmentInfoCard(
                          fulfillmentMethod: o.fulfillmentMethod,
                          deliveryAddress: o.deliveryAddress,
                          deliveryContactNumber: o.deliveryContact,
                          deliveryRecipientName: o.deliveryRecipient,
                          deliveryLabel: o.deliveryLabel,
                          deliveryNotes: o.deliveryNotes,
                        ),
                        const SizedBox(height: 12),
                        if (_isWaitingForPayment(o)) ...[
                          const WaitingForPaymentCard(),
                          const SizedBox(height: 12),
                        ],
                        if (_canConfirm(o)) ...[
                          _confirmCard(l10n),
                          const SizedBox(height: 12),
                        ],
                        if (!o.isPending &&
                            !o.isCancelled &&
                            o.status != 'approved') ...[
                          OrderPaymentCard(
                            paymentStatus: o.paymentStatus,
                            itemsTotal: o.totalAmount,
                            amountCollected: o.amountCollected,
                            deliveryFee: o.deliveryFeeCollected,
                            paidAt: o.paidAt,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (o.completionMethod == 'staff' &&
                            !o.legacyMigrated) ...[
                          StaffCompletionCard(
                            reason: o.staffCompletionReason,
                            showStaffIdentity: false,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _itemsCard(o, l10n, cs),
                        if (o.isPending) ...[
                          const SizedBox(height: 16),
                          OutlinedButton(
                            key: const Key('farmerCancel'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppConstants.errorRed,
                            ),
                            onPressed:
                                (_busy ||
                                    !ConnectivityService.instance.isOnline)
                                ? null
                                : _cancel,
                            child: Text(l10n.uoCancelOrder),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  bool _canConfirm(ProgramPurchase o) => canConfirmReceiptFor(
    o.status,
    o.fulfillmentMethod,
    paymentRecorded: o.isPaymentRecorded,
  );

  bool _isWaitingForPayment(ProgramPurchase o) =>
      !o.isPaymentRecorded &&
      canConfirmReceiptFor(o.status, o.fulfillmentMethod);

  Widget _confirmCard(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: AppConstants.primaryGreen.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.buyerOrderReceivedCardTitle,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            key: const Key('farmerConfirmReceived'),
            onPressed: (_busy || !ConnectivityService.instance.isOnline)
                ? null
                : _confirmReceived,
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: Text(
              l10n.buyerOrderReceivedAction,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(ProgramPurchase o, AppLocalizations l10n, ColorScheme cs) {
    final color = orderStatusColor(o.status);
    return _card(
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
                  adminOrderStatusLabel(l10n, o.status).toUpperCase(),
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
            AppUtils.formatDateTime(o.requestedAt),
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          if (o.isCancelled &&
              o.cancelReason != null &&
              o.cancelReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${l10n.uoReasonLabel}: ${o.cancelReason}',
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
        ],
      ),
    );
  }
}
