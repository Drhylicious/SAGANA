import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/crop_category_chips.dart';
import '../../widgets/crop_catalog_sheet.dart';
import '../../widgets/edit_crop_sheet.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/shared_widgets.dart';

class CropListingScreen extends StatefulWidget {
  const CropListingScreen({super.key});

  @override
  State<CropListingScreen> createState() => _CropListingScreenState();
}

class _CropListingScreenState extends State<CropListingScreen> {
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
    AppEventService.instance.addListener(_onHarvestRecorded);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _searchController.addListener(_onSearchChanged);
    _loadCrops();
  }

  @override
  void dispose() {
    AppEventService.instance.removeListener(_onHarvestRecorded);
    _searchController.dispose();
    super.dispose();
  }

  void _onHarvestRecorded() {
    if (mounted) _loadCrops();
  }

  Future<void> _loadCrops() async {
    setState(() => _isLoading = true);
    final crops = await _cropRepo.fetchCrops();
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

  List<String> get _categories =>
      (_crops.map((c) => c.category).toSet().toList()..sort());

  Future<void> _openCropCatalog() async {
    final added = await showCropCatalogSheet(
      context,
      repo: _cropRepo,
      existingCropMasterIds: _crops
          .where((c) => c.cropMasterId != null)
          .map((c) => c.cropMasterId!)
          .toList(),
    );
    if (added == true) _loadCrops();
  }

  void _onCropTap(FarmerCropModel crop) {
    context.pushRoute(AppRoutes.cropDetails, extra: crop);
  }

  Future<void> _openEditCrop(FarmerCropModel crop) async {
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This action requires an internet connection. Please try again once you\'re back online.',
          ),
          backgroundColor: AppConstants.warningAmber,
        ),
      );
      return;
    }
    final saved = await showEditCropSheet(context, repo: _cropRepo, crop: crop);
    if (saved == true) _loadCrops();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(
              message:
                  "You're offline — adding or removing crops requires an internet connection.",
            ),
          Expanded(
            child: Stack(
              children: [
                // Content
                Column(
                  children: [
                    const SizedBox(height: 72),
                    Expanded(
                      child: RefreshIndicator(
                        color: AppConstants.primaryGreen,
                        onRefresh: _loadCrops,
                        child: _isLoading
                            ? _LoadingBody()
                            : _crops.isEmpty
                            ? _EmptyState(onAddCrop: _openCropCatalog)
                            : _CropList(
                                allCrops: _crops,
                                filteredCrops: _filtered,
                                categories: _categories,
                                activeCategory: _activeCategory,
                                searchController: _searchController,
                                onCategorySelected: _setCategory,
                                onClearFilters: () {
                                  _searchController.clear();
                                  _setCategory(CropCategoryChips.all);
                                },
                                onCropTap: _onCropTap,
                                onViewHarvests: (crop) => context.pushRoute(
                                  AppRoutes.harvestHistory,
                                  extra: crop.cropName,
                                ),
                                onRecordHarvest: (crop) => context
                                    .pushRoute(
                                      AppRoutes.harvestEntryForm,
                                      extra: crop,
                                    )
                                    .then((result) {
                                      if (result == true) _loadCrops();
                                    }),
                                onEdit: (crop) => _openEditCrop(crop),
                              ),
                      ),
                    ),
                  ],
                ),

                // Top app bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FarmerTopBar(
                    title: 'Crop Roster',
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

      // FAB
      floatingActionButton: _crops.isNotEmpty
          ? _AddCropFab(onTap: _openCropCatalog)
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Crop List
// ─────────────────────────────────────────────────────────────────────────────

class _CropList extends StatelessWidget {
  final List<FarmerCropModel> allCrops;
  final List<FarmerCropModel> filteredCrops;
  final List<String> categories;
  final String activeCategory;
  final TextEditingController searchController;
  final ValueChanged<String> onCategorySelected;
  final VoidCallback onClearFilters;
  final ValueChanged<FarmerCropModel> onCropTap;
  final ValueChanged<FarmerCropModel> onViewHarvests;
  final ValueChanged<FarmerCropModel> onRecordHarvest;
  final ValueChanged<FarmerCropModel> onEdit;

  const _CropList({
    required this.allCrops,
    required this.filteredCrops,
    required this.categories,
    required this.activeCategory,
    required this.searchController,
    required this.onCategorySelected,
    required this.onClearFilters,
    required this.onCropTap,
    required this.onViewHarvests,
    required this.onRecordHarvest,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final hasHarvestsCount = allCrops.where((c) => c.hasHarvests).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      children: [
        Row(
          children: [
            Expanded(
              child: ReportIconStatCard(
                icon: Icons.eco_rounded,
                accent: AppConstants.primaryGreen,
                label: 'Total Crops',
                value: '${allCrops.length}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ReportIconStatCard(
                icon: Icons.check_circle_outline_rounded,
                accent: AppConstants.successGreen,
                label: 'Has Harvests',
                value: '$hasHarvestsCount',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _CropSearchBar(controller: searchController),
        const SizedBox(height: 12),
        CropCategoryChips(
          categories: categories,
          active: activeCategory,
          onSelected: onCategorySelected,
        ),
        const SizedBox(height: 16),
        if (filteredCrops.isEmpty)
          _NoMatchingCropsState(onClearFilters: onClearFilters)
        else
          ...filteredCrops.map(
            (crop) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _CropCard(
                crop: crop,
                onTap: () => onCropTap(crop),
                onViewHarvests: () => onViewHarvests(crop),
                onRecordHarvest: crop.isPendingApproval
                    ? null
                    : () => onRecordHarvest(crop),
                onEdit: () => onEdit(crop),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search Bar — mirrors Record New Harvest's _SearchBar exactly.
// ─────────────────────────────────────────────────────────────────────────────

class _CropSearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _CropSearchBar({required this.controller});

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
// list to nothing. Distinct from _EmptyState, which covers the farmer
// having zero crops at all.
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
          Text('Try a different search term or category.',
              style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onClearFilters,
            child: Text('Clear Filters',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppConstants.primaryGreen)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Crop Card
// ─────────────────────────────────────────────────────────────────────────────

class _CropCard extends StatelessWidget {
  final FarmerCropModel crop;
  final VoidCallback onTap;
  final VoidCallback onViewHarvests;
  final VoidCallback? onRecordHarvest;
  final VoidCallback onEdit;

  const _CropCard({
    required this.crop,
    required this.onTap,
    required this.onViewHarvests,
    required this.onRecordHarvest,
    required this.onEdit,
  });

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Crop icon or photo — matches Admin's All Listings/Crop
            // Management card recipe (68x68, radiusMd corners).
            _CropIconBox(crop: crop),
            const SizedBox(width: 14),

            // Name + category + market type + harvest status
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
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _CategoryBadge(category: crop.category),
                      if (crop.cropMasterId != null)
                        _MarketTypeBadge(cropType: crop.cropType),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _HarvestStatus(hasHarvests: crop.hasHarvests),
                  if (crop.cropMasterId == null) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: crop.isRejected && crop.requestNotes != null
                          ? () => showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusXl,
                                  ),
                                ),
                                title: Text(
                                  'Request Declined',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                content: Text(
                                  crop.requestNotes!,
                                  style: GoogleFonts.inter(fontSize: 13),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            )
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: crop.isRejected
                              ? AppConstants.errorRed.withValues(alpha: 0.10)
                              : AppConstants.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull,
                          ),
                        ),
                        child: Text(
                          crop.isRejected
                              ? 'Request Declined · Tap for reason'
                              : 'Pending Approval',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: crop.isRejected
                                ? AppConstants.errorRed
                                : AppConstants.amber,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Three-dot menu
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.more_vert_rounded,
                color: AppConstants.onSurfaceVariant,
                size: 22,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'view':
                    onViewHarvests();
                    break;
                  case 'record':
                    onRecordHarvest?.call();
                    break;
                  case 'edit':
                    onEdit();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'view',
                  child: _cropMenuRow(
                    Icons.eco_rounded,
                    'View Harvests',
                    AppConstants.primaryGreen,
                  ),
                ),
                PopupMenuItem(
                  value: 'record',
                  enabled: onRecordHarvest != null,
                  child: _cropMenuRow(
                    Icons.add_circle_outline_rounded,
                    onRecordHarvest != null
                        ? 'Record Harvest for This Crop'
                        : 'Record Harvest (awaiting approval)',
                    onRecordHarvest != null
                        ? AppConstants.primaryGreen
                        : AppConstants.outline,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'edit',
                  child: _cropMenuRow(
                    Icons.edit_outlined,
                    'Edit Crop',
                    AppConstants.buyerBlue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon+label row for a PopupMenuItem — same pattern used by Manage
/// Inventory's batch menu (matching Admin Inventory Management's own
/// 3-dot menu behavior).
Widget _cropMenuRow(IconData icon, String label, Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Text(label, style: GoogleFonts.inter(fontSize: 13, color: color)),
    ],
  );
}

class _MarketTypeBadge extends StatelessWidget {
  final String? cropType;
  const _MarketTypeBadge({required this.cropType});

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (cropType) {
      case 'sp3_cooperative':
        color = AppConstants.primaryGreen;
        break;
      case 'da_amad_market':
        color = AppConstants.amber;
        break;
      case 'open_market':
        color = AppConstants.buyerBlue;
        break;
      default:
        color = AppConstants.outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        marketTypeLabelFor(cropType),
        style: GoogleFonts.poppins(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}

// 68x68, radiusMd corners — matches Admin's All Listings / Crop Management
// / Loan Item Catalog thumbnail recipe. Prefers the farmer's own photo,
// falls back to the catalog's reference photo, then a generic category
// icon (FarmerCropModel.displayImageUrl / hasDisplayImage).
class _CropIconBox extends StatelessWidget {
  final FarmerCropModel crop;
  const _CropIconBox({required this.crop});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: crop.hasDisplayImage
          ? Image.network(
              crop.displayImageUrl!,
              width: 68,
              height: 68,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: 68,
                  height: 68,
                  color: const Color(0xFFDBF1FE),
                  child: const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) =>
                  _CategoryIcon(category: crop.category),
            )
          : _CategoryIcon(category: crop.category),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  final String category;
  const _CategoryIcon({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: const BoxDecoration(color: Color(0xFFDBF1FE)),
      child: Icon(
        _iconForCategory(category),
        color: AppConstants.primaryGreen,
        size: 32,
      ),
    );
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'Grain':
        return Icons.grass_rounded;
      case 'Legume':
        return Icons.eco_rounded;
      case 'Root & Spice Crop':
        return Icons.spa_rounded;
      case 'Fruit':
        return Icons.local_florist_rounded;
      case 'Tree Crop':
        return Icons.park_rounded;
      case 'Vegetable':
        return Icons.agriculture_rounded;
      default:
        return Icons.eco_rounded;
    }
  }
}

class _CategoryBadge extends StatelessWidget {
  final String category;
  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    final isGrain = category == 'Grain' || category == 'Legume';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isGrain ? const Color(0xFFD5ECF8) : const Color(0xFFE6F6FF),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        category.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: isGrain ? AppConstants.primaryGreen : AppConstants.amber,
        ),
      ),
    );
  }
}

class _HarvestStatus extends StatelessWidget {
  final bool hasHarvests;
  const _HarvestStatus({required this.hasHarvests});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          hasHarvests
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 14,
          color: hasHarvests ? AppConstants.successGreen : AppConstants.outline,
        ),
        const SizedBox(width: 5),
        Text(
          hasHarvests ? 'Has harvest entries' : 'No harvest yet',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: hasHarvests
                ? AppConstants.successGreen
                : AppConstants.outline,
          ),
        ),
      ],
    );
  }
}

// _CropMenuSheet and _MenuOption removed — the crop action menu is now a
// PopupMenuButton rendered directly in _CropCard's header (see
// _cropMenuRow above), matching Manage Inventory's Phase 3 conversion and
// Admin Inventory Management's own 3-dot menu pattern.

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddCrop;
  const _EmptyState({required this.onAddCrop});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppConstants.onPrimaryContainer.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.eco_outlined,
                size: 56,
                color: AppConstants.primaryGreen.withValues(alpha: 0.60),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No crops yet',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppConstants.primaryGreen,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a crop from the cooperative\'s list to start recording harvests.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onAddCrop,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Add a Crop',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
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
// Loading Body
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingBody extends StatefulWidget {
  @override
  State<_LoadingBody> createState() => _LoadingBodyState();
}

class _LoadingBodyState extends State<_LoadingBody>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(
      begin: -1,
      end: 2,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _block(double w, double h) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          stops: [
            (_anim.value - 1).clamp(0.0, 1.0),
            _anim.value.clamp(0.0, 1.0),
            (_anim.value + 1).clamp(0.0, 1.0),
          ],
          colors: const [
            Color(0xFFE8E8E8),
            Color(0xFFF5F5F5),
            Color(0xFFE8E8E8),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        _block(160, 12),
        const SizedBox(height: 16),
        ...List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.saganaColors.cardBackground,
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.10),
                ),
              ),
              child: Row(
                children: [
                  _block(68, 68),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _block(130, 14),
                        const SizedBox(height: 8),
                        _block(90, 11),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAB
// ─────────────────────────────────────────────────────────────────────────────

class _AddCropFab extends StatelessWidget {
  final VoidCallback onTap;
  const _AddCropFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 72),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppConstants.primaryContainer,
                AppConstants.primaryGreen,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppConstants.primaryGreen.withValues(alpha: 0.30),
                blurRadius: 25,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}
