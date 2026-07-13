import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/expense_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/trend_chart_painter.dart';

/// Expense Report — Admin.
/// Pushed above the shell. Route: /admin/reports/expenses
///
/// Subsidized vs. Farmer-Funded split per the agreed simplification — the
/// schema only supports a boolean is_subsidy flag, not a funding-source
/// breakdown. Subsidized entries carry no peso total by design (see
/// ExpenseReportData's doc comment), so only a count is shown for them.
class ExpenseReportScreen extends StatefulWidget {
  const ExpenseReportScreen({super.key});

  @override
  State<ExpenseReportScreen> createState() => _ExpenseReportScreenState();
}

class _ExpenseReportScreenState extends State<ExpenseReportScreen> {
  final _repo = AdminReportsRepository();
  final _searchController = TextEditingController();

  ReportPeriod _period = ReportPeriod.thisMonth;
  bool _isLoading = true;
  String _searchQuery = '';
  ExpenseReportData _data = ExpenseReportData.empty();

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
    final data = await _repo.fetchExpenseReport(_period);
    if (!mounted) return;
    setState(() {
      _data = data;
      _isLoading = false;
    });
  }

  void _setPeriod(ReportPeriod period) {
    setState(() => _period = period);
    _load();
  }

  List<ExpenseReportRow> get _filteredExpenses {
    if (_searchQuery.isEmpty) return _data.expenses;
    final q = _searchQuery.toLowerCase();
    return _data.expenses
        .where((e) =>
            e.farmerName.toLowerCase().contains(q) ||
            e.memberId.toLowerCase().contains(q) ||
            e.category.toLowerCase().contains(q) ||
            e.description.toLowerCase().contains(q))
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
                    _buildCategoryBreakdown(context, l10n, cs, sagana),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildTrendChart(context, l10n, cs, sagana),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildExpensesSection(context, l10n, cs, sagana),
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
                  l10n.reportsExpenseReport,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: cs.primary),
                ),
              ),
              IconButton(
                icon: Icon(Icons.file_download_outlined, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                onPressed: () => context.push(
                  AppRoutes.exportCenter,
                  extra: ExportCenterArgs(
                    preselectedModule: ReportModuleType.expense,
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
        children: ReportPeriod.values.map((p) {
          final active = _period == p;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(p.label, style: GoogleFonts.inter(fontSize: 12)),
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

  Widget _buildSummaryStats(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    return Row(
      children: [
        Expanded(child: _statCard(l10n.reportsFarmerFundedTotal, currency.format(_data.totalFarmerFundedAmount), AppConstants.primaryGreen, cs, sagana)),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(child: _statCard(l10n.reportsSubsidizedItems, '${_data.subsidizedCount}', AppConstants.buyerBlue, cs, sagana)),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(child: _statCard(l10n.reportsTotalEntries, '${_data.totalEntryCount}', AppConstants.amber, cs, sagana)),
      ],
    );
  }

  Widget _statCard(String label, String value, Color accent, ColorScheme cs, SaganaColors sagana) {
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
          Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(height: AppConstants.spacingSm),
          Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface)),
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    if (_data.categoryBreakdown.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.reportsExpensesByCategory, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
          const SizedBox(height: AppConstants.spacingMd),
          ..._data.categoryBreakdown.map((c) {
            final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
            return Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(categoryIcon(c.category), size: 14, color: categoryColor(c.category)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(c.category, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurface))),
                      if (c.hasSubsidy)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppConstants.buyerBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                          ),
                          child: Text(
                            l10n.reportsSubsidizedTag,
                            style: GoogleFonts.inter(fontSize: 9, color: AppConstants.buyerBlue),
                          ),
                        ),
                      Text(currency.format(c.total), style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12, color: cs.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    child: LinearProgressIndicator(
                      value: c.percentOfMax,
                      minHeight: 6,
                      backgroundColor: cs.outline.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation(categoryColor(c.category)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
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
          Text(l10n.reportsSpendingTrend, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
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

  Widget _buildExpensesSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final filtered = _filteredExpenses;
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.reportsExpenseEntries, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
        const SizedBox(height: AppConstants.spacingSm),
        if (_data.expenses.isNotEmpty)
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: l10n.reportsSearchExpenses,
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              prefixIcon: Icon(Icons.search_rounded, color: cs.outline, size: 20),
            ),
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
          ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_data.expenses.isEmpty)
          _buildEmptyState(l10n.reportsNoExpensesRecorded, cs)
        else if (filtered.isEmpty)
          _buildEmptyState(l10n.reportsNoSearchResults, cs)
        else
          ...filtered.map((e) => _buildExpenseRow(context, e, currency, l10n, cs, sagana)),
      ],
    );
  }

  Widget _buildEmptyState(String message, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildExpenseRow(
    BuildContext context,
    ExpenseReportRow expense,
    NumberFormat currency,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.farmerDetails, extra: expense.farmerId),
      child: Container(
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
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: categoryBgColor(expense.category),
                shape: BoxShape.circle,
              ),
              child: Icon(categoryIcon(expense.category), size: 16, color: categoryColor(expense.category)),
            ),
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.description,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${expense.farmerName} • ${expense.memberId} • ${DateFormat('MMM d, yyyy').format(expense.expenseDate)}',
                    style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            expense.isSubsidy
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppConstants.buyerBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(
                      l10n.reportsSubsidizedTag,
                      style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: AppConstants.buyerBlue),
                    ),
                  )
                : Text(
                    currency.format(expense.amount),
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface),
                  ),
          ],
        ),
      ),
    );
  }
}