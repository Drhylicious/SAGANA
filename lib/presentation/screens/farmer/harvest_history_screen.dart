import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/harvest_model.dart';
import '../../../data/repositories/harvest_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/harvest_log_widgets.dart';

class HarvestHistoryScreen extends StatefulWidget {
  final String? initialCropFilter;
  const HarvestHistoryScreen({super.key, this.initialCropFilter});

  @override
  State<HarvestHistoryScreen> createState() => _HarvestHistoryScreenState();
}

class _HarvestHistoryScreenState extends State<HarvestHistoryScreen> {
  final _repo = HarvestRepository();
  final _searchController = TextEditingController();

  List<HarvestModel> _allHarvests = [];
  List<HarvestModel> _filtered = [];
  List<String> _cropOptions = ['All Crops'];
  Map<String, double> _stats = {'total_yield': 0, 'synced_percent': 100};

  String _activeCrop = 'All Crops';
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    if (widget.initialCropFilter != null) {
      _activeCrop = widget.initialCropFilter!;
    }
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
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
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(message: "You're offline — your full harvest history may not be up to date."),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 72),
                    Expanded(
                      child: RefreshIndicator(
                        color: AppConstants.primaryGreen,
                        onRefresh: _loadData,
                        child: ListView(
                          padding:
                              const EdgeInsets.fromLTRB(20, 16, 20, 100),
                          children: [
                            // Search
                            _SearchBar(controller: _searchController),
                            const SizedBox(height: 12),

                            // Crop filter chips
                            HarvestCropChips(
                              options: _cropOptions,
                              active: _activeCrop,
                              onSelected: _setCropFilter,
                            ),
                            const SizedBox(height: 20),

                            // Summary stats
                            HarvestSummaryStats(
                                stats: _stats, isLoading: _isLoading),
                            const SizedBox(height: 24),

                            // Log entries
                            if (_isLoading)
                              ...List.generate(4, (_) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: _LogShimmer(),
                                  ))
                            else if (_filtered.isEmpty)
                              _EmptyState(
                                hasFilter: _searchQuery.isNotEmpty ||
                                  _activeCrop != 'All Crops',
                              )
                            else
                              ..._filtered.map((h) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: HarvestLogEntry(harvest: h),
                                  )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: FarmerTopBar(
                    title: 'Harvest History',
                    onBack: () => Navigator.of(context).pop(),
                    hideProfileAvatar: true,
                    onProfileTap: () {},
                    onNotificationTap: () {},
                    showNotificationButton: false,
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
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasFilter;

  const _EmptyState({required this.hasFilter});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            width: 96, height: 96,
            decoration: const BoxDecoration(
              color: Color(0xFFDBF1FE),
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
            Text(
              'You\'re all caught up.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppConstants.onSurfaceVariant,
              ),
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