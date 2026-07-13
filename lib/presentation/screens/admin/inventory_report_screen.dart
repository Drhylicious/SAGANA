import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../routes/app_routes.dart';

enum _GradeFilter { all, gradeA, gradeB, gradeC }

extension on _GradeFilter {
  String get label {
    switch (this) {
      case _GradeFilter.all:
        return 'All';
      case _GradeFilter.gradeA:
        return 'Grade A';
      case _GradeFilter.gradeB:
        return 'Grade B';
      case _GradeFilter.gradeC:
        return 'Grade C';
    }
  }

  bool matches(InventoryReportRow row) {
    if (this == _GradeFilter.all) return true;
    return row.qualityGrade == label;
  }
}

/// Inventory Report — Admin.
/// Pushed above the shell. Route: /admin/reports/inventory
///
/// No period filter — this reports current stock levels, a snapshot, not
/// something scoped to a date range. Available/Reserved/Sold are real
/// stored columns on inventory_batches; no cross-referencing required.
class InventoryReportScreen extends StatefulWidget {
  const InventoryReportScreen({super.key});

  @override
  State<InventoryReportScreen> createState() => _InventoryReportScreenState();
}

class _InventoryReportScreenState extends State<InventoryReportScreen> {
  final _repo = AdminReportsRepository();
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String _searchQuery = '';
  _GradeFilter _gradeFilter = _GradeFilter.all;
  InventoryReportData _data = InventoryReportData.empty();

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
    final data = await _repo.fetchInventoryReport();
    if (!mounted) return;
    setState(() {
      _data = data;
      _isLoading = false;
    });
  }

  List<InventoryReportRow> get _filteredBatches {
    var list = _data.batches.where((b) => _gradeFilter.matches(b)).toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
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
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.spacingSafeH,
                        AppConstants.spacingGutter,
                        AppConstants.spacingSafeH,
                        32,
                      ),
                      children: [
                        _buildSummaryStats(context, l10n, cs, sagana),
                        if (_data.lowStockCount > 0) ...[
                          const SizedBox(height: AppConstants.spacingMd),
                          _buildLowStockAlert(context, l10n, cs),
                        ],
                        const SizedBox(height: AppConstants.spacingSectionV),
                        _buildCropBreakdown(context, l10n, cs, sagana),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        _buildBatchesSection(context, l10n, cs, sagana),
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
                  l10n.reportsInventoryReport,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: cs.primary),
                ),
              ),
              IconButton(
                icon: Icon(Icons.file_download_outlined, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                onPressed: () => context.push(
                  AppRoutes.exportCenter,
                  extra: const ExportCenterArgs(
                    preselectedModule: ReportModuleType.inventory,
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

  Widget _buildSummaryStats(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Row(
      children: [
        Expanded(child: _statCard(l10n.reportsAvailable, '${_data.totalAvailableKg.toStringAsFixed(0)} kg', AppConstants.successGreen, cs, sagana)),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(child: _statCard(l10n.reportsReserved, '${_data.totalReservedKg.toStringAsFixed(0)} kg', AppConstants.buyerBlue, cs, sagana)),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(child: _statCard(l10n.reportsSold, '${_data.totalSoldKg.toStringAsFixed(0)} kg', AppConstants.amber, cs, sagana)),
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

  Widget _buildLowStockAlert(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: AppConstants.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppConstants.errorRed.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppConstants.errorRed, size: 18),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(
            child: Text(
              l10n.reportsLowStockAlert(_data.lowStockCount),
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppConstants.errorRed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCropBreakdown(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    if (_data.cropBreakdown.isEmpty) return const SizedBox.shrink();
    final maxKg = _data.cropBreakdown.first.totalKg;

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
          Text(l10n.reportsStockByCrop, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
          const SizedBox(height: AppConstants.spacingMd),
          ..._data.cropBreakdown.map((c) {
            final fraction = maxKg > 0 ? (c.totalKg / maxKg).clamp(0.0, 1.0) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(c.cropName, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurface)),
                      Text('${c.totalKg.toStringAsFixed(0)} kg', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12, color: cs.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 6,
                      backgroundColor: cs.outline.withValues(alpha: 0.12),
                      valueColor: const AlwaysStoppedAnimation(AppConstants.primaryGreen),
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
        Text(l10n.reportsInventoryBatches, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
        const SizedBox(height: AppConstants.spacingSm),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _GradeFilter.values.map((g) {
              final active = _gradeFilter == g;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(g.label, style: GoogleFonts.inter(fontSize: 12)),
                  selected: active,
                  onSelected: (_) => setState(() => _gradeFilter = g),
                  selectedColor: AppConstants.primaryGreen,
                  labelStyle: TextStyle(color: active ? Colors.white : cs.onSurface),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_data.batches.isNotEmpty)
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: l10n.reportsSearchBatches,
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              prefixIcon: Icon(Icons.search_rounded, color: cs.outline, size: 20),
            ),
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
          ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_data.batches.isEmpty)
          _buildEmptyState(l10n.reportsNoInventoryYet, cs)
        else if (filtered.isEmpty)
          _buildEmptyState(l10n.reportsNoSearchResults, cs)
        else
          ...filtered.map((b) => _buildBatchRow(context, b, cs, sagana)),
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

  Widget _buildBatchRow(
    BuildContext context,
    InventoryReportRow batch,
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
            color: batch.isLowStock ? AppConstants.errorRed.withValues(alpha: 0.3) : cs.outline.withValues(alpha: 0.10),
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
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface),
                      ),
                      Text(
                        '${batch.farmerName} • ${batch.memberId}',
                        style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(
                    batch.qualityGrade,
                    style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingMd),
            Row(
              children: [
                _batchStat(l10n(context).reportsAvailable, '${batch.availableKg.toStringAsFixed(0)} kg', cs),
                _batchStat(l10n(context).reportsReserved, '${batch.reservedKg.toStringAsFixed(0)} kg', cs),
                _batchStat(l10n(context).reportsSold, '${batch.soldKg.toStringAsFixed(0)} kg', cs),
              ],
            ),
            if (batch.isLowStock) ...[
              const SizedBox(height: AppConstants.spacingSm),
              Text(
                l10n(context).reportsLowStockBadge,
                style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor),
              ),
            ],
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
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
          Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12, color: cs.onSurface)),
        ],
      ),
    );
  }

  AppLocalizations l10n(BuildContext context) => AppLocalizations.of(context);
}