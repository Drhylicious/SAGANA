import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/models/harvest_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/repositories/harvest_repository.dart';
import '../../widgets/crop_category_chips.dart';
import '../../widgets/harvest_log_widgets.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/report_summary_widgets.dart';

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
        .where((h) => h.harvestDate.year == year)
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      l10n.farmerHarvestHistoryTitle,
                        style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
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
                              onSelected: _setCategory,
                            ),
                          const SizedBox(height: 16),
                          if (_isLoading)
                            const Center(
                              child: Padding(
                              padding: EdgeInsets.only(top: 40),
                                child: CircularProgressIndicator(
                                  color: AppConstants.primaryGreen,
                                ),
                              ),
                            )
                          else if (_filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: Center(
                                child: Text(
                                  _searchQuery.isNotEmpty ||
                                          _activeCategory !=
                                              CropCategoryChips.all
                                      ? 'No matching harvests. Try a different search or category.'
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
                                  onTap: () => _showAdminHarvestDetails(
                                    context,
                                    h,
                                    _cropsById[h.cropId],
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
            label: 'Total Harvest',
            value: isLoading ? '—' : '$totalHarvestCount',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.eco_rounded,
            accent: AppConstants.successGreen,
            label: "This Year's Yield",
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
            label: 'Sync Status',
            value: isLoading
                ? '—'
                : hasUnsynced
                ? '$unsyncedCount Unsynced'
                : 'Synced',
          ),
        ),
                        ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Harvest Details — read-only, same fields as the farmer-facing sheet
// (minus "Submitted to Cooperative", removed everywhere — see
// harvest_history_screen.dart's own note on why). No actions: this is
// Admin viewing, not managing, a farmer's record.
// ─────────────────────────────────────────────────────────────────────────────

void _showAdminHarvestDetails(
  BuildContext context,
  HarvestModel harvest,
  FarmerCropModel? crop,
) {
  showManagementModal<void>(
    context: context,
    builder: (_) => _AdminHarvestDetailsSheet(harvest: harvest, crop: crop),
  );
}

class _AdminHarvestDetailsSheet extends StatelessWidget {
  final HarvestModel harvest;
  final FarmerCropModel? crop;
  const _AdminHarvestDetailsSheet({required this.harvest, this.crop});

  // Same fix as the farmer-facing sheet (harvest_history_screen.dart) —
  // was omitted entirely when no crop photo existed instead of falling
  // back to the default crop icon.
  Widget _imagePlaceholder() {
    return Container(
      width: double.infinity,
      height: 140,
      color: AppConstants.primaryGreen.withValues(alpha: 0.10),
      child: const Icon(
        Icons.eco_rounded,
        color: AppConstants.primaryGreen,
        size: 40,
                      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ManagementModalShell(
      title: harvest.cropName,
      subtitle: harvest.variety != null && harvest.variety!.isNotEmpty
          ? harvest.variety
          : null,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: crop?.hasDisplayImage == true
                ? Image.network(
                    crop!.displayImageUrl!,
                    width: double.infinity,
                    height: 140,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _imagePlaceholder(),
                  )
                : _imagePlaceholder(),
          ),
          const SizedBox(height: 14),
          _AdminDetailRow(
            label: 'Quantity',
            value: '${harvest.quantityKg.toStringAsFixed(0)} kg',
          ),
          _AdminDetailRow(label: 'Category', value: harvest.cropCategory),
          _AdminDetailRow(
            label: 'Batch Number',
            value: harvest.batchNumber ?? '—',
          ),
          _AdminDetailRow(
            label: 'Storage Location',
            value: harvest.storageLocation ?? '—',
          ),
          _AdminDetailRow(
            label: 'Harvest Date',
            value: DateFormat(
              'MMM d, yyyy · h:mm a',
            ).format(harvest.harvestDate),
                    ),
          _AdminDetailRow(
            label: 'Sync Status',
            value: harvest.isSynced ? 'Synced' : 'Pending sync',
            isLast: true,
            ),
          ],
        ),
    );
  }
}

class _AdminDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;
  const _AdminDetailRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}