import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_loan_model.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/trend_chart_painter.dart';
import '../../widgets/report_summary_widgets.dart';

/// Loan Report — Admin.
/// Pushed above the shell. Route: /admin/reports/loans
///
/// Deliberately thin — reuses AdminLoanRepository's fetchAllLoans(),
/// fetchAllTimeLoanSummary(), and the AdminLoanListFilter search extension
/// directly, plus one new small method (fetchMonthlyCollectionTrend). No
/// new row model: the table reuses AdminLoanSummary as-is, since Loan
/// Report's mockup columns (reference, farmer, issue date, items, total,
/// paid, remaining, status) are already exactly what that model carries.
class LoanReportScreen extends StatefulWidget {
  const LoanReportScreen({super.key});

  @override
  State<LoanReportScreen> createState() => _LoanReportScreenState();
}

class _LoanReportScreenState extends State<LoanReportScreen> {
  final _repo = AdminLoanRepository();
  final _searchController = TextEditingController();

  ReportPeriod _period = ReportPeriod.thisMonth;
  String? _statusFilter;
  String _searchQuery = '';
  bool _isLoading = true;

  AllTimeLoanSummary _allTimeSummary = AllTimeLoanSummary.empty();
  List<double> _collectionTrend = [];
  List<AdminLoanSummary> _loans = [];

  @override
  void initState() {
    super.initState();
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
      _repo.fetchAllTimeLoanSummary(),
      _repo.fetchMonthlyCollectionTrend(),
      _repo.fetchAllLoans(
        statusFilter: _statusFilter,
        issuedAfter: _period.startDate,
        issuedBefore: _period.range().endDate,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _allTimeSummary = results[0] as AllTimeLoanSummary;
      _collectionTrend = results[1] as List<double>;
      _loans = results[2] as List<AdminLoanSummary>;
      _isLoading = false;
    });
  }

  void _setPeriod(ReportPeriod period) {
    setState(() => _period = period);
    _load();
  }

  void _setStatus(String? status) {
    setState(() => _statusFilter = status);
    _load();
  }

  /// Month abbreviations for fetchMonthlyCollectionTrend()'s trailing
  /// window — safe to compute client-side, since that method always
  /// returns a fixed "last N months ending at the current month" window,
  /// independent of the on-screen period filter.
  List<String> _trailingMonthLabels(int count) {
    final now = DateTime.now();
    return List.generate(count, (i) {
      final offset = count - 1 - i;
      final date = DateTime(now.year, now.month - offset, 1);
      return DateFormat('MMM').format(date);
    });
  }

  Map<String, int> get _statusDistribution {
    final counts = {'active': 0, 'overdue': 0, 'paid': 0};
    for (final loan in _loans) {
      counts[loan.status] = (counts[loan.status] ?? 0) + 1;
    }
    return counts;
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
          _buildTopBar(context, l10n, cs, sagana),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingSafeH,
                  AppConstants.spacingGutter,
                  AppConstants.spacingSafeH,
                  AppConstants.spacingSafeH,
                ),
                children: [
                  _buildAllTimeHealthCard(context, l10n, cs),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  _buildTrendChart(context, l10n, cs, sagana),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  _buildPeriodChips(l10n, cs),
                  const SizedBox(height: AppConstants.spacingSm),
                  _buildStatusChips(context, l10n, cs),
                  const SizedBox(height: AppConstants.spacingGutter),
                  if (!_isLoading && _statusFilter == null)
                    _buildStatusDistribution(context, l10n, cs),
                  const SizedBox(height: AppConstants.spacingGutter),
                  _buildSearchField(context, l10n, cs),
                  const SizedBox(height: AppConstants.spacingGutter),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_loans.applySearch(_searchQuery).isEmpty)
                    ReportEmptyState(message: l10n.reportsNoSearchResultsOrLoans)
                  else
                    ..._loans.applySearch(_searchQuery).map((loan) => _buildLoanRow(context, loan, cs, sagana)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSm),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  l10n.reportsLoanReport,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: cs.primary),
                ),
              ),
              IconButton(
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
            ],
          ),
        ),
      ),
    );
  }

  // Migrated onto the shared ReportHeroCard (Phase 16) — this screen
  // previously hand-built its own copy of the same gradient Container
  // Executive Snapshot/Harvest Report used, rather than sharing the
  // widget. The health badge moves into ReportHeroCard's trailing slot.
  Widget _buildAllTimeHealthCard(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    // A cooperative that has never issued a loan and one that has fully
    // collected on every loan it issued both reach isHealthy == true (see
    // AdminLoanRepository.fetchAllTimeLoanSummary — outstandingCount == 0
    // in both cases). Only the second is actually "Healthy"; the first has
    // no collection activity to evaluate at all, so it needs its own
    // neutral state rather than borrowing the green "Healthy" label.
    final hasLoanActivity = _allTimeSummary.totalLoanCount > 0;
    final healthColor = !hasLoanActivity
        ? cs.outline
        : _allTimeSummary.isHealthy
            ? AppConstants.successGreen
            : AppConstants.warningAmber;
    final healthLabel = !hasLoanActivity
        ? l10n.loanHistoryNoActivity
        : _allTimeSummary.isHealthy
            ? l10n.loanHistoryHealthy
            : l10n.loanHistoryNeedsAttention;

    return ReportHeroCard(
      title: l10n.loanHistoryAllTimeSummary,
      period: ReportPeriod.allTime,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: healthColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
        child: Text(healthLabel, style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: healthColor)),
      ),
      primaryStats: [
        ReportHeroStat(
          label: l10n.issueLoanTotalValue,
          value: currency.format(_allTimeSummary.totalIssued),
          icon: Icons.account_balance_wallet_rounded,
          accent: AppConstants.primaryGreen,
        ),
      ],
      secondaryStats: [
        ReportHeroStat(
          label: l10n.loanHistoryTotalCollected,
          value: currency.format(_allTimeSummary.totalCollected),
          icon: Icons.check_circle_rounded,
          accent: AppConstants.successGreen,
        ),
        ReportHeroStat(
          label: l10n.loanDashTotalOutstanding,
          value: currency.format(_allTimeSummary.totalOutstanding),
          icon: Icons.pending_actions_rounded,
          accent: AppConstants.warningAmber,
        ),
        ReportHeroStat(
          label: l10n.loanHistoryRate,
          value: '${_allTimeSummary.repaymentRatePercent.toStringAsFixed(0)}%',
          icon: Icons.percent_rounded,
          accent: AppConstants.buyerBlue,
        ),
      ],
    );
  }

  Widget _buildTrendChart(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.reportsCollectionTrend, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
          const SizedBox(height: AppConstants.spacingSm),
          SizedBox(
            height: 120,
            child: _collectionTrend.length < 2
                ? Center(
                    child: Text(
                      l10n.reportsNotEnoughTrendData,
                      style: GoogleFonts.inter(fontSize: 12, color: cs.outline),
                    ),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 120),
                    painter: TrendChartPainter(
                      values: _collectionTrend,
                      lineColor: cs.primary,
                      gradientColor: cs.primary,
                      xLabels: _trailingMonthLabels(_collectionTrend.length),
                      yValueFormatter: (v) => '₱${v.toStringAsFixed(0)}',
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChips(AppLocalizations l10n, ColorScheme cs) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: reportPeriodChipOrder.map((p) {
          final active = _period == p;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(reportPeriodLabel(l10n, p), style: GoogleFonts.inter(fontSize: 12)),
              selected: active,
              onSelected: (_) => _setPeriod(p),
              selectedColor: AppConstants.primaryGreen,
              labelStyle: TextStyle(color: active ? Colors.white : cs.onSurface),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusChips(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    final options = <String?, String>{
      null: l10n.loanHistoryFilterAll,
      'active': l10n.loanDashActiveLoans,
      'overdue': l10n.loanDashOverdueLoans,
      'paid': l10n.loanHistoryFilterPaid,
    };

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: options.entries.map((entry) {
          final active = _statusFilter == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(entry.value, style: GoogleFonts.inter(fontSize: 12)),
              selected: active,
              onSelected: (_) => _setStatus(entry.key),
              selectedColor: AppConstants.buyerBlue,
              labelStyle: TextStyle(color: active ? Colors.white : cs.onSurface),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusDistribution(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    final dist = _statusDistribution;
    final total = _loans.length;
    if (total == 0) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(child: _distributionChip(l10n.loanDashActiveLoans, dist['active'] ?? 0, AppConstants.successGreen)),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(child: _distributionChip(l10n.loanDashOverdueLoans, dist['overdue'] ?? 0, AppConstants.errorRed)),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(child: _distributionChip(l10n.loanHistoryFilterPaid, dist['paid'] ?? 0, AppConstants.buyerBlue)),
      ],
    );
  }

  Widget _distributionChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text('$count', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: color)),
          Text(label, style: GoogleFonts.inter(fontSize: 9, color: color), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _searchQuery = v),
      decoration: InputDecoration(
        hintText: l10n.loanHistorySearchHint,
        hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
        prefixIcon: Icon(Icons.search_rounded, color: cs.outline, size: 22),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.close_rounded, color: cs.outline, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
      ),
      style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
    );
  }

  Widget _buildLoanRow(BuildContext context, AdminLoanSummary loan, ColorScheme cs, SaganaColors sagana) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final statusColor = loan.isPaid
        ? AppConstants.buyerBlue
        : loan.isOverdue
            ? AppConstants.errorRed
            : AppConstants.successGreen;
    final statusLabel = loan.isPaid ? 'PAID' : loan.isOverdue ? 'OVERDUE' : 'ACTIVE';
    final itemsSummary = loan.itemNames.isEmpty ? '—' : loan.itemNames.join(', ');

    return GestureDetector(
      onTap: () => context.push(AppRoutes.loanDetails, extra: loan.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    loan.farmerName,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(statusLabel, style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: statusColor)),
                ),
              ],
            ),
            Text(
              '${loan.memberId} • ${loan.referenceNo} • ${DateFormat('MMM d, yyyy').format(loan.issuedDate)}',
              style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            Text(
              itemsSummary,
              style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppConstants.spacingSm),
            Row(
              children: [
                _loanStat(l10n(context).issueLoanTotalValue, currency.format(loan.totalValue), cs),
                _loanStat(l10n(context).loanDashPaid, currency.format(loan.amountPaid), cs),
                _loanStat(l10n(context).loanDashBalance, currency.format(loan.remainingBalance), cs),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _loanStat(String label, String value, ColorScheme cs) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
          Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12, color: cs.onSurface)),
        ],
      ),
    );
  }

  AppLocalizations l10n(BuildContext context) => AppLocalizations.of(context);
}