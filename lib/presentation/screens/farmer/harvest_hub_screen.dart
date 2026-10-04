import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/harvest_model.dart';
import '../../../data/models/farmer_crop_model.dart' hide HarvestFilter;
import '../../../data/repositories/crop_repository.dart';
import '../../../data/repositories/harvest_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/services/profile_state_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_navigation_drawer.dart';
import '../../widgets/shared_widgets.dart';

class HarvestHubScreen extends StatefulWidget {
  const HarvestHubScreen({super.key});

  @override
  State<HarvestHubScreen> createState() => _HarvestHubScreenState();
}

class _HarvestHubScreenState extends State<HarvestHubScreen> {
  final _harvestRepo = HarvestRepository();
  final _cropRepo = CropRepository();
  final _notifRepo = NotificationRepository();
  final _profileState = FarmerProfileStateService.instance;

  List<HarvestModel> _allHarvests = [];
  Map<String, FarmerCropModel> _cropsById = {};
  Map<String, int> _inventoryStats = {'total': 0, 'low_stock': 0};
  int _seasonHarvestCount = 0;
  int _cropCount = 0;
  int _unreadCount = 0;
  bool _isLoading = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    AppEventService.instance.addListener(_onHarvestRecorded);
    _profileState.addListener(_onProfileStateChanged);
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
    AppEventService.instance.removeListener(_onHarvestRecorded);
    _profileState.removeListener(_onProfileStateChanged);
    super.dispose();
  }

  void _onHarvestRecorded() {
    if (mounted) _loadData();
  }

  void _onProfileStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _harvestRepo.fetchRecentHarvests(limit: 5),
        _harvestRepo.fetchInventoryStats(),
        _notifRepo.fetchUnreadCount(),
        _harvestRepo.fetchStats(),
        _cropRepo.fetchCrops(),
      ]);
      await _profileState.refresh();
      if (!mounted) return;
      final crops = results[4] as List<FarmerCropModel>;
      setState(() {
        _allHarvests = results[0] as List<HarvestModel>;
        _inventoryStats = results[1] as Map<String, int>;
        _unreadCount = results[2] as int;
        _seasonHarvestCount = (results[3] as HarvestStats).seasonCount;
        _cropCount = crops.length;
        _cropsById = {for (final c in crops) c.id: c};
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
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
            onAboutOrganization: () => context.pushRoute(AppRoutes.aboutCooperative),
            onPrivacyPolicy: () => context.pushRoute(AppRoutes.privacyPolicy),
            onTermsOfUse: () => context.pushRoute(AppRoutes.termsOfUse),
          );
        },
      ),
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(
              message: "You're offline — new harvests are saved on your device and will sync automatically, but your harvest history may not be up to date.",
            ),
          Expanded(
            child: Stack(
              children: [
                // Subtle dot pattern background
                Positioned.fill(
                  child: CustomPaint(painter: _DotPatternPainter()),
                ),

                // Content
                Column(
                  children: [
                    const SizedBox(height: 50),
                    Expanded(
                      child: RefreshIndicator(
                        color: AppConstants.primaryGreen,
                        onRefresh: _loadData,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 24),

                              // ── Hero Bento Cards ──────────────────────────
                              _HeroCards(
                                inventoryTotal: _inventoryStats['total'] ?? 0,
                                inventoryLowStock:
                                    _inventoryStats['low_stock'] ?? 0,
                                seasonHarvestCount: _seasonHarvestCount,
                                cropCount: _cropCount,
                                onRecordHarvest: () => context.pushRoute(
                                    AppRoutes.selectCropForHarvest),
                                onMyCrops: () =>
                                    context.pushRoute(AppRoutes.cropListing),
                                onManageInventory: () => context.pushRoute(
                                    AppRoutes.manageInventory),
                              ),
                              const SizedBox(height: 16),

                              // Season/Records stats moved to Harvest
                              // History as part of its 3-card consolidation
                              // — no longer duplicated here.

                              // ── Recent Harvests ─────────────────────────
                              _RecentHarvestsSection(
                                harvests: _allHarvests,
                                cropsById: _cropsById,
                                isLoading: _isLoading,
                                onViewAll: () => context
                                    .pushRoute(AppRoutes.harvestHistory),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Top App Bar ─────────────────────────────────────────
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FarmerTopBar(
                    // Was "Harvest Hub" — the bottom-nav tab itself is
                    // just "Harvest" (navHarvest), so the on-screen title
                    // didn't match the tab that opens it.
                    title: 'Harvest',
                    unreadCount: _unreadCount,
                    hideProfileAvatar: true,
                    onProfileTap: () =>
                        context.goTab(AppRoutes.farmerProfile),
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
// Dot Pattern Painter
// ─────────────────────────────────────────────────────────────────────────────

class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppConstants.primaryGreen.withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;

    const spacing = 24.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x + 2, y + 2), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Bento Cards
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCards extends StatelessWidget {
  final int inventoryTotal;
  final int inventoryLowStock;
  final int seasonHarvestCount;
  final int cropCount;
  final VoidCallback onRecordHarvest;
  final VoidCallback onMyCrops;
  final VoidCallback onManageInventory;

  const _HeroCards({
    required this.inventoryTotal,
    required this.inventoryLowStock,
    required this.seasonHarvestCount,
    required this.cropCount,
    required this.onRecordHarvest,
    required this.onMyCrops,
    required this.onManageInventory,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Record New Harvest
        _HeroCard(
          backgroundImage: 'assets/images/harvest.jpg',
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppConstants.primaryGreen, AppConstants.tertiaryContainer],
          ),
          icon: Icons.eco_rounded,
          iconBg: Colors.white.withValues(alpha: 0.20),
          title: 'Record New Harvest',
          subtitle: '$seasonHarvestCount harvests this year',
          subtitleColor: AppConstants.onPrimaryContainer,
          onTap: onRecordHarvest,
        ),
        const SizedBox(height: 12),

        // Crop Roster
        _HeroCard(
          backgroundImage: 'assets/images/crop.jpg',
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppConstants.lightGreen, AppConstants.midGreen],
          ),
          icon: Icons.grass_rounded,
          iconBg: Colors.white.withValues(alpha: 0.20),
          title: 'Crop Roster',
          subtitle: '$cropCount crops in your roster',
          subtitleColor: Colors.white.withValues(alpha: 0.85),
          onTap: onMyCrops,
        ),
        const SizedBox(height: 12),

        // Manage Inventory
        _HeroCard(
          backgroundImage: 'assets/images/inventory.jpg',
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF835400), Color(0xFF694300)],
          ),
          icon: Icons.inventory_2_rounded,
          iconBg: Colors.white.withValues(alpha: 0.20),
          title: 'Manage Inventory',
          subtitle: inventoryTotal > 0
              ? '$inventoryTotal batches${inventoryLowStock > 0 ? ' • $inventoryLowStock low stock' : ''}'
              : 'View stock levels',
          subtitleColor: const Color(0xFFFFDDB5),
          onTap: onManageInventory,
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String backgroundImage;
  final LinearGradient gradient;
  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Color subtitleColor;
  final VoidCallback onTap;

  const _HeroCard({
    required this.backgroundImage,
    required this.gradient,
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withValues(alpha: 0.30),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background photo
              Image.asset(backgroundImage, fit: BoxFit.cover),
              // Gradient scrim — same brand colors as before, layered at
              // reduced opacity over the photo so the icon/title/subtitle
              // stay readable regardless of what's in the image.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: gradient.begin,
                    end: gradient.end,
                    colors: [
                      for (final c in gradient.colors) c.withValues(alpha: 0.82),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Icon
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: Colors.white, size: 28),
                    ),
                    // Text
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: subtitleColor,
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
      ),
    );
  }
}

// _StatsBar and _StatItem removed — Season/Records now live on Harvest
// History as part of its 3-card consolidation (_HistoryStatsRow), rather
// than being computed and shown in two places.

// ─────────────────────────────────────────────────────────────────────────────
// Recent Harvests Section
// ─────────────────────────────────────────────────────────────────────────────

class _RecentHarvestsSection extends StatelessWidget {
  final List<HarvestModel> harvests;
  final Map<String, FarmerCropModel> cropsById;
  final bool isLoading;
  final VoidCallback onViewAll;

  const _RecentHarvestsSection({
    required this.harvests,
    required this.cropsById,
    required this.isLoading,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row — matches Farmer Home's Recent Activity header
        // (Expanded label + fixed "View All", both weight 700) instead of
        // the previous mismatched-weight spaceBetween row.
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent Harvests',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.charcoal,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onViewAll,
              child: Text(
                'View All',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.primaryGreen,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Filter chips removed — Harvest History (via "View All") already
        // covers filtering; this is a 5-item preview only, styled to match
        // Farmer Home's Recent Activity card exactly (one bordered
        // container, divider-separated rows, not individually-carded
        // items).
        if (isLoading)
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingGutter),
            decoration: flatCardDecoration(context),
            child: Column(
              children: List.generate(
                3,
                (_) => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: _HarvestRowShimmer(),
                ),
              ),
            ),
          )
        else if (harvests.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingGutter),
            decoration: flatCardDecoration(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(
                    Icons.eco_outlined,
                    size: 40,
                    color: AppConstants.outline.withValues(alpha: 0.50),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No harvests yet',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppConstants.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: flatCardDecoration(context),
            child: Column(
              children: harvests
                  .asMap()
                  .entries
                  .map(
                    (e) => Column(
                      children: [
                        _HarvestTile(harvest: e.value, imageUrl: cropsById[e.value.cropId]?.displayImageUrl),
                        if (e.key < harvests.length - 1)
                          Divider(
                            height: 1,
                            color: AppConstants.outline.withValues(alpha: 0.08),
                          ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Harvest Tile — mirrors Farmer Home's _ActivityTile structure exactly.
// ─────────────────────────────────────────────────────────────────────────────

class _HarvestTile extends StatelessWidget {
  final HarvestModel harvest;
  final String? imageUrl;

  const _HarvestTile({required this.harvest, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: Container(
              width: 40,
              height: 40,
              color: AppConstants.primaryGreen.withValues(alpha: 0.10),
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        FarmerCropModel.iconForCategory(harvest.cropCategory),
                        color: AppConstants.primaryGreen,
                        size: 20,
                      ),
                    )
                  : Icon(
                      FarmerCropModel.iconForCategory(harvest.cropCategory),
                      color: AppConstants.primaryGreen,
                      size: 20,
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  harvest.variety != null && harvest.variety!.isNotEmpty
                      ? '${harvest.cropName} (${harvest.variety})'
                      : harvest.cropName,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppConstants.charcoal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Batch #${harvest.displayBatch} • ${harvest.displayQty}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppConstants.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                harvest.isSynced ? 'Synced' : 'Pending',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: harvest.isSynced
                      ? AppConstants.successGreen
                      : AppConstants.warningAmber,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatDateTime(harvest.harvestDate),
                style: GoogleFonts.inter(
                  fontSize: 9,
                  color: AppConstants.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('MMM d, hh:mm a').format(dt);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer — one row, matching _HarvestTile's own layout, for use inside the
// flatCardDecoration container while loading (replaces the old
// individually-carded shimmer block, consistent with the tile-based list).
// ─────────────────────────────────────────────────────────────────────────────

class _HarvestRowShimmer extends StatefulWidget {
  const _HarvestRowShimmer();

  @override
  State<_HarvestRowShimmer> createState() => _HarvestRowShimmerState();
}

class _HarvestRowShimmerState extends State<_HarvestRowShimmer>
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
        borderRadius: BorderRadius.circular(6),
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
    return Row(
      children: [
        _block(40, 40),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _block(120, 13),
              const SizedBox(height: 6),
              _block(90, 11),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _block(50, 12),
            const SizedBox(height: 4),
            _block(60, 9),
          ],
        ),
      ],
    );
  }
}