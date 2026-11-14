import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/utils/listing_order.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/marketplace_listing_model.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/repositories/shelf_life_repository.dart';
import '../../widgets/listing_filter_modal.dart'
    show MarketplaceFilterBar, MarketplaceFilterOption;
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/table_change_watcher.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../../data/guest/guest_farmer_sample_data.dart';
import '../../../data/services/guest_mode_service.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/guest_prompt.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/listing_status_badge.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import 'farmer_marketplace_tab.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/app_error_message.dart';

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
  // Each listing's real ordered amount (its orders' own totals), so a later
  // price change never rewrites what earlier orders were worth.
  Map<String, double> _orderedAmounts = {};
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
  TableChangeWatcher? _stockWatcher;

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
    // The quantity left on each of the Farmer's listings drops as orders come
    // in, so it follows the database live.
    if (!GuestModeService.active) {
      _stockWatcher = TableChangeWatcher(
        tables: const ['marketplace_listings', 'orders'],
        onChange: () {
          if (mounted) _loadData(silent: true);
        },
      )..start();
    }
  }

  @override
  void dispose() {
    _stockWatcher?.dispose();
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

  Future<void> _loadData({bool silent = false}) async {
    // Explore as Farmer: made-up listings, no repository or database call.
    if (GuestModeService.active) {
      setState(() {
        _allListings = GuestFarmerSampleData.listings;
        _unreadCount = 0;
        _applyFilter();
        _isLoading = false;
      });
      return;
    }
    if (!silent) setState(() => _isLoading = true);
    // Shelf-life state first (expiry-day discount, unavailable listings); a
    // silent refresh skips it, the full load already ran it.
    if (!silent) await ShelfLifeRepository().process();
    final results = await Future.wait([
      _repo.fetchListings(),
      _notifRepo.fetchUnreadCount(),
      _repo.fetchOrderedAmounts(),
    ]);
    if (!mounted) return;
    setState(() {
      _allListings = results[0] as List<MarketplaceListingModel>;
      _unreadCount = results[1] as int;
      _orderedAmounts = results[2] as Map<String, double>;
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
    // Live listings first, Sold Out / Disapproved / Withdrawn at the bottom.
    _filtered = orderForFarmerListings(
      _allListings.where((l) {
        if (!_activeFilter.matches(l)) return false;
        if (q.isEmpty) return true;
        return l.cropName.toLowerCase().contains(q) ||
            (l.variety?.toLowerCase().contains(q) ?? false);
      }),
    );
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
      .fold<double>(
        0,
        (sum, l) =>
            sum +
            (_orderedAmounts[l.id] ??
                moneyOf(l.volumeKg - l.remainingKg, l.pricePerKg)),
      );

  int get _availableCount => _countFor((l) => l.isAvailable);

  int get _pendingCount => _countFor((l) => l.isPending);

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _promptManageListing() => context.promptFarmer(
    (l) => l.guestManageListingTitle,
    (l) => l.guestManageListingMessage,
    icon: Icons.storefront_outlined,
  );

  void _confirmDelete(MarketplaceListingModel listing) {
    if (GuestModeService.active) {
      _promptManageListing();
      return;
    }
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).enhThisActionRequiresAnInternetConnectionPleaseTry,
          ),
          backgroundColor: AppConstants.snackbarWarning,
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
          AppLocalizations.of(context).enhDeleteListing,
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          AppLocalizations.of(
            context,
          ).enhThisWillPermanentlyDeleteTheListingForThis(
            (listing.displayName).toString(),
          ),
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              AppLocalizations.of(context).cancel,
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.outline,
              ),
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
                  SnackBar(
                    content: Text(
                      friendlyError(AppLocalizations.of(context), e),
                    ),
                  ),
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(
                        context,
                      ).enhFailedToDeletePleaseTryAgain,
                    ),
                  ),
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
            child: Text(
              AppLocalizations.of(context).exportDeleteButton,
              style: GoogleFonts.poppins(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // Phase 12 — every card tap opens the parameterized detail screen
  // regardless of status; Withdraw/Delete/Edit & Resubmit now live there
  // instead of as inline card buttons or a bottom-sheet menu.
  void _openDetail(MarketplaceListingModel listing) {
    if (GuestModeService.active) {
      _promptManageListing();
      return;
    }
    context.pushRoute(AppRoutes.myListingDetail, extra: listing);
  }

  void _handleFabTap() {
    if (GuestModeService.active) {
      context.promptFarmer(
        (l) => l.guestCreateListingTitle,
        (l) => l.guestCreateListingMessage,
        icon: Icons.add_business_outlined,
      );
      return;
    }
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).enhGoOnlineToCreateAListing,
          ),
        ),
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
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const TopBarSpacer(height: 72),
                    CachedDataNotice(
                      screen: 'my_listings',
                      isOnline: _isOnline,
                      offlineMessage: AppLocalizations.of(
                        context,
                      ).offlineListingActionsSome,
                    ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: _ListingTabs(
                                selected: _selectedTab,
                                onSelected: (i) =>
                                    setState(() => _selectedTab = i),
                              ),
                            ),
                            const SizedBox(height: 16),

                            if (_selectedTab == 1) ...[
                              if (GuestModeService.active) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 20),
                                  child: GuestSampleBanner(),
                                ),
                                const SizedBox(height: 16),
                              ],
                              // Listing Overview — one consolidated card (stats +
                              // priority actions) matching Admin Marketplace's own
                              // Overview card, replacing the separate KPI-tile row
                              // and standalone Needs Attention card from before.
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: _isLoading
                                    ? const SkeletonBlock(height: 150)
                                    : _ListingOverviewCard(
                                        availableCount: _availableCount,
                                        totalSold: _totalSold,
                                        pendingCount: _pendingCount,
                                        onPendingTap: () =>
                                            _setFilter(ListingFilter.pending),
                                      ),
                              ),

                              const SizedBox(height: 16),

                              // Search
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: _SearchBar(
                                  controller: _searchController,
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Filter chips
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: _FilterChips(
                                  active: _activeFilter,
                                  countFor: _countForFilter,
                                  onSelected: _setFilter,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Listing cards
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: _isLoading
                                    ? Column(
                                        children: List.generate(
                                          3,
                                          (_) => const Padding(
                                            padding: EdgeInsets.only(
                                              bottom: 14,
                                            ),
                                            child: SkeletonBlock(height: 140),
                                          ),
                                        ),
                                      )
                                    : _filtered.isEmpty
                                    ? _EmptyState(
                                        hasFilter:
                                            _activeFilter !=
                                                ListingFilter.all ||
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
                                                  onTap: () =>
                                                      _openDetail(listing),
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
                    title: _selectedTab == 0
                        ? AppLocalizations.of(context).navMarketplace
                        : AppLocalizations.of(context).navListings,
                    unreadCount: _unreadCount,
                    hideProfileAvatar: true,
                    onProfileTap: () => context.goTab(AppRoutes.farmerProfile),
                    onNotificationTap: () => GuestModeService.active
                        ? context.promptFarmer(
                            (l) => l.guestNotificationsTitle,
                            (l) => l.guestNotificationsMessage,
                            icon: Icons.notifications_none_rounded,
                          )
                        : context.pushRoute(AppRoutes.farmerNotifications),
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
  final int availableCount;
  final double totalSold;
  final int pendingCount;
  final VoidCallback onPendingTap;

  const _ListingOverviewCard({
    required this.availableCount,
    required this.totalSold,
    required this.pendingCount,
    required this.onPendingTap,
  });

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
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                AppLocalizations.of(context).enhListingOverview,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (_priorityCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppConstants.warningAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                  ),
                  child: Text(
                    '$_priorityCount',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.warningAmber,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _statMini(
                  context,
                  icon: Icons.storefront_outlined,
                  label: AppLocalizations.of(context).enhAvailableListings,
                  value: '$availableCount',
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: cs.outline.withValues(alpha: 0.15),
              ),
              Expanded(
                child: _statMini(
                  context,
                  icon: Icons.payments_outlined,
                  label: AppLocalizations.of(context).enhTotalSold,
                  value: formatPesosCompact(totalSold),
                ),
              ),
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
                title: AppLocalizations.of(context).enhListingPendingApproval(
                  (pendingCount).toString(),
                  (pendingCount == 1 ? '' : 's').toString(),
                ),
                subtitle: AppLocalizations.of(
                  context,
                ).enhAwaitingManagerDecision,
                onTap: onPendingTap,
              ),
          ],
        ],
      ),
    );
  }

  Widget _statMini(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 13,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
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
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.outline,
            ),
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

  const _ListingTabs({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        children: [
          Expanded(
            child: _tab(
              context,
              0,
              AppLocalizations.of(context).navMarketplace,
            ),
          ),
          Expanded(
            child: _tab(context, 1, AppLocalizations.of(context).enhListing),
          ),
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
          color: isActive
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
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
      style: GoogleFonts.inter(
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).enhSearchYourListings,
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.60),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: Theme.of(context).colorScheme.outline,
        ),
        filled: true,
        fillColor: context.saganaColors.cardBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.20),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.20),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
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

  // The standard "Label (n)" chips used across SAGANA. Every chip carries its
  // count, "All" included, and a zero is shown as (0). Each status keeps the
  // colour and wording of the badge on the cards (listing_status_badge.dart),
  // so the filter row and the cards speak the same language.
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MarketplaceFilterBar<ListingFilter>(
      selected: active,
      onSelected: onSelected,
      options: [
        for (final f in ListingFilter.values)
          MarketplaceFilterOption(
            value: f,
            label: listingFilterLabel(l10n, f),
            count: countFor(f),
            color: listingFilterColor(context, f),
          ),
      ],
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
    final borderColor = listingAccentColor(
      context,
      listingStateOf(status: listing.status, remainingKg: listing.remainingKg),
    );

    return SoldOutGrey(
      active: listing.isSoldOut,
      child: Opacity(
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
                    child: _StandardContent(
                      listing: listing,
                      onDelete: onDelete,
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
  final VoidCallback onDelete;

  const _StandardContent({required this.listing, required this.onDelete});

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The badge and the date flow in a Wrap: when the badge is long
                  // (Pending Approval, or Tagalog) the date drops to its own line
                  // instead of being squeezed against the pill.
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ListingStatusBadge.forListing(
                          context,
                          status: listing.status,
                          remainingKg: listing.remainingKg,
                          shelfUnavailable: listing.isShelfUnavailable,
                        ),
                        // The automatic expiry-day discount is on this listing.
                        if (listing.isShelfDiscounted &&
                            !listing.isShelfUnavailable)
                          ListingStatusBadge(
                            label: AppLocalizations.of(
                              context,
                            ).shelfTagDiscounted,
                            color: AppConstants.warningAmber,
                          ),
                        // The Reference Price Range changed and this price is
                        // now outside it.
                        if (listing.priceUpdateRequired)
                          ListingStatusBadge(
                            label: AppLocalizations.of(
                              context,
                            ).priceUpdateRequiredTag,
                            color: AppConstants.errorRed,
                          ),
                        if (!showMenu)
                          Text(
                            AppUtils.formatListingDate(listing.createdAt),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (showMenu)
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      onSelected: (value) {
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'delete',
                          child: _menuRow(
                            Icons.delete_outline_rounded,
                            AppLocalizations.of(context).enhDeleteListing246,
                            AppConstants.errorRed,
                          ),
                        ),
                      ],
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
                      ? Theme.of(context).colorScheme.outline
                      : Theme.of(context).colorScheme.onSurface,
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
                          ? Theme.of(context).colorScheme.outline
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    '/${unitOrDefault(listing.unit)}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                (listing.isLive || listing.isSold) &&
                        listing.submittedAt != null
                    ? AppLocalizations.of(context).enhSubmitted434(
                        (listingQuantityLabel(
                          AppLocalizations.of(context),
                          status: listing.status,
                          remainingKg: listing.remainingKg,
                          volumeKg: listing.volumeKg,
                          unit: listing.unit,
                        )).toString(),
                        (AppUtils.formatListingDate(
                          listing.submittedAt!,
                        )).toString(),
                      )
                    : listing.isWithdrawn
                    ? '${formatPricePerUnit(listing.pricePerKg, listing.unit)} • ${formatQuantityUnit(listing.volumeKg, listing.unit)}'
                    : AppLocalizations.of(context).enhVolume(
                        (formatQuantityUnit(
                          listing.volumeKg,
                          listing.unit,
                        )).toString(),
                      ),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              if (listing.priceUpdateRequired) ...[
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context).priceUpdateRequiredHint(
                    listing.priceUpdateRule!.min.toStringAsFixed(2),
                    listing.priceUpdateRule!.max.toStringAsFixed(2),
                    listing.priceUpdateRule!.unit,
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.errorRed,
                  ),
                ),
              ],
              // Past its shelf life (or discounted for it): say what to do.
              if (listing.isShelfUnavailable || listing.isShelfDiscounted) ...[
                const SizedBox(height: 4),
                Text(
                  listing.isShelfUnavailable
                      ? AppLocalizations.of(context).shelfListingUnavailableHint
                      : AppLocalizations.of(
                          context,
                        ).shelfListingDiscountedHint(
                          (listing.shelfLife?.preDiscountPrice ??
                                  listing.pricePerKg)
                              .toStringAsFixed(2),
                        ),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: listing.isShelfUnavailable
                        ? Theme.of(context).colorScheme.error
                        : AppConstants.warningAmber,
                  ),
                ),
              ],
              if (listing.isWithdrawn && listing.updatedAt != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 13,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      AppLocalizations.of(context).enhRemovedOn(
                        (AppUtils.formatListingDate(
                          listing.updatedAt!,
                        )).toString(),
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.outline,
          ),
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
              hasFilter ? Icons.search_off_rounded : Icons.storefront_outlined,
              size: 38,
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.60),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            hasFilter
                ? AppLocalizations.of(context).enhNoListingsMatchThisSearch
                : AppLocalizations.of(context).marketplaceNoListingsYet,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasFilter
                ? AppLocalizations.of(
                    context,
                  ).enhTryADifferentSearchTermOrFilter
                : AppLocalizations.of(
                    context,
                  ).enhCreateAListingFromYourInventoryToStart,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer (listing card)
// ─────────────────────────────────────────────────────────────────────────────

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
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.50),
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
                            : Theme.of(context).colorScheme.outline)
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
