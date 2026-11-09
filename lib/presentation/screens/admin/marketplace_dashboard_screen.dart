import 'package:flutter/material.dart';
import '../../../core/utils/order_status.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/dashboard_cards.dart';
import '../../widgets/admin_top_bar.dart';
import '../../widgets/report_summary_widgets.dart' show ReportSectionCard;
import '../../widgets/cached_data_notice.dart';
import '../../../data/repositories/admin_listing_repository.dart';
import '../../../data/repositories/admin_order_repository.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../data/repositories/cooperative_offer_repository.dart';
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/table_change_watcher.dart';
import '../../../routes/app_routes.dart';

class MarketplaceDashboardScreen extends StatefulWidget {
  const MarketplaceDashboardScreen({super.key});

  @override
  State<MarketplaceDashboardScreen> createState() =>
      _MarketplaceDashboardScreenState();
}

class _MarketplaceDashboardScreenState
    extends State<MarketplaceDashboardScreen> {
  final _repo = AdminListingRepository();
  final _orderRepo = AdminOrderRepository();
  final _offerRepo = CooperativeOfferRepository();
  final _buyerRepo = BuyerProfileRepository();
  final _marketLinkingRepo = MarketLinkingRepository();

  ListingSummaryStats _stats     = ListingSummaryStats.empty;
  OrderSummaryStats _orderStats = OrderSummaryStats.empty;
  int _pendingOffersCount = 0;
  // Edited listings waiting for a decision (with the new listings that are pending, they make up
  // the Pending Approval count), and every offer ever made to the cooperative.
  int _pendingEditCount = 0;
  int _totalOffersCount = 0;
  int _buyerCount = 0;
  int _marketLinkingCount = 0;
  int _marketLinkingFarmersCount = 0;
  int _marketLinkingCancellations = 0;
  bool _isLoading = true;
  bool _isOnline  = true;
  TableChangeWatcher? _watcher;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadAll();
    _watcher = TableChangeWatcher(
      // Every table a KPI reads, so each figure follows the data as it changes
      // (a new listing, order, offer, buyer or Market Linking request).
      tables: const [
        'marketplace_listings',
        'orders',
        'program_product_purchases',
        'listing_edit_requests',
        'cooperative_purchase_offers',
        'market_linking_programs',
        'user_roles',
      ],
      onChange: () {
        if (mounted) _loadAll(silent: true);
      },
    )..start();
  }

  @override
  void dispose() {
    _watcher?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchSummaryStats(),
      _orderRepo.fetchSummaryStats(),
      // A failed read keeps the figure already on screen rather than showing 0.
      _offerRepo.fetchAwaitingCooperativeCount().catchError((_) => _pendingOffersCount),
      _buyerRepo.fetchBuyerCount(),
      _marketLinkingRepo.fetchSummaryStats(),
      _repo.fetchPendingEditCount().catchError((_) => _pendingEditCount),
      _offerRepo.fetchTotalCount().catchError((_) => _totalOffersCount),
    ]);
    if (!mounted) return;
    setState(() {
      _stats   = results[0] as ListingSummaryStats;
      _orderStats = results[1] as OrderSummaryStats;
      _pendingOffersCount = results[2] as int;
      _buyerCount = results[3] as int;
      _pendingEditCount = results[5] as int;
      _totalOffersCount = results[6] as int;
      final marketLinkingStats = results[4] as MarketLinkingSummaryStats;
      // The Market Linking tile counts the requests themselves (the "All" chip
      // of the Market Linking screen). The priority alerts say how many
      // different Farmers have an open request, and how many cancellation
      // requests are waiting for a review.
      _marketLinkingCount = marketLinkingStats.total;
      _marketLinkingFarmersCount = marketLinkingStats.activeFarmers;
      _marketLinkingCancellations = marketLinkingStats.cancellationRequests;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n   = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        color: AppConstants.primaryGreen,
        onRefresh: _loadAll,
        child: CustomScrollView(
          slivers: [

            // Top bar unchanged — same shared AdminTopBarDelegate as before.
            SliverPersistentHeader(
              pinned: true,
              delegate: AdminTopBarDelegate(
                topPadding: MediaQuery.paddingOf(context).top,
                title: l10n.navMarketplace,
                onBroadcastTap: () => context.push(AppRoutes.announcementDashboard),
                onNotificationTap: () => context.push(AppRoutes.adminNotifications).then((_) => _loadAll()),
                onProfileTap: () => context.push(AppRoutes.adminProfile),
                enableMenu: true,
              ),
            ),
            SliverToBoxAdapter(
              child: CachedDataNotice(
                screen: 'listing_status_counts',
                isOnline: _isOnline,
                offlineMessage: AppLocalizations.of(context).offlineFeaturesUnavailable,
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

                  // ── Marketplace Overview — executive summary hero ───────
                  // Untouched, per your call — already data-driven, not a
                  // redesign candidate.
                  if (_isLoading)
                    const SkeletonBlock(height: 108)
                  else
                    _MarketplaceOverviewCard(
                      stats: _stats,
                      orderStats: _orderStats,
                      pendingOffersCount: _pendingOffersCount,
                      marketLinkingFarmersCount: _marketLinkingFarmersCount,
                      marketLinkingCancellations: _marketLinkingCancellations,
                      cs: cs, sagana: sagana,
                      onPendingListingsTap: () => context.push(AppRoutes.pendingApprovals).then((_) => _loadAll()),
                      onPendingOrdersTap: () => context.push(AppRoutes.adminOrders, extra: {'filter': kOrderNeedsActionFilter}).then((_) => _loadAll()),
                      onPendingOffersTap: () => context.push(AppRoutes.offerToCooperative).then((_) => _loadAll()),
                      onMarketLinkingTap: () => context.push(AppRoutes.marketLinking).then((_) => _loadAll()),
                    ),
                  const SizedBox(height: 20),

                  // ── KPI grid (non-clickable) ────────────────────────────
                  // Grouped inside the same outer titled container the
                  // Report tab uses (Executive Snapshot etc.), not just
                  // individually restyled cards.
                  if (_isLoading)
                    const SkeletonBlock(height: 150)
                  else
                    ReportSectionCard(
                      title: l10n.marketDashOverviewTitle,
                      icon: Icons.storefront_rounded,
                      accent: AppConstants.primaryGreen,
                      child: _KpiStrip(
                        stats: _stats,
                        orderStats: _orderStats,
                        pendingOffersCount: _pendingOffersCount,
                        pendingEditCount: _pendingEditCount,
                        buyerCount: _buyerCount,
                        marketLinkingCount: _marketLinkingCount,
                        cs: cs, sagana: sagana,
                      ),
                    ),
                  const SizedBox(height: 20),

                  // ── Marketplace Management ──────────────────────────────
                  Text(l10n.marketDashManagementTitle,
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
                  const SizedBox(height: 12),
                  _QuickActionsGrid(
                    stats: _stats,
                    orderStats: _orderStats,
                    pendingOffersCount: _pendingOffersCount,
                    pendingEditCount: _pendingEditCount,
                    totalOffersCount: _totalOffersCount,
                    buyerCount: _buyerCount,
                    marketLinkingCount: _marketLinkingCount,
                    cs: cs, sagana: sagana,
                    onAllListings: () => context.push(AppRoutes.allListings).then((_) => _loadAll()),
                    onPendingReview: () => context.push(AppRoutes.pendingApprovals).then((_) => _loadAll()),
                    onBuyerManagement: () => context.push(AppRoutes.buyerManagement),
                    onMarketLinking: () => context.push(AppRoutes.marketLinking),
                    onOrders: () => context.push(AppRoutes.adminOrders, extra: {'filter': kOrderNeedsActionFilter}),
                    onOfferToCooperative: () => context.push(AppRoutes.offerToCooperative).then((_) => _loadAll()),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Top bar is provided by shared AdminTopBarDelegate

// ─────────────────────────────────────────────────────────────────────────────
// Marketplace Overview — executive summary hero (non-clickable)
// ─────────────────────────────────────────────────────────────────────────────

class _MarketplaceOverviewCard extends StatelessWidget {
  final ListingSummaryStats stats;
  final OrderSummaryStats orderStats;
  final int pendingOffersCount;
  final int marketLinkingFarmersCount;
  final int marketLinkingCancellations;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onPendingListingsTap;
  final VoidCallback onPendingOrdersTap;
  final VoidCallback onPendingOffersTap;
  final VoidCallback onMarketLinkingTap;

  const _MarketplaceOverviewCard({
    required this.stats,
    required this.orderStats,
    required this.pendingOffersCount,
    required this.marketLinkingFarmersCount,
    required this.marketLinkingCancellations,
    required this.cs,
    required this.sagana,
    required this.onPendingListingsTap,
    required this.onPendingOrdersTap,
    required this.onPendingOffersTap,
    required this.onMarketLinkingTap,
  });

  List<_PriorityItem> _priorities(AppLocalizations l10n) {
    final items = <_PriorityItem>[];
    if (stats.pending > 0) {
      items.add(_PriorityItem(
        icon: Icons.pending_actions_rounded,
        color: AppConstants.warningAmber,
        title: l10n.marketDashListingsAwaitingReview(stats.pending),
        subtitle: l10n.marketDashFarmerSubmissionsNote,
        onTap: onPendingListingsTap,
      ));
    }
    if (orderStats.needsAction > 0) {
      items.add(_PriorityItem(
        icon: Icons.shopping_bag_outlined,
        color: AppConstants.programPurple,
        title: l10n.marketDashOrdersNeedAction(orderStats.needsAction),
        subtitle: l10n.marketDashOrdersNeedActionNote,
        onTap: onPendingOrdersTap,
      ));
    }
    if (pendingOffersCount > 0) {
      items.add(_PriorityItem(
        icon: Icons.handshake_outlined,
        color: AppConstants.successGreen,
        title: l10n.marketDashOffersAwaitingReview(pendingOffersCount),
        subtitle: l10n.marketDashOffersNote,
        onTap: onPendingOffersTap,
      ));
    }
    if (marketLinkingCancellations > 0) {
      items.add(_PriorityItem(
        icon: Icons.pending_actions_rounded,
        color: AppConstants.errorRed,
        title: l10n.marketDashCancellationRequests(marketLinkingCancellations),
        subtitle: l10n.marketDashCancellationNote,
        onTap: onMarketLinkingTap,
      ));
    }
    if (marketLinkingFarmersCount > 0) {
      items.add(_PriorityItem(
        icon: Icons.eco_outlined,
        color: AppConstants.midGreen,
        title: l10n.marketDashFarmersInPipeline(marketLinkingFarmersCount),

        subtitle: l10n.marketDashLinkingNote,
        onTap: onMarketLinkingTap,
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = _priorities(l10n);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 20, decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 10),
              Text(l10n.marketDashOverviewTitle, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const Spacer(),
              if (items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppConstants.warningAmber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
                  child: Text(l10n.buyerCartItemCount(items.length),
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppConstants.warningAmber)),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 2),
            child: Text(l10n.marketDashGovernanceSubtitle,
                style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Text(l10n.marketDashAllClear,
                  style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface, height: 1.4)),
            )
          else
            ...items.map((item) => _PriorityRow(item: item, cs: cs)),
        ],
      ),
    );
  }
}

class _PriorityItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _PriorityItem({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});
}

class _PriorityRow extends StatelessWidget {
  final _PriorityItem item;
  final ColorScheme cs;
  const _PriorityRow({required this.item, required this.cs});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(item.icon, size: 18, color: item.color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
                  Text(item.subtitle, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI Strip (non-clickable) — one simple total per Marketplace module
// ─────────────────────────────────────────────────────────────────────────────

class _KpiStrip extends StatelessWidget {
  final ListingSummaryStats stats;
  final OrderSummaryStats orderStats;
  final int pendingOffersCount;
  final int pendingEditCount;
  final int buyerCount;
  final int marketLinkingCount;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _KpiStrip({
    required this.stats,
    required this.orderStats,
    required this.pendingOffersCount,
    required this.pendingEditCount,
    required this.buyerCount,
    required this.marketLinkingCount,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Same card as the main Dashboard's Overview: label, value and a short caption.
    final tiles = [
      DashboardKpiTile(label: l10n.marketDashKpiAllListings, value: '${stats.total}', sub: l10n.marketDashKpiSubListings, color: cs.primary, icon: Icons.list_alt_rounded),
      DashboardKpiTile(label: l10n.adminDashKpiPending, value: '${stats.pending + pendingEditCount}', sub: l10n.marketDashKpiSubPending, color: AppConstants.warningAmber, icon: Icons.pending_actions_rounded),
      DashboardKpiTile(label: l10n.marketDashKpiBuyers, value: '$buyerCount', sub: l10n.marketDashKpiSubBuyers, color: AppConstants.buyerBlue, icon: Icons.people_rounded),
      DashboardKpiTile(label: l10n.marketDashKpiOrders, value: '${orderStats.total}', sub: l10n.marketDashKpiSubOrders, color: AppConstants.programPurple, icon: Icons.shopping_bag_rounded),
      DashboardKpiTile(label: l10n.marketDashKpiMarketLinking, value: '$marketLinkingCount', sub: l10n.marketDashKpiSubLinking, color: AppConstants.midGreen, icon: Icons.eco_rounded),
      DashboardKpiTile(label: l10n.marketDashKpiCoopOffers, value: '$pendingOffersCount', sub: l10n.marketDashKpiSubOffers, color: AppConstants.successGreen, icon: Icons.handshake_rounded),
    ];
    return DashboardKpiStrip(tiles: tiles);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Marketplace Management Grid — balanced 2-column, one tile per submodule
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionsGrid extends StatelessWidget {
  final ListingSummaryStats stats;
  final OrderSummaryStats orderStats;
  final int pendingOffersCount;
  final int pendingEditCount;
  final int totalOffersCount;
  final int buyerCount;
  final int marketLinkingCount;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onAllListings;
  final VoidCallback onPendingReview;
  final VoidCallback onBuyerManagement;
  final VoidCallback onMarketLinking;
  final VoidCallback onOrders;
  final VoidCallback onOfferToCooperative;

  const _QuickActionsGrid({
    required this.stats,
    required this.orderStats,
    required this.pendingOffersCount,
    required this.pendingEditCount,
    required this.totalOffersCount,
    required this.buyerCount,
    required this.marketLinkingCount,
    required this.cs,
    required this.sagana,
    required this.onAllListings,
    required this.onPendingReview,
    required this.onBuyerManagement,
    required this.onMarketLinking,
    required this.onOrders,
    required this.onOfferToCooperative,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Six cards, two columns by three rows, in the same style as the Dashboard's Management
    // Modules. Order, row by row:
    // All Listings | Pending Review
    // Buyer Management | Orders
    // Market Linking | Offer to Cooperative
    final items = [
      DashboardModuleItem(
        icon: Icons.list_alt_rounded,
        title: l10n.marketDashKpiAllListings,
        subtitle: l10n.marketDashModListingsSub,
        badge: '${stats.total}',
        onTap: onAllListings,
      ),
      DashboardModuleItem(
        icon: Icons.pending_actions_rounded,
        title: l10n.marketDashKpiPendingReview,
        subtitle: l10n.marketDashModPendingSub,
        // New listings and edited listings that are waiting for a decision.
        badge: '${stats.pending + pendingEditCount}',
        onTap: onPendingReview,
      ),
      DashboardModuleItem(
        icon: Icons.people_rounded,
        title: l10n.marketDashActionBuyerManagement,
        subtitle: l10n.marketDashModBuyersSub,
        badge: '$buyerCount',
        onTap: onBuyerManagement,
      ),
      DashboardModuleItem(
        icon: Icons.shopping_bag_rounded,
        title: l10n.orderMgmtTitleGeneric,
        subtitle: l10n.marketDashModOrdersSub,
        // Marketplace and Cooperative orders together.
        badge: '${orderStats.total}',
        onTap: onOrders,
      ),
      DashboardModuleItem(
        icon: Icons.alt_route_rounded,
        title: l10n.marketDashKpiMarketLinking,
        subtitle: l10n.marketDashModLinkingSub,
        // The Market Linking requests themselves, not the quantity of products sold.
        badge: '$marketLinkingCount',
        onTap: onMarketLinking,
      ),
      DashboardModuleItem(
        icon: Icons.handshake_rounded,
        title: l10n.marketDashActionOfferToCoop,
        subtitle: l10n.marketDashModOffersSub,
        badge: '$totalOffersCount',
        onTap: onOfferToCooperative,
      ),
    ];
    // The page scrolls, the grid does not.
    return KeyedSubtree(
      key: const Key('marketplaceActions'),
      child: DashboardModuleGrid(items: items),
    );
  }
}
