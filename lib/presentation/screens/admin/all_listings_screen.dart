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
  String? _categoryFilter; // null = All Categories
  String? _cropFilter; // null = All Crops

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

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchAllListings(
        statusFilter: _statusFilter,
        cropFilter: _cropFilter,
        categoryFilter: _categoryFilter,
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
        .where((l) =>
            l.cropName.toLowerCase().contains(q) ||
            l.farmerName.toLowerCase().contains(q) ||
            (l.variety?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  void _onStatusFilterChanged(String? status) {
    setState(() => _statusFilter = status);
    _loadAll();
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
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _searchCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'Search crop, farmer, variety...',
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
                              ],
                            ),
                            const SizedBox(height: 14),

                            // ── Status chips ──────────────────────────────────
                            SizedBox(
                              height: 34,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  _FilterChip(
                                    label: 'All', count: _stats.total, active: _statusFilter == null,
                                    color: cs.primary, onTap: () => _onStatusFilterChanged(null), cs: cs,
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: 'Pending', count: _stats.pending, active: _statusFilter == 'pending_review',
                                    color: cs.error, onTap: () => _onStatusFilterChanged('pending_review'), cs: cs,
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: 'Live', count: _stats.approved, active: _statusFilter == 'approved',
                                    color: AppConstants.successGreen, onTap: () => _onStatusFilterChanged('approved'), cs: cs,
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: 'Changes', count: _stats.changesRequired, active: _statusFilter == 'changes_required',
                                    color: AppConstants.warningAmber, onTap: () => _onStatusFilterChanged('changes_required'), cs: cs,
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: 'Sold', count: _stats.sold, active: _statusFilter == 'sold',
                                    color: cs.onSurfaceVariant, onTap: () => _onStatusFilterChanged('sold'), cs: cs,
                                  ),
                                  const SizedBox(width: 8),
                                  _FilterChip(
                                    label: 'Rejected', count: _stats.rejected, active: _statusFilter == 'rejected',
                                    color: cs.error, onTap: () => _onStatusFilterChanged('rejected'), cs: cs,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Result-count line intentionally removed — the
                            // filter chips above already show a live count
                            // for every status, including "All". A second
                            // count here was pure duplication.

                            if (visible.isEmpty)
                              _EmptyState(
                                hasSearch: _searchQuery.isNotEmpty || _statusFilter != null || _hasActiveFilter,
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
                                    onTap: () => context
                                        .push(AppRoutes.listingReview, extra: listing.id)
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
                child: Text('All Listings',
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: cs.primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Status Filter Bar ────────────────────────────────────────────────────────
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
            Text(label,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? Colors.white : cs.onSurface)),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: active ? Colors.white.withValues(alpha: 0.30) : cs.outline.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text('$count',
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800,
                      color: active ? Colors.white : cs.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Listing Filter Modal (category → scoped crop list, AND-combined) ─────
// Opened via showManagementModal() as a centered dialog, matching the
// Filter Members reference pattern (header + subtitle, sectioned body,
// Reset All / Apply Filters footer) instead of the old bottom sheet.
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
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
                      Text('₱${listing.pricePerKg.toStringAsFixed(2)}/kg',
                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
                      Text('  •  ${listing.volumeKg.toStringAsFixed(0)} kg',
                          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                      const Spacer(),
                      if (listing.hasStockWarning)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 13, color: cs.error),
                            const SizedBox(width: 2),
                            Text('Stock',
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: cs.error)),
                          ],
                        ),
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

  Color _statusColor(String status, ColorScheme cs) {
    switch (status) {
      case 'pending_review': return cs.error;
      case 'approved': return AppConstants.successGreen;
      case 'changes_required': return AppConstants.warningAmber;
      case 'sold': return cs.onSurfaceVariant;
      case 'rejected': return cs.error;
      default: return cs.outline;
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
          Text(hasSearch ? 'No listings match your filter' : 'No listings yet',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}