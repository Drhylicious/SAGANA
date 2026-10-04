import 'dart:async';
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
import '../../widgets/app_navigation_drawer.dart';
import '../../widgets/shared_widgets.dart';

// Shared compact-number formatter — kg and currency figures on Home all
// use the same "1.2k" shorthand above 1000; kept as one definition rather
// than each card computing its own identical copy.
String _formatCompact(double v) {
  if (v >= 1000) {
    return '${(v / 1000).toStringAsFixed(1)}k';
  }
  return v.toStringAsFixed(0);
}

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
        _dashRepo.fetchActivity(limit: 5),
        _loanRepo.fetchLoans(),
        _listingRepo.fetchListings(),
        _notifRepo.fetchNotifications(),
        _notifRepo.fetchUnreadCount(),
      ]);
      await _profileState.refresh();
      if (!mounted) return;
      // AppLocalizations.of(context) must not be called before this
      // widget's initState()/first build completes — _loadData() is
      // invoked directly from initState(), so this lookup has to wait
      // until after the first async gap above, not sit at the top of
      // this method (that crashed with "dependOnInheritedWidgetOfExactType
      // ... called before initState() completed").
      final l10n = AppLocalizations.of(context);

      final summary = results[0] as DashboardSummaryModel;
      final activity = results[2] as List<ActivityItem>;
      final loans = results[3] as List<LoanModel>;
      final listings = results[4] as List<MarketplaceListingModel>;
      final notifications = results[5] as List<NotificationModel>;

      setState(() {
        _summary = summary;
        _marketRates = results[1] as List<FarmerMarketRateModel>;
        // Loan-due entries live in the Priority section, not here — now
        // excluded server-side (before the 5-item cap is applied) instead
        // of filtered out of an already-capped list, which previously
        // could silently show fewer than 5 items on Home.
        _activity = activity;
        _priorityItems = _buildPriorityItems(
          l10n: l10n,
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

  /// Calendar-day difference to [target], ignoring time-of-day on both
  /// sides — a plain `.difference(DateTime.now()).inDays` would truncate
  /// toward zero and under-count by one whenever "now" has already moved
  /// past midnight (e.g. a payment 5 calendar-days away, checked at 3pm,
  /// is really 4.x Duration-days away and would misreport as "in 4 days").
  int _daysUntil(DateTime target) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(target.year, target.month, target.day);
    return targetDay.difference(today).inDays;
  }

  /// Ranked by urgency: overdue loan → listing needs changes →
  /// loan due soon → unsynced records → recent cooperative announcement.
  List<PriorityItem> _buildPriorityItems({
    required AppLocalizations l10n,
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
        title: l10n.farmerDashLoanOverdueTitle,
        subtitle: l10n.farmerDashLoanOverdueSubtitle(
            loan.referenceNo, loan.monthlyPayment.toStringAsFixed(0)),
        icon: Icons.warning_amber_rounded,
        severity: PrioritySeverity.critical,
        onTap: () => context.pushRoute(AppRoutes.myLoans),
      ));
    }

    for (final loan in loans.where(
      (l) => l.isActive && !l.isOverdue && l.nextPaymentDate != null,
    )) {
      if (loan.nextPaymentDate!.isBefore(dueSoonCutoff)) {
        final daysUntil = _daysUntil(loan.nextPaymentDate!);
        final title = daysUntil <= 0
            ? l10n.farmerDashLoanDueTodayTitle
            : daysUntil == 1
                ? l10n.farmerDashLoanDueInDaysTitleOne(daysUntil)
                : l10n.farmerDashLoanDueInDaysTitleOther(daysUntil);
        items.add(PriorityItem(
          title: title,
          subtitle: l10n.farmerDashLoanDueSoonSubtitle(
              loan.referenceNo,
              loan.monthlyPayment.toStringAsFixed(0),
              DateFormat('MMM d', l10n.localeName).format(loan.nextPaymentDate!)),
          icon: Icons.event_repeat_rounded,
          severity: PrioritySeverity.warning,
          onTap: () => context.pushRoute(AppRoutes.myLoans),
        ));
      }
    }

    if (unsyncedCount > 0) {
      items.add(PriorityItem(
        title: unsyncedCount == 1
            ? l10n.farmerDashUnsyncedCountOne(unsyncedCount)
            : l10n.farmerDashUnsyncedCountOther(unsyncedCount),
        subtitle: l10n.farmerDashTapToSync,
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
    // Captured before syncPending() runs — a tap with nothing queued isn't
    // a meaningful action to record in Recent Activity.
    final hadPending = _summary.unsyncedCount > 0;
    await SyncService.syncPending();
    if (hadPending) {
      await _dashRepo.logSyncCompleted();
    }
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
    return DateFormat('EEEE, MMMM d, yyyy', AppLocalizations.of(context).localeName)
        .format(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      drawer: AnimatedBuilder(
        animation: FarmerProfileStateService.instance,
        builder: (context, _) {
          final profile = FarmerProfileStateService.instance.profile;
          return AppNavigationDrawer(
            photoUrl: profile?.profilePhotoUrl,
            displayName: profile?.fullName ?? l10n.defaultFarmerName,
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
            OfflineBanner(message: l10n.farmerDashOfflineBanner),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
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

                      // Priority section — "Today's Priorities" header +
                      // count badge shown only when there's something to
                      // act on, mirroring Admin Dashboard's Priorities card.
                      // The All Clear state keeps its own self-contained
                      // positive framing instead, with no header above it.
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: StaggeredEntrance(
                            index: 1,
                            child: _isLoading
                                ? const _Shimmer(width: double.infinity, height: 72)
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (_priorityItems.isNotEmpty) ...[
                                        _PriorityHeader(
                                          count: _priorityItems.length,
                                          l10n: l10n,
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                      PriorityCard(
                                        items: _priorityItems,
                                        allClearTitle: l10n.dashboardAllClearTitle,
                                        allClearMessage: l10n.dashboardAllClearMessage,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),

                      // KPI cards. Monthly Earnings aggregates Marketplace
                      // (orders) + Offer to Cooperative
                      // (member_sales_transactions) + Informal Sales
                      // (informal_sales) + Market Linking
                      // (market_linking_programs, completed rounds) — see
                      // DashboardRepository.fetchSummary(). Earnings Goal is
                      // Admin-configurable (farmer_dashboard_settings),
                      // never hardcoded.
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

                      // Annual Yield / Annual Earnings moved to the Farmer
                      // Profile tab (as a KPI row above Farm Records) — no
                      // longer shown here. Market Rates' own top padding
                      // (20, matching every other section gap on this
                      // screen) now provides the spacing directly below
                      // the Monthly KPI section, so removing this block
                      // doesn't leave an uneven gap.

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

                      // Recent activity — loan-due entries excluded (now in Priority)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
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
              enableMenu: true,
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
// Priority Header — "Today's Priorities" + count badge, mirroring Admin
// Dashboard's Priorities card header. Shown only when there's at least one
// item; the All Clear state has its own self-contained framing instead.
// ─────────────────────────────────────────────────────────────────────────────

class _PriorityHeader extends StatelessWidget {
  final int count;
  final AppLocalizations l10n;

  const _PriorityHeader({required this.count, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppConstants.warningAmber,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.farmerDashTodaysPriorities,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppConstants.charcoal,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppConstants.warningAmber.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            count == 1
                ? l10n.farmerDashItemCountOne(count)
                : l10n.farmerDashItemCountOther(count),
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppConstants.warningAmber,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared section header — icon (optional) + label, matching Admin
// Dashboard's _SectionHeader treatment so Home's section titles read
// consistently with the rest of the app.
// ─────────────────────────────────────────────────────────────────────────────

class _FarmerSectionHeader extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _FarmerSectionHeader({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: AppConstants.primaryGreen),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppConstants.charcoal,
            ),
          ),
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
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: flatCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.farmerDashMonthlyYield,
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
                      _formatCompact(summary.monthlyYieldKg),
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.charcoal,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.farmerDashKgUnit,
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
              Flexible(
                child: Text(
                  l10n.farmerDashVsLastMonth(summary.yieldChangePercent.abs().toStringAsFixed(0)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: summary.yieldTrendUp
                        ? AppConstants.successGreen
                        : AppConstants.errorRed,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

class _EarningsCard extends StatelessWidget {
  final DashboardSummaryModel summary;
  final bool isLoading;

  const _EarningsCard({required this.summary, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: flatCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label gets the card's full width on its own line — previously
          // shared a row with the Goal badge, which forced it to truncate
          // to "Total Ear…" on narrower devices. The badge now pairs with
          // the amount below instead, where there's room for both.
          Text(
            l10n.farmerDashTotalEarnings,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: isLoading
                    ? const _Shimmer(width: 90, height: 24)
                    : Text(
                        '₱${_formatCompact(summary.monthlyEarnings)}',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.secondaryContainer,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppConstants.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n.farmerDashGoalPercent('${summary.earningsGoalPercent}'),
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.amber,
                  ),
                ),
              ),
            ],
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
            '₱${_formatCompact(summary.monthlyEarnings)} / ₱${_formatCompact(summary.earningsGoal)}',
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
    final l10n = AppLocalizations.of(context);
    final hasUnsynced = summary.unsyncedCount > 0;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: flatCardDecoration(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.farmerDashUnsyncedRecordsLabel,
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
                              summary.unsyncedCount == 1
                                  ? l10n.farmerDashItemCountOne(summary.unsyncedCount)
                                  : l10n.farmerDashItemCountOther(summary.unsyncedCount),
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
                      Flexible(
                        child: Container(
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
                            l10n.farmerDashRequiresSync,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                      ),
                  ],
                ),
                if (!isLoading) ...[
                  const SizedBox(height: 6),
                  Text(
                    summary.lastSyncedAt != null
                        ? l10n.farmerDashLastSynced(
                            AppUtils.formatRelativeTime(summary.lastSyncedAt!, l10n))
                        : l10n.farmerDashNeverSynced,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppConstants.onSurfaceVariant,
                    ),
                  ),
                ],
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
                mainAxisSize: MainAxisSize.min,
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
                  Flexible(
                    child: Text(
                      l10n.farmerDashSyncNow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppConstants.onPrimaryContainer,
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _FarmerSectionHeader(
                label: l10n.farmerDashMarketRates,
                icon: Icons.storefront_outlined,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onViewMarket,
              child: Text(
                l10n.farmerDashViewMarket,
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
          const _Shimmer(width: double.infinity, height: 188)
        else if (rates.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: flatCardDecoration(context),
            child: Row(
              children: [
                Icon(Icons.storefront_outlined,
                    size: 16, color: AppConstants.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.farmerDashNoMarketPrices,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppConstants.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 188,
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
    final l10n = AppLocalizations.of(context);
    final color = MarketTypeDisplay.color(context, rate.priceType);
    final imageUrl = rate.cropImageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 168,
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
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image fills the card's upper portion — crop identity comes
            // first, price is read once you know what it is. Mirrors Admin
            // Price Management's _PriceCard treatment, adapted to this
            // carousel's fixed card width instead of a grid.
            SizedBox(
              height: 84,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  hasImage
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: color.withValues(alpha: 0.12),
                            child: Icon(Icons.eco_rounded, size: 28, color: color),
                          ),
                        )
                      : Container(
                          color: color.withValues(alpha: 0.12),
                          child: Icon(Icons.eco_rounded, size: 28, color: color),
                        ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        MarketTypeDisplay.label(l10n, rate.priceType),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  const SizedBox(height: 6),
                  Text(
                    l10n.priceUpdatedPrefix(AppUtils.formatRelativeTime(rate.recordedAt, l10n)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppConstants.onSurfaceVariant,
                    ),
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
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _FarmerSectionHeader(label: l10n.recentActivity),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onViewAll,
              child: Text(
                l10n.farmerDashActivityViewAll,
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
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingGutter),
            decoration: flatCardDecoration(context),
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
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingGutter),
            decoration: flatCardDecoration(context),
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
                    l10n.farmerDashActivityEmpty,
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
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: flatCardDecoration(context),
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

    switch (type) {
      case ActivityType.harvest:
          icon = Icons.eco_rounded;
          bg = AppConstants.primaryGreen.withValues(alpha: 0.10);
          fg = AppConstants.primaryGreen;
          break;
        case ActivityType.listing:
          icon = Icons.storefront_outlined;
          bg = AppConstants.successGreen.withValues(alpha: 0.10);
          fg = AppConstants.successGreen;
          break;
        case ActivityType.orderPlaced:
          icon = Icons.shopping_cart_outlined;
          bg = AppConstants.successGreen.withValues(alpha: 0.10);
          fg = AppConstants.successGreen;
          break;
        case ActivityType.cropRequest:
          icon = Icons.local_florist_outlined;
          bg = (isAlert ? AppConstants.errorRed : AppConstants.primaryGreen)
              .withValues(alpha: 0.10);
          fg = isAlert ? AppConstants.errorRed : AppConstants.primaryGreen;
          break;
        case ActivityType.cropAdded:
          icon = Icons.grass_rounded;
          bg = AppConstants.primaryGreen.withValues(alpha: 0.10);
          fg = AppConstants.primaryGreen;
          break;
        case ActivityType.informalSale:
          icon = Icons.sell_outlined;
          bg = AppConstants.successGreen.withValues(alpha: 0.10);
          fg = AppConstants.successGreen;
          break;
        case ActivityType.cropPhotoUpdated:
          icon = Icons.photo_camera_outlined;
          bg = AppConstants.primaryGreen.withValues(alpha: 0.10);
          fg = AppConstants.primaryGreen;
          break;
        case ActivityType.cooperativeOffer:
          icon = Icons.groups_outlined;
          bg = AppConstants.successGreen.withValues(alpha: 0.10);
          fg = AppConstants.successGreen;
          break;
        case ActivityType.marketLinkingEnrollment:
          icon = Icons.handshake_outlined;
          bg = AppConstants.primaryGreen.withValues(alpha: 0.10);
          fg = AppConstants.primaryGreen;
          break;
        case ActivityType.gingerBatchSubmission:
          icon = Icons.outbox_outlined;
          bg = AppConstants.successGreen.withValues(alpha: 0.10);
          fg = AppConstants.successGreen;
          break;
        case ActivityType.profile:
          icon = Icons.person_outline_rounded;
          bg = AppConstants.outline.withValues(alpha: 0.10);
          fg = AppConstants.outline;
          break;
        case ActivityType.addressUpdated:
          icon = Icons.location_on_outlined;
          bg = AppConstants.outline.withValues(alpha: 0.10);
          fg = AppConstants.outline;
          break;
        case ActivityType.expenseAdded:
          icon = Icons.receipt_long_outlined;
          bg = AppConstants.outline.withValues(alpha: 0.10);
          fg = AppConstants.outline;
          break;
        case ActivityType.programEnrollment:
          icon = Icons.assignment_turned_in_outlined;
          bg = AppConstants.primaryGreen.withValues(alpha: 0.10);
          fg = AppConstants.primaryGreen;
          break;
        case ActivityType.programPurchase:
          icon = Icons.shopping_bag_outlined;
          bg = AppConstants.successGreen.withValues(alpha: 0.10);
          fg = AppConstants.successGreen;
          break;
        case ActivityType.capitalReinvestment:
          icon = Icons.savings_outlined;
          bg = AppConstants.primaryGreen.withValues(alpha: 0.10);
          fg = AppConstants.primaryGreen;
          break;
        case ActivityType.syncCompleted:
          icon = Icons.sync_rounded;
          bg = AppConstants.outline.withValues(alpha: 0.10);
          fg = AppConstants.outline;
          break;
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