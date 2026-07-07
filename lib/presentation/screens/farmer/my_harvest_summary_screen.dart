import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

class MyHarvestSummaryScreen extends StatefulWidget {
  const MyHarvestSummaryScreen({super.key});

  @override
  State<MyHarvestSummaryScreen> createState() => _MyHarvestSummaryScreenState();
}

class _MyHarvestSummaryScreenState extends State<MyHarvestSummaryScreen> {
  final _cropRepo = CropRepository();

  List<FarmerCropModel> _crops = [];
  Map<String, double> _kgPerCrop = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _cropRepo.fetchCrops(),
      _cropRepo.fetchTotalKgPerCrop(),
    ]);
    if (!mounted) return;
    setState(() {
      _crops = results[0] as List<FarmerCropModel>;
      _kgPerCrop = results[1] as Map<String, double>;
      _isLoading = false;
    });
  }

  // ── Computed overview stats ───────────────────────────────────────────────

  int get _totalEntries =>
      _crops.fold(0, (sum, c) => sum + c.harvestCount);

  double get _totalKg =>
      _kgPerCrop.values.fold(0.0, (sum, v) => sum + v);

  // ── Three-dot menu ────────────────────────────────────────────────────────

  void _showCropMenu(FarmerCropModel crop) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusXl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppConstants.outline.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(crop.cropName,
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
            const Divider(height: 20),
            _MenuOption(
              icon: Icons.eco_outlined,
              label: 'View Harvests',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushNamed(
                  AppRoutes.harvestManagement,
                  arguments: crop,
                );
              },
            ),
            _MenuOption(
              icon: Icons.add_circle_outline_rounded,
              label: 'Record Harvest for This Crop',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushNamed(
                  AppRoutes.harvestEntryForm,
                  arguments: crop,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                    children: [
                      // Overview banner
                      _OverviewBanner(
                        cropsCount: _crops.length,
                        totalEntries: _totalEntries,
                        totalKg: _totalKg,
                        isLoading: _isLoading,
                      ),
                      const SizedBox(height: 24),

                      // Section header
                      Text(
                        'YOUR ACTIVE CULTIVATIONS',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.outline,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Crop cards / shimmer / empty
                      if (_isLoading)
                        ...List.generate(3, (_) => const Padding(
                              padding: EdgeInsets.only(bottom: 14),
                              child: _CropCardShimmer(),
                            ))
                      else if (_crops.isEmpty)
                        _EmptyState(
                          onAdd: () => Navigator.of(context).pushNamed(AppRoutes.addCrop),
                        )
                      else
                        ..._crops.map((crop) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _CropCard(
                                crop: crop,
                                totalKg: _kgPerCrop[crop.id] ?? 0,
                                onMenuTap: () => _showCropMenu(crop),
                                onTap: () => context.pushRoute(AppRoutes.harvestManagement, extra: crop),
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
            child: FarmerTopBar(title: 'Harvest Summary', onBack: () => Navigator.of(context).pop(), profilePhotoUrl: null, onProfileTap: () {}, onNotificationTap: () => context.pushRoute(AppRoutes.farmerNotifications), onSettingsTap: null,),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Overview Banner
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewBanner extends StatelessWidget {
  final int cropsCount;
  final int totalEntries;
  final double totalKg;
  final bool isLoading;

  const _OverviewBanner({
    required this.cropsCount,
    required this.totalEntries,
    required this.totalKg,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppConstants.secondaryContainer.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.amber.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF455A64).withValues(alpha: 0.05),
              blurRadius: 12)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📊', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('Harvest Overview',
                  style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.charcoal)),
            ],
          ),
          const SizedBox(height: 16),
          isLoading
              ? Container(width: double.infinity, height: 40, color: const Color(0xFFE8E8E8))
              : Row(
                  children: [
                    Expanded(
                      child: _StatCell(
                        label: 'Crops Registered',
                        value: cropsCount.toString(),
                        showDivider: false,
                      ),
                    ),
                    Expanded(
                      child: _StatCell(
                        label: 'Total Entries',
                        value: totalEntries.toString(),
                        showDivider: true,
                      ),
                    ),
                    Expanded(
                      child: _StatCell(
                        label: 'Total Qty (kg)',
                        value: totalKg >= 1000
                            ? '${(totalKg / 1000).toStringAsFixed(1)}k'
                            : totalKg.toStringAsFixed(0),
                        showDivider: true,
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool showDivider;

  const _StatCell({
    required this.label,
    required this.value,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                left: BorderSide(
                    color: AppConstants.outline.withValues(alpha: 0.20)),
              ),
            )
          : null,
      padding: showDivider ? const EdgeInsets.only(left: 12) : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppConstants.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.primaryGreen)),
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
  final double totalKg;
  final VoidCallback onMenuTap;
  final VoidCallback onTap;

  const _CropCard({
    required this.crop,
    required this.totalKg,
    required this.onMenuTap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 128,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 10)
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          child: Row(
            children: [
              // ── Left: crop photo ─────────────────────────────────────────
              SizedBox(
                width: 110,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    crop.hasPhoto
                        ? Image.network(
                            crop.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _CategoryPhotoFallback(category: crop.category),
                          )
                        : _CategoryPhotoFallback(category: crop.category),
                    // Category badge
                    Positioned(
                      top: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: _categoryBadgeColor(crop.category)
                              .withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                        ),
                        child: Text(
                          crop.category.toUpperCase(),
                          style: GoogleFonts.inter(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Right: info ───────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(crop.cropName,
                                    style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppConstants.charcoal),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      crop.hasHarvests
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      size: 14,
                                      color: crop.hasHarvests
                                          ? AppConstants.successGreen
                                          : AppConstants.outline,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      crop.hasHarvests
                                          ? 'Has harvest entries'
                                          : 'No harvest yet',
                                      style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppConstants.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: onMenuTap,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.more_vert_rounded,
                                  size: 20, color: AppConstants.outline),
                            ),
                          ),
                        ],
                      ),

                      // Bottom stats row
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F6FF).withValues(alpha: 0.50),
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMd),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${totalKg.toStringAsFixed(0)} kg harvested',
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: AppConstants.outline),
                            ),
                            Container(
                              width: 1, height: 10,
                              color: AppConstants.outline.withValues(alpha: 0.30),
                            ),
                            Text(
                              '${crop.harvestCount} entr${crop.harvestCount == 1 ? 'y' : 'ies'}',
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: AppConstants.outline),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _categoryBadgeColor(String category) {
    switch (category) {
      case 'Grain': return AppConstants.primaryGreen;
      case 'Legume': return AppConstants.primaryContainer;
      case 'Root & Spice Crop': return AppConstants.amber;
      case 'Fruit': return const Color(0xFFE65100);
      case 'Tree Crop': return const Color(0xFF795548);
      case 'Vegetable': return AppConstants.amber;
      default: return AppConstants.outline;
    }
  }
}

class _CategoryPhotoFallback extends StatelessWidget {
  final String category;
  const _CategoryPhotoFallback({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFDBF1FE),
      child: Center(
        child: Icon(_iconForCategory(category),
            size: 40, color: AppConstants.primaryGreen.withValues(alpha: 0.50)),
      ),
    );
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'Grain': return Icons.grass_rounded;
      case 'Legume': return Icons.eco_rounded;
      case 'Root & Spice Crop': return Icons.spa_rounded;
      case 'Fruit': return Icons.local_florist_rounded;
      case 'Tree Crop': return Icons.park_rounded;
      case 'Vegetable': return Icons.agriculture_rounded;
      default: return Icons.eco_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu Option
// ─────────────────────────────────────────────────────────────────────────────

class _MenuOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuOption({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      tileColor: Colors.transparent,
      leading: Icon(icon, color: AppConstants.onSurfaceVariant, size: 22),
      title: Text(label,
          style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface)),
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFDBF1FE), shape: BoxShape.circle),
            child: Icon(Icons.grass_rounded,
                size: 36, color: AppConstants.outline.withValues(alpha: 0.60)),
          ),
          const SizedBox(height: 18),
          Text('No crops registered yet',
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  color: AppConstants.charcoal)),
          const SizedBox(height: 6),
          Text('Use the button below to register your first crop.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppConstants.onSurfaceVariant)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: AppConstants.primaryGreen,
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text('Add First Crop',
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w500,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer
// ─────────────────────────────────────────────────────────────────────────────

class _CropCardShimmer extends StatelessWidget {
  const _CropCardShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 128,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
    );
  }
}

