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

enum _BatchStatusFilter { all, available, reserved, lowStock, soldOut }

extension on _BatchStatusFilter {
  String label(AppLocalizations l10n) {
    switch (this) {
      case _BatchStatusFilter.all:
        return l10n.reportsAll;
      case _BatchStatusFilter.available:
        return l10n.reportsAvailable;
      case _BatchStatusFilter.reserved:
        return l10n.reportsReserved;
      case _BatchStatusFilter.lowStock:
        return l10n.reportsLowStockItems;
      case _BatchStatusFilter.soldOut:
        return l10n.reportsSoldOut;
    }
  }

  bool matches(InventoryReportRow row) {
    switch (this) {
      case _BatchStatusFilter.all:
        return true;
      case _BatchStatusFilter.available:
        return row.status == 'available';
      case _BatchStatusFilter.reserved:
        return row.status == 'reserved';
      case _BatchStatusFilter.lowStock:
        return row.status == 'low_stock';
      case _BatchStatusFilter.soldOut:
        return row.status == 'sold_out';
    }
  }
}

/// Harvest Report — Admin.
/// Pushed above the shell via rootNavigatorKey. Route: /admin/reports/harvest
///
/// Replaces the separate Harvest Report and Inventory Report screens.
/// Two internal tabs over two DELIBERATELY SEPARATE data sources:
///   - Activity & Trends  → harvest_records (period-scoped event log)
///   - Batches & Stock    → inventory_batches (unfiltered live snapshot)
/// fetchHarvestReport() and fetchInventoryReport() remain independent
/// repository calls — this screen only adds navigation/traceability
/// between their results via the batch_number they share.
class HarvestReportScreen extends StatefulWidget {
  final int initialTabIndex;
  const HarvestReportScreen({super.key, this.initialTabIndex = 0});

  @override
  State<HarvestReportScreen> createState() => _HarvestReportScreenState();
}

class _HarvestReportScreenState extends State<HarvestReportScreen>
    with SingleTickerProviderStateMixin {
  final _repo = AdminReportsRepository();
  late TabController _tabController;

  final _harvestSearchController = TextEditingController();
  final _inventorySearchController = TextEditingController();

  ReportPeriod _period = ReportPeriod.thisMonth;
  _BatchStatusFilter _statusFilter = _BatchStatusFilter.all;
  String _harvestSearchQuery = '';
  String _inventorySearchQuery = '';

  bool _isLoading = true;
  HarvestReportData _harvestData = HarvestReportData.empty();
  InventoryReportData _inventoryData = InventoryReportData.empty();
  List<double> _yieldTrend = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _harvestSearchController.dispose();
    _inventorySearchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchHarvestReport(_period),
      _repo.fetchInventoryReport(),
      _repo.fetchYieldTrend(),
    ]);
    if (!mounted) return;
    setState(() {
      _harvestData = results[0] as HarvestReportData;
      _inventoryData = results[1] as InventoryReportData;
      _yieldTrend = results[2] as List<double>;
      _isLoading = false;
    });
  }

  Future<void> _setPeriod(ReportPeriod period) async {
    setState(() => _period = period);
    final data = await _repo.fetchHarvestReport(period);
    if (!mounted) return;
    setState(() => _harvestData = data);
  }

  /// Month abbreviations for fetchYieldTrend()'s trailing window — safe to
  /// compute client-side without touching the repository, since that
  /// method always returns a fixed "last [count] months ending at the
  /// current month" window by construction (see its own doc comment).
  List<String> _trailingMonthLabels(int count) {
    final now = DateTime.now();
    return List.generate(count, (i) {
      final offset = count - 1 - i;
      final date = DateTime(now.year, now.month - offset, 1);
      return DateFormat('MMM').format(date);
    });
  }

  List<HarvestReportRow> get _filteredHarvests {
    if (_harvestSearchQuery.isEmpty) return _harvestData.harvests;
    final q = _harvestSearchQuery.toLowerCase();
    return _harvestData.harvests
        .where(
          (h) =>
              h.farmerName.toLowerCase().contains(q) ||
              h.memberId.toLowerCase().contains(q) ||
              h.cropName.toLowerCase().contains(q) ||
              h.batchNumber.toLowerCase().contains(q),
        )
        .toList();
  }

  List<InventoryReportRow> get _filteredBatches {
    var list = _inventoryData.batches
        .where((b) => _statusFilter.matches(b))
        .toList();
    if (_inventorySearchQuery.isNotEmpty) {
      final q = _inventorySearchQuery.toLowerCase();
      list = list
          .where(
            (b) =>
                b.farmerName.toLowerCase().contains(q) ||
                b.memberId.toLowerCase().contains(q) ||
                b.cropName.toLowerCase().contains(q) ||
                b.batchNumber.toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: AppConstants.warningAmber,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),
    );
  }

  void _viewBatch(HarvestReportRow harvest) {
    final match = _inventoryData.batches.where(
      (b) => b.batchNumber == harvest.batchNumber,
    );
    if (match.isEmpty) {
      _showSnack(AppLocalizations.of(context).reportsNoBatchFound);
      return;
    }
    setState(() {
      _inventorySearchController.text = harvest.batchNumber;
      _inventorySearchQuery = harvest.batchNumber;
    });
    _tabController.animateTo(1);
  }

  Future<void> _viewHarvest(InventoryReportRow batch) async {
    var match = _harvestData.harvests.where(
      (h) => h.batchNumber == batch.batchNumber,
    );

    if (match.isEmpty && _period != ReportPeriod.allTime) {
      final widened = await _repo.fetchHarvestReport(ReportPeriod.allTime);
      if (!mounted) return;
      match = widened.harvests.where((h) => h.batchNumber == batch.batchNumber);
      if (match.isNotEmpty) {
        setState(() {
          _period = ReportPeriod.allTime;
          _harvestData = widened;
        });
      }
    }

    if (match.isEmpty) {
      _showSnack(AppLocalizations.of(context).reportsNoHarvestFound);
      return;
    }

    setState(() {
      _harvestSearchController.text = batch.batchNumber;
      _harvestSearchQuery = batch.batchNumber;
    });
    _tabController.animateTo(0);
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
          if (!_isLoading) _buildExecutiveHeader(context, l10n, cs),
          _buildTabBar(context, l10n, cs),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildActivityTab(context, l10n, cs, sagana),
                      _buildBatchesTab(context, l10n, cs, sagana),
                    ],
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
                  l10n.reportsHarvestManagement,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: cs.primary,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.file_download_outlined, color: cs.primary),
                onPressed: () => context.push(
                  AppRoutes.exportCenter,
                  // Harvest Report's export now covers both tabs' data
                  // (Activity + Batches & Stock) in one file — see
                  // serializeHarvestReportCsv() — so both tabs preselect
                  // the same module.
                  extra: ExportCenterArgs(
                    preselectedModule: ReportModuleType.harvest,
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
  // Executive Snapshot/Loan Report used, rather than sharing the widget.
  Widget _buildExecutiveHeader(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingSafeH,
        AppConstants.spacingMd,
        AppConstants.spacingSafeH,
        0,
      ),
      child: ReportHeroCard(
        title: l10n.reportsHarvestOverview,
        period: _period,
        primaryStats: [
          ReportHeroStat(
            label: '${l10n.reportsTotalYield} (${reportPeriodLabel(l10n, _period)})',
            value: '${_harvestData.totalYieldKg.toStringAsFixed(0)} kg',
            icon: Icons.agriculture_rounded,
            accent: AppConstants.primaryGreen,
          ),
          ReportHeroStat(
            label: l10n.reportsAvailableStockLive,
            value: '${_inventoryData.totalAvailableKg.toStringAsFixed(0)} kg',
            icon: Icons.inventory_2_rounded,
            accent: AppConstants.buyerBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      margin: const EdgeInsets.only(top: AppConstants.spacingMd),
      child: TabBar(
        controller: _tabController,
        labelColor: AppConstants.primaryGreen,
        unselectedLabelColor: cs.onSurfaceVariant,
        indicatorColor: AppConstants.primaryGreen,
        labelStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
        onTap: (_) => setState(() {}), // refresh export-icon module target
        tabs: [
          Tab(text: l10n.reportsActivityTrendsTab),
          Tab(text: l10n.reportsBatchesStockTab),
        ],
      ),
    );
  }

  Widget _buildActivityTab(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingSafeH,
          AppConstants.spacingGutter,
          AppConstants.spacingSafeH,
          32,
        ),
        children: [
          _buildPeriodChips(l10n, cs),
          const SizedBox(height: AppConstants.spacingGutter),
          _buildHarvestSummaryStats(context, l10n, cs, sagana),
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildYieldByCrop(context, l10n, cs, sagana),
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildYieldTrend(context, l10n, cs, sagana),
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildHarvestsSection(context, l10n, cs, sagana),
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
              labelStyle: TextStyle(
                color: active ? Colors.white : cs.onSurface,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHarvestSummaryStats(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Row(
      children: [
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.agriculture_rounded,
            label: l10n.reportsTotalYield,
            value: '${_harvestData.totalYieldKg.toStringAsFixed(0)} kg',
            accent: AppConstants.primaryGreen,
          ),
        ),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.cloud_off_rounded,
            label: l10n.reportsUnsyncedEntries,
            value: '${_harvestData.unsyncedCount}',
            accent: AppConstants.warningAmber,
          ),
        ),
      ],
    );
  }

  Widget _buildYieldByCrop(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    if (_harvestData.cropBreakdown.isEmpty) return const SizedBox.shrink();
    final maxKg = _harvestData.cropBreakdown.first.totalKg;

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
          Text(
            l10n.reportsYieldByCrop,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          ..._harvestData.cropBreakdown.map((c) {
            final fraction = maxKg > 0
                ? (c.totalKg / maxKg).clamp(0.0, 1.0)
                : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        c.cropName,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${c.totalKg.toStringAsFixed(0)} kg',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 6,
                      backgroundColor: cs.outline.withValues(alpha: 0.12),
                      valueColor: const AlwaysStoppedAnimation(
                        AppConstants.primaryGreen,
                      ),
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

  Widget _buildYieldTrend(
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
            l10n.reportsYieldTrend,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          SizedBox(
            height: 120,
            child: _yieldTrend.length < 2
                ? Center(
                    child: Text(
                      l10n.reportsNotEnoughTrendData,
                      style: GoogleFonts.inter(fontSize: 12, color: cs.outline),
                    ),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 120),
                    painter: TrendChartPainter(
                      values: _yieldTrend,
                      lineColor: cs.primary,
                      gradientColor: cs.primary,
                      xLabels: _trailingMonthLabels(_yieldTrend.length),
                      yValueFormatter: (v) => '${v.toStringAsFixed(0)}kg',
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHarvestsSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final filtered = _filteredHarvests;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.reportsHarvestEntries,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_harvestData.harvests.isNotEmpty)
          TextField(
            controller: _harvestSearchController,
            onChanged: (v) => setState(() => _harvestSearchQuery = v),
            decoration: InputDecoration(
              hintText: l10n.reportsSearchHarvestsWithBatch,
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: cs.outline,
                size: 20,
              ),
              suffixIcon: _harvestSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: cs.outline,
                        size: 18,
                      ),
                      onPressed: () {
                        _harvestSearchController.clear();
                        setState(() => _harvestSearchQuery = '');
                      },
                    )
                  : null,
            ),
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
          ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_harvestData.harvests.isEmpty)
          ReportEmptyState(message: l10n.reportsNoHarvestsRecorded)
        else if (filtered.isEmpty)
          ReportEmptyState(message: l10n.reportsNoSearchResults)
        else
          ...filtered.map(
            (h) => _buildHarvestRow(context, h, l10n, cs, sagana),
          ),
      ],
    );
  }

  Widget _buildHarvestRow(
    BuildContext context,
    HarvestReportRow harvest,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return GestureDetector(
      onTap: () =>
          context.push(AppRoutes.farmerDetails, extra: harvest.farmerId),
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
                    harvest.cropName,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${harvest.quantityKg.toStringAsFixed(0)} kg',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            Text(
              '${harvest.farmerName} • ${harvest.memberId} • ${DateFormat('MMM d, yyyy').format(harvest.harvestDate)}',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Batch #${harvest.batchNumber}',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _statusChip(
                        icon: harvest.submittedToCooperative
                            ? Icons.check_circle_rounded
                            : Icons.remove_circle_outline_rounded,
                        label: harvest.submittedToCooperative
                            ? l10n.reportsToCoop
                            : l10n.reportsNotToCoop,
                        color: harvest.submittedToCooperative
                            ? AppConstants.successGreen
                            : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppConstants.spacingSm),
                      _statusChip(
                        icon: harvest.isSynced
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_off_rounded,
                        label: harvest.isSynced
                            ? l10n.reportsSynced
                            : l10n.reportsPendingSync,
                        color: harvest.isSynced
                            ? AppConstants.buyerBlue
                            : AppConstants.warningAmber,
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _viewBatch(harvest),
                  icon: const Icon(Icons.inventory_2_outlined, size: 14),
                  label: Text(
                    l10n.reportsViewBatch,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppConstants.primaryGreen,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: color)),
      ],
    );
  }

  Widget _buildBatchesTab(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingSafeH,
          AppConstants.spacingGutter,
          AppConstants.spacingSafeH,
          32,
        ),
        children: [
          _buildInventorySummaryStats(context, l10n, cs, sagana),
          if (_inventoryData.lowStockCount > 0) ...[
            const SizedBox(height: AppConstants.spacingMd),
            _buildLowStockAlert(context, l10n, cs),
          ],
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildStockByCrop(context, l10n, cs, sagana),
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildBatchesSection(context, l10n, cs, sagana),
        ],
      ),
    );
  }

  Widget _buildInventorySummaryStats(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Row(
      children: [
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.check_circle_rounded,
            label: l10n.reportsAvailable,
            value: '${_inventoryData.totalAvailableKg.toStringAsFixed(0)} kg',
            accent: AppConstants.successGreen,
          ),
        ),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.bookmark_rounded,
            label: l10n.reportsReserved,
            value: '${_inventoryData.totalReservedKg.toStringAsFixed(0)} kg',
            accent: AppConstants.buyerBlue,
          ),
        ),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.sell_rounded,
            label: l10n.reportsSold,
            value: '${_inventoryData.totalSoldKg.toStringAsFixed(0)} kg',
            accent: AppConstants.amber,
          ),
        ),
      ],
    );
  }

  Widget _buildLowStockAlert(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppConstants.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: AppConstants.errorRed.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: AppConstants.errorRed,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.reportsLowStockAlert(_inventoryData.lowStockCount),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppConstants.errorRed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockByCrop(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    if (_inventoryData.cropBreakdown.isEmpty) return const SizedBox.shrink();
    final maxKg = _inventoryData.cropBreakdown.first.totalKg;

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
          Text(
            l10n.reportsStockByCrop,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          ..._inventoryData.cropBreakdown.map((c) {
            final fraction = maxKg > 0
                ? (c.totalKg / maxKg).clamp(0.0, 1.0)
                : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        c.cropName,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${c.totalKg.toStringAsFixed(0)} kg',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 6,
                      backgroundColor: cs.outline.withValues(alpha: 0.12),
                      valueColor: const AlwaysStoppedAnimation(
                        AppConstants.primaryGreen,
                      ),
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

  Widget _buildBatchesSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final filtered = _filteredBatches;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.reportsInventoryBatches,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _BatchStatusFilter.values.map((s) {
              final active = _statusFilter == s;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    s.label(l10n),
                    style: GoogleFonts.inter(fontSize: 12),
                  ),
                  selected: active,
                  onSelected: (_) => setState(() => _statusFilter = s),
                  selectedColor: AppConstants.primaryGreen,
                  labelStyle: TextStyle(
                    color: active ? Colors.white : cs.onSurface,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_inventoryData.batches.isNotEmpty)
          TextField(
            controller: _inventorySearchController,
            onChanged: (v) => setState(() => _inventorySearchQuery = v),
            decoration: InputDecoration(
              hintText: l10n.reportsSearchBatches,
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: cs.outline,
                size: 20,
              ),
              suffixIcon: _inventorySearchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: cs.outline,
                        size: 18,
                      ),
                      onPressed: () {
                        _inventorySearchController.clear();
                        setState(() => _inventorySearchQuery = '');
                      },
                    )
                  : null,
            ),
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
          ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_inventoryData.batches.isEmpty)
          ReportEmptyState(message: l10n.reportsNoInventoryYet)
        else if (filtered.isEmpty)
          ReportEmptyState(message: l10n.reportsNoSearchResults)
        else
          ...filtered.map((b) => _buildBatchRow(context, b, l10n, cs, sagana)),
      ],
    );
  }

  Widget _buildBatchRow(
    BuildContext context,
    InventoryReportRow batch,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final statusColor = batch.isLowStock
        ? AppConstants.errorRed
        : batch.status == 'sold_out'
        ? AppConstants.buyerBlue
        : AppConstants.successGreen;

    return GestureDetector(
      onTap: () => context.push(AppRoutes.farmerDetails, extra: batch.farmerId),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: batch.isLowStock
                ? AppConstants.errorRed.withValues(alpha: 0.3)
                : cs.outline.withValues(alpha: 0.10),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${batch.cropName} • ${batch.batchNumber}',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${batch.farmerName} • ${batch.memberId}',
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
            const SizedBox(height: AppConstants.spacingMd),
            Row(
              children: [
                _batchStat(
                  l10n.reportsHarvestedQty,
                  '${batch.quantityKg.toStringAsFixed(0)} kg',
                  cs,
                ),
                _batchStat(
                  l10n.reportsAvailable,
                  '${batch.availableKg.toStringAsFixed(0)} kg',
                  cs,
                ),
                _batchStat(
                  l10n.reportsReserved,
                  '${batch.reservedKg.toStringAsFixed(0)} kg',
                  cs,
                ),
                _batchStat(
                  l10n.reportsSold,
                  '${batch.soldKg.toStringAsFixed(0)} kg',
                  cs,
                ),
              ],
            ),
            if (batch.isLowStock) ...[
              const SizedBox(height: AppConstants.spacingSm),
              Text(
                l10n.reportsLowStockBadge,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _viewHarvest(batch),
                icon: const Icon(Icons.agriculture_outlined, size: 14),
                label: Text(
                  l10n.reportsViewHarvest,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppConstants.primaryGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _batchStat(String label, String value, ColorScheme cs) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 9, color: cs.onSurfaceVariant),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
