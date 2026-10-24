import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/admin_listing_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/listing_filter_modal.dart' show ListingMarketBadge, ListingMarketFilterRow;
import '../../widgets/listing_status_badge.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

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
  String? _marketFilter; // null = All markets, else a crop_type value

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _searchCtrl.addListener(
      () => setState(() => _searchQuery = _searchCtrl.text),
    );
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // The market filter and the search are applied client-side in _filtered
  // below, so switching chips never re-hits the network.
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
    Iterable<AdminListingModel> list = _allListings;
    if (_marketFilter != null) {
      list = list.where((l) => l.marketType == _marketFilter);
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where(
        (l) =>
          l.cropName.toLowerCase().contains(q) ||
          l.farmerName.toLowerCase().contains(q) ||
            (l.variety?.toLowerCase().contains(q) ?? false),
      );
    }
    return list.toList();
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
        backgroundColor: isSuccess
            ? AppConstants.midGreen
            : AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
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
              CachedDataNotice(
                screen: 'listings_all_all_all_all',
                isOnline: _isOnline,
                offlineMessage: AppLocalizations.of(context).offlineListingActions,
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadAll,
                  child: _isLoading
                      ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                          children: [
                            TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: l10n.marketplaceSearchHint,
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: cs.outline,
                                ),
                                prefixIcon: Icon(
                                  Icons.search_rounded,
                                  color: cs.outline,
                                  size: 22,
                                ),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(
                                          Icons.close_rounded,
                                          color: cs.outline,
                                          size: 18,
                                        ),
                                        onPressed: () => _searchCtrl.clear(),
                                      )
                                    : null,
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ── Market chips only: All Markets / Cooperative Market /
                            // Public Market. They decide which market's listings
                            // are shown; each card's badge carries its status.
                            ListingMarketFilterRow(
                              value: _marketFilter,
                              onChanged: (v) =>
                                  setState(() => _marketFilter = v),
                            ),
                            const SizedBox(height: 20),

                            if (visible.isEmpty)
                              _EmptyState(
                                hasSearch:
                                    _searchQuery.isNotEmpty ||
                                    _marketFilter != null,
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
                                        .push(
                                          AppRoutes.listingReview,
                                          extra: {
                                            'listingId': listing.id,
                                            'readOnly': true,
                                          },
                                        )
                                        .then((_) => _loadAll()),
                                    onQuickApprove:
                                        listing.isPending && _isOnline
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
            child: _TopAppBar(
              onBack: () => context.pop(),
              sagana: sagana,
              cs: cs,
            ),
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
  const _TopAppBar({
    required this.onBack,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return SubPageTopBar(title: AppLocalizations.of(context).marketplaceAllListingsTitle, onBack: onBack);
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
    return SoldOutGrey(
      active: listing.isSoldOut,
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
            ),
          ],
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
                color: listing.isPending ? AppConstants.warningAmber : Colors.transparent,
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
                        errorBuilder: (_, __, ___) =>
                            _Thumb(cs: cs, crop: listing.cropName),
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
                          listing.variety != null
                              ? '${listing.cropName} — ${listing.variety}'
                              : listing.cropName,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ListingStatusBadge.forListing(
                        context,
                        status: listing.status,
                        remainingKg: listing.remainingKg,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${listing.farmerName} • ${listing.submittedLabel}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (listing.marketType != null) ...[
                    const SizedBox(height: 4),
                    ListingMarketBadge(marketType: listing.marketType),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                            TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    '₱${listing.pricePerKg.toStringAsFixed(2)}/kg',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                ),
                            ),
                            TextSpan(
                                text:
                                    '  •  ${listing.volumeKg.toStringAsFixed(0)} kg',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                            ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (listing.hasStockWarning) ...[
                        const SizedBox(width: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 13,
                              color: cs.error,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              AppLocalizations.of(
                                context,
                              ).marketplaceStockWarningBadge,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: cs.error,
                              ),
                            ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppConstants.successGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: AppConstants.successGreen,
                  ),
                ),
              )
            else
              Icon(Icons.chevron_right_rounded, color: cs.outline, size: 20),
          ],
        ),
      ),
      ),
    );
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
      child: Center(
        child: Icon(
          Icons.eco_outlined,
          size: 26,
          color: cs.outline.withValues(alpha: 0.40),
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _EmptyState({
    required this.hasSearch,
    required this.cs,
    required this.sagana,
  });

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
          Icon(
            Icons.inventory_2_outlined,
            size: 44,
            color: cs.outline.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            hasSearch
                  ? AppLocalizations.of(context).marketplaceNoListingsFiltered
                  : AppLocalizations.of(context).marketplaceNoListingsYet,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}