import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../data/services/hive_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../../data/services/profile_state_service.dart';
import '../../widgets/shared_widgets.dart';

class FarmerProfileScreen extends StatefulWidget {
  const FarmerProfileScreen({super.key});

  @override
  State<FarmerProfileScreen> createState() => _FarmerProfileScreenState();
}

class _FarmerProfileScreenState extends State<FarmerProfileScreen> {
  final _repo = FarmerProfileRepository();
  final _picker = ImagePicker();

  FarmerProfileModel? _profile;
  double _outstandingLoans = 0;
  double _monthExpenses = 0;
  int _harvestCount = 0;
  int _unsyncedCount = 0;
  bool _isLoading = true;
  bool _farmDetailsExpanded = true;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchProfile(),
      _repo.fetchOutstandingLoans(),
      _repo.fetchThisMonthExpenses(),
      _repo.fetchHarvestRecordCount(),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as FarmerProfileModel?;
      _outstandingLoans = results[1] as double;
      _monthExpenses = results[2] as double;
      _harvestCount = results[3] as int;
      _unsyncedCount = HiveService.getUnsyncedCount();
      _isLoading = false;
    });

    if (_profile != null) {
      FarmerProfileStateService.instance.updateProfile(_profile!);
    }
  }

  Future<void> _pickProfilePhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);
    final Uint8List bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').last;
    final url = await _repo.uploadProfilePhoto(
      imageBytes: bytes,
      fileExtension: ext,
    );
    if (!mounted) return;
    setState(() => _isUploadingPhoto = false);

    if (url != null) {
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to upload photo. Please try again.'),
        ),
      );
    }
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
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppConstants.primaryGreen,
                          ),
                        )
                      : _profile == null
                      ? _ProfileLoadError(onRetry: _loadData)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                          children: [
                            _ProfileHeaderCard(
                              profile: _profile!,
                              unsyncedCount: _unsyncedCount,
                              isUploadingPhoto: _isUploadingPhoto,
                              onEditPhoto: _pickProfilePhoto,
                              onSyncTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Syncing records...'),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            _FarmDetailsSection(
                              profile: _profile!,
                              expanded: _farmDetailsExpanded,
                              onToggle: () => setState(
                                () => _farmDetailsExpanded =
                                    !_farmDetailsExpanded,
                              ),
                              // Use pushRoute so Settings is pushed onto the
                              // navigator stack — allowing a subsequent pop.
                              onEdit: () =>
                                  context.pushRoute(AppRoutes.farmerSettings),
                            ),
                            const SizedBox(height: 20),
                            _FinancialRecordsSection(
                              outstandingLoans: _outstandingLoans,
                              monthExpenses: _monthExpenses,
                              harvestCount: _harvestCount,
                              onLoansTap: () =>
                                  context.goTab(AppRoutes.myLoans),
                              onExpensesTap: () =>
                                  context.goTab(AppRoutes.myExpenses),
                              onHarvestSummaryTap: () =>
                                  context.goTab(AppRoutes.myHarvestSummary),
                            ),
                            const SizedBox(height: 16),
                            _BalikTangkilikCard(
                              capitalShares: _profile!.capitalShares,
                              onTap: () =>
                                  context.goTab(AppRoutes.myContribution),
                            ),
                            const SizedBox(height: 20),
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
              profilePhotoUrl: _profile?.profilePhotoUrl,
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () =>
                  context.pushRoute(AppRoutes.farmerNotifications),
              onSettingsTap: () async {
                await context.pushRoute(AppRoutes.farmerSettings);
                if (mounted) _loadData();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Header Card
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeaderCard extends StatelessWidget {
  final FarmerProfileModel profile;
  final int unsyncedCount;
  final bool isUploadingPhoto;
  final VoidCallback onEditPhoto;
  final VoidCallback onSyncTap;

  const _ProfileHeaderCard({
    required this.profile,
    required this.unsyncedCount,
    required this.isUploadingPhoto,
    required this.onEditPhoto,
    required this.onSyncTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 16,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(40),
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppConstants.primaryGreen,
                              width: 2,
                            ),
                          ),
                          child: profile.hasPhoto
                              ? Image.network(
                                  profile.profilePhotoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _PhotoPlaceholder(),
                                )
                              : _PhotoPlaceholder(),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: onEditPhoto,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryGreen,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: isUploadingPhoto
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.edit_rounded,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              profile.fullName,
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppConstants.onSurface,
                              ),
                            ),
                            if (profile.isVerified)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppConstants.successGreen.withValues(
                                    alpha: 0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusFull,
                                  ),
                                  border: Border.all(
                                    color: AppConstants.successGreen.withValues(
                                      alpha: 0.20,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'ACTIVE MEMBER',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppConstants.successGreen,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppConstants.warningAmber.withValues(
                                    alpha: 0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusFull,
                                  ),
                                  border: Border.all(
                                    color: AppConstants.warningAmber.withValues(
                                      alpha: 0.20,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'PENDING VERIFICATION',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppConstants.warningAmber,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile.memberId != null
                              ? 'Member since ${profile.memberSinceLabel} • ${profile.memberId}'
                              : 'Member since ${profile.memberSinceLabel}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppConstants.onSurfaceVariant,
                          ),
                        ),
                        if (profile.sitio != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: AppConstants.onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  profile.sitio!,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppConstants.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Sync status
              if (unsyncedCount > 0)
                GestureDetector(
                  onTap: onSyncTap,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppConstants.warningAmber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                      border: Border.all(
                        color: AppConstants.warningAmber.withValues(
                          alpha: 0.25,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.sync_problem_rounded,
                              size: 18,
                              color: AppConstants.warningAmber,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '$unsyncedCount unsynced record${unsyncedCount == 1 ? '' : 's'}',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppConstants.warningAmber,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'SYNC NOW',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppConstants.warningAmber,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (unsyncedCount > 0) const SizedBox(height: 14),

              // Profile completion
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      profile.isComplete
                          ? 'Profile complete'
                          : 'Profile ${profile.completionPercentInt}% complete — tap Edit to finish',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppConstants.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: profile.completionPercent,
                  minHeight: 7,
                  backgroundColor: const Color(0xFFCFE6F2),
                  valueColor: const AlwaysStoppedAnimation(
                    AppConstants.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppConstants.limeGreen,
      child: const Icon(
        Icons.person_rounded,
        color: AppConstants.primaryGreen,
        size: 36,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Farm Details Section
// ─────────────────────────────────────────────────────────────────────────────

class _FarmDetailsSection extends StatelessWidget {
  final FarmerProfileModel profile;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  const _FarmDetailsSection({
    required this.profile,
    required this.expanded,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.agriculture_rounded,
                          color: AppConstants.primaryGreen,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Farm Details',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.primaryGreen,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppConstants.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _DetailField(
                            label: 'Farm Name',
                            value: profile.farmName ?? 'Not set',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _DetailField(
                            label: 'Land Area',
                            value: profile.landAreaHectares != null
                                ? '${profile.landAreaHectares!.toStringAsFixed(1)} hectares'
                                : 'Not set',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _DetailField(
                      label: 'Farm Location',
                      value: profile.farmLocation ?? 'Not set',
                      icon: Icons.pin_drop_outlined,
                    ),
                    if (profile.farmAddress != null &&
                        profile.farmAddress!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _DetailField(
                        label: 'Address',
                        value: profile.farmAddress!,
                        icon: Icons.location_city_outlined,
                      ),
                    ],
                    if (profile.hasCoordinates) ...[
                      const SizedBox(height: 14),
                      Text(
                        'LOCATION PREVIEW',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.outline,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 170,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                          border: Border.all(
                            color: AppConstants.outline.withValues(alpha: 0.30),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: fm.FlutterMap(
                          options: fm.MapOptions(
                            initialCenter: LatLng(
                              profile.farmLatitude!,
                              profile.farmLongitude!,
                            ),
                            initialZoom: 15,
                            interactionOptions: const fm.InteractionOptions(
                              flags: fm.InteractiveFlag.none,
                            ),
                          ),
                          children: [
                            fm.TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.sp3coop.sagana',
                              tileProvider: fm.NetworkTileProvider(),
                            ),
                            fm.MarkerLayer(
                              markers: [
                                fm.Marker(
                                  point: LatLng(
                                    profile.farmLatitude!,
                                    profile.farmLongitude!,
                                  ),
                                  width: 36,
                                  height: 36,
                                  child: const Icon(
                                    Icons.location_on,
                                    color: AppConstants.primaryGreen,
                                    size: 36,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'PRIMARY CROPS',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.outline,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    profile.primaryCrops.isEmpty
                        ? Text(
                            'No crops added yet',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppConstants.outline,
                            ),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: profile.primaryCrops
                                .map(
                                  (crop) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD5ECF8),
                                      borderRadius: BorderRadius.circular(
                                        AppConstants.radiusMd,
                                      ),
                                    ),
                                    child: Text(
                                      crop,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppConstants.primaryGreen,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppConstants.onSurfaceVariant,
                              ),
                              children: [
                                const TextSpan(text: 'Years Farming: '),
                                TextSpan(
                                  text: profile.yearsFarming != null
                                      ? '${profile.yearsFarming} years'
                                      : 'Not set',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    color: AppConstants.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // CORRECT: GestureDetector + Container instead of OutlinedButton
                        GestureDetector(
                          onTap: onEdit,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppConstants.primaryGreen.withValues(
                                  alpha: 0.40,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusMd,
                              ),
                            ),
                            child: Text(
                              'Edit Farm Details',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppConstants.primaryGreen,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const _DetailField({required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppConstants.outline,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: AppConstants.primaryGreen),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.onSurface,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Financial Records Section
// ─────────────────────────────────────────────────────────────────────────────

class _FinancialRecordsSection extends StatelessWidget {
  final double outstandingLoans;
  final double monthExpenses;
  final int harvestCount;
  final VoidCallback onLoansTap;
  final VoidCallback onExpensesTap;
  final VoidCallback onHarvestSummaryTap;

  const _FinancialRecordsSection({
    required this.outstandingLoans,
    required this.monthExpenses,
    required this.harvestCount,
    required this.onLoansTap,
    required this.onExpensesTap,
    required this.onHarvestSummaryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Financial Records',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppConstants.onSurface,
            ),
          ),
        ),
        _RecordRow(
          icon: Icons.eco_outlined,
          iconColor: AppConstants.tertiaryContainer,
          title: 'My Input Loans',
          subtitle: outstandingLoans > 0
              ? '₱${outstandingLoans.toStringAsFixed(2)} outstanding'
              : 'No outstanding loans',
          onTap: onLoansTap,
        ),
        const SizedBox(height: 8),
        _RecordRow(
          icon: Icons.receipt_outlined,
          iconColor: AppConstants.amber,
          title: 'My Expenses',
          subtitle: '₱${monthExpenses.toStringAsFixed(2)} this month',
          onTap: onExpensesTap,
        ),
        const SizedBox(height: 8),
        _RecordRow(
          icon: Icons.grass_rounded,
          iconColor: AppConstants.primaryGreen,
          title: 'My Harvest Summary',
          subtitle:
              '$harvestCount harvest record${harvestCount == 1 ? '' : 's'}',
          onTap: onHarvestSummaryTap,
        ),
      ],
    );
  }
}

class _RecordRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RecordRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppConstants.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 11,
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Balik-Tangkilik Card
// ─────────────────────────────────────────────────────────────────────────────

class _BalikTangkilikCard extends StatelessWidget {
  final double capitalShares;
  final VoidCallback onTap;

  const _BalikTangkilikCard({required this.capitalShares, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppConstants.primaryGreen, AppConstants.primaryContainer],
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -20,
              right: -20,
              child: Icon(
                Icons.savings_rounded,
                size: 120,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Balik-Tangkilik & Capital Share',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your annual distribution rewards based on cooperative participation and stock investment.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.80),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Capital Shares: ₱${capitalShares.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.trending_up_rounded, size: 16),
                  label: Text(
                    'View My Contribution',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.secondaryContainer,
                    foregroundColor: AppConstants.charcoal,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Settings Shortcut Row  (replaces the old Support & Info / Sign Out block)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Profile Load Error
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileLoadError extends StatelessWidget {
  final VoidCallback onRetry;
  const _ProfileLoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: AppConstants.outline.withValues(alpha: 0.60),
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load your profile',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppConstants.charcoal,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: GoogleFonts.poppins(color: AppConstants.primaryGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
