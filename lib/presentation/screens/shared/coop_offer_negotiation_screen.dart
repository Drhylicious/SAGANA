import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/db_error_utils.dart';
import '../../../data/models/cooperative_offer_model.dart';
import '../../../data/repositories/cooperative_offer_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/coop_offer_widgets.dart';
import '../../widgets/skeleton.dart';
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
  bool _isLoading = true;
  bool _busy = false;
  CooperativeOfferModel? _offer;
  List<CooperativeOfferEvent> _events = [];

  bool get _forFarmer => widget.isFarmer;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchOfferById(widget.offerId),
      _repo.fetchHistory(widget.offerId),
    ]);
    if (!mounted) return;
    setState(() {
      _offer = results[0] as CooperativeOfferModel?;
      _events = results[1] as List<CooperativeOfferEvent>;
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
    final l10n = AppLocalizations.of(context);
    final price = offer.currentPricePerKg;
    if (price == null) return;
    final confirmed = await showCoopConfirmDialog(
      context,
      title: l10n.coopAcceptTitle,
      body: l10n.coopAcceptBody(
        coopPricePerKg(price),
        coopKg(offer.offeredQuantityKg),
        offer.cropName,
        coopPeso(price * offer.offeredQuantityKg),
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
        amount: price * offer.offeredQuantityKg,
      ),
      l10n.coopToastAccepted,
    );
  }

  Future<void> _counter(CooperativeOfferModel offer) async {
    final l10n = AppLocalizations.of(context);
    final input = await showCoopPriceDialog(
      context,
      title: offer.hasPrice ? l10n.coopCounterTitle : l10n.coopProposeTitle,
      subtitle: l10n.coopCounterSubtitle(
        offer.cropName,
        coopKg(offer.offeredQuantityKg),
      ),
      priceLabel: l10n.coopPriceLabel,
      confirmLabel: offer.hasPrice
          ? l10n.coopCounterSend
          : l10n.coopActionProposePrice,
      quantityKg: offer.offeredQuantityKg,
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
      ),
      l10n.coopToastCountered,
    );
  }

  Future<void> _end(CooperativeOfferModel offer) async {
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
                        CoopSectionCard(
                          title: l10n.coopHistoryTitle,
                          child: CoopNegotiationTimeline(
                            events: _events,
                            forFarmer: _forFarmer,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: (offer != null && offer.isPending)
          ? _ActionBar(
              offer: offer,
              forFarmer: _forFarmer,
              busy: _busy,
              online: ConnectivityService.instance.isOnline,
              onAccept: () => _accept(offer),
              onCounter: () => _counter(offer),
              onEnd: () => _end(offer),
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
    if (offer.isConfirmed) {
      message = l10n.coopClosedAccepted;
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
                if (offer.farmerPhone != null)
                  Text(
                    offer.farmerPhone!,
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
                  _field(l10n.coopBatchLabel, '#${offer.batchNumber}', cs),
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
class _ActionBar extends StatelessWidget {
  final CooperativeOfferModel offer;
  final bool forFarmer;
  final bool busy;
  final bool online;
  final VoidCallback onAccept;
  final VoidCallback onCounter;
  final VoidCallback onEnd;

  const _ActionBar({
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
              if (myTurn)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: canAct ? onCounter : null,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            offer.hasPrice
                                ? l10n.coopActionCounter
                                : l10n.coopActionProposePrice,
                            maxLines: 1,
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    if (offer.hasPrice) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
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
                                    l10n.coopActionAccept(
                                      coopPricePerKg(offer.currentPricePerKg!),
                                    ),
                                    maxLines: 1,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
              TextButton(
                onPressed: canAct ? onEnd : null,
                style: TextButton.styleFrom(foregroundColor: cs.error),
                child: Text(
                  forFarmer
                      ? l10n.coopActionCancel
                      : l10n.coopActionDecline,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
