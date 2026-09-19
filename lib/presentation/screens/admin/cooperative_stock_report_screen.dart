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
import '../../widgets/report_summary_widgets.dart';

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
  // null = All. Any other value = a real category name from
  // _data.categoryCounts. No separate Low Stock filter — the low-stock
  // alert banner and per-row badge already surface that.
  String? _filter;
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
    var list = _filter == null
        ? _data.items
        : _data.items.where((i) => i.category == _filter).toList();
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
                        _buildOverviewCard(context, l10n, cs, sagana),
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
                icon: Icon(Icons.file_download_outlined, color: cs.primary),
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

  /// Header + KPI row together in one bordered, padded card — matching
  /// the breathing room Harvest/Loan/Member Patronage's ReportHeroCard-
  /// based headers already have, rather than a bare header row sitting
  /// directly on the page background with only a small gap to the tiles.
  Widget _buildOverviewCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReportSectionHeader(
            icon: Icons.inventory_2_rounded,
            title: l10n.reportsStockOverview,
          ),
          const SizedBox(height: AppConstants.spacingMd),
          _buildSummaryStats(context, l10n, cs, sagana),
        ],
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
          child: ReportIconStatCard(
            icon: Icons.inventory_2_rounded,
            label: l10n.reportsTotalItems,
            value: '${_data.totalItems}',
            accent: AppConstants.buyerBlue,
          ),
        ),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.warning_amber_rounded,
            label: l10n.reportsLowStockItems,
            value: '${_data.lowStockCount}',
            accent: AppConstants.errorRed,
          ),
        ),
        const SizedBox(width: AppConstants.spacingSm),
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.category_rounded,
            label: l10n.reportsCategories,
            value: '${_data.categoryCounts.length}',
            accent: AppConstants.amber,
          ),
        ),
      ],
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
        if (_data.items.isNotEmpty)
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _StockFilterChip(
                  label: l10n.reportsAll,
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                  cs: cs,
                  sagana: sagana,
                ),
                // Dynamic, per-category chips built from whatever
                // categories are actually present in cooperative_inventory
                // right now — mirrors Inventory Management's own category
                // filter exactly (All + categories only; no separate Low
                // Stock chip, since the alert banner and per-row badge
                // already surface that).
                ..._data.categoryCounts.keys.map(
                  (category) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _StockFilterChip(
                      label: category,
                      selected: _filter == category,
                      onTap: () => setState(() => _filter = category),
                      cs: cs,
                      sagana: sagana,
                    ),
                  ),
                ),
              ],
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
          ReportEmptyState(message: l10n.reportsNoCoopStockYet)
        else if (filtered.isEmpty)
          ReportEmptyState(message: l10n.reportsNoSearchResults)
        else
          ...filtered.map((i) => _buildItemRow(context, i, cs, sagana)),
      ],
    );
  }

  Widget _buildItemRow(
    BuildContext context,
    CoopStockReportRow item,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.adminInventory, extra: item.category),
      child: Container(
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // The item's Inventory Management photo — same All Listings-
            // style placement as Loan Item Catalog, fetched through the
            // existing cooperative_inventory row rather than a separate
            // upload.
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              child: SizedBox(
                width: 52,
                height: 52,
                child: (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                    ? Image.network(
                        item.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(Icons.inventory_2_outlined,
                              size: 22, color: cs.outline.withValues(alpha: 0.4)),
                        ),
                      )
                    : Container(
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.inventory_2_outlined,
                            size: 22, color: cs.outline.withValues(alpha: 0.4)),
                      ),
              ),
            ),
            const SizedBox(width: 12),
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
      ),
    );
  }

  AppLocalizations l10n(BuildContext context) => AppLocalizations.of(context);
}

/// Same rounded pill styling as Inventory Management's private category
/// chip (admin_inventory_screen.dart's `_Chip`) — kept as a separate,
/// file-local widget since that one is library-private and this report is
/// a different file, not because the visual design should ever diverge.
class _StockFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _StockFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? cs.primary : sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: selected ? cs.primary : cs.outline.withValues(alpha: 0.20),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
