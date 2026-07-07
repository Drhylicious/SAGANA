import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_dashboard_model.dart';
import '../../../data/repositories/admin_dashboard_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import 'package:go_router/go_router.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _repo = AdminDashboardRepository();

  AdminKpiSummary _kpi = AdminKpiSummary.empty;
  List<UrgentAction> _urgentActions = [];
  BodMeetingInfo? _bodInfo;
  List<AdminActivityItem> _activity = [];
  CoopPerformanceSummary _coopSummary = CoopPerformanceSummary.empty;
  Map<String, String> _toolsLabels = {};
  int _unreadCount = 0;

  bool _isLoading = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppTheme.applySystemOverlay(context);
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchKpiSummary(),
      _repo.fetchUrgentActions(),
      _repo.fetchBodMeetingInfo(),
      _repo.fetchRecentActivity(),
      _repo.fetchCoopPerformance(),
      _repo.fetchToolsLastUpdated(),
      _repo.fetchUnreadCount(),
    ]);
    if (!mounted) return;
    setState(() {
      _kpi          = results[0] as AdminKpiSummary;
      _urgentActions = results[1] as List<UrgentAction>;
      _bodInfo      = results[2] as BodMeetingInfo;
      _activity     = results[3] as List<AdminActivityItem>;
      _coopSummary  = results[4] as CoopPerformanceSummary;
      _toolsLabels  = results[5] as Map<String, String>;
      _unreadCount  = results[6] as int;
      _isLoading    = false;
    });
  }

  // ── Greeting ──────────────────────────────────────────────────────────────

  String _greeting(AppLocalizations l10n) {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return l10n.greetingMorning;
    if (hour >= 12 && hour < 18) return l10n.greetingAfternoon;
    return l10n.greetingEvening;
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

  String _bodDateLabel(DateTime dt) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n    = AppLocalizations.of(context);
    final sagana  = context.saganaColors;
    final cs      = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        color: AppConstants.primaryGreen,
        onRefresh: _loadAll,
        child: CustomScrollView(
          slivers: [
            // ── Offline banner ─────────────────────────────────────────────
            if (!_isOnline)
              SliverToBoxAdapter(child: _OfflineBanner(l10n: l10n)),

            // ── Top App Bar ────────────────────────────────────────────────
            SliverPersistentHeader(
              pinned: true,
              delegate: _AdminTopBarDelegate(
                unreadCount: _unreadCount,
                onNotificationTap: () =>
                    context.push(AppRoutes.farmerNotifications),
                onProfileTap: () =>
                    context.push(AppRoutes.adminProfile),
                sagana: sagana,
                cs: cs,
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

                  // ── Greeting ─────────────────────────────────────────────
                  Text(
                    '${_greeting(l10n)}, Manager!',
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
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── BOD Banner ────────────────────────────────────────────
                  if (_bodInfo != null) ...[
                    _BodBanner(
                      info: _bodInfo!,
                      dateLabel: _bodDateLabel(_bodInfo!.nextMeetingDate),
                      onTap: () => context.push(AppRoutes.loanDashboard),
                      l10n: l10n,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Urgent Actions ────────────────────────────────────────
                  _SectionHeader(
                    icon: Icons.priority_high_rounded,
                    label: l10n.adminUrgentActions,
                    iconColor: cs.error,
                  ),
                  const SizedBox(height: 10),
                  if (_isLoading)
                    _ShimmerBlock(height: 180)
                  else
                    _UrgentActionsSection(
                      actions: _urgentActions,
                      onListingsTap: () =>
                          context.push(AppRoutes.pendingApprovals),
                      onLoansTap: () =>
                          context.push(AppRoutes.loanDashboard),
                      onStockTap: () =>
                          context.push(AppRoutes.inventoryReport),
                      cs: cs,
                      sagana: sagana,
                    ),
                  const SizedBox(height: 20),

                  // ── KPI Grid ──────────────────────────────────────────────
                  if (_isLoading)
                    _ShimmerBlock(height: 180)
                  else
                    _KpiGrid(kpi: _kpi, cs: cs, sagana: sagana),
                  const SizedBox(height: 20),

                  // ── Tools & Management ────────────────────────────────────
                  _SectionHeader(label: l10n.adminToolsManagement, cs: cs),
                  const SizedBox(height: 12),
                  _ToolsSection(
                    labels: _toolsLabels,
                    sagana: sagana,
                    cs: cs,
                    onPriceTap: () =>
                        context.push(AppRoutes.priceManagement),
                    onBroadcastTap: () =>
                        context.push(AppRoutes.announcementDashboard),
                    onMapTap: () =>
                        context.push(AppRoutes.supplyChainMap),
                    l10n: l10n,
                  ),
                  const SizedBox(height: 20),

                  // ── Recent Activity ───────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionHeader(
                          label: l10n.adminRecentActivity, cs: cs),
                      GestureDetector(
                        onTap: () {},
                        child: Text(
                          l10n.seeAll,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isLoading)
                    _ShimmerBlock(height: 280)
                  else
                    _ActivityFeed(
                        items: _activity, sagana: sagana, cs: cs),
                  const SizedBox(height: 20),

                  // ── Coop Performance ──────────────────────────────────────
                  _CoopPerformanceCard(
                      summary: _coopSummary, cs: cs, sagana: sagana, l10n: l10n),
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
// Top App Bar via SliverPersistentHeader
// ─────────────────────────────────────────────────────────────────────────────

class _AdminTopBarDelegate extends SliverPersistentHeaderDelegate {
  final int unreadCount;
  final VoidCallback onNotificationTap;
  final VoidCallback onProfileTap;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _AdminTopBarDelegate({
    required this.unreadCount,
    required this.onNotificationTap,
    required this.onProfileTap,
    required this.sagana,
    required this.cs,
  });

  @override
  double get minExtent => 64;
  @override
  double get maxExtent => 64;
  @override
  bool shouldRebuild(covariant _AdminTopBarDelegate old) =>
      old.unreadCount != unreadCount;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(
              bottom: BorderSide(
                color: sagana.glassBorder,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Profile avatar
              GestureDetector(
                onTap: onProfileTap,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppConstants.primaryContainer,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.80),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: AppConstants.onPrimaryContainer,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // SAGANA + Admin badge
              Row(
                children: [
                  Text(
                    'SAGANA',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppConstants.amber,
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull),
                    ),
                    child: Text(
                      'Admin',
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppConstants.charcoal,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Notification bell
              GestureDetector(
                onTap: onNotificationTap,
                child: Stack(
                  children: [
                    Icon(
                      Icons.notifications_outlined,
                      color: cs.primary,
                      size: 26,
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppConstants.errorRed,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offline Banner
// ─────────────────────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  final AppLocalizations l10n;
  const _OfflineBanner({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppConstants.warningAmber,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 14, color: AppConstants.charcoal),
          const SizedBox(width: 6),
          Text(
            l10n.offlineBanner,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppConstants.charcoal,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOD Banner
// ─────────────────────────────────────────────────────────────────────────────

class _BodBanner extends StatelessWidget {
  final BodMeetingInfo info;
  final String dateLabel;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  const _BodBanner({
    required this.info,
    required this.dateLabel,
    required this.onTap,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [AppConstants.primaryGreen, AppConstants.primaryContainer],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primaryGreen.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BOD Meeting — $dateLabel',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${info.farmersWithOutstandingLoans} farmers have outstanding loan balances.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: AppConstants.secondaryContainer,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMd),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                l10n.adminGoToLoanPayments,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.charcoal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Urgent Actions
// ─────────────────────────────────────────────────────────────────────────────

class _UrgentActionsSection extends StatelessWidget {
  final List<UrgentAction> actions;
  final VoidCallback onListingsTap;
  final VoidCallback onLoansTap;
  final VoidCallback onStockTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _UrgentActionsSection({
    required this.actions,
    required this.onListingsTap,
    required this.onLoansTap,
    required this.onStockTap,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: actions.map((action) {
        VoidCallback onTap;
        IconData icon;
        Color iconColor;
        Color iconBg;

        switch (action.type) {
          case UrgentActionType.pendingListings:
            onTap = onListingsTap;
            icon = Icons.inventory_2_outlined;
            iconColor = cs.primary;
            iconBg = cs.surfaceContainerHighest;
            break;
          case UrgentActionType.overdueLoans:
            onTap = onLoansTap;
            icon = Icons.warning_amber_rounded;
            iconColor = cs.error;
            iconBg = cs.errorContainer.withValues(alpha: 0.30);
            break;
          case UrgentActionType.lowStock:
            onTap = onStockTap;
            icon = Icons.inventory_rounded;
            iconColor = AppConstants.warningAmber;
            iconBg = AppConstants.warningAmber.withValues(alpha: 0.10);
            break;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _ActionCard(
            action: action,
            icon: icon,
            iconColor: iconColor,
            iconBg: iconBg,
            onTap: onTap,
            sagana: sagana,
            cs: cs,
          ),
        );
      }).toList(),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final UrgentAction action;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final VoidCallback onTap;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _ActionCard({
    required this.action,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.onTap,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: cs.outline.withValues(alpha: 0.10),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
            ),
          ],
        ),
        padding: action.isCritical
            ? const EdgeInsets.fromLTRB(12, 14, 16, 14)
            : const EdgeInsets.all(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (action.isCritical)
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppConstants.radiusLg),
                      bottomLeft: Radius.circular(AppConstants.radiusLg),
                    ),
                  ),
                ),
              if (action.isCritical) const SizedBox(width: 12),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle,
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
                color: action.isCritical ? cs.error : cs.outline,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI Grid
// ─────────────────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  final AdminKpiSummary kpi;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _KpiGrid({required this.kpi, required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _KpiData(
        label: 'Active Members',
        value: '${kpi.activeMembers}',
        delta: '+2',
        deltaPositive: true,
        barPercent: kpi.activeMembers / kpi.totalMembersTarget,
        barColor: AppConstants.successGreen,
      ),
      _KpiData(
        label: 'Total Stock (kg)',
        value: _formatNumber(kpi.totalStockKg),
        delta: '',
        deltaPositive: true,
        barPercent: 0.60,
        barColor: AppConstants.warningAmber,
      ),
      _KpiData(
        label: 'Pending Orders',
        value: '${kpi.pendingOrders}',
        delta: '',
        deltaPositive: true,
        barPercent: kpi.pendingOrders > 0
            ? (kpi.pendingOrders / 20).clamp(0.0, 1.0)
            : 0,
        barColor: cs.primary,
      ),
      _KpiData(
        label: 'Total Revenue',
        value: '₱${_formatNumber(kpi.totalRevenueThisMonth)}',
        delta: 'This Month',
        deltaPositive: true,
        barPercent: 0,
        barColor: cs.primary,
        isRevenue: true,
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: cards.map((d) => _KpiCard(data: d, cs: cs, sagana: sagana)).toList(),
    );
  }

  String _formatNumber(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }
}

class _KpiData {
  final String label;
  final String value;
  final String delta;
  final bool deltaPositive;
  final double barPercent;
  final Color barColor;
  final bool isRevenue;

  const _KpiData({
    required this.label,
    required this.value,
    required this.delta,
    required this.deltaPositive,
    required this.barPercent,
    required this.barColor,
    this.isRevenue = false,
  });
}

class _KpiCard extends StatelessWidget {
  final _KpiData data;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _KpiCard(
      {required this.data, required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border:
            Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            data.label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  data.value,
                  style: GoogleFonts.poppins(
                    fontSize: data.isRevenue ? 16 : 22,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (data.delta.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  data.delta,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: data.isRevenue
                        ? cs.onSurfaceVariant
                        : (data.deltaPositive
                            ? AppConstants.successGreen
                            : cs.error),
                  ),
                ),
              ],
            ],
          ),
          if (!data.isRevenue && data.barPercent > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: data.barPercent,
                minHeight: 5,
                backgroundColor:
                    cs.surfaceContainerHighest,
                valueColor:
                    AlwaysStoppedAnimation(data.barColor),
              ),
            )
          else if (data.isRevenue)
            Text(
              data.delta,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tools & Management
// ─────────────────────────────────────────────────────────────────────────────

class _ToolsSection extends StatelessWidget {
  final Map<String, String> labels;
  final SaganaColors sagana;
  final ColorScheme cs;
  final VoidCallback onPriceTap;
  final VoidCallback onBroadcastTap;
  final VoidCallback onMapTap;
  final AppLocalizations l10n;

  const _ToolsSection({
    required this.labels,
    required this.sagana,
    required this.cs,
    required this.onPriceTap,
    required this.onBroadcastTap,
    required this.onMapTap,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final tools = [
      _ToolData(
        icon: Icons.sell_outlined,
        title: l10n.adminPriceManagement,
        subtitle: l10n.adminPriceManagementSubtitle,
        lastUpdated: labels['price'] ?? '—',
        onTap: onPriceTap,
      ),
      _ToolData(
        icon: Icons.campaign_outlined,
        title: l10n.adminNotificationBroadcast,
        subtitle: l10n.adminNotificationBroadcastSubtitle,
        lastUpdated: labels['broadcast'] ?? '—',
        onTap: onBroadcastTap,
      ),
      _ToolData(
        icon: Icons.map_outlined,
        title: l10n.adminSupplyChainMap,
        subtitle: l10n.adminSupplyChainMapSubtitle,
        lastUpdated: labels['map'] ?? '—',
        onTap: onMapTap,
      ),
    ];

    return Column(
      children: tools
          .map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ToolRow(data: t, sagana: sagana, cs: cs),
              ))
          .toList(),
    );
  }
}

class _ToolData {
  final IconData icon;
  final String title;
  final String subtitle;
  final String lastUpdated;
  final VoidCallback onTap;

  const _ToolData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.lastUpdated,
    required this.onTap,
  });
}

class _ToolRow extends StatelessWidget {
  final _ToolData data;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _ToolRow(
      {required this.data, required this.sagana, required this.cs});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: data.onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusLg),
          border:
              Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Icon(data.icon, color: cs.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    data.subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.lastUpdated,
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: cs.outline, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Activity Feed
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityFeed extends StatelessWidget {
  final List<AdminActivityItem> items;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _ActivityFeed(
      {required this.items, required this.sagana, required this.cs});

  @override
  Widget build(BuildContext context) {
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
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final isLast = i == items.length - 1;

          return Column(
            children: [
              _ActivityRow(item: item, cs: cs),
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
    switch (item.type) {
      case AdminActivityType.harvest:
        return AppConstants.primaryGreen;
      case AdminActivityType.listing:
        return item.isPrimary
            ? AppConstants.successGreen
            : AppConstants.primaryGreen;
      case AdminActivityType.order:
        return cs.surfaceContainerHighest;
      case AdminActivityType.loan:
        return cs.surfaceContainerHighest;
      case AdminActivityType.price:
        return cs.surfaceContainerHighest;
      case AdminActivityType.member:
        return AppConstants.primaryGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Build rich text: highlight the name in bold
    final description = item.description;
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
                name != null && description.contains(name)
                    ? _RichDescription(
                        description: description,
                        boldName: name,
                        cs: cs,
                      )
                    : Text(
                        description,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: cs.onSurface,
                        ),
                      ),
                const SizedBox(height: 2),
                Text(
                  item.timeLabel,
                  style: GoogleFonts.inter(
                    fontSize: 11,
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
  final ColorScheme cs;
  final SaganaColors sagana;
  final AppLocalizations l10n;

  const _CoopPerformanceCard({
    required this.summary,
    required this.cs,
    required this.sagana,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.adminCoopPerformanceTitle.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _StatsGrid(summary: summary, cs: cs),
          const SizedBox(height: 16),
          Divider(color: cs.outline.withValues(alpha: 0.12)),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              style: GoogleFonts.inter(
                  fontSize: 13, color: cs.onSurfaceVariant),
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
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final CoopPerformanceSummary summary;
  final ColorScheme cs;

  const _StatsGrid({required this.summary, required this.cs});

  @override
  Widget build(BuildContext context) {
    final stats = [
      _StatData('Total Harvests', '${summary.totalHarvests}'),
      _StatData('Total Stock', '${summary.totalStockKg.toStringAsFixed(0)} kg'),
      _StatData('Active Listings', '${summary.activeListings}'),
      _StatData('Completed Sales', '${summary.completedSales}'),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.8,
      crossAxisSpacing: 8,
      mainAxisSpacing: 12,
      children: stats
          .map((s) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.label.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.value,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ],
              ))
          .toList(),
    );
  }
}

class _StatData {
  final String label;
  final String value;
  const _StatData(this.label, this.value);
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final ColorScheme? cs;

  const _SectionHeader({
    required this.label,
    this.icon,
    this.iconColor,
    this.cs,
  });

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

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer loading block
// ─────────────────────────────────────────────────────────────────────────────

class _ShimmerBlock extends StatelessWidget {
  final double height;
  const _ShimmerBlock({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
    );
  }
}
