import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

class CropListingScreen extends StatefulWidget {
  const CropListingScreen({super.key});

  @override
  State<CropListingScreen> createState() => _CropListingScreenState();
}

class _CropListingScreenState extends State<CropListingScreen> {
  final _cropRepo = CropRepository();

  List<FarmerCropModel> _crops = [];
  bool _isLoading = true;
  bool _isDeleting = false;

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
    _loadCrops();
  }

  @override
  void dispose() {
    AppEventService.instance.removeListener(_onHarvestRecorded);
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
      _isLoading = false;
    });
  }

  Future<void> _navigateToAddCrop() async {
    final result = await context.pushRoute(AppRoutes.addCrop);
    // Refresh list if a crop was added
    if (result == true) _loadCrops();
  }

  void _onCropTap(FarmerCropModel crop) {
    context.pushRoute(AppRoutes.harvestManagement, extra: crop);
  }

  void _showCropMenu(BuildContext context, FarmerCropModel crop) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CropMenuSheet(
        crop: crop,
        onViewHarvests: () {
          Navigator.pop(context);
          context.pushRoute(AppRoutes.harvestManagement, extra: crop);
        },
        onRecordHarvest: () {
          Navigator.pop(context);
          context.pushRoute(AppRoutes.harvestEntryForm, extra: crop).then((result) {
            if (result == true) _loadCrops();
          });
        },
        onDelete: () {
          Navigator.pop(context);
          _confirmDelete(crop);
        },
      ),
    );
  }

  Future<void> _confirmDelete(FarmerCropModel crop) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text(
          'Delete ${crop.cropName}?',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: Text(
          crop.hasHarvests
              ? 'This crop has harvest records. Deleting it will also remove all related harvest entries. This action cannot be undone.'
              : 'Are you sure you want to delete this crop? This action cannot be undone.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppConstants.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: AppConstants.outline),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.errorRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            child: Text('Delete', style: GoogleFonts.poppins(fontSize: 14)),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await _cropRepo.deleteCrop(crop.id);
      if (!mounted) return;
      await _loadCrops();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to delete ${crop.cropName}. Please try again.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          backgroundColor: AppConstants.errorRed,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
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
                      ? _EmptyState(onAddCrop: _navigateToAddCrop)
                      : _CropList(
                          crops: _crops,
                          onCropTap: _onCropTap,
                          onMenuTap: (crop) => _showCropMenu(context, crop),
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
              title: 'My Crops',
              onBack: () => Navigator.of(context).pop(),
              profilePhotoUrl: null,
              onProfileTap: () {},
              onNotificationTap: () =>
                  context.pushRoute(AppRoutes.farmerNotifications),
              onSettingsTap: null,
            ),
          ),

          // Deleting overlay
          if (_isDeleting)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black12,
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppConstants.primaryGreen,
                  ),
                ),
              ),
            ),
        ],
      ),

      // FAB
      floatingActionButton: _crops.isNotEmpty
          ? _AddCropFab(onTap: _navigateToAddCrop)
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Crop List
// ─────────────────────────────────────────────────────────────────────────────

class _CropList extends StatelessWidget {
  final List<FarmerCropModel> crops;
  final ValueChanged<FarmerCropModel> onCropTap;
  final ValueChanged<FarmerCropModel> onMenuTap;

  const _CropList({
    required this.crops,
    required this.onCropTap,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      children: [
        // Section label
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Your Active Cultivations'.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              color: AppConstants.outline,
              letterSpacing: 1.2,
            ),
          ),
        ),
        // Crop cards
        ...crops.map(
          (crop) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _CropCard(
              crop: crop,
              onTap: () => onCropTap(crop),
              onMenuTap: () => onMenuTap(crop),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Crop Card
// ─────────────────────────────────────────────────────────────────────────────

class _CropCard extends StatelessWidget {
  final FarmerCropModel crop;
  final VoidCallback onTap;
  final VoidCallback onMenuTap;

  const _CropCard({
    required this.crop,
    required this.onTap,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.70),
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF455A64).withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Crop icon or photo
                _CropIconBox(crop: crop),
                const SizedBox(width: 14),

                // Name + category + harvest status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              crop.cropName,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: AppConstants.charcoal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _CategoryBadge(category: crop.category),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _HarvestStatus(hasHarvests: crop.hasHarvests),
                    ],
                  ),
                ),

                // Three-dot menu
                IconButton(
                  onPressed: onMenuTap,
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: AppConstants.onSurfaceVariant,
                    size: 22,
                  ),
                  style: IconButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CropIconBox extends StatelessWidget {
  final FarmerCropModel crop;
  const _CropIconBox({required this.crop});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: crop.hasPhoto
          ? Image.network(
              crop.photoUrl!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: 56,
                  height: 56,
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
      width: 56,
      height: 56,
      decoration: const BoxDecoration(color: Color(0xFFDBF1FE)),
      child: Icon(
        _iconForCategory(category),
        color: AppConstants.primaryGreen,
        size: 28,
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

// ─────────────────────────────────────────────────────────────────────────────
// Crop Menu Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CropMenuSheet extends StatelessWidget {
  final FarmerCropModel crop;
  final VoidCallback onViewHarvests;
  final VoidCallback onRecordHarvest;
  final VoidCallback onDelete;

  const _CropMenuSheet({
    required this.crop,
    required this.onViewHarvests,
    required this.onRecordHarvest,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppConstants.outline.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Crop name header
          Text(
            crop.cropName,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppConstants.charcoal,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            crop.category,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppConstants.onSurfaceVariant,
            ),
          ),

          const Divider(height: 24),

          // Menu options
          _MenuOption(
            icon: Icons.eco_rounded,
            label: 'View Harvests',
            color: AppConstants.primaryGreen,
            onTap: onViewHarvests,
          ),
          _MenuOption(
            icon: Icons.add_circle_outline_rounded,
            label: 'Record Harvest for This Crop',
            color: AppConstants.primaryGreen,
            onTap: onRecordHarvest,
          ),
          _MenuOption(
            icon: Icons.delete_outline_rounded,
            label: 'Delete Crop',
            color: AppConstants.errorRed,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

class _MenuOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MenuOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        tileColor: Colors.transparent,
        leading: Icon(icon, color: color, size: 22),
        title: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: color == AppConstants.errorRed
                ? AppConstants.errorRed
                : AppConstants.onSurface,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

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
              'No crops added yet',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppConstants.primaryGreen,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to record your first crop and start tracking your harvest.',
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
                'Add First Crop',
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
                color: Colors.white.withValues(alpha: 0.70),
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
              ),
              child: Row(
                children: [
                  _block(56, 56),
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
