import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../widgets/admin_top_bar.dart';
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
  List<AdminListingModel> _recent   = [];
  OrderSummaryStats _orderStats = OrderSummaryStats.empty;
  int _pendingOffersCount = 0;
  int _buyerCount = 0;
  int _marketLinkingCount = 0;
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
      _repo.fetchRecentListings(limit: 3),
      _orderRepo.fetchSummaryStats(),
      _offerRepo.fetchPendingOffers(),
      _buyerRepo.fetchBuyerCount(),
      _marketLinkingRepo.fetchAll(),
    ]);
    if (!mounted) return;
    setState(() {
      _stats   = results[0] as ListingSummaryStats;
      _recent  = results[1] as List<AdminListingModel>;
      _orderStats = results[2] as OrderSummaryStats;
      _pendingOffersCount = (results[3] as List).length;
      _buyerCount = results[4] as int;
      _marketLinkingCount = (results[5] as List).length;
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
              SliverToBoxAdapter(
                child: Container(
                  color: AppConstants.warningAmber,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 14, color: AppConstants.charcoal),
                      const SizedBox(width: 6),
                      Text('Offline — data may be outdated',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppConstants.charcoal)),
                    ],
                  ),
                ),
              ),

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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

                  // ── Marketplace Overview — executive summary hero ───────
                  // Untouched, per your call — already data-driven, not a
                  // redesign candidate.
                  if (_isLoading)
                    const _ShimmerBlock(height: 108)
                  else
                    _MarketplaceOverviewCard(stats: _stats, orderStats: _orderStats, cs: cs, sagana: sagana),
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
                  const SizedBox(height: 20),

                  // ── Recent Listings ─────────────────────────────────────
                  Text('Recent Listings',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
                  const SizedBox(height: 10),

                  if (_isLoading)
                    const _ShimmerBlock(height: 130)
                  else if (_recent.isEmpty)
                    _EmptySection(
                      icon: Icons.storefront_outlined,
                      message: 'No listings yet',
                      cs: cs, sagana: sagana,
                    )
                  else
                    SizedBox(
                      height: 130,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _recent.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => _RecentListingPreviewCard(
                          listing: _recent[i],
                          onTap: () => context.push(AppRoutes.listingReview, extra: _recent[i].id).then((_) => _loadAll()),
                          cs: cs, sagana: sagana,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.allListings).then((_) => _loadAll()),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                        border: Border.all(color: cs.primary, width: 1.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.list_alt_rounded, size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Text('View All Listings',
                              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.primary)),
                        ],
                      ),
                    ),
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
  final ColorScheme cs;
  final SaganaColors sagana;
  const _MarketplaceOverviewCard({
    required this.stats,
    required this.orderStats,
    required this.cs,
    required this.sagana,
  });

  String get _insight {
    final needsListingReview = stats.pending > 0;
    final needsOrderAction   = orderStats.pending > 0;

    if (!needsListingReview && !needsOrderAction) {
      return "Everything's running smoothly — no listings or orders need attention right now.";
    }
    if (needsListingReview && needsOrderAction) {
      return '${stats.pending} listing${stats.pending == 1 ? '' : 's'} need${stats.pending == 1 ? 's' : ''} review '
          'and ${orderStats.pending} order${orderStats.pending == 1 ? '' : 's'} '
          '${orderStats.pending == 1 ? 'is' : 'are'} awaiting fulfillment.';
    }
    if (needsListingReview) {
      return '${stats.pending} listing${stats.pending == 1 ? '' : 's'} '
          '${stats.pending == 1 ? 'is' : 'are'} waiting for your review.';
    }
    return '${orderStats.pending} order${orderStats.pending == 1 ? '' : 's'} '
        '${orderStats.pending == 1 ? 'is' : 'are'} awaiting fulfillment.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 56,
            decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Marketplace Overview',
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
                const SizedBox(height: 2),
                Text('Real-time governance dashboard',
                    style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                const SizedBox(height: 10),
                Text(_insight,
                    style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface, height: 1.4)),
              ],
            ),
          ),
        ],
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
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final t = tiles[i];
          return Container(
            width: 100,
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
                Row(children: [
                  Icon(t.icon, size: 13, color: t.color),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(t.label,
                        style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
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
                Flexible(
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

// ─────────────────────────────────────────────────────────────────────────────
// Recent Listing Preview Card — unchanged
// ─────────────────────────────────────────────────────────────────────────────

class _RecentListingPreviewCard extends StatelessWidget {
  final AdminListingModel listing;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _RecentListingPreviewCard({required this.listing, required this.onTap, required this.cs, required this.sagana});

  Color get _statusColor {
    switch (listing.status) {
      case 'approved': return AppConstants.successGreen;
      case 'pending_review': return AppConstants.warningAmber;
      case 'changes_required': return AppConstants.warningAmber;
      case 'sold': return cs.onSurfaceVariant;
      case 'rejected': return cs.error;
      case 'withdrawn': return cs.outline;
      default: return cs.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: _statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
              child: Text(listing.statusLabel.toUpperCase(),
                  style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w800, color: _statusColor)),
            ),
            const SizedBox(height: 8),
            Text(listing.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
            Text(listing.farmerName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
            const Spacer(),
            Text('₱${listing.pricePerKg.toStringAsFixed(2)}/kg',
                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets — unchanged
// ─────────────────────────────────────────────────────────────────────────────

class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String message;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _EmptySection({required this.icon, required this.message, required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(color: sagana.cardBackground, borderRadius: BorderRadius.circular(AppConstants.radiusLg), border: Border.all(color: cs.outline.withValues(alpha: 0.10))),
      child: Column(
        children: [
          Icon(icon, size: 36, color: cs.onSurfaceVariant.withValues(alpha: 0.50)),
          const SizedBox(height: 8),
          Text(message, style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
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