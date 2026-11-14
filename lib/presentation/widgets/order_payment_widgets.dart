import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../core/utils/app_utils.dart';
import '../../core/utils/order_status.dart';
import '../../core/utils/quantity_utils.dart';
import 'crop_photo_capture.dart';
import 'management_modal.dart';

/// "Manager" / "Officer" for a stored staff role ('admin' and 'manager' both read Manager).
String staffRoleLabel(AppLocalizations l10n, String? role) =>
    role == 'officer' ? l10n.staffRoleOfficer : l10n.staffRoleManager;

/// Which engine an order came from: Marketplace or Cooperative.
class OrderSourceBadge extends StatelessWidget {
  final String source;
  const OrderSourceBadge({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final coop = source == kOrderSourceCooperative;
    final color = coop ? AppConstants.programPurple : AppConstants.buyerBlue;
    return Container(
      key: Key('sourceBadge_$source'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            coop ? Icons.groups_2_outlined : Icons.storefront_outlined,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            coop ? l10n.uoSourceCooperative : l10n.uoSourceMarketplace,
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown to a consumer whose order is ready / delivered but whose cash the cooperative has
/// not recorded yet: Confirm Receipt waits for it.
class WaitingForPaymentCard extends StatelessWidget {
  const WaitingForPaymentCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('waitingForPayment'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.warningAmber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: AppConstants.warningAmber.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.payments_outlined,
            size: 20,
            color: AppConstants.warningAmber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.uoWaitingPaymentTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.uoWaitingPaymentBody,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.4,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What was paid, kept apart from the fulfillment status. [staffView] adds who recorded it.
class OrderPaymentCard extends StatelessWidget {
  final String paymentStatus;
  final double itemsTotal;
  final double? amountCollected;
  final double deliveryFee;
  final DateTime? paidAt;
  final String? recordedByName;
  final String? recordedByRole;
  final bool staffView;

  const OrderPaymentCard({
    super.key,
    required this.paymentStatus,
    required this.itemsTotal,
    this.amountCollected,
    this.deliveryFee = 0,
    this.paidAt,
    this.recordedByName,
    this.recordedByRole,
    this.staffView = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
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
              fontSize: bold ? 13.5 : 12.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    final paid = paymentStatus == 'paid';
    return Container(
      key: const Key('orderPaymentCard'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: AppConstants.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                paid ? Icons.verified_outlined : Icons.payments_outlined,
                size: 18,
                color: paid
                    ? Theme.of(context).colorScheme.primary
                    : AppConstants.warningAmber,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.uoPaymentTitle,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (paid) ...[
            row(l10n.uoPaymentItems, formatPesos(itemsTotal)),
            if (deliveryFee > 0)
              row(l10n.uoPaymentDeliveryFee, formatPesos(deliveryFee)),
            row(
              l10n.uoPaymentCash,
              formatPesos(amountCollected ?? itemsTotal + deliveryFee),
              bold: true,
            ),
            if (paidAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.uoPaymentRecordedOn(AppUtils.formatDateTime(paidAt!)),
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            if (staffView && recordedByName != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  l10n.uoPaymentRecordedBy(
                    recordedByName!,
                    staffRoleLabel(l10n, recordedByRole),
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                paymentStatus == 'not_recorded'
                    ? l10n.uoPaymentNotRecorded
                    : l10n.uoPaymentUnpaid,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown on an order that staff completed for the customer.
class StaffCompletionCard extends StatelessWidget {
  final String? reason;
  final String? photoUrl;
  final String? byName;
  final String? byRole;
  final DateTime? at;
  final bool showStaffIdentity;

  const StaffCompletionCard({
    super.key,
    this.reason,
    this.photoUrl,
    this.byName,
    this.byRole,
    this.at,
    this.showStaffIdentity = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const Key('staffCompletionCard'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: AppConstants.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assignment_turned_in_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.uoCompletedByStaffTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (showStaffIdentity && byName != null && at != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.uoCompletedByStaffBy(
                  byName!,
                  staffRoleLabel(l10n, byRole),
                  AppUtils.formatDateTime(at!),
                ),
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          if (reason != null && reason!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${l10n.uoReasonLabel}: $reason',
                style: GoogleFonts.inter(fontSize: 12.5, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Staff dialogs ───────────────────────────────────────────────────────────

/// What the handover dialog returns.
class HandoverInput {
  final double amount;
  final CapturedCropPhoto? photo;
  final String? note;
  const HandoverInput({required this.amount, this.photo, this.note});
}

/// Records the cash for an order. [needsPhoto] is true for a delivery handover (the photo is
/// required). The amount must equal [itemsAmount] + [deliveryFee]: the database checks it too.
Future<HandoverInput?> showCashHandoverDialog(
  BuildContext context, {
  required String subtitle,
  required double itemsAmount,
  double deliveryFee = 0,
  required bool needsPhoto,
}) {
  return showManagementModal<HandoverInput>(
    context: context,
    builder: (_) => _CashHandoverDialog(
      subtitle: subtitle,
      itemsAmount: itemsAmount,
      deliveryFee: deliveryFee,
      needsPhoto: needsPhoto,
    ),
  );
}

class _CashHandoverDialog extends StatefulWidget {
  final String subtitle;
  final double itemsAmount;
  final double deliveryFee;
  final bool needsPhoto;
  const _CashHandoverDialog({
    required this.subtitle,
    required this.itemsAmount,
    required this.deliveryFee,
    required this.needsPhoto,
  });

  @override
  State<_CashHandoverDialog> createState() => _CashHandoverDialogState();
}

class _CashHandoverDialogState extends State<_CashHandoverDialog> {
  late final TextEditingController _amount;
  final _note = TextEditingController();
  CapturedCropPhoto? _photo;
  bool _photoMissing = false;
  bool _amountWrong = false;

  double get _due => double.parse(
    (widget.itemsAmount + widget.deliveryFee).toStringAsFixed(2),
  );

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: _due.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _take() async {
    final photo = await captureCropPhoto(context);
    if (photo == null || !mounted) return;
    setState(() {
      _photo = photo;
      _photoMissing = false;
    });
  }

  void _submit() {
    final entered = double.tryParse(_amount.text.trim());
    final wrong = entered == null || (entered - _due).abs() > 0.004;
    final noPhoto = widget.needsPhoto && _photo == null;
    if (wrong || noPhoto) {
      setState(() {
        _amountWrong = wrong;
        _photoMissing = noPhoto;
      });
      return;
    }
    final note = _note.text.trim();
    Navigator.pop(
      context,
      HandoverInput(
        amount: _due,
        photo: _photo,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    Widget line(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.only(top: 4),
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
              fontSize: bold ? 15 : 12.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return ManagementModalShell(
      title: widget.needsPhoto
          ? l10n.uoHandoverDialogTitle
          : l10n.uoPaymentDialogTitle,
      subtitle: widget.subtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.needsPhoto
                ? l10n.uoHandoverDialogBody
                : l10n.uoPaymentDialogBody,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            key: const Key('cashDue'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Column(
              children: [
                line(l10n.uoCashItemsLine, formatPesos(widget.itemsAmount)),
                if (widget.deliveryFee > 0)
                  line(l10n.uoCashFeeLine, formatPesos(widget.deliveryFee)),
                const Divider(height: 14),
                line(l10n.uoCashToCollect, formatPesos(_due), bold: true),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.uoCashReceived,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('cashReceived'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            onChanged: (_) => setState(() => _amountWrong = false),
          ),
          if (_amountWrong)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.uoCashMismatch(formatPesos(_due)),
                style: GoogleFonts.inter(fontSize: 12, color: cs.error),
              ),
            ),
          if (widget.needsPhoto) ...[
            const SizedBox(height: 14),
            if (_photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                child: Image.memory(
                  _photo!.bytes,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            if (_photo != null) const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('handoverPhoto'),
                onPressed: _take,
                icon: const Icon(Icons.photo_camera_rounded, size: 18),
                label: Text(
                  _photo == null
                      ? l10n.coopDeliverTakePhoto
                      : l10n.coopDeliverRetake,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (_photoMissing)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.coopDeliverPhotoRequired,
                  style: GoogleFonts.inter(fontSize: 12, color: cs.error),
                ),
              ),
          ],
          const SizedBox(height: 14),
          Text(
            l10n.coopNoteLabel,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          TextField(controller: _note, maxLines: 2, maxLength: 200),
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: l10n.uoCashRecord,
        onPrimary: _submit,
      ),
    );
  }
}

/// What staff-assisted completion returns.
class AssistedCompleteInput {
  final String reason;
  final CapturedCropPhoto photo;
  const AssistedCompleteInput({required this.reason, required this.photo});
}

/// Staff complete an order for a customer who cannot confirm. A reason and a photo are required.
Future<AssistedCompleteInput?> showAssistedCompleteDialog(
  BuildContext context, {
  required String subtitle,
}) {
  return showManagementModal<AssistedCompleteInput>(
    context: context,
    builder: (_) => _AssistedCompleteDialog(subtitle: subtitle),
  );
}

class _AssistedCompleteDialog extends StatefulWidget {
  final String subtitle;
  const _AssistedCompleteDialog({required this.subtitle});

  @override
  State<_AssistedCompleteDialog> createState() =>
      _AssistedCompleteDialogState();
}

class _AssistedCompleteDialogState extends State<_AssistedCompleteDialog> {
  final _reason = TextEditingController();
  CapturedCropPhoto? _photo;
  bool _reasonShort = false;
  bool _photoMissing = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _take() async {
    final photo = await captureCropPhoto(context);
    if (photo == null || !mounted) return;
    setState(() {
      _photo = photo;
      _photoMissing = false;
    });
  }

  void _submit() {
    final reason = _reason.text.trim();
    final short = reason.length < 5;
    final noPhoto = _photo == null;
    if (short || noPhoto) {
      setState(() {
        _reasonShort = short;
        _photoMissing = noPhoto;
      });
      return;
    }
    Navigator.pop(
      context,
      AssistedCompleteInput(reason: reason, photo: _photo!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return ManagementModalShell(
      title: l10n.uoAssistTitle,
      subtitle: widget.subtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.uoAssistBody,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.uoAssistReasonLabel,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('assistReason'),
            controller: _reason,
            maxLines: 3,
            maxLength: 300,
            onChanged: (_) => setState(() => _reasonShort = false),
          ),
          if (_reasonShort)
            Text(
              l10n.uoAssistReasonRequired,
              style: GoogleFonts.inter(fontSize: 12, color: cs.error),
            ),
          const SizedBox(height: 12),
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: Image.memory(
                _photo!.bytes,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          if (_photo != null) const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('assistPhoto'),
              onPressed: _take,
              icon: const Icon(Icons.photo_camera_rounded, size: 18),
              label: Text(
                _photo == null
                    ? l10n.coopDeliverTakePhoto
                    : l10n.coopDeliverRetake,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (_photoMissing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.coopDeliverPhotoRequired,
                style: GoogleFonts.inter(fontSize: 12, color: cs.error),
              ),
            ),
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: l10n.uoAssistConfirm,
        onPrimary: _submit,
      ),
    );
  }
}
