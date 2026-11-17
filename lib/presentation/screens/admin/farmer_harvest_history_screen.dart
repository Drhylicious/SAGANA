import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/models/harvest_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/repositories/harvest_repository.dart';
import '../../widgets/crop_category_chips.dart';
import '../../widgets/harvest_details_sheet.dart';
import '../../widgets/harvest_log_widgets.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// Admin's read-only view of one farmer's Harvest History — mirrors the
/// farmer-facing screen (harvest_history_screen.dart) exactly: same KPI
/// row, same category chips, same list/detail presentation. No action a
/// farmer couldn't already take is exposed here (there's no delete/edit
/// anywhere on the farmer side of this screen either) — Admin just reads
/// the same records.
class AdminFarmerHarvestHistoryScreen extends StatefulWidget {
  const AdminFarmerHarvestHistoryScreen({super.key, this.farmerId});

  final String? farmerId;

  @override
  State<AdminFarmerHarvestHistoryScreen> createState() =>
      _AdminFarmerHarvestHistoryScreenState();
}

class _AdminFarmerHarvestHistoryScreenState
    extends State<AdminFarmerHarvestHistoryScreen> {
  final _repo = HarvestRepository();
  final _cropRepo = CropRepository();
  final _searchController = TextEditingController();

  List<HarvestModel> _allHarvests = [];
  List<HarvestModel> _filtered = [];
  Map<String, FarmerCropModel> _cropsById = {};

  String _activeCategory = CropCategoryChips.all;
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.farmerId == null) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchAllHarvestsForFarmer(widget.farmerId!),
      _cropRepo.fetchCropsByIdForFarmer(widget.farmerId!),
    ]);
    if (!mounted) return;
    setState(() {
      _allHarvests = results[0] as List<HarvestModel>;
      _cropsById = results[1] as Map<String, FarmerCropModel>;
      _applyFilters();
      _isLoading = false;
    });
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _applyFilters();
    });
  }

  void _setCategory(String category) {
    setState(() {
      _activeCategory = category;
      _applyFilters();
    });
  }

  List<String> get _categories =>
      (_allHarvests.map((h) => h.cropCategory).toSet().toList()..sort());

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    _filtered = _allHarvests.where((h) {
      if (_activeCategory != CropCategoryChips.all &&
          h.cropCategory != _activeCategory) {
        return false;
      }
      if (q.isEmpty) return true;
      return h.cropName.toLowerCase().contains(q) ||
          (h.variety?.toLowerCase().contains(q) ?? false) ||
          (h.batchNumber?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  double get _thisYearYieldKg {
    final year = DateTime.now().year;
    return _allHarvests
        .where((h) => h.harvestDate.year == year && isKg(h.unit))
        .fold(0.0, (sum, h) => sum + h.quantityKg);
  }

  int get _unsyncedCount => _allHarvests.where((h) => !h.isSynced).length;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            SubPageTopBar(
              title: l10n.farmerHarvestHistoryTitle,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: widget.farmerId == null
                  ? Center(
                      child: Text(l10n.farmerHarvestHistoryNoFarmerSelected),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        children: [
                          _AdminHistoryStatsRow(
                            totalHarvestCount: _allHarvests.length,
                            thisYearYieldKg: _thisYearYieldKg,
                            unsyncedCount: _unsyncedCount,
                            isLoading: _isLoading,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: l10n.farmerHarvestHistorySearchHint,
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 20,
                              ),
                              filled: true,
                              fillColor: sagana.cardBackground,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppConstants.radiusMd,
                                ),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (!_isLoading)
                            CropCategoryChips(
                              categories: _categories,
                              active: _activeCategory,
                              counts: CropCategoryChips.countBy(
                                _allHarvests,
                                (h) => h.cropCategory,
                              ),
                              onSelected: _setCategory,
                            ),
                          const SizedBox(height: 16),
                          if (_isLoading)
                            const Padding(
                              padding: EdgeInsets.only(top: 40),
                              child: SkeletonList(),
                            )
                          else if (_filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: Center(
                                child: Text(
                                  _searchQuery.isNotEmpty ||
                                          _activeCategory !=
                                              CropCategoryChips.all
                                      ? AppLocalizations.of(
                                          context,
                                        ).enhNoMatchingHarvestsTryADifferentSearchOr
                                      : l10n.farmerHarvestHistoryNoRecords,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          else
                            ..._filtered.map(
                              (h) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: GestureDetector(
                                  onTap: () => showHarvestDetailsSheet(
                                    context,
                                    harvest: h,
                                    crop: _cropsById[h.cropId],
                                  ),
                                  child: HarvestLogEntry(
                                    harvest: h,
                                    imageUrl:
                                        _cropsById[h.cropId]?.displayImageUrl,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats Row — identical structure to the farmer-facing screen's
// _HistoryStatsRow (harvest_history_screen.dart): Total Harvest (all-time
// count) | This Year's Yield (calendar-year-to-date kg) | Sync Status.
// ─────────────────────────────────────────────────────────────────────────────

class _AdminHistoryStatsRow extends StatelessWidget {
  final int totalHarvestCount;
  final double thisYearYieldKg;
  final int unsyncedCount;
  final bool isLoading;

  const _AdminHistoryStatsRow({
    required this.totalHarvestCount,
    required this.thisYearYieldKg,
    required this.unsyncedCount,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final yieldLabel = thisYearYieldKg % 1 == 0
        ? thisYearYieldKg.toStringAsFixed(0)
        : thisYearYieldKg.toStringAsFixed(1);
    final hasUnsynced = unsyncedCount > 0;

    return Row(
      children: [
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.calendar_month_rounded,
            accent: AppConstants.primaryGreen,
            label: AppLocalizations.of(context).reportsTotalHarvest,
            value: isLoading ? '—' : '$totalHarvestCount',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.eco_rounded,
            accent: AppConstants.successGreen,
            label: AppLocalizations.of(context).enhThisYearSYield,
            value: isLoading ? '—' : '$yieldLabel kg',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ReportIconStatCard(
            icon: hasUnsynced
                ? Icons.sync_rounded
                : Icons.check_circle_outline_rounded,
            accent: hasUnsynced
                ? AppConstants.warningAmber
                : AppConstants.successGreen,
            label: AppLocalizations.of(context).enhSyncStatus,
            value: isLoading
                ? '—'
                : hasUnsynced
                ? AppLocalizations.of(
                    context,
                  ).enhUnsynced((unsyncedCount).toString())
                : AppLocalizations.of(context).reportsSynced,
          ),
        ),
      ],
    );
  }
}
