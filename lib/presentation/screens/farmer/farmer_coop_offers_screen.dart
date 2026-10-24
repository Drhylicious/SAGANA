import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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

/// Farmer > Profile > Cooperative Offers.
///
/// Every harvest the Farmer has offered to the Cooperative, with where each
/// negotiation stands. A counteroffer from the Cooperative is highlighted
/// because it is waiting for the Farmer. Tapping an offer opens the
/// negotiation screen (accept, counteroffer or cancel).
class FarmerCoopOffersScreen extends StatefulWidget {
  const FarmerCoopOffersScreen({super.key});

  @override
  State<FarmerCoopOffersScreen> createState() => _FarmerCoopOffersScreenState();
}

class _FarmerCoopOffersScreenState extends State<FarmerCoopOffersScreen> {
  final _repo = CooperativeOfferRepository();

  List<CooperativeOfferModel> _offers = [];
  bool _isLoading = true;
  CoopOfferFilter _filter = CoopOfferFilter.all;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _load();
  }

  Future<void> _load() async {
    final offers = await _repo.fetchMyOffers();
    if (!mounted) return;
    setState(() {
      _offers = offers;
      _isLoading = false;
    });
  }

  List<CooperativeOfferModel> get _filtered =>
      _offers.where(_filter.matches).toList();

  int _countFor(CoopOfferFilter f) => _offers.where(f.matches).length;

  Future<void> _open(CooperativeOfferModel offer) async {
    await context.push(AppRoutes.farmerCoopOfferDetail, extra: offer.id);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final list = _filtered;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.coopMyOffersTitle,
            onBack: () => context.pop(),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppConstants.primaryGreen,
              onRefresh: _load,
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SkeletonList(),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        SizedBox(
                          height: 34,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final f in CoopOfferFilter.values) ...[
                                ListingStatusFilterChip(
                                  label: f == CoopOfferFilter.all
                                      ? f.label(l10n, forFarmer: true)
                                      : '${f.label(l10n, forFarmer: true)} (${_countFor(f)})',
                                  active: _filter == f,
                                  color: f.color(context, forFarmer: true),
                                  onTap: () => setState(() => _filter = f),
                                  cs: cs,
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (list.isEmpty)
                          _Empty(
                            filtered: _offers.isNotEmpty,
                            cs: cs,
                            sagana: sagana,
                          )
                        else
                          for (final offer in list)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _OfferCard(
                                offer: offer,
                                cs: cs,
                                sagana: sagana,
                                onTap: () => _open(offer),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = CoopOfferStatusView.of(context, offer, forFarmer: true);
    final price = offer.isConfirmed
        ? (offer.agreedPricePerKg ?? offer.currentPricePerKg)
        : offer.currentPricePerKg;

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
                          if (offer.askingPricePerKg != null)
                            _line(
                              l10n.coopYourAskingLabel,
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
                          if (offer.isConfirmed && offer.confirmedAmount != null)
                            _line(
                              l10n.coopTotalPaidLabel,
                              coopPeso(offer.confirmedAmount!),
                              strong: true,
                              color: AppConstants.successGreen,
                            ),
                          if (view.needsMyResponse)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                l10n.coopTapToRespond,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppConstants.warningAmber,
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
}

class _Empty extends StatelessWidget {
  final bool filtered;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _Empty({required this.filtered, required this.cs, required this.sagana});

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
            filtered ? Icons.search_off_rounded : Icons.handshake_outlined,
            size: 48,
            color: (filtered ? cs.outline : AppConstants.successGreen)
                .withValues(alpha: 0.40),
          ),
          const SizedBox(height: 14),
          Text(
            filtered ? l10n.offerCoopNoOffersFiltered : l10n.coopMyOffersEmpty,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            filtered ? l10n.offerCoopTryDifferentFilter : l10n.coopMyOffersEmptyHint,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
