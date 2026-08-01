import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/marketplace_listing_model.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  final _repo = ListingRepository();
  final _notifRepo = NotificationRepository();
  final _searchController = TextEditingController();

  List<MarketplaceListingModel> _allListings = [];
  List<MarketplaceListingModel> _filtered = [];
  ListingFilter _activeFilter = ListingFilter.all;
  String _searchQuery = '';
  int _unreadCount = 0;
  bool _isLoading = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    AppEventService.instance.addListener(_onDataChanged);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _searchController.addListener(_onSearchChanged);
    _loadData();
  }

  @override
  void dispose() {
    AppEventService.instance.removeListener(_onDataChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) _loadData();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _applyFilter();
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchListings(),
      _notifRepo.fetchUnreadCount(),
    ]);
    if (!mounted) return;
    setState(() {
      _allListings = results[0] as List<MarketplaceListingModel>;
      _unreadCount = results[1] as int;
      _applyFilter();
      _isLoading = false;
    });
  }

  void _setFilter(ListingFilter f) {
    setState(() {
      _activeFilter = f;
      _applyFilter();
    });
  }

  void _applyFilter() {
    final q = _searchQuery.trim().toLowerCase();
    _filtered = _allListings.where((l) {
      if (!_activeFilter.matches(l)) return false;
      if (q.isEmpty) return true;
      return l.cropName.toLowerCase().contains(q) ||
          (l.variety?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  int _countFor(bool Function(MarketplaceListingModel) test) =>
      _allListings.where(test).length;

  int _countForFilter(ListingFilter f) =>
      _allListings.where((l) => f.matches(l)).length;

  // ── KPI computations ────────────────────────────────────────────────────

  double get _activeMarketValue => _allListings
      .where((l) => l.isLive)
      .fold<double>(0, (sum, l) => sum + (l.pricePerKg * l.volumeKg));

  int get _liveCount => _countFor((l) => l.isLive);

  int get _awaitingActionCount =>
      _countFor((l) => l.isPending) + _countFor((l) => l.needsChanges);

  List<MarketplaceListingModel> get _needsAttention =>
      _allListings.where((l) => l.needsChanges).toList();

  // ── Actions ───────────────────────────────────────────────────────────────

  void _confirmWithdraw(MarketplaceListingModel listing) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text(
          'Withdraw Listing?',
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '${listing.displayName} will be removed from the marketplace. You can create a new listing for this batch later.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppConstants.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: AppConstants.outline),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _repo.withdrawListing(listing.id);
              if (!mounted) return;
              _loadData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.errorRed,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            child: Text('Withdraw', style: GoogleFonts.poppins(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(MarketplaceListingModel listing) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text(
          'Delete Listing?',
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will permanently delete the listing for ${listing.displayName}. This action cannot be undone.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppConstants.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: AppConstants.outline),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _repo.deleteListing(listing.id);
              if (!mounted) return;
              _loadData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.errorRed,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            child: Text('Delete', style: GoogleFonts.poppins(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  void _showListingMenu(MarketplaceListingModel listing) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ListingMenuSheet(
        listing: listing,
        onWithdraw: () {
          Navigator.pop(context);
          _confirmWithdraw(listing);
        },
        onDelete: () {
          Navigator.pop(context);
          _confirmDelete(listing);
        },
      ),
    );
  }

  void _viewLive(MarketplaceListingModel listing) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ListingPreviewSheet(listing: listing),
    );
  }

  void _editAndResubmit(MarketplaceListingModel listing) {
    Navigator.of(
      context,
    ).pushNamed(AppRoutes.createListing, arguments: listing).then((result) {
      if (result == true) _loadData();
    });
  }

  void _handleFabTap() {
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Go online to create a listing')),
      );
      return;
    }
    context.pushRoute(AppRoutes.createListing).then((result) {
      if (result == true) _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final needsAttention = _needsAttention;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 72),
              if (!_isOnline) const _OfflineBanner(),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 100),
                    children: [
                      // KPI overview
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _isLoading
                            ? Row(
                                children: const [
                                  Expanded(child: _Shimmer(height: 92)),
                                  SizedBox(width: 12),
                                  Expanded(child: _Shimmer(height: 92)),
                                ],
                              )
                            : _KpiRow(
                                activeMarketValue: _activeMarketValue,
                                liveCount: _liveCount,
                                awaitingActionCount: _awaitingActionCount,
                              ),
                      ),

                      // Needs attention
                      if (!_isLoading && needsAttention.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: PriorityCard(
                            items: needsAttention
                                .map(
                                  (l) => PriorityItem(
                                    title: '${l.displayName} needs changes',
                                    subtitle: (l.adminNotes != null &&
                                            l.adminNotes!.isNotEmpty)
                                        ? l.adminNotes
                                        : 'Admin requested an update before this can go live',
                                    icon: Icons.error_outline_rounded,
                                    severity: PrioritySeverity.critical,
                                    onTap: () => _editAndResubmit(l),
                                  ),
                                )
                                .toList(),
                            allClearTitle: '',
                            allClearMessage: '',
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Search
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _SearchBar(controller: _searchController),
                      ),
                      const SizedBox(height: 14),

                      // Filter chips
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _FilterChips(
                          active: _activeFilter,
                          countFor: _countForFilter,
                          onSelected: _setFilter,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Listing cards
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _isLoading
                            ? Column(
                                children: List.generate(
                                  3,
                                  (_) => Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: _ListingShimmer(),
                                  ),
                                ),
                              )
                            : _filtered.isEmpty
                            ? _EmptyState(
                                hasFilter: _activeFilter != ListingFilter.all ||
                                    _searchQuery.isNotEmpty,
                              )
                            : Column(
                                children: _filtered
                                    .map(
                                      (listing) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 14,
                                        ),
                                        child: _ListingCard(
                                          listing: listing,
                                          onMenuTap: () =>
                                              _showListingMenu(listing),
                                          onWithdraw: () =>
                                              _confirmWithdraw(listing),
                                          onViewLive: () => _viewLive(listing),
                                          onEditResubmit: () =>
                                              _editAndResubmit(listing),
                                          onDelete: () =>
                                              _confirmDelete(listing),
                                        ),
                                      ),
                                    )
                                    .toList(),
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
            child: FarmerTopBar(
              title: 'Marketplace',
              unreadCount: _unreadCount,
              hideProfileAvatar: true,
              onProfileTap: () => context.goTab(AppRoutes.farmerProfile),
              onNotificationTap: () =>
                  context.pushRoute(AppRoutes.farmerNotifications),
            ),
          ),
        ],
      ),
      floatingActionButton: _CreateListingFab(
        isOnline: _isOnline,
        onTap: _handleFabTap,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI Row
// ─────────────────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final double activeMarketValue;
  final int liveCount;
  final int awaitingActionCount;

  const _KpiRow({
    required this.activeMarketValue,
    required this.liveCount,
    required this.awaitingActionCount,
  });

  String _formatCurrency(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active Market Value',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppConstants.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '₱${_formatCurrency(activeMarketValue)}',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.primaryGreen,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$liveCount live on market',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppConstants.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Awaiting Action',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppConstants.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$awaitingActionCount',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: awaitingActionCount > 0
                        ? AppConstants.warningAmber
                        : AppConstants.charcoal,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  awaitingActionCount > 0
                      ? 'Pending review or changes'
                      : 'All caught up',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppConstants.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search Bar
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: InputDecoration(
        hintText: 'Search your listings...',
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppConstants.outline.withValues(alpha: 0.60),
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppConstants.outline,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: AppConstants.outline.withValues(alpha: 0.20),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: AppConstants.outline.withValues(alpha: 0.20),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(color: AppConstants.primaryGreen),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter Chips
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  final ListingFilter active;
  final int Function(ListingFilter) countFor;
  final ValueChanged<ListingFilter> onSelected;

  const _FilterChips({
    required this.active,
    required this.countFor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ListingFilter.values.map((f) {
          final isActive = f == active;
          final count = countFor(f);
          final label = (f != ListingFilter.all && count > 0)
              ? '${f.label} ($count)'
              : f.label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: Border.all(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.20),
                  ),
                ),
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Listing Card
// ─────────────────────────────────────────────────────────────────────────────

class _ListingCard extends StatelessWidget {
  final MarketplaceListingModel listing;
  final VoidCallback onMenuTap;
  final VoidCallback onWithdraw;
  final VoidCallback onViewLive;
  final VoidCallback onEditResubmit;
  final VoidCallback onDelete;

  const _ListingCard({
    required this.listing,
    required this.onMenuTap,
    required this.onWithdraw,
    required this.onViewLive,
    required this.onEditResubmit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = listing.isPending
        ? AppConstants.warningAmber
        : listing.needsChanges
        ? AppConstants.errorRed
        : null;

    return Opacity(
      opacity: listing.isWithdrawn ? 0.65 : 1.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.70),
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.30),
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.shadow.withValues(alpha: 0.05),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (borderColor != null)
                  Container(width: 4, color: borderColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: listing.needsChanges
                        ? _ChangesRequiredContent(
                            listing: listing,
                            onEditResubmit: onEditResubmit,
                            onDelete: onDelete,
                          )
                        : _StandardContent(
                            listing: listing,
                            onMenuTap: onMenuTap,
                            onWithdraw: onWithdraw,
                            onViewLive: onViewLive,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StandardContent extends StatelessWidget {
  final MarketplaceListingModel listing;
  final VoidCallback onMenuTap;
  final VoidCallback onWithdraw;
  final VoidCallback onViewLive;

  const _StandardContent({
    required this.listing,
    required this.onMenuTap,
    required this.onWithdraw,
    required this.onViewLive,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PhotoThumb(listing: listing),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _StatusBadge(status: listing.status),
                      if (listing.isPending)
                        Text(
                          DateFormat('MMM d, yyyy').format(listing.createdAt),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.outline,
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: onMenuTap,
                          child: const Icon(
                            Icons.more_vert_rounded,
                            size: 20,
                            color: AppConstants.outline,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    listing.displayName,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: listing.isWithdrawn
                          ? AppConstants.outline
                          : AppConstants.charcoal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '₱${listing.pricePerKg.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: listing.isWithdrawn
                              ? AppConstants.outline
                              : AppConstants.primaryGreen,
                        ),
                      ),
                      Text(
                        '/kg',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppConstants.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    listing.isLive && listing.submittedAt != null
                        ? 'Volume: ${listing.volumeKg.toStringAsFixed(0)} kg • Submitted ${DateFormat('MMM d, yyyy').format(listing.submittedAt!)}'
                        : listing.isWithdrawn
                        ? '₱${listing.pricePerKg.toStringAsFixed(2)}/kg • ${listing.volumeKg.toStringAsFixed(0)} kg'
                        : 'Volume: ${listing.volumeKg.toStringAsFixed(0)} kg',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppConstants.outline,
                    ),
                  ),
                  if (listing.isWithdrawn && listing.updatedAt != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          size: 13,
                          color: AppConstants.outline,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Removed on ${DateFormat('MMM d, yyyy').format(listing.updatedAt!)}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (listing.isPending || listing.isLive) ...[
          const SizedBox(height: 14),
          StatusStepper.forListingStatus(listing.status),
        ],
        if (listing.isPending) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onWithdraw,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppConstants.outline,
                side: BorderSide(
                  color: AppConstants.outline.withValues(alpha: 0.40),
                ),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: Text(
                'Withdraw Listing',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ] else if (listing.isLive) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onViewLive,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: Text(
                'View Live',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryContainer,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChangesRequiredContent extends StatelessWidget {
  final MarketplaceListingModel listing;
  final VoidCallback onEditResubmit;
  final VoidCallback onDelete;

  const _ChangesRequiredContent({
    required this.listing,
    required this.onEditResubmit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _PhotoThumb(listing: listing, dimmed: true),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.error_rounded,
                        color: Theme.of(context).colorScheme.onError,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _StatusBadge(status: listing.status),
                      Text(
                        DateFormat('MMM d, yyyy').format(listing.createdAt),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppConstants.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    listing.displayName,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppConstants.charcoal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '₱${listing.pricePerKg.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.primaryGreen,
                        ),
                      ),
                      Text(
                        '/kg',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppConstants.outline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (listing.adminNotes != null && listing.adminNotes!.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppConstants.errorRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: AppConstants.errorRed.withValues(alpha: 0.20),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppConstants.errorRed,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(
                          text: 'Admin: ',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: listing.adminNotes),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: onEditResubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Edit & Resubmit',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                  foregroundColor: AppConstants.errorRed,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                child: Text(
                  'Delete',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final MarketplaceListingModel listing;
  final bool dimmed;

  const _PhotoThumb({required this.listing, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 76,
        height: 76,
        child: listing.photoUrl != null
            ? Opacity(
                opacity: dimmed ? 0.60 : 1.0,
                child: Image.network(
                  listing.photoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _FallbackThumb(),
                ),
              )
            : _FallbackThumb(),
      ),
    );
  }
}

class _FallbackThumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(
        context,
      ).colorScheme.secondaryContainer.withValues(alpha: 0.35),
      child: Icon(
        Icons.eco_rounded,
        color: Theme.of(context).colorScheme.primary,
        size: 30,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    String label;
    Color bg;
    Color fg;
    switch (status) {
      case 'pending_review':
        label = 'PENDING REVIEW';
        bg = AppConstants.warningAmber.withValues(alpha: 0.20);
        fg = Theme.of(context).colorScheme.onSecondaryContainer;
        break;
      case 'approved':
        label = 'LIVE ON MARKET';
        bg = AppConstants.successGreen.withValues(alpha: 0.20);
        fg = AppConstants.successGreen;
        break;
      case 'changes_required':
        label = 'CHANGES REQUIRED';
        bg = Theme.of(
          context,
        ).colorScheme.errorContainer.withValues(alpha: 0.70);
        fg = Theme.of(context).colorScheme.onErrorContainer;
        break;
      case 'withdrawn':
        label = 'WITHDRAWN';
        bg = AppConstants.outline.withValues(alpha: 0.20);
        fg = AppConstants.outline;
        break;
      default:
        label = status.toUpperCase();
        bg = AppConstants.outline.withValues(alpha: 0.20);
        fg = AppConstants.outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Listing Preview Sheet (View Live)
// ─────────────────────────────────────────────────────────────────────────────

class _ListingPreviewSheet extends StatelessWidget {
  final MarketplaceListingModel listing;
  const _ListingPreviewSheet({required this.listing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppConstants.outline.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            child: SizedBox(
              width: double.infinity,
              height: 160,
              child: listing.photoUrl != null
                  ? Image.network(
                      listing.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _FallbackThumb(),
                    )
                  : _FallbackThumb(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            listing.displayName,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppConstants.charcoal,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₱${listing.pricePerKg.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.primaryGreen,
                ),
              ),
              Text(
                '/kg',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppConstants.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${listing.volumeKg.toStringAsFixed(0)} kg available',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppConstants.successGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppConstants.successGreen,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This listing is live and visible to buyers on the marketplace.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppConstants.successGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Listing Menu Sheet (three-dot)
// ─────────────────────────────────────────────────────────────────────────────

class _ListingMenuSheet extends StatelessWidget {
  final MarketplaceListingModel listing;
  final VoidCallback onWithdraw;
  final VoidCallback onDelete;

  const _ListingMenuSheet({
    required this.listing,
    required this.onWithdraw,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppConstants.outline.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            listing.displayName,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Divider(height: 20),
          if (listing.isLive)
            _MenuOption(
              icon: Icons.remove_circle_outline_rounded,
              label: 'Withdraw Listing',
              onTap: onWithdraw,
            ),
          if (listing.isWithdrawn)
            _MenuOption(
              icon: Icons.delete_outline_rounded,
              label: 'Delete Listing',
              color: AppConstants.errorRed,
              onTap: onDelete,
            ),
        ],
      ),
    );
  }
}

class _MenuOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _MenuOption({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        tileColor: Colors.transparent,
        leading: Icon(
          icon,
          color: color ?? AppConstants.onSurfaceVariant,
          size: 22,
        ),
        title: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: color ?? AppConstants.onSurface,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasFilter;

  const _EmptyState({required this.hasFilter});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.secondaryContainer.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasFilter
                  ? Icons.search_off_rounded
                  : Icons.storefront_outlined,
              size: 38,
              color: AppConstants.outline.withValues(alpha: 0.60),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            hasFilter ? 'No listings match this search' : 'No listings yet',
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppConstants.charcoal,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasFilter
                ? 'Try a different search term or filter'
                : 'Create a listing from your inventory to start selling to buyers. Tap the + button to get started.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shimmer block (KPI loading state)
// ─────────────────────────────────────────────────────────────────────────────

class _Shimmer extends StatelessWidget {
  final double height;
  const _Shimmer({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offline Banner
// ─────────────────────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Theme.of(
        context,
      ).colorScheme.secondaryContainer.withValues(alpha: 0.18),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Text(
            'Offline — Showing cached listings.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer (listing card)
// ─────────────────────────────────────────────────────────────────────────────

class _ListingShimmer extends StatefulWidget {
  @override
  State<_ListingShimmer> createState() => _ListingShimmerState();
}

class _ListingShimmerState extends State<_ListingShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(
      begin: -1,
      end: 2,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _block(double w, double h) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          stops: [
            (_anim.value - 1).clamp(0.0, 1.0),
            _anim.value.clamp(0.0, 1.0),
            (_anim.value + 1).clamp(0.0, 1.0),
          ],
          colors: [
            Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _block(76, 76),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _block(100, 16),
                const SizedBox(height: 8),
                _block(120, 14),
                const SizedBox(height: 8),
                _block(80, 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAB
// ─────────────────────────────────────────────────────────────────────────────

class _CreateListingFab extends StatelessWidget {
  final bool isOnline;
  final VoidCallback onTap;

  const _CreateListingFab({required this.isOnline, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 64),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isOnline
                ? null
                : AppConstants.outline.withValues(alpha: 0.50),
            gradient: isOnline
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppConstants.primaryContainer,
                      AppConstants.primaryGreen,
                    ],
                  )
                : null,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color:
                    (isOnline
                            ? AppConstants.primaryGreen
                            : AppConstants.outline)
                        .withValues(alpha: 0.30),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.add_rounded,
            color: Theme.of(context).colorScheme.onPrimary,
            size: 30,
          ),
        ),
      ),
    );
  }
}