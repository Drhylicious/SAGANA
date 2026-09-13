import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_dashboard_model.dart';
import '../../../data/repositories/admin_dashboard_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/admin_top_bar.dart';
import '../../widgets/shared_widgets.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _repo = AdminDashboardRepository();

  AdminKpiSummary _kpi = AdminKpiSummary.empty;
  List<DashboardPriority> _priorities = [];
  List<AdminActivityItem> _activity = [];
  CoopPerformanceSummary _coopSummary = CoopPerformanceSummary.empty;
  List<InventoryAlertItem> _inventoryAlerts = [];
  List<ManagementModuleCard> _managementModules = [];
  List<CalendarEvent> _calendarEvents = [];
  int _unreadCount = 0;
  String _adminName = 'Admin';

  bool _isLoading = true;
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySub;

  DateTime _calendarMonth =
      DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    _repo.clearDashboardCache(); // Phase 5, item 5.1 — fresh data every cycle, not stale reuse
    final results = await Future.wait([
      _repo.fetchKpiSummary(),
      _repo.fetchDashboardPriorities(),
      _repo.fetchRecentActivity(limit: 5), // Dashboard preview kept compact per your request — Activity Log's own call is separate and untouched
      _repo.fetchCoopPerformance(),
      _repo.fetchInventoryAlerts(),
      _repo.fetchManagementModuleBadges(),
      _repo.fetchCalendarEvents(
          year: _calendarMonth.year, month: _calendarMonth.month),
      _repo.fetchUnreadCount(),
      _repo.fetchAdminFirstName(),
    ]);
    if (!mounted) return;
    setState(() {
      _kpi               = results[0] as AdminKpiSummary;
      _priorities        = results[1] as List<DashboardPriority>;
      _activity          = results[2] as List<AdminActivityItem>;
      _coopSummary       = results[3] as CoopPerformanceSummary;
      _inventoryAlerts   = results[4] as List<InventoryAlertItem>;
      _managementModules = results[5] as List<ManagementModuleCard>;
      _calendarEvents    = results[6] as List<CalendarEvent>;
      _unreadCount       = results[7] as int;
      final adminFirstName = results[8] as String?;
      if (adminFirstName != null) _adminName = adminFirstName;
      _isLoading         = false;
    });
  }

  Future<void> _changeCalendarMonth(int delta) async {
    final next = DateTime(
        _calendarMonth.year, _calendarMonth.month + delta);
    setState(() => _calendarMonth = next);
    final events = await _repo.fetchCalendarEvents(
        year: next.year, month: next.month);
    if (mounted) setState(() => _calendarEvents = events);
  }

  // ── Navigation helpers ────────────────────────────────────────────────────
  // Shell tab switches use context.go(); above-shell pushes use context.push().

  void _navigate(String route, {bool useGo = false, String? extra}) {
    if (useGo) {
      context.go(route);
    } else if (extra != null) {
      context.push(route, extra: extra);
    } else {
      context.push(route);
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
          context.push(AppRoutes.farmerDetails, extra: item.referenceId);
        } else {
          context.go(AppRoutes.farmerManagement);
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
    }
  }

  // ── Formatting ────────────────────────────────────────────────────────────

  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Good morning';
    if (h >= 12 && h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _formattedDate() {
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    const days = [
      'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'
    ];
    final now = DateTime.now();
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n   = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        color: AppConstants.primaryGreen,
        onRefresh: _loadAll,
        child: CustomScrollView(
          slivers: [
            if (!_isOnline)
              const SliverToBoxAdapter(child: OfflineBanner()),

            SliverPersistentHeader(
              pinned: true,
              delegate: AdminTopBarDelegate(
                title: l10n.adminNavDashboard,
                unreadCount: _unreadCount,
                onNotificationTap: () =>
                    context.push(AppRoutes.adminNotifications)
                        .then((_) => _loadAll()),
                onBroadcastTap: () =>
                    context.push(AppRoutes.announcementDashboard),
                onProfileTap: () =>
                    context.push(AppRoutes.adminProfile),
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
                    '${_greeting()}, $_adminName!',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formattedDate(),
                    style: GoogleFonts.inter(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),

                  // ── Dynamic Hero Card (Today's Priorities) ───────────────
                  if (!_isLoading)
                    _PrioritiesHeroCard(
                      priorities: _priorities,
                      onTap: (p) => _navigate(p.route,
                          useGo: p.useGo, extra: p.extra),
                      cs: cs,
                      sagana: sagana,
                    )
                  else
                    const _ShimmerBlock(height: 120),
                  const SizedBox(height: 20),

                  // ── Cooperative Performance ────────────────────────────
                  _CoopPerformanceCard(
                    summary: _coopSummary,
                    onTap: () =>
                        context.go(AppRoutes.operationalReports),
                    cs: cs,
                    sagana: sagana,
                  ),
                  const SizedBox(height: 20),

                  // ── KPI Strip ────────────────────────────────────────────
                  if (_isLoading)
                    const _ShimmerBlock(height: 96)
                  else
                    _KpiStrip(kpi: _kpi, cs: cs, sagana: sagana),
                  const SizedBox(height: 20),

                  // ── Inventory Alerts ─────────────────────────────────────
                  if (!_isLoading && _inventoryAlerts.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _SectionHeader(
                          icon: Icons.inventory_2_outlined,
                          label: 'Inventory Alerts',
                          iconColor: AppConstants.warningAmber,
                          cs: cs,
                        ),
                        GestureDetector(
                          // Phase 2: this card now describes cooperative_inventory
                          // (Inventory Management's own stock), so the link routes
                          // there instead of the farmer-harvest-batches screen.
                          onTap: () => context.push(AppRoutes.adminInventory),
                          child: Text(
                            'View Inventory',
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
                    _InventoryAlertsCard(
                      alerts: _inventoryAlerts,
                      cs: cs,
                      sagana: sagana,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Color-Coded Calendar ─────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionHeader(
                        icon: Icons.calendar_month_rounded,
                        label: 'Cooperative Calendar',
                        cs: cs,
                      ),
                      GestureDetector(
                        // Full Calendar is a real screen — push above shell
                        onTap: () =>
                            context.push(AppRoutes.adminCalendar),
                        child: Text(
                          'View Full Calendar',
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
                  if (_isLoading)
                    const _ShimmerBlock(height: 280)
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
                      label: 'Management Modules',
                      cs: cs),
                  const SizedBox(height: 12),
                  if (_isLoading)
                    const _ShimmerBlock(height: 200)
                  else
                    _ManagementModulesGrid(
                      modules: _managementModules,
                      onTap: (m) =>
                          _navigate(m.route, useGo: m.useGo),
                      cs: cs,
                      sagana: sagana,
                    ),
                  const SizedBox(height: 20),

                  // ── Recent Activity ──────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionHeader(label: 'Recent Activity', cs: cs),
                      GestureDetector(
                        onTap: () => context.push(AppRoutes.adminActivityLog),
                        child: Text(
                          'View All',
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
                  if (_isLoading)
                    const _ShimmerBlock(height: 280)
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
      case DashboardPriorityLevel.critical: return AppConstants.errorRed;
      case DashboardPriorityLevel.warning:  return AppConstants.warningAmber;
      case DashboardPriorityLevel.info:     return AppConstants.buyerBlue;
    }
  }

  IconData _levelIcon(DashboardPriorityLevel level) {
    switch (level) {
      case DashboardPriorityLevel.critical: return Icons.warning_rounded;
      case DashboardPriorityLevel.warning:  return Icons.schedule_rounded;
      case DashboardPriorityLevel.info:     return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (priorities.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppConstants.successGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          border: Border.all(
              color: AppConstants.successGreen.withValues(alpha: 0.20)),
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
              child: const Icon(Icons.check_circle_rounded,
                  color: AppConstants.successGreen, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All Clear',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.successGreen,
                    ),
                  ),
                  Text(
                    'No urgent items today. Cooperative is on track.',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant),
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
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: priorities.first.level ==
                            DashboardPriorityLevel.critical
                        ? AppConstants.errorRed
                        : AppConstants.warningAmber,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "Today's Priorities",
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(
                    '${priorities.length} item${priorities.length == 1 ? '' : 's'}',
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          Divider(
              height: 1,
              color: cs.outline.withValues(alpha: 0.08)),
          ...priorities.take(4).toList().asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            final color = _levelColor(p.level);
            final icon = _levelIcon(p.level);
            final isLast =
                i == priorities.take(4).length - 1;
            return Column(
              children: [
                GestureDetector(
                  onTap: () => onTap(p),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(icon, color: color, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
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
                                    color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: color.withValues(alpha: 0.60),
                            size: 18),
                      ],
                    ),
                  ),
                ),
                if (!isLast)
                  Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: cs.outline.withValues(alpha: 0.08)),
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

// Phase 2, item 2.1 — flags the Overdue Loans figure as stale when the
// nightly run_daily_loan_maintenance() job hasn't confirmed a run in over
// 30 hours (its usual cadence is daily; 30h gives one missed-run's grace
// before surfacing a warning).
bool _isLoanDataStale(DateTime? asOf) {
  if (asOf == null) return false;
  return DateTime.now().difference(asOf) > const Duration(hours: 30);
}

String _loanDataStalenessLabel(DateTime? asOf) {
  if (!_isLoanDataStale(asOf)) return 'loans';
  final hours = DateTime.now().difference(asOf!).inHours;
  final days = (hours / 24).floor();
  return days >= 1 ? 'data ${days}d old' : 'data ${hours}h old';
}

class _KpiStrip extends StatelessWidget {
  final AdminKpiSummary kpi;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _KpiStrip(
      {required this.kpi, required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _KpiTile(
        label: 'Members',
        value: '${kpi.activeMembers}',
        sub: 'of ${kpi.totalMembersTarget}',
        color: AppConstants.successGreen,
        icon: Icons.people_rounded,
      ),
      _KpiTile(
        label: 'Coop Stock (kg)',
        value: _fmt(kpi.totalStockKg),
        sub: 'available',
        color: AppConstants.warningAmber,
        icon: Icons.inventory_2_rounded,
      ),
      _KpiTile(
        label: 'Pending',
        value: '${kpi.pendingListings}',
        sub: 'listings',
        color: cs.primary,
        icon: Icons.pending_actions_rounded,
      ),
      _KpiTile(
        label: 'Overdue',
        value: '${kpi.overdueLoans}',
        sub: _loanDataStalenessLabel(kpi.loanDataAsOf),
        color: _isLoanDataStale(kpi.loanDataAsOf)
            ? AppConstants.warningAmber
            : kpi.overdueLoans > 0
                ? AppConstants.errorRed
                : cs.outline,
        icon: Icons.warning_amber_rounded,
      ),
      _KpiTile(
        label: 'Revenue',
        value: '₱${_fmt(kpi.totalRevenueThisMonth)}',
        sub: 'this month',
        color: AppConstants.successGreen,
        icon: Icons.trending_up_rounded,
      ),
    ];

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) =>
            _KpiCard(tile: tiles[i], cs: cs, sagana: sagana),
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }
}

class _KpiTile {
  final String label;
  final String value;
  final String sub;
  final Color color;
  final IconData icon;
  const _KpiTile({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.icon,
  });
}

class _KpiCard extends StatelessWidget {
  final _KpiTile tile;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _KpiCard(
      {required this.tile, required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius:
            BorderRadius.circular(AppConstants.radiusLg),
        border:
            Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(tile.icon, size: 14, color: tile.color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  tile.label,
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            tile.value,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: tile.color,
            ),
          ),
          Text(
            tile.sub,
            style: GoogleFonts.inter(
                fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inventory Alerts Card
// ─────────────────────────────────────────────────────────────────────────────

class _InventoryAlertsCard extends StatelessWidget {
  final List<InventoryAlertItem> alerts;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _InventoryAlertsCard(
      {required this.alerts, required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8),
        ],
      ),
      child: Column(
        children: alerts.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final isLast = i == alerts.length - 1;
          final color = item.isDepleted
              ? AppConstants.errorRed
              : AppConstants.warningAmber;
          final label = item.isDepleted ? 'DEPLETED' : 'LOW STOCK';

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.inventory_2_outlined,
                          color: color, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.itemName,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            item.category,
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${item.quantityOnHand.toStringAsFixed(1)} ${item.unit}',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                                AppConstants.radiusFull),
                          ),
                          child: Text(
                            label,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: color,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(
                    height: 1,
                    color: cs.outline.withValues(alpha: 0.08),
                    indent: 16,
                    endIndent: 16),
            ],
          );
        }).toList(),
      ),
    );
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

  static const _monthNames = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December',
  ];
  static const _dayLabels = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];

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
      case CalendarEventType.bodMeeting:   return AppConstants.successGreen;
      case CalendarEventType.loanDue:      return AppConstants.errorRed;
      case CalendarEventType.harvest:      return AppConstants.warningAmber;
      case CalendarEventType.announcement: return AppConstants.buyerBlue;
      case CalendarEventType.program:      return AppConstants.programPurple;
    }
  }

  String _legendLabel(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.bodMeeting:   return 'BOD Meeting';
      case CalendarEventType.loanDue:      return 'Loan Due';
      case CalendarEventType.harvest:      return 'Harvest';
      case CalendarEventType.announcement: return 'Announcement';
      case CalendarEventType.program:      return 'Program';
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth =
        DateTime(month.year, month.month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7; // Sunday = 0
    final eventMap = _buildEventMap();
    final uniqueTypes = events.map((e) => e.type).toSet().toList();

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8),
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
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Icon(Icons.chevron_left_rounded,
                      size: 20, color: cs.onSurface),
                ),
              ),
              Text(
                '${_monthNames[month.month - 1]} ${month.year}',
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
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 20, color: cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Day-of-week headers
          Row(
            children: _dayLabels.map((d) {
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
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.0,
            ),
            itemCount: startWeekday + daysInMonth,
            itemBuilder: (_, index) {
              if (index < startWeekday) {
                return const SizedBox.shrink();
              }
              final day = index - startWeekday + 1;
              final isToday = today.year == month.year &&
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
                          color: isToday
                              ? Colors.white
                              : cs.onSurface,
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
                            .map((type) => Container(
                                  width: 4,
                                  height: 4,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 1),
                                  decoration: BoxDecoration(
                                    color: _eventColor(type),
                                    shape: BoxShape.circle,
                                  ),
                                ))
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
                    Text(
                      _legendLabel(type),
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          color: cs.onSurfaceVariant),
                    ),
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
    'inventory':    Icons.inventory_2_rounded,
    'crops':        Icons.grass_rounded,
    'programs':     Icons.people_alt_rounded,
    'loan-items':   Icons.category_rounded,
    'supply-chain': Icons.alt_route_rounded,
    'prices':       Icons.sell_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemCount: modules.length,
      itemBuilder: (context, i) {
        final m = modules[i];
        final icon = _icons[m.id] ?? Icons.settings_rounded;
        return GestureDetector(
          onTap: () => onTap(m),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: sagana.cardBackground,
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(
                  color: cs.outline.withValues(alpha: 0.10)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color:
                            cs.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd),
                      ),
                      child: Icon(icon,
                          color: cs.primary, size: 20),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: m.hasBadgeAlert
                            ? AppConstants.warningAmber
                                .withValues(alpha: 0.15)
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull),
                      ),
                      child: Text(
                        m.badgeLabel,
                        style: GoogleFonts.inter(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: m.hasBadgeAlert
                              ? AppConstants.warningAmber
                              : cs.onSurfaceVariant,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        m.title,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        m.subtitle,
                        style: GoogleFonts.inter(
                            fontSize: 9,
                            color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
    if (items.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
              color: cs.outline.withValues(alpha: 0.10)),
        ),
        child: Text(
          'No recent activity',
          style: GoogleFonts.inter(
              fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8),
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
                onTap: () => onTap(item),
                behavior: HitTestBehavior.opaque,
                child: _ActivityRow(item: item, cs: cs),
              ),
              if (!isLast)
                Divider(
                    height: 1,
                    color: cs.outline.withValues(alpha: 0.08),
                    indent: 16,
                    endIndent: 16),
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
    switch (item.type) {
      case AdminActivityType.harvest:   return AppConstants.primaryGreen;
      case AdminActivityType.listing:   return item.isPrimary ? AppConstants.successGreen : AppConstants.primaryGreen;
      case AdminActivityType.member:    return AppConstants.primaryGreen;
      case AdminActivityType.order:     return cs.outline;
      case AdminActivityType.loan:      return AppConstants.errorRed;
      case AdminActivityType.price:     return cs.outline;
      case AdminActivityType.inventory: return AppConstants.warningAmber;
      case AdminActivityType.program:   return AppConstants.programPurple;
      case AdminActivityType.cropRequest: return AppConstants.warningAmber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final desc = item.description;
    final name = item.highlightedName;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12),
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
                  shape: BoxShape.circle),
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
                        cs: cs)
                    : Text(desc,
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            color: cs.onSurface)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      item.timeLabel,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: cs.onSurfaceVariant),
                    ),
                    if (item.referenceId != null) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded,
                          size: 12,
                          color: cs.onSurfaceVariant),
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
        style:
            GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusXl),
          border: Border.all(
              color: cs.outline.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'COOPERATIVE PERFORMANCE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                      'View Reports →',
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
            Row(
              children: [
                _StatPill('Harvests',
                    '${summary.totalHarvests}', cs),
                const SizedBox(width: 12),
                _StatPill('Farmer Stock',
                    '${summary.totalStockKg.toStringAsFixed(0)} kg',
                    cs),
                const SizedBox(width: 12),
                _StatPill('Listings',
                    '${summary.activeListings}', cs),
                const SizedBox(width: 12),
                _StatPill('Sales (all-time)',
                    '${summary.completedSales}', cs),
              ],
            ),
            const SizedBox(height: 16),
            Divider(
                color: cs.outline.withValues(alpha: 0.12)),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                style: GoogleFonts.inter(
                    fontSize: 13,
                    color: cs.onSurfaceVariant),
                children: [
                  const TextSpan(text: 'Member participation: '),
                  TextSpan(
                    text:
                        '${summary.activeMembersThisSeason} of ${summary.totalMembers} members',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  const TextSpan(text: ' active this season.'),
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
                valueColor:
                    AlwaysStoppedAnimation(cs.primary),
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
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.primary,
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
  final Color? iconColor;
  final ColorScheme? cs;

  const _SectionHeader(
      {required this.label, this.icon, this.iconColor, this.cs});

  @override
  Widget build(BuildContext context) {
    final scheme = cs ?? Theme.of(context).colorScheme;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: iconColor ?? scheme.primary),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ShimmerBlock extends StatelessWidget {
  final double height;
  const _ShimmerBlock({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
        borderRadius:
            BorderRadius.circular(AppConstants.radiusLg),
      ),
    );
  }
}