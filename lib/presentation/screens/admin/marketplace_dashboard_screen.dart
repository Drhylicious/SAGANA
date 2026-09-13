import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../widgets/admin_top_bar.dart';
import '../../widgets/shared_widgets.dart';
import '../../../data/repositories/admin_listing_repository.dart';
import '../../../data/repositories/admin_order_repository.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../data/repositories/cooperative_offer_repository.dart';
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/services/connectivity_service.dart';
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
  int _buyerCount = 0;
  int _marketLinkingCount = 0;
  int _marketLinkingSubmittedCount = 0;
  bool _isLoading = true;
  bool _isOnline  = true;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchSummaryStats(),
      _orderRepo.fetchSummaryStats(),
      _offerRepo.fetchPendingOffers(),
      _buyerRepo.fetchBuyerCount(),
      _marketLinkingRepo.fetchSummaryStats(),
    ]);
    if (!mounted) return;
    setState(() {
      _stats   = results[0] as ListingSummaryStats;
      _orderStats = results[1] as OrderSummaryStats;
      _pendingOffersCount = (results[2] as List).length;
      _buyerCount = results[3] as int;
      final marketLinkingStats = results[4] as MarketLinkingSummaryStats;
      // Enrolled farmers (unique), not total rows/rounds — the "Market
      // Linking" KPI tile is labeled around farmers, and a farmer with a
      // second round (Start New Round) must not double-count here, same
      // fix already applied to the Market Linking screen's own KPI strip.
      _marketLinkingCount = marketLinkingStats.enrolledFarmers;
      _marketLinkingSubmittedCount = marketLinkingStats.submitted;
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
            if (!_isOnline)
              const SliverToBoxAdapter(child: OfflineBanner()),

            // Top bar unchanged — same shared AdminTopBarDelegate as before.
            SliverPersistentHeader(
              pinned: true,
              delegate: AdminTopBarDelegate(
                title: l10n.navMarketplace,
                onBroadcastTap: () => context.push(AppRoutes.announcementDashboard),
                onNotificationTap: () => context.push(AppRoutes.adminNotifications).then((_) => _loadAll()),
                onProfileTap: () => context.push(AppRoutes.adminProfile),
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
                    const _ShimmerBlock(height: 108)
                  else
                    _MarketplaceOverviewCard(
                      stats: _stats,
                      orderStats: _orderStats,
                      pendingOffersCount: _pendingOffersCount,
                      marketLinkingSubmittedCount: _marketLinkingSubmittedCount,
                      cs: cs, sagana: sagana,
                      onPendingListingsTap: () => context.push(AppRoutes.pendingApprovals).then((_) => _loadAll()),
                      onPendingOrdersTap: () => context.push(AppRoutes.adminOrders).then((_) => _loadAll()),
                      onPendingOffersTap: () => context.push(AppRoutes.offerToCooperative).then((_) => _loadAll()),
                      onMarketLinkingTap: () => context.push(AppRoutes.marketLinking).then((_) => _loadAll()),
                    ),
                  const SizedBox(height: 20),

                  // ── KPI grid (non-clickable) ────────────────────────────
                  if (_isLoading)
                    const _ShimmerBlock(height: 88)
                  else
                    _KpiStrip(
                      stats: _stats,
                      orderStats: _orderStats,
                      pendingOffersCount: _pendingOffersCount,
                      buyerCount: _buyerCount,
                      marketLinkingCount: _marketLinkingCount,
                      cs: cs, sagana: sagana,
                    ),
                  const SizedBox(height: 20),

                  // ── Marketplace Management ──────────────────────────────
                  Text('Marketplace Management',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
                  const SizedBox(height: 12),
                  _QuickActionsGrid(
                    stats: _stats,
                    orderStats: _orderStats,
                    pendingOffersCount: _pendingOffersCount,
                    cs: cs, sagana: sagana,
                    onAllListings: () => context.push(AppRoutes.allListings).then((_) => _loadAll()),
                    onPendingReview: () => context.push(AppRoutes.pendingApprovals).then((_) => _loadAll()),
                    onBuyerManagement: () => context.push(AppRoutes.buyerManagement),
                    onMarketLinking: () => context.push(AppRoutes.marketLinking),
                    onOrders: () => context.push(AppRoutes.adminOrders),
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
  final int marketLinkingSubmittedCount;
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
    required this.marketLinkingSubmittedCount,
    required this.cs,
    required this.sagana,
    required this.onPendingListingsTap,
    required this.onPendingOrdersTap,
    required this.onPendingOffersTap,
    required this.onMarketLinkingTap,
  });

  List<_PriorityItem> get _priorities {
    final items = <_PriorityItem>[];
    if (stats.pending > 0) {
      items.add(_PriorityItem(
        icon: Icons.pending_actions_rounded,
        color: AppConstants.warningAmber,
        title: '${stats.pending} Listing${stats.pending == 1 ? '' : 's'} Awaiting Review',
        subtitle: 'Farmer submissions need approval',
        onTap: onPendingListingsTap,
      ));
    }
    if (orderStats.pending > 0) {
      items.add(_PriorityItem(
        icon: Icons.shopping_bag_outlined,
        color: AppConstants.programPurple,
        title: '${orderStats.pending} Order${orderStats.pending == 1 ? '' : 's'} Awaiting Fulfillment',
        subtitle: 'Buyer orders need action',
        onTap: onPendingOrdersTap,
      ));
    }
    if (pendingOffersCount > 0) {
      items.add(_PriorityItem(
        icon: Icons.handshake_outlined,
        color: AppConstants.successGreen,
        title: '$pendingOffersCount Cooperative Offer${pendingOffersCount == 1 ? '' : 's'} Awaiting Review',
        subtitle: 'Farmers offered crops for purchase',
        onTap: onPendingOffersTap,
      ));
    }
    if (marketLinkingSubmittedCount > 0) {
      items.add(_PriorityItem(
        icon: Icons.eco_outlined,
        color: AppConstants.midGreen,
        title: '$marketLinkingSubmittedCount Farmer${marketLinkingSubmittedCount == 1 ? '' : 's'} in DA-AMAD Pipeline',
        subtitle: 'Market Linking enrollments in progress',
        onTap: onMarketLinkingTap,
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _priorities;
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
              Text('Marketplace Overview', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const Spacer(),
              if (items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppConstants.warningAmber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
                  child: Text('${items.length} item${items.length == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppConstants.warningAmber)),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 2),
            child: Text('Real-time governance dashboard',
                style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Text("Everything's running smoothly — nothing needs attention right now.",
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
  final int buyerCount;
  final int marketLinkingCount;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _KpiStrip({
    required this.stats,
    required this.orderStats,
    required this.pendingOffersCount,
    required this.buyerCount,
    required this.marketLinkingCount,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _KpiTile('All Listings', '${stats.total}', cs.primary, Icons.list_alt_rounded),
      _KpiTile('Pending Review', '${stats.pending}', AppConstants.warningAmber, Icons.pending_actions_rounded),
      _KpiTile('Buyers', '$buyerCount', AppConstants.buyerBlue, Icons.people_rounded),
      // Was cs.primary (near-black) before — visually indistinguishable from
      // "black" next to the amber/blue tiles. programPurple isn't used
      // elsewhere in this module, so Orders is now unambiguous at a glance.
      _KpiTile('Orders', '${orderStats.total}', AppConstants.programPurple, Icons.shopping_bag_rounded),
      _KpiTile('Market Linking', '$marketLinkingCount', AppConstants.midGreen, Icons.eco_rounded),
      _KpiTile('Coop Offers', '$pendingOffersCount', AppConstants.successGreen, Icons.handshake_rounded),
    ];

    return SizedBox(
      height: 98,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final t = tiles[i];
          return Container(
            width: 112,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: sagana.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(t.icon, size: 13, color: t.color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(t.label,
                          style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant, height: 1.2),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                Text(t.value,
                    style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: t.color)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KpiTile {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _KpiTile(this.label, this.value, this.color, this.icon);
}

// ─────────────────────────────────────────────────────────────────────────────
// Marketplace Management Grid — balanced 2-column, one tile per submodule
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionsGrid extends StatelessWidget {
  final ListingSummaryStats stats;
  final OrderSummaryStats orderStats;
  final int pendingOffersCount;
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
    // Order matches the requested 2-column layout, row by row:
    // All Listings | Pending Review
    // Buyer Management | Orders
    // Market Linking | Offer to Cooperative
    final actions = [
      _ActionItem(icon: Icons.list_alt_rounded, label: 'All Listings', badge: '${stats.total}', hasBadge: false, color: cs.primary, onTap: onAllListings),
      _ActionItem(icon: Icons.pending_actions_rounded, label: 'Pending Review', badge: stats.pending > 0 ? '${stats.pending} pending' : '', hasBadge: false,
          color: stats.pending > 0 ? AppConstants.warningAmber : cs.outline, onTap: onPendingReview),
      _ActionItem(icon: Icons.people_rounded, label: 'Buyer Management', badge: '', hasBadge: false, color: AppConstants.buyerBlue, onTap: onBuyerManagement),
      _ActionItem(icon: Icons.shopping_bag_rounded, label: 'Orders', badge: orderStats.pending > 0 ? '${orderStats.pending} pending' : '', hasBadge: false,
          color: orderStats.pending > 0 ? AppConstants.warningAmber : cs.outline, onTap: onOrders),
      _ActionItem(icon: Icons.alt_route_rounded, label: 'Market Linking', badge: 'DA-AMAD', hasBadge: false, color: AppConstants.primaryGreen, onTap: onMarketLinking),
      _ActionItem(icon: Icons.handshake_rounded, label: 'Offer to Cooperative', badge: pendingOffersCount > 0 ? '$pendingOffersCount pending' : '', hasBadge: false,
          color: pendingOffersCount > 0 ? AppConstants.warningAmber : cs.outline, onTap: onOfferToCooperative),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.6),
      itemCount: actions.length,
      itemBuilder: (_, i) {
        final a = actions[i];
        return GestureDetector(
          onTap: a.onTap,
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
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: a.color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
                      child: Icon(a.icon, color: a.color, size: 20),
                    ),
                    if (a.badge.isNotEmpty)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
                          child: Text(
                            a.badge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    a.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final String badge;
  final bool hasBadge;
  final Color color;
  final VoidCallback onTap;
  const _ActionItem({required this.icon, required this.label, required this.badge, required this.hasBadge, required this.color, required this.onTap});
}


class _ShimmerBlock extends StatelessWidget {
  final double height;
  const _ShimmerBlock({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
    );
  }
}