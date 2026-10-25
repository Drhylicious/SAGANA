import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../data/models/admin_loan_model.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/report_ui_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../data/services/connectivity_service.dart';

/// Loan Report — Admin.
/// Pushed above the shell. Route: /admin/reports/loans
///
/// A report by reporting period: it lists the loans ISSUED in the selected
/// period and summarises exactly those loans. Status filtering is left to Loan
/// Management; here each loan simply shows its status. Reuses
/// AdminLoanRepository's fetchAllLoans() and the AdminLoanListFilter search
/// extension — the summary is computed from the same list by
/// [LoanPeriodSummary], so the headline figures always agree with the rows.
class LoanReportScreen extends StatefulWidget {
  const LoanReportScreen({super.key});

  @override
  State<LoanReportScreen> createState() => _LoanReportScreenState();
}

class _LoanReportScreenState extends State<LoanReportScreen> {
  final _repo = AdminLoanRepository();
  final _searchController = TextEditingController();

  ReportPeriod _period = ReportPeriod.thisMonth;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isOnline = ConnectivityService.instance.isOnline;

  List<double> _collectionTrend = [];
  List<AdminLoanSummary> _loans = [];

  static final _money0 = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchMonthlyCollectionTrend(),
      _repo.fetchAllLoans(
        issuedAfter: _period.startDate,
        issuedBefore: _period.range().endDate,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _collectionTrend = results[0] as List<double>;
      _loans = results[1] as List<AdminLoanSummary>;
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
    final summary = LoanPeriodSummary.fromLoans(_loans);
    final visible = _loans.applySearch(_searchQuery);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.reportsLoanReport,
            onBack: () => context.pop(),
            trailing: IconButton(
              icon: Icon(Icons.file_download_outlined, color: cs.primary),
              onPressed: () => context.push(
                AppRoutes.exportCenter,
                extra: ExportCenterArgs(
                  preselectedModule: ReportModuleType.loan,
                  period: _period,
                ),
              ),
              tooltip: l10n.reportsExportCenter,
            ),
          ),
          CachedDataNotice(
            screen: _repo.allLoansCacheScreen(
              issuedAfter: _period.startDate,
              issuedBefore: _period.range().endDate,
            ),
            isOnline: _isOnline,
            offlineMessage: l10n.offlineLoans,
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
                  ReportPeriodFilter(period: _period, onSelected: _setPeriod),
                  const SizedBox(height: AppConstants.spacingGutter),
                  _buildSummaryCard(l10n, cs, summary),
                  if (!_isLoading) ...[
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildStatusCard(l10n, summary),
                  ],
                  const SizedBox(height: AppConstants.spacingSectionV),
                  ReportTrendCard(
                    title: l10n.reportsCollectionTrend,
                    values: _collectionTrend,
                    valueFormatter: (v) => '₱${v.toStringAsFixed(0)}',
                  ),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  _buildLoansSection(context, l10n, cs, visible),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    AppLocalizations l10n,
    ColorScheme cs,
    LoanPeriodSummary summary,
  ) {
    // A period with no loans has no repayments to judge, so it gets a neutral
    // badge rather than a green "Healthy".
    final healthColor = !summary.hasActivity
        ? cs.outline
        : summary.isHealthy
        ? AppConstants.successGreen
        : AppConstants.warningAmber;
    final healthLabel = !summary.hasActivity
        ? l10n.loanHistoryNoActivity
        : summary.isHealthy
        ? l10n.loanHistoryHealthy
        : l10n.loanHistoryNeedsAttention;

    return ReportHeroCard(
      title: l10n.rptLoanSummaryTitle,
      period: _period,
      isLoading: _isLoading,
      trailing: _isLoading
          ? null
          : ReportStatusPill(label: healthLabel, color: healthColor),
      primaryStats: [
        ReportHeroStat(
          label: l10n.rptTotalValueIssued,
          value: _money0.format(summary.totalIssued),
          icon: Icons.account_balance_wallet_rounded,
          accent: AppConstants.primaryGreen,
        ),
        ReportHeroStat(
          label: l10n.rptLoansIssued,
          value: '${summary.loanCount}',
          icon: Icons.request_page_rounded,
          accent: AppConstants.buyerBlue,
        ),
      ],
      secondaryStats: [
        ReportHeroStat(
          label: l10n.loanHistoryTotalCollected,
          value: _money0.format(summary.totalCollected),
          icon: Icons.check_circle_rounded,
          accent: AppConstants.successGreen,
        ),
        ReportHeroStat(
          label: l10n.loanDashTotalOutstanding,
          value: _money0.format(summary.totalOutstanding),
          icon: Icons.pending_actions_rounded,
          accent: AppConstants.warningAmber,
        ),
        ReportHeroStat(
          label: l10n.rptOverdueBalance,
          value: _money0.format(summary.overdueBalance),
          icon: Icons.warning_amber_rounded,
          accent: AppConstants.errorRed,
        ),
        ReportHeroStat(
          label: l10n.rptRepaymentRate,
          value: '${summary.repaymentRatePercent.toStringAsFixed(0)}%',
          icon: Icons.percent_rounded,
          accent: AppConstants.amber,
        ),
      ],
    );
  }

  Widget _buildStatusCard(AppLocalizations l10n, LoanPeriodSummary summary) {
    return ReportSectionCard(
      title: l10n.rptLoanStatusTitle,
      icon: Icons.donut_small_rounded,
      child: Row(
        children: [
          Expanded(
            child: _statusTile(
              l10n.rptStatusActive,
              summary.activeCount,
              AppConstants.successGreen,
            ),
          ),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(
            child: _statusTile(
              l10n.rptStatusOverdue,
              summary.overdueCount,
              AppConstants.errorRed,
            ),
          ),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(
            child: _statusTile(
              l10n.rptStatusPaid,
              summary.paidCount,
              AppConstants.buyerBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusTile(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: color,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildLoansSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    List<AdminLoanSummary> visible,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.rptLoansIssued,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (!_isLoading && _loans.isNotEmpty)
              Text(
                l10n.rptShowingCount(visible.length, _loans.length),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_loans.isNotEmpty) ...[
          ReportSearchField(
            controller: _searchController,
            hint: l10n.loanHistorySearchHint,
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: AppConstants.spacingMd),
        ],
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: SkeletonList(),
          )
        else if (_loans.isEmpty)
          ReportEmptyState(message: l10n.rptNoLoansInPeriod)
        else if (visible.isEmpty)
          ReportEmptyState(message: l10n.rptNoMatches)
        else
          ...visible.map((loan) => _buildLoanRow(context, loan, l10n, cs)),
      ],
    );
  }

  Widget _buildLoanRow(
    BuildContext context,
    AdminLoanSummary loan,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final statusColor = loan.isPaid
        ? AppConstants.buyerBlue
        : loan.isOverdue
        ? AppConstants.errorRed
        : AppConstants.successGreen;
    final statusLabel = loan.isPaid
        ? l10n.rptStatusPaid
        : loan.isOverdue
        ? l10n.rptStatusOverdue
        : l10n.rptStatusActive;
    final itemsSummary = loan.itemNames.isEmpty
        ? '—'
        : loan.itemNames.join(', ');
    final showDue = !loan.isPaid && loan.nextPaymentDate != null;

    return ReportRecordCard(
      onTap: () => context.push(AppRoutes.loanDetails, extra: loan.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  loan.farmerName,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ReportStatusPill(label: statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${loan.referenceNo} • '
            '${DateFormat('MMM d, yyyy').format(loan.issuedDate)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          Text(
            itemsSummary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              _loanStat(
                l10n.issueLoanTotalValue,
                _money0.format(loan.totalValue),
                cs,
              ),
              _loanStat(
                l10n.loanDashPaid,
                _money0.format(loan.amountPaid),
                cs,
              ),
              _loanStat(
                l10n.loanDashBalance,
                _money0.format(loan.remainingBalance),
                cs,
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: LinearProgressIndicator(
              value: loan.repaidPercent,
              minHeight: 5,
              backgroundColor: cs.outline.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(statusColor),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                l10n.rptRepaidPercent(
                  (loan.repaidPercent * 100).toStringAsFixed(0),
                ),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (showDue)
                Text(
                  l10n.rptNextDue(
                    DateFormat('MMM d, yyyy').format(loan.nextPaymentDate!),
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: loan.isOverdue
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: loan.isOverdue
                        ? AppConstants.errorRed
                        : cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _loanStat(String label, String value, ColorScheme cs) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
