import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../widgets/admin_top_bar.dart';
import '../../widgets/app_navigation_drawer.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../data/services/admin_profile_state_service.dart';
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
  PerformanceSummary _summary = PerformanceSummary.empty();
  PerformanceSummary _previousSummary = PerformanceSummary.empty();
  QuickInsights _insights = QuickInsights.empty();
  int _lowStockCount = 0;
  List<ExportHistoryEntry> _recentExports = [];
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
      drawer: AnimatedBuilder(
        animation: AdminProfileStateService.instance,
        builder: (context, _) {
          final profile = AdminProfileStateService.instance.profile;
          return AppNavigationDrawer(
            photoUrl: profile?.profilePhotoUrl,
            displayName: profile?.fullName ?? 'Admin',
            contactEmail: profile?.contactEmail ?? profile?.email,
            phoneNumber: profile?.phoneNumber,
            onEditProfile: () {
              Navigator.pop(context);
              context.push(AppRoutes.adminEditProfile);
            },
            onSignOut: () => confirmAdminSignOut(context),
            onAboutSagana: () => context.push(AppRoutes.aboutSagana),
            onAboutOrganization: () => context.push(AppRoutes.aboutCooperative),
            onPrivacyPolicy: () => context.push(AppRoutes.privacyPolicy),
            onTermsOfUse: () => context.push(AppRoutes.termsOfUse),
          );
        },
      ),
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
                  _buildQuickInsights(context, l10n, cs, sagana),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  _buildSectionTitle(l10n.reportsDetailedReports, cs),
                  const SizedBox(height: AppConstants.spacingSm),
                  _buildDetailedReportsGrid(context, l10n, cs, sagana),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  // Renamed from "Reporting Tools" (Phase 14) — that name
                  // didn't fit a section containing Analytics, Balik-
                  // Tangkilik Management, and Export Center. Reuses the
                  // pre-existing reportsManagementTools l10n key, which
                  // already had both English and Tagalog strings defined
                  // but was never wired up to any screen.
                  _buildSectionTitle(l10n.reportsManagementTools, cs),
                  const SizedBox(height: AppConstants.spacingSm),
                  _buildReportingToolsRow(context, l10n, cs, sagana),
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
              label: Text(reportPeriodLabel(l10n, p), style: GoogleFonts.inter(fontSize: 12)),
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
          icon: Icons.storefront_rounded,
          accent: AppConstants.primaryGreen,
        ),
        ReportHeroStat(
          label: l10n.reportsTotalHarvest,
          value: '${_summary.totalHarvestKg.toStringAsFixed(0)} kg',
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
          label: l10n.reportsActiveLoans,
          value: currency.format(_summary.activeLoanOutstanding),
          current: _summary.activeLoanOutstanding,
          previous: _previousSummary.activeLoanOutstanding,
          icon: Icons.request_page_rounded,
          accent: AppConstants.errorRed,
        ),
        ReportHeroStat(
          label: l10n.reportsTotalExpenses,
          value: currency.format(_summary.totalExpenses),
          current: _summary.totalExpenses,
          previous: _previousSummary.totalExpenses,
          icon: Icons.receipt_long_rounded,
          accent: AppConstants.amber,
        ),
        ReportHeroStat(
          label: l10n.reportsMemberParticipation,
          value: '${_summary.memberParticipationPercent.toStringAsFixed(0)}%',
          current: _summary.memberParticipationPercent,
          previous: _previousSummary.memberParticipationPercent,
          icon: Icons.groups_rounded,
          accent: AppConstants.warningAmber,
        ),
      ],
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
        // A simple export count instead of a long "No exports yet..."
        // sentence when empty — the card is small, and Export Center's
        // own screen already shows the fuller history/date detail.
        previewLabel: l10n.reportsExportCount,
        previewValue: '${_recentExports.length}',
      ),
    ];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tools.length; i++) ...[
            if (i > 0) const SizedBox(width: AppConstants.spacingSm),
            Expanded(child: _reportCard(context, tools[i], cs, sagana)),
          ],
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