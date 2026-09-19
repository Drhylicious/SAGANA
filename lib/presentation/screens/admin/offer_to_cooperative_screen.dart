import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/cooperative_offer_model.dart';
import '../../../data/repositories/cooperative_offer_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/management_modal.dart';

/// Same UI structure as PendingApprovalsScreen, by explicit instruction —
/// search bar, filter icon, status chips, crop/category filter panel. The
/// filter panel reuses the full crop_master category+crop set, which now
/// genuinely matches reality: any crop except Ginger (DA-AMAD-exclusive)
/// can be offered here (Scoped Fix decision, Admin Marketplace review) —
/// only Palay/Peanut confirmations settle into member_sales_transactions
/// (Balik-Tangkilik-eligible); confirm_cooperative_offer records any other
/// crop's confirmation directly on the offer row instead.
class OfferToCooperativeScreen extends StatefulWidget {
  const OfferToCooperativeScreen({super.key});

  @override
  State<OfferToCooperativeScreen> createState() => _OfferToCooperativeScreenState();
}

class _OfferToCooperativeScreenState extends State<OfferToCooperativeScreen> {
  final _repo = CooperativeOfferRepository();
  final _searchCtrl = TextEditingController();

  // Fetched once (the full pending/confirmed/declined set), then filtered
  // entirely client-side — switching status chips or typing a search term
  // no longer re-hits the network, matching Order Management's already-
  // smooth filtering. See M-marketplace-8. The crop/category filter icon
  // was removed entirely (per review decision) — All Listings remains the
  // only Marketplace screen with that control.
  List<CooperativeOfferModel> _allOffers = [];
  bool _isLoading = true;
  bool _hasLoadedOnce = false;

  String _searchQuery = '';
  String? _statusFilter; // null = All (pending + confirmed + declined)

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
    var list = _statusFilter == null
        ? _allOffers
        : _allOffers.where((o) => o.status == _statusFilter);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((o) =>
          o.cropName.toLowerCase().contains(q) ||
          o.farmerName.toLowerCase().contains(q));
    }
    return list.toList();
  }

  // Pending offers keep the existing review-sheet flow (confirm/decline
  // with the purchase-details form) unchanged. Approved (confirmed) and
  // Rejected (declined) offers are terminal — nothing left to review — so
  // tapping one now opens a dedicated, read-only Offer Details screen
  // instead, mirroring how Order Management opens OrderDetailScreen.
  void _openOffer(CooperativeOfferModel offer) async {
    if (offer.isPending) {
      final acted = await showManagementModal<bool>(
        context: context,
        builder: (_) => _ReviewOfferSheet(repo: _repo, offer: offer),
      );
      if (acted == true) _loadAll();
    } else {
      context.push(AppRoutes.offerDetail, extra: offer.id);
    }
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
          _TopBar(sagana: sagana, cs: cs),
          Expanded(
            child: RefreshIndicator(
              color: AppConstants.primaryGreen,
              onRefresh: _loadAll,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        // No filter icon here anymore — crop/category
                        // filtering stays exclusive to All Listings.
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

                        // Status chips — wording matches Pending Review
                        // exactly: Pending / Approved / Rejected, never
                        // "Confirmed" or "Declined" even though those are
                        // the real underlying status values. Switching is
                        // instant now, filtered client-side (M-marketplace-8).
                        SizedBox(
                          height: 34,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _FilterChip(
                                label: l10n.farmerMgmtAllFilter, active: _statusFilter == null, color: cs.primary,
                                onTap: () => setState(() => _statusFilter = null), cs: cs,
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: l10n.buyerOrderDetailPendingTimestamp, active: _statusFilter == 'pending', color: AppConstants.warningAmber,
                                onTap: () => setState(() => _statusFilter = 'pending'), cs: cs,
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: l10n.buyerOrderDetailStepApproved, active: _statusFilter == 'confirmed', color: AppConstants.successGreen,
                                onTap: () => setState(() => _statusFilter = 'confirmed'), cs: cs,
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: l10n.farmerMgmtStatusRejectedLabel, active: _statusFilter == 'declined', color: cs.error,
                                onTap: () => setState(() => _statusFilter = 'declined'), cs: cs,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        if (_filtered.isEmpty)
                          _EmptyOffersState(
                            cs: cs,
                            sagana: sagana,
                            hasActiveFilter: _searchQuery.isNotEmpty || _statusFilter != null,
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

// ─── Top App Bar ──────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final SaganaColors sagana;
  final ColorScheme cs;
  const _TopBar({required this.sagana, required this.cs});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary, size: 24),
                onPressed: () => context.pop(),
                tooltip: l10n.offerCoopBackTooltip,
              ),
              Expanded(
                child: Text(l10n.offerCoopTitle,
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w700, color: cs.primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Status Filter Chip — identical to Pending Review's ──────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.white : cs.onSurface,
          ),
        ),
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
  const _OfferCard({required this.offer, required this.cs, required this.sagana, required this.onTap});

  Color get _statusColor {
    if (offer.isConfirmed) return AppConstants.successGreen;
    if (offer.isDeclined) return cs.error;
    return AppConstants.warningAmber;
  }

  @override
  Widget build(BuildContext context) {
    // Same fix as _EntryCard in market_linking_screen.dart: a left-accent
    // color border can't coexist with borderRadius on the other uniform
    // sides — Flutter throws at paint time. The accent moves into its own
    // thin Container in a Row instead of a Border side.
    //
    // Every card is tappable now, regardless of status — pending opens the
    // existing review sheet, confirmed/declined open the new read-only
    // Offer Details screen (see _openOffer in the parent screen).
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
                  Container(width: 4, color: _statusColor),
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
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                                ),
                                child: Text(
                                  offer.statusLabel.toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: _statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            offer.farmerName,
                            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                '${offer.offeredQuantityKg.toStringAsFixed(0)} kg offered',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                offer.offeredLabel,
                                style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
                              ),
                            ],
                          ),
                          if (offer.isConfirmed) ...[
                            const SizedBox(height: 8),
                            Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
                            const SizedBox(height: 8),
                            Text(
                              'Approved for ${offer.confirmedQuantityKg?.toStringAsFixed(0) ?? '—'} kg · '
                              '₱${offer.confirmedAmount?.toStringAsFixed(2) ?? '—'}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppConstants.successGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else if (offer.isDeclined && offer.adminNotes != null && offer.adminNotes!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
                            const SizedBox(height: 8),
                            Text(
                              'Reason: ${offer.adminNotes}',
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
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Review Offer Sheet (confirm / decline) ───────────────────────────────────
class _ReviewOfferSheet extends StatefulWidget {
  final CooperativeOfferRepository repo;
  final CooperativeOfferModel offer;
  const _ReviewOfferSheet({required this.repo, required this.offer});

  @override
  State<_ReviewOfferSheet> createState() => _ReviewOfferSheetState();
}

class _ReviewOfferSheetState extends State<_ReviewOfferSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _qtyCtrl;
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: widget.offer.offeredQuantityKg.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await widget.repo.confirmCooperativeOffer(
        offerId: widget.offer.id,
        confirmedQuantityKg: double.parse(_qtyCtrl.text.trim()),
        confirmedAmount: double.parse(_amountCtrl.text.trim()),
        adminNotes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).offerCoopApproveFailed)),
      );
    }
  }

  Future<void> _decline() async {
    setState(() => _isSaving = true);
    try {
      await widget.repo.declineCooperativeOffer(
        offerId: widget.offer.id,
        adminNotes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).offerCoopRejectFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final offer = widget.offer;

    return ManagementModalShell(
      title: l10n.offerCoopOfferTitle(offer.cropName),
      subtitle: offer.farmerName,
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.offerCoopOffered(offer.offeredQuantityKg.toStringAsFixed(0)),
                style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 14),
            Text(l10n.offerCoopConfirmedQuantityLabel,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return l10n.offerCoopEnterValidQuantity;
                if (n > offer.offeredQuantityKg) {
                  return l10n.offerCoopCannotExceedOffered(offer.offeredQuantityKg.toStringAsFixed(0));
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Text(l10n.offerCoopAmountPaidLabel,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return l10n.offerCoopEnterValidAmount;
                return null;
              },
            ),
            const SizedBox(height: 12),
            Text(l10n.issueLoanNotes,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 6),
            TextFormField(controller: _notesCtrl, maxLines: 2),
          ],
        ),
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isSaving ? null : _decline,
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(l10n.commonReject, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _confirm,
              child: _isSaving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(l10n.farmerMgmtApproveAction, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
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