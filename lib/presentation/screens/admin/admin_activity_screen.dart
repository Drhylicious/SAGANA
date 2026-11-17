import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_dashboard_model.dart';
import '../../../data/repositories/admin_activity_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/member_access.dart';
import '../../../core/utils/activity_navigation.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/recent_activity_widgets.dart';

// Builds the localized activity description from an item's raw
// descKind + name/cropName/quantityKg/amount fields — the repository that
// creates AdminActivityItem has no AppLocalizations access (see
// admin_dashboard_model.dart), so the actual sentence is assembled here
// instead. Shared by this screen and admin_dashboard_screen.dart's
// Recent Activity preview (both display the same AdminActivityItem list).
String adminActivityDescription(AppLocalizations l10n, AdminActivityItem item) {
  if (item.plainDescription != null) return item.plainDescription!;
  final name = item.name ?? l10n.defaultFarmerName;
  switch (item.descKind!) {
    case AdminActivityDescKind.harvest:
      return l10n.adminActivityNewHarvest(
        name,
        item.quantityKg ?? '',
        item.cropName ?? '',
      );
    case AdminActivityDescKind.listingApproved:
      return l10n.adminActivityListingApproved(item.cropName ?? '', name);
    case AdminActivityDescKind.listingSubmitted:
      return l10n.adminActivityListingSubmitted(name, item.cropName ?? '');
    case AdminActivityDescKind.orderPlaced:
      return l10n.adminActivityOrderPlaced(item.amount ?? '');
    case AdminActivityDescKind.priceUpdated:
      return l10n.adminActivityPriceUpdated(
        item.cropName ?? '',
        item.amount ?? '',
      );
    case AdminActivityDescKind.newMember:
      return l10n.adminActivityNewMember(
        item.name ?? l10n.adminActivityNewMemberFallback,
      );
    case AdminActivityDescKind.cropRequested:
      return l10n.adminActivityCropRequested(name, item.cropName ?? '');
  }
}

// Module-keyed color/icon/label — the single lookup every activity item
// (legacy 6-source AND admin_activity_log-backed) renders through, keyed
// by AdminActivityItem.sourceModule rather than the closed
// AdminActivityType enum. A new module (e.g. a future admin action logged
// from a screen that doesn't exist yet) needs an entry added here to get
// its own color/icon/label — everything else (filtering, rendering)
// already works for it via the fallback case, no other code changes
// needed. This is the fix for Recent Activity "not being fully adaptive".
Color moduleColor(String? module, ColorScheme cs) {
  switch (module) {
    case 'harvest':
      return AppConstants.primaryGreen;
    case 'listings':
      return cs.primary;
    case 'orders':
      return AppConstants.buyerBlue;
    case 'prices':
      return cs.outline;
    case 'members':
      return AppConstants.primaryGreen;
    case 'crops':
      return AppConstants.warningAmber;
    case 'inventory':
      return AppConstants.warningAmber;
    case 'programs':
      return AppConstants.programPurple;
    case 'loans':
      return AppConstants.errorRed;
    case 'reports':
      return AppConstants.buyerBlue;
    case 'market_linking':
      return AppConstants.buyerBlue;
    case 'offers':
      return AppConstants.successGreen;
    case 'broadcast':
      return AppConstants.amber;
    case 'marketplace':
      return AppConstants.buyerBlue;
    case 'system':
      return cs.outline;
    case 'profile':
      return cs.outline;
    default:
      return cs.outline;
  }
}

IconData moduleIcon(String? module) {
  switch (module) {
    case 'harvest':
      return Icons.agriculture_rounded;
    case 'listings':
      return Icons.store_rounded;
    case 'orders':
      return Icons.shopping_bag_rounded;
    case 'prices':
      return Icons.sell_rounded;
    case 'members':
      return Icons.person_add_rounded;
    case 'crops':
      return Icons.eco_outlined;
    case 'inventory':
      return Icons.inventory_2_rounded;
    case 'programs':
      return Icons.star_rounded;
    case 'loans':
      return Icons.account_balance_rounded;
    case 'reports':
      return Icons.summarize_rounded;
    case 'market_linking':
      return Icons.hub_rounded;
    case 'offers':
      return Icons.handshake_rounded;
    case 'broadcast':
      return Icons.campaign_rounded;
    case 'marketplace':
      return Icons.storefront_rounded;
    case 'system':
      return Icons.settings_suggest_rounded;
    case 'profile':
      return Icons.person_rounded;
    default:
      return Icons.history_rounded;
  }
}

String moduleLabel(AppLocalizations l10n, String? module) {
  switch (module) {
    case null:
      return l10n.reportsAll;
    case 'harvest':
      return l10n.navHarvest;
    case 'listings':
      return l10n.adminNavListings;
    case 'orders':
      return l10n.statOrders;
    case 'prices':
      return l10n.buyerNavPrices;
    case 'members':
      return l10n.adminNavMembers;
    case 'crops':
      return l10n.cropMgmtTitle;
    case 'inventory':
      return l10n.adminInvManagementTitle;
    case 'programs':
      return l10n.programMgmtTitle;
    case 'loans':
      return l10n.loanItemCatalogTitle;
    case 'reports':
      return l10n.adminNavReports;
    case 'market_linking':
      return l10n.marketLinkTitle;
    case 'offers':
      return l10n.offerCoopTitle;
    case 'broadcast':
      return l10n.broadcastTitle;
    case 'marketplace':
      return l10n.navMarketplace;
    case 'system':
      return l10n.staffLogSystem;
    case 'profile':
      return l10n.adminProfileTitle;
    default:
      return module;
  }
}

// Relative-time label computed from the item's bare timestamp at display
// time (rather than a pre-baked English string from the repository) —
// same relative-time phrasing already used by admin_notifications_screen.dart.
String adminActivityTimeLabel(AppLocalizations l10n, DateTime timestamp) {
  final diff = DateTime.now().difference(timestamp);
  if (diff.inMinutes < 1) return l10n.broadcastJustNow;
  if (diff.inMinutes < 60) return l10n.buyerNotifTimeMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.buyerNotifTimeHoursAgo(diff.inHours);
  return l10n.buyerNotifTimeDaysAgo(diff.inDays);
}

class AdminActivityScreen extends StatefulWidget {
  const AdminActivityScreen({super.key});

  @override
  State<AdminActivityScreen> createState() => _AdminActivityScreenState();
}

class _AdminActivityScreenState extends State<AdminActivityScreen> {
  // admin_activity_log only — deliberately NOT AdminDashboardRepository,
  // whose fetchRecentActivity() additionally polls 6 other tables
  // (harvests, orders, listing submissions, new members, crop requests,
  // price records) to build the Dashboard's separate "what's happening"
  // preview. Those are farmer/buyer-initiated events, not admin actions,
  // and the Dashboard preview keeps that broader mix intentionally — this
  // screen (the admin's own action log) now shows admin-performed actions
  // only.
  final _repo = AdminActivityRepository();

  List<AdminActivityItem> _items = [];
  bool _isLoading = true;
  // Filtering is by nav-section category rather than the raw sourceModule —
  // the per-module chip list (listings/orders/prices/members/crops/
  // inventory/programs/loans/market_linking/offers/broadcast/profile) was
  // too many chips to scan at a glance, so chips are consolidated down to
  // the same 6 sections the bottom nav + drawer already use.
  String? _filterCategory;

  // The Manager's/Officer's own actions are fetched once (up to this many, the
  // server's per-request ceiling); chips, search and "Load More" then work on
  // that set in memory, so switching a chip never reloads the screen and the
  // chip counts are exact for everything fetched.
  static const _fetchLimit = 1000;
  static const _pageSize = 30;
  int _visibleCount = _pageSize;

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
        _visibleCount = _pageSize;
      });
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final fetched = await _repo.fetchActivity(limit: _fetchLimit);
    if (!mounted) return;
    setState(() {
      _items = fetched;
      _visibleCount = _pageSize;
      _isLoading = false;
    });
  }

  // Only the visible records change; nothing is re-fetched.
  void _onFilterTap(String? category) {
    setState(() {
      _filterCategory = category;
      _visibleCount = _pageSize;
    });
  }

  bool _inCategory(AdminActivityItem item, String? category) =>
      category == null ||
      (_categoryModules[category]?.contains(item.sourceModule) ?? false);

  // How many records sit under a chip (search does not change the numbers).
  int _countFor(String? category) =>
      _items.where((i) => _inCategory(i, category)).length;

  // Chip and search are both client-side over what was fetched.
  List<AdminActivityItem> get _filteredItems {
    final l10n = AppLocalizations.of(context);
    return _items.where((item) {
      if (!_inCategory(item, _filterCategory)) return false;
      if (_searchQuery.isEmpty) return true;
      return adminActivityDescription(
        l10n,
        item,
      ).toLowerCase().contains(_searchQuery);
    }).toList();
  }

  // Mirrors Farmer's Recent Activity _groupByDate() exactly — same Today/
  // Yesterday/named-date logic, same calendar-day (not 24h-rolling) equality.
  Map<String, List<AdminActivityItem>> _groupByDate(
    List<AdminActivityItem> items,
  ) {
    final Map<String, List<AdminActivityItem>> groups = {};
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
        label = AppLocalizations.of(context).buyerNotifTimeYesterday;
      } else {
        label = activityDateLabel(
          item.timestamp,
          AppLocalizations.of(context).localeName,
          now: now,
        );
      }
      groups.putIfAbsent(label, () => []).add(item);
    }
    return groups;
  }

  void _onItemTap(AdminActivityItem item) {
    switch (item.type) {
      case AdminActivityType.listing:
        if (item.referenceId != null) {
          context.push(AppRoutes.listingReview, extra: item.referenceId);
        }
      case AdminActivityType.loan:
        if (item.referenceId != null) {
          context.push(AppRoutes.loanDetails, extra: item.referenceId);
        }
      case AdminActivityType.member:
      case AdminActivityType.harvest:
        if (item.referenceId != null) {
          pushFarmerDetails(context, item.referenceId);
        }
      case AdminActivityType.order:
        context.push(AppRoutes.pendingApprovals);
      case AdminActivityType.price:
        context.push(AppRoutes.priceManagement);
      case AdminActivityType.inventory:
        context.push(AppRoutes.adminInventory);
      case AdminActivityType.program:
        context.push(AppRoutes.programManagement);
      case AdminActivityType.cropRequest:
        context.push(AppRoutes.cropRequestApproval);
      case AdminActivityType.logged:
        openLoggedAdminActivity(context, item);
    }
  }

  // Chips are grouped into the same 6 sections the bottom nav + drawer use
  // (Dashboard, Members, Marketplace, Loans, Reports, Profile) rather than
  // one chip per raw sourceModule — each category maps to every module
  // whose activity belongs under that section. "Reports" has no
  // sourceModule of its own today (nothing logs an activity item for
  // report generation), so it's included as a chip but currently always
  // shows empty — kept for parity with the nav rather than omitted.
  // 'harvest' removed from 'members' — harvests are farmer-performed, never
  // an admin action, so that module value never appears in
  // admin_activity_log (only ever the 6-source Dashboard preview feed).
  static const _categoryModules = {
    'dashboard': ['prices', 'crops', 'inventory', 'programs', 'broadcast'],
    'members': ['members'],
    'marketplace': ['listings', 'orders', 'market_linking', 'offers', 'marketplace'],
    'loans': ['loans'],
    'reports': ['reports'],
    'profile': ['profile'],
  };
  static const _filterCategories = [
    null,
    'dashboard',
    'members',
    'marketplace',
    'loans',
    'reports',
    'profile',
  ];

  // Manager and Officer both have every tab, so every chip is shown.
  List<String?> get _visibleCategories => _filterCategories;

  String _categoryLabel(AppLocalizations l10n, String? category) {
    switch (category) {
      case null:
        return l10n.reportsAll;
      case 'dashboard':
        return l10n.adminNavDashboard;
      case 'members':
        return l10n.adminNavMembers;
      case 'marketplace':
        return l10n.navMarketplace;
      case 'loans':
        return l10n.adminNavLoans;
      case 'reports':
        return l10n.adminNavReports;
      case 'profile':
        return l10n.recentActivityAccountChip;
      default:
        return category;
    }
  }

  // One Admin row: module-coloured icon and badge, navigable rows get a
  // chevron and tap through. Shared card look, so it matches Farmer and Buyer.
  RecentActivityCard _adminCard(
    AppLocalizations l10n,
    ColorScheme cs,
    AdminActivityItem item,
  ) {
    // Every record opens something: its own record, or the screen of its module.
    final tappable =
        membersAccessAllowed ||
        !(item.type == AdminActivityType.member ||
            item.type == AdminActivityType.harvest ||
            item.sourceModule == 'members');

    return RecentActivityCard(
      icon: moduleIcon(item.sourceModule),
      accentColor: moduleColor(item.sourceModule, cs),
      title: adminActivityDescription(l10n, item),
      subtitle: item.adminName ?? '',
      timestamp: item.timestamp,
      statusLabel: moduleLabel(l10n, item.sourceModule),
      onTap: tappable ? () => _onItemTap(item) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final filtered = _filteredItems;
    final visible = filtered.take(_visibleCount).toList();
    final hasMore = _visibleCount < filtered.length;
    final grouped = _groupByDate(visible);
    final dateKeys = grouped.keys.toList();
    final hasSearch = _searchQuery.isNotEmpty || _filterCategory != null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.adminActivityTitle,
            onBack: () => context.pop(),
          ),
          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : RefreshIndicator(
                    color: Theme.of(context).colorScheme.primary,
                    onRefresh: _load,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                            child: RecentActivitySearchBar(
                              controller: _searchCtrl,
                              hint: l10n.adminActivitySearchHint,
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                            child: RecentActivityFilterChips<String?>(
                              options: [
                                for (final category in _visibleCategories)
                                  RecentActivityFilterOption<String?>(
                                    value: category,
                                    label: _categoryLabel(l10n, category),
                                    count: _countFor(category),
                                  ),
                              ],
                              active: _filterCategory,
                              onSelected: _onFilterTap,
                            ),
                          ),
                        ),
                        if (filtered.isEmpty)
                          SliverFillRemaining(
                            child: RecentActivityEmptyState(
                              hasSearch: hasSearch,
                              emptyTitle: l10n.adminActivityNoActivityYet,
                              emptyHint: l10n.activityEmptyHint,
                              noMatchTitle: l10n.activityNoMatchTitle,
                              noMatchHint: l10n.activityNoMatchHint,
                            ),
                          )
                        else ...[
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final label = dateKeys[index];
                                return RecentActivityDateGroup(
                                  label: label,
                                  cards: [
                                    for (final item in grouped[label]!)
                                      _adminCard(l10n, cs, item),
                                  ],
                                );
                              }, childCount: dateKeys.length),
                            ),
                          ),
                          if (hasMore)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Center(
                                  child: GestureDetector(
                                    onTap: () => setState(
                                      () => _visibleCount += _pageSize,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: sagana.cardBackground,
                                        borderRadius: BorderRadius.circular(
                                          AppConstants.radiusFull,
                                        ),
                                        border: Border.all(
                                          color: cs.outline.withValues(
                                            alpha: 0.20,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        l10n.adminActivityLoadMore,
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: cs.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 40)),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
