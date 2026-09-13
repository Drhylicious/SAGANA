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
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../data/services/sync_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../../data/services/profile_state_service.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/profile_avatar.dart';

class FarmerProfileScreen extends StatefulWidget {
  const FarmerProfileScreen({super.key});

  @override
  State<FarmerProfileScreen> createState() => _FarmerProfileScreenState();
}

class _FarmerProfileScreenState extends State<FarmerProfileScreen> {
  final _repo = FarmerProfileRepository();
  final _notifRepo = NotificationRepository();
  final _marketLinkingRepo = MarketLinkingRepository();
  final _picker = ImagePicker();

  FarmerProfileModel? _profile;
  double _outstandingLoans = 0;
  double _monthExpenses = 0;
  int _harvestCount = 0;
  int _unsyncedCount = 0;
  int _unreadCount = 0;
  int _programCount = 0;
  int _marketLinkingCount = 0;
  bool _isLoading = true;
  bool _farmDetailsExpanded = true;
  bool _isUploadingPhoto = false;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    AppEventService.instance.addListener(_onDataChanged);
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
    _loadData();
  }

  @override
  void dispose() {
    AppEventService.instance.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchProfile(),
      _repo.fetchOutstandingLoans(),
      _repo.fetchThisMonthExpenses(),
      _repo.fetchHarvestRecordCount(),
      _notifRepo.fetchUnreadCount(),
      _repo.fetchMyProgramCount(),
      _marketLinkingRepo.fetchMyEnrollmentCount(),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as FarmerProfileModel?;
      _outstandingLoans = results[1] as double;
      _monthExpenses = results[2] as double;
      _harvestCount = results[3] as int;
      _unreadCount = results[4] as int;
      _programCount = results[5] as int;
      _marketLinkingCount = results[6] as int;
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
    final url = await _repo.updatePhoto(
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
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(message: "You're offline — some actions, like changing your photo, require an internet connection."),
          Expanded(
            child: Stack(
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
                      ? _ProfileLoadError(onRetry: _loadData, isOnline: _isOnline)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 5),
                          children: [
                            _ProfileHeaderCard(
                              profile: _profile!,
                              unsyncedCount: _unsyncedCount,
                              isUploadingPhoto: _isUploadingPhoto,
                              onEditPhoto: _pickProfilePhoto,
                              onSyncTap: () async {
                                final isOnline = await ConnectivityService
                                    .instance
                                    .checkConnectivity();
                                if (!isOnline) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'No internet connection. Records will sync automatically once you\'re back online.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Syncing records...'),
                                  ),
                                );
                                // No explicit _loadData() call here anymore —
                                // SyncService.syncPending() now broadcasts via
                                // AppEventService.notify() on completion,
                                // which this screen already listens for
                                // (_onDataChanged). Calling both was a
                                // redundant double-fetch (Final Verification,
                                // item 2).
                                await SyncService.syncPending();
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
                              onEdit: () async {
                                await context.pushRoute(
                                  AppRoutes.editFarmDetails,
                                );
                                if (mounted) _loadData();
                              },
                            ),
                            const SizedBox(height: 20),
                            _FarmRecordsSection(
                              outstandingLoans: _outstandingLoans,
                              monthExpenses: _monthExpenses,
                              harvestCount: _harvestCount,
                              onLoansTap: () =>
                                  context.pushRoute(AppRoutes.myLoans),
                              onExpensesTap: () =>
                                  context.pushRoute(AppRoutes.myExpenses),
                              onHarvestSummaryTap: () =>
                                  context.pushRoute(AppRoutes.myHarvestSummary),
                            ),
                            const SizedBox(height: 20),
                            const _CooperativeBenefitsHeader(),
                            _RecordRow(
                              icon: Icons.volunteer_activism_rounded,
                              iconColor: AppConstants.programPurple,
                              title: 'Programs',
                              subtitle:
                                  '$_programCount active program${_programCount == 1 ? '' : 's'}',
                              onTap: () =>
                                  context.pushRoute(AppRoutes.myPrograms),
                            ),
                            if (_marketLinkingCount > 0) ...[
                              const SizedBox(height: 8),
                              _RecordRow(
                                icon: Icons.eco_rounded,
                                iconColor: AppConstants.primaryGreen,
                                title: 'DA-AMAD Market Linking',
                                subtitle: 'View your enrollment status',
                                onTap: () => context
                                    .pushRoute(AppRoutes.myMarketLinking),
                              ),
                            ],
                            const SizedBox(height: 8),
                            _RecordRow(
                              icon: Icons.groups_outlined,
                              iconColor: AppConstants.primaryGreen,
                              title: 'Balik-Tangkilik & Capital Share',
                              subtitle:
                                  'Capital Shares: ₱${_profile!.capitalShares.toStringAsFixed(2)}',
                              onTap: () =>
                                  context.pushRoute(AppRoutes.myContribution),
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
              title: 'Profile',
              profilePhotoUrl: _profile?.profilePhotoUrl,
              unreadCount: _unreadCount,
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
                  ProfileAvatar(
                    photoUrl: profile.profilePhotoUrl,
                    displayName: profile.fullName,
                    radius: 40,
                    onTap: isUploadingPhoto ? null : onEditPhoto,
                    badge: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppConstants.primaryGreen,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: isUploadingPhoto
                          ? const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                    ),
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
                            if (profile.accountStatus == 'suspended')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppConstants.errorRed.withValues(
                                    alpha: 0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusFull,
                                  ),
                                  border: Border.all(
                                    color: AppConstants.errorRed.withValues(
                                      alpha: 0.20,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'ACCOUNT SUSPENDED',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppConstants.errorRed,
                                    letterSpacing: 0.3,
                                  ),
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
                        if (profile.purok != null) ...[
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
                                  profile.purok!,
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
                    // farm_location (legacy duplicate of farm_address) has
                    // been dropped from the schema — farmAddress is now
                    // the sole source for this field (Phase 4 cleanup).
                    _DetailField(
                      label: 'Farm Location',
                      value: (profile.farmAddress?.isNotEmpty ?? false)
                          ? profile.farmAddress!
                          : 'Not set',
                      icon: Icons.pin_drop_outlined,
                    ),
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
// Farm Records Section
// ─────────────────────────────────────────────────────────────────────────────

class _FarmRecordsSection extends StatelessWidget {
  final double outstandingLoans;
  final double monthExpenses;
  final int harvestCount;
  final VoidCallback onLoansTap;
  final VoidCallback onExpensesTap;
  final VoidCallback onHarvestSummaryTap;

  const _FarmRecordsSection({
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
            'Farm Records',
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
          title: 'Input Loans',
          subtitle: outstandingLoans > 0
              ? '₱${outstandingLoans.toStringAsFixed(2)} outstanding'
              : 'No outstanding loans',
          onTap: onLoansTap,
        ),
        const SizedBox(height: 8),
        _RecordRow(
          icon: Icons.receipt_outlined,
          iconColor: AppConstants.amber,
          title: 'Expenses',
          subtitle: '₱${monthExpenses.toStringAsFixed(2)} this month',
          onTap: onExpensesTap,
        ),
        const SizedBox(height: 8),
        _RecordRow(
          icon: Icons.grass_rounded,
          iconColor: AppConstants.primaryGreen,
          title: 'Harvest Summary',
          subtitle:
              '$harvestCount harvest record${harvestCount == 1 ? '' : 's'}',
          onTap: onHarvestSummaryTap,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cooperative Benefits Section
// ─────────────────────────────────────────────────────────────────────────────

class _CooperativeBenefitsHeader extends StatelessWidget {
  const _CooperativeBenefitsHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        'Cooperative Benefits',
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppConstants.onSurface,
        ),
      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Market Linking Entry Card
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Settings Shortcut Row  (replaces the old Support & Info / Sign Out block)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Profile Load Error
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileLoadError extends StatelessWidget {
  final VoidCallback onRetry;
  // Distinguishes "you're offline" from a genuine load failure — same
  // underlying _profile == null result either way (fetchProfile() collapses
  // both cases), but the message/icon shown now reflects which one it
  // actually is, using connectivity state at render time. No caching of a
  // last-known profile added here — that's a separate, larger decision.
  final bool isOnline;
  const _ProfileLoadError({required this.onRetry, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOnline ? Icons.error_outline_rounded : Icons.wifi_off_rounded,
              size: 40,
              color: AppConstants.outline.withValues(alpha: 0.60),
            ),
            const SizedBox(height: 12),
            Text(
              isOnline
                  ? 'Could not load your profile'
                  : 'You\'re offline',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppConstants.charcoal,
              ),
            ),
            if (!isOnline) ...[
              const SizedBox(height: 4),
              Text(
                'Your profile will load once you\'re back online.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
            ],
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