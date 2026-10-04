import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/crop_category_chips.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/shared_widgets.dart';

/// Shared "choose which crop" step, standing between "Record New Harvest"
/// (from the Harvest Hub or Manage Inventory) and the Harvest Entry Form.
///
/// Not used by "Record Harvest for This Crop" in Crop Roster's three-dot
/// menu — that action already knows the crop and goes straight to the form.
class SelectCropScreen extends StatefulWidget {
  const SelectCropScreen({super.key});

  @override
  State<SelectCropScreen> createState() => _SelectCropScreenState();
}

class _SelectCropScreenState extends State<SelectCropScreen> {
  final _cropRepo = CropRepository();
  final _searchController = TextEditingController();
  List<FarmerCropModel> _crops = [];
  List<FarmerCropModel> _filtered = [];
  String _activeCategory = CropCategoryChips.all;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _load();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final crops = await _cropRepo.fetchCrops(approvedOnly: true);
    if (!mounted) return;
    setState(() {
      _crops = crops;
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

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    _filtered = _crops.where((c) {
      if (_activeCategory != CropCategoryChips.all &&
          c.category != _activeCategory) {
        return false;
      }
      if (q.isEmpty) return true;
      return c.cropName.toLowerCase().contains(q);
    }).toList();
  }

  // Harvestable crops only, since fetchCrops(approvedOnly: true) already
  // excludes pending/rejected ones — every category present here is one
  // the farmer can actually record a harvest against right now.
  List<String> get _categories =>
      (_crops.map((c) => c.category).toSet().toList()..sort());

  Future<void> _onCropSelected(FarmerCropModel crop) async {
    await context.pushRoute(AppRoutes.harvestEntryForm, extra: crop);
    // Stay on this screen after a successful submission — the farmer lands
    // back on "Record New Harvest" (this picker), not the Hub/Manage
    // Inventory screen underneath it, so they can immediately record
    // another crop's harvest if needed.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(
              message: "You're offline — your crop list may not be up to date.",
            ),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 72),
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: AppConstants.primaryGreen,
                              ),
                            )
                          : _crops.isEmpty
                          ? _NoCropsEmptyState(
                              onGoToMyCrops: () =>
                                  context.pushRoute(AppRoutes.cropListing),
                            )
                          : RefreshIndicator(
                              color: AppConstants.primaryGreen,
                              onRefresh: _load,
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  40,
                                ),
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ReportIconStatCard(
                                          icon: Icons.eco_rounded,
                                          accent: AppConstants.primaryGreen,
                                          label: 'Available Crops',
                                          value: '${_crops.length}',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ReportIconStatCard(
                                          icon: Icons.category_outlined,
                                          accent: AppConstants.buyerBlue,
                                          label: 'Categories',
                                          value: '${_categories.length}',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _SearchBar(controller: _searchController),
                                  const SizedBox(height: 12),
                                  CropCategoryChips(
                                    categories: _categories,
                                    active: _activeCategory,
                                    onSelected: _setCategory,
                                  ),
                                  const SizedBox(height: 16),
                                  if (_filtered.isEmpty)
                                    _NoMatchingCropsState(
                                      onClearFilters: () {
                                        _searchController.clear();
                                        _setCategory(CropCategoryChips.all);
                                      },
                                    )
                                  else
                                    ..._filtered.map(
                                      (crop) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 14,
                                        ),
                                        child: _SelectableCropCard(
                                          crop: crop,
                                          onTap: () => _onCropSelected(crop),
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
                    title: 'Record New Harvest',
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
        hintText: 'Search crops...',
        hintStyle: GoogleFonts.inter(
            fontSize: 14, color: AppConstants.outline.withValues(alpha: 0.60)),
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
// No Matching Crops State — search/filter narrowed the (non-empty) crop
// list to nothing. Distinct from _NoCropsEmptyState, which covers the
// farmer having zero harvestable crops at all.
// ─────────────────────────────────────────────────────────────────────────────

class _NoMatchingCropsState extends StatelessWidget {
  final VoidCallback onClearFilters;
  const _NoMatchingCropsState({required this.onClearFilters});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.filter_alt_off_rounded,
              size: 40, color: AppConstants.outline.withValues(alpha: 0.60)),
          const SizedBox(height: 12),
          Text('No Matching Crops',
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppConstants.onSurface)),
          const SizedBox(height: 6),
          Text('Try a different search or category.',
              style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onClearFilters,
            child: Text('Clear Filters',
                style: GoogleFonts.poppins(color: AppConstants.primaryGreen)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selectable Crop Card
// ─────────────────────────────────────────────────────────────────────────────

// Matches Admin's All Listings card recipe (solid card background,
// visible border, subtle shadow, 68x68 rounded photo) — the reference
// this screen was redesigned against, replacing its previous circular
// icon-only, glass-style card.
class _SelectableCropCard extends StatelessWidget {
  final FarmerCropModel crop;
  final VoidCallback onTap;

  const _SelectableCropCard({required this.crop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: crop.hasDisplayImage
                  ? Image.network(
                      crop.displayImageUrl!,
                      width: 68,
                      height: 68,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _CropTypeIcon(category: crop.category),
                    )
                  : _CropTypeIcon(category: crop.category),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    crop.cropName,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.charcoal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    crop.category,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppConstants.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppConstants.outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _CropTypeIcon extends StatelessWidget {
  final String category;
  const _CropTypeIcon({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: const BoxDecoration(color: Color(0xFFDBF1FE)),
      child: Icon(
        FarmerCropModel.iconForCategory(category),
        color: AppConstants.primaryGreen,
        size: 32,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// No Crops Empty State (mirrors harvest_entry_form_screen.dart's version)
// ─────────────────────────────────────────────────────────────────────────────

class _NoCropsEmptyState extends StatelessWidget {
  final VoidCallback onGoToMyCrops;
  const _NoCropsEmptyState({required this.onGoToMyCrops});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppConstants.primaryGreen.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.eco_outlined,
                size: 40,
                color: AppConstants.primaryGreen,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "You don't have any crops yet",
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppConstants.charcoal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a crop from the cooperative\'s list before recording a harvest.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onGoToMyCrops,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                ),
              ),
              child: Text(
                'Go to Crop Roster',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
