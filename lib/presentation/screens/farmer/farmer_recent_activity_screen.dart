import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../data/models/dashboard_summary_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/recent_activity_widgets.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';

class FarmerRecentActivityScreen extends StatefulWidget {
  const FarmerRecentActivityScreen({super.key});

  @override
  State<FarmerRecentActivityScreen> createState() =>
      _FarmerRecentActivityScreenState();
}

class _FarmerRecentActivityScreenState
    extends State<FarmerRecentActivityScreen> {
  final _repo = DashboardRepository();
  final _searchController = TextEditingController();

  List<ActivityItem> _allItems = [];
  List<ActivityItem> _filtered = [];
  ActivityFilter _activeFilter = ActivityFilter.all;
  bool _isLoading = true;
  String _searchQuery = '';
  bool _isOnline = true;

  // "Load More" pill at the end of the list — same pattern as Admin
  // Recent Activity's own Load More. fetchActivity already supports
  // offset/limit (it fetches a generous flat amount per source, combines,
  // sorts, then applies skip/take — see DashboardRepository.fetchActivity),
  // so each tap is a genuine incremental fetch, not just revealing more of
  // an already-loaded batch.
  int _page = 0;
  static const _pageSize = 30;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
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
    _loadActivity();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadActivity() async {
    setState(() {
      _page = 0;
      _allItems = [];
      _hasMore = true;
      _isLoading = true;
    });
    try {
      final items = await _repo.fetchActivity(limit: _pageSize, offset: 0);
      if (!mounted) return;
      setState(() {
        _allItems = items;
        _hasMore = items.length == _pageSize;
        _applyFilter();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _page++);
    try {
      final items = await _repo.fetchActivity(
        limit: _pageSize,
        offset: _page * _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _allItems.addAll(items);
        _hasMore = items.length == _pageSize;
        _applyFilter();
      });
    } catch (_) {
      // Best-effort — the already-loaded page stays visible; the pill
      // simply remains tappable for a retry.
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _applyFilter();
    });
  }

  void _setFilter(ActivityFilter filter) {
    setState(() {
      _activeFilter = filter;
      _applyFilter();
    });
  }

  void _applyFilter() {
    final q = _searchQuery.trim().toLowerCase();
    _filtered = _allItems.where((item) {
      final matchesFilter = _activeFilter.matches(item);
      if (!matchesFilter) return false;
      if (q.isEmpty) return true;
      return item.title.toLowerCase().contains(q) ||
          item.subtitle.toLowerCase().contains(q);
    }).toList();
  }

  // ─── Group by date label ─────────────────────────────────────────────────────

  Map<String, List<ActivityItem>> _groupByDate(List<ActivityItem> items) {
    final Map<String, List<ActivityItem>> groups = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final item in items) {
      final itemDate = DateTime(
        item.timestamp.year,
        item.timestamp.month,
        item.timestamp.day,
      );
      String label;
      if (itemDate == today) {
        label = AppLocalizations.of(context).buyerActivityToday;
      } else if (itemDate == yesterday) {
        label = AppLocalizations.of(context).buyerActivityYesterday;
      } else {
        label = DateFormat('MMMM d', AppLocalizations.of(context).localeName).format(item.timestamp);
      }
      groups.putIfAbsent(label, () => []).add(item);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate(_filtered);
    final dateKeys = grouped.keys.toList();

    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // ── Content ──────────────────────────────────────────────
                Column(
                  children: [
                    const SizedBox(height: 72), // space for top bar
                    CachedDataNotice(
                      screen: DashboardRepository.activityCacheScreen(limit: _pageSize),
                      isOnline: _isOnline,
                      offlineMessage: AppLocalizations.of(context).offlineActivity,
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        color: AppConstants.primaryGreen,
                        onRefresh: _loadActivity,
                        child: CustomScrollView(
                          slivers: [
                            // Header + search + chips
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 8),
                                    RecentActivitySearchBar(
                                      controller: _searchController,
                                      hint: AppLocalizations.of(context).activitySearchHint,
                                    ),
                                    const SizedBox(height: 16),
                                    RecentActivityFilterChips<ActivityFilter>(
                                      options: _filterOptions(context),
                                      active: _activeFilter,
                                      onSelected: _setFilter,
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ),

                            // Empty state
                            if (!_isLoading && _filtered.isEmpty)
                              SliverFillRemaining(
                                child: recentActivityEmptyState(
                                  context,
                                  hasSearch:
                                      _searchQuery.isNotEmpty ||
                                      _activeFilter != ActivityFilter.all,
                                ),
                              )
                            // Loading shimmer
                            else if (_isLoading)
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  100,
                                ),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (_, __) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: SkeletonList(count: 4, rowHeight: 80),
                                    ),
                                    childCount: 5,
                                  ),
                                ),
                              )
                            // Grouped timeline
                            else ...[
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  0,
                                ),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate((
                                    context,
                                    index,
                                  ) {
                                    final label = dateKeys[index];
                                    final group = grouped[label]!;
                                    return RecentActivityDateGroup(
                                      label: label,
                                      cards: [
                                        for (final item in group)
                                          _farmerActivityCard(context, item),
                                      ],
                                    );
                                  }, childCount: dateKeys.length),
                                ),
                              ),
                              // Load More pill — same pattern as Admin
                              // Recent Activity. Stays enabled regardless of
                              // search/filter (both are client-side, same as
                              // Admin's own search) — each tap fetches the
                              // next page of the unfiltered feed, then
                              // _applyFilter() re-narrows the bigger set.
                              if (_hasMore)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      0,
                                      20,
                                      16,
                                    ),
                                    child: Center(
                                      child: GestureDetector(
                                        onTap: _loadMore,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              AppConstants.radiusFull,
                                            ),
                                            border: Border.all(
                                              color: AppConstants.outline
                                                  .withValues(alpha: 0.20),
                                            ),
                                          ),
                                          child: Text(
                                            AppLocalizations.of(context).loadMore,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppConstants.primaryGreen,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 84),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Top App Bar ──────────────────────────────────────────
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FarmerTopBar(
                    title: AppLocalizations.of(context).recentActivity,
                    onBack: () => Navigator.of(context).pop(),
                    hideProfileAvatar: true,
                    onProfileTap: () {},
                    onNotificationTap: () {},
                    showNotificationButton: false,
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

String _chipLabel(BuildContext context, ActivityFilter filter) {
  final l10n = AppLocalizations.of(context);
  switch (filter) {
    case ActivityFilter.all:
      return l10n.reportsAll;
    case ActivityFilter.home:
      return l10n.navHome;
    case ActivityFilter.harvest:
      return l10n.navHarvest;
    case ActivityFilter.listing:
      return l10n.navListings;
    case ActivityFilter.profile:
      return l10n.navProfile;
  }
}

List<RecentActivityFilterOption<ActivityFilter>> _filterOptions(
  BuildContext context,
) => [
  for (final filter in ActivityFilter.values)
    RecentActivityFilterOption(value: filter, label: _chipLabel(context, filter)),
];

RecentActivityCard _farmerActivityCard(BuildContext context, ActivityItem item) {
  final l10n = AppLocalizations.of(context);
  final (icon, tone) = _farmerActivityIcon(item);
  return RecentActivityCard(
    icon: icon,
    iconTone: tone,
    title: item.title,
    subtitle: item.subtitle,
    timestamp: item.timestamp,
    valueLabel: item.valueLabel,
    statusLabel: item.statusLabel,
    statusTone: _farmerStatusTone(l10n, item),
    isAlert: item.isAlert,
  );
}

(IconData, RecentActivityIconTone) _farmerActivityIcon(ActivityItem item) =>
    switch (item.type) {
      ActivityType.harvest => (Icons.agriculture_rounded, RecentActivityIconTone.primary),
      ActivityType.listing => (Icons.verified_outlined, RecentActivityIconTone.primary),
      ActivityType.orderPlaced => (Icons.shopping_cart_outlined, RecentActivityIconTone.accent),
      ActivityType.cropRequest => (
          Icons.local_florist_outlined,
          item.isAlert ? RecentActivityIconTone.alert : RecentActivityIconTone.primary,
        ),
      ActivityType.cropAdded => (Icons.grass_rounded, RecentActivityIconTone.primary),
      ActivityType.informalSale => (Icons.sell_outlined, RecentActivityIconTone.accent),
      ActivityType.cropPhotoUpdated => (Icons.photo_camera_outlined, RecentActivityIconTone.primary),
      ActivityType.cooperativeOffer => (Icons.groups_outlined, RecentActivityIconTone.accent),
      ActivityType.marketLinkingEnrollment => (Icons.handshake_outlined, RecentActivityIconTone.primary),
      ActivityType.gingerBatchSubmission => (Icons.outbox_outlined, RecentActivityIconTone.accent),
      ActivityType.profile => (Icons.person_outline_rounded, RecentActivityIconTone.neutral),
      ActivityType.addressUpdated => (Icons.location_on_outlined, RecentActivityIconTone.neutral),
      ActivityType.expenseAdded => (Icons.receipt_long_outlined, RecentActivityIconTone.neutral),
      ActivityType.programEnrollment => (Icons.assignment_turned_in_outlined, RecentActivityIconTone.primary),
      ActivityType.programPurchase => (Icons.shopping_bag_outlined, RecentActivityIconTone.accent),
      ActivityType.capitalReinvestment => (Icons.savings_outlined, RecentActivityIconTone.primary),
      ActivityType.syncCompleted => (Icons.sync_rounded, RecentActivityIconTone.neutral),
    };

// Status colour is decided from the status kind, not the label text, so it
// stays correct when the labels are translated.
RecentActivityTone _farmerStatusTone(AppLocalizations l10n, ActivityItem item) {
  if (item.isAlert) return RecentActivityTone.alert;
  final label = item.statusLabel;
  if (label == null) return RecentActivityTone.neutral;
  if (label == l10n.activityPendingSync ||
      label == l10n.activityPendingReview ||
      label == l10n.activityPending) {
    return RecentActivityTone.warning;
  }
  if (label == l10n.activitySynced) return RecentActivityTone.success;
  return RecentActivityTone.neutral;
}
