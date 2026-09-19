import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/admin_listing_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/listing_filter_modal.dart' show ListingStatusFilterChip;

class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  final _repo = AdminListingRepository();
  final _searchCtrl = TextEditingController();

  // Fetched once (the full pending/approved/rejected outcome set), then
  // filtered entirely client-side below — switching status chips or
  // typing a search term no longer re-hits the network, matching Order
  // Management's already-smooth filtering instead of visibly reloading
  // on every tap. See M-marketplace-8.
  List<AdminListingModel> _allListings = [];
  bool _isLoading = true;
  bool _hasLoadedOnce = false;
  bool _isOnline = true;

  String _searchQuery = '';
  String? _statusFilter; // null = All (pending_review + approved + rejected)

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_hasLoadedOnce) setState(() => _isLoading = true);
    final listings = await _repo.fetchReviewListings();
    if (!mounted) return;
    setState(() {
      _allListings = listings;
      _isLoading = false;
      _hasLoadedOnce = true;
    });
  }

  List<AdminListingModel> get _filtered {
    var list = _statusFilter == null
        ? _allListings
        : _allListings.where((l) => l.status == _statusFilter);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((l) =>
          l.cropName.toLowerCase().contains(q) ||
          l.farmerName.toLowerCase().contains(q) ||
          (l.variety?.toLowerCase().contains(q) ?? false));
    }
    return list.toList();
  }

  Future<void> _quickApprove(AdminListingModel listing) async {
    await _repo.approveListing(listing.id);
    _showSnack('${listing.cropName} listing approved.', isSuccess: true);
    _load();
  }

  void _showSnack(String msg, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: isSuccess ? AppConstants.successGreen : AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
      ),
    );
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
              onRefresh: _load,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        // ── Search — no filter icon here anymore; crop/
                        // category filtering was removed from this screen,
                        // it stays exclusive to All Listings.
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: l10n.marketplaceSearchHint,
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

                        // ── Status chips — instant, client-side switching ──
                        SizedBox(
                          height: 34,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              ListingStatusFilterChip(
                                label: l10n.farmerMgmtAllFilter, active: _statusFilter == null, color: cs.primary,
                                onTap: () => setState(() => _statusFilter = null), cs: cs,
                              ),
                              const SizedBox(width: 8),
                              ListingStatusFilterChip(
                                label: l10n.buyerOrderDetailPendingTimestamp, active: _statusFilter == 'pending_review', color: AppConstants.warningAmber,
                                onTap: () => setState(() => _statusFilter = 'pending_review'), cs: cs,
                              ),
                              const SizedBox(width: 8),
                              ListingStatusFilterChip(
                                label: l10n.buyerOrderDetailStepApproved, active: _statusFilter == 'approved', color: AppConstants.successGreen,
                                onTap: () => setState(() => _statusFilter = 'approved'), cs: cs,
                              ),
                              const SizedBox(width: 8),
                              ListingStatusFilterChip(
                                label: l10n.farmerMgmtStatusRejectedLabel, active: _statusFilter == 'rejected', color: cs.error,
                                onTap: () => setState(() => _statusFilter = 'rejected'), cs: cs,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── List / empty state ────────────────────────────
                        if (_filtered.isEmpty)
                          _EmptyPendingState(
                            cs: cs,
                            sagana: sagana,
                            hasActiveFilter: _searchQuery.isNotEmpty || _statusFilter != null,
                          )
                        else
                          ..._filtered.map(
                            (listing) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PendingListingCard(
                                listing: listing,
                                cs: cs,
                                sagana: sagana,
                                onTap: () => context
                                    .push(AppRoutes.listingReview, extra: listing.id)
                                    .then((_) => _load()),
                                onQuickApprove: (_isOnline && listing.isPending)
                                    ? () => _quickApprove(listing)
                                    : null,
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
                child: Text(l10n.pendingApprovalsTitle,
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


// ─── Pending Listing Card ─────────────────────────────────────────────────────
class _PendingListingCard extends StatelessWidget {
  final AdminListingModel listing;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onTap;
  final VoidCallback? onQuickApprove;

  const _PendingListingCard({
    required this.listing,
    required this.cs,
    required this.sagana,
    required this.onTap,
    this.onQuickApprove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final card = Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (listing.listingPhotoUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppConstants.radiusLg)),
              child: AspectRatio(
                aspectRatio: 16 / 7,
                child: Image.network(
                  listing.listingPhotoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _PhotoPlaceholder(cs: cs, cropName: listing.cropName),
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppConstants.radiusLg)),
              child: _PhotoPlaceholder(cs: cs, cropName: listing.cropName),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        listing.variety != null ? '${listing.cropName} — ${listing.variety}' : listing.cropName,
                        style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (listing.hasStockWarning)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withValues(alpha: 0.50),
                          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                        ),
                        child: Text('⚠ Stock',
                            style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: cs.error)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppConstants.primaryContainer),
                      child: Center(
                        child: Text(
                          listing.farmerName.isNotEmpty ? listing.farmerName[0].toUpperCase() : 'F',
                          style: GoogleFonts.poppins(
                              fontSize: 10, fontWeight: FontWeight.w700, color: AppConstants.onPrimaryContainer),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(listing.farmerName,
                          style: GoogleFonts.inter(fontSize: 12, color: cs.onSurface), overflow: TextOverflow.ellipsis),
                    ),
                    Text(listing.submittedLabel, style: GoogleFonts.inter(fontSize: 11, color: cs.outline)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _InfoChip(icon: Icons.payments_outlined, label: '₱${listing.pricePerKg.toStringAsFixed(2)}/kg', cs: cs),
                    const SizedBox(width: 8),
                    _InfoChip(icon: Icons.scale_outlined, label: '${listing.volumeKg.toStringAsFixed(0)} kg', cs: cs),
                    const Spacer(),
                    if (listing.priceDiffPercent != null) _PriceIndicator(listing: listing, cs: cs),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: cs.primary),
                            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.rate_review_outlined, size: 16, color: cs.primary),
                              const SizedBox(width: 6),
                              Text(l10n.pendingApprovalsReviewAction,
                                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: onQuickApprove,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: onQuickApprove != null ? AppConstants.successGreen : cs.outline.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline_rounded, size: 16,
                                  color: onQuickApprove != null ? Colors.white : cs.outline),
                              const SizedBox(width: 6),
                              Text(l10n.farmerMgmtApproveAction,
                                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600,
                                      color: onQuickApprove != null ? Colors.white : cs.outline)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (listing.hasStockWarning)
            ClipRRect(
              borderRadius: BorderRadius.horizontal(left: Radius.circular(AppConstants.radiusLg)),
              child: Container(width: 4, color: cs.error),
            ),
          Expanded(child: card),
        ],
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  final ColorScheme cs;
  final String cropName;
  const _PhotoPlaceholder({required this.cs, required this.cropName});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.eco_outlined, size: 32, color: cs.outline.withValues(alpha: 0.40)),
            const SizedBox(height: 4),
            Text(cropName, style: GoogleFonts.inter(fontSize: 11, color: cs.outline)),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme cs;
  const _InfoChip({required this.icon, required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ],
      ),
    );
  }
}

class _PriceIndicator extends StatelessWidget {
  final AdminListingModel listing;
  final ColorScheme cs;
  const _PriceIndicator({required this.listing, required this.cs});

  @override
  Widget build(BuildContext context) {
    final pct = listing.priceDiffPercent!;
    final isBelow = pct < 0;
    final color = listing.isPriceWithinMarketRange ? AppConstants.successGreen : cs.error;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(isBelow ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 14, color: color),
        Text('${pct.abs().toStringAsFixed(1)}% vs market',
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyPendingState extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;
  final bool hasActiveFilter;
  const _EmptyPendingState({required this.cs, required this.sagana, this.hasActiveFilter = false});

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
            hasActiveFilter ? Icons.search_off_rounded : Icons.check_circle_outline_rounded,
            size: 48,
            color: (hasActiveFilter ? cs.outline : AppConstants.successGreen).withValues(alpha: 0.40),
          ),
          const SizedBox(height: 14),
          Text(hasActiveFilter ? l10n.marketplaceNoListingsFiltered : l10n.pendingApprovalsAllCaughtUp,
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(
            hasActiveFilter
                ? l10n.offerCoopTryDifferentFilter
                : l10n.pendingApprovalsNoneWaiting,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}