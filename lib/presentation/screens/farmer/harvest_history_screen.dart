import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/harvest_model.dart';
import '../../../data/repositories/harvest_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

class HarvestHistoryScreen extends StatefulWidget {
  const HarvestHistoryScreen({super.key});

  @override
  State<HarvestHistoryScreen> createState() => _HarvestHistoryScreenState();
}

class _HarvestHistoryScreenState extends State<HarvestHistoryScreen> {
  final _repo = HarvestRepository();
  final _searchController = TextEditingController();

  List<HarvestModel> _allHarvests = [];
  List<HarvestModel> _filtered = [];
  List<String> _cropOptions = ['All Crops'];
  Map<String, double> _stats = {'total_yield': 0, 'premium_percent': 0};

  String _activeCrop = 'All Crops';
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchAllHarvests(),
      _repo.fetchHistoryStats(),
    ]);
    if (!mounted) return;

    final harvests = results[0] as List<HarvestModel>;
    final distinctCrops = harvests.map((h) => h.cropName).toSet().toList()
      ..sort();

    setState(() {
      _allHarvests = harvests;
      _stats = results[1] as Map<String, double>;
      _cropOptions = ['All Crops', ...distinctCrops];
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

  void _setCropFilter(String crop) {
    setState(() {
      _activeCrop = crop;
      _applyFilters();
    });
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    _filtered = _allHarvests.where((h) {
      if (_activeCrop != 'All Crops' && h.cropName != _activeCrop) {
        return false;
      }
      if (q.isEmpty) return true;
      return h.cropName.toLowerCase().contains(q) ||
          (h.variety?.toLowerCase().contains(q) ?? false) ||
          (h.batchNumber?.toLowerCase().contains(q) ?? false);
    }).toList();
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
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    children: [
                      // Search
                      _SearchBar(controller: _searchController),
                      const SizedBox(height: 12),

                      // Crop filter chips
                      _CropChips(
                        options: _cropOptions,
                        active: _activeCrop,
                        onSelected: _setCropFilter,
                      ),
                      const SizedBox(height: 20),

                      // Summary stats
                      _SummaryStats(stats: _stats, isLoading: _isLoading),
                      const SizedBox(height: 24),

                      // Section title
                      Text(
                        'Recent Activity',
                        style: GoogleFonts.poppins(
                          fontSize: 18, fontWeight: FontWeight.w700,
                          color: AppConstants.charcoal,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Log entries
                      if (_isLoading)
                        ...List.generate(4, (_) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _LogShimmer(),
                            ))
                      else if (_filtered.isEmpty)
                        _EmptyState(
                          hasFilter: _searchQuery.isNotEmpty ||
                              _activeCrop != 'All Crops',
                          onLogHarvest: () => Navigator.of(context)
                              .pushReplacementNamed(AppRoutes.cropListing),
                        )
                      else
                        ..._filtered.map((h) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _LogEntry(harvest: h),
                            )),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: FarmerTopBar(title: 'Harvest History', onBack: () => Navigator.of(context).pop(), profilePhotoUrl: null, onProfileTap: () {}, onNotificationTap: () => context.pushRoute(AppRoutes.farmerNotifications), onSettingsTap: null,),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar
// ─────────────────────────────────────────────────────────────────────────────


// ─────────────────────────────────────────────────────────────────────────────
// Search Bar
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: InputDecoration(
        hintText: 'Search harvest history...',
        hintStyle: GoogleFonts.inter(fontSize: 14, color: AppConstants.outline.withValues(alpha: 0.60)),
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
// Crop Filter Chips
// ─────────────────────────────────────────────────────────────────────────────

class _CropChips extends StatelessWidget {
  final List<String> options;
  final String active;
  final ValueChanged<String> onSelected;

  const _CropChips({
    required this.options,
    required this.active,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((crop) {
          final isActive = crop == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(crop),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppConstants.primaryContainer.withValues(alpha: 0.12)
                      : const Color(0xFFD5ECF8),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: isActive
                      ? Border.all(color: AppConstants.primaryContainer.withValues(alpha: 0.30))
                      : null,
                ),
                child: Text(crop,
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w500,
                        color: isActive
                            ? AppConstants.primaryContainer
                            : AppConstants.onSurfaceVariant)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Stats
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryStats extends StatelessWidget {
  final Map<String, double> stats;
  final bool isLoading;

  const _SummaryStats({required this.stats, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Total Harvest (30d)',
            value: isLoading ? '—' : _fmtYield(stats['total_yield'] ?? 0),
            unit: 'kg',
            valueColor: AppConstants.primaryGreen,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            label: 'Premium Yield',
            value: isLoading ? '—' : (stats['premium_percent'] ?? 0).toStringAsFixed(0),
            unit: '%',
            valueColor: AppConstants.amber,
          ),
        ),
      ],
    );
  }

  String _fmtYield(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color valueColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.valueColor,
  });

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
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 8,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value,
                      style: GoogleFonts.poppins(
                          fontSize: 24, fontWeight: FontWeight.w700, color: valueColor)),
                  const SizedBox(width: 4),
                  Text(unit,
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: AppConstants.onSurfaceVariant)),
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
// Log Entry
// ─────────────────────────────────────────────────────────────────────────────

class _LogEntry extends StatelessWidget {
  final HarvestModel harvest;
  const _LogEntry({required this.harvest});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(_cropIcon(harvest.cropCategory),
                    size: 26, color: AppConstants.primaryGreen),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(harvest.cropName,
                                  style: GoogleFonts.poppins(
                                      fontSize: 15, fontWeight: FontWeight.w500,
                                      color: AppConstants.onSurface)),
                              if (harvest.variety != null)
                                Text(harvest.variety!,
                                    style: GoogleFonts.inter(
                                        fontSize: 12, color: AppConstants.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        _GradeBadge(grade: harvest.qualityGrade ?? 'Grade A'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.scale_rounded,
                                size: 15, color: AppConstants.primaryGreen),
                            const SizedBox(width: 5),
                            Text(harvest.displayQty,
                                style: GoogleFonts.inter(
                                    fontSize: 13, fontWeight: FontWeight.w700,
                                    color: AppConstants.primaryGreen)),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 13, color: AppConstants.outline),
                            const SizedBox(width: 4),
                            Text(DateFormat('MMM d, yyyy').format(harvest.harvestDate),
                                style: GoogleFonts.inter(
                                    fontSize: 11, color: AppConstants.outline)),
                            const SizedBox(width: 10),
                            Icon(
                              harvest.isSynced
                                  ? Icons.cloud_done_rounded
                                  : Icons.sync_rounded,
                              size: 13,
                              color: harvest.isSynced
                                  ? AppConstants.successGreen
                                  : AppConstants.warningAmber,
                            ),
                            const SizedBox(width: 3),
                            Text(harvest.isSynced ? 'Synced' : 'Pending',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: harvest.isSynced
                                        ? AppConstants.successGreen
                                        : AppConstants.warningAmber)),
                          ],
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

  IconData _cropIcon(String category) {
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

class _GradeBadge extends StatelessWidget {
  final String grade;
  const _GradeBadge({required this.grade});

  @override
  Widget build(BuildContext context) {
    final isPremium = grade == 'Grade A';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isPremium
            ? AppConstants.secondaryContainer.withValues(alpha: 0.20)
            : const Color(0xFFCFE6F2).withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(grade,
          style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w500,
              color: isPremium ? AppConstants.amber : AppConstants.onSurfaceVariant)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasFilter;
  final VoidCallback onLogHarvest;

  const _EmptyState({required this.hasFilter, required this.onLogHarvest});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              color: const Color(0xFFDBF1FE),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.history_rounded,
                size: 40, color: AppConstants.outline.withValues(alpha: 0.60)),
          ),
          const SizedBox(height: 20),
          Text(hasFilter ? 'No Matching Harvests' : 'No Harvests Found',
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: AppConstants.onSurface)),
          const SizedBox(height: 8),
          Text(
            hasFilter
                ? 'Try a different search or crop filter.'
                : 'You haven\'t recorded any harvests for this period yet.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
          ),
          if (!hasFilter) ...[
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onLogHarvest,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                ),
              ),
              child: Text('Log New Harvest',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer
// ─────────────────────────────────────────────────────────────────────────────

class _LogShimmer extends StatefulWidget {
  @override
  State<_LogShimmer> createState() => _LogShimmerState();
}

class _LogShimmerState extends State<_LogShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _anim = Tween<double>(begin: -1, end: 2).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _block(double w, double h) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Container(
          width: w, height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              stops: [
                (_anim.value - 1).clamp(0.0, 1.0),
                _anim.value.clamp(0.0, 1.0),
                (_anim.value + 1).clamp(0.0, 1.0),
              ],
              colors: const [Color(0xFFE8E8E8), Color(0xFFF5F5F5), Color(0xFFE8E8E8)],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                _block(110, 14),
                const SizedBox(height: 8),
                _block(140, 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

