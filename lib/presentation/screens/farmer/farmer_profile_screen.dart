import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/map_attribution_links.dart';
import '../../../core/constants/osm_config.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/models/dashboard_summary_model.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../data/services/sync_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../../data/services/profile_state_service.dart';
import '../../widgets/app_navigation_drawer.dart';
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
  final _dashboardRepo = DashboardRepository();

  FarmerProfileModel? _profile;
  double _outstandingLoans = 0;
  double _monthExpenses = 0;
  // Relocated from the Farmer Home tab — same DashboardRepository.
  // fetchSummary() call Home itself uses, so this is the identical
  // figure, not a second independent computation of "this year's yield".
  double _annualYieldKg = 0;
  double _annualEarnings = 0;
  int _unsyncedCount = 0;
  int _unreadCount = 0;
  int _programCount = 0;
  int _marketLinkingCount = 0;
  bool _isLoading = true;
  bool _farmDetailsExpanded = true;
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
      _notifRepo.fetchUnreadCount(),
      _repo.fetchMyProgramCount(),
      _marketLinkingRepo.fetchMySubmissionCount(),
      _marketLinkingRepo.fetchHasGingerCrop(),
      _dashboardRepo.fetchSummary(),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as FarmerProfileModel?;
      _outstandingLoans = results[1] as double;
      _monthExpenses = results[2] as double;
      _unreadCount = results[3] as int;
      _programCount = results[4] as int;
      // "DA-AMAD Market Linking" shows for anyone who's ever submitted a
      // Ginger sale OR currently grows Ginger — the latter so a farmer who
      // hasn't touched Market Linking yet can still discover the
      // enrollment flow, not just farmers with existing submission history.
      _marketLinkingCount = (results[5] as int) > 0 || (results[6] as bool)
          ? 1
          : 0;
      final summary = results[7] as DashboardSummaryModel;
      _annualYieldKg = summary.annualYieldKg;
      _annualEarnings = summary.annualEarnings;
      _unsyncedCount = HiveService.getUnsyncedCount();
      _isLoading = false;
    });

    if (_profile != null) {
      FarmerProfileStateService.instance.updateProfile(_profile!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      drawer: AnimatedBuilder(
        animation: FarmerProfileStateService.instance,
        builder: (context, _) {
          final profile = FarmerProfileStateService.instance.profile;
          return AppNavigationDrawer(
            photoUrl: profile?.profilePhotoUrl,
            displayName: profile?.fullName ?? 'Farmer',
            contactEmail: profile?.contactEmail,
            phoneNumber: profile?.phoneNumber,
            onEditProfile: () {
              Navigator.pop(context);
              context.pushRoute(AppRoutes.farmerEditProfile);
            },
            onEditFarmDetails: () {
              Navigator.pop(context);
              context.pushRoute(AppRoutes.editFarmDetails);
            },
            onMyAddresses: () {
              Navigator.pop(context);
              context.pushRoute(AppRoutes.myAddresses);
            },
            onSignOut: () => confirmFarmerSignOut(context),
            onAboutSagana: () => context.pushRoute(AppRoutes.aboutSagana),
            onAboutOrganization: () =>
                context.pushRoute(AppRoutes.aboutCooperative),
            onPrivacyPolicy: () => context.pushRoute(AppRoutes.privacyPolicy),
            onTermsOfUse: () => context.pushRoute(AppRoutes.termsOfUse),
          );
        },
      ),
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(
              message:
                  "You're offline — some actions, like changing your photo, require an internet connection.",
            ),
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
                            ? _ProfileLoadError(
                                onRetry: _loadData,
                                isOnline: _isOnline,
                              )
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  5,
                                ),
                                children: [
                                  _ProfileHeaderCard(
                                    profile: _profile!,
                                    unsyncedCount: _unsyncedCount,
                                    onSyncTap: () async {
                                      final isOnline = await ConnectivityService
                                          .instance
                                          .checkConnectivity();
                                      if (!isOnline) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'No internet connection. Records will sync automatically once you\'re back online.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
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
                                  _AnnualStatsRow(
                                    annualYieldKg: _annualYieldKg,
                                    annualEarnings: _annualEarnings,
                                    isLoading: _isLoading,
                                  ),
                                  const SizedBox(height: 20),
                                  _FarmRecordsSection(
                                    outstandingLoans: _outstandingLoans,
                                    monthExpenses: _monthExpenses,
                                    onLoansTap: () =>
                                        context.pushRoute(AppRoutes.myLoans),
                                    onExpensesTap: () =>
                                        context.pushRoute(AppRoutes.myExpenses),
                                    onTransactionHistoryTap: () =>
                                        context.pushRoute(
                                          AppRoutes.myTransactionHistory,
                                        ),
                                    onMyOrdersTap: () => context.pushRoute(
                                      AppRoutes.farmerMyOrders,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  const _CooperativeBenefitsHeader(),
                                  _RecordRow(
                                    icon: Icons.volunteer_activism_rounded,
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
                                      title: 'DA-AMAD Market Linking',
                                      subtitle: 'View your enrollment status',
                                      onTap: () => context.pushRoute(
                                        AppRoutes.myMarketLinking,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  _RecordRow(
                                    icon: Icons.groups_outlined,
                                    title: 'Balik-Tangkilik & Capital Share',
                                    subtitle:
                                        'Capital Shares: ₱${_profile!.capitalShares.toStringAsFixed(2)}',
                                    onTap: () => context.pushRoute(
                                      AppRoutes.myContribution,
                                    ),
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
                    enableMenu: true,
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
  final VoidCallback onSyncTap;

  const _ProfileHeaderCard({
    required this.profile,
    required this.unsyncedCount,
    required this.onSyncTap,
  });

  @override
  Widget build(BuildContext context) {
    // Account standing is coordinated with the Admin Members module —
    // accountStatus is the raw user_roles.status value Admin's own
    // suspend/reactivate RPCs write, not a Farmer-side concept. 'inactive'
    // (a login-recency derivation) is deliberately never surfaced here,
    // per the existing rule that it's an Admin-facing indicator only —
    // anything other than a manual suspension displays as Active.
    final isSuspended = profile.accountStatus == 'suspended';
    // "Farmer Member" is a distinct concept from account standing —
    // farmer_profiles.is_verified, set once by Admin after SP3 membership
    // verification. Shown only for verified members, independent of
    // whether the account is currently active or suspended.
    final isApprovedMember = profile.isVerified;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.80),
                AppConstants.primaryGreen.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            border: Border.all(
              color: AppConstants.primaryGreen.withValues(alpha: 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.06),
                blurRadius: 16,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A slim brand-accent bar along the top edge — enough to
              // read as "SAGANA" without turning the card into a banner.
              Container(
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppConstants.radiusXl),
                  ),
                  gradient: LinearGradient(
                    colors: [
                      AppConstants.primaryGreen,
                      AppConstants.primaryGreen.withValues(alpha: 0.35),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status badge in its own full-width row, right-aligned
                    // — "upper-right of the header," not squeezed in beside
                    // the name (that approach forced long names into an
                    // ugly mid-word wrap/truncation, since the badge was
                    // eating into the name's available width). This way the
                    // avatar+name row below gets the entire card width to
                    // itself. Exactly one badge now — Active vs. Suspended
                    // is a single account-status fact, not two things to
                    // show at once.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _StatusBadge(
                          label: isSuspended ? 'SUSPENDED' : 'ACTIVE',
                          color: isSuspended
                              ? AppConstants.errorRed
                              : AppConstants.successGreen,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Not editable here — per design, the avatar can
                        // only be changed via Edit Profile, which has its
                        // own working photo picker. No onTap/badge means no
                        // affordance suggesting this is tappable.
                        ProfileAvatar(
                          photoUrl: profile.profilePhotoUrl,
                          displayName: profile.fullName,
                          radius: 40,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.fullName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppConstants.onSurface,
                                ),
                              ),
                              // Only shown for verified members — a
                              // distinct fact from account standing above,
                              // never implied by it.
                              if (isApprovedMember) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Farmer Member',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppConstants.primaryGreen,
                                  ),
                                ),
                              ],
                              // Contact info — email if set, else phone,
                              // both if both are set, nothing if neither
                              // is. contactEmail (the farmer's own entered
                              // address), never the synthetic
                              // username@sagana.local auth address.
                              if ((profile.contactEmail?.isNotEmpty ?? false) ||
                                  (profile.phoneNumber?.isNotEmpty ??
                                      false)) ...[
                                const SizedBox(height: 10),
                                if (profile.contactEmail?.isNotEmpty ?? false)
                                  _ContactLine(
                                    icon: Icons.email_outlined,
                                    text: profile.contactEmail!,
                                  ),
                                if (profile.phoneNumber?.isNotEmpty ??
                                    false) ...[
                                  const SizedBox(height: 3),
                                  _ContactLine(
                                    icon: Icons.phone_outlined,
                                    text: profile.phoneNumber!,
                                  ),
                                ],
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
                            color: AppConstants.warningAmber.withValues(
                              alpha: 0.08,
                            ),
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// A "boxed" status indicator (small rounded-rect, not a full pill) —
// referencing the style Admin already uses for member status, per the
// requested redesign, without copying Admin's card layout itself.
class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ContactLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ContactLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppConstants.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
        ),
      ],
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
                                ? '${profile.landAreaHectares!.toStringAsFixed(1)} ha'
                                : 'Not set',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _DetailField(
                            label: 'Years Farming',
                            value: profile.yearsFarming != null
                                ? '${profile.yearsFarming}'
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
                            const OsmMapAttribution(),
                            fm.TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.sp3coop.sagana',
                              tileProvider: fm.NetworkTileProvider(
                                headers: {'User-Agent': kOsmTileUserAgent},
                              ),
                              // flutter_map cancels in-flight tile requests
                              // for tiles that go out of view (e.g. the
                              // screen is closed mid-fetch) — expected, not
                              // a real failure. Without this it surfaces as
                              // a noisy "EXCEPTION CAUGHT BY IMAGE RESOURCE
                              // SERVICE" log.
                              errorTileCallback: (tile, error, stackTrace) {},
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
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
// Annual Stats Row — relocated from the Farmer Home tab (Final
// Verification round). Same DashboardRepository.fetchSummary() figures
// Home itself used, just displayed here now instead — not a second,
// independent computation of "this year's yield/earnings".
// ─────────────────────────────────────────────────────────────────────────────

class _AnnualStatsRow extends StatelessWidget {
  final double annualYieldKg;
  final double annualEarnings;
  final bool isLoading;

  const _AnnualStatsRow({
    required this.annualYieldKg,
    required this.annualEarnings,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return Row(
      children: [
        Expanded(
          child: _AnnualStatTile(
            icon: Icons.eco_rounded,
            color: AppConstants.primaryGreen,
            label: AppLocalizations.of(context).farmerDashAnnualYield(year),
            value: isLoading
                ? '—'
                : '${NumberFormat('#,##0').format(annualYieldKg)} kg',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _AnnualStatTile(
            icon: Icons.payments_rounded,
            color: AppConstants.buyerBlue,
            label: AppLocalizations.of(context).farmerDashAnnualEarnings(year),
            value: isLoading
                ? '—'
                : '₱${NumberFormat('#,##0').format(annualEarnings)}',
          ),
        ),
      ],
    );
  }
}

class _AnnualStatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _AnnualStatTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppConstants.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Farm Records Section
// ─────────────────────────────────────────────────────────────────────────────

class _FarmRecordsSection extends StatelessWidget {
  final double outstandingLoans;
  final double monthExpenses;
  final VoidCallback onLoansTap;
  final VoidCallback onExpensesTap;
  final VoidCallback onTransactionHistoryTap;
  final VoidCallback onMyOrdersTap;

  const _FarmRecordsSection({
    required this.outstandingLoans,
    required this.monthExpenses,
    required this.onLoansTap,
    required this.onExpensesTap,
    required this.onTransactionHistoryTap,
    required this.onMyOrdersTap,
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
          title: 'Input Loans',
          subtitle: outstandingLoans > 0
              ? '₱${outstandingLoans.toStringAsFixed(2)} outstanding'
              : 'No outstanding loans',
          onTap: onLoansTap,
        ),
        const SizedBox(height: 8),
        _RecordRow(
          icon: Icons.receipt_outlined,
          title: 'Expenses',
          subtitle: '₱${monthExpenses.toStringAsFixed(2)} this month',
          onTap: onExpensesTap,
        ),
        const SizedBox(height: 8),
        _RecordRow(
          icon: Icons.receipt_long_outlined,
          title: 'Transaction History',
          subtitle: 'Your sales across every selling channel',
          onTap: onTransactionHistoryTap,
        ),
        const SizedBox(height: 8),
        _RecordRow(
          icon: Icons.shopping_bag_outlined,
          title: 'Orders',
          subtitle: 'Orders you\'ve placed on the Marketplace',
          onTap: onMyOrdersTap,
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

// Icon rendering intentionally has no per-row color — a single neutral
// tone for every row, matching farmer_bottom_nav.dart's established
// "simple, non-colorful" icon convention instead of the previous
// per-item rainbow of tinted circular backgrounds.
class _RecordRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RecordRow({
    required this.icon,
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
                  color: AppConstants.outline.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppConstants.primaryGreen, size: 20),
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
              isOnline ? 'Could not load your profile' : 'You\'re offline',
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
