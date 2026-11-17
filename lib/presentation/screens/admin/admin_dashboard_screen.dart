import '../../../core/utils/quantity_utils.dart';
import 'package:flutter/material.dart';
import '../../../data/services/hive_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_dashboard_model.dart';
import '../../../data/models/admin_reports_model.dart' show DashboardOverview;
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../data/repositories/admin_dashboard_repository.dart';
import '../../../data/repositories/admin_activity_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/admin_top_bar.dart';
import '../../widgets/report_summary_widgets.dart' show ReportSectionCard;
import '../../widgets/dashboard_cards.dart';
import '../../widgets/sync_status_card.dart';
import '../../../core/utils/member_access.dart';
import '../../../core/utils/activity_navigation.dart';
import 'admin_activity_screen.dart'
    show adminActivityDescription, adminActivityTimeLabel, moduleColor;

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

enum _DashSection { priorities, coop, kpi, calendar, modules, activity }

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _repo = AdminDashboardRepository();

  DashboardOverview _pulse = DashboardOverview.empty;
  List<DashboardPriority> _priorities = [];
  List<AdminActivityItem> _activity = [];
  CoopPerformanceSummary _coopSummary = CoopPerformanceSummary.empty;
  List<ManagementModuleCard> _managementModules = [];
  List<CalendarEvent> _calendarEvents = [];
  int _unreadCount = 0;
  String _adminName = '';

  // Sections appear as soon as their own data arrives, so a slow query no
  // longer holds back the rest of the dashboard. Refreshes keep showing the
  // previous data instead of re-showing the skeleton.
  final Set<_DashSection> _ready = {};

  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  Future<void> _loadAll() async {
    _repo.clearDashboardCache(); // fresh data every cycle, not stale reuse
    final month = _calendarMonth;
    await Future.wait<void>([
      _section(
        _DashSection.kpi,
        AdminReportsRepository().fetchDashboardOverview(),
        (v) => _pulse = v,
      ),
      _section(
        _DashSection.priorities,
        _repo.fetchDashboardPriorities(),
        (v) => _priorities = v,
      ),
      _section(
        _DashSection.activity,
        AdminActivityRepository().fetchActivity(
          limit: 5,
        ), // this user's own actions only
        (v) => _activity = v,
      ),
      _section(
        _DashSection.coop,
        _repo.fetchCoopPerformance(),
        (v) => _coopSummary = v,
      ),
      _section(
        _DashSection.modules,
        _repo.fetchManagementModuleBadges(),
        (v) => _managementModules = v,
      ),
      _section(
        _DashSection.calendar,
        _repo.fetchCalendarEvents(year: month.year, month: month.month),
        (v) => _calendarEvents = v,
      ),
      _loadHeaderExtras(),
    ]);
  }

  // Runs one dashboard fetch and applies its result as soon as it completes.
  // The section is marked ready even on failure, so a failed query shows an
  // empty section rather than a skeleton that never clears.
  Future<void> _section<T>(
    _DashSection section,
    Future<T> fetch,
    void Function(T) apply,
  ) async {
    try {
      final value = await fetch;
      if (mounted) setState(() => apply(value));
    } catch (e) {
      debugPrint('[AdminDashboardScreen] $section: $e');
    } finally {
      if (mounted) setState(() => _ready.add(section));
    }
  }

  Future<void> _loadHeaderExtras() async {
    try {
      final results = await Future.wait<Object?>([
        NotificationRepository().fetchUnreadCount(),
        _repo.fetchAdminFirstName(),
      ]);
      if (!mounted) return;
      setState(() {
        _unreadCount = results[0] as int;
        final adminFirstName = results[1] as String?;
        if (adminFirstName != null) _adminName = adminFirstName;
      });
    } catch (e) {
      debugPrint('[AdminDashboardScreen] header extras: $e');
    }
  }

  Future<void> _changeCalendarMonth(int delta) async {
    final next = DateTime(_calendarMonth.year, _calendarMonth.month + delta);
    setState(() => _calendarMonth = next);
    final events = await _repo.fetchCalendarEvents(
      year: next.year,
      month: next.month,
    );
    if (mounted) setState(() => _calendarEvents = events);
  }

  // ── Navigation helpers ────────────────────────────────────────────────────
  // Shell tab switches use context.go(); above-shell pushes use context.push().

  void _navigate(String route, {bool useGo = false, String? extra}) {
    if (useGo) {
      context.go(route);
    } else if (extra != null) {
      context.push(route, extra: extra).then((_) {
        if (mounted) _loadAll();
      });
    } else {
      // Refresh on return — this screen only loads once (initState), and
      // the Dashboard route uses StatefulShellRoute.indexedStack, which
      // keeps it alive rather than rebuilding it, so badge counts (e.g.
      // "Crop Requests", crop count) otherwise stay stale after an admin
      // approves/edits something in a pushed module and comes back.
      context.push(route).then((_) {
        if (mounted) _loadAll();
      });
    }
  }

  void _onActivityTap(AdminActivityItem item) {
    switch (item.type) {
      case AdminActivityType.listing:
        if (item.referenceId != null) {
          context
              .push(AppRoutes.listingReview, extra: item.referenceId)
              .then((_) => _loadAll());
        } else {
          // AppRoutes.pendingApprovals is a root-navigator push route, not
          // a shell branch — see fetchDashboardPriorities() for the same
          // fix and rationale. Phase 1, item 1.2.
          context.push(AppRoutes.pendingApprovals).then((_) => _loadAll());
        }
      case AdminActivityType.loan:
        if (item.referenceId != null) {
          context
              .push(AppRoutes.loanDetails, extra: item.referenceId)
              .then((_) => _loadAll());
        } else {
          context.go(AppRoutes.loanDashboard);
        }
      case AdminActivityType.member:
      case AdminActivityType.harvest:
        // Both navigate to farmer details using referenceId (farmerId)
        if (item.referenceId != null) {
          pushFarmerDetails(context, item.referenceId);
        } else {
          goMembersList(context);
        }
      case AdminActivityType.order:
        context.push(AppRoutes.pendingApprovals).then((_) => _loadAll());
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

  // ── Formatting ────────────────────────────────────────────────────────────

  String _greeting(AppLocalizations l10n) {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return l10n.greetingMorning;
    if (h >= 12 && h < 18) return l10n.greetingAfternoon;
    return l10n.greetingEvening;
  }

  String _formattedDate(AppLocalizations l10n) {
    final months = [
      l10n.adminCalMonthJan,
      l10n.adminCalMonthFeb,
      l10n.adminCalMonthMar,
      l10n.adminCalMonthApr,
      l10n.adminCalMonthMay,
      l10n.adminCalMonthJun,
      l10n.adminCalMonthJul,
      l10n.adminCalMonthAug,
      l10n.adminCalMonthSep,
      l10n.adminCalMonthOct,
      l10n.adminCalMonthNov,
      l10n.adminCalMonthDec,
    ];
    final days = [
      l10n.adminCalWeekdayMon,
      l10n.adminCalWeekdayTue,
      l10n.adminCalWeekdayWed,
      l10n.adminCalWeekdayThu,
      l10n.adminCalWeekdayFri,
      l10n.adminCalWeekdaySat,
      l10n.adminCalWeekdaySun,
    ];
    final now = DateTime.now();
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: _loadAll,
        child: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: AdminTopBarDelegate(
                topPadding: MediaQuery.paddingOf(context).top,
                title: l10n.adminNavDashboard,
                unreadCount: _unreadCount,
                onNotificationTap: () => context
                    .push(AppRoutes.adminNotifications)
                    .then((_) => _loadAll()),
                onBroadcastTap: () =>
                    context.push(AppRoutes.announcementDashboard),
                onProfileTap: () => context.push(AppRoutes.adminProfile),
                enableMenu: true,
              ),
            ),

            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                10 + MediaQuery.of(context).viewPadding.bottom,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Greeting ────────────────────────────────────────────
                  Text(
                    '${_greeting(l10n)}, ${_adminName.isNotEmpty
                        ? _adminName
                        : HiveService.isOfficer
                        ? l10n.staffRoleOfficer
                        : l10n.staffRoleManager}!',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formattedDate(l10n),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Dynamic Hero Card (Today's Priorities) ───────────────
                  if (_ready.contains(_DashSection.priorities))
                    _PrioritiesHeroCard(
                      priorities: _priorities,
                      onTap: (p) =>
                          _navigate(p.route, useGo: p.useGo, extra: p.extra),
                      cs: cs,
                      sagana: sagana,
                    )
                  else
                    const SkeletonBlock(height: 120),
                  const SizedBox(height: 20),

                  // ── Cooperative Performance ────────────────────────────
                  if (_ready.contains(_DashSection.coop))
                    _CoopPerformanceCard(
                      summary: _coopSummary,
                      onTap: () => context.go(AppRoutes.operationalReports),
                      cs: cs,
                      sagana: sagana,
                    )
                  else
                    const SkeletonBlock(height: 120),
                  const SizedBox(height: 20),

                  // ── KPI Strip ────────────────────────────────────────────
                  // Grouped inside the same outer titled container the
                  // Report tab uses (Executive Snapshot etc.), not just
                  // individually restyled cards.
                  if (!_ready.contains(_DashSection.kpi))
                    const SkeletonBlock(height: 150)
                  else
                    ReportSectionCard(
                      title: l10n.adminDashOverviewTitle,
                      icon: Icons.dashboard_rounded,
                      accent: AppConstants.primaryGreen,
                      child: _KpiStrip(pulse: _pulse, cs: cs, sagana: sagana),
                    ),
                  const SizedBox(height: 20),

                  // ── Sync & connectivity (below Overview) ─────────────────
                  const SyncStatusCard(),
                  const SizedBox(height: 20),
                  // ── Color-Coded Calendar ─────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _SectionHeader(
                          icon: Icons.calendar_month_rounded,
                          label: l10n.adminCalTitle,
                          cs: cs,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        // Full Calendar is a real screen — push above shell
                        onTap: () => context.push(AppRoutes.adminCalendar),
                        child: Text(
                          l10n.adminDashViewFullCalendar,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (!_ready.contains(_DashSection.calendar))
                    const SkeletonBlock(height: 280)
                  else
                    _MiniCalendar(
                      month: _calendarMonth,
                      events: _calendarEvents,
                      onPreviousMonth: () => _changeCalendarMonth(-1),
                      onNextMonth: () => _changeCalendarMonth(1),
                      cs: cs,
                      sagana: sagana,
                    ),
                  const SizedBox(height: 20),

                  // ── Management Modules ───────────────────────────────────
                  _SectionHeader(
                    icon: Icons.grid_view_rounded,
                    label: l10n.adminDashManagementModules,
                    cs: cs,
                  ),
                  const SizedBox(height: 12),
                  if (!_ready.contains(_DashSection.modules))
                    const SkeletonBlock(height: 200)
                  else
                    _ManagementModulesGrid(
                      modules: _managementModules,
                      onTap: (m) => _navigate(m.route, useGo: m.useGo),
                      cs: cs,
                      sagana: sagana,
                    ),
                  const SizedBox(height: 20),

                  // ── Recent Activity ──────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _SectionHeader(
                          label: l10n.adminDashRecentActivity,
                          cs: cs,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => context.push(AppRoutes.adminActivityLog),
                        child: Text(
                          l10n.listingsAllButton,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!_ready.contains(_DashSection.activity))
                    const SkeletonBlock(height: 280)
                  else
                    _ActivityFeed(
                      items: _activity,
                      onTap: _onActivityTap,
                      sagana: sagana,
                      cs: cs,
                    ),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dynamic Hero Card — Today's Priorities
// ─────────────────────────────────────────────────────────────────────────────

class _PrioritiesHeroCard extends StatelessWidget {
  final List<DashboardPriority> priorities;
  final void Function(DashboardPriority) onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _PrioritiesHeroCard({
    required this.priorities,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  Color _levelColor(DashboardPriorityLevel level) {
    switch (level) {
      case DashboardPriorityLevel.critical:
        return AppConstants.errorRed;
      case DashboardPriorityLevel.warning:
        return AppConstants.warningAmber;
      case DashboardPriorityLevel.info:
        return AppConstants.buyerBlue;
    }
  }

  IconData _levelIcon(DashboardPriorityLevel level) {
    switch (level) {
      case DashboardPriorityLevel.critical:
        return Icons.warning_rounded;
      case DashboardPriorityLevel.warning:
        return Icons.schedule_rounded;
      case DashboardPriorityLevel.info:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (priorities.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppConstants.successGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          border: Border.all(
            color: AppConstants.successGreen.withValues(alpha: 0.20),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppConstants.successGreen.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppConstants.successGreen,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.dashboardAllClearTitle,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.successGreen,
                    ),
                  ),
                  Text(
                    l10n.adminDashAllClearMessage,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color:
                        priorities.first.level ==
                            DashboardPriorityLevel.critical
                        ? AppConstants.errorRed
                        : AppConstants.warningAmber,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.adminDashTodaysPriorities,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                  ),
                  child: Text(
                    l10n.buyerCartItemCount(priorities.length),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.08)),
          ...priorities.take(4).toList().asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            final color = _levelColor(p.level);
            final icon = _levelIcon(p.level);
            final isLast = i == priorities.take(4).length - 1;
            return Column(
              children: [
                GestureDetector(
                  onTap: () => onTap(p),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: color, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.label,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                p.value,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: color.withValues(alpha: 0.60),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isLast)
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: cs.outline.withValues(alpha: 0.08),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI Strip
// ─────────────────────────────────────────────────────────────────────────────

/// The Dashboard Overview: one card for each Management Module (same order as the modules below
/// it) with Revenue in the middle. Every figure is for the current year and starts again each
/// January, so nothing piles up across years.
class _KpiStrip extends StatelessWidget {
  final DashboardOverview pulse;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _KpiStrip({
    required this.pulse,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tiles = [
      DashboardKpiTile(
        label: l10n.adminDashModInventory,
        value: '${pulse.inventoryItems}',
        sub: l10n.adminDashModInventorySub,
        color: AppConstants.warningAmber,
        icon: Icons.inventory_2_rounded,
      ),
      DashboardKpiTile(
        label: l10n.adminDashModCrops,
        value: '${pulse.crops}',
        sub: l10n.adminDashModCropsSub,
        color: AppConstants.midGreen,
        icon: Icons.grass_rounded,
      ),
      DashboardKpiTile(
        label: l10n.adminDashModPrograms,
        value: '${pulse.programs}',
        sub: l10n.adminDashModProgramsSub,
        color: AppConstants.programPurple,
        icon: Icons.people_alt_rounded,
      ),
      DashboardKpiTile(
        label: l10n.adminDashKpiRevenue,
        value: '₱${_fmt(pulse.revenue)}',
        // Marketplace sales plus what members paid for Cooperative Products.
        sub: l10n.adminDashPulseRevenueSub,
        color: AppConstants.successGreen,
        icon: Icons.trending_up_rounded,
      ),
      DashboardKpiTile(
        label: l10n.adminDashModSupplyChain,
        value: '${pulse.totalSupplies}',
        sub: l10n.adminDashModSupplyChainSub(
          pulse.suppliesIncoming,
          pulse.suppliesOutgoing,
        ),
        color: AppConstants.primaryGreen,
        icon: Icons.alt_route_rounded,
      ),
      DashboardKpiTile(
        label: l10n.adminDashModPrices,
        value: '${pulse.retailPrices}',
        sub: l10n.adminDashModPricesSub,
        color: AppConstants.amber,
        icon: Icons.sell_rounded,
      ),
    ];

    return DashboardKpiStrip(tiles: tiles);
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini Calendar
// ─────────────────────────────────────────────────────────────────────────────

class _MiniCalendar extends StatelessWidget {
  final DateTime month;
  final List<CalendarEvent> events;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _MiniCalendar({
    required this.month,
    required this.events,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.cs,
    required this.sagana,
  });

  List<String> _monthNames(AppLocalizations l10n) => [
    l10n.adminCalMonthJan,
    l10n.adminCalMonthFeb,
    l10n.adminCalMonthMar,
    l10n.adminCalMonthApr,
    l10n.adminCalMonthMay,
    l10n.adminCalMonthJun,
    l10n.adminCalMonthJul,
    l10n.adminCalMonthAug,
    l10n.adminCalMonthSep,
    l10n.adminCalMonthOct,
    l10n.adminCalMonthNov,
    l10n.adminCalMonthDec,
  ];
  List<String> _dayLabels(AppLocalizations l10n) => [
    l10n.adminCalWeekdayShortSun,
    l10n.adminCalWeekdayShortMon,
    l10n.adminCalWeekdayShortTue,
    l10n.adminCalWeekdayShortWed,
    l10n.adminCalWeekdayShortThu,
    l10n.adminCalWeekdayShortFri,
    l10n.adminCalWeekdayShortSat,
  ];

  Map<int, Set<CalendarEventType>> _buildEventMap() {
    final map = <int, Set<CalendarEventType>>{};
    for (final e in events) {
      if (e.date.year == month.year && e.date.month == month.month) {
        map.putIfAbsent(e.date.day, () => {}).add(e.type);
      }
    }
    return map;
  }

  Color _eventColor(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.bodMeeting:
        return AppConstants.successGreen;
      case CalendarEventType.loanDue:
        return AppConstants.errorRed;
      case CalendarEventType.harvest:
        return AppConstants.warningAmber;
      case CalendarEventType.announcement:
        return AppConstants.buyerBlue;
      case CalendarEventType.program:
        return AppConstants.programPurple;
    }
  }

  String _legendLabel(AppLocalizations l10n, CalendarEventType type) {
    switch (type) {
      case CalendarEventType.bodMeeting:
        return l10n.adminCalEventBodMeeting;
      case CalendarEventType.loanDue:
        return l10n.adminCalEventLoanDue;
      case CalendarEventType.harvest:
        return l10n.adminCalEventHarvest;
      case CalendarEventType.announcement:
        return l10n.adminCalEventAnnouncement;
      case CalendarEventType.program:
        return l10n.adminCalEventProgram;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final monthNames = _monthNames(l10n);
    final dayLabels = _dayLabels(l10n);
    final today = DateTime.now();
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7; // Sunday = 0
    final eventMap = _buildEventMap();
    final uniqueTypes = events.map((e) => e.type).toSet().toList();

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Month navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: onPreviousMonth,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Text(
                '${monthNames[month.month - 1]} ${month.year}',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              GestureDetector(
                onTap: onNextMonth,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Day-of-week headers
          Row(
            children: dayLabels.map((d) {
              return Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

          // Calendar grid
          GridView.builder(
            shrinkWrap: true,
            // No automatic status-bar padding: this list sits inside a bigger scroll view.
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.0,
            ),
            itemCount: startWeekday + daysInMonth,
            itemBuilder: (_, index) {
              if (index < startWeekday) {
                return const SizedBox.shrink();
              }
              final day = index - startWeekday + 1;
              final isToday =
                  today.year == month.year &&
                  today.month == month.month &&
                  today.day == day;
              final dayEvents = eventMap[day];

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: isToday
                        ? BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Center(
                      child: Text(
                        '$day',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isToday ? Colors.white : cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                  if (dayEvents != null && dayEvents.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: dayEvents
                            .take(3)
                            .map(
                              (type) => Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: _eventColor(type),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              );
            },
          ),

          // Legend
          if (uniqueTypes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: cs.outline.withValues(alpha: 0.10)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: uniqueTypes.map((type) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _eventColor(type),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(child: Text(
                      _legendLabel(l10n, type),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    )),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Management Modules Grid
// ─────────────────────────────────────────────────────────────────────────────

class _ManagementModulesGrid extends StatelessWidget {
  final List<ManagementModuleCard> modules;
  final void Function(ManagementModuleCard) onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ManagementModulesGrid({
    required this.modules,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  static const _icons = {
    'inventory': Icons.inventory_2_rounded,
    'crops': Icons.grass_rounded,
    'programs': Icons.people_alt_rounded,
    'loan-items': Icons.category_rounded,
    'supply-chain': Icons.alt_route_rounded,
    'prices': Icons.sell_rounded,
  };

  // Card title/subtitle are looked up here by id rather than read off the
  // model — ManagementModuleCard.title/subtitle come from the repository
  // (a data layer with no AppLocalizations access) and were hardcoded
  // English; the id is stable data, so it's the right join key for the
  // locale-aware display strings instead.
  static String _title(AppLocalizations l10n, String id) {
    switch (id) {
      case 'inventory':
        return l10n.adminInvManagementTitle;
      case 'crops':
        return l10n.cropMgmtTitle;
      case 'programs':
        return l10n.programMgmtTitle;
      case 'loan-items':
        return l10n.loanItemCatalogTitle;
      case 'supply-chain':
        return l10n.supplyChainTitle;
      case 'prices':
        return l10n.adminPriceManagement;
      default:
        return id;
    }
  }

  static String _subtitle(AppLocalizations l10n, String id) {
    switch (id) {
      case 'inventory':
        return l10n.adminDashModuleInventorySubtitle;
      case 'crops':
        return l10n.adminDashModuleCropsSubtitle;
      case 'programs':
        return l10n.adminDashModuleProgramsSubtitle;
      case 'loan-items':
        return l10n.adminDashModuleLoanItemsSubtitle;
      case 'supply-chain':
        return l10n.adminDashModuleSupplyChainSubtitle;
      case 'prices':
        return l10n.adminDashModulePricesSubtitle;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DashboardModuleGrid(
      items: [
        for (final m in modules)
          DashboardModuleItem(
            icon: _icons[m.id] ?? Icons.settings_rounded,
            title: _title(l10n, m.id),
            subtitle: _subtitle(l10n, m.id),
            badge: m.badgeLabel,
            onTap: () => onTap(m),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Activity Feed
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityFeed extends StatelessWidget {
  final List<AdminActivityItem> items;
  final void Function(AdminActivityItem) onTap;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _ActivityFeed({
    required this.items,
    required this.onTap,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (items.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        ),
        child: Text(
          l10n.adminDashNoRecentActivity,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final isLast = i == items.length - 1;
          return Column(
            children: [
              GestureDetector(
                onTap:
                    (membersAccessAllowed ||
                        !(item.type == AdminActivityType.member ||
                            item.type == AdminActivityType.harvest))
                    ? () => onTap(item)
                    : null,
                behavior: HitTestBehavior.opaque,
                child: _ActivityRow(item: item, cs: cs),
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  color: cs.outline.withValues(alpha: 0.08),
                  indent: 16,
                  endIndent: 16,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final AdminActivityItem item;
  final ColorScheme cs;

  const _ActivityRow({required this.item, required this.cs});

  Color _dotColor() {
    if (item.type == AdminActivityType.listing) {
      return item.isPrimary
          ? AppConstants.successGreen
          : AppConstants.primaryGreen;
    }
    return moduleColor(item.sourceModule, cs);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final desc = adminActivityDescription(l10n, item);
    final name = item.highlightedName;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _dotColor(),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                name != null && desc.contains(name)
                    ? _RichDescription(
                        description: desc,
                        boldName: name,
                        cs: cs,
                      )
                    : Text(
                        desc,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: cs.onSurface,
                        ),
                      ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(child: Text(
                      adminActivityTimeLabel(l10n, item.timestamp),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    )),
                    if (item.referenceId != null) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RichDescription extends StatelessWidget {
  final String description;
  final String boldName;
  final ColorScheme cs;

  const _RichDescription({
    required this.description,
    required this.boldName,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final parts = description.split(boldName);
    return Text.rich(
      TextSpan(
        style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
        children: [
          TextSpan(text: parts[0]),
          TextSpan(
            text: boldName,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          if (parts.length > 1) TextSpan(text: parts[1]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cooperative Performance Card
// ─────────────────────────────────────────────────────────────────────────────

class _CoopPerformanceCard extends StatelessWidget {
  final CoopPerformanceSummary summary;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _CoopPerformanceCard({
    required this.summary,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    l10n.adminDashCoopPerformanceHeader,
                    maxLines: 2,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      l10n.adminDashViewReportsArrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Top-aligned, so the four labels share a line and the four figures share a line;
            // only Farmer Stock (one line per unit) runs longer.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatPill(
                  l10n.adminDashStatHarvests,
                  '${summary.totalHarvests}',
                  cs,
                ),
                const SizedBox(width: 12),
                _StatPill(
                  l10n.adminDashStatFarmerStock,
                  // One line per unit (kg, sack...), never added together.
                  summary.farmerStock.isEmpty
                      ? '0'
                      : formatQuantitiesByUnit(
                          summary.farmerStock,
                        ).replaceAll(' + ', '\n'),
                  cs,
                ),
                const SizedBox(width: 12),
                _StatPill(
                  l10n.adminDashStatListings,
                  '${summary.activeListings}',
                  cs,
                ),
                const SizedBox(width: 12),
                _StatPill(
                  l10n.adminDashStatSalesAllTime,
                  formatPesosCompact(summary.salesAmount),
                  cs,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: cs.outline.withValues(alpha: 0.12)),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
                children: [
                  TextSpan(text: l10n.adminDashMemberParticipationPrefix),
                  TextSpan(
                    text: l10n.adminDashMembersOfTotal(
                      summary.activeMembersThisSeason,
                      summary.totalMembers,
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  TextSpan(text: l10n.adminDashMemberParticipationSuffix),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: summary.participationPercent,
                minHeight: 8,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(cs.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;

  const _StatPill(this.label, this.value, this.cs);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Two lines of room for every label, so a longer one never pushes its figure down.
          SizedBox(
            height: 24,
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                label.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          // A figure may have several lines (stock in more than one unit); each line shrinks to
          // fit rather than breaking in the middle ("377.50 / kg").
          for (final line in value.split('\n'))
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                line,
                maxLines: 1,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Section Header, Shimmer
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData? icon;
  final ColorScheme? cs;

  const _SectionHeader({required this.label, this.icon, this.cs});

  @override
  Widget build(BuildContext context) {
    final scheme = cs ?? Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
        ],
        // Flexible + ellipsis: translated section titles (e.g. "Kalendaryo
        // ng Kooperatiba", "Mga Alerto sa Imbakan") run noticeably longer
        // than their English source. This header always sits in a
        // spaceBetween Row next to a trailing "View X" link with no other
        // slack, so without this a long title pushes the link past the
        // available width and overflows.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
