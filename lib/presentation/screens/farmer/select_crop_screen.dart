import '../../../core/l10n/localized_labels.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/crop_category_chips.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/channel_only_badge.dart';
import '../../../core/l10n/app_localizations.dart';

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
                      screen: 'farmer_crops_approved',
                      isOnline: _isOnline,
                      offlineMessage: AppLocalizations.of(
                        context,
                      ).offlineCropList,
                    ),
                    Expanded(
                      child: _isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: SkeletonList(),
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
                                          label: AppLocalizations.of(
                                            context,
                                          ).enhAvailableCrops,
                                          value: '${_crops.length}',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ReportIconStatCard(
                                          icon: Icons.category_outlined,
                                          accent: AppConstants.buyerBlue,
                                          label: AppLocalizations.of(
                                            context,
                                          ).reportsCategories,
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
                                    counts: CropCategoryChips.countBy(
                                      _crops,
                                      (c) => c.category,
                                    ),
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
                    title: AppLocalizations.of(context).enhRecordNewHarvest,
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
      style: GoogleFonts.inter(
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).priceSearchHint,
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
          Icon(
            Icons.filter_alt_off_rounded,
            size: 40,
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.60),
          ),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context).enhNoMatchingCrops,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context).loanReqNoMatchBody,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onClearFilters,
            child: Text(
              AppLocalizations.of(context).enhClearFilters,
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
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
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    localizeBuiltinLabel(
                      AppLocalizations.of(context),
                      crop.category,
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (crop.exclusiveChannel != null) ...[
                    const SizedBox(height: 6),
                    ChannelOnlyBadge(channel: crop.exclusiveChannel),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.outline,
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
        color: Theme.of(context).colorScheme.primary,
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
              child: Icon(
                Icons.eco_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context).enhYouDonTHaveAnyCropsYet,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(
                context,
              ).enhAddACropFromTheCooperativeSList285,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                AppLocalizations.of(context).enhGoToCropRoster,
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
