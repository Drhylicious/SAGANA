import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

/// Shared "choose which crop" step, standing between "Record New Harvest"
/// (from the Harvest Hub or Manage Inventory) and the Harvest Entry Form.
///
/// Not used by "Record Harvest for This Crop" in My Crops' three-dot menu —
/// that action already knows the crop and goes straight to the form.
class SelectCropScreen extends StatefulWidget {
  final FarmerCropModel? initialCrop;
  const SelectCropScreen({super.key, this.initialCrop});

  @override
  State<SelectCropScreen> createState() => _SelectCropScreenState();
}

class _SelectCropScreenState extends State<SelectCropScreen> {
  final _cropRepo = CropRepository();
  List<FarmerCropModel> _crops = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final crops = await _cropRepo.fetchCrops(approvedOnly: true);
    if (!mounted) return;
    setState(() {
      _crops = crops;
      _isLoading = false;
    });
  }

  Future<void> _onCropSelected(FarmerCropModel crop) async {
    final result = await context.pushRoute(AppRoutes.harvestEntryForm, extra: crop);
    if (!mounted) return;
    // Cascade the success signal so the farmer lands back on the Hub /
    // Manage Inventory screen they started from, instead of lingering here.
    if (result == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 72),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppConstants.primaryGreen))
                    : _crops.isEmpty
                        ? _NoCropsEmptyState(
                            onGoToMyCrops: () =>
                                context.pushRoute(AppRoutes.cropListing),
                          )
                        : RefreshIndicator(
                            color: AppConstants.primaryGreen,
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                              children: [
                                Text(
                                  'Which crop are you recording a harvest for?'
                                      .toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: AppConstants.outline,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ..._crops.map(
                                  (crop) => Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selectable Crop Card
// ─────────────────────────────────────────────────────────────────────────────

class _SelectableCropCard extends StatelessWidget {
  final FarmerCropModel crop;
  final VoidCallback onTap;

  const _SelectableCropCard({required this.crop, required this.onTap});

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
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDBF1FE),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(FarmerCropModel.iconForCategory(crop.category),
                      color: AppConstants.primaryGreen, size: 24),
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
                          fontWeight: FontWeight.w500,
                          color: AppConstants.charcoal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        crop.category,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppConstants.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppConstants.outline),
              ],
            ),
          ),
        ),
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
              width: 88, height: 88,
              decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.08),
                  shape: BoxShape.circle),
              child: const Icon(Icons.eco_outlined,
                  size: 40, color: AppConstants.primaryGreen),
            ),
            const SizedBox(height: 20),
            Text("You don't have any crops yet",
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppConstants.charcoal)),
            const SizedBox(height: 8),
            Text(
              'Add a crop from the cooperative\'s list before recording a harvest.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppConstants.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onGoToMyCrops,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
              ),
              child: Text('Go to My Crops',
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}