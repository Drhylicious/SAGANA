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
import '../../widgets/management_modal.dart'; // TODO: confirm this matches your actual widget path

class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  final _repo = AdminListingRepository();
  final _searchCtrl = TextEditingController();

  List<AdminListingModel> _listings = [];
  bool _isLoading = true;
  bool _isOnline = true;

  String _searchQuery = '';
  String? _statusFilter; // null = All (pending_review + approved + rejected)
  String? _categoryFilter;
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
      _loadAll();
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
    final listings = await _repo.fetchReviewListings(
      statusFilter: _statusFilter,
      searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      cropFilter: _cropFilter,
      categoryFilter: _categoryFilter,
    );
    if (!mounted) return;
    setState(() {
      _listings = listings;
      _isLoading = false;
    });
  }

  bool get _hasActiveFilter => _categoryFilter != null || _cropFilter != null;

  void _openFilterPanel() async {
    final result = await showManagementModal<(String?, String?)>(
      context: context,
      builder: (_) => _ListingFilterModal(
        repo: _repo,
        initialCategory: _categoryFilter,
        initialCrop: _cropFilter,
      ),
    );
    if (result != null) {
      setState(() {
        _categoryFilter = result.$1;
        _cropFilter = result.$2;
      });
      _loadAll();
    }
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
              onRefresh: _loadAll,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        // ── Search + filter ────────────────────────────────
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: 'Search crop, farmer, variety...',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.close_rounded, size: 18),
                                        onPressed: () => _searchCtrl.clear(),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _openFilterPanel,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: _hasActiveFilter ? cs.primary : cs.surfaceContainerHighest,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.tune_rounded,
                                size: 20,
                                color: _hasActiveFilter ? Colors.white : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),

                        // ── Status chips ──────────────────────────────────
                        SizedBox(
                          height: 34,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _FilterChip(
                                label: 'All', active: _statusFilter == null, color: cs.primary,
                                onTap: () { setState(() => _statusFilter = null); _loadAll(); }, cs: cs,
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Pending', active: _statusFilter == 'pending_review', color: AppConstants.warningAmber,
                                onTap: () { setState(() => _statusFilter = 'pending_review'); _loadAll(); }, cs: cs,
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Approved', active: _statusFilter == 'approved', color: AppConstants.successGreen,
                                onTap: () { setState(() => _statusFilter = 'approved'); _loadAll(); }, cs: cs,
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Rejected', active: _statusFilter == 'rejected', color: cs.error,
                                onTap: () { setState(() => _statusFilter = 'rejected'); _loadAll(); }, cs: cs,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── List / empty state ────────────────────────────
                        if (_listings.isEmpty)
                          _EmptyPendingState(
                            cs: cs,
                            sagana: sagana,
                            hasActiveFilter: _searchQuery.isNotEmpty || _statusFilter != null || _hasActiveFilter,
                          )
                        else
                          ..._listings.map(
                            (listing) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PendingListingCard(
                                listing: listing,
                                cs: cs,
                                sagana: sagana,
                                onTap: () => context
                                    .push(AppRoutes.listingReview, extra: listing.id)
                                    .then((_) => _loadAll()),
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
                tooltip: 'Back',
              ),
              Expanded(
                child: Text('Pending Approvals',
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

// ─── Status Filter Chip ─────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _FilterChip({
    required this.label,
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
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.white : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

// ─── Listing Filter Modal (category → scoped crop list, AND-combined) ─────
// Opened via showManagementModal() as a centered dialog, matching the
// Filter Members reference pattern (header + subtitle, sectioned body,
// Reset All / Apply Filters footer) instead of the old bottom sheet.
// Same behavior as All Listings' filter modal — worth promoting to a shared
// widget file rather than duplicating the class now that both screens need
// it identically; flagging that as still open rather than doing it silently
// as part of this pass.
class _ListingFilterModal extends StatefulWidget {
  final AdminListingRepository repo;
  final String? initialCategory;
  final String? initialCrop;

  const _ListingFilterModal({
    required this.repo,
    this.initialCategory,
    this.initialCrop,
  });

  @override
  State<_ListingFilterModal> createState() => _ListingFilterModalState();
}

class _ListingFilterModalState extends State<_ListingFilterModal> {
  String? _category;
  String? _crop;
  List<String> _crops = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _crop = widget.initialCrop;
    _loadCrops();
  }

  Future<void> _loadCrops() async {
    setState(() => _isLoading = true);
    final crops = await widget.repo.fetchCropsByCategory(category: _category);
    if (!mounted) return;
    setState(() {
      _crops = crops;
      // Category change narrows the crop list — drop the previously
      // selected crop if it no longer belongs to the new category.
      if (_crop != null && !_crops.contains(_crop)) _crop = null;
      _isLoading = false;
    });
  }

  void _onCategorySelected(String? category) {
    setState(() => _category = category);
    _loadCrops();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ManagementModalShell(
      title: 'Filter Listings',
      subtitle: 'Refine the list by crop category or crop',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CROP CATEGORY',
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 0.6, color: cs.outline)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ...AdminListingRepository.cropCategories.map((c) =>
                _Chip(label: c, active: _category == c,
                    onTap: () => _onCategorySelected(_category == c ? null : c), cs: cs)),
          ]),
          const SizedBox(height: 20),
          Text('CROPS',
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 0.6, color: cs.outline)),
          const SizedBox(height: 10),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (_crops.isEmpty)
            Text('No crops in this category',
                style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              ..._crops.map((c) =>
                  _Chip(label: c, active: _crop == c,
                      onTap: () => setState(() => _crop = _crop == c ? null : c), cs: cs)),
            ]),
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: cs.outline.withValues(alpha: 0.30)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              onPressed: () => Navigator.pop(context, (null, null)),
              child: Text(
                'Reset All',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, (_category, _crop)),
              child: Text(
                'Apply Filters',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.white : cs.onSurfaceVariant,
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
                            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurface),
                            overflow: TextOverflow.ellipsis),
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
                                Text('Review',
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
                                Text('Approve',
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
          Text(hasActiveFilter ? 'No listings match your filter' : 'All caught up!',
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(
            hasActiveFilter
                ? 'Try a different search or filter.'
                : 'No listings are waiting for review.',
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}