import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/inventory_batch_model.dart';
import '../../../data/repositories/cooperative_offer_repository.dart';
import '../../../data/repositories/informal_sale_repository.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../data/repositories/market_linking_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/report_summary_widgets.dart';

class ManageInventoryScreen extends StatefulWidget {
  const ManageInventoryScreen({super.key});

  @override
  State<ManageInventoryScreen> createState() => _ManageInventoryScreenState();
}

class _ManageInventoryScreenState extends State<ManageInventoryScreen> {
  final _repo = InventoryRepository();
  final _cropRepo = CropRepository();
  final _offerRepo = CooperativeOfferRepository();
  final _marketLinkingRepo = MarketLinkingRepository();
  final _searchController = TextEditingController();

  List<InventoryBatchModel> _allBatches = [];
  List<InventoryBatchModel> _filtered = [];
  Map<String, double> _summary = {'available': 0, 'reserved': 0, 'sold': 0};
  Map<String, FarmerCropModel> _cropsById = {};
  bool _hasCrops = true; // assume true until loaded, avoids an empty-state flash
  Set<String> _pendingOfferBatchIds = {};
  Set<String> _activeMarketLinkingBatchIds = {};
  DaAmadEnrollmentStatus? _gingerEnrollmentStatus; // null = never enrolled

  String _activeStatusFilter = _StatusFilterRow.all;
  bool _isLoading = true;
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
      _marketLinkingRepo.fetchMyActiveSubmissionBatchIds(),
      _marketLinkingRepo.fetchMyEnrollment(),
    ]);
    if (!mounted) return;
    final crops = results[2] as List<FarmerCropModel>;
    setState(() {
      _allBatches = results[0] as List<InventoryBatchModel>;
      _summary = results[1] as Map<String, double>;
      _hasCrops = crops.isNotEmpty;
      _cropsById = {for (final c in crops) c.id: c};
      _pendingOfferBatchIds = results[3] as Set<String>;
      _activeMarketLinkingBatchIds = results[4] as Set<String>;
      _gingerEnrollmentStatus = (results[5] as DaAmadEnrollmentModel?)?.status;
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

  void _setStatusFilter(String filter) {
    setState(() {
      _activeStatusFilter = filter;
      _applyFilters();
    });
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    _filtered = _allBatches.where((b) {
      switch (_activeStatusFilter) {
        case _StatusFilterRow.available:
          if (b.status != 'available') return false;
          break;
        case _StatusFilterRow.reserved:
          if (b.status != 'reserved') return false;
          break;
        // Folds 'withdrawn' into "Sold" — both represent inventory no
        // longer available to dispose of, matching the old Show-Sold
        // toggle's own grouping; withdrawn batches are rare enough not to
        // warrant a 6th chip nobody asked for.
        case _StatusFilterRow.sold:
          if (!(b.isSoldOut || b.isWithdrawn)) return false;
          break;
        case _StatusFilterRow.lowStock:
          if (b.status != 'low_stock') return false;
          break;
        default: // All — no status filter
          break;
      }

      if (q.isEmpty) return true;
      return b.cropName.toLowerCase().contains(q) ||
          b.batchNumber.toLowerCase().contains(q);
    }).toList();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

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
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
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
              'Total batch quantity: ${batch.quantityKg.toStringAsFixed(0)} kg  •  You can only decrease this value',
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
              final maxAvailable = batch.availableKg;
              if (newQty == null || newQty < 0 || newQty > maxAvailable) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Enter a value between 0 and ${maxAvailable.toStringAsFixed(0)} kg. Increasing beyond the current available amount isn\'t supported here — released reservations restore this automatically.',
                    ),
                  ),
                );
                return;
              }
              if (!_isOnline) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Updating quantity requires an internet connection. Please try again once you\'re back online.'),
                    backgroundColor: AppConstants.warningAmber,
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

  Future<void> _handleBatchAction(InventoryBatchModel batch) async {
    // Ginger (DA-AMAD-exclusive) batches never go through the generic
    // Marketplace/Cooperative/Informal disposal flow below — Market
    // Linking is their only path. Intercepted here, before the
    // isAvailable branching, because Market Linking never reserves the
    // batch (available_kg is only touched at admin completion) — a
    // Ginger batch with an active submission still reads as plain
    // 'available' and would otherwise fall into the wrong branch.
    if (batch.cropType == 'da_amad_market') {
      if (_activeMarketLinkingBatchIds.contains(batch.id)) {
        context.pushRoute(AppRoutes.myMarketLinking);
      } else if (_gingerEnrollmentStatus != DaAmadEnrollmentStatus.approved) {
        // Not yet an approved Market Linking participant — route to the
        // enrollment flow instead of the sale dialog. Covers "never
        // enrolled," "pending," and "rejected" alike; MyMarketLinkingScreen
        // shows the right state for each on its own.
        context.pushRoute(AppRoutes.myMarketLinking).then((_) => _loadData());
      } else {
        if (!_isOnline) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'This action requires an internet connection. Please try again once you\'re back online.'),
              backgroundColor: AppConstants.warningAmber,
            ),
          );
          return;
        }
        final result = await showSubmitToSellDialog(context, batch: batch);
        if (result == true) _loadData();
      }
      return;
    }

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

    // Marketplace/Cooperative/Informal all depend on live server state
    // (available_kg at call time, market price, row locks) — unlike
    // Harvest Entry, these are deliberately NOT queued for offline replay.
    // Block with a clear message instead of letting the RPC fail silently.
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This action requires an internet connection. Please try again once you\'re back online.'),
          backgroundColor: AppConstants.warningAmber,
        ),
      );
      return;
    }

    final action = await showDisposalActionSheet(
      context,
      cropName: batch.cropName,
      availableKg: batch.availableKg,
      isCoopEligible: batch.isCoopEligible,
      cropType: batch.cropType,
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
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(message: "You're offline — some inventory actions require an internet connection."),
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
                    // No FAB or bottom nav under this pushed (non-tab)
                    // screen to clear — 100px of bottom padding was
                    // leaving genuinely dead space at the end of the
                    // scroll, not reserved space for anything.
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      // Summary metrics
                      _SummaryMetrics(summary: _summary, isLoading: _isLoading),
                      const SizedBox(height: 20),

                      // Search bar
                      _SearchBar(controller: _searchController),
                      const SizedBox(height: 12),

                      // Status filter chips (replaces the old binary
                      // Show-Sold toggle)
                      _StatusFilterRow(
                        active: _activeStatusFilter,
                        onSelected: _setStatusFilter,
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
                          hasFilter: _searchQuery.isNotEmpty ||
                              _activeStatusFilter != _StatusFilterRow.all,
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
                              crop: _cropsById[b.cropId],
                              hasPendingOffer: _pendingOfferBatchIds.contains(b.id),
                              hasActiveMarketLinking: _activeMarketLinkingBatchIds.contains(b.id),
                              gingerEnrollmentApproved:
                                  _gingerEnrollmentStatus == DaAmadEnrollmentStatus.approved,
                              onUpdateQuantity: () => _showUpdateQuantityDialog(b),
                              onViewHarvestRecord: () => context
                                  .pushRoute(AppRoutes.harvestHistory, extra: b.cropName),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Metrics — built on the shared ReportIconStatCard (the same KPI
// tile Admin's Reports module uses), per the redesign's request to match
// Admin's KPI card pattern rather than this screen's own bespoke style.
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
          child: ReportIconStatCard(
            icon: Icons.check_circle_outline_rounded,
            accent: AppConstants.successGreen,
            label: 'Available',
            value: isLoading ? '—' : '${_fmt(summary['available'] ?? 0)} kg',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.hourglass_top_rounded,
            accent: AppConstants.warningAmber,
            label: 'Reserved',
            value: isLoading ? '—' : '${_fmt(summary['reserved'] ?? 0)} kg',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ReportIconStatCard(
            icon: Icons.sell_outlined,
            accent: AppConstants.primaryGreen,
            label: 'Sold',
            value: isLoading ? '—' : '${_fmt(summary['sold'] ?? 0)} kg',
          ),
        ),
      ],
    );
  }

  String _fmt(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
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
// Status Filter Row — replaces the old binary Show-Sold toggle with real
// filter chips over InventoryBatchModel.status, same visual pattern as
// CropCategoryChips elsewhere in this redesign round.
// ─────────────────────────────────────────────────────────────────────────────

class _StatusFilterRow extends StatelessWidget {
  static const all = 'All';
  static const available = 'Available';
  static const reserved = 'Reserved';
  static const sold = 'Sold';
  static const lowStock = 'Low Stock';
  static const _options = [all, available, reserved, sold, lowStock];

  final String active;
  final ValueChanged<String> onSelected;

  const _StatusFilterRow({required this.active, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _options.map((option) {
          final isActive = option == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppConstants.primaryContainer.withValues(alpha: 0.12)
                      : sagana.cardBackground,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: isActive
                      ? Border.all(
                          color: AppConstants.primaryContainer.withValues(alpha: 0.30))
                      : null,
                ),
                child: Text(
                  option,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive ? AppConstants.primaryContainer : cs.onSurfaceVariant,
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

// ─────────────────────────────────────────────────────────────────────────────
// Batch Card
// ─────────────────────────────────────────────────────────────────────────────

/// Icon+label row for a PopupMenuItem — matches Admin Inventory
/// Management's own menu-row pattern (admin_inventory_screen.dart's
/// _menuRow), used as the reference for how this screen's 3-dot menu
/// should behave.
Widget _batchMenuRow(IconData icon, String label, Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Text(label, style: GoogleFonts.inter(fontSize: 13, color: color)),
    ],
  );
}

class _BatchCard extends StatelessWidget {
  final InventoryBatchModel batch;
  final FarmerCropModel? crop;
  final bool hasPendingOffer;
  final bool hasActiveMarketLinking;
  final bool gingerEnrollmentApproved;
  final VoidCallback onUpdateQuantity;
  final VoidCallback onViewHarvestRecord;
  final VoidCallback onActionTap;

  const _BatchCard({
    required this.batch,
    this.crop,
    this.hasPendingOffer = false,
    this.hasActiveMarketLinking = false,
    this.gingerEnrollmentApproved = false,
    required this.onUpdateQuantity,
    required this.onViewHarvestRecord,
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
                color: AppConstants.infoBlueFg.withValues(alpha: 0.05),
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
                  _BatchCropImage(crop: crop, category: crop?.category ?? ''),
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
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: AppConstants.outline,
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'update':
                          onUpdateQuantity();
                          break;
                        case 'history':
                          onViewHarvestRecord();
                          break;
                      }
                    },
                    // "Delete Batch" removed — a batch can already carry
                    // real selling/transaction history (listings, coop
                    // offers, informal sales, market linking), and
                    // deleting it would erase that record. Historical
                    // records are preserved, not deletable, same
                    // reasoning already applied to Crop Roster's crops.
                    itemBuilder: (context) => [
                      if (!batch.isSoldOut)
                        PopupMenuItem(
                          value: 'update',
                          child: _batchMenuRow(
                            Icons.edit_outlined,
                            'Update Quantity',
                            AppConstants.onSurface,
                          ),
                        ),
                      PopupMenuItem(
                        value: 'history',
                        child: _batchMenuRow(
                          Icons.receipt_long_outlined,
                          'View Harvest Record',
                          AppConstants.onSurface,
                        ),
                      ),
                    ],
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
                    _ActionButton(
                      status: batch.status,
                      hasPendingOffer: hasPendingOffer,
                      isDaAmadExclusive: batch.cropType == 'da_amad_market',
                      hasActiveMarketLinking: hasActiveMarketLinking,
                      gingerEnrollmentApproved: gingerEnrollmentApproved,
                      onTap: onActionTap,
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

  _StatusInfo _statusInfo(String status) {
    switch (status) {
      case 'available':
        return _StatusInfo(accent: AppConstants.successGreen);
      case 'low_stock':
        return _StatusInfo(accent: AppConstants.warningAmber);
      case 'reserved':
        return _StatusInfo(accent: AppConstants.warningAmber);
      case 'sold_out':
        return _StatusInfo(accent: AppConstants.outline);
      default:
        return _StatusInfo(accent: AppConstants.outline);
    }
  }
}

class _StatusInfo {
  final Color accent;
  _StatusInfo({required this.accent});
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch Crop Image — the shared-image system: Crop Roster's Edit Crop
// (Revision D) is the one place a farmer sets a crop's photo, and every
// other context (this card, Record New Harvest, Harvest History) reads
// the exact same FarmerCropModel.displayImageUrl, never a separate copy.
// Neutral background (matching Crop Roster/Select Crop's own fallback),
// not status-tinted, so a real photo isn't fighting an amber/green box
// behind it.
// ─────────────────────────────────────────────────────────────────────────────

class _BatchCropImage extends StatelessWidget {
  final FarmerCropModel? crop;
  final String category;

  const _BatchCropImage({required this.crop, required this.category});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: crop?.hasDisplayImage == true
          ? Image.network(
              crop!.displayImageUrl!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _BatchCropFallbackIcon(category: category),
            )
          : _BatchCropFallbackIcon(category: category),
    );
  }
}

class _BatchCropFallbackIcon extends StatelessWidget {
  final String category;
  const _BatchCropFallbackIcon({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(color: Color(0xFFDBF1FE)),
      child: Icon(
        FarmerCropModel.iconForCategory(category),
        color: AppConstants.primaryGreen,
        size: 28,
      ),
    );
  }
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
  final bool isDaAmadExclusive;
  final bool hasActiveMarketLinking;
  final bool gingerEnrollmentApproved;
  final VoidCallback onTap;

  const _ActionButton({
    required this.status,
    this.hasPendingOffer = false,
    this.isDaAmadExclusive = false,
    this.hasActiveMarketLinking = false,
    this.gingerEnrollmentApproved = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    String label;
    bool isOutlined = false;
    if (isDaAmadExclusive && (status == 'available' || status == 'low_stock')) {
      // Ginger's only path — never "Create Listing", which would imply
      // the Marketplace/Cooperative/Informal flow that doesn't apply here.
      // A farmer who isn't an approved Market Linking participant yet is
      // guided to enroll first, rather than straight to a sale dialog
      // that would just fail server-side.
      label = hasActiveMarketLinking
          ? 'See Progress'
          : gingerEnrollmentApproved
              ? 'Submit to Sell'
              : 'Enroll to Sell';
    } else {
      switch (status) {
        case 'available':
        case 'low_stock':
          label = 'Create Listing';
          break;
        case 'reserved':
          // Not "View Order" — a reserved batch with no pending cooperative
          // offer means it's tied to a Marketplace listing, not an order;
          // this switches to the My Listings tab, there's no per-order
          // screen in this path.
          label = hasPendingOffer ? 'Offer Status' : 'View Listing';
          break;
        default:
          label = 'View History';
          isOutlined = true;
      }
    }

    // Fixed width (not IntrinsicWidth) — this button's label changes with
    // batch status ("Create Listing" / "View Listing" / "Offer Status" /
    // "Submit to Sell" / "See Progress" / "View History"), and hugging each
    // label's own text made the button visibly change size card-to-card.
    // Sized to fit the longest label; text stays on one line, shrinking
    // to fit if needed rather than wrapping and changing card height.
    const buttonWidth = 136.0;

    if (isOutlined) {
      return SizedBox(
        width: buttonWidth,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppConstants.outline,
            side: BorderSide(
              color: AppConstants.outline.withValues(alpha: 0.30),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                maxLines: 1, style: GoogleFonts.poppins(fontSize: 12)),
          ),
        ),
      );
    }

    return SizedBox(
      width: buttonWidth,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          elevation: 0,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

// _BatchActionSheet and _MenuOption removed — the batch action menu is now
// a PopupMenuButton rendered directly in _BatchCard's header (see
// _batchMenuRow above), matching Admin Inventory Management's own 3-dot
// menu pattern instead of the app's centered ManagementModalShell dialog.

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
                color: AppConstants.infoBlueBg,
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
                'Go to Crop Roster',
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
              color: AppConstants.infoBlueBg,
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
// Submit to Sell Dialog (Ginger / Market Linking)
// Ginger's only disposal path — submits a farmer-initiated Market Linking
// request tied to this specific batch (supabase_schema_market_linking_
// farmer_requests.sql), pending admin approval. Mirrors
// _OfferToCooperativeDialog's shape (volume input, pre-filled from
// available stock).
// ─────────────────────────────────────────────────────────────────────────────

Future<bool?> showSubmitToSellDialog(
  BuildContext context, {
  required InventoryBatchModel batch,
}) {
  return showManagementModal<bool>(
    context: context,
    builder: (_) => _SubmitToSellDialog(batch: batch),
  );
}

class _SubmitToSellDialog extends StatefulWidget {
  final InventoryBatchModel batch;
  const _SubmitToSellDialog({required this.batch});

  @override
  State<_SubmitToSellDialog> createState() => _SubmitToSellDialogState();
}

class _SubmitToSellDialogState extends State<_SubmitToSellDialog> {
  late final TextEditingController _qtyController;
  final _repo = MarketLinkingRepository();
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
      await _repo.submitGingerForSale(
        inventoryBatchId: widget.batch.id,
        volumeKg: qty,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = 'Could not submit. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ManagementModalShell(
      title: 'Submit to Sell',
      subtitle: 'SP3 will review this and find a DA-AMAD buyer for this batch. '
          'You can track progress in My Market Linking.',
      body: TextField(
        controller: _qtyController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
        ],
        decoration: InputDecoration(
          labelText: 'Quantity to submit (kg)',
          errorText: _error,
        ),
      ),
      footer: ManagementModalActions(
        primaryLabel: 'Submit Request',
        isLoading: _isSubmitting,
        onPrimary: _submit,
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
  return showManagementModal<bool>(
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
  String? _qtyError;
  String? _submitError;

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

    setState(() {
      _qtyError = (qty == null || qty <= 0 || qty > widget.batch.availableKg)
          ? 'Enter a quantity up to ${widget.batch.availableKg.toStringAsFixed(0)} kg.'
          : null;
      _submitError = null;
    });
    if (_qtyError != null) return;

    setState(() => _isSubmitting = true);
    try {
      await _repo.offerToCooperative(batch: widget.batch, quantityKg: qty!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitError = 'Could not submit offer. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enteredQty = double.tryParse(_qtyController.text.trim());
    final exceedsAvailable = enteredQty != null && enteredQty > widget.batch.availableKg;

    return ManagementModalShell(
      title: 'Offer to Cooperative',
      subtitle: 'SP3 will confirm the actual weighed quantity and price when they pick this up.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FieldLabel(label: 'Quantity to offer (kg)', cs: cs),
          TextFormField(
            controller: _qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: '0.00', errorText: _qtyError),
          ),
          const SizedBox(height: 4),
          Text(
            exceedsAvailable
                ? 'Only ${widget.batch.availableKg.toStringAsFixed(0)} kg available — reduce the quantity.'
                : '${widget.batch.availableKg.toStringAsFixed(0)} kg available',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: exceedsAvailable ? FontWeight.w600 : FontWeight.w400,
              color: exceedsAvailable ? AppConstants.errorRed : cs.onSurfaceVariant,
            ),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 12),
            Text(
              _submitError!,
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed),
            ),
          ],
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: 'Submit Offer',
        isLoading: _isSubmitting,
        onPrimary: _submit,
      ),
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
  return showManagementModal<bool>(
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
  final _repo = InformalSaleRepository();
  bool _isSubmitting = false;
  String? _qtyError;
  String? _buyerError;
  String? _amountError;
  String? _submitError;

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
    super.dispose();
  }

  Future<void> _submit() async {
    final qty = double.tryParse(_qtyController.text.trim());
    final buyer = _buyerController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());

    setState(() {
      _qtyError = (qty == null || qty <= 0 || qty > widget.batch.availableKg)
          ? 'Enter a quantity up to ${widget.batch.availableKg.toStringAsFixed(0)} kg.'
          : null;
      _buyerError = buyer.isEmpty ? 'Buyer name is required.' : null;
      _amountError =
          (amount == null || amount <= 0) ? 'Amount received is required.' : null;
      _submitError = null;
    });
    if (_qtyError != null || _buyerError != null || _amountError != null) return;

    setState(() => _isSubmitting = true);
    try {
      await _repo.recordInformalSale(
        batch: widget.batch,
        quantityKg: qty!,
        buyerName: buyer,
        amount: amount,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitError = 'Could not record sale. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enteredQty = double.tryParse(_qtyController.text.trim());
    final exceedsAvailable = enteredQty != null && enteredQty > widget.batch.availableKg;

    return ManagementModalShell(
      title: 'Record Informal Sale',
      subtitle: 'For a sale made outside the app — to a neighbor, local buyer, or for personal use.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FieldLabel(label: 'Quantity sold (kg)', cs: cs),
          TextFormField(
            controller: _qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: '0.00', errorText: _qtyError),
          ),
          const SizedBox(height: 4),
          Text(
            exceedsAvailable
                ? 'Only ${widget.batch.availableKg.toStringAsFixed(0)} kg available — reduce the quantity.'
                : '${widget.batch.availableKg.toStringAsFixed(0)} kg available',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: exceedsAvailable ? FontWeight.w600 : FontWeight.w400,
              color: exceedsAvailable ? AppConstants.errorRed : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel(label: 'Buyer name', cs: cs),
          TextFormField(
            controller: _buyerController,
            decoration: InputDecoration(hintText: 'Who bought it?', errorText: _buyerError),
          ),
          const SizedBox(height: 16),
          _FieldLabel(label: 'Amount received (₱)', cs: cs),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              prefixText: '₱ ',
              hintText: '0.00',
              errorText: _amountError,
            ),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 12),
            Text(
              _submitError!,
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed),
            ),
          ],
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: 'Save',
        isLoading: _isSubmitting,
        onPrimary: _submit,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final ColorScheme cs;

  const _FieldLabel({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
        ),
      ),
    );
  }
}