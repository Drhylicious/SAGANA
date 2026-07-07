import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/inventory_batch_model.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

class ManageInventoryScreen extends StatefulWidget {
  const ManageInventoryScreen({super.key});

  @override
  State<ManageInventoryScreen> createState() => _ManageInventoryScreenState();
}

class _ManageInventoryScreenState extends State<ManageInventoryScreen> {
  final _repo = InventoryRepository();
  final _searchController = TextEditingController();

  List<InventoryBatchModel> _allBatches = [];
  List<InventoryBatchModel> _filtered = [];
  Map<String, double> _summary = {'available': 0, 'reserved': 0, 'sold': 0};

  InventoryGradeFilter _gradeFilter = InventoryGradeFilter.all;
  bool _showSold = false;
  bool _isLoading = true;
  bool _isDeleting = false;
  bool _isOnline = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    AppEventService.instance.addListener(_onHarvestRecorded);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    AppEventService.instance.removeListener(_onHarvestRecorded);
    _searchController.dispose();
    super.dispose();
  }

  void _onHarvestRecorded() {
    if (mounted) _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchBatches(),
      _repo.fetchSummary(),
    ]);
    if (!mounted) return;
    setState(() {
      _allBatches = results[0] as List<InventoryBatchModel>;
      _summary = results[1] as Map<String, double>;
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

  void _setGradeFilter(InventoryGradeFilter f) {
    setState(() {
      _gradeFilter = f;
      _applyFilters();
    });
  }

  void _toggleShowSold() {
    setState(() {
      _showSold = !_showSold;
      _applyFilters();
    });
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    _filtered = _allBatches.where((b) {
      // Apply grade filter first
      if (!_gradeFilter.matches(b)) return false;
      
      // Apply sold filter: binary toggle
      // When _showSold is TRUE: show ONLY sold/withdrawn batches
      // When _showSold is FALSE: show ONLY available batches
      final isSold = b.isSoldOut || b.isWithdrawn;
      final shouldDisplay = _showSold ? isSold : !isSold;
      if (!shouldDisplay) return false;
      
      // Apply search filter
      if (q.isEmpty) return true;
      return b.cropName.toLowerCase().contains(q) ||
          b.batchNumber.toLowerCase().contains(q);
    }).toList();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _showBatchMenu(InventoryBatchModel batch) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _BatchActionSheet(
        batch: batch,
        onUpdateQuantity: () {
          Navigator.pop(context);
          _showUpdateQuantityDialog(batch);
        },
        onMarkAsSold: () {
          Navigator.pop(context);
          _confirmMarkAsSold(batch);
        },
        onViewHarvestRecord: () {
          Navigator.pop(context);
          // Navigates to harvest history filtered by this batch's crop
            context.goTab(AppRoutes.harvestHistory);
        },
        onDelete: () {
          Navigator.pop(context);
          _confirmDelete(batch);
        },
      ),
    );
  }

  void _showUpdateQuantityDialog(InventoryBatchModel batch) {
    final controller =
        TextEditingController(text: batch.availableKg.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text('Update Quantity',
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${batch.cropName} • Batch #${batch.batchNumber}',
                style: GoogleFonts.inter(fontSize: 12, color: AppConstants.outline)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Available Quantity (kg)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Total batch quantity: ${batch.quantityKg.toStringAsFixed(0)} kg',
                style: GoogleFonts.inter(fontSize: 11, color: AppConstants.outline)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: AppConstants.outline)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newQty = double.tryParse(controller.text.trim());
              if (newQty == null || newQty < 0 || newQty > batch.quantityKg) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Enter a value between 0 and ${batch.quantityKg.toStringAsFixed(0)} kg')),
                );
                return;
              }
              Navigator.pop(context);
              await _repo.updateQuantity(batch.id, newQty);
              _loadData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            child: Text('Save', style: GoogleFonts.poppins(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  void _confirmMarkAsSold(InventoryBatchModel batch) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text('Mark as Sold?',
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          'This will mark the remaining ${batch.availableKg.toStringAsFixed(0)} kg of ${batch.cropName} (Batch #${batch.batchNumber}) as sold outside the marketplace.',
          style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: AppConstants.outline)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _repo.markAsSold(batch.id);
              _loadData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.successGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            child: Text('Confirm', style: GoogleFonts.poppins(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(InventoryBatchModel batch) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text('Delete Batch?',
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          'This will permanently delete Batch #${batch.batchNumber}. This action cannot be undone.',
          style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: AppConstants.outline)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (!mounted) return;
              setState(() => _isDeleting = true);
              try {
                await _repo.deleteBatch(batch.id);
                if (!mounted) return;
                await _loadData();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Failed to delete batch #${batch.batchNumber}. Please try again.',
                      style: GoogleFonts.inter(fontSize: 13),
                    ),
                    backgroundColor: AppConstants.errorRed,
                    duration: const Duration(seconds: 3),
                  ),
                );
              } finally {
                if (mounted) {
                  setState(() => _isDeleting = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.errorRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            child: Text('Delete', style: GoogleFonts.poppins(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  void _handleBatchAction(InventoryBatchModel batch) {
    if (batch.isAvailable) {
      context.pushRoute(AppRoutes.createListing, extra: batch);
    } else if (batch.isReserved) {
      context.goTab(AppRoutes.myListings);
    } else {
      context.goTab(AppRoutes.harvestHistory);
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
              const SizedBox(height: 72),
              if (!_isOnline) const _OfflineBanner(),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    children: [
                      // Summary metrics
                      _SummaryMetrics(summary: _summary, isLoading: _isLoading),
                      const SizedBox(height: 20),

                      // Search bar
                      _SearchBar(controller: _searchController),
                      const SizedBox(height: 12),

                      // Filter row
                      _FilterRow(
                        gradeFilter: _gradeFilter,
                        showSold: _showSold,
                        onGradeChanged: _setGradeFilter,
                        onToggleShowSold: _toggleShowSold,
                      ),
                      const SizedBox(height: 20),

                      // Section title
                      Text(
                        'Inventory Batches',
                        style: GoogleFonts.poppins(
                          fontSize: 18, fontWeight: FontWeight.w700,
                          color: AppConstants.charcoal,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Batch list
                      if (_isLoading)
                        ...List.generate(3, (_) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _BatchShimmer(),
                            ))
                      else if (_filtered.isEmpty)
                        _EmptyState(
                          hasFilter: _searchQuery.isNotEmpty ||
                              _gradeFilter != InventoryGradeFilter.all ||
                              _showSold,  // Show filtered message when "Show Sold" is active
                          onRecordHarvest: () => context.goTab(AppRoutes.cropListing),
                        )
                      else
                        ..._filtered.map((b) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _BatchCard(
                                batch: b,
                                onMenuTap: () => _showBatchMenu(b),
                                onActionTap: () => _handleBatchAction(b),
                              ),
                            )),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: FarmerTopBar(title: 'Manage Inventory', onBack: () => Navigator.of(context).pop(), profilePhotoUrl: null, onProfileTap: () {}, onNotificationTap: () => context.pushRoute(AppRoutes.farmerNotifications), onSettingsTap: null,),
          ),
          // Deleting overlay
          if (_isDeleting)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black12,
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppConstants.primaryGreen,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offline Banner
// ─────────────────────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: const Color(0xFFFFDAD6),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: Color(0xFF93000A)),
          const SizedBox(width: 8),
          Text('Offline: Data may be outdated',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF93000A))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Metrics
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryMetrics extends StatelessWidget {
  final Map<String, double> summary;
  final bool isLoading;

  const _SummaryMetrics({required this.summary, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            value: isLoading ? '—' : _fmt(summary['available'] ?? 0),
            label: 'Available',
            valueColor: AppConstants.primaryGreen,
            dotColor: AppConstants.successGreen,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(
            value: isLoading ? '—' : _fmt(summary['reserved'] ?? 0),
            label: 'Reserved',
            valueColor: AppConstants.amber,
            dotColor: AppConstants.warningAmber,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(
            value: isLoading ? '—' : _fmt(summary['sold'] ?? 0),
            label: 'Sold',
            valueColor: AppConstants.successGreen,
            dotColor: AppConstants.primaryGreen,
          ),
        ),
      ],
    );
  }

  String _fmt(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _MetricCard extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;
  final Color dotColor;

  const _MetricCard({
    required this.value,
    required this.label,
    required this.valueColor,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 12,
              ),
            ],
          ),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Text(value,
                      style: GoogleFonts.poppins(
                          fontSize: 20, fontWeight: FontWeight.w700,
                          color: valueColor)),
                  Positioned(
                    top: -2, right: -8,
                    child: Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(label.toUpperCase(),
                  style: GoogleFonts.inter(
                      fontSize: 9, color: AppConstants.outline, letterSpacing: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}

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
        hintText: 'Search batch or crop...',
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
// Filter Row
// ─────────────────────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final InventoryGradeFilter gradeFilter;
  final bool showSold;
  final ValueChanged<InventoryGradeFilter> onGradeChanged;
  final VoidCallback onToggleShowSold;

  const _FilterRow({
    required this.gradeFilter,
    required this.showSold,
    required this.onGradeChanged,
    required this.onToggleShowSold,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Show Sold toggle
          GestureDetector(
            onTap: onToggleShowSold,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFD5ECF8),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Show Sold',
                      style: GoogleFonts.poppins(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: AppConstants.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 32, height: 18,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: showSold
                          ? AppConstants.primaryGreen
                          : AppConstants.outline.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 150),
                      alignment: showSold ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        width: 14, height: 14,
                        decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Grade chips
          ...InventoryGradeFilter.values.map((f) {
            final isActive = f == gradeFilter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onGradeChanged(f),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppConstants.primaryGreen.withValues(alpha: 0.10)
                        : const Color(0xFFD5ECF8),
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    border: isActive
                        ? Border.all(color: AppConstants.primaryGreen.withValues(alpha: 0.30))
                        : null,
                  ),
                  child: Text(f.label,
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w500,
                          color: isActive
                              ? AppConstants.primaryGreen
                              : AppConstants.onSurfaceVariant)),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch Card
// ─────────────────────────────────────────────────────────────────────────────

class _BatchCard extends StatelessWidget {
  final InventoryBatchModel batch;
  final VoidCallback onMenuTap;
  final VoidCallback onActionTap;

  const _BatchCard({
    required this.batch,
    required this.onMenuTap,
    required this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusInfo = _statusInfo(batch.status);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (batch.isSoldOut ? const Color(0xFFF8FAFC) : Colors.white)
                .withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 16, offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: statusInfo.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: statusInfo.border),
                    ),
                    child: Center(
                      child: Text(_emojiForCrop(batch.cropName),
                          style: const TextStyle(fontSize: 28)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(batch.cropName,
                                style: GoogleFonts.poppins(
                                    fontSize: 15, fontWeight: FontWeight.w700,
                                    color: AppConstants.charcoal)),
                            _StatusBadge(status: batch.status),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('Batch: #${batch.batchNumber} • ${batch.qualityGrade}',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: AppConstants.outline)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onMenuTap,
                    icon: const Icon(Icons.more_vert_rounded,
                        size: 20, color: AppConstants.outline),
                    style: IconButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Stock progress
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Stock: ${batch.availableKg.toStringAsFixed(0)}kg of ${batch.quantityKg.toStringAsFixed(0)}kg',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppConstants.outline),
                  ),
                  Text('${(batch.stockPercent * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: statusInfo.accent)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: batch.stockPercent,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFD5ECF8),
                  valueColor: AlwaysStoppedAnimation<Color>(statusInfo.accent),
                ),
              ),
              const SizedBox(height: 12),

              // Footer
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppConstants.outline.withValues(alpha: 0.08)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('HARVEST DATE',
                            style: GoogleFonts.inter(
                                fontSize: 9, color: AppConstants.outline, letterSpacing: 0.5)),
                        Text(
                          batch.harvestDate != null
                              ? DateFormat('MMM d, yyyy').format(batch.harvestDate!)
                              : DateFormat('MMM d, yyyy').format(batch.createdAt),
                          style: GoogleFonts.inter(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: AppConstants.onSurface),
                        ),
                      ],
                    ),
                    _ActionButton(status: batch.status, onTap: onActionTap),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _emojiForCrop(String cropName) {
    final lower = cropName.toLowerCase();
    if (lower.contains('banana')) return '🍌';
    if (lower.contains('peanut') || lower.contains('mani')) return '🥜';
    if (lower.contains('copra') || lower.contains('coconut')) return '🥥';
    if (lower.contains('rice') || lower.contains('palay')) return '🌾';
    if (lower.contains('corn') || lower.contains('mais')) return '🌽';
    if (lower.contains('ginger') || lower.contains('luya')) return '🫚';
    if (lower.contains('mango') || lower.contains('mangga')) return '🥭';
    if (lower.contains('papaya')) return '🍈';
    if (lower.contains('cassava') || lower.contains('kamoteng kahoy')) return '🍠';
    if (lower.contains('kamote')) return '🍠';
    if (lower.contains('garlic') || lower.contains('bawang')) return '🧄';
    if (lower.contains('onion') || lower.contains('sibuyas')) return '🧅';
    return '📦';
  }

  _StatusInfo _statusInfo(String status) {
    switch (status) {
      case 'available':
        return _StatusInfo(
          bg: const Color(0xFFFFF7E0), border: const Color(0xFFFFE9B3),
          accent: AppConstants.successGreen,
        );
      case 'low_stock':
        return _StatusInfo(
          bg: const Color(0xFFFFF3E0), border: const Color(0xFFFFE0B2),
          accent: AppConstants.warningAmber,
        );
      case 'reserved':
        return _StatusInfo(
          bg: const Color(0xFFFFF3E0), border: const Color(0xFFFFE0B2),
          accent: AppConstants.warningAmber,
        );
      case 'sold_out':
        return _StatusInfo(
          bg: const Color(0xFFF1F5F9), border: const Color(0xFFE2E8F0),
          accent: AppConstants.outline,
        );
      default:
        return _StatusInfo(
          bg: const Color(0xFFF1F5F9), border: const Color(0xFFE2E8F0),
          accent: AppConstants.outline,
        );
    }
  }
}

class _StatusInfo {
  final Color bg;
  final Color border;
  final Color accent;
  _StatusInfo({required this.bg, required this.border, required this.accent});
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    switch (status) {
      case 'available':
        label = 'AVAILABLE'; color = AppConstants.successGreen; break;
      case 'low_stock':
        label = 'LOW STOCK'; color = AppConstants.warningAmber; break;
      case 'reserved':
        label = 'RESERVED'; color = AppConstants.warningAmber; break;
      case 'sold_out':
        label = 'SOLD OUT'; color = AppConstants.outline; break;
      case 'withdrawn':
        label = 'WITHDRAWN'; color = AppConstants.errorRed; break;
      default:
        label = status.toUpperCase(); color = AppConstants.outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: GoogleFonts.inter(
              fontSize: 9, fontWeight: FontWeight.w700,
              color: Colors.white, letterSpacing: 0.5)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String status;
  final VoidCallback onTap;

  const _ActionButton({required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    String label;
    bool isOutlined = false;
    switch (status) {
      case 'available':
      case 'low_stock':
        label = 'Create Listing'; break;
      case 'reserved':
        label = 'View Order'; break;
      default:
        label = 'View History'; isOutlined = true;
    }

    if (isOutlined) {
      return IntrinsicWidth(
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppConstants.outline,
            side: BorderSide(color: AppConstants.outline.withValues(alpha: 0.30)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
          ),
          child: Text(label, style: GoogleFonts.poppins(fontSize: 12)),
        ),
      );
    }

    return IntrinsicWidth(
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          elevation: 0,
        ),
        child: Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch Action Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _BatchActionSheet extends StatelessWidget {
  final InventoryBatchModel batch;
  final VoidCallback onUpdateQuantity;
  final VoidCallback onMarkAsSold;
  final VoidCallback onViewHarvestRecord;
  final VoidCallback onDelete;

  const _BatchActionSheet({
    required this.batch,
    required this.onUpdateQuantity,
    required this.onMarkAsSold,
    required this.onViewHarvestRecord,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusXl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppConstants.outline.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('${batch.cropName} — Batch #${batch.batchNumber}',
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
          const Divider(height: 20),
          if (!batch.isSoldOut) ...[
            _MenuOption(icon: Icons.edit_outlined, label: 'Update Quantity', onTap: onUpdateQuantity),
            _MenuOption(icon: Icons.check_circle_outline_rounded, label: 'Mark as Sold', onTap: onMarkAsSold),
          ],
          _MenuOption(icon: Icons.receipt_long_outlined, label: 'View Harvest Record', onTap: onViewHarvestRecord),
          _MenuOption(icon: Icons.delete_outline_rounded, label: 'Delete Batch', color: AppConstants.errorRed, onTap: onDelete),
        ],
      ),
    );
  }
}

class _MenuOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _MenuOption({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      tileColor: Colors.transparent,
      leading: Icon(icon, color: color ?? AppConstants.onSurfaceVariant, size: 22),
      title: Text(label,
          style: GoogleFonts.inter(fontSize: 14, color: color ?? AppConstants.onSurface)),
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasFilter;
  final VoidCallback onRecordHarvest;

  const _EmptyState({required this.hasFilter, required this.onRecordHarvest});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFDBF1FE),
              shape: BoxShape.circle,
            ),
            child: const Center(child: Text('📦', style: TextStyle(fontSize: 36))),
          ),
          const SizedBox(height: 16),
          Text(hasFilter ? 'No batches match this filter' : 'No inventory yet',
              style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w700,
                  color: AppConstants.charcoal)),
          const SizedBox(height: 6),
          Text(
            hasFilter
                ? 'Try a different search or filter'
                : 'Start by recording your first harvest.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: AppConstants.outline),
          ),
          const SizedBox(height: 20),
          if (!hasFilter)
            ElevatedButton(
              onPressed: onRecordHarvest,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                ),
              ),
              child: Text('Go to Record Harvest',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer
// ─────────────────────────────────────────────────────────────────────────────

class _BatchShimmer extends StatefulWidget {
  @override
  State<_BatchShimmer> createState() => _BatchShimmerState();
}

class _BatchShimmerState extends State<_BatchShimmer>
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
            borderRadius: BorderRadius.circular(8),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _block(56, 56), const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_block(120, 14), const SizedBox(height: 6), _block(90, 11)],
            )),
          ]),
          const SizedBox(height: 12),
          _block(double.infinity, 8),
        ],
      ),
    );
  }
}

