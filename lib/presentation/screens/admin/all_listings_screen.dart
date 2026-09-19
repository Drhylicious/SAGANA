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
import '../../widgets/listing_filter_modal.dart';

class AllListingsScreen extends StatefulWidget {
  const AllListingsScreen({super.key});

  @override
  State<AllListingsScreen> createState() => _AllListingsScreenState();
}

class _AllListingsScreenState extends State<AllListingsScreen> {
  final _repo = AdminListingRepository();
  final _searchCtrl = TextEditingController();

  List<AdminListingModel> _allListings = [];
  bool _isLoading = true;
  bool _hasLoadedOnce = false;
  bool _isOnline = true;

  String _searchQuery = '';
  String? _statusFilter; // null = All

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text));
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Status is deliberately NOT passed here — it's filtered client-side in
  // _filtered below, so switching status chips never re-hits the network
  // (matching Order Management's already-smooth behavior).
  Future<void> _loadAll() async {
    if (!_hasLoadedOnce) setState(() => _isLoading = true);
    final listings = await _repo.fetchAllListings();
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

  void _onStatusFilterChanged(String? status) {
    setState(() => _statusFilter = status);
  }

  Future<void> _quickApprove(AdminListingModel listing) async {
    await _repo.approveListing(listing.id);
    _showSnack('${listing.cropName} listing approved.', isSuccess: true);
    _loadAll();
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
    final visible = _filtered;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadAll,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                          children: [
                            TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: l10n.marketplaceSearchHint,
                                hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
                                prefixIcon: Icon(Icons.search_rounded, color: cs.outline, size: 22),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.close_rounded, color: cs.outline, size: 18),
                                        onPressed: () => _searchCtrl.clear(),
                                      )
                                    : null,
                              ),
                              style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
                            ),
                            const SizedBox(height: 14),

                            // ── Status chips — same plain-pill style as
                            // Pending Approval / Offer to Cooperative now
                            // (no count badge), instead of this screen's own
                            // previous, visually different chip design.
                            SizedBox(
                              height: 34,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  ListingStatusFilterChip(
                                    label: l10n.farmerMgmtAllFilter, active: _statusFilter == null,
                                    color: cs.primary, onTap: () => _onStatusFilterChanged(null), cs: cs,
                                  ),
                                  const SizedBox(width: 8),
                                  ListingStatusFilterChip(
                                    label: l10n.buyerOrderDetailPendingTimestamp, active: _statusFilter == 'pending_review',
                                    color: cs.error, onTap: () => _onStatusFilterChanged('pending_review'), cs: cs,
                                  ),
                                  const SizedBox(width: 8),
                                  ListingStatusFilterChip(
                                    label: l10n.marketplaceFilterLive, active: _statusFilter == 'approved',
                                    color: AppConstants.successGreen, onTap: () => _onStatusFilterChanged('approved'), cs: cs,
                                  ),
                                  const SizedBox(width: 8),
                                  ListingStatusFilterChip(
                                    label: l10n.marketplaceFilterChanges, active: _statusFilter == 'changes_required',
                                    color: AppConstants.warningAmber, onTap: () => _onStatusFilterChanged('changes_required'), cs: cs,
                                  ),
                                  const SizedBox(width: 8),
                                  ListingStatusFilterChip(
                                    label: l10n.marketplaceFilterSold, active: _statusFilter == 'sold',
                                    color: cs.onSurfaceVariant, onTap: () => _onStatusFilterChanged('sold'), cs: cs,
                                  ),
                                  const SizedBox(width: 8),
                                  ListingStatusFilterChip(
                                    label: l10n.farmerMgmtStatusRejectedLabel, active: _statusFilter == 'rejected',
                                    color: cs.error, onTap: () => _onStatusFilterChanged('rejected'), cs: cs,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            if (visible.isEmpty)
                              _EmptyState(
                                hasSearch: _searchQuery.isNotEmpty || _statusFilter != null,
                                cs: cs,
                                sagana: sagana,
                              )
                            else
                              ...visible.map(
                                (listing) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _AllListingCard(
                                    listing: listing,
                                    cs: cs,
                                    sagana: sagana,
                                    isOnline: _isOnline,
                                    // All Listings is read-only — approve/
                                    // reject/request-changes stays exclusive
                                    // to Pending Review (see M-marketplace-2).
                                    onTap: () => context
                                        .push(AppRoutes.listingReview,
                                            extra: {'listingId': listing.id, 'readOnly': true})
                                        .then((_) => _loadAll()),
                                    onQuickApprove: listing.isPending && _isOnline
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
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopAppBar(onBack: () => context.pop(), sagana: sagana, cs: cs),
          ),
        ],
      ),
    );
  }
}

// ─── Top App Bar ──────────────────────────────────────────────────────────────
// No count badge at all now — genuinely removed this time, not just
// stopped-being-passed. Subtitle added to match the title/subtitle pattern
// now used across Market Linking and Pending Approval.
class _TopAppBar extends StatelessWidget {
  final VoidCallback onBack;
  final SaganaColors sagana;
  final ColorScheme cs;
  const _TopAppBar({required this.onBack, required this.sagana, required this.cs});

  @override
  Widget build(BuildContext context) {
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
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: onBack,
              ),
              Expanded(
                child: Text(AppLocalizations.of(context).marketplaceAllListingsTitle,
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: cs.primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



// ─── All Listing Card ─────────────────────────────────────────────────────────
class _AllListingCard extends StatelessWidget {
  final AdminListingModel listing;
  final ColorScheme cs;
  final SaganaColors sagana;
  final bool isOnline;
  final VoidCallback onTap;
  final VoidCallback? onQuickApprove;

  const _AllListingCard({
    required this.listing,
    required this.cs,
    required this.sagana,
    required this.isOnline,
    required this.onTap,
    this.onQuickApprove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final statusColor = _statusColor(listing.status, cs, context);
    final statusLabel = listingStatusLabel(l10n, listing.status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Always reserved, not just `if (listing.isPending)` — that
            // conditional was shifting every other element in this Row
            // (starting with the image) ~13px right only for pending
            // cards, since non-pending cards never allocated this space
            // at all. Same width for every card now; only the color
            // changes, so the image lines up identically across every
            // status.
            Container(
              width: 3,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: listing.isPending ? cs.error : Colors.transparent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppConstants.radiusLg),
                  bottomLeft: Radius.circular(AppConstants.radiusLg),
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: SizedBox(
                width: 68,
                height: 68,
                child: listing.listingPhotoUrl != null
                    ? Image.network(
                        listing.listingPhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _Thumb(cs: cs, crop: listing.cropName),
                      )
                    : _Thumb(cs: cs, crop: listing.cropName),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          listing.variety != null ? '${listing.cropName} — ${listing.variety}' : listing.cropName,
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _StatusBadge(label: statusLabel, color: statusColor, cs: cs),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('${listing.farmerName} • ${listing.submittedLabel}',
                      style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: '₱${listing.pricePerKg.toStringAsFixed(2)}/kg',
                              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary),
                            ),
                            TextSpan(
                              text: '  •  ${listing.volumeKg.toStringAsFixed(0)} kg',
                              style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (listing.hasStockWarning) ...[
                        const SizedBox(width: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 13, color: cs.error),
                            const SizedBox(width: 2),
                            Text(AppLocalizations.of(context).marketplaceStockWarningBadge,
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: cs.error)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onQuickApprove != null)
              GestureDetector(
                onTap: onQuickApprove,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppConstants.successGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: const Icon(Icons.check_rounded, size: 18, color: AppConstants.successGreen),
                ),
              )
            else
              Icon(Icons.chevron_right_rounded, color: cs.outline, size: 20),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status, ColorScheme cs, BuildContext context) {
    switch (status) {
      case 'pending_review': return cs.error;
      default: return ListingStatusDisplay.color(context, status);
    }
  }
}

class _Thumb extends StatelessWidget {
  final ColorScheme cs;
  final String crop;
  const _Thumb({required this.cs, required this.crop});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(child: Icon(Icons.eco_outlined, size: 26, color: cs.outline.withValues(alpha: 0.40))),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final ColorScheme cs;
  const _StatusBadge({required this.label, required this.color, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
      child: Text(label.toUpperCase(),
          style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: color)),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _EmptyState({required this.hasSearch, required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
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
          Icon(Icons.inventory_2_outlined, size: 44, color: cs.outline.withValues(alpha: 0.35)),
          const SizedBox(height: 12),
          Text(hasSearch
                  ? AppLocalizations.of(context).marketplaceNoListingsFiltered
                  : AppLocalizations.of(context).marketplaceNoListingsYet,
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}