import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/admin_listing_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';

class AllListingsScreen extends StatefulWidget {
  const AllListingsScreen({super.key});

  @override
  State<AllListingsScreen> createState() => _AllListingsScreenState();
}

class _AllListingsScreenState extends State<AllListingsScreen> {
  final _repo = AdminListingRepository();
  final _searchCtrl = TextEditingController();

  List<AdminListingModel> _allListings = [];
  ListingSummaryStats _stats = ListingSummaryStats.empty;
  bool _isLoading = true;
  bool _isOnline = true;

  String _searchQuery = '';
  String? _statusFilter; // null = All
  String? _cropFilter;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text);
    });
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchAllListings(
        statusFilter: _statusFilter,
        cropFilter: _cropFilter,
      ),
      _repo.fetchSummaryStats(),
    ]);
    if (!mounted) return;
    setState(() {
      _allListings = results[0] as List<AdminListingModel>;
      _stats = results[1] as ListingSummaryStats;
      _isLoading = false;
    });
  }

  List<AdminListingModel> get _filtered {
    if (_searchQuery.isEmpty) return _allListings;
    final q = _searchQuery.toLowerCase();
    return _allListings
        .where(
          (l) =>
              l.cropName.toLowerCase().contains(q) ||
              l.farmerName.toLowerCase().contains(q) ||
              (l.variety?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  void _onStatusFilterChanged(String? status) {
    setState(() => _statusFilter = status);
    _loadAll();
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
    final visible = _filtered;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              // ── Status filter chip row ────────────────────────────────
              _StatusFilterBar(
                stats: _stats,
                selected: _statusFilter,
                onSelected: _onStatusFilterChanged,
                cs: cs,
                sagana: sagana,
              ),
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
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                          children: [
                            // ── Search ──────────────────────────────────
                            TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: 'Search crop, farmer, variety...',
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
                            const SizedBox(height: 16),

                            // ── Result count ─────────────────────────────
                            Row(
                              children: [
                                Text(
                                  '${visible.length} listing${visible.length == 1 ? '' : 's'}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                if (_statusFilter != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(
                                        AppConstants.radiusFull,
                                      ),
                                    ),
                                    child: Text(
                                      _statusLabel(_statusFilter!),
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),

                            // ── Listing cards ─────────────────────────────
                            if (visible.isEmpty)
                              _EmptyState(
                                hasSearch:
                                    _searchQuery.isNotEmpty ||
                                    _statusFilter != null,
                                cs: cs,
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
                                    onTap: () => context
                                        .push(
                                          AppRoutes.listingReview,
                                          extra: listing.id,
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

          // ── Top App Bar ─────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopAppBar(
              totalCount: _stats.total,
              onBack: () => context.pop(),
              sagana: sagana,
              cs: cs,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending_review':
        return 'Pending';
      case 'approved':
        return 'Live';
      case 'changes_required':
        return 'Changes';
      case 'sold':
        return 'Sold';
      default:
        return s;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopAppBar extends StatelessWidget {
  final int totalCount;
  final VoidCallback onBack;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _TopAppBar({
    required this.totalCount,
    required this.onBack,
    required this.sagana,
    required this.cs,
  });

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
                child: Text(
                  'All Listings',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  '$totalCount total',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status Filter Bar
// ─────────────────────────────────────────────────────────────────────────────

class _StatusFilterBar extends StatelessWidget {
  final ListingSummaryStats stats;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _StatusFilterBar({
    required this.stats,
    required this.selected,
    required this.onSelected,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: sagana.cardBackground,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _FilterChip(
              label: 'All',
              count: stats.total,
              active: selected == null,
              color: cs.primary,
              onTap: () => onSelected(null),
              cs: cs,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Pending',
              count: stats.pending,
              active: selected == 'pending_review',
              color: cs.error,
              onTap: () => onSelected('pending_review'),
              cs: cs,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Live',
              count: stats.approved,
              active: selected == 'approved',
              color: AppConstants.successGreen,
              onTap: () => onSelected('approved'),
              cs: cs,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Changes',
              count: stats.changesRequired,
              active: selected == 'changes_required',
              color: AppConstants.warningAmber,
              onTap: () => onSelected('changes_required'),
              cs: cs,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Sold',
              count: stats.sold,
              active: selected == 'sold',
              color: cs.onSurfaceVariant,
              onTap: () => onSelected('sold'),
              cs: cs,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _FilterChip({
    required this.label,
    required this.count,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? Colors.white : cs.onSurface,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withValues(alpha: 0.30)
                    : cs.outline.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// All Listing Card (compact — shows more at once than Pending card)
// ─────────────────────────────────────────────────────────────────────────────

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
    final statusColor = _statusColor(listing.status, cs);
    final statusLabel = listing.statusLabel;

    return GestureDetector(
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
            if (listing.isPending)
              Container(
                width: 3,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: cs.error,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppConstants.radiusLg),
                    bottomLeft: Radius.circular(AppConstants.radiusLg),
                  ),
                ),
              ),
            // Photo thumbnail
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

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Crop + status badge
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
                      _StatusBadge(
                        label: statusLabel,
                        color: statusColor,
                        cs: cs,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Farmer name + time
                  Text(
                    '${listing.farmerName} • ${listing.submittedLabel}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Price + qty + warnings row
                  Row(
                    children: [
                      Text(
                        '₱${listing.pricePerKg.toStringAsFixed(2)}/kg',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                      Text(
                        '  •  ${listing.volumeKg.toStringAsFixed(0)} kg',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      if (listing.hasStockWarning)
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
                              'Stock',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: cs.error,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Right: quick-approve or chevron
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
    );
  }

  Color _statusColor(String status, ColorScheme cs) {
    switch (status) {
      case 'pending_review':
        return cs.error;
      case 'approved':
        return AppConstants.successGreen;
      case 'changes_required':
        return AppConstants.warningAmber;
      case 'sold':
        return cs.onSurfaceVariant;
      default:
        return cs.outline;
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

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final ColorScheme cs;
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  final ColorScheme cs;
  const _EmptyState({required this.hasSearch, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: cs.outline.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            hasSearch ? 'No listings match your filter' : 'No listings yet',
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
