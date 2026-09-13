import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../widgets/admin_top_bar.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../data/services/hive_service.dart';
import '../../../routes/app_routes.dart';
import '../../../data/models/admin_loan_model.dart';
import '../../../data/models/admin_analytics_model.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/repositories/admin_analytics_repository.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/app_dialog.dart';

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
  final _loanRepo = AdminLoanRepository();
  final _analyticsRepo = AdminAnalyticsRepository();

  ReportPeriod _period = ReportPeriod.thisMonth;
  bool _isLoading = true;
  bool _isSendingReminders = false;
  PerformanceSummary _summary = PerformanceSummary.empty();
  PerformanceSummary _previousSummary = PerformanceSummary.empty();
  QuickInsights _insights = QuickInsights.empty();
  int _lowStockCount = 0;
  List<ExportHistoryEntry> _recentExports = [];
  LoanDashboardStats _loanStats = LoanDashboardStats.empty();
  MemberParticipationSummary _participation = MemberParticipationSummary.empty();

  @override
  void initState() {
    super.initState();
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
      _loanRepo.fetchDashboardStats(),
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
      _loanStats = results[5] as LoanDashboardStats;
      _participation = results[6] as MemberParticipationSummary;
      _isLoading = false;
    });
  }

  Future<void> _confirmAndSendReminders(AppLocalizations l10n) async {
    final count = _participation.inactiveCount;
    if (count == 0) return;

    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: AlertDialog(
        title: Text(
          l10n.analyticsSendReminderTitle,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Text(
          l10n.analyticsSendReminderMessage(count),
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.issueLoanCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.analyticsSendReminderConfirm,
              style: const TextStyle(color: AppConstants.primaryGreen),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSendingReminders = true);
    try {
      await _analyticsRepo.sendReminders(
        farmerIds: _participation.inactiveFarmers.map((f) => f.id).toList(),
        title: l10n.analyticsReminderNotifTitle,
        body: l10n.analyticsReminderNotifBody,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.analyticsReminderSent(count))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.analyticsReminderError)),
      );
    } finally {
      if (mounted) setState(() => _isSendingReminders = false);
    }
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
                  const SizedBox(height: AppConstants.spacingSectionV),
                  _buildSectionTitle(l10n.reportsNeedsAttention, cs),
                  const SizedBox(height: AppConstants.spacingSm),
                  _buildNeedsAttention(context, l10n, cs, sagana),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  _buildQuickInsights(context, l10n, cs, sagana),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  _buildSectionTitle(l10n.reportsDetailedReports, cs),
                  const SizedBox(height: AppConstants.spacingSm),
                  _buildDetailedReportsGrid(context, l10n, cs, sagana),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  _buildSectionTitle(l10n.reportsReportingTools, cs),
                  const SizedBox(height: AppConstants.spacingSm),
                  _buildReportingToolsRow(context, l10n, cs, sagana),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  _buildSectionTitle(l10n.reportsExportHistory, cs),
                  const SizedBox(height: AppConstants.spacingSm),
                  _buildExportHistory(context, l10n, cs),
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
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _periodChipOrder.map((p) {
          final active = _period == p;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(p.label, style: GoogleFonts.inter(fontSize: 12)),
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
    return ReportHeroCard(
      title: l10n.reportsExecutiveSnapshot,
      period: _period,
      isLoading: _isLoading,
      primaryStats: [
        ReportHeroStat(
          label: l10n.reportsCoopSales,
          value: currency.format(_summary.coopSalesAmount),
          current: _summary.coopSalesAmount,
          previous: _previousSummary.coopSalesAmount,
        ),
        ReportHeroStat(
          label: l10n.reportsTotalHarvest,
          value: '${_summary.totalHarvestKg.toStringAsFixed(0)} kg',
          current: _summary.totalHarvestKg,
          previous: _previousSummary.totalHarvestKg,
        ),
      ],
      secondaryStats: [
        ReportHeroStat(
          label: l10n.reportsMarketplaceRevenue,
          value: currency.format(_summary.marketplaceRevenue),
          current: _summary.marketplaceRevenue,
          previous: _previousSummary.marketplaceRevenue,
        ),
        ReportHeroStat(
          label: l10n.reportsActiveLoans,
          value: currency.format(_summary.activeLoanOutstanding),
          current: _summary.activeLoanOutstanding,
          previous: _previousSummary.activeLoanOutstanding,
        ),
        ReportHeroStat(
          label: l10n.reportsTotalExpenses,
          value: currency.format(_summary.totalExpenses),
          current: _summary.totalExpenses,
          previous: _previousSummary.totalExpenses,
        ),
        ReportHeroStat(
          label: l10n.reportsMemberParticipation,
          value: '${_summary.memberParticipationPercent.toStringAsFixed(0)}%',
          current: _summary.memberParticipationPercent,
          previous: _previousSummary.memberParticipationPercent,
        ),
      ],
    );
  }

  /// Needs Attention — pulls together signals already computed elsewhere
  /// (low stock, overdue loans, inactive members) so an admin sees "where
  /// do I look first" without opening three separate screens.
  Widget _buildNeedsAttention(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );
    final items = <_AttentionItem>[];

    if (_lowStockCount > 0) {
      items.add(_AttentionItem(
        icon: Icons.inventory_2_rounded,
        label: l10n.reportsLowStockItems,
        value: '$_lowStockCount',
        color: AppConstants.errorRed,
        onTap: () => context.push(AppRoutes.coopStockReport),
      ));
    }
    if (_loanStats.overdueLoansCount > 0) {
      items.add(_AttentionItem(
        icon: Icons.request_page_rounded,
        label: l10n.reportsOverdueLoans,
        value:
            '${_loanStats.overdueLoansCount} • ${currency.format(_loanStats.totalOverdueAmount)}',
        color: AppConstants.errorRed,
        onTap: () => context.push(AppRoutes.loanReport),
      ));
    }
    if (_participation.inactiveCount > 0) {
      items.add(_AttentionItem(
        icon: Icons.person_off_rounded,
        label: l10n.reportsInactiveMembers,
        value: '${_participation.inactiveCount}',
        color: AppConstants.warningAmber,
        trailingAction: TextButton(
          onPressed: _isSendingReminders
              ? null
              : () => _confirmAndSendReminders(l10n),
          child: _isSendingReminders
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  l10n.analyticsSendReminder(_participation.inactiveCount),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ));
    }

    if (items.isEmpty) {
      return ReportEmptyState(message: l10n.reportsAllClear);
    }
    return Column(children: items.map((i) => _attentionRow(i, cs, sagana)).toList());
  }

  Widget _attentionRow(_AttentionItem item, ColorScheme cs, SaganaColors sagana) {
    return GestureDetector(
      onTap: item.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: item.color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(item.icon, size: 18, color: item.color),
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  Text(
                    item.value,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (item.trailingAction != null)
              item.trailingAction!
            else if (item.onTap != null)
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickInsights(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final chips = <Widget>[];
    if (_insights.topCropName != null) {
      chips.add(_insightChip(
        Icons.trending_up_rounded,
        l10n.reportsInsightTopCrop,
        '${_insights.topCropName} • ₱${_insights.topCropAmount.toStringAsFixed(0)}',
        AppConstants.successGreen,
        cs,
        sagana,
      ));
    }
    if (_insights.topFarmerName != null) {
      chips.add(_insightChip(
        Icons.emoji_events_outlined,
        l10n.reportsInsightTopFarmer,
        '${_insights.topFarmerName} • ₱${_insights.topFarmerAmount.toStringAsFixed(0)}',
        AppConstants.amber,
        cs,
        sagana,
      ));
    }
    if (_insights.topExpenseCategory != null) {
      chips.add(_insightChip(
        Icons.trending_down_rounded,
        l10n.reportsInsightTopExpense,
        '${_insights.topExpenseCategory} • ₱${_insights.topExpenseAmount!.toStringAsFixed(0)}',
        AppConstants.warningAmber,
        cs,
        sagana,
      ));
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
                  style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
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

  Widget _buildDetailedReportsGrid(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final reports = <_ReportCardData>[
      _ReportCardData(
        l10n.reportsSalesReport,
        Icons.point_of_sale_rounded,
        AppRoutes.salesReport,
        previewLabel: l10n.reportsCoopSales,
        previewValue: '₱${_summary.coopSalesAmount.toStringAsFixed(0)}',
        accent: AppConstants.primaryGreen,
      ),
      _ReportCardData(
        l10n.reportsHarvestManagement,
        Icons.agriculture_rounded,
        AppRoutes.harvestReport,
        previewLabel: l10n.reportsTotalHarvest,
        previewValue: '${_summary.totalHarvestKg.toStringAsFixed(0)} kg',
        accent: AppConstants.successGreen,
      ),
      _ReportCardData(
        l10n.reportsCoopStockReport,
        Icons.inventory_2_rounded,
        AppRoutes.coopStockReport,
        previewLabel: l10n.reportsLowStockItems,
        previewValue: '$_lowStockCount',
        accent: _lowStockCount > 0
            ? AppConstants.errorRed
            : AppConstants.buyerBlue,
      ),
      _ReportCardData(
        l10n.reportsLoanReport,
        Icons.request_page_rounded,
        AppRoutes.loanReport,
        previewLabel: l10n.reportsActiveLoans,
        previewValue: '₱${_summary.activeLoanOutstanding.toStringAsFixed(0)}',
        accent: _summary.activeLoanOutstanding > 0
            ? AppConstants.errorRed
            : AppConstants.successGreen,
      ),
      _ReportCardData(
        l10n.reportsExpenseReport,
        Icons.receipt_long_rounded,
        AppRoutes.expenseReport,
        previewLabel: l10n.reportsTotalExpenses,
        previewValue: '₱${_summary.totalExpenses.toStringAsFixed(0)}',
        accent: AppConstants.amber,
      ),
      _ReportCardData(
        l10n.reportsMemberContributionReport,
        Icons.groups_rounded,
        AppRoutes.memberContributionReport,
        previewLabel: l10n.reportsMemberParticipation,
        previewValue:
            '${_summary.memberParticipationPercent.toStringAsFixed(0)}%',
        accent: AppConstants.buyerBlue,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppConstants.spacingMd,
      crossAxisSpacing: AppConstants.spacingMd,
      childAspectRatio: 1.05,
      children: reports
          .map((r) => _reportCard(context, r, cs, sagana))
          .toList(),
    );
  }

  Widget _reportCard(
    BuildContext context,
    _ReportCardData data,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return GestureDetector(
      onTap: () => context.push(data.route),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(data.icon, color: AppConstants.primaryGreen, size: 22),
            const SizedBox(height: AppConstants.spacingSm),
            Text(
              data.label,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: cs.onSurface,
              ),
            ),
            if (data.previewLabel != null && data.previewValue != null) ...[
              const SizedBox(height: AppConstants.spacingSm),
              Text(
                data.previewLabel!,
                style: GoogleFonts.inter(fontSize: 9, color: cs.onSurfaceVariant),
              ),
              Text(
                data.previewValue!,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: data.accent ?? AppConstants.primaryGreen,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReportingToolsRow(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final tools = <_ReportCardData>[
      _ReportCardData(
        l10n.reportsAnalyticsDashboard,
        Icons.insights_rounded,
        AppRoutes.adminAnalytics,
        previewLabel: l10n.reportsInactiveMembers,
        previewValue: '${_participation.inactiveCount}',
        accent: _participation.inactiveCount > 0
            ? AppConstants.warningAmber
            : AppConstants.successGreen,
      ),
      _ReportCardData(
        l10n.reportsBalikTangkilikManagement,
        Icons.volunteer_activism_rounded,
        AppRoutes.balikTangkilikManagement,
      ),
      _ReportCardData(
        l10n.reportsExportCenter,
        Icons.file_download_rounded,
        AppRoutes.exportCenter,
        previewLabel: l10n.reportsLastExport,
        previewValue: _recentExports.isEmpty
            ? l10n.reportsNoExportsYet
            : DateFormat('MMM d').format(_recentExports.first.generatedAt),
      ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < tools.length; i++) ...[
          if (i > 0) const SizedBox(width: AppConstants.spacingMd),
          Expanded(child: _reportCard(context, tools[i], cs, sagana)),
        ],
      ],
    );
  }

  Widget _buildExportHistory(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final recent = _recentExports.take(3).toList();
    if (recent.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppConstants.spacingGutter),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Text(
          l10n.reportsNoExportsYet,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }

    return Column(
      children: [
        ...recent.map((entry) => _recentExportRow(entry, cs)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.push(AppRoutes.exportCenter),
            child: Text(l10n.reportsViewAllExports, style: GoogleFonts.inter(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _recentExportRow(ExportHistoryEntry entry, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.fileName,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12, color: cs.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            '${entry.periodLabel} • ${DateFormat('MMM d, h:mm a').format(entry.generatedAt)}',
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ReportCardData {
  final String label;
  final IconData icon;
  final String route;
  final String? previewLabel;
  final String? previewValue;
  final Color? accent;
  const _ReportCardData(
    this.label,
    this.icon,
    this.route, {
    this.previewLabel,
    this.previewValue,
    this.accent,
  });
}

class _AttentionItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailingAction;
  const _AttentionItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
    this.trailingAction,
  });
}