import '../../../core/theme/sagana_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/models/harvest_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/repositories/harvest_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/crop_category_chips.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/harvest_details_sheet.dart';
import '../../widgets/harvest_log_widgets.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../../core/l10n/app_localizations.dart';

class HarvestHistoryScreen extends StatefulWidget {
  final String? initialCropFilter;
  const HarvestHistoryScreen({super.key, this.initialCropFilter});

  @override
  State<HarvestHistoryScreen> createState() => _HarvestHistoryScreenState();
}

class _HarvestHistoryScreenState extends State<HarvestHistoryScreen> {
  final _repo = HarvestRepository();
  final _cropRepo = CropRepository();
  final _searchController = TextEditingController();

  List<HarvestModel> _allHarvests = [];
  List<HarvestModel> _filtered = [];
  Map<String, FarmerCropModel> _cropsById = {};
  HarvestStats _seasonStats = HarvestStats.empty;

  String _activeCategory = CropCategoryChips.all;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    // The deep link from Crop Roster's "View Harvests" names one specific
    // crop, not a category — pre-filling the search bar (rather than
    // selecting a category chip) keeps that exact-crop result while still
    // leaving every category chip available for browsing everything else.
    if (widget.initialCropFilter != null) {
      _searchController.text = widget.initialCropFilter!;
      _searchQuery = widget.initialCropFilter!;
    }
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchAllHarvests(),
      _repo.fetchStats(),
      _cropRepo.fetchCrops(),
    ]);
    if (!mounted) return;

    final harvests = results[0] as List<HarvestModel>;
    final crops = results[2] as List<FarmerCropModel>;

    setState(() {
      _allHarvests = harvests;
      _seasonStats = results[1] as HarvestStats;
      _cropsById = {for (final c in crops) c.id: c};
      _applyFilters();
      _isLoading = false;
    });
  }

  // Calendar-year-to-date KG total (harvests measured in another unit are not
  // added to it: units are never mixed), computed from the same already-fetched
  // _allHarvests every other stat here uses — replaces the previous rolling
  // 30-day figure, which was hard to explain (an arbitrary window tied to
  // nothing in the business) and didn't pair naturally with "Total Harvest"
  // (all-time count) the way a year-to-date figure does.
  double get _thisYearYieldKg {
    final year = DateTime.now().year;
    return _allHarvests
        .where((h) => h.harvestDate.year == year && isKg(h.unit))
        .fold(0.0, (sum, h) => sum + h.quantityKg);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const TopBarSpacer(height: 72),
                    CachedDataNotice(
                      screen: 'harvests',
                      isOnline: _isOnline,
                      offlineMessage: AppLocalizations.of(
                        context,
                      ).offlineHarvestHistory,
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        color: Theme.of(context).colorScheme.primary,
                        onRefresh: _loadData,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          children: [
                            // Summary stats — moved before the search bar
                            // and filter chips per the redesign request.
                            _HistoryStatsRow(
                              totalHarvestCount: _allHarvests.length,
                              thisYearYieldKg: _thisYearYieldKg,
                              unsyncedCount: _seasonStats.unsyncedCount,
                              isLoading: _isLoading,
                            ),
                            const SizedBox(height: 20),

                            // Search
                            _SearchBar(controller: _searchController),
                            const SizedBox(height: 12),

                            // Category filter chips (Revision B0's shared
                            // component — same pattern as Crop Roster and
                            // Record New Harvest).
                            CropCategoryChips(
                              categories: _categories,
                              active: _activeCategory,
                              counts: CropCategoryChips.countBy(
                                _allHarvests,
                                (h) => h.cropCategory,
                              ),
                              onSelected: _setCategory,
                            ),
                            const SizedBox(height: 20),

                            // Log entries
                            if (_isLoading)
                              ...List.generate(
                                4,
                                (_) => const Padding(
                                  padding: EdgeInsets.only(bottom: 10),
                                  child: SkeletonList(count: 4, rowHeight: 72),
                                ),
                              )
                            else if (_filtered.isEmpty)
                              _EmptyState(
                                hasFilter:
                                    _searchQuery.isNotEmpty ||
                                    _activeCategory != CropCategoryChips.all,
                              )
                            else
                              ..._filtered.map(
                                (h) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
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
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FarmerTopBar(
                    title: AppLocalizations.of(
                      context,
                    ).farmerHarvestHistoryTitle,
                    onBack: () => Navigator.of(context).pop(),
                    hideProfileAvatar: true,
                    onProfileTap: () {},
                    onNotificationTap: () {},
                    showNotificationButton: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History Stats Row — 3 cards: Total Harvest (all-time count, never resets)
// | This Year's Yield | Sync Status. Total Harvest replaces the old
// calendar-year "Season" figure, which reset every January and undercounted
// a farmer's real history. This Year's Yield replaces a rolling 30-day
// figure that was hard to explain (an arbitrary window tied to nothing in
// the business) — a calendar-year-to-date total pairs naturally with the
// all-time Total Harvest count beside it, and resets on a boundary
// (January 1) that's easy to explain to anyone.
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryStatsRow extends StatelessWidget {
  final int totalHarvestCount;
  final double thisYearYieldKg;
  final int unsyncedCount;
  final bool isLoading;

  const _HistoryStatsRow({
    required this.totalHarvestCount,
    required this.thisYearYieldKg,
    required this.unsyncedCount,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final yieldLabel = formatQuantity(thisYearYieldKg);
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

// ─────────────────────────────────────────────────────────────────────────────
// Search Bar
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).enhSearchHarvestHistory,
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.60),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: Theme.of(context).colorScheme.outline,
        ),
        filled: true,
        fillColor: context.saganaColors.cardBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.20),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.20),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasFilter;

  const _EmptyState({required this.hasFilter});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: context.adaptiveSurface(const Color(0xFFDBF1FE)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.history_rounded,
              size: 40,
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.60),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            hasFilter
                ? AppLocalizations.of(context).enhNoMatchingHarvests
                : AppLocalizations.of(context).enhNoHarvestsFound,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilter
                ? AppLocalizations.of(
                    context,
                  ).enhTryADifferentSearchOrCropFilter
                : AppLocalizations.of(
                    context,
                  ).enhYouHavenTRecordedAnyHarvestsForThis,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (!hasFilter) ...[
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context).enhYouReAllCaughtUp296,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer
// ─────────────────────────────────────────────────────────────────────────────
