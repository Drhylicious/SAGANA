import 'dart:async';
import 'dart:ui';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/animations/staggered_entrance.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/dashboard_summary_model.dart';
import '../../../data/models/farmer_market_rate_model.dart';
import '../../../data/models/loan_model.dart';
import '../../../data/models/marketplace_listing_model.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../data/repositories/farmer_market_rates_repository.dart';
import '../../../data/repositories/loan_repository.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/profile_state_service.dart';
import '../../../data/services/sync_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';

class FarmerDashboardScreen extends StatefulWidget {
  const FarmerDashboardScreen({super.key});

  @override
  State<FarmerDashboardScreen> createState() => _FarmerDashboardScreenState();
}

class _FarmerDashboardScreenState extends State<FarmerDashboardScreen> {
  final _dashRepo = DashboardRepository();
  final _loanRepo = LoanRepository();
  final _listingRepo = ListingRepository();
  final _notifRepo = NotificationRepository();
  final _marketRatesRepo = FarmerMarketRatesRepository();
  final _profileState = FarmerProfileStateService.instance;

  DashboardSummaryModel _summary = DashboardSummaryModel.empty;
  List<FarmerMarketRateModel> _marketRates = [];
  List<ActivityItem> _activity = [];
  List<PriorityItem> _priorityItems = [];
  int _unreadCount = 0;
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    AppEventService.instance.addListener(_onHarvestRecorded);
    _profileState.addListener(_onProfileStateChanged);
    _loadData();
    _listenConnectivity();
  }

  @override
  void dispose() {
    AppEventService.instance.removeListener(_onHarvestRecorded);
    _profileState.removeListener(_onProfileStateChanged);
    super.dispose();
  }

  void _onHarvestRecorded() {
    if (mounted) _loadData();
  }

  void _onProfileStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  void _listenConnectivity() {
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _isOnline = ConnectivityService.instance.isOnline;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _dashRepo.fetchSummary(),
        _marketRatesRepo.fetchMarketRates(limit: 10),
        _dashRepo.fetchRecentActivity(),
        _loanRepo.fetchLoans(),
        _listingRepo.fetchListings(),
        _notifRepo.fetchNotifications(),
        _notifRepo.fetchUnreadCount(),
      ]);
      await _profileState.refresh();
      if (!mounted) return;

      final summary = results[0] as DashboardSummaryModel;
      final fullActivity = results[2] as List<ActivityItem>;
      final loans = results[3] as List<LoanModel>;
      final listings = results[4] as List<MarketplaceListingModel>;
      final notifications = results[5] as List<NotificationModel>;

      setState(() {
        _summary = summary;
        _marketRates = results[1] as List<FarmerMarketRateModel>;
        // Loan-due entries now live in the Priority section, not here.
        _activity =
            fullActivity.where((a) => a.type != ActivityType.loan).toList();
        _priorityItems = _buildPriorityItems(
          loans: loans,
          listings: listings,
          unsyncedCount: summary.unsyncedCount,
          notifications: notifications,
        );
        _unreadCount = results[6] as int;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Ranked by urgency: overdue loan → listing needs changes →
  /// loan due soon → unsynced records → recent cooperative announcement.
  List<PriorityItem> _buildPriorityItems({
    required List<LoanModel> loans,
    required List<MarketplaceListingModel> listings,
    required int unsyncedCount,
    required List<NotificationModel> notifications,
  }) {
    final items = <PriorityItem>[];
    final now = DateTime.now();
    final dueSoonCutoff = now.add(const Duration(days: 7));

    for (final loan in loans.where((l) => l.isOverdue)) {
      items.add(PriorityItem(
        title: 'Loan payment overdue',
        subtitle:
            '${loan.referenceNo} • ₱${loan.monthlyPayment.toStringAsFixed(0)} due',
        icon: Icons.warning_amber_rounded,
        severity: PrioritySeverity.critical,
        onTap: () => context.pushRoute(AppRoutes.myLoans),
      ));
    }

    for (final listing in listings.where((l) => l.status == 'changes_required')) {
      items.add(PriorityItem(
        title: '${listing.cropName} listing needs changes',
        subtitle: 'Cooperative requested an update before it can be listed',
        icon: Icons.storefront_outlined,
        severity: PrioritySeverity.warning,
        onTap: () => context.goTab(AppRoutes.myListings),
      ));
    }

    for (final loan in loans.where(
      (l) => l.isActive && !l.isOverdue && l.nextPaymentDate != null,
    )) {
      if (loan.nextPaymentDate!.isBefore(dueSoonCutoff)) {
        items.add(PriorityItem(
          title: 'Loan payment due soon',
          subtitle:
              '${loan.referenceNo} • ₱${loan.monthlyPayment.toStringAsFixed(0)} by ${DateFormat('MMM d').format(loan.nextPaymentDate!)}',
          icon: Icons.event_repeat_rounded,
          severity: PrioritySeverity.warning,
          onTap: () => context.pushRoute(AppRoutes.myLoans),
        ));
      }
    }

    if (unsyncedCount > 0) {
      items.add(PriorityItem(
        title: '$unsyncedCount harvest record${unsyncedCount == 1 ? '' : 's'} waiting to sync',
        subtitle: 'Tap to sync now',
        icon: Icons.sync_rounded,
        severity: PrioritySeverity.warning,
        onTap: _handleSync,
      ));
    }

    final recentBroadcast = notifications.where(
      (n) =>
          n.type == NotificationType.system &&
          n.isUnread &&
          now.difference(n.createdAt).inDays <= 5,
    ).firstOrNull;
    if (recentBroadcast != null) {
      items.add(PriorityItem(
        title: recentBroadcast.title,
        subtitle: recentBroadcast.body,
        icon: Icons.campaign_outlined,
        severity: PrioritySeverity.info,
        onTap: () => context.pushRoute(AppRoutes.farmerNotifications),
      ));
    }

    return items;
  }

  Future<void> _handleSync() async {
    setState(() => _isSyncing = true);
    await SyncService.syncPending();
    await _loadData();
    if (mounted) setState(() => _isSyncing = false);
  }

  String _greeting(AppLocalizations l10n) {
    final hour = DateTime.now().hour;
    if (hour < 12) return l10n.greetingMorning;
    if (hour < 18) return l10n.greetingAfternoon;
    return l10n.greetingEvening;
  }

  String _firstName(AppLocalizations l10n) {
    final name = _profileState.fullName ?? l10n.defaultFarmerName;
    return name.split(' ').first;
  }

  String get _formattedDate {
    return DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              if (!_isOnline) const OfflineBanner(),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: CustomScrollView(
                    slivers: [
                      const SliverToBoxAdapter(child: SizedBox(height: 72)),

                      // Welcome
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: StaggeredEntrance(
                            index: 0,
                            child: _WelcomeSection(
                              greeting: _greeting(l10n),
                              firstName: _firstName(l10n),
                              date: _formattedDate,
                              isLoading: _isLoading,
                            ),
                          ),
                        ),
                      ),

                      // Priority section (new)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: StaggeredEntrance(
                            index: 1,
                            child: _isLoading
                                ? const _Shimmer(width: double.infinity, height: 72)
                                : PriorityCard(
                                    items: _priorityItems,
                                    allClearTitle: l10n.dashboardAllClearTitle,
                                    allClearMessage: l10n.dashboardAllClearMessage,
                                  ),
                          ),
                        ),
                      ),

                      // KPI cards — unchanged, deliberately left open pending
                      // Harvest/Marketplace workflow analysis.
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: _KpiSection(
                            summary: _summary,
                            isLoading: _isLoading,
                            isSyncing: _isSyncing,
                            onSync: _handleSync,
                          ),
                        ),
                      ),

                      // Market Rates carousel — replaces the ticker
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: _MarketRatesCarousel(
                            rates: _marketRates,
                            isLoading: _isLoading,
                            onViewMarket: () =>
                                context.pushRoute(AppRoutes.viewMarket),
                            onTapRate: (rate) => context.pushRoute(
                              AppRoutes.marketRateDetails,
                              extra: rate,
                            ),
                          ),
                        ),
                      ),

                      // Quick Actions (new)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                          child: StaggeredEntrance(
                            index: 2,
                            child: _QuickActionsSection(l10n: l10n),
                          ),
                        ),
                      ),

                      // Recent activity — loan-due entries excluded (now in Priority)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                          child: _RecentActivitySection(
                            items: _activity,
                            isLoading: _isLoading,
                            onViewAll: () => context.pushRoute(
                              AppRoutes.farmerRecentActivity,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Top bar — now with unread badge
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: l10n.navHome,
              unreadCount: _unreadCount,
              hideProfileAvatar: true,
              onProfileTap: () => context.goTab(AppRoutes.farmerProfile),
              onNotificationTap: () =>
                  context.pushRoute(AppRoutes.farmerNotifications),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Actions
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionsSection extends StatelessWidget {
  final AppLocalizations l10n;
  const _QuickActionsSection({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.dashboardQuickActions,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppConstants.charcoal,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            QuickActionButton(
              icon: Icons.add_circle_outline_rounded,
              label: l10n.quickActionRecordHarvest,
              onTap: () => context.pushRoute(AppRoutes.selectCropForHarvest),
            ),
            const SizedBox(width: 10),
            QuickActionButton(
              icon: Icons.storefront_outlined,
              label: l10n.quickActionCreateListing,
              onTap: () => context.pushRoute(AppRoutes.createListing),
            ),
            const SizedBox(width: 10),
            QuickActionButton(
              icon: Icons.trending_up_rounded,
              label: l10n.quickActionCheckPrices,
              onTap: () => context.goTab(AppRoutes.farmerAnalytics),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Welcome Section
// ─────────────────────────────────────────────────────────────────────────────

class _WelcomeSection extends StatelessWidget {
  final String greeting;
  final String firstName;
  final String date;
  final bool isLoading;

  const _WelcomeSection({
    required this.greeting,
    required this.firstName,
    required this.date,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        isLoading
            ? const _Shimmer(width: 200, height: 28)
            : Text(
                '$greeting, $firstName!',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.charcoal,
                  letterSpacing: -0.3,
                ),
              ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 14,
              color: AppConstants.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              date,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI Section
// ─────────────────────────────────────────────────────────────────────────────

class _KpiSection extends StatelessWidget {
  final DashboardSummaryModel summary;
  final bool isLoading;
  final bool isSyncing;
  final VoidCallback onSync;

  const _KpiSection({
    required this.summary,
    required this.isLoading,
    required this.isSyncing,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _YieldCard(summary: summary, isLoading: isLoading),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _EarningsCard(summary: summary, isLoading: isLoading),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SyncCard(
          summary: summary,
          isLoading: isLoading,
          isSyncing: isSyncing,
          onSync: onSync,
        ),
      ],
    );
  }
}

class _YieldCard extends StatelessWidget {
  final DashboardSummaryModel summary;
  final bool isLoading;

  const _YieldCard({required this.summary, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Yield',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          isLoading
              ? const _Shimmer(width: 80, height: 24)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _formatNumber(summary.totalYieldKg),
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.charcoal,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'kg',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppConstants.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                summary.yieldTrendUp
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                size: 16,
                color: summary.yieldTrendUp
                    ? AppConstants.successGreen
                    : AppConstants.errorRed,
              ),
              const SizedBox(width: 4),
              Text(
                '${summary.yieldChangePercent.abs().toStringAsFixed(0)}% vs last month',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: summary.yieldTrendUp
                      ? AppConstants.successGreen
                      : AppConstants.errorRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatNumber(double n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1)}k';
    }
    return n.toStringAsFixed(0);
  }
}

class _EarningsCard extends StatelessWidget {
  final DashboardSummaryModel summary;
  final bool isLoading;

  const _EarningsCard({required this.summary, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  'Total Earnings',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppConstants.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppConstants.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Goal ${summary.earningsGoalPercent}%',
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          isLoading
              ? const _Shimmer(width: 90, height: 24)
              : Text(
                  '₱${_formatCurrency(summary.totalEarnings)}',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.secondaryContainer,
                  ),
                ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: summary.earningsProgressPercent,
              minHeight: 6,
              backgroundColor: AppConstants.amber.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppConstants.secondaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₱${_formatCurrency(summary.totalEarnings)} / ₱${_formatCurrency(summary.earningsGoal)}',
            style: GoogleFonts.inter(
              fontSize: 9,
              color: AppConstants.onSurfaceVariant,
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(1)}k';
    }
    return v.toStringAsFixed(0);
  }
}

class _SyncCard extends StatelessWidget {
  final DashboardSummaryModel summary;
  final bool isLoading;
  final bool isSyncing;
  final VoidCallback onSync;

  const _SyncCard({
    required this.summary,
    required this.isLoading,
    required this.isSyncing,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnsynced = summary.unsyncedCount > 0;
    return GlassCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unsynced Records',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppConstants.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    isLoading
                        ? const _Shimmer(width: 60, height: 20)
                        : Flexible(
                            child: Text(
                              '${summary.unsyncedCount} Item${summary.unsyncedCount != 1 ? 's' : ''}',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppConstants.charcoal,
                              ),
                            ),
                          ),
                    const SizedBox(width: 8),
                    if (hasUnsynced)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.errorContainer.withValues(alpha: 0.70),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Requires Sync',
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: isSyncing ? null : onSync,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppConstants.primaryContainer,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Row(
                children: [
                  isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppConstants.onPrimaryContainer,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.sync_rounded,
                          size: 16,
                          color: AppConstants.onPrimaryContainer,
                        ),
                  const SizedBox(width: 6),
                  Text(
                    'Sync Now',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppConstants.onPrimaryContainer,
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
// Market Rates Carousel
// ─────────────────────────────────────────────────────────────────────────────

class _MarketRatesCarousel extends StatelessWidget {
  final List<FarmerMarketRateModel> rates;
  final bool isLoading;
  final VoidCallback onViewMarket;
  final ValueChanged<FarmerMarketRateModel> onTapRate;

  const _MarketRatesCarousel({
    required this.rates,
    required this.isLoading,
    required this.onViewMarket,
    required this.onTapRate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Market Rates',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppConstants.charcoal,
              ),
            ),
            GestureDetector(
              onTap: onViewMarket,
              child: Text(
                'View Market',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.primaryGreen,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (isLoading)
          const _Shimmer(width: double.infinity, height: 132)
        else if (rates.isEmpty)
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.storefront_outlined,
                    size: 16, color: AppConstants.outline),
                const SizedBox(width: 8),
                Text(
                  'No market prices recorded yet',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppConstants.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 132,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: rates.length,
              itemBuilder: (context, index) {
                // Deliberately sized so the next card visibly peeks at the
                // screen edge — the scrollability affordance the old ticker
                // never had.
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == rates.length - 1 ? 0 : 10,
                  ),
                  child: _MarketRateCard(
                    rate: rates[index],
                    onTap: () => onTapRate(rates[index]),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _MarketRateCard extends StatelessWidget {
  final FarmerMarketRateModel rate;
  final VoidCallback onTap;

  const _MarketRateCard({required this.rate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = MarketTypeDisplay.color(context, rate.priceType);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 168,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF455A64).withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                MarketTypeDisplay.label(rate.priceType),
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              rate.cropName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppConstants.charcoal,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              rate.formattedPrice,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppConstants.primaryGreen,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Updated ${AppUtils.formatRelativeTime(rate.recordedAt)}',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent Activity
// ─────────────────────────────────────────────────────────────────────────────

class _RecentActivitySection extends StatelessWidget {
  final List<ActivityItem> items;
  final bool isLoading;
  final VoidCallback onViewAll;

  const _RecentActivitySection({
    required this.items,
    required this.isLoading,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Activity',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppConstants.charcoal,
              ),
            ),
            GestureDetector(
              onTap: onViewAll,
              child: Text(
                'View All',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.primaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (isLoading)
          GlassCard(
            child: Column(
              children: List.generate(
                3,
                (_) => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: _Shimmer(width: double.infinity, height: 48),
                ),
              ),
            ),
          )
        else if (items.isEmpty)
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const Icon(
                    Icons.inbox_outlined,
                    size: 40,
                    color: AppConstants.outline,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No recent activity',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppConstants.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.30),
                  ),
                ),
                child: Column(
                  children: items
                      .asMap()
                      .entries
                      .map(
                        (e) => Column(
                          children: [
                            _ActivityTile(item: e.value),
                            if (e.key < items.length - 1)
                              Divider(
                                height: 1,
                                color: AppConstants.outline.withValues(
                                  alpha: 0.08,
                                ),
                              ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final ActivityItem item;
  const _ActivityTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _ActivityIcon(type: item.type, isAlert: item.isAlert),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppConstants.charcoal,
                  ),
                ),
                Text(
                  item.subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: item.isAlert
                        ? AppConstants.errorRed
                        : AppConstants.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (item.valueLabel != null)
                Text(
                  item.valueLabel!,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: item.isAlert
                        ? AppConstants.errorRed
                        : item.type == ActivityType.order
                        ? AppConstants.primaryGreen
                        : AppConstants.charcoal,
                  ),
                ),
              if (item.statusLabel != null)
                Text(
                  item.statusLabel!,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: item.isAlert
                        ? AppConstants.errorRed.withValues(alpha: 0.70)
                        : AppConstants.successGreen,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityIcon extends StatelessWidget {
  final ActivityType type;
  final bool isAlert;

  const _ActivityIcon({required this.type, required this.isAlert});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color bg;
    Color fg;

    if (isAlert && type == ActivityType.loan) {
      icon = Icons.event_repeat_rounded;
      bg = AppConstants.errorRed.withValues(alpha: 0.12);
      fg = AppConstants.errorRed;
    } else {
      switch (type) {
        case ActivityType.harvest:
          icon = Icons.eco_rounded;
          bg = AppConstants.primaryGreen.withValues(alpha: 0.10);
          fg = AppConstants.primaryGreen;
          break;
        case ActivityType.order:
          icon = Icons.shopping_cart_outlined;
          bg = AppConstants.primaryGreen.withValues(alpha: 0.10);
          fg = AppConstants.primaryGreen;
          break;
        case ActivityType.listing:
          icon = Icons.storefront_outlined;
          bg = AppConstants.successGreen.withValues(alpha: 0.10);
          fg = AppConstants.successGreen;
          break;
        case ActivityType.loan:
          icon = Icons.account_balance_wallet_outlined;
          bg = AppConstants.warningAmber.withValues(alpha: 0.10);
          fg = AppConstants.warningAmber;
          break;
        case ActivityType.cropRequest:
          icon = Icons.local_florist_outlined;
          bg = (isAlert ? AppConstants.errorRed : AppConstants.primaryGreen)
              .withValues(alpha: 0.10);
          fg = isAlert ? AppConstants.errorRed : AppConstants.primaryGreen;
          break;
      }
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 22, color: fg),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _Shimmer extends StatefulWidget {
  final double width;
  final double height;

  const _Shimmer({required this.width, required this.height});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _animation = Tween<double>(
      begin: -1,
      end: 2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: [
              (_animation.value - 1).clamp(0.0, 1.0),
              _animation.value.clamp(0.0, 1.0),
              (_animation.value + 1).clamp(0.0, 1.0),
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
  }
}