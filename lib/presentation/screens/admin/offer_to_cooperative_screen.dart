import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/cooperative_offer_model.dart';
import '../../../data/repositories/cooperative_offer_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/coop_offer_widgets.dart';
import '../../widgets/listing_filter_modal.dart' show ListingStatusFilterChip;
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// Manager > Marketplace > Offer to Cooperative.
///
/// Lists every offer a Farmer has made to the Cooperative. An offer is a price
/// negotiation: the Cooperative and the Farmer take turns accepting or
/// countering a price per kg. Tapping any offer opens the negotiation screen,
/// where the Manager replies. The chips separate the offers that need the
/// Manager's answer from the ones waiting on the Farmer, then the three ways
/// an offer ends: Accepted, Declined, Cancelled.
class OfferToCooperativeScreen extends StatefulWidget {
  const OfferToCooperativeScreen({super.key});

  @override
  State<OfferToCooperativeScreen> createState() => _OfferToCooperativeScreenState();
}

class _OfferToCooperativeScreenState extends State<OfferToCooperativeScreen> {
  final _repo = CooperativeOfferRepository();
  final _searchCtrl = TextEditingController();

  // Fetched once, then filtered client-side, so switching chips or typing a
  // search term never re-hits the network.
  List<CooperativeOfferModel> _allOffers = [];
  bool _isLoading = true;
  bool _hasLoadedOnce = false;

  String _searchQuery = '';
  CoopOfferFilter _filter = CoopOfferFilter.all;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text));
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!_hasLoadedOnce) setState(() => _isLoading = true);
    final offers = await _repo.fetchOffers();
    if (!mounted) return;
    setState(() {
      _allOffers = offers;
      _isLoading = false;
      _hasLoadedOnce = true;
    });
  }

  List<CooperativeOfferModel> get _filtered {
    Iterable<CooperativeOfferModel> list = _allOffers.where(_filter.matches);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((o) =>
          o.cropName.toLowerCase().contains(q) ||
          o.farmerName.toLowerCase().contains(q));
    }
    return list.toList();
  }

  int _countFor(CoopOfferFilter f) => _allOffers.where(f.matches).length;

  Future<void> _openOffer(CooperativeOfferModel offer) async {
    await context.push(AppRoutes.offerDetail, extra: offer.id);
    if (mounted) _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(title: l10n.offerCoopTitle, onBack: () => context.pop()),
          Expanded(
            child: RefreshIndicator(
              color: AppConstants.primaryGreen,
              onRefresh: _loadAll,
              child: _isLoading
                  ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: l10n.offerCoopSearchHint,
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    onPressed: () => _searchCtrl.clear(),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 34,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final f in CoopOfferFilter.values) ...[
                                ListingStatusFilterChip(
                                  label: f == CoopOfferFilter.all
                                      ? f.label(l10n, forFarmer: false)
                                      : '${f.label(l10n, forFarmer: false)} (${_countFor(f)})',
                                  active: _filter == f,
                                  color: f.color(context, forFarmer: false),
                                  onTap: () => setState(() => _filter = f),
                                  cs: cs,
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_filtered.isEmpty)
                          _EmptyOffersState(
                            cs: cs,
                            sagana: sagana,
                            hasActiveFilter:
                                _searchQuery.isNotEmpty || _filter != CoopOfferFilter.all,
                          )
                        else
                          ..._filtered.map(
                            (offer) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _OfferCard(
                                offer: offer,
                                cs: cs,
                                sagana: sagana,
                                onTap: () => _openOffer(offer),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Offer Card ────────────────────────────────────────────────────────────────
class _OfferCard extends StatelessWidget {
  final CooperativeOfferModel offer;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onTap;
  const _OfferCard({
    required this.offer,
    required this.cs,
    required this.sagana,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = CoopOfferStatusView.of(context, offer, forFarmer: false);
    final price = offer.isConfirmed
        ? (offer.agreedPricePerKg ?? offer.currentPricePerKg)
        : offer.currentPricePerKg;

    // The accent is its own thin Container in a Row, not a Border side: a
    // coloured one-sided border can't be combined with a border radius.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          child: Container(
            decoration: BoxDecoration(
              color: sagana.cardBackground,
              border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: view.color),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  offer.cropName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                              CoopOfferStatusBadge(view: view),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            offer.farmerName,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                coopKg(offer.offeredQuantityKg),
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                offer.offeredLabel,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: cs.outline,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
                          const SizedBox(height: 8),
                          // The numbers that matter at a glance: the Farmer's
                          // ask and the price on the table now.
                          if (offer.askingPricePerKg != null)
                            _line(
                              l10n.coopAskingPriceLabel,
                              coopPricePerKg(offer.askingPricePerKg!),
                            ),
                          if (price != null && price != offer.askingPricePerKg)
                            _line(
                              offer.isConfirmed
                                  ? l10n.coopAgreedPriceLabel
                                  : l10n.coopLatestProposalLabel,
                              coopPricePerKg(price),
                              strong: true,
                            ),
                          if (price == null)
                            _line(l10n.coopLatestProposalLabel, l10n.coopNoPriceYet),
                          if (offer.isConfirmed && offer.confirmedAmount != null)
                            _line(
                              l10n.coopTotalPaidLabel,
                              coopPeso(offer.confirmedAmount!),
                              strong: true,
                              color: AppConstants.successGreen,
                            ),
                          if (offer.isDeclined &&
                              offer.adminNotes != null &&
                              offer.adminNotes!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                l10n.coopReasonLine(offer.adminNotes!),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String value, {bool strong = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: color ?? cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyOffersState extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;
  final bool hasActiveFilter;
  const _EmptyOffersState({required this.cs, required this.sagana, this.hasActiveFilter = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          Icon(
            hasActiveFilter ? Icons.search_off_rounded : Icons.handshake_outlined,
            size: 48,
            color: (hasActiveFilter ? cs.outline : AppConstants.successGreen).withValues(alpha: 0.40),
          ),
          const SizedBox(height: 14),
          Text(hasActiveFilter ? l10n.offerCoopNoOffersFiltered : l10n.offerCoopNoOffersYet,
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(
            hasActiveFilter
                ? l10n.offerCoopTryDifferentFilter
                : l10n.offerCoopWillAppearHere,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
