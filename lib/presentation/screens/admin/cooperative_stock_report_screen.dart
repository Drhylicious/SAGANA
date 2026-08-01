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

enum _StockFilter { all, lowStock }

/// Cooperative Stock Report — Admin.
/// Pushed above the shell. Route: /admin/reports/coop-stock
///
/// Reports on cooperative_inventory exclusively — the co-op's own owned
/// stock, distinct from the Farmer Harvest Report (inventory_batches).
/// Deliberately reports item counts, never a summed quantity_on_hand —
/// that table spans multiple units (bag/kg/sack/piece/liter/set/bottle),
/// so a single summed number would be meaningless.
class CooperativeStockReportScreen extends StatefulWidget {
  const CooperativeStockReportScreen({super.key});

  @override
  State<CooperativeStockReportScreen> createState() =>
      _CooperativeStockReportScreenState();
}

class _CooperativeStockReportScreenState
    extends State<CooperativeStockReportScreen> {
  final _repo = AdminReportsRepository();
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String _searchQuery = '';
  _StockFilter _filter = _StockFilter.all;
  CoopStockReportData _data = CoopStockReportData.empty;

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
    final data = await _repo.fetchCoopStockReport();
    if (!mounted) return;
    setState(() {
      _data = data;
      _isLoading = false;
    });
  }

  List<CoopStockReportRow> get _filteredItems {
    var list = _filter == _StockFilter.lowStock
        ? _data.items.where((i) => i.isLowStock).toList()
        : _data.items;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where(
            (i) =>
                i.itemName.toLowerCase().contains(q) ||
                i.category.toLowerCase().contains(q),
          )
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
                        _buildCategoryBreakdown(context, l10n, cs, sagana),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        _buildItemsSection(context, l10n, cs, sagana),
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
                  l10n.reportsCoopStockReport,
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
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                ),
                onPressed: () => context.push(
                  AppRoutes.exportCenter,
                  extra: const ExportCenterArgs(
                    preselectedModule: ReportModuleType.coopStock,
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
        Expanded(
          child: _statCard(
            l10n.reportsTotalItems,
            '${_data.totalItems}',
            AppConstants.buyerBlue,
            cs,
            sagana,
          ),
        ),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(
          child: _statCard(
            l10n.reportsLowStockItems,
            '${_data.lowStockCount}',
            AppConstants.errorRed,
            cs,
            sagana,
          ),
        ),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(
          child: _statCard(
            l10n.reportsCategories,
            '${_data.categoryCounts.length}',
            AppConstants.amber,
            cs,
            sagana,
          ),
        ),
      ],
    );
  }

  Widget _statCard(
    String label,
    String value,
    Color accent,
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
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: cs.onSurface,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockAlert(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: cs.error, size: 18),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(
            child: Text(
              l10n.reportsLowStockAlert(_data.lowStockCount),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onErrorContainer,
              ),
            ),
          ),
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
    if (_data.categoryCounts.isEmpty) return const SizedBox.shrink();
    final maxCount = _data.categoryCounts.values.reduce(
      (a, b) => a > b ? a : b,
    );

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
            l10n.reportsCoopStockByCategory,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          ..._data.categoryCounts.entries.map((entry) {
            final fraction = maxCount > 0 ? entry.value / maxCount : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        entry.key,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${entry.value} items',
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

  Widget _buildItemsSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final filtered = _filteredItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.reportsCoopStockItems,
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
            children: _StockFilter.values.map((f) {
              final active = _filter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    f == _StockFilter.all
                        ? l10n.reportsAll
                        : l10n.reportsLowStockItems,
                    style: GoogleFonts.inter(fontSize: 12),
                  ),
                  selected: active,
                  onSelected: (_) => setState(() => _filter = f),
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
        if (_data.items.isNotEmpty)
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: l10n.reportsSearchItems,
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
        if (_data.items.isEmpty)
          _buildEmptyState(l10n.reportsNoCoopStockYet, cs)
        else if (filtered.isEmpty)
          _buildEmptyState(l10n.reportsNoSearchResults, cs)
        else
          ...filtered.map((i) => _buildItemRow(context, i, cs, sagana)),
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

  Widget _buildItemRow(
    BuildContext context,
    CoopStockReportRow item,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: item.isLowStock
              ? AppConstants.errorRed.withValues(alpha: 0.3)
              : cs.outline.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  item.category,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.quantityOnHand.toStringAsFixed(item.quantityOnHand % 1 == 0 ? 0 : 1)} ${item.unit}',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
              if (item.isLowStock)
                Text(
                  l10n(context).reportsLowStockBadge,
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.errorRed,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  AppLocalizations l10n(BuildContext context) => AppLocalizations.of(context);
}
