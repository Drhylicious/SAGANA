import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/report_ui_widgets.dart';
import '../../../core/utils/member_access.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../data/services/connectivity_service.dart';

enum _BatchStatusFilter { all, available, committed, lowStock, soldOut }

extension on _BatchStatusFilter {
  String label(AppLocalizations l10n) {
    switch (this) {
      case _BatchStatusFilter.all:
        return l10n.reportsAll;
      case _BatchStatusFilter.available:
        return l10n.rptStatusAvailable;
      case _BatchStatusFilter.committed:
        return l10n.rptStatusCommitted;
      case _BatchStatusFilter.lowStock:
        return l10n.rptStatusLowStock;
      case _BatchStatusFilter.soldOut:
        return l10n.rptStatusSoldOut;
    }
  }

  // The stored batch status for "Committed" is 'reserved' (the whole batch is
  // placed in a listing, offer or sale); the Manager sees it as Committed.
  bool matches(InventoryReportRow row) {
    switch (this) {
      case _BatchStatusFilter.all:
        return true;
      case _BatchStatusFilter.available:
        return row.status == 'available';
      case _BatchStatusFilter.committed:
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
/// Two internal tabs over two DELIBERATELY SEPARATE data sources:
///   - Activity & Trends  → harvest_records (period-scoped event log)
///   - Batches & Stock    → inventory_batches (unfiltered live snapshot)
/// fetchHarvestReport() and fetchInventoryReport() remain independent
/// repository calls — this screen only adds navigation/traceability
/// between their results via the batch_number they share. The period filter
/// lives inside the Activity tab, the only tab it applies to.
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
  bool _isOnline = ConnectivityService.instance.isOnline;
  HarvestReportData _harvestData = HarvestReportData.empty();
  InventoryReportData _inventoryData = InventoryReportData.empty();
  List<double> _yieldTrend = [];

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
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

  List<HarvestReportRow> get _filteredHarvests {
    if (_harvestSearchQuery.isEmpty) return _harvestData.harvests;
    final q = _harvestSearchQuery.toLowerCase();
    return _harvestData.harvests
        .where(
          (h) =>
              h.farmerName.toLowerCase().contains(q) ||
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
                b.cropName.toLowerCase().contains(q) ||
                b.batchNumber.toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  void _viewBatch(HarvestReportRow harvest) {
    final match = _inventoryData.batches.where(
      (b) => b.batchNumber == harvest.batchNumber,
    );
    if (match.isEmpty) {
      PostActionFeedback.error(
        context,
        AppLocalizations.of(context).reportsNoBatchFound,
      );
      return;
    }
    setState(() {
      _statusFilter = _BatchStatusFilter.all;
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
      PostActionFeedback.error(
        context,
        AppLocalizations.of(context).reportsNoHarvestFound,
      );
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

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.reportsHarvestManagement,
            onBack: () => context.pop(),
            // The export covers both tabs (Activity + Batches & Stock).
            trailing: IconButton(
              icon: Icon(Icons.file_download_outlined, color: cs.primary),
              onPressed: () => context.push(
                AppRoutes.exportCenter,
                extra: ExportCenterArgs(
                  preselectedModule: ReportModuleType.harvest,
                  period: _period,
                ),
              ),
              tooltip: l10n.reportsExportCenter,
            ),
          ),
          CachedDataNotice(
            screen: AdminReportsRepository.harvestCacheScreen(_period),
            isOnline: _isOnline,
            offlineMessage: l10n.offlineStaffBody,
          ),
          TabBar(
            controller: _tabController,
            labelColor: AppConstants.primaryGreen,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: AppConstants.primaryGreen,
            labelStyle: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
            tabs: [
              Tab(text: l10n.reportsActivityTrendsTab),
              Tab(text: l10n.reportsBatchesStockTab),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildActivityTab(context, l10n, cs),
                      _buildBatchesTab(context, l10n, cs),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  EdgeInsets get _tabPadding => const EdgeInsets.fromLTRB(
    AppConstants.spacingSafeH,
    AppConstants.spacingGutter,
    AppConstants.spacingSafeH,
    32,
  );

  // ─── Activity & Trends ────────────────────────────────────────────────────

  Widget _buildActivityTab(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final contributingFarmers = _harvestData.harvests
        .map((h) => h.farmerId)
        .toSet()
        .length;

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: _tabPadding,
        children: [
          ReportPeriodFilter(period: _period, onSelected: _setPeriod),
          const SizedBox(height: AppConstants.spacingGutter),
          ReportHeroCard(
            title: l10n.reportsHarvestOverview,
            period: _period,
            primaryStats: [
              ReportHeroStat(
                label: l10n.reportsTotalYield,
                value: '${_harvestData.totalYieldKg.toStringAsFixed(0)} kg',
                icon: Icons.agriculture_rounded,
                accent: AppConstants.primaryGreen,
              ),
              ReportHeroStat(
                label: l10n.reportsSold,
                value: '${_harvestData.soldKgInPeriod.toStringAsFixed(0)} kg',
                icon: Icons.sell_rounded,
                accent: AppConstants.buyerBlue,
              ),
            ],
            secondaryStats: [
              ReportHeroStat(
                label: l10n.rptHarvestEntriesStat,
                value: '${_harvestData.harvestCount}',
                icon: Icons.receipt_long_rounded,
                accent: AppConstants.amber,
              ),
              ReportHeroStat(
                label: l10n.rptContributingFarmers,
                value: '$contributingFarmers',
                icon: Icons.groups_rounded,
                accent: AppConstants.warningAmber,
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildYieldByCrop(l10n),
          if (_harvestData.cropBreakdown.isNotEmpty)
            const SizedBox(height: AppConstants.spacingSectionV),
          ReportTrendCard(
            title: l10n.reportsYieldTrend,
            values: _yieldTrend,
            valueFormatter: (v) => '${v.toStringAsFixed(0)}kg',
          ),
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildHarvestsSection(context, l10n, cs),
        ],
      ),
    );
  }

  Widget _buildYieldByCrop(AppLocalizations l10n) {
    if (_harvestData.cropBreakdown.isEmpty) return const SizedBox.shrink();
    final maxKg = _harvestData.cropBreakdown.first.totalKg;
    final total = _harvestData.totalYieldKg;

    return ReportSectionCard(
      title: l10n.reportsYieldByCrop,
      icon: Icons.grass_rounded,
      child: Column(
        children: _harvestData.cropBreakdown.map((c) {
          final share = total > 0 ? c.totalKg / total * 100 : 0.0;
          return ReportBarRow(
            label: c.cropName,
            valueText: '${c.totalKg.toStringAsFixed(0)} kg',
            fraction: maxKg > 0 ? c.totalKg / maxKg : 0,
            caption: l10n.rptShareOfTotal(share.toStringAsFixed(0)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHarvestsSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final filtered = _filteredHarvests;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.reportsHarvestEntries,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (_harvestData.harvests.isNotEmpty)
              Text(
                l10n.rptShowingCount(
                  filtered.length,
                  _harvestData.harvests.length,
                ),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_harvestData.harvests.isNotEmpty) ...[
          ReportSearchField(
            controller: _harvestSearchController,
            hint: l10n.reportsSearchHarvestsWithBatch,
            onChanged: (v) => setState(() => _harvestSearchQuery = v),
          ),
          const SizedBox(height: AppConstants.spacingMd),
        ],
        if (_harvestData.harvests.isEmpty)
          ReportEmptyState(message: l10n.reportsNoHarvestsRecorded)
        else if (filtered.isEmpty)
          ReportEmptyState(message: l10n.rptNoMatches)
        else
          ...filtered.map((h) => _buildHarvestRow(context, h, l10n, cs)),
      ],
    );
  }

  Widget _buildHarvestRow(
    BuildContext context,
    HarvestReportRow harvest,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return ReportRecordCard(
      onTap: membersAccessAllowed
          ? () => pushFarmerDetails(context, harvest.farmerId)
          : null,
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
                formatQuantityUnit(harvest.quantityKg, harvest.unit),
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${harvest.farmerName} • '
            '${DateFormat('MMM d, yyyy').format(harvest.harvestDate)}',
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.rptBatchNumber(formatBatchNumber(harvest.batchNumber)),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
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
    );
  }

  // ─── Batches & Stock ──────────────────────────────────────────────────────

  Widget _buildBatchesTab(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: _tabPadding,
        children: [
          ReportSectionCard(
            title: l10n.reportsStockOverview,
            icon: Icons.inventory_2_rounded,
            child: Row(
              children: [
                Expanded(
                  child: ReportIconStatCard(
                    icon: Icons.check_circle_rounded,
                    label: l10n.rptStatusAvailable,
                    value:
                        '${_inventoryData.totalAvailableKg.toStringAsFixed(0)} kg',
                    accent: AppConstants.successGreen,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingSm),
                Expanded(
                  child: ReportIconStatCard(
                    icon: Icons.bookmark_rounded,
                    label: l10n.rptCommitted,
                    value:
                        '${_inventoryData.totalReservedKg.toStringAsFixed(0)} kg',
                    accent: AppConstants.buyerBlue,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingSm),
                Expanded(
                  child: ReportIconStatCard(
                    icon: Icons.sell_rounded,
                    label: l10n.reportsSold,
                    value:
                        '${_inventoryData.totalSoldKg.toStringAsFixed(0)} kg',
                    accent: AppConstants.amber,
                  ),
                ),
              ],
            ),
          ),
          if (_inventoryData.lowStockCount > 0) ...[
            const SizedBox(height: AppConstants.spacingMd),
            _buildLowStockAlert(l10n),
          ],
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildStockByCrop(l10n),
          if (_inventoryData.cropBreakdown.isNotEmpty)
            const SizedBox(height: AppConstants.spacingSectionV),
          _buildBatchesSection(context, l10n, cs),
        ],
      ),
    );
  }

  Widget _buildLowStockAlert(AppLocalizations l10n) {
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

  Widget _buildStockByCrop(AppLocalizations l10n) {
    if (_inventoryData.cropBreakdown.isEmpty) return const SizedBox.shrink();
    final maxKg = _inventoryData.cropBreakdown.first.totalKg;

    return ReportSectionCard(
      title: l10n.reportsStockByCrop,
      icon: Icons.grass_rounded,
      subtitle: l10n.rptStatusAvailable,
      child: Column(
        children: _inventoryData.cropBreakdown
            .map(
              (c) => ReportBarRow(
                label: c.cropName,
                valueText: '${c.totalKg.toStringAsFixed(0)} kg',
                fraction: maxKg > 0 ? c.totalKg / maxKg : 0,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildBatchesSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final filtered = _filteredBatches;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.reportsInventoryBatches,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (_inventoryData.batches.isNotEmpty)
              Text(
                l10n.rptShowingCount(
                  filtered.length,
                  _inventoryData.batches.length,
                ),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_inventoryData.batches.isNotEmpty) ...[
          ReportSearchField(
            controller: _inventorySearchController,
            hint: l10n.reportsSearchBatches,
            onChanged: (v) => setState(() => _inventorySearchQuery = v),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          ReportFilterChips<_BatchStatusFilter>(
            options: [
              for (final s in _BatchStatusFilter.values)
                ReportFilterOption(s, s.label(l10n)),
            ],
            selected: _statusFilter,
            onSelected: (s) => setState(() => _statusFilter = s),
          ),
          const SizedBox(height: AppConstants.spacingMd),
        ],
        if (_inventoryData.batches.isEmpty)
          ReportEmptyState(message: l10n.reportsNoInventoryYet)
        else if (filtered.isEmpty)
          ReportEmptyState(message: l10n.rptNoMatches)
        else
          ...filtered.map((b) => _buildBatchRow(context, b, l10n, cs)),
      ],
    );
  }

  ({String label, Color color}) _batchStatus(
    AppLocalizations l10n,
    String status,
  ) {
    switch (status) {
      case 'low_stock':
        return (label: l10n.rptStatusLowStock, color: AppConstants.errorRed);
      case 'reserved':
        return (label: l10n.rptStatusCommitted, color: AppConstants.buyerBlue);
      case 'sold_out':
        return (label: l10n.rptStatusSoldOut, color: AppConstants.mutedSlate);
      case 'withdrawn':
        return (label: l10n.rptStatusWithdrawn, color: AppConstants.mutedBrown);
      default:
        return (
          label: l10n.rptStatusAvailable,
          color: AppConstants.successGreen,
        );
    }
  }

  Widget _buildBatchRow(
    BuildContext context,
    InventoryReportRow batch,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final status = _batchStatus(l10n, batch.status);

    return ReportRecordCard(
      borderColor: batch.isLowStock
          ? AppConstants.errorRed.withValues(alpha: 0.3)
          : null,
      onTap: membersAccessAllowed
          ? () => pushFarmerDetails(context, batch.farmerId)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${batch.cropName} • ${formatBatchNumber(batch.batchNumber)}',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      batch.farmerName,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ReportStatusPill(label: status.label, color: status.color),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              _batchStat(
                l10n.reportsHarvestedQty,
                formatQuantityUnit(batch.quantityKg, batch.unit),
                cs,
              ),
              _batchStat(
                l10n.rptStatusAvailable,
                formatQuantityUnit(batch.availableKg, batch.unit),
                cs,
              ),
              _batchStat(
                l10n.rptCommitted,
                formatQuantityUnit(batch.reservedKg, batch.unit),
                cs,
              ),
              _batchStat(
                l10n.reportsSold,
                formatQuantityUnit(batch.soldKg, batch.unit),
                cs,
              ),
            ],
          ),
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
    );
  }

  Widget _batchStat(String label, String value, ColorScheme cs) {
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
              fontSize: 11,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
