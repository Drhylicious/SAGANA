import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/inventory_batch_model.dart';
import '../../../data/repositories/cooperative_offer_repository.dart';
import '../../../data/repositories/informal_sale_repository.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/management_modal.dart';

class ManageInventoryScreen extends StatefulWidget {
  const ManageInventoryScreen({super.key});

  @override
  State<ManageInventoryScreen> createState() => _ManageInventoryScreenState();
}

class _ManageInventoryScreenState extends State<ManageInventoryScreen> {
  final _repo = InventoryRepository();
  final _cropRepo = CropRepository();
  final _offerRepo = CooperativeOfferRepository();
  final _searchController = TextEditingController();

  List<InventoryBatchModel> _allBatches = [];
  List<InventoryBatchModel> _filtered = [];
  Map<String, double> _summary = {'available': 0, 'reserved': 0, 'sold': 0};
  bool _hasCrops = true; // assume true until loaded, avoids an empty-state flash
  Set<String> _pendingOfferBatchIds = {};

  bool _showSold = false;
  bool _isLoading = true;
  bool _isDeleting = false;
  bool _isOnline = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    AppEventService.instance.addListener(_onHarvestRecorded);
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
      _cropRepo.fetchCrops(),
      _offerRepo.fetchBatchIdsWithPendingOffers(),
    ]);
    if (!mounted) return;
    setState(() {
      _allBatches = results[0] as List<InventoryBatchModel>;
      _summary = results[1] as Map<String, double>;
      _hasCrops = (results[2] as List<FarmerCropModel>).isNotEmpty;
      _pendingOfferBatchIds = results[3] as Set<String>;
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

  void _toggleShowSold() {
    setState(() {
      _showSold = !_showSold;
      _applyFilters();
    });
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    _filtered = _allBatches.where((b) {
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
    showManagementModal(
      context: context,
      builder: (_) => _BatchActionSheet(
        batch: batch,
        onUpdateQuantity: () {
          Navigator.pop(context);
          _showUpdateQuantityDialog(batch);
        },
        onViewHarvestRecord: () {
          Navigator.pop(context);
          context.pushRoute(AppRoutes.harvestHistory, extra: batch.cropName);
        },
        onDelete: () {
          Navigator.pop(context);
          _confirmDelete(batch);
        },
      ),
    );
  }

  void _showUpdateQuantityDialog(InventoryBatchModel batch) {
    final controller = TextEditingController(
      text: batch.availableKg.toStringAsFixed(0),
    );
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text(
          'Update Quantity',
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${batch.cropName} • Batch #${batch.batchNumber}',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppConstants.outline,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Available Quantity (kg)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Total batch quantity: ${batch.quantityKg.toStringAsFixed(0)} kg',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppConstants.outline,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: AppConstants.outline),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final newQty = double.tryParse(controller.text.trim());
              if (newQty == null || newQty < 0 || newQty > batch.quantityKg) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Enter a value between 0 and ${batch.quantityKg.toStringAsFixed(0)} kg',
                    ),
                  ),
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

  void _confirmDelete(InventoryBatchModel batch) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text(
          'Delete Batch?',
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will permanently delete Batch #${batch.batchNumber}. This action cannot be undone.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppConstants.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: AppConstants.outline),
            ),
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

  Future<void> _handleBatchAction(InventoryBatchModel batch) async {
    if (!batch.isAvailable) {
      // Reserved batches now branch on which disposal path actually
      // claimed them, rather than assuming 'reserved' always means a
      // marketplace listing — a batch offered to the cooperative and
      // awaiting confirmation has nothing relevant on My Listings.
      if (batch.isReserved && _pendingOfferBatchIds.contains(batch.id)) {
        _showPendingOfferStatus(batch);
      } else if (batch.isReserved) {
        context.goTab(AppRoutes.myListings);
      } else {
        context.pushRoute(AppRoutes.harvestHistory, extra: batch.cropName);
      }
      return;
    }

    final action = await showDisposalActionSheet(
      context,
      cropName: batch.cropName,
      availableKg: batch.availableKg,
      isCoopEligible: batch.isCoopEligible,
    );
    if (action == null || !mounted) return;

    switch (action) {
      case DisposalAction.marketplace:
        final result = await context.pushRoute(AppRoutes.createListing, extra: batch);
        if (result == true) _loadData();
        break;
      case DisposalAction.cooperative:
        final result = await showOfferToCooperativeDialog(context, batch: batch);
        if (result == true) _loadData();
        break;
      case DisposalAction.informal:
        final result = await showRecordInformalSaleDialog(context, batch: batch);
        if (result == true) _loadData();
        break;
    }
  }

  void _showPendingOfferStatus(InventoryBatchModel batch) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusXl)),
        title: Row(children: [
          const Icon(Icons.groups_outlined, color: AppConstants.primaryGreen),
          const SizedBox(width: 10),
          Text('Offered to Cooperative', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          '${batch.cropName} • Batch #${batch.batchNumber} has been offered to SP3 and is awaiting cooperative confirmation. '
          'SP3 will confirm the final weighed quantity and price at pickup.',
          style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it', style: GoogleFonts.poppins(color: AppConstants.primaryGreen)),
          ),
        ],
      ),
    );
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
              if (!_isOnline) const OfflineBanner(),
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
                        showSold: _showSold,
                        onToggleShowSold: _toggleShowSold,
                      ),
                      const SizedBox(height: 20),

                      // Section title
                      Text(
                        'Inventory Batches',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.charcoal,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Batch list
                      if (_isLoading)
                        ...List.generate(
                          3,
                          (_) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _BatchShimmer(),
                          ),
                        )
                      else if (_filtered.isEmpty)
                        _InventoryEmptyState(
                          hasCrops: _hasCrops,
                          hasFilter: _searchQuery.isNotEmpty || _showSold,
                          onGoToMyCrops: () =>
                              context.pushRoute(AppRoutes.cropListing),
                          onRecordHarvest: () =>
                              context.pushRoute(AppRoutes.selectCropForHarvest),
                        )
                      else
                        ..._filtered.map(
                          (b) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _BatchCard(
                              batch: b,
                              hasPendingOffer: _pendingOfferBatchIds.contains(b.id),
                              onMenuTap: () => _showBatchMenu(b),
                              onActionTap: () => _handleBatchAction(b),
                            ),
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
            child: FarmerTopBar(
              title: 'Manage Inventory',
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
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

  String _fmt(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
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
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: valueColor,
                    ),
                  ),
                  Positioned(
                    top: -2,
                    right: -8,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 9,
                  color: AppConstants.outline,
                  letterSpacing: 0.8,
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
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppConstants.outline.withValues(alpha: 0.60),
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppConstants.outline,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: AppConstants.outline.withValues(alpha: 0.20),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: AppConstants.outline.withValues(alpha: 0.20),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(color: AppConstants.primaryGreen),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter Row
// ─────────────────────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final bool showSold;
  final VoidCallback onToggleShowSold;

  const _FilterRow({
    required this.showSold,
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
                  Text(
                    'Show Sold',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 32,
                    height: 18,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: showSold
                          ? AppConstants.primaryGreen
                          : AppConstants.outline.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 150),
                      alignment: showSold
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
  final bool hasPendingOffer;
  final VoidCallback onMenuTap;
  final VoidCallback onActionTap;

  const _BatchCard({
    required this.batch,
    this.hasPendingOffer = false,
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
                blurRadius: 16,
                offset: const Offset(0, 4),
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
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: statusInfo.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: statusInfo.border),
                    ),
                    child: Center(
                      child: Text(
                        _emojiForCrop(batch.cropName),
                        style: const TextStyle(fontSize: 28),
                      ),
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
                            Text(
                              batch.cropName,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppConstants.charcoal,
                              ),
                            ),
                            _StatusBadge(status: batch.status),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Batch: #${batch.batchNumber}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onMenuTap,
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: AppConstants.outline,
                    ),
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
                      fontSize: 12,
                      color: AppConstants.outline,
                    ),
                  ),
                  Text(
                    '${(batch.stockPercent * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: statusInfo.accent,
                    ),
                  ),
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
                    top: BorderSide(
                      color: AppConstants.outline.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HARVEST DATE',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            color: AppConstants.outline,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          batch.harvestDate != null
                              ? DateFormat(
                                  'MMM d, yyyy',
                                ).format(batch.harvestDate!)
                              : DateFormat(
                                  'MMM d, yyyy',
                                ).format(batch.createdAt),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppConstants.onSurface,
                          ),
                        ),
                      ],
                    ),
                    _ActionButton(status: batch.status, hasPendingOffer: hasPendingOffer, onTap: onActionTap),
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
    if (lower.contains('cassava') || lower.contains('kamoteng kahoy')) {
      return '🍠';
    }
    if (lower.contains('kamote')) return '🍠';
    if (lower.contains('garlic') || lower.contains('bawang')) return '🧄';
    if (lower.contains('onion') || lower.contains('sibuyas')) return '🧅';
    return '📦';
  }

  _StatusInfo _statusInfo(String status) {
    switch (status) {
      case 'available':
        return _StatusInfo(
          bg: const Color(0xFFFFF7E0),
          border: const Color(0xFFFFE9B3),
          accent: AppConstants.successGreen,
        );
      case 'low_stock':
        return _StatusInfo(
          bg: const Color(0xFFFFF3E0),
          border: const Color(0xFFFFE0B2),
          accent: AppConstants.warningAmber,
        );
      case 'reserved':
        return _StatusInfo(
          bg: const Color(0xFFFFF3E0),
          border: const Color(0xFFFFE0B2),
          accent: AppConstants.warningAmber,
        );
      case 'sold_out':
        return _StatusInfo(
          bg: const Color(0xFFF1F5F9),
          border: const Color(0xFFE2E8F0),
          accent: AppConstants.outline,
        );
      default:
        return _StatusInfo(
          bg: const Color(0xFFF1F5F9),
          border: const Color(0xFFE2E8F0),
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
        label = 'AVAILABLE';
        color = AppConstants.successGreen;
        break;
      case 'low_stock':
        label = 'LOW STOCK';
        color = AppConstants.warningAmber;
        break;
      case 'reserved':
        label = 'RESERVED';
        color = AppConstants.warningAmber;
        break;
      case 'sold_out':
        label = 'SOLD OUT';
        color = AppConstants.outline;
        break;
      case 'withdrawn':
        label = 'WITHDRAWN';
        color = AppConstants.errorRed;
        break;
      default:
        label = status.toUpperCase();
        color = AppConstants.outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String status;
  final bool hasPendingOffer;
  final VoidCallback onTap;

  const _ActionButton({required this.status, this.hasPendingOffer = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    String label;
    bool isOutlined = false;
    switch (status) {
      case 'available':
      case 'low_stock':
        label = 'Create Listing';
        break;
      case 'reserved':
        label = hasPendingOffer ? 'Offer Status' : 'View Order';
        break;
      default:
        label = 'View History';
        isOutlined = true;
    }

    if (isOutlined) {
      return IntrinsicWidth(
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppConstants.outline,
            side: BorderSide(
              color: AppConstants.outline.withValues(alpha: 0.30),
            ),
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
        child: Text(
          label,
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
        ),
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
  final VoidCallback onViewHarvestRecord;
  final VoidCallback onDelete;

  const _BatchActionSheet({
    required this.batch,
    required this.onUpdateQuantity,
    required this.onViewHarvestRecord,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ManagementModalShell(
      title: '${batch.cropName} — Batch #${batch.batchNumber}',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!batch.isSoldOut)
            _MenuOption(
              icon: Icons.edit_outlined,
              label: 'Update Quantity',
              onTap: onUpdateQuantity,
            ),
          _MenuOption(
            icon: Icons.receipt_long_outlined,
            label: 'View Harvest Record',
            onTap: onViewHarvestRecord,
          ),
          _MenuOption(
            icon: Icons.delete_outline_rounded,
            label: 'Delete Batch',
            color: AppConstants.errorRed,
            onTap: onDelete,
          ),
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
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        tileColor: Colors.transparent,
        leading: Icon(
          icon,
          color: color ?? AppConstants.onSurfaceVariant,
          size: 22,
        ),
        title: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: color ?? AppConstants.onSurface,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _InventoryEmptyState extends StatelessWidget {
  final bool hasCrops;
  final bool hasFilter;
  final VoidCallback onGoToMyCrops;
  final VoidCallback onRecordHarvest;

  const _InventoryEmptyState({
    required this.hasCrops,
    required this.hasFilter,
    required this.onGoToMyCrops,
    required this.onRecordHarvest,
  });

  @override
  Widget build(BuildContext context) {
    // Filtered-to-empty takes priority over the two onboarding cases —
    // a farmer who filtered their own real inventory to nothing isn't
    // missing crops or harvests, they just need to adjust the filter.
    if (hasFilter) {
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
                Icons.filter_alt_off_rounded,
                size: 40,
                color: AppConstants.outline.withValues(alpha: 0.60),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Matching Batches',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppConstants.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search or adjust your filters.',
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

    // Tier 1 — no crops at all yet.
    if (!hasCrops) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppConstants.primaryGreen.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.eco_outlined,
                size: 40,
                color: AppConstants.primaryGreen,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "You don't have any crops yet",
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppConstants.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a crop before you can build up inventory.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onGoToMyCrops,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                ),
              ),
              child: Text(
                'Go to My Crops',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Tier 2 — has crops, but no harvests recorded yet.
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
              Icons.inventory_2_outlined,
              size: 40,
              color: AppConstants.outline.withValues(alpha: 0.60),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No Inventory Yet',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppConstants.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Record a harvest to start building your inventory.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onRecordHarvest,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              ),
            ),
            child: Text(
              'Record New Harvest',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
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
        borderRadius: BorderRadius.circular(8),
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _block(56, 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _block(120, 14),
                    const SizedBox(height: 6),
                    _block(90, 11),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _block(double.infinity, 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offer to Cooperative Dialog
// ─────────────────────────────────────────────────────────────────────────────

Future<bool?> showOfferToCooperativeDialog(
  BuildContext context, {
  required InventoryBatchModel batch,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _OfferToCooperativeDialog(batch: batch),
  );
}

class _OfferToCooperativeDialog extends StatefulWidget {
  final InventoryBatchModel batch;
  const _OfferToCooperativeDialog({required this.batch});

  @override
  State<_OfferToCooperativeDialog> createState() => _OfferToCooperativeDialogState();
}

class _OfferToCooperativeDialogState extends State<_OfferToCooperativeDialog> {
  late final TextEditingController _qtyController;
  final _repo = CooperativeOfferRepository();
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(
      text: widget.batch.availableKg.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final qty = double.tryParse(_qtyController.text.trim());
    if (qty == null || qty <= 0 || qty > widget.batch.availableKg) {
      setState(() => _error =
          'Enter a quantity up to ${widget.batch.availableKg.toStringAsFixed(0)} kg.');
      return;
    }

    setState(() { _isSubmitting = true; _error = null; });
    try {
      await _repo.offerToCooperative(batch: widget.batch, quantityKg: qty);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = 'Could not submit offer. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusXl)),
      title: Text('Offer to Cooperative',
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SP3 will confirm the actual weighed quantity and price when they pick this up.',
            style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Quantity to offer (kg)',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.poppins(color: AppConstants.outline)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConstants.primaryGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
          ),
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('Submit Offer', style: GoogleFonts.poppins(fontSize: 14)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Record Informal Sale Dialog
// ─────────────────────────────────────────────────────────────────────────────

Future<bool?> showRecordInformalSaleDialog(
  BuildContext context, {
  required InventoryBatchModel batch,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _RecordInformalSaleDialog(batch: batch),
  );
}

class _RecordInformalSaleDialog extends StatefulWidget {
  final InventoryBatchModel batch;
  const _RecordInformalSaleDialog({required this.batch});

  @override
  State<_RecordInformalSaleDialog> createState() => _RecordInformalSaleDialogState();
}

class _RecordInformalSaleDialogState extends State<_RecordInformalSaleDialog> {
  late final TextEditingController _qtyController;
  final _buyerController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _repo = InformalSaleRepository();
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(
      text: widget.batch.availableKg.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _buyerController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final qty = double.tryParse(_qtyController.text.trim());
    if (qty == null || qty <= 0 || qty > widget.batch.availableKg) {
      setState(() => _error =
          'Enter a quantity up to ${widget.batch.availableKg.toStringAsFixed(0)} kg.');
      return;
    }

    setState(() { _isSubmitting = true; _error = null; });
    try {
      await _repo.recordInformalSale(
        batch: widget.batch,
        quantityKg: qty,
        buyerName: _buyerController.text.trim().isEmpty ? null : _buyerController.text.trim(),
        amount: double.tryParse(_amountController.text.trim()),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = 'Could not record sale. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusXl)),
      title: Text('Record Informal Sale',
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _qtyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Quantity sold (kg)', errorText: _error),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _buyerController,
              decoration: const InputDecoration(labelText: 'Buyer name (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount received (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.poppins(color: AppConstants.outline)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConstants.primaryGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
          ),
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('Save', style: GoogleFonts.poppins(fontSize: 14)),
        ),
      ],
    );
  }
}