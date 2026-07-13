import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../widgets/admin_top_bar.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../routes/app_routes.dart';

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

  ReportPeriod _period = ReportPeriod.thisMonth;
  bool _isLoading = true;
  PerformanceSummary _summary = PerformanceSummary.empty();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final summary = await _repo.fetchPerformanceSummary(_period);
    if (!mounted) return;
    setState(() {
      _summary = summary;
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
            onNotificationTap: () => context.push(AppRoutes.adminNotifications).then((_) => _load()),
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
                  _buildSummaryCard(context, l10n, cs),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  _buildSectionTitle(l10n.reportsDetailedReports, cs),
                  const SizedBox(height: AppConstants.spacingSm),
                  _buildDetailedReportsGrid(context, l10n, cs, sagana),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  _buildSectionTitle(l10n.reportsManagementTools, cs),
                  const SizedBox(height: AppConstants.spacingSm),
                  _buildManagementToolsList(context, l10n, cs, sagana),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  _buildSectionTitle(l10n.reportsRecentReports, cs),
                  const SizedBox(height: AppConstants.spacingSm),
                  _buildRecentReportsEmptyState(l10n, cs),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Top bar provided by shared AdminTopBar

  Widget _buildPeriodChips(BuildContext context, ColorScheme cs) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: ReportPeriod.values.map((p) {
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

  Widget _buildSummaryCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        gradient: AppConstants.primaryButtonGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.reportsPerformanceSummary,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          _isLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              : GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppConstants.spacingMd,
                  crossAxisSpacing: AppConstants.spacingMd,
                  childAspectRatio: 2.2,
                  children: [
                    _summaryStat(
                      l10n.reportsTotalHarvest,
                      '${_summary.totalHarvestKg.toStringAsFixed(0)} kg',
                    ),
                    _summaryStat(
                      l10n.reportsCoopSales,
                      currency.format(_summary.coopSalesAmount),
                    ),
                    _summaryStat(
                      l10n.reportsMarketplaceRevenue,
                      currency.format(_summary.marketplaceRevenue),
                    ),
                    _summaryStat(
                      l10n.reportsActiveLoans,
                      currency.format(_summary.activeLoanOutstanding),
                    ),
                    _summaryStat(
                      l10n.reportsTotalExpenses,
                      currency.format(_summary.totalExpenses),
                    ),
                    _summaryStat(
                      l10n.reportsMemberParticipation,
                      '${_summary.memberParticipationPercent.toStringAsFixed(0)}%',
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, color: Colors.white70),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Colors.white,
          ),
        ),
      ],
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
      ),
      _ReportCardData(
        l10n.reportsInventoryReport,
        Icons.inventory_2_rounded,
        AppRoutes.inventoryReport,
      ),
      _ReportCardData(
        l10n.reportsLoanReport,
        Icons.request_page_rounded,
        AppRoutes.loanReport,
      ),
      _ReportCardData(
        l10n.reportsHarvestReport,
        Icons.agriculture_rounded,
        AppRoutes.harvestReport,
      ),
      _ReportCardData(
        l10n.reportsExpenseReport,
        Icons.receipt_long_rounded,
        AppRoutes.expenseReport,
      ),
      _ReportCardData(
        l10n.reportsMemberContributionReport,
        Icons.groups_rounded,
        AppRoutes.memberContributionReport,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppConstants.spacingMd,
      crossAxisSpacing: AppConstants.spacingMd,
      childAspectRatio: 1.35,
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(data.icon, color: AppConstants.primaryGreen, size: 22),
            Text(
              data.label,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManagementToolsList(
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
      ),
    ];

    return Column(
      children: tools
          .map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
              child: GestureDetector(
                onTap: () => context.push(t.route),
                child: Container(
                  padding: const EdgeInsets.all(AppConstants.spacingMd),
                  decoration: BoxDecoration(
                    color: sagana.cardBackground,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    border: Border.all(
                      color: cs.outline.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(t.icon, color: AppConstants.primaryGreen, size: 20),
                      const SizedBox(width: AppConstants.spacingMd),
                      Expanded(
                        child: Text(
                          t.label,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildRecentReportsEmptyState(AppLocalizations l10n, ColorScheme cs) {
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
}

class _ReportCardData {
  final String label;
  final IconData icon;
  final String route;
  const _ReportCardData(this.label, this.icon, this.route);
}
