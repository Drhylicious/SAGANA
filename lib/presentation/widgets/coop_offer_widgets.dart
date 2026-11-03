import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/cooperative_offer_model.dart';
import 'crop_photo_capture.dart';
import 'management_modal.dart';

/// Shared pieces of the Offer to Cooperative price negotiation, used by both
/// the Manager's and the Farmer's screens so the two sides always show the
/// same wording, colours and amounts.

final NumberFormat _pesoFormat = NumberFormat('#,##0.00');

/// 1,234.50 with the peso sign.
String coopPeso(num amount) => '₱${_pesoFormat.format(amount)}';

/// A price per unit, `₱12.50/kg`. [unit] is the offer's unit (the batch's).
String coopPricePerKg(num price, [String? unit]) =>
    '${coopPeso(price)}/${unitOrDefault(unit)}';

/// A quantity with its unit, `10.75 sack`. The name is historical.
String coopKg(num kg, [String? unit]) => formatQuantityUnit(kg, unit);

String coopDateTime(DateTime d) =>
    DateFormat('MMM d, yyyy · h:mm a').format(d.toLocal());

// ─── Status ──────────────────────────────────────────────────────────────────

/// How one offer's status reads to one side. The stored status and
/// last_proposed_by decide it; [forFarmer] only changes the wording of the two
/// "whose turn" states.
class CoopOfferStatusView {
  final String label;
  final Color color;
  final IconData icon;

  /// True when this side has to answer (so the card can stand out).
  final bool needsMyResponse;

  const CoopOfferStatusView({
    required this.label,
    required this.color,
    required this.icon,
    this.needsMyResponse = false,
  });

  factory CoopOfferStatusView.of(
    BuildContext context,
    CooperativeOfferModel offer, {
    required bool forFarmer,
  }) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    if (offer.isCompleted) {
      return CoopOfferStatusView(
        label: l10n.coopStatusCompleted,
        color: AppConstants.primaryGreen,
        icon: Icons.verified_rounded,
      );
    }
    if (offer.isDelivered) {
      // The Manager / Officer has to confirm the receipt; the Farmer waits.
      return CoopOfferStatusView(
        label: forFarmer
            ? l10n.coopStatusDeliveredWaiting
            : l10n.coopStatusConfirmReceipt,
        color: forFarmer ? AppConstants.buyerBlue : AppConstants.warningAmber,
        icon: forFarmer
            ? Icons.hourglass_top_rounded
            : Icons.priority_high_rounded,
        needsMyResponse: !forFarmer,
      );
    }
    if (offer.isApproved) {
      // The Farmer has to deliver and upload the photo; the Manager waits.
      return CoopOfferStatusView(
        label: forFarmer
            ? l10n.coopStatusDeliverNow
            : l10n.coopStatusApprovedWaitingDelivery,
        color: forFarmer ? AppConstants.warningAmber : AppConstants.successGreen,
        icon: forFarmer
            ? Icons.local_shipping_outlined
            : Icons.check_circle_rounded,
        needsMyResponse: forFarmer,
      );
    }
    if (offer.isDeclined) {
      return CoopOfferStatusView(
        label: l10n.coopStatusDeclined,
        color: cs.error,
        icon: Icons.cancel_rounded,
      );
    }
    if (offer.isCancelled) {
      return CoopOfferStatusView(
        label: l10n.coopStatusCancelled,
        color: AppConstants.mutedSlate,
        icon: Icons.remove_circle_outline_rounded,
      );
    }
    // Open: the colour says whether the ball is in this side's court.
    final myTurn = forFarmer ? offer.awaitingFarmer : offer.awaitingCooperative;
    if (myTurn) {
      return CoopOfferStatusView(
        label: forFarmer
            ? l10n.coopStatusCounterReceived
            : l10n.coopStatusNeedsResponse,
        color: AppConstants.warningAmber,
        icon: Icons.priority_high_rounded,
        needsMyResponse: true,
      );
    }
    return CoopOfferStatusView(
      label: forFarmer
          ? l10n.coopStatusWaitingCooperative
          : l10n.coopStatusWaitingFarmer,
      color: AppConstants.buyerBlue,
      icon: Icons.hourglass_top_rounded,
    );
  }
}

class CoopOfferStatusBadge extends StatelessWidget {
  final CoopOfferStatusView view;
  const CoopOfferStatusBadge({super.key, required this.view});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: view.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        view.label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: view.color,
        ),
      ),
    );
  }
}

/// Filter for both sides' offer lists. The stored state decides membership;
/// the label is read from the same [CoopOfferStatusView] wording as the badge.
enum CoopOfferFilter {
  all,
  awaitingCooperative,
  awaitingFarmer,
  approved,
  delivered,
  completed,
  declined,
  cancelled,
}

extension CoopOfferFilterExt on CoopOfferFilter {
  bool matches(CooperativeOfferModel o) {
    switch (this) {
      case CoopOfferFilter.all:
        return true;
      case CoopOfferFilter.awaitingCooperative:
        return o.awaitingCooperative;
      case CoopOfferFilter.awaitingFarmer:
        return o.awaitingFarmer;
      case CoopOfferFilter.approved:
        return o.isApproved;
      case CoopOfferFilter.delivered:
        return o.isDelivered;
      case CoopOfferFilter.completed:
        return o.isCompleted;
      case CoopOfferFilter.declined:
        return o.isDeclined;
      case CoopOfferFilter.cancelled:
        return o.isCancelled;
    }
  }

  String label(AppLocalizations l10n, {required bool forFarmer}) {
    switch (this) {
      case CoopOfferFilter.all:
        return l10n.farmerMgmtAllFilter;
      case CoopOfferFilter.awaitingCooperative:
        return forFarmer
            ? l10n.coopStatusWaitingCooperative
            : l10n.coopStatusNeedsResponse;
      case CoopOfferFilter.awaitingFarmer:
        return forFarmer
            ? l10n.coopStatusCounterReceived
            : l10n.coopStatusWaitingFarmer;
      case CoopOfferFilter.approved:
        return l10n.coopStatusApproved;
      case CoopOfferFilter.delivered:
        return l10n.coopStatusDelivered;
      case CoopOfferFilter.completed:
        return l10n.coopStatusCompleted;
      case CoopOfferFilter.declined:
        return l10n.coopStatusDeclined;
      case CoopOfferFilter.cancelled:
        return l10n.coopStatusCancelled;
    }
  }

  Color color(BuildContext context, {required bool forFarmer}) {
    final cs = Theme.of(context).colorScheme;
    switch (this) {
      case CoopOfferFilter.all:
        return cs.primary;
      case CoopOfferFilter.awaitingCooperative:
        return forFarmer ? AppConstants.buyerBlue : AppConstants.warningAmber;
      case CoopOfferFilter.awaitingFarmer:
        return forFarmer ? AppConstants.warningAmber : AppConstants.buyerBlue;
      case CoopOfferFilter.approved:
        return AppConstants.successGreen;
      case CoopOfferFilter.delivered:
        return AppConstants.buyerBlue;
      case CoopOfferFilter.completed:
        return AppConstants.primaryGreen;
      case CoopOfferFilter.declined:
        return cs.error;
      case CoopOfferFilter.cancelled:
        return AppConstants.mutedSlate;
    }
  }
}

/// The offers a list shows: those in [filter], narrowed by the search [query].
/// The query matches the crop name, and also the Farmer's name when
/// [matchFarmerName] is set (the Manager's list; a Farmer only sees their own
/// offers). Case-insensitive; an empty or blank query matches everything. The
/// filter and the search combine: an offer must satisfy both.
List<CooperativeOfferModel> filterCoopOffers(
  Iterable<CooperativeOfferModel> offers, {
  required CoopOfferFilter filter,
  String query = '',
  bool matchFarmerName = false,
}) {
  final q = query.trim().toLowerCase();
  return offers.where((o) {
    if (!filter.matches(o)) return false;
    if (q.isEmpty) return true;
    return o.cropName.toLowerCase().contains(q) ||
        (matchFarmerName && o.farmerName.toLowerCase().contains(q));
  }).toList();
}

// ─── Price summary ───────────────────────────────────────────────────────────

/// The numbers of a negotiation: quantity, the Farmer's asking price, the
/// latest proposal and who made it, and the total at that price. Once the
/// offer is accepted it shows the agreed price and the settled total.
class CoopPriceSummary extends StatelessWidget {
  final CooperativeOfferModel offer;
  final bool forFarmer;

  const CoopPriceSummary({super.key, required this.offer, required this.forFarmer});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final accepted = offer.isAgreed;
    final settled = offer.isCompleted;
    final price = accepted
        ? (offer.agreedPricePerKg ?? offer.currentPricePerKg)
        : offer.currentPricePerKg;
    final total = accepted ? offer.confirmedAmount : offer.currentTotal;
    // The Farmer sees their own proposals as "You"; the Cooperative side is
    // always "Cooperative" (several Managers act for it).
    final proposedBy = offer.lastProposedBy == 'farmer'
        ? (forFarmer ? l10n.coopByYou : l10n.coopByFarmer)
        : l10n.coopByCooperative;

    Widget row(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: strong ? 15 : 13,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: strong ? AppConstants.primaryGreen : cs.onSurface,
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(l10n.coopQuantityLabel, coopKg(offer.offeredQuantityKg, offer.unit)),
        if (offer.askingPricePerKg != null)
          row(
            l10n.coopAskingPriceLabel,
            coopPricePerKg(offer.askingPricePerKg!, offer.unit),
          ),
        if (price != null) ...[
          row(
            accepted ? l10n.coopAgreedPriceLabel : l10n.coopLatestProposalLabel,
            coopPricePerKg(price, offer.unit),
            strong: true,
          ),
          if (!accepted && offer.isPending)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${l10n.coopProposedBy(proposedBy)} · ${l10n.coopRoundLabel(offer.negotiationRound)}',
                style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
              ),
            ),
        ] else
          row(l10n.coopLatestProposalLabel, l10n.coopNoPriceYet),
        if (total != null) ...[
          Divider(height: 18, color: cs.outline.withValues(alpha: 0.12)),
          row(
            settled
                ? l10n.coopTotalPaidLabel
                : accepted
                ? l10n.coopAgreedTotalLabel
                : l10n.coopTotalAtPriceLabel,
            coopPeso(total),
            strong: true,
          ),
        ],
      ],
    );
  }
}

// ─── History timeline ────────────────────────────────────────────────────────

class CoopNegotiationTimeline extends StatelessWidget {
  final List<CooperativeOfferEvent> events;
  final bool forFarmer;

  /// The unit the offer's prices are quoted in.
  final String unit;

  /// Manager / Officer view only: the name of the staff member behind each
  /// cooperative step (user id -> full name). Null for a Farmer, who sees
  /// "Cooperative" and never a staff identity.
  final Map<String, String>? staffNames;

  const CoopNegotiationTimeline({
    super.key,
    required this.events,
    required this.forFarmer,
    this.unit = kDefaultUnit,
    this.staffNames,
  });

  String _title(AppLocalizations l10n, CooperativeOfferEvent e) {
    switch (e.action) {
      case 'offered':
        return l10n.coopEventOffered;
      case 'countered':
        return l10n.coopEventCountered;
      case 'accepted':
        return l10n.coopEventAccepted;
      case 'declined':
        return l10n.coopEventDeclined;
      case 'cancelled':
        return l10n.coopEventCancelled;
      case 'delivered':
        return l10n.coopEventDelivered;
      case 'received':
        return l10n.coopEventReceived;
      default:
        return e.action;
    }
  }

  IconData _icon(String action) {
    switch (action) {
      case 'offered':
        return Icons.sell_outlined;
      case 'countered':
        return Icons.swap_horiz_rounded;
      case 'accepted':
        return Icons.check_circle_rounded;
      case 'delivered':
        return Icons.local_shipping_outlined;
      case 'received':
        return Icons.verified_rounded;
      case 'declined':
        return Icons.cancel_rounded;
      default:
        return Icons.remove_circle_outline_rounded;
    }
  }

  Color _color(BuildContext context, String action) {
    switch (action) {
      case 'accepted':
      case 'delivered':
      case 'received':
        return AppConstants.successGreen;
      case 'declined':
        return Theme.of(context).colorScheme.error;
      case 'cancelled':
        return AppConstants.mutedSlate;
      default:
        return AppConstants.primaryGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    if (events.isEmpty) {
      return Text(
        l10n.coopHistoryEmpty,
        style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          _TimelineRow(
            isLast: i == events.length - 1,
            icon: _icon(events[i].action),
            color: _color(context, events[i].action),
            title: _title(l10n, events[i]),
            price: events[i].pricePerKg == null
                ? null
                : coopPricePerKg(events[i].pricePerKg!, unit),
            who: events[i].byFarmer
                ? (forFarmer ? l10n.coopByYou : l10n.coopByFarmer)
                : (!forFarmer &&
                          staffNames != null &&
                          (staffNames![events[i].actorId] ?? '').isNotEmpty
                      ? '${l10n.coopByCooperative} · ${staffNames![events[i].actorId]}'
                      : l10n.coopByCooperative),
            when: coopDateTime(events[i].createdAt),
            note: events[i].note,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final bool isLast;
  final IconData icon;
  final Color color;
  final String title;
  final String? price;
  final String who;
  final String when;
  final String? note;

  const _TimelineRow({
    required this.isLast,
    required this.icon,
    required this.color,
    required this.title,
    required this.price,
    required this.who,
    required this.when,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Icon(icon, size: 20, color: color),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: cs.outline.withValues(alpha: 0.18),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      if (price != null)
                        Text(
                          price!,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$who · $when',
                    style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
                  ),
                  if (note != null && note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '“${note!.trim()}”',
                      style: GoogleFonts.inter(
                        fontSize: 12,
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
    );
  }
}

// ─── Section card ────────────────────────────────────────────────────────────

class CoopSectionCard extends StatelessWidget {
  final String? title;
  final Widget child;

  const CoopSectionCard({super.key, this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

// ─── Dialogs ─────────────────────────────────────────────────────────────────

/// What a counteroffer dialog returns: the price and an optional note.
class CoopCounterInput {
  final double pricePerKg;
  final String? note;
  const CoopCounterInput(this.pricePerKg, this.note);
}

/// Asks for a price per kg (and an optional note) with a live total.
/// [currentPrice] is rejected as "no change". Returns null if dismissed.
Future<CoopCounterInput?> showCoopPriceDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String priceLabel,
  required String confirmLabel,
  required double quantityKg,
  String unit = kDefaultUnit,
  double? currentPrice,
  double? initialPrice,
  bool askNote = true,
}) {
  return showManagementModal<CoopCounterInput>(
    context: context,
    builder: (_) => _CoopPriceDialog(
      title: title,
      subtitle: subtitle,
      priceLabel: priceLabel,
      confirmLabel: confirmLabel,
      quantityKg: quantityKg,
      unit: unit,
      currentPrice: currentPrice,
      initialPrice: initialPrice,
      askNote: askNote,
    ),
  );
}

class _CoopPriceDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String priceLabel;
  final String confirmLabel;
  final double quantityKg;
  final String unit;
  final double? currentPrice;
  final double? initialPrice;
  final bool askNote;

  const _CoopPriceDialog({
    required this.title,
    required this.subtitle,
    required this.priceLabel,
    required this.confirmLabel,
    required this.quantityKg,
    required this.unit,
    required this.currentPrice,
    required this.initialPrice,
    required this.askNote,
  });

  @override
  State<_CoopPriceDialog> createState() => _CoopPriceDialogState();
}

class _CoopPriceDialogState extends State<_CoopPriceDialog> {
  late final TextEditingController _price = TextEditingController(
    text: widget.initialPrice == null ? '' : widget.initialPrice!.toStringAsFixed(2),
  );
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_price.text.trim());

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final v = _value;
    if (v == null || v <= 0) {
      setState(() => _error = l10n.coopPriceInvalid);
      return;
    }
    if (widget.currentPrice != null && v == widget.currentPrice) {
      setState(() => _error = l10n.coopPriceSame);
      return;
    }
    final note = _note.text.trim();
    Navigator.pop(context, CoopCounterInput(v, note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final v = _value;
    return ManagementModalShell(
      title: widget.title,
      subtitle: widget.subtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.priceLabel,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _price,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [DecimalInputFormatter(maxWholeDigits: 6)],
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              prefixText: '₱ ',
              hintText: '0.00',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 8),
          if (widget.currentPrice != null)
            Text(
              l10n.coopCurrentPriceHint(
                coopPricePerKg(widget.currentPrice!, widget.unit),
              ),
              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          if (v != null && v > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.coopTotalPreview(
                  coopKg(widget.quantityKg, widget.unit),
                  coopPeso(moneyOf(v, widget.quantityKg)),
                ),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.primaryGreen,
                ),
              ),
            ),
          if (widget.askNote) ...[
            const SizedBox(height: 14),
            Text(
              l10n.coopNoteLabel,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            TextField(controller: _note, maxLines: 2, maxLength: 200),
          ],
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: widget.confirmLabel,
        onPrimary: _submit,
      ),
    );
  }
}

/// Plain confirmation with an optional reason field. Returns the reason text
/// ('' when left empty) on confirm, null when dismissed.
Future<String?> showCoopConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String? cancelLabel,
  String? reasonLabel,
  bool destructive = false,
}) {
  return showManagementModal<String>(
    context: context,
    builder: (_) => _CoopConfirmDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      reasonLabel: reasonLabel,
      destructive: destructive,
    ),
  );
}

class _CoopConfirmDialog extends StatefulWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final String? cancelLabel;
  final String? reasonLabel;
  final bool destructive;

  const _CoopConfirmDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.reasonLabel,
    required this.destructive,
  });

  @override
  State<_CoopConfirmDialog> createState() => _CoopConfirmDialogState();
}

class _CoopConfirmDialogState extends State<_CoopConfirmDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ManagementModalShell(
      title: widget.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.body,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (widget.reasonLabel != null) ...[
            const SizedBox(height: 14),
            Text(
              widget.reasonLabel!,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            TextField(controller: _reason, maxLines: 2, maxLength: 200),
          ],
        ],
      ),
      footer: ManagementModalActions(
        cancelLabel: widget.cancelLabel,
        primaryLabel: widget.confirmLabel,
        isDestructive: widget.destructive,
        onPrimary: () => Navigator.pop(context, _reason.text.trim()),
      ),
    );
  }
}

// ─── Delivery evidence ───────────────────────────────────────────────────────

/// What the delivery dialog returns: the photo the Farmer took and an optional
/// note.
class CoopDeliveryInput {
  final CapturedCropPhoto photo;
  final String? note;
  const CoopDeliveryInput(this.photo, this.note);
}

/// Asks the Farmer for the photo evidence of a delivery (camera only, like every
/// Farmer crop photo) and an optional note. Returns null if dismissed.
/// [title], [body] and [confirmLabel] default to the Offer to Cooperative wording;
/// the Marketplace "Mark as Delivered" step passes its own.
Future<CoopDeliveryInput?> showCoopDeliveryDialog(
  BuildContext context, {
  required String subtitle,
  String? title,
  String? body,
  String? confirmLabel,
}) {
  return showManagementModal<CoopDeliveryInput>(
    context: context,
    builder: (_) => _CoopDeliveryDialog(
      subtitle: subtitle,
      title: title,
      body: body,
      confirmLabel: confirmLabel,
    ),
  );
}

class _CoopDeliveryDialog extends StatefulWidget {
  final String subtitle;
  final String? title;
  final String? body;
  final String? confirmLabel;
  const _CoopDeliveryDialog({
    required this.subtitle,
    this.title,
    this.body,
    this.confirmLabel,
  });

  @override
  State<_CoopDeliveryDialog> createState() => _CoopDeliveryDialogState();
}

class _CoopDeliveryDialogState extends State<_CoopDeliveryDialog> {
  final _note = TextEditingController();
  CapturedCropPhoto? _photo;
  bool _missing = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _take() async {
    final photo = await captureCropPhoto(context);
    if (photo == null || !mounted) return;
    setState(() {
      _photo = photo;
      _missing = false;
    });
  }

  void _submit() {
    final photo = _photo;
    if (photo == null) {
      setState(() => _missing = true);
      return;
    }
    final note = _note.text.trim();
    Navigator.pop(context, CoopDeliveryInput(photo, note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return ManagementModalShell(
      title: widget.title ?? l10n.coopDeliverTitle,
      subtitle: widget.subtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.body ?? l10n.coopDeliverBody,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: Image.memory(
                _photo!.bytes,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          if (_photo != null) const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
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
          if (_missing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.coopDeliverPhotoRequired,
                style: GoogleFonts.inter(fontSize: 12, color: cs.error),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            l10n.coopNoteLabel,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          TextField(controller: _note, maxLines: 2, maxLength: 200),
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: widget.confirmLabel ?? l10n.coopDeliverConfirm,
        onPrimary: _submit,
      ),
    );
  }
}

/// The delivery photo of an offer, tappable to see it full size.
class CoopDeliveryPhoto extends StatelessWidget {
  final String url;
  const CoopDeliveryPhoto({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(24),
                child: Icon(Icons.broken_image_outlined, size: 48),
              ),
            ),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Image.network(
          url,
          height: 200,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: 120,
            alignment: Alignment.center,
            color: cs.surfaceContainerHighest,
            child: Icon(Icons.broken_image_outlined, color: cs.outline),
          ),
        ),
      ),
    );
  }
}

/// A single full-width action pinned to the bottom: the Farmer's "Mark as
/// Delivered" on an approved offer, the Manager / Officer's "Confirm Receipt"
/// on a delivered one.
class CoopHandoverBar extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final bool online;
  final VoidCallback onPressed;

  const CoopHandoverBar({
    super.key,
    required this.label,
    required this.icon,
    required this.busy,
    required this.online,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.15))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!online)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.coopOfflineNote,
                    style: GoogleFonts.inter(fontSize: 12, color: cs.error),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: online && !busy ? onPressed : null,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : Icon(icon, size: 18),
                  label: Text(
                    label,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Farmer's email and phone number on an offer, for the Manager / Officer.
/// (The Farmer's full name is already the heading above it.) Each line is shown
/// only when the Farmer has given it: nothing empty, nothing twice.
class CoopFarmerContact extends StatelessWidget {
  final CooperativeOfferModel offer;
  final bool compact;

  const CoopFarmerContact({super.key, required this.offer, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final email = (offer.farmerEmail ?? '').trim();
    final phone = (offer.farmerPhone ?? '').trim();
    if (email.isEmpty && phone.isEmpty) return const SizedBox.shrink();

    Widget line(IconData icon, String text) => Padding(
      padding: EdgeInsets.only(top: compact ? 2 : 3),
      child: Row(
        children: [
          Icon(icon, size: compact ? 12 : 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: compact ? 11.5 : 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (email.isNotEmpty) line(Icons.mail_outline_rounded, email),
        if (phone.isNotEmpty) line(Icons.phone_outlined, phone),
      ],
    );
  }
}
