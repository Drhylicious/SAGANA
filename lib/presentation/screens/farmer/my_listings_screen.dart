import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/marketplace_listing_model.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/profile_state_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_navigation_drawer.dart';
import '../../widgets/shared_widgets.dart';
import 'farmer_marketplace_tab.dart';

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

  // 0 = Marketplace (Phase 9 — farmer-as-buyer browsing of ALL approved
  // listings, mirrors Buyer Browse), 1 = Listing (management —
  // create/withdraw/resubmit this farmer's own listings; this was index 0
  // and labeled "My Listings" before Phase 9's toggle rename to
  // "Marketplace | Listing"). Deliberately an in-screen segmented control,
  // not a new bottom-nav item or shell branch. Defaults to 1 (Listing) so
  // landing on this tab keeps showing what a farmer previously saw first.
  int _selectedTab = 1;

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

  // Realized value moved through this farmer's listings — the kg actually
  // sold (volumeKg - remainingKg) times the listing's own price. Restricted
  // to isLive/isSold: withdrawn and rejected listings also have
  // remaining_kg reset to 0, but as a released reservation, not a sale —
  // including them here would count every withdrawn/rejected listing's
  // full original volume as "sold," which it wasn't.
  double get _totalSold => _allListings
      .where((l) => l.isLive || l.isSold)
      .fold<double>(0, (sum, l) => sum + ((l.volumeKg - l.remainingKg) * l.pricePerKg));

  int get _liveCount => _countFor((l) => l.isLive);

  int get _pendingCount => _countFor((l) => l.isPending);

  // ── Actions ───────────────────────────────────────────────────────────────

  void _confirmDelete(MarketplaceListingModel listing) {
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This action requires an internet connection. Please try again once you\'re back online.'),
          backgroundColor: AppConstants.warningAmber,
        ),
      );
      return;
    }
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
              try {
                await _repo.deleteListing(listing.id);
                if (!mounted) return;
                _loadData();
              } on PostgrestException catch (e) {
                // delete_listing() now raises a specific message when the
                // listing has order history (Buyer review finding 1.1,
                // Option A) or isn't withdrawn yet. Surface that message
                // directly instead of a generic failure text, so the
                // farmer understands this isn't a bug to retry.
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message)),
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to delete. Please try again.')),
                );
              }
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

  // Phase 12 — every card tap opens the parameterized detail screen
  // regardless of status; Withdraw/Delete/Edit & Resubmit now live there
  // instead of as inline card buttons or a bottom-sheet menu.
  void _openDetail(MarketplaceListingModel listing) {
    context.pushRoute(AppRoutes.myListingDetail, extra: listing);
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

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      drawer: AnimatedBuilder(
        animation: FarmerProfileStateService.instance,
        builder: (context, _) {
          final profile = FarmerProfileStateService.instance.profile;
          return AppNavigationDrawer(
            photoUrl: profile?.profilePhotoUrl,
            displayName: profile?.fullName ?? 'Farmer',
            contactEmail: profile?.contactEmail,
            phoneNumber: profile?.phoneNumber,
            onEditProfile: () {
              Navigator.pop(context);
              context.pushRoute(AppRoutes.farmerEditProfile);
            },
            onEditFarmDetails: () {
              Navigator.pop(context);
              context.pushRoute(AppRoutes.editFarmDetails);
            },
            onMyAddresses: () {
              Navigator.pop(context);
              context.pushRoute(AppRoutes.myAddresses);
            },
            onSignOut: () => confirmFarmerSignOut(context),
            onAboutSagana: () => context.pushRoute(AppRoutes.aboutSagana),
            onAboutOrganization: () => context.pushRoute(AppRoutes.aboutCooperative),
            onPrivacyPolicy: () => context.pushRoute(AppRoutes.privacyPolicy),
            onTermsOfUse: () => context.pushRoute(AppRoutes.termsOfUse),
          );
        },
      ),
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(message: "You're offline — some listing actions require an internet connection."),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 72),
                    Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 100),
                    children: [
                      // Marketplace / Listing — see _selectedTab's comment
                      // for why this is in-screen state, not a new route or
                      // bottom-nav item.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _ListingTabs(
                          selected: _selectedTab,
                          onSelected: (i) => setState(() => _selectedTab = i),
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (_selectedTab == 1) ...[
                      // Listing Overview — one consolidated card (stats +
                      // priority actions) matching Admin Marketplace's own
                      // Overview card, replacing the separate KPI-tile row
                      // and standalone Needs Attention card from before.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _isLoading
                            ? const _Shimmer(height: 150)
                            : _ListingOverviewCard(
                                liveCount: _liveCount,
                                totalSold: _totalSold,
                                pendingCount: _pendingCount,
                                onPendingTap: () => _setFilter(ListingFilter.pending),
                              ),
                      ),

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
                                          onTap: () => _openDetail(listing),
                                          onDelete: () =>
                                              _confirmDelete(listing),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),
                      ] else
                        // Marketplace (Phase 9) — farmer-as-buyer browsing
                        // of every approved listing on the platform
                        // (including this farmer's own, shown but not
                        // purchasable). Replaces the old read-only "Live
                        // Listings" browse of just this farmer's own
                        // listings, per the approved redesign proposal.
                        const FarmerMarketplaceTab(),
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
              title: _selectedTab == 0 ? 'Marketplace' : 'Listings',
              unreadCount: _unreadCount,
              hideProfileAvatar: true,
              onProfileTap: () => context.goTab(AppRoutes.farmerProfile),
              onNotificationTap: () =>
                  context.pushRoute(AppRoutes.farmerNotifications),
              enableMenu: true,
            ),
          ),
              ],
            ),
          ),
        ],
      ),
      // Creating a listing only makes sense from the Listing (management)
      // tab — hidden on Marketplace, matching Buyer Browse having no
      // equivalent create action either.
      floatingActionButton: _selectedTab == 1
          ? _CreateListingFab(isOnline: _isOnline, onTap: _handleFabTap)
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Listing Overview — consolidated card matching Admin Marketplace's own
// Overview treatment (_MarketplaceOverviewCard): accent bar + title + count
// badge, a compact stat row, then a tappable priority-item list. Replaces
// the separate 3-tile KPI row and standalone Needs Attention PriorityCard
// this screen used before — Admin's pattern puts everything important in
// one card, not several stacked ones.
// ─────────────────────────────────────────────────────────────────────────────

class _ListingOverviewCard extends StatelessWidget {
  final int liveCount;
  final double totalSold;
  final int pendingCount;
  final VoidCallback onPendingTap;

  const _ListingOverviewCard({
    required this.liveCount,
    required this.totalSold,
    required this.pendingCount,
    required this.onPendingTap,
  });

  String _formatCurrency(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  int get _priorityCount => pendingCount > 0 ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: flatCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 10),
              Text('Listing Overview', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const Spacer(),
              if (_priorityCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppConstants.warningAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text('$_priorityCount',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppConstants.warningAmber)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _statMini(icon: Icons.storefront_outlined, label: 'Live Listings', value: '$liveCount')),
              Container(width: 1, height: 34, color: cs.outline.withValues(alpha: 0.15)),
              Expanded(child: _statMini(icon: Icons.payments_outlined, label: 'Total Sold', value: '₱${_formatCurrency(totalSold)}')),
            ],
          ),
          if (_priorityCount > 0) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
            const SizedBox(height: 6),
            if (pendingCount > 0)
              _PriorityRow(
                icon: Icons.pending_actions_rounded,
                color: AppConstants.warningAmber,
                title: '$pendingCount listing${pendingCount == 1 ? '' : 's'} pending review',
                subtitle: 'Awaiting admin decision',
                onTap: onPendingTap,
              ),
          ],
        ],
      ),
    );
  }

  Widget _statMini({required IconData icon, required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppConstants.primaryGreen),
              const SizedBox(width: 5),
              Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppConstants.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
        ],
      ),
    );
  }
}

class _PriorityRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PriorityRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppConstants.charcoal),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppConstants.outline),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Listing Tabs — Marketplace / Listing segmented control (Phase 9 toggle
// rename; was My Listings / Live Listings).
// ─────────────────────────────────────────────────────────────────────────────

class _ListingTabs extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;

  const _ListingTabs({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        children: [
          Expanded(child: _tab(context, 0, 'Marketplace')),
          Expanded(child: _tab(context, 1, 'Listing')),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, int index, String label) {
    final isActive = selected == index;
    return GestureDetector(
      onTap: () => onSelected(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Theme.of(context).colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isActive
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
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

  // "All" keeps its own solid-primary treatment (matching every other
  // active chip's prior look) since it doesn't represent one specific
  // status. Every real status chip is colored via the same
  // ListingStatusDisplay.color() mapping _StatusBadge already uses, so a
  // farmer sees the same color language on the filter row as on the cards
  // themselves — the thing the filter chips previously didn't do at all.
  Color _statusColorFor(BuildContext context, ListingFilter f) {
    switch (f) {
      case ListingFilter.all:
        return Theme.of(context).colorScheme.primary;
      case ListingFilter.pending:
        return ListingStatusDisplay.color(context, 'pending_review');
      case ListingFilter.live:
        return ListingStatusDisplay.color(context, 'approved');
      case ListingFilter.withdrawn:
        return ListingStatusDisplay.color(context, 'withdrawn');
      case ListingFilter.rejected:
        return ListingStatusDisplay.color(context, 'rejected');
      case ListingFilter.sold:
        return ListingStatusDisplay.color(context, 'sold');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ListingFilter.values.map((f) {
          final isActive = f == active;
          final isAll = f == ListingFilter.all;
          final count = countFor(f);
          final label = (f != ListingFilter.all && count > 0)
              ? '${f.label} ($count)'
              : f.label;
          final statusColor = _statusColorFor(context, f);
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
                      ? (isAll
                          ? Theme.of(context).colorScheme.primary
                          : statusColor.withValues(alpha: 0.15))
                      : Theme.of(context).colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: Border.all(
                    color: isActive
                        ? statusColor
                        : Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.20),
                    width: isActive ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? (isAll
                            ? Theme.of(context).colorScheme.onPrimary
                            : statusColor)
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
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ListingCard({
    required this.listing,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = listing.isPending ? AppConstants.warningAmber : null;

    return Opacity(
      opacity: listing.isWithdrawn ? 0.65 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: flatCardDecoration(context),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (borderColor != null)
                Container(width: 4, color: borderColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: _StandardContent(listing: listing, onDelete: onDelete),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StandardContent extends StatelessWidget {
  final MarketplaceListingModel listing;
  final VoidCallback onDelete;

  const _StandardContent({
    required this.listing,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Phase 12 — every action (Withdraw/Edit & Resubmit/Delete) now lives
    // on the parameterized detail screen the whole card taps through to.
    // The 3-dot menu here is a Manage-Inventory-style quick action
    // (PopupMenuButton, not a bottom sheet), and only for Withdrawn/
    // Rejected — the two statuses whose only remaining action is Delete,
    // per the approved redesign.
    final showMenu = listing.isWithdrawn || listing.isRejected;

    return Row(
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
                  if (showMenu)
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppConstants.outline),
                      onSelected: (value) {
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'delete',
                          child: _menuRow(Icons.delete_outline_rounded, 'Delete Listing', AppConstants.errorRed),
                        ),
                      ],
                    )
                  else
                    Text(
                      DateFormat('MMM d, yyyy').format(listing.createdAt),
                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.outline),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                listing.displayName,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: listing.isWithdrawn ? AppConstants.outline : AppConstants.charcoal,
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
                      color: listing.isWithdrawn ? AppConstants.outline : AppConstants.primaryGreen,
                    ),
                  ),
                  Text('/kg', style: GoogleFonts.inter(fontSize: 11, color: AppConstants.outline)),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                listing.isLive && listing.submittedAt != null
                    ? 'Volume: ${listing.volumeKg.toStringAsFixed(0)} kg • Submitted ${DateFormat('MMM d, yyyy').format(listing.submittedAt!)}'
                    : listing.isWithdrawn
                    ? '₱${listing.pricePerKg.toStringAsFixed(2)}/kg • ${listing.volumeKg.toStringAsFixed(0)} kg'
                    : 'Volume: ${listing.volumeKg.toStringAsFixed(0)} kg',
                style: GoogleFonts.inter(fontSize: 11, color: AppConstants.outline),
              ),
              if (listing.isWithdrawn && listing.updatedAt != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.history_rounded, size: 13, color: AppConstants.outline),
                    const SizedBox(width: 5),
                    Text(
                      'Removed on ${DateFormat('MMM d, yyyy').format(listing.updatedAt!)}',
                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.outline),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, left: 4),
          child: Icon(Icons.chevron_right_rounded, size: 18, color: AppConstants.outline),
        ),
      ],
    );
  }
}

/// Icon+label row for a PopupMenuItem — matches Manage Inventory's own
/// 3-dot menu-row pattern (_batchMenuRow), the reference this screen's menu
/// follows per the approved redesign.
Widget _menuRow(IconData icon, String label, Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Text(label, style: GoogleFonts.inter(fontSize: 13, color: color)),
    ],
  );
}

class _PhotoThumb extends StatelessWidget {
  final MarketplaceListingModel listing;

  const _PhotoThumb({required this.listing});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 76,
        height: 76,
        child: listing.photoUrl != null
            ? Image.network(
                listing.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _FallbackThumb(),
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
        fg = ListingStatusDisplay.color(context, status);
        bg = fg.withValues(alpha: 0.20);
        break;
      case 'approved':
        label = 'LIVE ON MARKET';
        fg = ListingStatusDisplay.color(context, status);
        bg = fg.withValues(alpha: 0.20);
        break;
      case 'withdrawn':
        label = 'WITHDRAWN';
        fg = ListingStatusDisplay.color(context, status);
        bg = fg.withValues(alpha: 0.20);
        break;
      case 'rejected':
        label = 'REJECTED';
        fg = ListingStatusDisplay.color(context, status);
        bg = fg.withValues(alpha: 0.20);
        break;
      case 'sold':
        label = 'SOLD';
        fg = ListingStatusDisplay.color(context, status);
        bg = fg.withValues(alpha: 0.20);
        break;
      default:
        label = status.toUpperCase();
        fg = ListingStatusDisplay.color(context, status);
        bg = fg.withValues(alpha: 0.20);
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