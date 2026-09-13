import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/trend_chart_painter.dart';
import '../../widgets/report_summary_widgets.dart';

/// Sales Report — Admin.
/// Pushed above the shell. Route: /admin/reports/sales
///
/// Reports on member_sales_transactions (direct Palay/Peanut sales to
/// SP3) rather than the marketplace `orders` table — see the Phase 1
/// analysis for why. Read-only; shows an explicit empty state if no
/// transactions have been recorded yet, since there is currently no
/// admin tool that creates rows in this table.
class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  final _repo = AdminReportsRepository();
  final _searchController = TextEditingController();

  ReportPeriod _period = ReportPeriod.thisMonth;
  bool _isLoading = true;
  String _searchQuery = '';
  SalesReportData _data = SalesReportData.empty();
  SalesReportData _previousData = SalesReportData.empty();

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
      _repo.fetchSalesReport(_period),
      _repo.fetchPreviousSalesReport(_period),
    ]);
    if (!mounted) return;
    setState(() {
      _data = results[0];
      _previousData = results[1];
      _isLoading = false;
    });
  }

  void _setPeriod(ReportPeriod period) {
    setState(() => _period = period);
    _load();
  }

  List<SalesTransactionRow> get _filteredTransactions {
    if (_searchQuery.isEmpty) return _data.transactions;
    final q = _searchQuery.toLowerCase();
    return _data.transactions
        .where(
          (t) =>
              t.farmerName.toLowerCase().contains(q) ||
              t.memberId.toLowerCase().contains(q) ||
              t.cropName.toLowerCase().contains(q) ||
              (t.referenceNo?.toLowerCase().contains(q) ?? false),
        )
        .toList();
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
                  32,
                ),
                children: [
                  _buildPeriodChips(cs),
                  const SizedBox(height: AppConstants.spacingGutter),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    _buildSummaryStats(context, l10n, cs, sagana),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildCropSplit(context, l10n, cs, sagana),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildTrendChart(context, l10n, cs, sagana),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildTransactionsSection(context, l10n, cs, sagana),
                  ],
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingSm,
          ),
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
                  l10n.reportsSalesReport,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: cs.primary,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.file_download_outlined,
                  color: cs.primary,
                ),
                onPressed: () => context.push(
                  AppRoutes.exportCenter,
                  extra: ExportCenterArgs(
                    preselectedModule: ReportModuleType.sales,
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

  Widget _buildPeriodChips(ColorScheme cs) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: reportPeriodChipOrder.map((p) {
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

  Widget _buildSummaryStats(
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
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ReportKpiTile(
                label: l10n.reportsTotalRevenue,
                value: currency.format(_data.totalRevenue),
                delta: ReportDeltaBadge(
                  current: _data.totalRevenue,
                  previous: _previousData.totalRevenue,
                  period: _period,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spacingSm),
            Expanded(
              child: ReportKpiTile(
                label: l10n.reportsTotalVolume,
                value: '${_data.totalQuantityKg.toStringAsFixed(0)} kg',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingSm),
        Row(
          children: [
            Expanded(
              child: ReportKpiTile(
                label: l10n.reportsTransactions,
                value: '${_data.transactionCount}',
              ),
            ),
            const SizedBox(width: AppConstants.spacingSm),
            Expanded(
              child: ReportKpiTile(
                label: l10n.reportsAvgSale,
                value: currency.format(_data.averageSaleAmount),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingSm),
        Row(
          children: [
            Expanded(
              child: ReportKpiTile(
                label: l10n.reportsMarketplaceRevenue,
                value: currency.format(_data.marketplaceRevenue),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCropSplit(
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
    final total = _data.palayAmount + _data.peanutAmount;
    final palayFraction = total > 0 ? _data.palayAmount / total : 0.5;

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
          Text(
            l10n.reportsCropBreakdown,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    flex: (palayFraction * 100).round().clamp(1, 99),
                    child: Container(color: AppConstants.primaryGreen),
                  ),
                  Expanded(
                    flex: (100 - (palayFraction * 100).round()).clamp(1, 99),
                    child: Container(color: AppConstants.amber),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _legendDot(
                AppConstants.primaryGreen,
                'Palay — ${currency.format(_data.palayAmount)}',
              ),
              _legendDot(
                AppConstants.amber,
                'Peanut — ${currency.format(_data.peanutAmount)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 11)),
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
          Text(
            l10n.reportsRevenueTrend,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          SizedBox(
            height: 120,
            child: _data.monthlyTrend.length < 2
                ? Center(
                    child: Text(
                      l10n.reportsNotEnoughTrendData,
                      style: GoogleFonts.inter(fontSize: 12, color: cs.outline),
                    ),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 120),
                    painter: TrendChartPainter(
                      values: _data.monthlyTrend,
                      lineColor: cs.primary,
                      gradientColor: cs.primary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final filtered = _filteredTransactions;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.reportsTransactionDetails,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_data.transactions.isNotEmpty)
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: l10n.reportsSearchTransactions,
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: cs.outline,
                size: 20,
              ),
            ),
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
          ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_data.transactions.isEmpty)
          ReportEmptyState(message: l10n.reportsNoSalesRecorded)
        else if (filtered.isEmpty)
          ReportEmptyState(message: l10n.reportsNoSearchResults)
        else
          ...filtered.map((t) => _buildTransactionRow(t, currency, cs, sagana)),
      ],
    );
  }

  Widget _buildTransactionRow(
    SalesTransactionRow t,
    NumberFormat currency,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final cropColor = t.cropType == 'palay'
        ? AppConstants.primaryGreen
        : AppConstants.amber;

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: cropColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            ),
            child: Text(
              t.cropName,
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: cropColor,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.farmerName,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${t.memberId} • ${t.quantityKg.toStringAsFixed(0)} kg • ${DateFormat('MMM d, yyyy').format(t.saleDate)}'
                  '${t.referenceNo != null ? ' • ${t.referenceNo}' : ''}',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            currency.format(t.amount),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}