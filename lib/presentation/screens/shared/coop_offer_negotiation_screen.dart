import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/db_error_utils.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/cooperative_offer_model.dart';
import '../../../data/repositories/cooperative_offer_repository.dart';
import '../../../data/repositories/workflow_event_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/staff_permission_service.dart';
import '../../../data/services/table_change_watcher.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/coop_offer_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/view_only_banner.dart';
import '../../widgets/sub_page_top_bar.dart';

/// One Offer to Cooperative negotiation, for either side.
///
/// The Manager opens it from Marketplace > Offer to Cooperative and the Farmer
/// from Profile > Cooperative Offers (or a notification). It shows the price
/// summary, the whole negotiation history and, while the offer is open, the
/// actions this side may take: accept the latest price (only when it is the
/// other side's price), send a counteroffer, or end the negotiation (Decline
/// for the Cooperative, Cancel for the Farmer). The database re-checks every
/// one of these, including that the price on screen is still the latest.
class CoopOfferNegotiationScreen extends StatefulWidget {
  final String offerId;
  final bool isFarmer;

  const CoopOfferNegotiationScreen({
    super.key,
    required this.offerId,
    required this.isFarmer,
  });

  @override
  State<CoopOfferNegotiationScreen> createState() =>
      _CoopOfferNegotiationScreenState();
}

class _CoopOfferNegotiationScreenState
    extends State<CoopOfferNegotiationScreen> {
  final _repo = CooperativeOfferRepository();
  TableChangeWatcher? _watcher;
  bool _isLoading = true;
  bool _busy = false;
  CooperativeOfferModel? _offer;
  List<CooperativeOfferEvent> _events = [];
  Map<String, String> _staffNames = const {};

  bool get _forFarmer => widget.isFarmer;

  /// The cooperative's answers (accept, counter, decline, confirm receipt)
  /// belong to the Marketplace module: a View Only Officer is told why and
  /// nothing is sent. The Farmer's side has no such check, and the Manager
  /// always passes.
  bool _cooperativeMayAct() =>
      _forFarmer || requireManage(context, StaffModule.marketplace);

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _load();
    // The other side answering (a counteroffer, an acceptance, a decline) must
    // change the buttons here without a pull-down: Accept / Decline /
    // Counteroffer follow whose turn it is.
    _watcher = TableChangeWatcher(
      tables: const ['cooperative_purchase_offers'],
      onChange: () {
        if (mounted && !_busy) _load(showSpinner: false);
      },
    )..start();
  }

  @override
  void dispose() {
    _watcher?.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchOfferById(widget.offerId),
      _repo.fetchHistory(widget.offerId),
    ]);
    final events = results[1] as List<CooperativeOfferEvent>;
    // The Manager / Officer sees which staff member took each cooperative step;
    // a Farmer never gets these names.
    final names = _forFarmer
        ? const <String, String>{}
        : await WorkflowEventRepository().fetchNames([
            for (final e in events)
              if (!e.byFarmer && e.actorId != null) e.actorId!,
          ]);
    if (!mounted) return;
    setState(() {
      _offer = results[0] as CooperativeOfferModel?;
      _events = events;
      _staffNames = names;
      _isLoading = false;
    });
  }

  /// Runs one negotiation action. On a refusal (someone answered first, the
  /// price moved, the offer closed) the message is shown and the screen is
  /// reloaded so the user sees the latest price before trying again.
  Future<void> _run(Future<void> Function() action, String successMessage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      AppToast.show(context, successMessage);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load(showSpinner: false);
  }

  Future<void> _accept(CooperativeOfferModel offer) async {
    if (!_cooperativeMayAct()) return;
    final l10n = AppLocalizations.of(context);
    final price = offer.currentPricePerKg;
    if (price == null) return;
    final confirmed = await showCoopConfirmDialog(
      context,
      title: l10n.coopAcceptTitle,
      body: l10n.coopAcceptBody(
        coopPricePerKg(price, offer.unit),
        coopKg(offer.offeredQuantityKg, offer.unit),
        offer.cropName,
        coopPeso(moneyOf(price, offer.offeredQuantityKg)),
      ),
      confirmLabel: l10n.coopAcceptConfirm,
    );
    if (confirmed == null) return;
    await _run(
      () => _repo.acceptOffer(
        offerId: offer.id,
        expectedRound: offer.negotiationRound,
        asCooperative: !_forFarmer,
        kg: offer.offeredQuantityKg,
        unit: offer.unit,
        amount: moneyOf(price, offer.offeredQuantityKg),
      ),
      l10n.coopToastAccepted,
    );
  }

  Future<void> _counter(CooperativeOfferModel offer) async {
    if (!_cooperativeMayAct()) return;
    final l10n = AppLocalizations.of(context);
    final input = await showCoopPriceDialog(
      context,
      title: offer.hasPrice ? l10n.coopCounterTitle : l10n.coopProposeTitle,
      subtitle: l10n.coopCounterSubtitle(
        offer.cropName,
        coopKg(offer.offeredQuantityKg, offer.unit),
      ),
      priceLabel: l10n.coopPriceLabel(unitOrDefault(offer.unit)),
      confirmLabel: offer.hasPrice
          ? l10n.coopCounterSend
          : l10n.coopActionProposePrice,
      quantityKg: offer.offeredQuantityKg,
      unit: offer.unit,
      currentPrice: offer.currentPricePerKg,
    );
    if (input == null) return;
    await _run(
      () => _repo.counterOffer(
        offerId: offer.id,
        pricePerKg: input.pricePerKg,
        expectedRound: offer.negotiationRound,
        note: input.note,
        asCooperative: !_forFarmer,
        unit: offer.unit,
      ),
      l10n.coopToastCountered,
    );
  }

  /// The Farmer hands the approved harvest over: a camera photo is required.
  Future<void> _deliver(CooperativeOfferModel offer) async {
    final l10n = AppLocalizations.of(context);
    final input = await showCoopDeliveryDialog(
      context,
      subtitle: l10n.coopCounterSubtitle(
        offer.cropName,
        coopKg(offer.offeredQuantityKg, offer.unit),
      ),
    );
    if (input == null) return;
    await _run(
      () => _repo.deliverOffer(
        offerId: offer.id,
        photoBytes: input.photo.bytes,
        photoExtension: input.photo.extension,
        note: input.note,
      ),
      l10n.coopToastDelivered,
    );
  }

  /// The Manager / Officer confirms the physical receipt: the sale is settled and
  /// the harvest enters cooperative inventory.
  Future<void> _confirmReceipt(CooperativeOfferModel offer) async {
    if (!_cooperativeMayAct()) return;
    final l10n = AppLocalizations.of(context);
    final amount = offer.confirmedAmount ??
        moneyOf(offer.agreedPricePerKg ?? 0, offer.offeredQuantityKg);
    final note = await showCoopConfirmDialog(
      context,
      title: l10n.coopReceiptTitle,
      body: l10n.coopReceiptBody(
        coopKg(offer.offeredQuantityKg, offer.unit),
        offer.cropName,
        offer.farmerName,
        coopPeso(amount),
      ),
      confirmLabel: l10n.coopReceiptConfirm,
      reasonLabel: l10n.coopNoteLabel,
    );
    if (note == null) return;
    await _run(
      () => _repo.confirmReceipt(
        offerId: offer.id,
        note: note.isEmpty ? null : note,
        kg: offer.offeredQuantityKg,
        unit: offer.unit,
        amount: amount,
      ),
      l10n.coopToastReceived,
    );
  }

  Future<void> _end(CooperativeOfferModel offer) async {
    if (!_cooperativeMayAct()) return;
    final l10n = AppLocalizations.of(context);
    if (_forFarmer) {
      final note = await showCoopConfirmDialog(
        context,
        title: l10n.coopCancelTitle,
        body: l10n.coopCancelBody,
        confirmLabel: l10n.coopCancelConfirm,
        cancelLabel: l10n.coopKeepOffer,
        reasonLabel: l10n.coopNoteLabel,
        destructive: true,
      );
      if (note == null) return;
      await _run(
        () => _repo.cancelOffer(
          offerId: offer.id,
          note: note.isEmpty ? null : note,
        ),
        l10n.coopToastCancelled,
      );
    } else {
      final reason = await showCoopConfirmDialog(
        context,
        title: l10n.coopDeclineTitle,
        body: l10n.coopDeclineBody,
        confirmLabel: l10n.coopDeclineConfirm,
        reasonLabel: l10n.coopDeclineReasonLabel,
        destructive: true,
      );
      if (reason == null) return;
      await _run(
        () => _repo.declineOffer(
          offerId: offer.id,
          expectedRound: offer.negotiationRound,
          note: reason.isEmpty ? null : reason,
        ),
        l10n.coopToastDeclined,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final offer = _offer;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(
            title: offer != null
                ? l10n.coopOfferTitle(offer.cropName)
                : l10n.coopOfferDetailsTitle,
            onBack: () => context.pop(),
          ),
          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : offer == null
                ? Center(
                    child: Text(
                      l10n.coopOfferNotFound,
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
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        _StatusCard(offer: offer, forFarmer: _forFarmer),
                        const SizedBox(height: 16),
                        CoopSectionCard(
                          title: l10n.coopNegotiationTitle,
                          child: CoopPriceSummary(
                            offer: offer,
                            forFarmer: _forFarmer,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (!_forFarmer) ...[
                          _FarmerCard(offer: offer),
                          const SizedBox(height: 16),
                        ],
                        _BatchCard(offer: offer),
                        const SizedBox(height: 16),
                        if (offer.deliveryPhotoUrl != null) ...[
                          _DeliveryCard(offer: offer),
                          const SizedBox(height: 16),
                        ],
                        CoopSectionCard(
                          title: l10n.coopHistoryTitle,
                          child: CoopNegotiationTimeline(
                            events: _events,
                            forFarmer: _forFarmer,
                            unit: offer.unit,
                            staffNames: _forFarmer ? null : _staffNames,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: offer == null
          ? null
          : offer.isPending
          ? CoopOfferActionBar(
              offer: offer,
              forFarmer: _forFarmer,
              busy: _busy,
              online: ConnectivityService.instance.isOnline,
              onAccept: () => _accept(offer),
              onCounter: () => _counter(offer),
              onEnd: () => _end(offer),
            )
          // Approved: the Farmer delivers. Delivered: the Manager / Officer
          // confirms the receipt. Nobody else has an action on these.
          : (offer.awaitingDelivery && _forFarmer)
          ? CoopHandoverBar(
              label: l10n.coopActionDeliver,
              icon: Icons.local_shipping_outlined,
              busy: _busy,
              online: ConnectivityService.instance.isOnline,
              onPressed: () => _deliver(offer),
            )
          : (offer.awaitingReceipt && !_forFarmer)
          ? CoopHandoverBar(
              label: l10n.coopActionConfirmReceipt,
              icon: Icons.verified_rounded,
              busy: _busy,
              online: ConnectivityService.instance.isOnline,
              onPressed: () => _confirmReceipt(offer),
            )
          : null,
    );
  }
}

// ─── Status card ─────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final CooperativeOfferModel offer;
  final bool forFarmer;
  const _StatusCard({required this.offer, required this.forFarmer});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final view = CoopOfferStatusView.of(context, offer, forFarmer: forFarmer);

    final String message;
    if (offer.isCompleted) {
      message = l10n.coopClosedCompleted;
    } else if (offer.isDelivered) {
      message = forFarmer
          ? l10n.coopDeliveredFarmerMsg
          : l10n.coopDeliveredStaffMsg;
    } else if (offer.isApproved) {
      message = forFarmer
          ? l10n.coopApprovedFarmerMsg
          : l10n.coopApprovedStaffMsg;
    } else if (offer.isDeclined) {
      message = l10n.coopClosedDeclined;
    } else if (offer.isCancelled) {
      message = l10n.coopClosedCancelled;
    } else if (forFarmer ? offer.awaitingFarmer : offer.awaitingCooperative) {
      message = offer.hasPrice
          ? l10n.coopTurnYourMove
          : l10n.coopTurnNeedFirstPrice;
    } else {
      message = forFarmer
          ? l10n.coopTurnWaitingCooperative
          : l10n.coopTurnWaitingFarmer;
    }

    return CoopSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(view.icon, size: 18, color: view.color),
              const SizedBox(width: 8),
              CoopOfferStatusBadge(view: view),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (offer.isDeclined &&
              offer.adminNotes != null &&
              offer.adminNotes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.coopReasonLine(offer.adminNotes!),
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
}

// ─── Delivery evidence card ──────────────────────────────────────────────────

class _DeliveryCard extends StatelessWidget {
  final CooperativeOfferModel offer;
  const _DeliveryCard({required this.offer});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return CoopSectionCard(
      title: l10n.coopDeliveryPhotoTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoopDeliveryPhoto(url: offer.deliveryPhotoUrl!),
          const SizedBox(height: 10),
          if (offer.deliveredAt != null)
            Text(
              l10n.coopDeliveredOn(coopDateTime(offer.deliveredAt!)),
              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          if (offer.deliveryNote != null && offer.deliveryNote!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '“${offer.deliveryNote}”',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          if (offer.receivedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.coopReceivedOn(coopDateTime(offer.receivedAt!)),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.successGreen,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Farmer + batch cards ────────────────────────────────────────────────────

class _FarmerCard extends StatelessWidget {
  final CooperativeOfferModel offer;
  const _FarmerCard({required this.offer});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CoopSectionCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppConstants.primaryGreen.withValues(alpha: 0.12),
            backgroundImage: offer.farmerPhotoUrl != null
                ? NetworkImage(offer.farmerPhotoUrl!)
                : null,
            onBackgroundImageError: offer.farmerPhotoUrl != null
                ? (_, __) {}
                : null,
            child: offer.farmerPhotoUrl != null
                ? null
                : Text(
                    offer.farmerName.isNotEmpty
                        ? offer.farmerName[0].toUpperCase()
                        : 'F',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      color: AppConstants.primaryGreen,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.farmerName,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                CoopFarmerContact(offer: offer),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchCard extends StatelessWidget {
  final CooperativeOfferModel offer;
  const _BatchCard({required this.offer});

  Widget _field(String label, String value, ColorScheme cs) => Column(
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return CoopSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            offer.cropName,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            offer.offeredLabel,
            style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
          ),
          if (offer.batchNumber != null ||
              offer.harvestDate != null ||
              offer.category != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                if (offer.batchNumber != null)
                  _field(
                    l10n.coopBatchLabel,
                    formatBatchNumber(offer.batchNumber),
                    cs,
                  ),
                if (offer.harvestDate != null)
                  _field(l10n.coopFreshnessLabel, offer.harvestedLabel, cs),
                if (offer.category != null)
                  _field(l10n.coopCategoryLabel, offer.category!, cs),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Action bar ──────────────────────────────────────────────────────────────

/// Pinned to the bottom while the offer is open. Accept and Counteroffer only
/// appear on this side's turn; ending the negotiation is always available.
class CoopOfferActionBar extends StatelessWidget {
  final CooperativeOfferModel offer;
  final bool forFarmer;
  final bool busy;
  final bool online;
  final VoidCallback onAccept;
  final VoidCallback onCounter;
  final VoidCallback onEnd;

  const CoopOfferActionBar({
    required this.offer,
    required this.forFarmer,
    required this.busy,
    required this.online,
    required this.onAccept,
    required this.onCounter,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final myTurn = forFarmer ? offer.awaitingFarmer : offer.awaitingCooperative;
    final canAct = online && !busy;

    // The Manager / Officer who just sent a counteroffer has nothing to do until
    // the Farmer answers: no buttons at all (the status card says who is up).
    // Decline Offer comes back when the Farmer answers with a counteroffer.
    if (!forFarmer && !myTurn) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: cs.outline.withValues(alpha: 0.15)),
        ),
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
              // Both sides share one layout (the Farmer answering a counteroffer
              // sees the same buttons as the Manager / Officer answering an offer):
              //   [ Accept Offer ] [ Decline Offer ]
              //   [   Submit Counteroffer          ]
              // Accepting needs no counteroffer first: it approves the price on
              // the table as is. Only the side whose turn it is gets them.
              if (myTurn)
                ..._turnActions(context, canAct)
              else if (forFarmer)
                // Waiting for the Cooperative: the Farmer can still withdraw.
                SizedBox(
                  width: double.infinity,
                  child: _endButton(context, canAct, l10n.coopActionCancel),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The red outlined "end the negotiation" button.
  Widget _endButton(BuildContext context, bool canAct, String label) {
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: canAct ? onEnd : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.error,
        side: BorderSide(
          color: canAct ? cs.error : cs.outline.withValues(alpha: 0.30),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// The buttons of the side whose turn it is (Manager / Officer or Farmer):
  ///   with a price on the table:
  ///       [ Accept Offer ] [ Decline Offer ]
  ///       [   Submit Counteroffer          ]
  ///   with no price yet (an older offer, Cooperative only): Propose a Price,
  ///   then Decline Offer.
  /// For the Farmer, "Decline Offer" ends the negotiation exactly as Cancel
  /// Offer does (same confirmation, same release of the reserved stock).
  List<Widget> _turnActions(BuildContext context, bool canAct) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    final decline = _endButton(context, canAct, l10n.coopActionDecline);
    final counter = SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: canAct ? onCounter : null,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            offer.hasPrice
                ? l10n.coopActionSubmitCounter
                : l10n.coopActionProposePrice,
            maxLines: 1,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );

    if (!offer.hasPrice) {
      return [counter, const SizedBox(height: 10), SizedBox(width: double.infinity, child: decline)];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          l10n.coopCurrentPriceHint(
            coopPricePerKg(offer.currentPricePerKg!, offer.unit),
          ),
          style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ),
      Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: canAct ? onAccept : null,
              child: busy
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
                      child: Text(
                        l10n.coopActionAcceptOffer,
                        maxLines: 1,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: decline),
        ],
      ),
      const SizedBox(height: 10),
      counter,
    ];
  }
}
