import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

/// Read-only crop details — what tapping a crop card in My Crops opens.
/// Actions (record harvest, view history, delete) stay in the three-dot
/// menu on the list; this screen is "view", not "act", with the two most
/// common next steps offered as a convenience.
class CropDetailsScreen extends StatelessWidget {
  final FarmerCropModel crop;
  const CropDetailsScreen({super.key, required this.crop});

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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  children: [
                    _HeaderCard(crop: crop),
                    const SizedBox(height: 20),
                    _InfoRow(
                      label: 'Category',
                      value: crop.category,
                    ),
                    _InfoRow(
                      label: 'Added on',
                      value: DateFormat('MMMM d, yyyy').format(crop.createdAt),
                    ),
                    _InfoRow(
                      label: 'Harvest entries',
                      value: crop.hasHarvests
                          ? '${crop.harvestCount}'
                          : 'None yet',
                    ),
                    _InfoRow(
                      label: 'Catalog status',
                      value: crop.isPendingApproval
                          ? (crop.isRejected ? 'Request declined' : 'Pending admin approval')
                          : 'Approved',
                    ),
                    if (crop.isRejected && crop.requestNotes != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppConstants.errorRed.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                          border: Border.all(
                              color: AppConstants.errorRed.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Reason for decline',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppConstants.errorRed)),
                            const SizedBox(height: 4),
                            Text(crop.requestNotes!,
                                style: GoogleFonts.inter(
                                    fontSize: 13, color: AppConstants.errorRed)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    ElevatedButton.icon(
                      onPressed: () => context.pushRoute(
                          AppRoutes.harvestHistory,
                          extra: crop.cropName),
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('View Harvest History'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppConstants.primaryGreen,
                        elevation: 0,
                        side: const BorderSide(color: AppConstants.primaryGreen),
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (crop.isPendingApproval)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppConstants.amber.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                          border: Border.all(color: AppConstants.amber.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.hourglass_top_rounded, size: 18, color: AppConstants.amber),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'You can record a harvest once this crop is approved by the cooperative.',
                                style: GoogleFonts.inter(fontSize: 13, color: AppConstants.amber),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: () => context.pushRoute(
                            AppRoutes.harvestEntryForm,
                            extra: crop),
                        icon: const Icon(Icons.eco_rounded, size: 18),
                        label: const Text('Record Harvest for This Crop'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primaryGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: crop.cropName,
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
// Header Card — photo/icon, name, category + status badges
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final FarmerCropModel crop;
  const _HeaderCard({required this.crop});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF455A64).withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: crop.hasPhoto
                ? Image.network(crop.photoUrl!,
                    width: 88, height: 88, fit: BoxFit.cover)
                : Container(
                    width: 88,
                    height: 88,
                    color: const Color(0xFFDBF1FE),
                    child: const Icon(Icons.eco_rounded,
                        color: AppConstants.primaryGreen, size: 40),
                  ),
          ),
          const SizedBox(height: 14),
          Text(crop.cropName,
              style: GoogleFonts.poppins(
                  fontSize: 20, fontWeight: FontWeight.w700,
                  color: AppConstants.charcoal)),
          const SizedBox(height: 8),
          if (crop.isPendingApproval)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: crop.isRejected
                    ? AppConstants.errorRed.withValues(alpha: 0.10)
                    : AppConstants.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text(
                crop.isRejected ? 'Request Declined' : 'Pending Approval',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: crop.isRejected
                      ? AppConstants.errorRed
                      : AppConstants.amber,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info Row
// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppConstants.onSurfaceVariant)),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.charcoal)),
        ],
      ),
    );
  }
}
