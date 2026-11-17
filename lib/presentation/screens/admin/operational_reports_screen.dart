import 'package:flutter/material.dart';
import '../../../core/utils/quantity_utils.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/dashboard_cards.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../widgets/admin_top_bar.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../data/services/hive_service.dart';
import '../../../routes/app_routes.dart';
import '../../../data/models/admin_analytics_model.dart';
import '../../../data/repositories/admin_analytics_repository.dart';
import '../../widgets/report_summary_widgets.dart';

/// Operational Reports — Admin hub.
/// Shell tab landing screen (branch 4, adminReportsKey). No back button.
/// Route: /admin/reports (NEW — see router edit below; this used to be
/// mapped to AppRoutes.adminAnalytics, which is now repointed to the
/// actual Analytics Dashboard screen instead).
class OperationalReportsScreen extends StatefulWidget {
  const OperationalReportsScreen({super.key});

  @override
  State<OperationalReportsScreen> createState() =>
      _OperationalReportsScreenState();
}

class _OperationalReportsScreenState extends State<OperationalReportsScreen> {
  final _repo = AdminReportsRepository();
  final _analyticsRepo = AdminAnalyticsRepository();

  ReportPeriod _period = ReportPeriod.thisMonth;
  bool _isLoading = true;
  bool _isOnline = ConnectivityService.instance.isOnline;
  PerformanceSummary _summary = PerformanceSummary.empty();
  PerformanceSummary _previousSummary = PerformanceSummary.empty();
  QuickInsights _insights = QuickInsights.empty();
  int _lowStockCount = 0;
  List<ExportHistoryEntry> _recentExports = [];
  MemberParticipationSummary _participation =
      MemberParticipationSummary.empty();

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchPerformanceSummary(_period),
      _repo.fetchPreviousPeriodSummary(_period),
      _repo.fetchQuickInsights(_period),
      Future.value(HiveService.getExportHistory()),
      _repo.fetchLowStockCount(),
      _analyticsRepo.fetchMemberParticipation(),
    ]);
    if (!mounted) return;
    setState(() {
      _summary = results[0] as PerformanceSummary;
      _previousSummary = results[1] as PerformanceSummary;
      _insights = results[2] as QuickInsights;
      _recentExports = (results[3] as List<Map<String, dynamic>>)
          .map(ExportHistoryEntry.fromMap)
          .toList();
      _lowStockCount = results[4] as int;
      _participation = results[5] as MemberParticipationSummary;
      _isLoading = false;
    });
  }

  void _setPeriod(ReportPeriod period) {
    setState(() => _period = period);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          AdminTopBar(
            title: l10n.reportsHubTitle,
            onBroadcastTap: () => context.push(AppRoutes.announcementDashboard),
            onNotificationTap: () =>
                context.push(AppRoutes.adminNotifications).then((_) => _load()),
            onProfileTap: () => context.push(AppRoutes.adminProfile),
            enableMenu: true,
          ),
          CachedDataNotice(
            screen: AdminReportsRepository.performanceCacheScreen(_period),
            isOnline: _isOnline,
            offlineMessage: l10n.offlineStaffBody,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingSafeH,
                  AppConstants.spacingGutter,
                  AppConstants.spacingSafeH,
                  32,
                ),
                children: [
                  _buildPeriodChips(context, cs),
                  const SizedBox(height: AppConstants.spacingGutter),
                  _buildExecutiveSnapshot(context, l10n, cs),
                  // Quick Insights only appear once there is data. Its gap is
                  // part of it, so with no insights the Snapshot is followed
                  // by exactly one gap, not two stacked ones.
                  if (_hasInsights) ...[
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildQuickInsights(context, l10n, cs, sagana),
                  ],
                  const SizedBox(height: AppConstants.spacingSectionV),
                  _buildSectionTitle(l10n.reportsDetailedReports, cs),
                  const SizedBox(height: AppConstants.spacingMd),
                  _buildDetailedReportsGrid(context, l10n),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  // Renamed from "Reporting Tools" (Phase 14) — that name
                  // didn't fit a section containing Analytics and Export Center. Reuses the
                  // pre-existing reportsManagementTools l10n key, which
                  // already had both English and Tagalog strings defined
                  // but was never wired up to any screen.
                  _buildSectionTitle(l10n.reportsManagementTools, cs),
                  const SizedBox(height: AppConstants.spacingMd),
                  _buildManagementToolsGrid(context, l10n),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Top bar provided by shared AdminTopBar

  // Display order for the period chips only — deliberately independent of
  // ReportPeriod's declared enum order, in case other logic (sorting,
  // previousRange(), etc.) relies on that declaration order.
  static const _periodChipOrder = [
    ReportPeriod.allTime,
    ReportPeriod.thisMonth,
    ReportPeriod.thisQuarter,
    ReportPeriod.thisYear,
  ];

  Widget _buildPeriodChips(BuildContext context, ColorScheme cs) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _periodChipOrder.map((p) {
          final active = _period == p;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                reportPeriodLabel(l10n, p),
                style: GoogleFonts.inter(fontSize: 12),
              ),
              selected: active,
              onSelected: (_) => _setPeriod(p),
              selectedColor: AppConstants.primaryGreen,
              labelStyle: TextStyle(
                color: active ? Colors.white : cs.onSurface,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildExecutiveSnapshot(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );
    // Two connected metrics in every row (a two-column grid, so each pair shares a row):
    //   Total Sales (Farmers)   | Total Harvested (Farmers)
    //   Marketplace Revenue     | Cooperative Product Sales
    //   Completed Orders        | Active Loans (Farmers)
    //   Total Expenses (Farmers)| Member Participation (Farmers)
    return ReportHeroCard(
      title: l10n.reportsExecutiveSnapshot,
      period: _period,
      isLoading: _isLoading,
      primaryStats: [
        ReportHeroStat(
          label: l10n.reportsSnapTotalSales,
          value: currency.format(_summary.totalSalesAmount),
          current: _summary.totalSalesAmount,
          previous: _previousSummary.totalSalesAmount,
          icon: Icons.storefront_rounded,
          accent: AppConstants.primaryGreen,
        ),
        ReportHeroStat(
          label: l10n.reportsSnapTotalHarvested,
          value: formatKgTotal(_summary.totalHarvestKg),
          current: _summary.totalHarvestKg,
          previous: _previousSummary.totalHarvestKg,
          icon: Icons.agriculture_rounded,
          accent: AppConstants.successGreen,
        ),
      ],
      secondaryStats: [
        ReportHeroStat(
          label: l10n.reportsMarketplaceRevenue,
          value: currency.format(_summary.marketplaceRevenue),
          current: _summary.marketplaceRevenue,
          previous: _previousSummary.marketplaceRevenue,
          icon: Icons.point_of_sale_rounded,
          accent: AppConstants.buyerBlue,
        ),
        ReportHeroStat(
          label: l10n.reportsProductSales,
          value: currency.format(_summary.productSalesAmount),
          current: _summary.productSalesAmount,
          previous: _previousSummary.productSalesAmount,
          icon: Icons.inventory_2_rounded,
          accent: AppConstants.programPurple,
        ),
        ReportHeroStat(
          label: l10n.reportsCompletedOrders,
          value: '${_summary.completedOrders}',
          current: _summary.completedOrders.toDouble(),
          previous: _previousSummary.completedOrders.toDouble(),
          icon: Icons.task_alt_rounded,
          accent: AppConstants.midGreen,
        ),
        ReportHeroStat(
          label: l10n.reportsSnapActiveLoans,
          value: currency.format(_summary.activeLoanOutstanding),
          current: _summary.activeLoanOutstanding,
          previous: _previousSummary.activeLoanOutstanding,
          icon: Icons.request_page_rounded,
          accent: AppConstants.errorRed,
        ),
        ReportHeroStat(
          label: l10n.reportsSnapTotalExpenses,
          value: currency.format(_summary.totalExpenses),
          current: _summary.totalExpenses,
          previous: _previousSummary.totalExpenses,
          icon: Icons.receipt_long_rounded,
          accent: AppConstants.amber,
        ),
        ReportHeroStat(
          label: l10n.reportsSnapParticipation,
          value: '${_summary.memberParticipationPercent.toStringAsFixed(0)}%',
          current: _summary.memberParticipationPercent,
          previous: _previousSummary.memberParticipationPercent,
          icon: Icons.groups_rounded,
          accent: AppConstants.warningAmber,
        ),
      ],
    );
  }

  bool get _hasInsights =>
      _insights.topCropName != null ||
      _insights.topFarmerName != null ||
      _insights.topExpenseCategory != null;

  Widget _buildQuickInsights(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final chips = <Widget>[];
    if (_insights.topCropName != null) {
      chips.add(
        _insightChip(
          Icons.trending_up_rounded,
          l10n.reportsInsightTopCrop,
          '${_insights.topCropName} • ₱${_insights.topCropAmount.toStringAsFixed(0)}',
          AppConstants.successGreen,
          cs,
          sagana,
        ),
      );
    }
    if (_insights.topFarmerName != null) {
      chips.add(
        _insightChip(
          Icons.emoji_events_outlined,
          l10n.reportsInsightTopFarmer,
          '${_insights.topFarmerName} • ₱${_insights.topFarmerAmount.toStringAsFixed(0)}',
          AppConstants.amber,
          cs,
          sagana,
        ),
      );
    }
    if (_insights.topExpenseCategory != null) {
      chips.add(
        _insightChip(
          Icons.trending_down_rounded,
          l10n.reportsInsightTopExpense,
          '${_insights.topExpenseCategory} • ₱${_insights.topExpenseAmount!.toStringAsFixed(0)}',
          AppConstants.warningAmber,
          cs,
          sagana,
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.reportsQuickInsights,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        ...chips,
      ],
    );
  }

  Widget _insightChip(
    IconData icon,
    String label,
    String value,
    Color accent,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme cs) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: cs.onSurface,
      ),
    );
  }

  /// A peso amount that fits a small badge: whole pesos, or 1.2M style once
  /// it gets long.
  static String _peso(double v) => v >= 100000
      ? '₱${NumberFormat.compact().format(v)}'
      : NumberFormat.currency(
          locale: 'en_PH',
          symbol: '₱',
          decimalDigits: 0,
        ).format(v);

  /// Detailed Reports: the same two-column cards as the Dashboard's Management
  /// Modules and the Marketplace's Management section. The badge is the
  /// report's headline figure for the period chosen above.
  Widget _buildDetailedReportsGrid(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return DashboardModuleGrid(
      items: [
        DashboardModuleItem(
          icon: Icons.point_of_sale_rounded,
          title: l10n.reportsSalesReport,
          subtitle: l10n.rptHubSalesSub,
          badge: _peso(_summary.totalSalesAmount),
          onTap: () => context.push(AppRoutes.salesReport),
        ),
        DashboardModuleItem(
          icon: Icons.agriculture_rounded,
          title: l10n.reportsHarvestManagement,
          subtitle: l10n.rptHubHarvestSub,
          badge: formatKgTotal(_summary.totalHarvestKg),
          onTap: () => context.push(AppRoutes.harvestReport),
        ),
        DashboardModuleItem(
          icon: Icons.inventory_2_rounded,
          title: l10n.reportsCoopStockReport,
          subtitle: l10n.rptHubStockSub,
          badge: _lowStockCount > 0
              ? l10n.rptHubBadgeLowStock(_lowStockCount)
              : l10n.rptHubBadgeStockOk,
          onTap: () => context.push(AppRoutes.coopStockReport),
        ),
        DashboardModuleItem(
          icon: Icons.request_page_rounded,
          title: l10n.reportsLoanReport,
          subtitle: l10n.rptHubLoanSub,
          badge: l10n.rptHubBadgeOwed(_peso(_summary.activeLoanOutstanding)),
          onTap: () => context.push(AppRoutes.loanReport),
        ),
        DashboardModuleItem(
          icon: Icons.receipt_long_rounded,
          title: l10n.reportsExpenseReport,
          subtitle: l10n.rptHubExpenseSub,
          badge: _peso(_summary.totalExpenses),
          onTap: () => context.push(AppRoutes.expenseReport),
        ),
        DashboardModuleItem(
          icon: Icons.groups_rounded,
          title: l10n.reportsMemberContributionReport,
          subtitle: l10n.rptHubPatronageSub,
          badge: l10n.rptHubBadgeActive(
            _summary.memberParticipationPercent.toStringAsFixed(0),
          ),
          onTap: () => context.push(AppRoutes.memberContributionReport),
        ),
      ],
    );
  }

  /// Management Tools: Analytics Dashboard and Export Center, the same cards
  /// again, in one fixed row for Manager and Officer alike.
  Widget _buildManagementToolsGrid(BuildContext context, AppLocalizations l10n) {
    final items = [
        DashboardModuleItem(
          icon: Icons.insights_rounded,
          title: l10n.reportsAnalyticsDashboard,
          subtitle: l10n.rptHubAnalyticsSub,
          badge: l10n.rptHubBadgeNoActivity(_participation.inactiveCount),
          onTap: () => context.push(AppRoutes.adminAnalytics),
        ),
        DashboardModuleItem(
          icon: Icons.file_download_rounded,
          title: l10n.reportsExportCenter,
          subtitle: l10n.rptHubExportSub,
          badge: l10n.rptHubBadgeExports(_recentExports.length),
          onTap: () => context.push(AppRoutes.exportCenter),
        ),
    ];
    return DashboardModuleGrid(items: items);
  }
}
