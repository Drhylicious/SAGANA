import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/harvest_model.dart';
import '../../../data/repositories/harvest_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/services/profile_state_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';

class HarvestHubScreen extends StatefulWidget {
  const HarvestHubScreen({super.key});

  @override
  State<HarvestHubScreen> createState() => _HarvestHubScreenState();
}

class _HarvestHubScreenState extends State<HarvestHubScreen> {
  final _harvestRepo = HarvestRepository();
  final _notifRepo = NotificationRepository();
  final _profileState = FarmerProfileStateService.instance;

  HarvestStats _stats = HarvestStats.empty;
  List<HarvestModel> _allHarvests = [];
  List<HarvestModel> _filtered = [];
  Map<String, int> _inventoryStats = {'total': 0, 'low_stock': 0};
  HarvestFilter _activeFilter = HarvestFilter.all;
  int _unreadCount = 0;
  bool _isLoading = true;

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
        _harvestRepo.fetchStats(),
        _harvestRepo.fetchRecentHarvests(),
        _harvestRepo.fetchInventoryStats(),
        _notifRepo.fetchUnreadCount(),
      ]);
      await _profileState.refresh();
      if (!mounted) return;
      setState(() {
        _stats = results[0] as HarvestStats;
        _allHarvests = results[1] as List<HarvestModel>;
        _inventoryStats = results[2] as Map<String, int>;
        _unreadCount = results[3] as int;
        _applyFilter();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    _filtered = _allHarvests.where((h) => _activeFilter.matches(h)).toList();
  }

  void _setFilter(HarvestFilter f) {
    setState(() {
      _activeFilter = f;
      _applyFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
        children: [
          // Subtle dot pattern background
          Positioned.fill(child: CustomPaint(painter: _DotPatternPainter())),

          // Content
          Column(
            children: [
              const SizedBox(height: 72),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Header ────────────────────────────────────────
                        _HeaderSection(),
                        const SizedBox(height: 24),

                        // ── Hero Bento Cards ──────────────────────────────
                        _HeroCards(
                          inventoryTotal: _inventoryStats['total'] ?? 0,
                          inventoryLowStock: _inventoryStats['low_stock'] ?? 0,
                          onRecordHarvest: () =>
                              context.pushRoute(AppRoutes.selectCropForHarvest),
                          onMyCrops: () =>
                              context.pushRoute(AppRoutes.cropListing),
                          onManageInventory: () =>
                              context.pushRoute(AppRoutes.manageInventory),
                        ),
                        const SizedBox(height: 16),

                        // ── Stats Bar ─────────────────────────────────────
                        _StatsBar(stats: _stats, isLoading: _isLoading),
                        const SizedBox(height: 24),

                        // ── Recent Harvests ───────────────────────────────
                        _RecentHarvestsSection(
                          harvests: _filtered,
                          allHarvests: _allHarvests,
                          activeFilter: _activeFilter,
                          isLoading: _isLoading,
                          onFilterChanged: _setFilter,
                          onViewAll: () =>
                              context.pushRoute(AppRoutes.harvestHistory),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Top App Bar ───────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: 'Harvest Hub',
              unreadCount: _unreadCount,
              hideProfileAvatar: true,
              onProfileTap: () => context.goTab(AppRoutes.farmerProfile),
              onNotificationTap: () =>
                  context.pushRoute(AppRoutes.farmerNotifications),
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
// Header Section
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Bento Cards
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCards extends StatelessWidget {
  final int inventoryTotal;
  final int inventoryLowStock;
  final VoidCallback onRecordHarvest;
  final VoidCallback onMyCrops;
  final VoidCallback onManageInventory;

  const _HeroCards({
    required this.inventoryTotal,
    required this.inventoryLowStock,
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
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppConstants.primaryGreen, AppConstants.tertiaryContainer],
          ),
          icon: Icons.eco_rounded,
          iconBg: Colors.white.withValues(alpha: 0.20),
          title: 'Record New Harvest',
          subtitle: 'Log daily yields and batch quality',
          subtitleColor: AppConstants.onPrimaryContainer,
          onTap: onRecordHarvest,
        ),
        const SizedBox(height: 12),

        // My Crops
        _HeroCard(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppConstants.lightGreen, AppConstants.midGreen],
          ),
          icon: Icons.grass_rounded,
          iconBg: Colors.white.withValues(alpha: 0.20),
          title: 'My Crops',
          subtitle: 'Manage the crops you grow',
          subtitleColor: Colors.white.withValues(alpha: 0.85),
          onTap: onMyCrops,
        ),
        const SizedBox(height: 12),

        // Manage Inventory
        _HeroCard(
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
  final LinearGradient gradient;
  final IconData icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Color subtitleColor;
  final VoidCallback onTap;

  const _HeroCard({
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withValues(alpha: 0.30),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats Bar
// ─────────────────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final HarvestStats stats;
  final bool isLoading;

  const _StatsBar({required this.stats, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F6FF).withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.04),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          _StatItem(
            label: 'Season',
            value: isLoading ? '—' : '${stats.seasonCount} Harvests',
            valueColor: AppConstants.primaryGreen,
            hasDivider: true,
          ),
          _StatItem(
            label: 'Total Yield',
            value: isLoading ? '—' : _formatYield(stats.totalYieldKg),
            valueColor: AppConstants.primaryGreen,
            hasDivider: true,
          ),
          _StatItem(
            label: 'Records',
            value: isLoading
                ? '—'
                : stats.unsyncedCount > 0
                ? '${stats.unsyncedCount} Unsynced'
                : 'All Synced',
            valueColor: stats.unsyncedCount > 0
                ? AppConstants.warningAmber
                : AppConstants.successGreen,
            hasDivider: false,
          ),
        ],
      ),
    );
  }

  String _formatYield(double kg) {
    if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)}t';
    return '${kg.toStringAsFixed(0)} kg';
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool hasDivider;

  const _StatItem({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.hasDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: hasDivider
            ? BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: AppConstants.outline.withValues(alpha: 0.20),
                  ),
                ),
              )
            : null,
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 9,
                color: AppConstants.outline,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent Harvests Section
// ─────────────────────────────────────────────────────────────────────────────

class _RecentHarvestsSection extends StatelessWidget {
  final List<HarvestModel> harvests;
  final List<HarvestModel> allHarvests;
  final HarvestFilter activeFilter;
  final bool isLoading;
  final ValueChanged<HarvestFilter> onFilterChanged;
  final VoidCallback onViewAll;

  const _RecentHarvestsSection({
    required this.harvests,
    required this.allHarvests,
    required this.activeFilter,
    required this.isLoading,
    required this.onFilterChanged,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Harvests',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppConstants.charcoal,
              ),
            ),
            GestureDetector(
              onTap: onViewAll,
              child: Text(
                'View All',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppConstants.primaryGreen,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: HarvestFilter.values.map((f) {
              final isActive = f == activeFilter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onFilterChanged(f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppConstants.primaryGreen
                          : const Color(0xFFDBF1FE),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      f.label,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isActive
                            ? Colors.white
                            : AppConstants.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        // List
        if (isLoading)
          ...List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _HarvestShimmer(),
            ),
          )
        else if (harvests.isEmpty)
          _EmptyHarvests(
            hasFilter: activeFilter != HarvestFilter.all || allHarvests.isEmpty,
          )
        else
          ...harvests.map(
            (h) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _HarvestCard(harvest: h),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Harvest Card
// ─────────────────────────────────────────────────────────────────────────────

class _HarvestCard extends StatelessWidget {
  final HarvestModel harvest;

  const _HarvestCard({required this.harvest});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
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
                color: const Color(0xFF455A64).withValues(alpha: 0.04),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            children: [
              // Crop icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFDBF1FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _cropIcon(harvest.cropCategory),
                  color: AppConstants.primaryGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),

              // Name + batch
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      harvest.variety != null
                          ? '${harvest.cropName} (${harvest.variety})'
                          : harvest.cropName,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppConstants.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Batch #${harvest.displayBatch} • ${harvest.displayQty}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppConstants.outline,
                      ),
                    ),
                  ],
                ),
              ),

              // Status + date
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _SyncBadge(isSynced: harvest.isSynced),
                  const SizedBox(height: 4),
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
        ),
      ),
    );
  }

  IconData _cropIcon(String category) {
    switch (category.toLowerCase()) {
      case 'grain':
        return Icons.grass_rounded;
      case 'legume':
        return Icons.eco_rounded;
      case 'root & spice crop':
        return Icons.spa_rounded;
      case 'fruit':
        return Icons.local_florist_rounded;
      case 'tree crop':
        return Icons.park_rounded;
      case 'vegetable':
        return Icons.agriculture_rounded;
      default:
        return Icons.eco_rounded;
    }
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('MMM d, hh:mm a').format(dt);
  }
}

class _SyncBadge extends StatelessWidget {
  final bool isSynced;
  const _SyncBadge({required this.isSynced});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isSynced
            ? AppConstants.successGreen.withValues(alpha: 0.10)
            : AppConstants.warningAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSynced ? Icons.cloud_done_rounded : Icons.sync_rounded,
            size: 10,
            color: isSynced
                ? AppConstants.successGreen
                : AppConstants.warningAmber,
          ),
          const SizedBox(width: 3),
          Text(
            isSynced ? 'Synced' : 'Pending',
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: isSynced
                  ? AppConstants.successGreen
                  : AppConstants.warningAmber,
              letterSpacing: 0.5,
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

class _HarvestShimmer extends StatefulWidget {
  @override
  State<_HarvestShimmer> createState() => _HarvestShimmerState();
}

class _HarvestShimmerState extends State<_HarvestShimmer>
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          _block(48, 48),
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
              _block(60, 18),
              const SizedBox(height: 4),
              _block(50, 9),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyHarvests extends StatelessWidget {
  final bool hasFilter;
  const _EmptyHarvests({required this.hasFilter});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.eco_outlined,
            size: 48,
            color: AppConstants.outline.withValues(alpha: 0.50),
          ),
          const SizedBox(height: 12),
          Text(
            hasFilter ? 'No harvests match this filter' : 'No harvests yet',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasFilter
                ? 'Try a different filter'
                : 'Tap "Record New Harvest" to log your first crop',
            style: GoogleFonts.inter(fontSize: 13, color: AppConstants.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}