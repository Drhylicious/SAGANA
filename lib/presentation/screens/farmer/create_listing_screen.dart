import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/inventory_batch_model.dart';
import '../../../data/models/marketplace_listing_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';

class CreateListingScreen extends StatefulWidget {
  // Either an InventoryBatchModel (preselected from Manage Inventory's
  // disposal sheet) or a MarketplaceListingModel (resubmitting a
  // changes_required listing), or null (opened with no preselection).
  final Object? initialArg;

  const CreateListingScreen({super.key, this.initialArg});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _inventoryRepo = InventoryRepository();
  final _listingRepo = ListingRepository();
  final _dashboardRepo = DashboardRepository();
  final _picker = ImagePicker();

  final _titleController = TextEditingController();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();

  List<InventoryBatchModel> _batches = [];
  InventoryBatchModel? _selectedBatch;
  MarketplaceListingModel? _editingListing; // non-null when resubmitting

  double? _marketPrice;
  XFile? _photo;
  bool _isLoadingBatches = true;
  bool _isSubmitting = false;
  bool _isOnline = true;
  bool _batchWasPreselected = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });

    // Read via the constructor now — GoRouter's `extra` is delivered here,
    // not through ModalRoute.settings.arguments (that only ever gets
    // populated by raw Navigator.push(..., settings: RouteSettings(...)),
    // which is not how this screen is reached).
    final arg = widget.initialArg;
    if (arg is MarketplaceListingModel) {
      _editingListing = arg;
      _titleController.text = arg.displayName;
      _quantityController.text = arg.volumeKg.toStringAsFixed(0);
      _priceController.text = arg.pricePerKg.toStringAsFixed(2);
      // Resubmit path: fetch the listing's *own* reserved batch directly,
      // bypassing fetchAvailableBatches()'s status filter. That filter only
      // returns 'available'/'low_stock' batches, but the batch behind a
      // changes_required listing is almost always 'reserved' (fully
      // committed to this pending listing) — so it would never appear
      // there, and falling back to fetchAvailableBatches().first would
      // silently validate "Max: X kg" and the market price against an
      // unrelated batch.
      if (arg.inventoryBatchId != null) {
        _loadEditingBatch(arg.inventoryBatchId!);
      } else {
        _isLoadingBatches = false;
      }
    } else {
      if (arg is InventoryBatchModel) _batchWasPreselected = true;
      _loadBatches(preselect: arg is InventoryBatchModel ? arg : null);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _loadBatches({InventoryBatchModel? preselect}) async {
    setState(() => _isLoadingBatches = true);
    final batches = await _inventoryRepo.fetchAvailableBatches();
    if (!mounted) return;

    InventoryBatchModel? initial = preselect ?? (batches.isNotEmpty ? batches.first : null);

    setState(() {
      _batches = batches;
      _selectedBatch = initial;
      _isLoadingBatches = false;
    });

    if (initial != null) _onBatchSelected(initial);
  }

  /// Loads the specific batch a `changes_required` listing already reserved
  /// stock against, regardless of that batch's current status.
  Future<void> _loadEditingBatch(String batchId) async {
    setState(() => _isLoadingBatches = true);
    final batch = await _inventoryRepo.fetchBatchById(batchId);
    if (!mounted) return;
    setState(() {
      _batches = batch != null ? [batch] : [];
      _selectedBatch = batch;
      _isLoadingBatches = false;
    });
    // Safe to reuse _onBatchSelected here: _editingListing is already set,
    // so its "don't overwrite quantity/price" branch applies — this just
    // picks up the market-price lookup for the correct crop.
    if (batch != null) _onBatchSelected(batch);
  }

  Future<void> _onBatchSelected(InventoryBatchModel batch) async {
    setState(() {
      _selectedBatch = batch;
      if (_editingListing == null) {
        _quantityController.text = batch.availableKg.toStringAsFixed(0);
      }
    });
    final price = await _dashboardRepo.fetchLatestPriceForCrop(batch.cropName);
    if (!mounted) return;
    setState(() {
      _marketPrice = price;
      if (_editingListing == null && price != null && _priceController.text.isEmpty) {
        _priceController.text = price.toStringAsFixed(2);
      }
    });
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PhotoSourceSheet(),
    );
    if (source == null) return;
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked != null && mounted) setState(() => _photo = picked);
  }

  void _removePhoto() => setState(() => _photo = null);

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _handleSubmit() async {
    if (_selectedBatch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a batch to list.')),
      );
      return;
    }

    final qty = double.tryParse(_quantityController.text.trim());
    final price = double.tryParse(_priceController.text.trim());

    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity.')),
      );
      return;
    }

    // When editing, _selectedBatch.availableKg already has this listing's
    // own reservation subtracted out (it's a real batch fetched via
    // fetchBatchById, not a fresh unreserved one) — so the ceiling here
    // must add back what the farmer already holds. Otherwise a farmer
    // resubmitting at their existing quantity, or a small increase, would
    // be wrongly capped at only what's available *elsewhere*.
    if (_editingListing != null) {
      final effectiveMax = _selectedBatch!.availableKg + _editingListing!.volumeKg;
      if (qty > effectiveMax) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quantity cannot exceed your available stock (${effectiveMax.toStringAsFixed(0)} kg).')),
        );
        return;
      }
    } else if (qty > _selectedBatch!.availableKg) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Quantity cannot exceed available stock (${_selectedBatch!.availableKg.toStringAsFixed(0)} kg).')),
      );
      return;
    }

    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid asking price.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      String? photoUrl = _editingListing?.photoUrl;
      if (_photo != null) {
        final Uint8List bytes = await _photo!.readAsBytes();
        final ext = _photo!.name.split('.').last;
        photoUrl = await _listingRepo.uploadListingPhoto(
          batchNumber: _selectedBatch!.batchNumber,
          imageBytes: bytes,
          fileExtension: ext,
        );
      }

      MarketplaceListingModel submittedListing;
      if (_editingListing != null) {
        submittedListing = await _listingRepo.resubmitListing(
          listingId: _editingListing!.id,
          pricePerKg: price,
          volumeKg: qty,
          photoUrl: photoUrl,
        );
      } else {
        submittedListing = await _listingRepo.createListing(
          cropName: _selectedBatch!.cropName,
          variety: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
          pricePerKg: price,
          volumeKg: qty,
          inventoryBatchId: _selectedBatch!.id,
          photoUrl: photoUrl,
        );
      }

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      context.pushReplacementRoute(AppRoutes.listingSuccess, extra: submittedListing);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      // resubmit_listing_with_reservation raises when an increased quantity
      // exceeds real available stock, and create_listing_with_reservation
      // raises when the crop is Ginger (DA-AMAD-exclusive, sold only
      // through Market Linking) — surface both specifically instead of a
      // generic message, since they're actionable, expected failures
      // rather than network/server errors.
      final errorText = e.toString();
      final message = errorText.contains('Not enough available quantity')
          ? 'Not enough available stock for that quantity. Please lower it and try again.'
          : errorText.contains('Ginger cannot be listed')
              ? 'Ginger can only be sold through the Market Linking program, not the open Marketplace.'
              : 'Failed to submit listing. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  double get _estimatedRevenue {
    final qty = double.tryParse(_quantityController.text.trim()) ?? 0;
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    return qty * price;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(message: "You're offline — you won't be able to submit a new listing until you're reconnected."),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 72),
                    Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Admin review banner
                      const _AdminReviewBanner(),
                      const SizedBox(height: 24),

                      // ── Section 1: Batch source ─────────────────────────
                      if (_editingListing == null && !_batchWasPreselected) ...[
                        const _SectionLabel(number: 1, title: 'Choose What to Sell'),
                        const SizedBox(height: 10),
                        _isLoadingBatches
                            ? const SizedBox(height: 110, child: Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen)))
                            : _batches.isEmpty
                                ? _NoBatchesNotice(onGoToInventory: () =>
                                  context.pushReplacementRoute(AppRoutes.manageInventory))
                                : _BatchSelector(
                                    batches: _batches,
                                    selected: _selectedBatch,
                                    onSelected: _onBatchSelected,
                                  ),
                        const SizedBox(height: 24),
                      ],
                      if (_editingListing == null && _batchWasPreselected && _selectedBatch != null) ...[
                        const _SectionLabel(number: 1, title: 'What You\'re Selling'),
                        const SizedBox(height: 10),
                        _PreselectedBatchBanner(batch: _selectedBatch!),
                        const SizedBox(height: 24),
                      ],
                      if (_editingListing != null) ...[
                        const _SectionLabel(number: 1, title: 'What You\'re Selling'),
                        const SizedBox(height: 10),
                        if (_isLoadingBatches)
                          const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen)))
                        else if (_selectedBatch != null)
                          _PreselectedBatchBanner(batch: _selectedBatch!),
                        const SizedBox(height: 14),
                      ],

                      // Auto-filled details
                      if (_selectedBatch != null) ...[
                        _AutoFilledGrid(batch: _selectedBatch!),
                        const SizedBox(height: 24),
                      ],

                      // ── Section 2: Price & quantity + photo ─────────────
                      const _SectionLabel(number: 2, title: 'Set Your Price & Add a Photo'),
                      const SizedBox(height: 10),
                      _FormCard(
                        titleController: _titleController,
                        quantityController: _quantityController,
                        priceController: _priceController,
                        maxQty: _editingListing != null
                            ? (_selectedBatch != null
                                ? _selectedBatch!.availableKg + _editingListing!.volumeKg
                                : null)
                            : _selectedBatch?.availableKg,
                        marketPrice: _marketPrice,
                        photo: _photo,
                        existingPhotoUrl: _editingListing?.photoUrl,
                        isResubmit: _editingListing != null,
                        onPickPhoto: _pickPhoto,
                        onRemovePhoto: _removePhoto,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 24),

                      // ── Section 3: Preview ───────────────────────────────
                      const _SectionLabel(number: 3, title: 'Review Before Submitting'),
                      const SizedBox(height: 10),
                      _LivePreviewCard(
                        title: _titleController.text.trim().isEmpty
                            ? (_selectedBatch?.cropName ?? '')
                            : _titleController.text.trim(),
                        cropName: _selectedBatch?.cropName ?? '',
                        quantity: double.tryParse(_quantityController.text.trim()) ?? 0,
                        price: double.tryParse(_priceController.text.trim()) ?? 0,
                        photo: _photo,
                        existingPhotoUrl: _editingListing?.photoUrl,
                        estimatedRevenue: _estimatedRevenue,
                      ),
                      const SizedBox(height: 20),

                      // ── What happens next preview ───────────────────────
                      _WhatHappensNextCard(isResubmit: _editingListing != null),
                      const SizedBox(height: 24),

                      // Bottom actions
                      _BottomActions(
                        isOnline: _isOnline,
                        isSubmitting: _isSubmitting,
                        isResubmit: _editingListing != null,
                        canSubmit: _selectedBatch != null,
                        onSubmit: _handleSubmit,
                        onViewListings: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: FarmerTopBar(
              title: _editingListing != null ? 'Edit Listing' : 'Create Listing',
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
// Section Label — numbered guide markers ("1. Choose What to Sell")
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final int number;
  final String title;
  const _SectionLabel({required this.number, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppConstants.primaryGreen,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppConstants.charcoal,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Review Banner
// ─────────────────────────────────────────────────────────────────────────────

class _AdminReviewBanner extends StatelessWidget {
  const _AdminReviewBanner();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppConstants.warningAmber.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: AppConstants.warningAmber.withValues(alpha: 0.30)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, color: AppConstants.warningAmber, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant, height: 1.4),
                    children: [
                      const TextSpan(text: 'Your listing will be reviewed by the '),
                      TextSpan(text: 'SP3 Cooperative admin', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppConstants.onSurface)),
                      const TextSpan(text: ' before becoming visible to buyers in the marketplace.'),
                    ],
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
// Preselected Batch Banner
// ─────────────────────────────────────────────────────────────────────────────

class _PreselectedBatchBanner extends StatelessWidget {
  final InventoryBatchModel batch;
  const _PreselectedBatchBanner({required this.batch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.primaryGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.primaryGreen.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: AppConstants.primaryGreen, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${batch.cropName} • ${batch.availableKg.toStringAsFixed(0)} kg from Batch #${batch.batchNumber}',
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppConstants.primaryGreen),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch Selector
// ─────────────────────────────────────────────────────────────────────────────

class _BatchSelector extends StatelessWidget {
  final List<InventoryBatchModel> batches;
  final InventoryBatchModel? selected;
  final ValueChanged<InventoryBatchModel> onSelected;

  const _BatchSelector({required this.batches, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: batches.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final batch = batches[i];
          final isActive = batch.id == selected?.id;
          return GestureDetector(
            onTap: () => onSelected(batch),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 168,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: isActive ? AppConstants.primaryGreen.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.60),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isActive ? AppConstants.primaryGreen : AppConstants.outline.withValues(alpha: 0.20),
                  width: isActive ? 2 : 1,
                ),
              ),
              child: Stack(
                children: [
                  if (isActive)
                    const Positioned(
                      top: 0, right: 0,
                      child: Icon(Icons.check_circle_rounded, color: AppConstants.primaryGreen, size: 20),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(batch.batchNumber,
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                              color: isActive ? AppConstants.primaryGreen : AppConstants.outline)),
                      const SizedBox(height: 3),
                      Text(batch.cropName,
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.onSurface),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 12, color: AppConstants.outline),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text('${batch.availableKg.toStringAsFixed(0)}kg',
                                style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NoBatchesNotice extends StatelessWidget {
  final VoidCallback onGoToInventory;
  const _NoBatchesNotice({required this.onGoToInventory});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.outline.withValues(alpha: 0.20)),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 32, color: AppConstants.outline.withValues(alpha: 0.60)),
          const SizedBox(height: 10),
          Text('No available inventory to list',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppConstants.charcoal)),
          const SizedBox(height: 4),
          Text('Record a harvest first to build up inventory.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.outline)),
          const SizedBox(height: 12),
          TextButton(onPressed: onGoToInventory, child: Text('Go to Inventory', style: GoogleFonts.poppins(color: AppConstants.primaryGreen))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auto-filled Details Grid
// ─────────────────────────────────────────────────────────────────────────────

class _AutoFilledGrid extends StatelessWidget {
  final InventoryBatchModel batch;
  const _AutoFilledGrid({required this.batch});

  @override
  Widget build(BuildContext context) {
    return Row(
      // Avoid stretching children vertically inside an unbounded
      // SingleChildScrollView; use `start` so the row doesn't try to
      // expand to infinite height (causes BoxConstraints error).
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _DetailChip(label: 'Crop Name', value: batch.cropName)),
        const SizedBox(width: 10),
        Expanded(child: _DetailChip(label: 'Batch Number', value: batch.batchNumber)),
        const SizedBox(width: 10),
        Expanded(child: _DetailChip(label: 'Available Stock', value: '${batch.availableKg.toStringAsFixed(0)} kg')),
      ],
    );
  }
}

class _DetailChip extends StatelessWidget {
  final String label;
  final String value;
  const _DetailChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppConstants.infoBlueBg.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppConstants.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(),
              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: AppConstants.outline, letterSpacing: 0.6)),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppConstants.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form Card
// ─────────────────────────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController quantityController;
  final TextEditingController priceController;
  final double? maxQty;
  final double? marketPrice;
  final XFile? photo;
  final String? existingPhotoUrl;
  final bool isResubmit;
  final VoidCallback onPickPhoto;
  final VoidCallback onRemovePhoto;
  final VoidCallback onChanged;

  const _FormCard({
    required this.titleController,
    required this.quantityController,
    required this.priceController,
    required this.maxQty,
    required this.marketPrice,
    required this.photo,
    required this.existingPhotoUrl,
    required this.isResubmit,
    required this.onPickPhoto,
    required this.onRemovePhoto,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            boxShadow: [BoxShadow(color: AppConstants.infoBlueFg.withValues(alpha: 0.05), blurRadius: 16)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              const _FieldLabel('Listing Title', optional: true),
              const SizedBox(height: 8),
              TextField(
                controller: titleController,
                onChanged: (_) => onChanged(),
                style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
                decoration: _inputDecoration(hint: 'e.g. Premium Dried Peanut'),
              ),
              const SizedBox(height: 18),

              // Quantity + Price row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('Quantity (kg)'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: quantityController,
                          onChanged: (_) => onChanged(),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                          ],
                          style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
                          decoration: _inputDecoration(hint: '0.00', suffix: 'kg'),
                        ),
                        if (isResubmit) Padding(
                          padding: const EdgeInsets.only(top: 4, left: 2),
                          child: Text('You can adjust this amount before resubmitting.',
                              style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant)),
                        ),
                        if (maxQty != null) Padding(
                          padding: const EdgeInsets.only(top: 4, left: 2),
                          child: Text('Max: ${maxQty!.toStringAsFixed(0)} kg',
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppConstants.outline)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('Asking Price'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: priceController,
                          onChanged: (_) => onChanged(),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                          ],
                          style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
                          decoration: _inputDecoration(hint: '0.00', prefix: '₱', suffix: '/kg'),
                        ),
                        if (marketPrice != null) Padding(
                          padding: const EdgeInsets.only(top: 4, left: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.trending_up_rounded, size: 11, color: AppConstants.warningAmber),
                              const SizedBox(width: 3),
                              Text('Market: ₱${marketPrice!.toStringAsFixed(2)}/kg',
                                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppConstants.warningAmber)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Photo upload
              const _FieldLabel('Product Photo'),
              const SizedBox(height: 8),
              _PhotoUpload(
                photo: photo,
                existingPhotoUrl: existingPhotoUrl,
                onPick: onPickPhoto,
                onRemove: onRemovePhoto,
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint, String? prefix, String? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 14, color: AppConstants.outline.withValues(alpha: 0.50)),
      prefixText: prefix,
      prefixStyle: GoogleFonts.inter(fontSize: 13, color: AppConstants.outline),
      suffixText: suffix,
      suffixStyle: GoogleFonts.inter(fontSize: 12, color: AppConstants.outline),
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
        borderSide: const BorderSide(color: AppConstants.primaryGreen, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool optional;
  const _FieldLabel(this.text, {this.optional = false});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppConstants.onSurfaceVariant),
        children: [
          TextSpan(text: text),
          if (optional)
            TextSpan(text: '  (Optional)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w400, color: AppConstants.outline)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photo Upload
// ─────────────────────────────────────────────────────────────────────────────

// SAGANA is mobile-first — farmers get a choice between photographing the
// crop directly and picking an existing photo, rather than only gallery
// access (the previous behavior).
class _PhotoSourceSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppConstants.outline.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: AppConstants.primaryGreen),
              title: Text('Take Photo', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppConstants.primaryGreen),
              title: Text('Choose from Gallery', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PhotoUpload extends StatelessWidget {
  final XFile? photo;
  final String? existingPhotoUrl;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _PhotoUpload({
    required this.photo,
    required this.existingPhotoUrl,
    required this.onPick,
    required this.onRemove,
  });

  bool get _hasImage => photo != null || (existingPhotoUrl != null && existingPhotoUrl!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    if (_hasImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: 140,
              child: photo != null
                  ? Image.network(photo!.path, fit: BoxFit.cover)
                  : Image.network(existingPhotoUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: AppConstants.infoBlueBg)),
            ),
            Positioned(
              top: 8, right: 8,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.60), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                ),
              ),
            ),
            Positioned(
              bottom: 8, right: 8,
              child: GestureDetector(
                onTap: onPick,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.60), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.edit_rounded, size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('Change', style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onPick,
      child: Container(
        width: double.infinity,
        height: 110,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.50),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppConstants.outline.withValues(alpha: 0.30), width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined, color: AppConstants.primaryGreen, size: 28),
            const SizedBox(height: 6),
            Text('Upload Clear Product Photo',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppConstants.primaryGreen)),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('Adding a clear photo improves your chances of approval.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Preview Card
// ─────────────────────────────────────────────────────────────────────────────

class _LivePreviewCard extends StatelessWidget {
  final String title;
  final String cropName;
  final double quantity;
  final double price;
  final XFile? photo;
  final String? existingPhotoUrl;
  final double estimatedRevenue;

  const _LivePreviewCard({
    required this.title,
    required this.cropName,
    required this.quantity,
    required this.price,
    required this.photo,
    required this.existingPhotoUrl,
    required this.estimatedRevenue,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = photo != null || (existingPhotoUrl != null && existingPhotoUrl!.isNotEmpty);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            boxShadow: [BoxShadow(color: AppConstants.infoBlueFg.withValues(alpha: 0.05), blurRadius: 16)],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 80, height: 80,
                        child: hasImage
                            ? (photo != null
                                ? Image.network(photo!.path, fit: BoxFit.cover)
                                : Image.network(existingPhotoUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder()))
                            : _placeholder(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title.isEmpty ? 'Listing Title' : title,
                                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppConstants.charcoal),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(cropName,
                                  style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                            ],
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Qty: ${quantity.toStringAsFixed(0)} kg',
                                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppConstants.outline)),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text('₱${price.toStringAsFixed(2)}',
                                          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                                      Text(' /kg', style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant)),
                                    ],
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.05),
                  border: Border(top: BorderSide(color: AppConstants.primaryGreen.withValues(alpha: 0.10))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Estimated Total Revenue',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppConstants.onSurfaceVariant)),
                    Text('₱${estimatedRevenue.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppConstants.infoBlueBg,
        child: const Icon(Icons.eco_rounded, color: AppConstants.primaryGreen, size: 30),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// What Happens Next — stepper preview (not yet submitted)
// ─────────────────────────────────────────────────────────────────────────────

class _WhatHappensNextCard extends StatelessWidget {
  final bool isResubmit;
  const _WhatHappensNextCard({required this.isResubmit});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What Happens After You Submit',
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.charcoal),
          ),
          const SizedBox(height: 4),
          Text(
            isResubmit
                ? 'Your updated listing goes back to the cooperative admin for a fresh review.'
                : 'Your listing enters the cooperative admin\'s review queue before it appears to buyers.',
            style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          const StatusStepper(currentStep: -1),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Actions
// ─────────────────────────────────────────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  final bool isOnline;
  final bool isSubmitting;
  final bool isResubmit;
  final bool canSubmit;
  final VoidCallback onSubmit;
  final VoidCallback onViewListings;

  const _BottomActions({
    required this.isOnline,
    required this.isSubmitting,
    required this.isResubmit,
    required this.canSubmit,
    required this.onSubmit,
    required this.onViewListings,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: !isOnline
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppConstants.outline.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off_rounded, color: AppConstants.outline.withValues(alpha: 0.60), size: 20),
                      const SizedBox(width: 8),
                      Text('Go online to submit your listing',
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppConstants.outline.withValues(alpha: 0.70))),
                    ],
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppConstants.primaryGreen, Color(0xFF2E7D32)]),
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    boxShadow: [BoxShadow(color: AppConstants.primaryGreen.withValues(alpha: 0.30), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: ElevatedButton(
                    onPressed: (isSubmitting || !canSubmit) ? null : onSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
                    ),
                    child: isSubmitting
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(isResubmit ? 'Resubmit for Review' : 'Submit for Review',
                                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
                            ],
                          ),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton(
            onPressed: onViewListings,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppConstants.primaryGreen,
              side: const BorderSide(color: AppConstants.primaryGreen),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.list_alt_rounded, size: 18),
                const SizedBox(width: 8),
                Text('View My Listings', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}