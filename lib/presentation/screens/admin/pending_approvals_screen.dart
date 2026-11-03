import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/listing_edit_request_model.dart';
import '../../../data/repositories/admin_listing_repository.dart';
import '../../widgets/edit_request_widgets.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/listing_order.dart';
import '../../widgets/listing_filter_modal.dart'
    show MarketplaceFilterBar, MarketplaceFilterOption, ListingMarketBadge;
import '../../widgets/listing_status_badge.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/table_change_watcher.dart';
import '../../widgets/cached_data_notice.dart';

class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen>
    with WidgetsBindingObserver {
  final _repo = AdminListingRepository();
  StreamSubscription<bool>? _connectivitySub;
  final _searchCtrl = TextEditingController();

  // Fetched once (the full pending/approved/rejected outcome set), then
  // filtered entirely client-side below — switching status chips or
  // typing a search term no longer re-hits the network, matching Order
  // Management's already-smooth filtering instead of visibly reloading
  // on every tap. See M-marketplace-8.
  List<AdminListingModel> _allListings = [];

  // Farmer requests to change a PUBLISHED listing. The listing itself stays as it
  // is until one of these is approved.
  List<ListingEditRequest> _edits = [];
  // 0 = New Listings, 1 = Edit Requests.
  int _tab = 0;
  // null = All; otherwise pending | approved | rejected | cancelled.
  String? _editFilter;
  bool _isLoading = true;
  bool _isOnline = ConnectivityService.instance.isOnline;
  bool _hasLoadedOnce = false;

  String _searchQuery = '';
  // null = All. The chips filter by the Manager's approval decision, whatever
  // the listing's market; a Sold Out listing was approved, so it is Approved.
  ListingApproval? _approvalFilter;
  TableChangeWatcher? _stockWatcher;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (!mounted) return;
      final cameOnline = v && !_isOnline;
      setState(() => _isOnline = v);
      if (cameOnline) _load();
    });
    AppTheme.applySystemOverlay(context);
    _searchCtrl.addListener(
      () => setState(() => _searchQuery = _searchCtrl.text),
    );
    _load();
    _stockWatcher = TableChangeWatcher(
      tables: const ['marketplace_listings', 'orders', 'listing_edit_requests'],
      onChange: () {
        if (mounted) _load();
      },
    )..start();
  }

  // Reload when the app returns to the foreground so decisions made on
  // another device show up without a restart.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stockWatcher?.dispose();
    _connectivitySub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_hasLoadedOnce) setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchReviewListings(),
      _repo.fetchEditRequests(),
    ]);
    final listings = results[0] as List<AdminListingModel>;
    if (!mounted) return;
    setState(() {
      _edits = results[1] as List<ListingEditRequest>;
      _allListings = listings;
      _isLoading = false;
      _hasLoadedOnce = true;
    });
  }

  // How many listings each approval chip holds, from the loaded records.
  Map<ListingApproval, int> get _approvalCounts {
    final counts = <ListingApproval, int>{};
    for (final l in _allListings) {
      final a = listingApprovalOf(l.status);
      if (a != null) counts[a] = (counts[a] ?? 0) + 1;
    }
    return counts;
  }

  List<AdminListingModel> get _filtered {
    Iterable<AdminListingModel> list = _approvalFilter == null
        ? _allListings
        : _allListings.where(
            (l) => listingApprovalOf(l.status) == _approvalFilter,
          );
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where(
        (l) =>
            l.cropName.toLowerCase().contains(q) ||
            l.farmerName.toLowerCase().contains(q) ||
            (l.variety?.toLowerCase().contains(q) ?? false),
      );
    }
    // Pending first, then Approved, Disapproved last; newest first inside each
    // group. Applied after the filter and the search.
    return orderForApprovals(list);
  }

  int get _pendingNewCount => _allListings.where((l) => l.isPending).length;
  int get _pendingEditCount => _edits.where((e) => e.isPending).length;

  int _editCount(String? status) =>
      status == null ? _edits.length : _edits.where((e) => e.status == status).length;

  // Waiting requests first, then the decided ones; newest first inside each.
  List<ListingEditRequest> get _filteredEdits {
    Iterable<ListingEditRequest> list = _editFilter == null
        ? _edits
        : _edits.where((e) => e.status == _editFilter);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where(
        (e) =>
            e.cropName.toLowerCase().contains(q) ||
            e.farmerName.toLowerCase().contains(q) ||
            (e.variety?.toLowerCase().contains(q) ?? false),
      );
    }
    return stableGroupSort<ListingEditRequest>(list, (e) => e.isPending ? 0 : 1);
  }

  Widget _tabSelector(AppLocalizations l10n, ColorScheme cs) {
    Widget tab(int index, String label, int waiting) {
      final selected = _tab == index;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? cs.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                if (waiting > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? cs.onPrimary : AppConstants.warningAmber,
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(
                      '$waiting',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: selected ? cs.primary : Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd + 2),
      ),
      child: Row(
        children: [
          tab(0, l10n.lePendingTabNew, _pendingNewCount),
          tab(1, l10n.lePendingTabEdits, _pendingEditCount),
        ],
      ),
    );
  }

  Widget _editRequestsSection(AppLocalizations l10n, ColorScheme cs, SaganaColors sagana) {
    final list = _filteredEdits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarketplaceFilterBar<String?>(
          selected: _editFilter,
          onSelected: (v) => setState(() => _editFilter = v),
          options: [
            MarketplaceFilterOption(
              value: null,
              label: l10n.farmerMgmtAllFilter,
              count: _editCount(null),
              color: cs.primary,
            ),
            for (final s in const ['pending', 'approved', 'rejected', 'cancelled'])
              MarketplaceFilterOption(
                value: s,
                label: editRequestStatusLabel(l10n, s),
                count: _editCount(s),
                color: editRequestStatusColor(s),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (list.isEmpty)
          Container(
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
                  Icons.edit_note_rounded,
                  size: 48,
                  color: cs.outline.withValues(alpha: 0.40),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.leEmptyEdits,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          )
        else
          ...list.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _EditRequestCard(
                request: e,
                cs: cs,
                sagana: sagana,
                onTap: () => context
                    .push(AppRoutes.listingEditRequest, extra: e.id)
                    .then((_) => _load()),
              ),
            ),
          ),
      ],
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
          CachedDataNotice(
            screen: 'listings_all_all_all_all',
            isOnline: _isOnline,
            offlineMessage: AppLocalizations.of(
              context,
            ).offlineFeaturesUnavailable,
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
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                    onPressed: () => _searchCtrl.clear(),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // New Listings | Edit Requests: a Farmer's change to a
                        // published listing is a different decision from
                        // approving a brand-new listing, so they are kept apart.
                        _tabSelector(l10n, cs),
                        const SizedBox(height: 14),

                        if (_tab == 1)
                          _editRequestsSection(l10n, cs, sagana)
                        else ...[
                        // ── Approval chips — instant, client-side switching ──
                        MarketplaceFilterBar<ListingApproval?>(
                          selected: _approvalFilter,
                          onSelected: (v) => setState(() => _approvalFilter = v),
                          options: [
                            MarketplaceFilterOption(
                              value: null,
                              label: l10n.farmerMgmtAllFilter,
                              count: _allListings.length,
                              color: cs.primary,
                            ),
                            for (final a in const [
                              ListingApproval.pending,
                              ListingApproval.approved,
                              ListingApproval.disapproved,
                            ])
                              MarketplaceFilterOption(
                                value: a,
                                label: switch (a) {
                                  ListingApproval.pending => l10n.listingFilterPending,
                                  ListingApproval.approved => l10n.listingStateApproved,
                                  ListingApproval.disapproved => l10n.listingStateDisapproved,
                                },
                                count: _approvalCounts[a] ?? 0,
                                color: listingApprovalColor(context, a),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ── List / empty state ────────────────────────────
                        if (_filtered.isEmpty)
                          _EmptyPendingState(
                            cs: cs,
                            sagana: sagana,
                            hasActiveFilter:
                                _searchQuery.isNotEmpty ||
                                _approvalFilter != null,
                          )
                        else
                          ..._filtered.map(
                            (listing) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PendingListingCard(
                                listing: listing,
                                cs: cs,
                                sagana: sagana,
                                // Approve / disapprove stays on the pending ones. A
                                // decided listing opens read-only.
                                onTap: () => context
                                    .push(
                                      AppRoutes.listingReview,
                                      extra: listing.isPending
                                          ? listing.id
                                          : {
                                              'listingId': listing.id,
                                              'readOnly': true,
                                            },
                                    )
                                    .then((_) => _load()),
                              ),
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

// ─── Top App Bar ──────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final SaganaColors sagana;
  final ColorScheme cs;
  const _TopBar({required this.sagana, required this.cs});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SubPageTopBar(
      title: l10n.pendingApprovalsTitle,
      onBack: () => context.pop(),
    );
  }
}

// ─── Pending Listing Card ─────────────────────────────────────────────────────
class _PendingListingCard extends StatelessWidget {
  final AdminListingModel listing;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onTap;

  const _PendingListingCard({
    required this.listing,
    required this.cs,
    required this.sagana,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final card = Container(
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
          if (listing.listingPhotoUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppConstants.radiusLg),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 7,
                child: Image.network(
                  listing.listingPhotoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _PhotoPlaceholder(cs: cs, cropName: listing.cropName),
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppConstants.radiusLg),
              ),
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
                        listing.variety != null
                            ? '${listing.cropName} — ${listing.variety}'
                            : listing.cropName,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    ListingStatusBadge.forApproval(
                      context,
                      status: listing.status,
                    ),
                  ],
                ),
                // Market and stock pills wrap onto their own line, so the
                // title and the approval badge never get squeezed on a
                // narrow phone.
                if (listing.marketType != null || listing.hasStockWarning) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (listing.marketType != null)
                        ListingMarketBadge(marketType: listing.marketType),
                      if (listing.hasStockWarning)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: cs.errorContainer.withValues(alpha: 0.50),
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull,
                            ),
                          ),
                          child: Text(
                            '⚠ Stock',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: cs.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppConstants.primaryContainer,
                      ),
                      child: Center(
                        child: Text(
                          listing.farmerName.isNotEmpty
                              ? listing.farmerName[0].toUpperCase()
                              : 'F',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppConstants.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        listing.farmerName,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      listing.submittedLabel,
                      style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Was a Row with a Spacer pushing _PriceIndicator to the far
                // right — on a narrow card, the two fixed-width _InfoChips
                // plus the indicator's own text ("X.X% vs market") could
                // together exceed the available width with nothing able to
                // shrink, overflowing past the edge. Wrap lets the indicator
                // drop to a second line instead of being clipped.
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _InfoChip(
                      icon: Icons.payments_outlined,
                      label: formatPricePerUnit(listing.pricePerKg, listing.unit),
                      cs: cs,
                    ),
                    _InfoChip(
                      icon: Icons.scale_outlined,
                      label: listingQuantityLabel(
                        l10n,
                        status: listing.status,
                        remainingKg: listing.remainingKg,
                        volumeKg: listing.volumeKg,
                        unit: listing.unit,
                      ),
                      cs: cs,
                    ),
                    if (listing.priceDiffPercent != null)
                      _PriceIndicator(listing: listing, cs: cs),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
                const SizedBox(height: 12),
                // Quick-Approve removed — approval now only happens inside
                // Listing Review, where the admin has the full pricing/
                // stock/farmer context in front of them before deciding.
                // Review is the one remaining action, full width.
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: onTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.primary),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            listing.isPending
                                ? Icons.rate_review_outlined
                                : Icons.visibility_outlined,
                            size: 16,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            listing.isPending
                                ? l10n.pendingApprovalsReviewAction
                                : l10n.listingApprovalsViewDetails,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(AppConstants.radiusLg),
              ),
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
            Icon(
              Icons.eco_outlined,
              size: 32,
              color: cs.outline.withValues(alpha: 0.40),
            ),
            const SizedBox(height: 4),
            Text(
              cropName,
              style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
            ),
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
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
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
    final color = listing.isPriceWithinMarketRange
        ? AppConstants.successGreen
        : cs.error;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isBelow ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
          size: 14,
          color: color,
        ),
        Text(
          '${pct.abs().toStringAsFixed(1)}% vs market',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyPendingState extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;
  final bool hasActiveFilter;
  const _EmptyPendingState({
    required this.cs,
    required this.sagana,
    this.hasActiveFilter = false,
  });

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
            hasActiveFilter
                ? Icons.search_off_rounded
                : Icons.check_circle_outline_rounded,
            size: 48,
            color: (hasActiveFilter ? cs.outline : AppConstants.successGreen)
                .withValues(alpha: 0.40),
          ),
          const SizedBox(height: 14),
          Text(
            hasActiveFilter
                ? l10n.marketplaceNoListingsFiltered
                : l10n.pendingApprovalsAllCaughtUp,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
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

// ─── Edit Request Card ────────────────────────────────────────────────────────
// A Farmer's proposed change to a published listing: what would change, in one
// glance (old → new), without opening it.
class _EditRequestCard extends StatelessWidget {
  final ListingEditRequest request;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onTap;

  const _EditRequestCard({
    required this.request,
    required this.cs,
    required this.sagana,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final r = request;
    final unit = r.unit;
    final name = (r.variety ?? '').trim().isEmpty ? r.cropName : '${r.cropName} — ${r.variety}';
    final when = DateFormat.yMMMd(Localizations.localeOf(context).toString()).add_jm();

    Widget change(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 12.5, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );

    final changes = <Widget>[
      if (r.changesQuantity)
        change(
          Icons.scale_outlined,
          l10n.wfDetailQuantity(
            formatQuantityUnit(r.shownQuantity, unit),
            formatQuantityUnit(r.proposedQuantity, unit),
          ),
        ),
      if (r.changesPrice)
        change(
          Icons.payments_outlined,
          l10n.wfDetailPrice(
            formatPricePerUnit(r.shownPrice, unit),
            formatPricePerUnit(r.proposedPrice, unit),
          ),
        ),
      if (r.changesDescription)
        change(Icons.notes_rounded, l10n.wfDetailDescription),
      if (r.changesPhoto) change(Icons.photo_camera_outlined, l10n.wfDetailPhoto),
    ];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                EditRequestStatusChip(status: r.status),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.edit_note_rounded, size: 15, color: AppConstants.buyerBlue),
                const SizedBox(width: 4),
                Text(
                  l10n.leEditRequestBadge,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.buyerBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.farmerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: cs.onSurface),
                  ),
                ),
              ],
            ),
            ...changes,
            const SizedBox(height: 10),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.leRequestedOn(when.format(r.createdAt)),
                    style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
                  ),
                ),
                Icon(
                  r.isPending ? Icons.rate_review_outlined : Icons.visibility_outlined,
                  size: 16,
                  color: cs.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  r.isPending ? l10n.pendingApprovalsReviewAction : l10n.listingApprovalsViewDetails,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
