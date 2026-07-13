import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../widgets/admin_top_bar.dart';
import '../../../data/repositories/admin_listing_repository.dart';
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

  ListingSummaryStats _stats     = ListingSummaryStats.empty;
  List<AdminListingModel> _pending  = [];
  List<AdminListingModel> _recent   = [];
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
      _repo.fetchPendingListings(),
      _repo.fetchRecentListings(limit: 5),
    ]);
    if (!mounted) return;
    setState(() {
      _stats   = results[0] as ListingSummaryStats;
      _pending = results[1] as List<AdminListingModel>;
      _recent  = results[2] as List<AdminListingModel>;
      _isLoading = false;
    });
  }

  Future<void> _quickApprove(AdminListingModel listing) async {
    await _repo.approveListing(listing.id);
    _loadAll();
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
            // Offline banner
            if (!_isOnline)
              SliverToBoxAdapter(
                child: Container(
                  color: AppConstants.warningAmber,
                  padding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off_rounded,
                          size: 14, color: AppConstants.charcoal),
                      const SizedBox(width: 6),
                      Text('Offline — data may be outdated',
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppConstants.charcoal)),
                    ],
                  ),
                ),
              ),

            // Pinned glass top bar
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

                  // ── KPI strip ─────────────────────────────────────────
                  if (_isLoading)
                    const _ShimmerBlock(height: 88)
                  else
                    _KpiStrip(stats: _stats, cs: cs, sagana: sagana),
                  const SizedBox(height: 20),

                  // ── Pending Listings ───────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        if (_stats.pending > 0)
                          Container(
                            width: 8, height: 8,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: const BoxDecoration(
                              color: AppConstants.warningAmber,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Text('Pending Review',
                            style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface)),
                        if (_stats.pending > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppConstants.warningAmber
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusFull),
                            ),
                            child: Text('${_stats.pending}',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppConstants.warningAmber)),
                          ),
                        ],
                      ]),
                      GestureDetector(
                        onTap: () => context
                            .push(AppRoutes.pendingApprovals)
                            .then((_) => _loadAll()),
                        child: Text('Review All',
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_isLoading)
                    const _ShimmerBlock(height: 120)
                  else if (_pending.isEmpty)
                    _EmptySection(
                      icon: Icons.check_circle_outline_rounded,
                      message: 'No listings awaiting review',
                      color: AppConstants.successGreen,
                      cs: cs,
                      sagana: sagana,
                    )
                  else
                    Column(
                      children: _pending.take(3).map((listing) =>
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PendingListingCard(
                              listing: listing,
                              isOnline: _isOnline,
                              onReview: () => context
                                  .push(AppRoutes.listingReview,
                                      extra: listing.id)
                                  .then((_) => _loadAll()),
                              onQuickApprove: _isOnline
                                  ? () => _quickApprove(listing)
                                  : null,
                              cs: cs,
                              sagana: sagana,
                            ),
                          )).toList(),
                    ),

                  if (_stats.pending > 3) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => context
                          .push(AppRoutes.pendingApprovals)
                          .then((_) => _loadAll()),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: AppConstants.warningAmber
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusLg),
                          border: Border.all(
                              color: AppConstants.warningAmber
                                  .withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          '+${_stats.pending - 3} more pending listings',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.warningAmber),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // ── Quick Actions grid ─────────────────────────────────
                  Text('Manage',
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                  const SizedBox(height: 12),
                  _QuickActionsGrid(
                    stats: _stats,
                    cs: cs,
                    sagana: sagana,
                    onAllListings: () => context
                        .push(AppRoutes.allListings)
                        .then((_) => _loadAll()),
                    onBuyerManagement: () =>
                        context.push(AppRoutes.buyerManagement),
                    onMarketLinking: () =>
                        context.push(AppRoutes.marketLinking),
                    onOrders: () =>
                        context.push(AppRoutes.adminOrders),
                  ),
                  const SizedBox(height: 20),

                  // ── Recent Listings ────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Recent Listings',
                          style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface)),
                      GestureDetector(
                        onTap: () => context
                            .push(AppRoutes.allListings)
                            .then((_) => _loadAll()),
                        child: Text('View All',
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_isLoading)
                    const _ShimmerBlock(height: 200)
                  else if (_recent.isEmpty)
                    _EmptySection(
                      icon: Icons.storefront_outlined,
                      message: 'No listings yet',
                      cs: cs,
                      sagana: sagana,
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: sagana.cardBackground,
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusLg),
                        border: Border.all(
                            color: cs.outline.withValues(alpha: 0.10)),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8),
                        ],
                      ),
                      child: Column(
                        children: _recent.asMap().entries.map((entry) {
                          final i       = entry.key;
                          final listing = entry.value;
                          final isLast  = i == _recent.length - 1;
                          return Column(children: [
                            _RecentListingRow(
                              listing: listing,
                              onTap: () => context
                                  .push(AppRoutes.listingReview,
                                      extra: listing.id)
                                  .then((_) => _loadAll()),
                              cs: cs,
                            ),
                            if (!isLast)
                              Divider(
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                  color: cs.outline.withValues(alpha: 0.08)),
                          ]);
                        }).toList(),
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
// KPI Strip
// ─────────────────────────────────────────────────────────────────────────────

class _KpiStrip extends StatelessWidget {
  final ListingSummaryStats stats;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _KpiStrip(
      {required this.stats, required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _KpiTile('Pending',  '${stats.pending}',
          AppConstants.warningAmber,   Icons.pending_actions_rounded),
      _KpiTile('Live',     '${stats.approved}',
          AppConstants.successGreen,   Icons.storefront_rounded),
      _KpiTile('Changes',  '${stats.changesRequired}',
          AppConstants.errorRed,       Icons.edit_note_rounded),
      _KpiTile('Total',    '${stats.total}',
          cs.primary,                  Icons.list_alt_rounded),
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
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(
                  color: cs.outline.withValues(alpha: 0.10)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8),
              ],
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
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
                Text(t.value,
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: t.color)),
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
// Pending Listing Card
// ─────────────────────────────────────────────────────────────────────────────

class _PendingListingCard extends StatelessWidget {
  final AdminListingModel listing;
  final bool isOnline;
  final VoidCallback onReview;
  final VoidCallback? onQuickApprove;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _PendingListingCard({
    required this.listing,
    required this.isOnline,
    required this.onReview,
    this.onQuickApprove,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border(
          left: const BorderSide(
              color: AppConstants.warningAmber, width: 4),
          top: BorderSide(
              color: cs.outline.withValues(alpha: 0.10)),
          right: BorderSide(
              color: cs.outline.withValues(alpha: 0.10)),
          bottom: BorderSide(
              color: cs.outline.withValues(alpha: 0.10)),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Center(
                  child: Text(
                    _cropEmoji(listing.cropName),
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(listing.displayName,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface)),
                    Text(listing.farmerName,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₱${listing.pricePerKg.toStringAsFixed(2)}/kg',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.primary)),
                  Text('${listing.volumeKg.toStringAsFixed(0)} kg',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: cs.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: onReview,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd),
                  ),
                  child: Text('Review',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.primary)),
                ),
              ),
            ),
            if (onQuickApprove != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: onQuickApprove,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: AppConstants.successGreen
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd),
                    ),
                    child: Text('Quick Approve',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.successGreen)),
                  ),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  String _cropEmoji(String cropName) {
    final lower = cropName.toLowerCase();
    if (lower.contains('palay') || lower.contains('rice')) return '🌾';
    if (lower.contains('peanut') || lower.contains('mani')) return '🥜';
    if (lower.contains('ginger') || lower.contains('luya')) return '🫚';
    if (lower.contains('banana') || lower.contains('saging')) return '🍌';
    if (lower.contains('copra') || lower.contains('niyog')) return '🥥';
    return '🌱';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Actions Grid (2×2)
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionsGrid extends StatelessWidget {
  final ListingSummaryStats stats;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onAllListings;
  final VoidCallback onBuyerManagement;
  final VoidCallback onMarketLinking;
  final VoidCallback onOrders;

  const _QuickActionsGrid({
    required this.stats,
    required this.cs,
    required this.sagana,
    required this.onAllListings,
    required this.onBuyerManagement,
    required this.onMarketLinking,
    required this.onOrders,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionItem(
        icon: Icons.list_alt_rounded,
        label: 'All Listings',
        badge: '${stats.total}',
        hasBadge: false,
        color: cs.primary,
        onTap: onAllListings,
      ),
      _ActionItem(
        icon: Icons.people_rounded,
        label: 'Buyer Management',
        badge: '',
        hasBadge: false,
        color: AppConstants.buyerBlue,
        onTap: onBuyerManagement,
      ),
      _ActionItem(
        icon: Icons.alt_route_rounded,
        label: 'Market Linking',
        badge: 'DA-AMAD',
        hasBadge: false,
        color: AppConstants.primaryGreen,
        onTap: onMarketLinking,
      ),
      _ActionItem(
        icon: Icons.shopping_bag_rounded,
        label: 'Orders',
        badge: 'Coming Soon',
        hasBadge: false,
        color: cs.outline,
        onTap: onOrders,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
      ),
      itemCount: actions.length,
      itemBuilder: (_, i) {
        final a = actions[i];
        return GestureDetector(
          onTap: a.onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sagana.cardBackground,
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(
                  color: cs.outline.withValues(alpha: 0.10)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: a.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd),
                      ),
                      child: Icon(a.icon, color: a.color, size: 20),
                    ),
                    if (a.badge.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull),
                        ),
                        child: Text(a.badge,
                            style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurfaceVariant)),
                      ),
                  ],
                ),
                Text(a.label,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
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
  const _ActionItem({
    required this.icon, required this.label, required this.badge,
    required this.hasBadge, required this.color, required this.onTap,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent Listing Row
// ─────────────────────────────────────────────────────────────────────────────

class _RecentListingRow extends StatelessWidget {
  final AdminListingModel listing;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _RecentListingRow(
      {required this.listing, required this.onTap, required this.cs});

  Color _statusColor() {
    switch (listing.status) {
      case 'approved':          return AppConstants.successGreen;
      case 'pending_review':    return AppConstants.warningAmber;
      case 'changes_required':  return AppConstants.errorRed;
      case 'withdrawn':         return cs.outline;
      default:                  return cs.outline;
    }
  }

  String _statusLabel() {
    switch (listing.status) {
      case 'approved':          return 'LIVE';
      case 'pending_review':    return 'PENDING';
      case 'changes_required':  return 'CHANGES';
      case 'withdrawn':         return 'WITHDRAWN';
      default:                  return listing.status.toUpperCase();
    }
  }

  String _timeLabel() {
    // submittedAt is a non-nullable getter on AdminListingModel that returns
    // createdAt — the admin query uses created_at (no submitted_at column).
    final dt  = listing.submittedAt;
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0)   return 'Today';
    if (diff.inDays == 1)   return 'Yesterday';
    if (diff.inDays < 7)    return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor();
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Center(
              child: Text(
                _cropEmoji(listing.cropName),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(listing.displayName,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                Text(listing.farmerName,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull),
                ),
                child: Text(_statusLabel(),
                    style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.4)),
              ),
              const SizedBox(height: 3),
              Text(_timeLabel(),
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded,
              size: 18, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }

  String _cropEmoji(String cropName) {
    final lower = cropName.toLowerCase();
    if (lower.contains('palay') || lower.contains('rice')) return '🌾';
    if (lower.contains('peanut') || lower.contains('mani')) return '🥜';
    if (lower.contains('ginger') || lower.contains('luya')) return '🫚';
    if (lower.contains('banana') || lower.contains('saging')) return '🍌';
    if (lower.contains('copra') || lower.contains('niyog')) return '🥥';
    return '🌱';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color? color;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _EmptySection({
    required this.icon,
    required this.message,
    this.color,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: c.withValues(alpha: 0.50)),
          const SizedBox(height: 8),
          Text(message,
              style: GoogleFonts.inter(
                  fontSize: 13, color: cs.onSurfaceVariant)),
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
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
    );
  }
}