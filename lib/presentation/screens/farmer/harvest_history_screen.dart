import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/models/harvest_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/repositories/harvest_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/crop_category_chips.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/harvest_log_widgets.dart';
import '../../widgets/report_summary_widgets.dart';

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
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
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

  // Calendar-year-to-date kg total, computed from the same already-fetched
  // _allHarvests every other stat here uses — replaces the previous rolling
  // 30-day figure, which was hard to explain (an arbitrary window tied to
  // nothing in the business) and didn't pair naturally with "Total Harvest"
  // (all-time count) the way a year-to-date figure does.
  double get _thisYearYieldKg {
    final year = DateTime.now().year;
    return _allHarvests
        .where((h) => h.harvestDate.year == year)
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
      backgroundColor: AppConstants.offWhite,
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(message: "You're offline — your full harvest history may not be up to date."),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 72),
                    Expanded(
                      child: RefreshIndicator(
                        color: AppConstants.primaryGreen,
                        onRefresh: _loadData,
                        child: ListView(
                          padding:
                              const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                              onSelected: _setCategory,
                            ),
                            const SizedBox(height: 20),

                            // Log entries
                            if (_isLoading)
                              ...List.generate(4, (_) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: _LogShimmer(),
                                  ))
                            else if (_filtered.isEmpty)
                              _EmptyState(
                                hasFilter: _searchQuery.isNotEmpty ||
                                  _activeCategory != CropCategoryChips.all,
                              )
                            else
                              ..._filtered.map((h) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: GestureDetector(
                                      onTap: () => _showHarvestDetails(
                                          context, h, _cropsById[h.cropId]),
                                      child: HarvestLogEntry(
                                        harvest: h,
                                        imageUrl: _cropsById[h.cropId]?.displayImageUrl,
                                      ),
                                    ),
                                  )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: FarmerTopBar(
                    title: 'Harvest History',
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

void _showHarvestDetails(
    BuildContext context, HarvestModel harvest, FarmerCropModel? crop) {
  showManagementModal<void>(
    context: context,
    builder: (_) => _HarvestDetailsSheet(harvest: harvest, crop: crop),
  );
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
            icon: hasUnsynced ? Icons.sync_rounded : Icons.check_circle_outline_rounded,
            accent: hasUnsynced ? AppConstants.warningAmber : AppConstants.successGreen,
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
// Harvest Details — read-only. Tapping a log entry opens this instead of
// navigating anywhere; there's nothing here a farmer can edit (an already-
// submitted harvest record isn't editable from History in this app).
// ─────────────────────────────────────────────────────────────────────────────

class _HarvestDetailsSheet extends StatelessWidget {
  final HarvestModel harvest;
  final FarmerCropModel? crop;
  const _HarvestDetailsSheet({required this.harvest, this.crop});

  // Was omitted entirely when no crop photo existed — the sheet jumped
  // straight from the title to "Quantity" with no image area at all.
  // Shows the same default crop icon the list row falls back to instead.
  Widget _imagePlaceholder() {
    return Container(
      width: double.infinity,
      height: 140,
      color: AppConstants.primaryGreen.withValues(alpha: 0.10),
      child: const Icon(Icons.eco_rounded, color: AppConstants.primaryGreen, size: 40),
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
          _DetailRow(label: 'Quantity', value: '${harvest.quantityKg.toStringAsFixed(0)} kg'),
          _DetailRow(label: 'Category', value: harvest.cropCategory),
          _DetailRow(label: 'Batch Number', value: harvest.batchNumber ?? '—'),
          _DetailRow(label: 'Storage Location', value: harvest.storageLocation ?? '—'),
          _DetailRow(
            label: 'Harvest Date',
            value: DateFormat('MMM d, yyyy · h:mm a').format(harvest.harvestDate),
          ),
          _DetailRow(
            label: 'Sync Status',
            value: harvest.isSynced ? 'Synced' : 'Pending sync',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;
  const _DetailRow({required this.label, required this.value, this.isLast = false});

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
              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
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
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: InputDecoration(
        hintText: 'Search harvest history...',
        hintStyle: GoogleFonts.inter(fontSize: 14, color: AppConstants.outline.withValues(alpha: 0.60)),
        prefixIcon: const Icon(Icons.search_rounded, color: AppConstants.outline),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(color: AppConstants.primaryGreen),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            width: 96, height: 96,
            decoration: const BoxDecoration(
              color: Color(0xFFDBF1FE),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.history_rounded,
                size: 40, color: AppConstants.outline.withValues(alpha: 0.60)),
          ),
          const SizedBox(height: 20),
          Text(hasFilter ? 'No Matching Harvests' : 'No Harvests Found',
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: AppConstants.onSurface)),
          const SizedBox(height: 8),
          Text(
            hasFilter
                ? 'Try a different search or crop filter.'
                : 'You haven\'t recorded any harvests for this period yet.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
          ),
          if (!hasFilter) ...[
            const SizedBox(height: 20),
            Text(
              'You\'re all caught up.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppConstants.onSurfaceVariant,
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

class _LogShimmer extends StatefulWidget {
  @override
  State<_LogShimmer> createState() => _LogShimmerState();
}

class _LogShimmerState extends State<_LogShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _anim = Tween<double>(begin: -1, end: 2).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _block(double w, double h) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Container(
          width: w, height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              stops: [
                (_anim.value - 1).clamp(0.0, 1.0),
                _anim.value.clamp(0.0, 1.0),
                (_anim.value + 1).clamp(0.0, 1.0),
              ],
              colors: const [Color(0xFFE8E8E8), Color(0xFFF5F5F5), Color(0xFFE8E8E8)],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          _block(48, 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _block(110, 14),
                const SizedBox(height: 8),
                _block(140, 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}