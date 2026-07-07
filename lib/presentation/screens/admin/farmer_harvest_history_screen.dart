import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/harvest_model.dart';
import '../../../data/repositories/harvest_repository.dart';

class AdminFarmerHarvestHistoryScreen extends StatefulWidget {
  const AdminFarmerHarvestHistoryScreen({super.key, required this.farmerId});

  final String farmerId;

  @override
  State<AdminFarmerHarvestHistoryScreen> createState() =>
      _AdminFarmerHarvestHistoryScreenState();
}

class _AdminFarmerHarvestHistoryScreenState
    extends State<AdminFarmerHarvestHistoryScreen> {
  final HarvestRepository _repo = HarvestRepository();
  final TextEditingController _searchController = TextEditingController();

  List<HarvestModel> _allHarvests = [];
  List<HarvestModel> _filteredHarvests = [];
  List<String> _cropOptions = const ['All Crops'];
  Map<String, double> _stats = const {'total_yield': 0, 'premium_percent': 0};

  String _activeCrop = 'All Crops';
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _searchController.addListener(_onSearchChanged);
    _loadData();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchAllHarvestsForFarmer(widget.farmerId),
      _repo.fetchHistoryStatsForFarmer(widget.farmerId),
    ]);

    if (!mounted) return;

    final harvests = results[0] as List<HarvestModel>;
    final cropOptions = harvests.map((h) => h.cropName).toSet().toList()..sort();

    setState(() {
      _allHarvests = harvests;
      _stats = results[1] as Map<String, double>;
      _cropOptions = ['All Crops', ...cropOptions];
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
    final query = _searchQuery.trim().toLowerCase();
    _filteredHarvests = _allHarvests.where((harvest) {
      if (_activeCrop != 'All Crops' && harvest.cropName != _activeCrop) {
        return false;
      }
      if (query.isEmpty) return true;
      return harvest.cropName.toLowerCase().contains(query) ||
          (harvest.variety?.toLowerCase().contains(query) ?? false) ||
          (harvest.batchNumber?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
                      _AdminBanner(farmerId: widget.farmerId, cs: cs),
                      const SizedBox(height: 16),
                      _SearchBar(controller: _searchController),
                      const SizedBox(height: 12),
                      _CropChips(
                        options: _cropOptions,
                        active: _activeCrop,
                        onSelected: _setCropFilter,
                      ),
                      const SizedBox(height: 20),
                      _SummaryStats(stats: _stats, isLoading: _isLoading),
                      const SizedBox(height: 24),
                      Text(
                        'Harvest History',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.charcoal,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_isLoading)
                        ...List.generate(
                          4,
                          (_) => const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: _LogShimmer(),
                          ),
                        )
                      else if (_filteredHarvests.isEmpty)
                        _EmptyState(
                          hasFilter: _searchQuery.isNotEmpty ||
                              _activeCrop != 'All Crops',
                        )
                      else
                        ..._filteredHarvests.map(
                          (harvest) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _LogEntry(harvest: harvest),
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
            child: _TopBar(
              onBack: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppConstants.charcoal,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Farmer Harvest History',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppConstants.charcoal,
                          ),
                        ),
                        Text(
                          'Admin monitoring view',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppConstants.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(
                      'ADMIN',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.primaryGreen,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminBanner extends StatelessWidget {
  const _AdminBanner({required this.farmerId, required this.cs});

  final String farmerId;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.admin_panel_settings_rounded,
                    color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin View Only',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.charcoal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Monitoring harvest records for farmer ID: $farmerId',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppConstants.onSurfaceVariant,
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

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: InputDecoration(
        hintText: 'Search harvest history...',
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppConstants.outline.withValues(alpha: 0.60),
        ),
        prefixIcon:
            const Icon(Icons.search_rounded, color: AppConstants.outline),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide:
              BorderSide(color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide:
              BorderSide(color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(color: AppConstants.primaryGreen),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _CropChips extends StatelessWidget {
  const _CropChips({
    required this.options,
    required this.active,
    required this.onSelected,
  });

  final List<String> options;
  final String active;
  final ValueChanged<String> onSelected;

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppConstants.primaryContainer.withValues(alpha: 0.12)
                      : const Color(0xFFD5ECF8),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: isActive
                      ? Border.all(
                          color:
                              AppConstants.primaryContainer.withValues(alpha: 0.30),
                        )
                      : null,
                ),
                child: Text(
                  crop,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? AppConstants.primaryContainer
                        : AppConstants.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SummaryStats extends StatelessWidget {
  const _SummaryStats({required this.stats, required this.isLoading});

  final Map<String, double> stats;
  final bool isLoading;

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
            value: isLoading
                ? '—'
                : (stats['premium_percent'] ?? 0).toStringAsFixed(0),
            unit: '%',
            valueColor: AppConstants.amber,
          ),
        ),
      ],
    );
  }

  String _fmtYield(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.valueColor,
  });

  final String label;
  final String value;
  final String unit;
  final Color valueColor;

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
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppConstants.onSurfaceVariant)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: valueColor,
                    ),
                  ),
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

class _LogEntry extends StatelessWidget {
  const _LogEntry({required this.harvest});

  final HarvestModel harvest;

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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _cropIcon(harvest.cropCategory),
                  size: 26,
                  color: AppConstants.primaryGreen,
                ),
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
                              Text(
                                harvest.cropName,
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: AppConstants.onSurface,
                                ),
                              ),
                              if (harvest.variety != null)
                                Text(
                                  harvest.variety!,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppConstants.onSurfaceVariant,
                                  ),
                                ),
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
                            const Icon(
                              Icons.scale_rounded,
                              size: 15,
                              color: AppConstants.primaryGreen,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              harvest.displayQty,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppConstants.primaryGreen,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 13,
                              color: AppConstants.outline,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('MMM d, yyyy').format(harvest.harvestDate),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppConstants.outline,
                              ),
                            ),
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
                            Text(
                              harvest.isSynced ? 'Synced' : 'Pending',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: harvest.isSynced
                                    ? AppConstants.successGreen
                                    : AppConstants.warningAmber,
                              ),
                            ),
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

class _GradeBadge extends StatelessWidget {
  const _GradeBadge({required this.grade});

  final String grade;

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
      child: Text(
        grade,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: isPremium ? AppConstants.amber : AppConstants.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilter});

  final bool hasFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: Color(0xFFDBF1FE),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.history_rounded,
              size: 40,
              color: AppConstants.outline.withValues(alpha: 0.60),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            hasFilter ? 'No Matching Harvests' : 'No Harvest Records',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppConstants.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilter
                ? 'Try a different search or crop filter.'
                : 'No harvest entries were found for this farmer.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogShimmer extends StatefulWidget {
  const _LogShimmer();

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
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _block(double width, double height) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Container(
          width: width,
          height: height,
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