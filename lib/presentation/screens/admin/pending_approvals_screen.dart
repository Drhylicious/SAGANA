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

class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  static String buildViewAllLabel(int pendingCount) {
    if (pendingCount <= 0) {
      return 'View All Listings';
    }
    return 'View All $pendingCount Pending Listings';
  }

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  final _repo = AdminListingRepository();

  List<AdminListingModel> _pending = [];
  ListingSummaryStats _stats = ListingSummaryStats.empty;
  bool _isLoading = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchPendingListings(),
      _repo.fetchSummaryStats(),
    ]);
    if (!mounted) return;
    setState(() {
      _pending = results[0] as List<AdminListingModel>;
      _stats = results[1] as ListingSummaryStats;
      _isLoading = false;
    });
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
            ? AppConstants.successGreen
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
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // ── Top App Bar ───────────────────────────────────────────────
          _TopBar(sagana: sagana, cs: cs),

          Expanded(
            child: RefreshIndicator(
              color: AppConstants.primaryGreen,
              onRefresh: _loadAll,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppConstants.primaryGreen,
                      ),
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              // ── Stats pills ─────────────────────────
                              _StatsPillRow(
                                stats: _stats,
                                cs: cs,
                                sagana: sagana,
                              ),
                              const SizedBox(height: 20),

                              // ── Section header ───────────────────────
                              Row(
                                children: [
                                  Icon(
                                    Icons.pending_actions_rounded,
                                    size: 18,
                                    color: cs.error,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Pending Approvals',
                                    style: GoogleFonts.poppins(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  if (_stats.pending > 0) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.error,
                                        borderRadius: BorderRadius.circular(
                                          AppConstants.radiusFull,
                                        ),
                                      ),
                                      child: Text(
                                        '${_stats.pending}',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),

                              // ── Empty state ─────────────────────────
                              if (_pending.isEmpty)
                                _EmptyPendingState(cs: cs)
                              else ...[
                                ..._pending.map(
                                  (listing) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _PendingListingCard(
                                      listing: listing,
                                      cs: cs,
                                      sagana: sagana,
                                      onTap: () => context
                                          .push(
                                            AppRoutes.listingReview,
                                            extra: listing.id,
                                          )
                                          .then((_) => _loadAll()),
                                      onQuickApprove: _isOnline
                                          ? () => _quickApprove(listing)
                                          : null,
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 20),

                              // ── View All Listings button ─────────────
                              GestureDetector(
                                onTap: () =>
                                    context.push(AppRoutes.allListings),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
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
                                        Icons.list_alt_rounded,
                                        size: 18,
                                        color: cs.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        PendingApprovalsScreen.buildViewAllLabel(
                                          _pending.length,
                                        ),
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: cs.primary,
                                        ),
                                      ),
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
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar (shell-tab style — no back button)
// ─────────────────────────────────────────────────────────────────────────────

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
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              Icon(Icons.storefront_outlined, color: cs.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                l10n.listingsPendingTitle,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats Pill Row
// ─────────────────────────────────────────────────────────────────────────────

class _StatsPillRow extends StatelessWidget {
  final ListingSummaryStats stats;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _StatsPillRow({
    required this.stats,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Pill(
            label: 'Total',
            value: stats.total,
            color: cs.primary,
            cs: cs,
            sagana: sagana,
          ),
          const SizedBox(width: 8),
          _Pill(
            label: 'Pending',
            value: stats.pending,
            color: cs.error,
            cs: cs,
            sagana: sagana,
          ),
          const SizedBox(width: 8),
          _Pill(
            label: 'Live',
            value: stats.approved,
            color: AppConstants.successGreen,
            cs: cs,
            sagana: sagana,
          ),
          const SizedBox(width: 8),
          _Pill(
            label: 'Changes',
            value: stats.changesRequired,
            color: AppConstants.warningAmber,
            cs: cs,
            sagana: sagana,
          ),
          const SizedBox(width: 8),
          _Pill(
            label: 'Sold',
            value: stats.sold,
            color: cs.onSurfaceVariant,
            cs: cs,
            sagana: sagana,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _Pill({
    required this.label,
    required this.value,
    required this.color,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          Text(
            '$value',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending Listing Card
// ─────────────────────────────────────────────────────────────────────────────

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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: listing.hasStockWarning
              ? Border(
                  left: BorderSide(color: cs.error, width: 4),
                  top: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
                  right: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
                  bottom: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
                )
              : Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Photo or placeholder ────────────────────────────────────
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
                  // ── Crop + badges ─────────────────────────────────────
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
                  const SizedBox(height: 4),

                  // ── Farmer + time ─────────────────────────────────────
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
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: cs.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Price + quantity ──────────────────────────────────
                  Row(
                    children: [
                      _InfoChip(
                        icon: Icons.payments_outlined,
                        label: '₱${listing.pricePerKg.toStringAsFixed(2)}/kg',
                        cs: cs,
                      ),
                      const SizedBox(width: 8),
                      _InfoChip(
                        icon: Icons.scale_outlined,
                        label: '${listing.volumeKg.toStringAsFixed(0)} kg',
                        cs: cs,
                      ),
                      const Spacer(),
                      // ── Price vs market indicator ───────────────────
                      if (listing.priceDiffPercent != null)
                        _PriceIndicator(listing: listing, cs: cs),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
                  const SizedBox(height: 12),

                  // ── Review + quick approve buttons ────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
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
                                  Icons.rate_review_outlined,
                                  size: 16,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Review',
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: onQuickApprove,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: onQuickApprove != null
                                  ? AppConstants.successGreen
                                  : cs.outline.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusMd,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 16,
                                  color: onQuickApprove != null
                                      ? Colors.white
                                      : cs.outline,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Approve',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: onQuickApprove != null
                                        ? Colors.white
                                        : cs.outline,
                                  ),
                                ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyPendingState extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyPendingState({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 52,
            color: AppConstants.successGreen.withValues(alpha: 0.40),
          ),
          const SizedBox(height: 14),
          Text(
            'All caught up!',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'No listings are waiting for review.',
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
