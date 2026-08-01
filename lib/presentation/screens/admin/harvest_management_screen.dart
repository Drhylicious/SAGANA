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

/// Harvest Management — Admin.
/// Pushed above the shell via rootNavigatorKey. Route: /admin/reports/harvest
///
/// Replaces the separate Harvest Report and Inventory Report screens/routes.
/// Two internal tabs over two DELIBERATELY SEPARATE data sources:
///   - Activity & Trends  → harvest_records (period-scoped event log)
///   - Batches & Stock    → inventory_batches (unfiltered live snapshot)
/// fetchHarvestReport() and fetchInventoryReport() remain independent
/// repository calls — this screen only adds navigation/traceability
/// between their results via the batch_number they share.
class HarvestManagementScreen extends StatefulWidget {
  const HarvestManagementScreen({super.key});

  @override
  State<HarvestManagementScreen> createState() =>
      _HarvestManagementScreenState();
}

class _HarvestManagementScreenState extends State<HarvestManagementScreen>
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    ]);
    if (!mounted) return;
    setState(() {
      _harvestData = results[0] as HarvestReportData;
      _inventoryData = results[1] as InventoryReportData;
      _isLoading = false;
    });
  }

  /// Inventory is an unfiltered snapshot, so only the harvest half needs
  /// to refetch when the period chip changes.
  Future<void> _setPeriod(ReportPeriod period) async {
    setState(() => _period = period);
    final data = await _repo.fetchHarvestReport(period);
    if (!mounted) return;
    setState(() => _harvestData = data);
  }

  List<HarvestReportRow> get _filteredHarvests {
    if (_harvestSearchQuery.isEmpty) return _harvestData.harvests;
    final q = _harvestSearchQuery.toLowerCase();
    return _harvestData.harvests
        .where((h) =>
            h.farmerName.toLowerCase().contains(q) ||
            h.memberId.toLowerCase().contains(q) ||
            h.cropName.toLowerCase().contains(q) ||
            h.batchNumber.toLowerCase().contains(q))
        .toList();
  }

  List<InventoryReportRow> get _filteredBatches {
    var list =
        _inventoryData.batches.where((b) => _statusFilter.matches(b)).toList();
    if (_inventorySearchQuery.isNotEmpty) {
      final q = _inventorySearchQuery.toLowerCase();
      list = list
          .where((b) =>
              b.farmerName.toLowerCase().contains(q) ||
              b.memberId.toLowerCase().contains(q) ||
              b.cropName.toLowerCase().contains(q) ||
              b.batchNumber.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: AppConstants.warningAmber,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
    ));
  }

  /// Harvest → Batch. Auto-created at harvest time, but the insert is
  /// best-effort on the farmer side (see HarvestEntryRepository.submitHarvest
  /// — a failed batch insert never blocks the harvest submission), so a
  /// harvest with no matching batch is a real, if rare, possibility.
  void _viewBatch(HarvestReportRow harvest) {
    final match = _inventoryData.batches
        .where((b) => b.batchNumber == harvest.batchNumber);
    if (match.isEmpty) {
      _showSnack(
        AppLocalizations.of(context).reportsNoBatchFound,
      );
      return;
    }
    setState(() {
      _inventorySearchController.text = harvest.batchNumber;
      _inventorySearchQuery = harvest.batchNumber;
    });
    _tabController.animateTo(1);
  }

  /// Batch → Harvest. The FK (harvest_record_id, NOT NULL) guarantees the
  /// source harvest always exists, but it may sit outside the currently
  /// selected period filter — inventory has no period filter, so a batch
  /// can be visible while its harvest is temporarily hidden. Widen to All
  /// Time automatically rather than surfacing a dead end.
  Future<void> _viewHarvest(InventoryReportRow batch) async {
    var match = _harvestData.harvests
        .where((h) => h.batchNumber == batch.batchNumber);

    if (match.isEmpty && _period != ReportPeriod.allTime) {
      final widened = await _repo.fetchHarvestReport(ReportPeriod.allTime);
      if (!mounted) return;
      match =
          widened.harvests.where((h) => h.batchNumber == batch.batchNumber);
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

  // ─── Top bar ──────────────────────────────────────────────────────────

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
          padding:
              const EdgeInsets.symmetric(horizontal: AppConstants.spacingSm),
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
                      color: cs.primary),
                ),
              ),
              IconButton(
                icon: Icon(Icons.file_download_outlined,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                onPressed: () => context.push(
                  AppRoutes.exportCenter,
                  extra: ExportCenterArgs(
                    preselectedModule: _tabController.index == 0
                        ? ReportModuleType.harvest
                        : ReportModuleType.inventory,
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

  // ─── Executive header (combines both datasets) ─────────────────────────

  Widget _buildExecutiveHeader(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppConstants.spacingSafeH,
        AppConstants.spacingMd,
        AppConstants.spacingSafeH,
        0,
      ),
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        gradient: AppConstants.primaryButtonGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        children: [
          Expanded(
            child: _headerStat(
              l10n.reportsTotalYield,
              '${_harvestData.totalYieldKg.toStringAsFixed(0)} kg',
              _period.label,
            ),
          ),
          Container(
              width: 1,
              height: 34,
              color: Colors.white.withValues(alpha: 0.25)),
          const SizedBox(width: AppConstants.spacingMd),
          Expanded(
            child: _headerStat(
              l10n.reportsTotalAvailableStock,
              '${_inventoryData.totalAvailableKg.toStringAsFixed(0)} kg',
              l10n.reportsLiveLabel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value, String scopeLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(fontSize: 10, color: Colors.white70)),
        Text(value,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: Colors.white)),
        Text(scopeLabel,
            style: GoogleFonts.inter(
                fontSize: 9, color: Colors.white.withValues(alpha: 0.6))),
      ],
    );
  }

  // ─── Tab bar ────────────────────────────────────────────────────────────

  Widget _buildTabBar(
      BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      margin: const EdgeInsets.only(top: AppConstants.spacingMd),
      child: TabBar(
        controller: _tabController,
        labelColor: AppConstants.primaryGreen,
        unselectedLabelColor: cs.onSurfaceVariant,
        indicatorColor: AppConstants.primaryGreen,
        labelStyle:
            GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
        onTap: (_) => setState(() {}), // refresh export-icon module target
        tabs: [
          Tab(text: l10n.reportsActivityTrendsTab),
          Tab(text: l10n.reportsBatchesStockTab),
        ],
      ),
    );
  }

  // ─── Tab 1: Activity & Trends ───────────────────────────────────────────

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
          _buildPeriodChips(cs),
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

  Widget _buildHarvestSummaryStats(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Row(
      children: [
        Expanded(
          child: _statCard(l10n.reportsTotalYield,
              '${_harvestData.totalYieldKg.toStringAsFixed(0)} kg',
              AppConstants.primaryGreen, cs, sagana),
        ),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(
          child: _statCard(l10n.reportsGradeAShare,
              '${_harvestData.gradeAPercent.toStringAsFixed(0)}%',
              AppConstants.successGreen, cs, sagana),
        ),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(
          child: _statCard(l10n.reportsUnsyncedEntries,
              '${_harvestData.unsyncedCount}', AppConstants.warningAmber, cs,
              sagana),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, Color accent, ColorScheme cs,
      SaganaColors sagana) {
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
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(height: AppConstants.spacingSm),
          Text(value,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: cs.onSurface)),
          Text(label,
              style:
                  GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
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
          Text(l10n.reportsYieldByCrop,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: cs.onSurface)),
          const SizedBox(height: AppConstants.spacingMd),
          ..._harvestData.cropBreakdown.map((c) {
            final fraction =
                maxKg > 0 ? (c.totalKg / maxKg).clamp(0.0, 1.0) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(c.cropName,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: cs.onSurface)),
                      Text('${c.totalKg.toStringAsFixed(0)} kg',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: cs.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 6,
                      backgroundColor: cs.outline.withValues(alpha: 0.12),
                      valueColor: const AlwaysStoppedAnimation(
                          AppConstants.primaryGreen),
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
          Text(l10n.reportsYieldTrend,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: cs.onSurface)),
          const SizedBox(height: AppConstants.spacingSm),
          SizedBox(
            height: 120,
            child: _harvestData.monthlyTrend.length < 2
                ? Center(
                    child: Text(l10n.reportsNotEnoughTrendData,
                        style:
                            GoogleFonts.inter(fontSize: 12, color: cs.outline)),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 120),
                    painter: TrendChartPainter(
                      values: _harvestData.monthlyTrend,
                      lineColor: cs.primary,
                      gradientColor: cs.primary,
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
        Text(l10n.reportsHarvestEntries,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: cs.onSurface)),
        const SizedBox(height: AppConstants.spacingSm),
        if (_harvestData.harvests.isNotEmpty)
          TextField(
            controller: _harvestSearchController,
            onChanged: (v) => setState(() => _harvestSearchQuery = v),
            decoration: InputDecoration(
              hintText: l10n.reportsSearchHarvestsWithBatch,
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              prefixIcon: Icon(Icons.search_rounded, color: cs.outline, size: 20),
              suffixIcon: _harvestSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded, color: cs.outline, size: 18),
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
          _buildEmptyState(l10n.reportsNoHarvestsRecorded, cs)
        else if (filtered.isEmpty)
          _buildEmptyState(l10n.reportsNoSearchResults, cs)
        else
          ...filtered.map((h) => _buildHarvestRow(context, h, l10n, cs, sagana)),
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
    return Container(
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
                  '${harvest.cropName} • ${harvest.qualityGrade}',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: cs.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${harvest.quantityKg.toStringAsFixed(0)} kg',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: cs.onSurface)),
            ],
          ),
          Text(
            '${harvest.farmerName} • ${harvest.memberId} • ${DateFormat('MMM d, yyyy').format(harvest.harvestDate)}',
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Batch #${harvest.batchNumber}',
            style: GoogleFonts.inter(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant),
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
                label: Text(l10n.reportsViewBatch,
                    style: GoogleFonts.inter(
                        fontSize: 11, fontWeight: FontWeight.w600)),
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
    );
  }

  Widget _statusChip(
      {required IconData icon, required String label, required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: color)),
      ],
    );
  }

  // ─── Tab 2: Batches & Stock ─────────────────────────────────────────────

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
          child: _statCard(l10n.reportsAvailable,
              '${_inventoryData.totalAvailableKg.toStringAsFixed(0)} kg',
              AppConstants.successGreen, cs, sagana),
        ),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(
          child: _statCard(l10n.reportsReserved,
              '${_inventoryData.totalReservedKg.toStringAsFixed(0)} kg',
              AppConstants.buyerBlue, cs, sagana),
        ),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(
          child: _statCard(l10n.reportsSold,
              '${_inventoryData.totalSoldKg.toStringAsFixed(0)} kg',
              AppConstants.amber, cs, sagana),
        ),
      ],
    );
  }

  Widget _buildLowStockAlert(
      BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppConstants.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppConstants.errorRed.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: AppConstants.errorRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.reportsLowStockAlert(_inventoryData.lowStockCount),
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed),
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
          Text(l10n.reportsStockByCrop,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: cs.onSurface)),
          const SizedBox(height: AppConstants.spacingMd),
          ..._inventoryData.cropBreakdown.map((c) {
            final fraction =
                maxKg > 0 ? (c.totalKg / maxKg).clamp(0.0, 1.0) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(c.cropName,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: cs.onSurface)),
                      Text('${c.totalKg.toStringAsFixed(0)} kg',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: cs.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 6,
                      backgroundColor: cs.outline.withValues(alpha: 0.12),
                      valueColor: const AlwaysStoppedAnimation(
                          AppConstants.primaryGreen),
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
        Text(l10n.reportsInventoryBatches,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: cs.onSurface)),
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
                  label: Text(s.label(l10n), style: GoogleFonts.inter(fontSize: 12)),
                  selected: active,
                  onSelected: (_) => setState(() => _statusFilter = s),
                  selectedColor: AppConstants.primaryGreen,
                  labelStyle:
                      TextStyle(color: active ? Colors.white : cs.onSurface),
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
              prefixIcon: Icon(Icons.search_rounded, color: cs.outline, size: 20),
              suffixIcon: _inventorySearchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded, color: cs.outline, size: 18),
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
          _buildEmptyState(l10n.reportsNoInventoryYet, cs)
        else if (filtered.isEmpty)
          _buildEmptyState(l10n.reportsNoSearchResults, cs)
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

    return Container(
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
                          color: cs.onSurface),
                    ),
                    Text(
                      '${batch.farmerName} • ${batch.memberId}',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: batch.qualityGrade == 'Grade Pending'
                      ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
                      : AppConstants.primaryGreen.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  batch.qualityGrade,
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: batch.qualityGrade == 'Grade Pending'
                        ? cs.onSurfaceVariant
                        : AppConstants.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              // Original harvested quantity, alongside the live remainder —
              // both already exist on InventoryReportRow (quantityKg vs
              // availableKg); this just makes the depletion visible.
              _batchStat(l10n.reportsHarvestedQty,
                  '${batch.quantityKg.toStringAsFixed(0)} kg', cs),
              _batchStat(l10n.reportsAvailable,
                  '${batch.availableKg.toStringAsFixed(0)} kg', cs),
              _batchStat(l10n.reportsReserved,
                  '${batch.reservedKg.toStringAsFixed(0)} kg', cs),
              _batchStat(
                  l10n.reportsSold, '${batch.soldKg.toStringAsFixed(0)} kg', cs),
            ],
          ),
          if (batch.isLowStock) ...[
            const SizedBox(height: AppConstants.spacingSm),
            Text(l10n.reportsLowStockBadge,
                style: GoogleFonts.poppins(
                    fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _viewHarvest(batch),
              icon: const Icon(Icons.agriculture_outlined, size: 14),
              label: Text(l10n.reportsViewHarvest,
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w600)),
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
    );
  }

  Widget _batchStat(String label, String value, ColorScheme cs) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(fontSize: 9, color: cs.onSurfaceVariant)),
          Text(value,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 11, color: cs.onSurface)),
        ],
      ),
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
      child: Text(message,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
    );
  }
}
