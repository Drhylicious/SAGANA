import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/expense_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/report_ui_widgets.dart';
import '../../../core/utils/member_access.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../data/services/connectivity_service.dart';

/// Expense Report — Admin.
/// Pushed above the shell. Route: /admin/reports/expenses
///
/// Subsidized vs. farmer-paid split — the schema only supports a boolean
/// is_subsidy flag, not a funding-source breakdown. Subsidized entries carry
/// no peso total by design (see ExpenseReportData's doc comment), so only a
/// count is shown for them.
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
  bool _isOnline = ConnectivityService.instance.isOnline;
  String _searchQuery = '';
  String? _categoryFilter; // null = All
  ExpenseReportData _data = ExpenseReportData.empty();
  List<double> _spendingTrend = [];

  static final _money0 = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 0,
  );
  static final _money2 = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
    _loadTrend();
  }

  Future<void> _loadTrend() async {
    final trend = await _repo.fetchExpenseTrend();
    if (!mounted) return;
    setState(() => _spendingTrend = trend);
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
      // A category that has no entries in the new period no longer has a chip.
      if (_categoryFilter != null &&
          !data.categoryBreakdown.any((c) => c.category == _categoryFilter)) {
        _categoryFilter = null;
      }
      _isLoading = false;
    });
  }

  void _setPeriod(ReportPeriod period) {
    setState(() => _period = period);
    _load();
  }

  List<ExpenseReportRow> get _filteredExpenses {
    var list = _categoryFilter == null
        ? _data.expenses
        : _data.expenses.where((e) => e.category == _categoryFilter).toList();
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list
        .where(
          (e) =>
              e.farmerName.toLowerCase().contains(q) ||
              e.category.toLowerCase().contains(q) ||
              e.name.toLowerCase().contains(q) ||
              e.description.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.reportsExpenseReport,
            onBack: () => context.pop(),
            trailing: IconButton(
              icon: Icon(Icons.file_download_outlined, color: cs.primary),
              onPressed: () => context.push(
                AppRoutes.exportCenter,
                extra: ExportCenterArgs(
                  preselectedModule: ReportModuleType.expense,
                  period: _period,
                ),
              ),
              tooltip: l10n.reportsExportCenter,
            ),
          ),
          CachedDataNotice(
            screen: AdminReportsRepository.expenseCacheScreen(_period),
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
                  ReportPeriodFilter(period: _period, onSelected: _setPeriod),
                  const SizedBox(height: AppConstants.spacingGutter),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: SkeletonList(),
                    )
                  else ...[
                    _buildOverviewCard(l10n),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildCategoryBreakdown(l10n),
                    if (_data.categoryBreakdown.isNotEmpty)
                      const SizedBox(height: AppConstants.spacingSectionV),
                    ReportTrendCard(
                      title: l10n.reportsSpendingTrend,
                      values: _spendingTrend,
                      valueFormatter: (v) => '₱${v.toStringAsFixed(0)}',
                    ),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildExpensesSection(context, l10n, cs),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(AppLocalizations l10n) {
    // The peso total gets a full-width tile, because it is the headline figure
    // and its label is long. The two counts share the row below it. Each row
    // is as tall as its content (no fixed height), so nothing is cut off on a
    // narrow phone and there is no empty space on a wide one.
    return ReportSectionCard(
      title: l10n.reportsExpenseOverview,
      icon: Icons.account_balance_wallet_rounded,
      subtitle: l10n.rptExpenseNote,
      child: Column(
        children: [
          _kpiTile(
            icon: Icons.payments_rounded,
            accent: AppConstants.primaryGreen,
            label: l10n.rptPaidByFarmers,
            value: _money0.format(_data.totalFarmerFundedAmount),
            large: true,
          ),
          const SizedBox(height: AppConstants.spacingSm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _kpiTile(
                    icon: Icons.volunteer_activism_rounded,
                    accent: AppConstants.buyerBlue,
                    label: l10n.rptSubsidizedEntries,
                    value: '${_data.subsidizedCount}',
                  ),
                ),
                const SizedBox(width: AppConstants.spacingSm),
                Expanded(
                  child: _kpiTile(
                    icon: Icons.receipt_long_rounded,
                    accent: AppConstants.amber,
                    label: l10n.reportsTotalEntries,
                    value: '${_data.totalEntryCount}',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A compact KPI tile: icon badge on the left, label above the value.
  Widget _kpiTile({
    required IconData icon,
    required Color accent,
    required String label,
    required String value,
    bool large = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingMd,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800,
                    fontSize: large ? 20 : 17,
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

  Widget _buildCategoryBreakdown(AppLocalizations l10n) {
    if (_data.categoryBreakdown.isEmpty) return const SizedBox.shrink();
    final total = _data.totalFarmerFundedAmount;

    return ReportSectionCard(
      title: l10n.reportsExpensesByCategory,
      icon: Icons.pie_chart_rounded,
      child: Column(
        children: _data.categoryBreakdown.map((c) {
          final share = total > 0 ? c.total / total * 100 : null;
          return ReportBarRow(
            label: c.category,
            valueText: _money0.format(c.total),
            fraction: c.percentOfMax,
            color: categoryColor(c.category),
            leading: Icon(
              categoryIcon(c.category),
              size: 14,
              color: categoryColor(c.category),
            ),
            tag: c.hasSubsidy
                ? ReportStatusPill(
                    label: l10n.reportsSubsidizedTag,
                    color: AppConstants.buyerBlue,
                  )
                : null,
            caption: share == null
                ? null
                : l10n.rptShareOfTotal(share.toStringAsFixed(0)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildExpensesSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final filtered = _filteredExpenses;
    final categoryOptions = <ReportFilterOption<String?>>[
      ReportFilterOption<String?>(null, l10n.reportsAll),
      for (final c in _data.categoryBreakdown)
        ReportFilterOption<String?>(c.category, c.category),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.reportsExpenseEntries,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (_data.expenses.isNotEmpty)
              Text(
                l10n.rptShowingCount(filtered.length, _data.expenses.length),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_data.expenses.isNotEmpty) ...[
          ReportSearchField(
            controller: _searchController,
            hint: l10n.reportsSearchExpenses,
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          ReportFilterChips<String?>(
            options: categoryOptions,
            selected: _categoryFilter,
            onSelected: (v) => setState(() => _categoryFilter = v),
          ),
          const SizedBox(height: AppConstants.spacingMd),
        ],
        if (_data.expenses.isEmpty)
          ReportEmptyState(message: l10n.reportsNoExpensesRecorded)
        else if (filtered.isEmpty)
          ReportEmptyState(message: l10n.rptNoMatches)
        else
          ...filtered.map((e) => _buildExpenseRow(context, e, l10n, cs)),
      ],
    );
  }

  Widget _buildExpenseRow(
    BuildContext context,
    ExpenseReportRow expense,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    // Tapping the row opens the expense's details for everyone; the Manager
    // can go on to the farmer's profile from there.
    return ReportRecordCard(
      onTap: () => _showExpenseDetail(context, expense, l10n),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: categoryBgColor(expense.category),
              shape: BoxShape.circle,
            ),
            child: Icon(
              categoryIcon(expense.category),
              size: 17,
              color: categoryColor(expense.category),
            ),
          ),
          const SizedBox(width: AppConstants.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  '${expense.category} • ${expense.farmerName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  DateFormat('MMM d, yyyy').format(expense.expenseDate),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          expense.isSubsidy
              ? ReportStatusPill(
                  label: l10n.reportsSubsidizedTag,
                  color: AppConstants.buyerBlue,
                )
              : Text(
                  _money2.format(expense.amount),
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

  void _showExpenseDetail(
    BuildContext context,
    ExpenseReportRow expense,
    AppLocalizations l10n,
  ) {
    showManagementModal<void>(
      context: context,
      builder: (sheetContext) => ManagementModalShell(
        title: expense.name,
        subtitle: expense.category,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReportDetailRow(label: l10n.rptFarmer, value: expense.farmerName),
            ReportDetailRow(label: l10n.rptCategory, value: expense.category),
            if (expense.description.isNotEmpty)
              ReportDetailRow(
                label: l10n.rptDescription,
                value: expense.description,
              ),
            ReportDetailRow(
              label: l10n.rptAmount,
              value: expense.isSubsidy
                  ? l10n.rptSubsidizedNoAmount
                  : _money2.format(expense.amount),
            ),
            ReportDetailRow(
              label: l10n.rptDate,
              value: DateFormat('MMM d, yyyy').format(expense.expenseDate),
              isLast: true,
            ),
          ],
        ),
        footer: membersAccessAllowed
            ? Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    pushFarmerDetails(context, expense.farmerId);
                  },
                  icon: const Icon(Icons.person_outline_rounded, size: 18),
                  label: Text(l10n.rptViewFarmerProfile),
                ),
              )
            : null,
      ),
    );
  }
}
