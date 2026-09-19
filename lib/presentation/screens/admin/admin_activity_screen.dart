import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_dashboard_model.dart';
import '../../../data/repositories/admin_dashboard_repository.dart';
import '../../../routes/app_routes.dart';

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
      return l10n.adminActivityNewHarvest(name, item.quantityKg ?? '', item.cropName ?? '');
    case AdminActivityDescKind.listingApproved:
      return l10n.adminActivityListingApproved(item.cropName ?? '', name);
    case AdminActivityDescKind.listingSubmitted:
      return l10n.adminActivityListingSubmitted(name, item.cropName ?? '');
    case AdminActivityDescKind.orderPlaced:
      return l10n.adminActivityOrderPlaced(item.amount ?? '');
    case AdminActivityDescKind.priceUpdated:
      return l10n.adminActivityPriceUpdated(item.cropName ?? '', item.amount ?? '');
    case AdminActivityDescKind.newMember:
      return l10n.adminActivityNewMember(item.name ?? l10n.adminActivityNewMemberFallback);
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
    case 'harvest':        return AppConstants.primaryGreen;
    case 'listings':       return cs.primary;
    case 'orders':         return AppConstants.buyerBlue;
    case 'prices':         return cs.outline;
    case 'members':        return AppConstants.primaryGreen;
    case 'crops':          return AppConstants.warningAmber;
    case 'inventory':      return AppConstants.warningAmber;
    case 'programs':       return AppConstants.programPurple;
    case 'loans':          return AppConstants.errorRed;
    case 'market_linking': return AppConstants.buyerBlue;
    case 'offers':         return AppConstants.successGreen;
    case 'broadcast':      return AppConstants.amber;
    case 'profile':        return cs.outline;
    default:                return cs.outline;
  }
}

IconData moduleIcon(String? module) {
  switch (module) {
    case 'harvest':        return Icons.agriculture_rounded;
    case 'listings':       return Icons.store_rounded;
    case 'orders':         return Icons.shopping_bag_rounded;
    case 'prices':         return Icons.sell_rounded;
    case 'members':        return Icons.person_add_rounded;
    case 'crops':          return Icons.eco_outlined;
    case 'inventory':      return Icons.inventory_2_rounded;
    case 'programs':       return Icons.star_rounded;
    case 'loans':          return Icons.account_balance_rounded;
    case 'market_linking': return Icons.hub_rounded;
    case 'offers':         return Icons.handshake_rounded;
    case 'broadcast':      return Icons.campaign_rounded;
    case 'profile':        return Icons.person_rounded;
    default:                return Icons.history_rounded;
  }
}

String moduleLabel(AppLocalizations l10n, String? module) {
  switch (module) {
    case null:              return l10n.reportsAll;
    case 'harvest':         return l10n.navHarvest;
    case 'listings':        return l10n.adminNavListings;
    case 'orders':          return l10n.statOrders;
    case 'prices':          return l10n.buyerNavPrices;
    case 'members':         return l10n.adminNavMembers;
    case 'crops':           return l10n.cropMgmtTitle;
    case 'inventory':       return l10n.adminInvManagementTitle;
    case 'programs':        return l10n.programMgmtTitle;
    case 'loans':           return l10n.loanItemCatalogTitle;
    case 'market_linking':  return l10n.marketLinkTitle;
    case 'offers':          return l10n.offerCoopTitle;
    case 'broadcast':       return l10n.broadcastTitle;
    case 'profile':         return l10n.adminProfileTitle;
    default:                return module;
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
  final _repo = AdminDashboardRepository();

  List<AdminActivityItem> _items = [];
  bool _isLoading = true;
  // Filtering is by nav-section category rather than the raw sourceModule —
  // the per-module chip list (harvest/listings/orders/prices/members/crops/
  // inventory/programs/loans/market_linking/offers/broadcast/profile) was
  // too many chips to scan at a glance, so chips are consolidated down to
  // the same 6 sections the bottom nav + drawer already use.
  String? _filterCategory;
  int _page = 0;
  static const _pageSize = 30;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _loadPage(reset: true);
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (reset) {
      setState(() { _page = 0; _items = []; _hasMore = true; _isLoading = true; });
    }
    final fetched = await _repo.fetchRecentActivity(
      limit: _pageSize,
      offset: _page * _pageSize,
      moduleFilters: _filterCategory == null ? null : _categoryModules[_filterCategory],
    );
    if (!mounted) return;
    setState(() {
      _items.addAll(fetched);
      _hasMore = fetched.length == _pageSize;
      _isLoading = false;
    });
  }

  void _onFilterTap(String? category) {
    setState(() => _filterCategory = category);
    _loadPage(reset: true);
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
          context.push(AppRoutes.farmerDetails, extra: item.referenceId);
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
        switch (item.sourceModule) {
          case 'inventory': context.push(AppRoutes.adminInventory);
          case 'crops':     context.push(AppRoutes.cropManagement);
          case 'programs':  context.push(AppRoutes.programManagement);
          case 'loans':     context.push(AppRoutes.loanItemManagement);
          case 'prices':    context.push(AppRoutes.priceManagement);
          case 'market_linking': context.push(AppRoutes.marketLinking);
          case 'offers':    context.push(AppRoutes.offerToCooperative);
          case 'broadcast': context.push(AppRoutes.broadcastHistory);
          case 'profile':   context.push(AppRoutes.adminProfile);
          // 'members' and other future modules with no known destination
          // simply aren't navigable — same as any item with no referenceId.
        }
    }
  }

  // Chips are grouped into the same 6 sections the bottom nav + drawer use
  // (Dashboard, Members, Marketplace, Loans, Reports, Profile) rather than
  // one chip per raw sourceModule — each category maps to every module
  // whose activity belongs under that section. "Reports" has no
  // sourceModule of its own today (nothing logs an activity item for
  // report generation), so it's included as a chip but currently always
  // shows empty — kept for parity with the nav rather than omitted.
  static const _categoryModules = {
    'dashboard': ['prices', 'crops', 'inventory', 'programs', 'broadcast'],
    'members': ['harvest', 'members'],
    'marketplace': ['listings', 'orders', 'market_linking', 'offers'],
    'loans': ['loans'],
    'reports': <String>[],
    'profile': ['profile'],
  };
  static const _filterCategories = [null, 'dashboard', 'members', 'marketplace', 'loans', 'reports', 'profile'];

  String _categoryLabel(AppLocalizations l10n, String? category) {
    switch (category) {
      case null:          return l10n.reportsAll;
      case 'dashboard':   return l10n.adminNavDashboard;
      case 'members':     return l10n.adminNavMembers;
      case 'marketplace': return l10n.navMarketplace;
      case 'loans':       return l10n.adminNavLoans;
      case 'reports':     return l10n.adminNavReports;
      case 'profile':     return l10n.adminProfileTitle;
      default:            return category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Glass top bar
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 64 + MediaQuery.of(context).padding.top,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                  left: 8, right: 20,
                ),
                decoration: BoxDecoration(
                  color: sagana.glassBackground,
                  border: Border(bottom: BorderSide(color: sagana.glassBorder)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                      onPressed: () => context.pop(),
                    ),
                    Text(
                      l10n.adminActivityTitle,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Filter chips
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: _filterCategories.map((category) {
                  final isSelected = _filterCategory == category;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _onFilterTap(category),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary
                              : sagana.cardBackground,
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull),
                          border: Border.all(
                            color: isSelected
                                ? cs.primary
                                : cs.outline.withValues(alpha: 0.20),
                          ),
                        ),
                        child: Text(
                          _categoryLabel(l10n, category),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppConstants.primaryGreen, strokeWidth: 2))
                : RefreshIndicator(
                    color: AppConstants.primaryGreen,
                    onRefresh: () => _loadPage(reset: true),
                    child: _items.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 120),
                              Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.history_rounded,
                                        size: 48,
                                        color: cs.onSurfaceVariant),
                                    const SizedBox(height: 12),
                                    Text(
                                      l10n.adminActivityNoActivityYet,
                                      style: GoogleFonts.inter(
                                          fontSize: 14,
                                          color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                                20, 8, 20, 40),
                            itemCount:
                                _items.length + (_hasMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i == _items.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  child: Center(
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() => _page++);
                                        _loadPage();
                                      },
                                      child: Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 10),
                                        decoration: BoxDecoration(
                                          color: sagana.cardBackground,
                                          borderRadius:
                                              BorderRadius.circular(
                                                  AppConstants.radiusFull),
                                          border: Border.all(
                                            color: cs.outline
                                                .withValues(alpha: 0.20),
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
                                );
                              }

                              final item = _items[i];
                              final color = moduleColor(item.sourceModule, cs);
                              final icon = moduleIcon(item.sourceModule);
                              final isNavigable =
                                  item.referenceId != null ||
                                      item.type ==
                                          AdminActivityType.order ||
                                      item.type ==
                                          AdminActivityType.price ||
                                      (item.type == AdminActivityType.logged &&
                                          item.sourceModule != 'members');

                              return Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 10),
                                child: GestureDetector(
                                  onTap: isNavigable
                                      ? () => _onItemTap(item)
                                      : null,
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: sagana.cardBackground,
                                      borderRadius:
                                          BorderRadius.circular(
                                              AppConstants.radiusLg),
                                      border: Border.all(
                                        color: cs.outline
                                            .withValues(alpha: 0.10),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.03),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: color.withValues(
                                                alpha: 0.12),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(icon,
                                              color: color, size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .start,
                                            children: [
                                              Text(
                                                adminActivityDescription(l10n, item),
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  color: cs.onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  // Flexible + ellipsis: some
                                                  // translated category
                                                  // labels ("Mga Kahilingan
                                                  // sa Pananim" for Crop
                                                  // Requests) run far longer
                                                  // than their English
                                                  // source, and this badge
                                                  // previously had no width
                                                  // limit of its own next to
                                                  // the time label sharing
                                                  // this Row.
                                                  Flexible(
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                      decoration:
                                                          BoxDecoration(
                                                        color: color
                                                            .withValues(
                                                                alpha: 0.10),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                          AppConstants
                                                              .radiusFull,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        moduleLabel(
                                                            l10n, item.sourceModule),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: color,
                                                          letterSpacing: 0.3,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                      width: 6),
                                                  Flexible(
                                                    child: Text(
                                                      item.adminName != null
                                                          ? '${adminActivityTimeLabel(l10n, item.timestamp)} · ${item.adminName}'
                                                          : adminActivityTimeLabel(l10n, item.timestamp),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style:
                                                          GoogleFonts.inter(
                                                        fontSize: 11,
                                                        color: cs
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isNavigable)
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            size: 18,
                                            color: cs.onSurfaceVariant,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}