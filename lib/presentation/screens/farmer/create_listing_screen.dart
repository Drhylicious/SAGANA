import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_crop_model.dart' show marketTypeLabelFor;
import '../../../data/models/inventory_batch_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';
import 'listing_success_screen.dart' show ListingSuccessArgs;

// FilteringTextInputFormatter.allow with an anchored (^) pattern only ever
// re-validates from the start of the string, via allMatches() — once a
// field already holds a 2-decimal value like "20.00" (as Asking Price does
// immediately after the market-price auto-fill), any further keystroke
// appended after that silently fails to match and gets dropped, even
// though the field is genuinely focused and the cursor blinks normally.
// This formatter instead validates the WHOLE new value on every edit and
// simply rejects the edit (keeping the old value) if it doesn't match —
// the correct pattern for a bounded-decimal field.
class _DecimalInputFormatter extends TextInputFormatter {
  // Optional upper bound — when set (Quantity, bounded by the batch's real
  // available stock), any edit whose parsed value would exceed it is
  // rejected outright instead of being typeable and only clamped later on
  // blur/submit. Price has no such ceiling, so it omits this and keeps its
  // original format-only behavior.
  final double? max;
  const _DecimalInputFormatter({this.max});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(newValue.text)) return oldValue;
    final ceiling = max;
    if (ceiling != null) {
      final parsed = double.tryParse(newValue.text);
      if (parsed != null && parsed > ceiling) return oldValue;
    }
    return newValue;
  }
}

class CreateListingScreen extends StatefulWidget {
  // An InventoryBatchModel (preselected from Manage Inventory's disposal
  // sheet), or null (opened with no preselection).
  final Object? initialArg;

  const CreateListingScreen({super.key, this.initialArg});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _inventoryRepo = InventoryRepository();
  final _listingRepo = ListingRepository();
  final _dashboardRepo = DashboardRepository();

  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  // Select-all-on-focus for both — without this, tapping into a field
  // that's already pre-filled (quantity defaults to the batch's full
  // available stock; price auto-fills from the market reference) places
  // the cursor at the END of the existing text, per Flutter's default
  // focus behavior. Every further keystroke then lands past the decimal
  // formatter's cap and gets correctly rejected, which looks and feels
  // exactly like the field is locked — because there's no way to just tap
  // and type to replace a pre-filled value otherwise. This is the actual,
  // complete fix; the earlier formatter fix alone was correct but not
  // sufficient on its own.
  final _quantityFocusNode = FocusNode();
  final _priceFocusNode = FocusNode();

  List<InventoryBatchModel> _batches = [];
  InventoryBatchModel? _selectedBatch;

  double? _marketPrice;
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
    if (arg is InventoryBatchModel) _batchWasPreselected = true;
    _loadBatches(preselect: arg is InventoryBatchModel ? arg : null);

    _quantityFocusNode.addListener(() => _selectAllOnFocus(_quantityFocusNode, _quantityController));
    _priceFocusNode.addListener(() => _selectAllOnFocus(_priceFocusNode, _priceController));
  }

  void _selectAllOnFocus(FocusNode node, TextEditingController controller) {
    if (node.hasFocus && controller.text.isNotEmpty) {
      controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _quantityFocusNode.dispose();
    _priceFocusNode.dispose();
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

  Future<void> _onBatchSelected(InventoryBatchModel batch) async {
    setState(() {
      _selectedBatch = batch;
      _quantityController.text = batch.availableKg.toStringAsFixed(0);
    });
    final price = await _dashboardRepo.fetchLatestPriceForCrop(
      batch.cropName,
      priceType: batch.cropType,
    );
    if (!mounted) return;
    setState(() {
      _marketPrice = price;
      if (price != null && _priceController.text.isEmpty) {
        _priceController.text = price.toStringAsFixed(2);
      }
    });
  }

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

    if (qty > _selectedBatch!.availableKg) {
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

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description for this listing.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      // Photo is no longer farmer-uploaded here — the Crop Roster is the
      // single source of truth for a crop's image (per explicit product
      // direction), so this is always whatever the selected batch already
      // resolved (InventoryRepository, via fetchFarmerCropImageMap): the
      // farmer's own crop photo if set, else the crop_master catalog
      // photo, else none.
      final photoUrl = _selectedBatch?.displayImageUrl;

      final submittedListing = await _listingRepo.createListing(
        cropName: _selectedBatch!.cropName,
        pricePerKg: price,
        volumeKg: qty,
        inventoryBatchId: _selectedBatch!.id,
        photoUrl: photoUrl,
        description: _descriptionController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      context.pushReplacementRoute(
        AppRoutes.listingSuccess,
        extra: ListingSuccessArgs(
          listing: submittedListing,
          batchNumber: _selectedBatch?.batchNumber,
          marketType: _selectedBatch?.cropType,
          category: _selectedBatch?.category,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      // create_listing_with_reservation raises when the submitted quantity
      // exceeds real available stock, and separately when the crop is
      // Ginger (DA-AMAD-exclusive, sold only through Market Linking) —
      // surface both specifically instead of a generic message, since
      // they're actionable, expected failures rather than network/server
      // errors.
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
                      if (!_batchWasPreselected) ...[
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
                      if (_batchWasPreselected && _selectedBatch != null) ...[
                        const _SectionLabel(number: 1, title: 'What You\'re Selling'),
                        const SizedBox(height: 10),
                        _PreselectedBatchBanner(batch: _selectedBatch!),
                        const SizedBox(height: 24),
                      ],

                      // Auto-filled details
                      if (_selectedBatch != null) ...[
                        _AutoFilledGrid(batch: _selectedBatch!),
                        const SizedBox(height: 24),
                      ],

                      // ── Section 2: Price & quantity ─────────────────────
                      const _SectionLabel(number: 2, title: 'Set Your Price & Quantity'),
                      const SizedBox(height: 10),
                      _FormCard(
                        cropName: _selectedBatch?.cropName ?? '',
                        photoUrl: _selectedBatch?.displayImageUrl,
                        quantityController: _quantityController,
                        priceController: _priceController,
                        descriptionController: _descriptionController,
                        quantityFocusNode: _quantityFocusNode,
                        priceFocusNode: _priceFocusNode,
                        maxQty: _selectedBatch?.availableKg,
                        marketPrice: _marketPrice,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 24),

                      // ── Section 3: Preview ───────────────────────────────
                      const _SectionLabel(number: 3, title: 'Review Before Submitting'),
                      const SizedBox(height: 10),
                      _LivePreviewCard(
                        cropName: _selectedBatch?.cropName ?? '',
                        photoUrl: _selectedBatch?.displayImageUrl,
                        quantity: double.tryParse(_quantityController.text.trim()) ?? 0,
                        price: double.tryParse(_priceController.text.trim()) ?? 0,
                        estimatedRevenue: _estimatedRevenue,
                      ),
                      const SizedBox(height: 20),

                      // ── What happens next preview ───────────────────────
                      const _WhatHappensNextCard(),
                      const SizedBox(height: 24),

                      // Bottom actions
                      _BottomActions(
                        isOnline: _isOnline,
                        isSubmitting: _isSubmitting,
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
              title: 'Create Listing',
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
    // Was a 2-row/2-col grid with Category left alone on its own row below
    // (nothing to pair it with) — that orphaned row was exactly what read
    // as uneven. A single horizontally-scrollable row of consistently-
    // sized chips fixes both the unevenness and the cramping a 4-in-a-row
    // fixed layout ran into once Market Type's longer label was added.
    final chips = <Widget>[
      _DetailChip(label: 'Crop Name', value: batch.cropName),
      if (batch.category != null) _DetailChip(label: 'Category', value: batch.category!),
      _DetailChip(label: 'Market Type', value: marketTypeLabelFor(batch.cropType)),
      _DetailChip(label: 'Batch Number', value: batch.batchNumber),
      _DetailChip(label: 'Available Stock', value: '${batch.availableKg.toStringAsFixed(0)} kg'),
    ];
    return SizedBox(
      // 64 clipped the two-line chip content by ~1px on some font metrics
      // (Column's mainAxisAlignment: center leaves no slack once padding
      // is subtracted) — a few extra px of headroom fixes it outright
      // rather than trimming padding/font size to fit exactly.
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => chips[i],
      ),
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
      width: 118,
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
  final String cropName;
  final String? photoUrl;
  final TextEditingController quantityController;
  final TextEditingController priceController;
  final TextEditingController descriptionController;
  final FocusNode quantityFocusNode;
  final FocusNode priceFocusNode;
  final double? maxQty;
  final double? marketPrice;
  final VoidCallback onChanged;

  const _FormCard({
    required this.cropName,
    required this.photoUrl,
    required this.quantityController,
    required this.priceController,
    required this.descriptionController,
    required this.quantityFocusNode,
    required this.priceFocusNode,
    required this.maxQty,
    required this.marketPrice,
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
              // Title — locked, always the selected crop's own name. Not a
              // farmer-editable field: per explicit product direction, the
              // listing title must reflect exactly what was selected in
              // Step 1, never a disconnected value a farmer typed in.
              const _FieldLabel('Listing Title'),
              const SizedBox(height: 8),
              _LockedField(value: cropName),
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
                          focusNode: quantityFocusNode,
                          onChanged: (_) => onChanged(),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [_DecimalInputFormatter(max: maxQty)],
                          style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
                          decoration: _inputDecoration(hint: '0.00', suffix: 'kg'),
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
                          focusNode: priceFocusNode,
                          onChanged: (_) => onChanged(),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [_DecimalInputFormatter()],
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

              // Description — required, per-listing copy the farmer
              // writes fresh each time (not a catalog-level description
              // shared across every listing of that crop). Shown to
              // buyers on Listing Details and to the farmer on their own
              // listing detail / Submission Success screens.
              Row(
                children: [
                  const _FieldLabel('Description'),
                  const SizedBox(width: 4),
                  Text('*',
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.errorRed)),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descriptionController,
                onChanged: (_) => onChanged(),
                minLines: 3,
                maxLines: 5,
                maxLength: 300,
                style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
                decoration: _inputDecoration(
                  hint: 'Describe your product — quality, sourcing, sun-dried, etc.',
                ).copyWith(counterStyle: GoogleFonts.inter(fontSize: 10, color: AppConstants.outline)),
              ),
              const SizedBox(height: 4),

              // Photo — locked, sourced from the Crop Roster via the
              // selected batch. No upload control: per explicit product
              // direction, a listing must never carry a different image
              // than the crop's own registered photo, to avoid
              // inconsistent product images across the system.
              const _FieldLabel('Product Photo'),
              const SizedBox(height: 8),
              _PhotoPreview(photoUrl: photoUrl),
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
// Locked Field — read-only display for a value derived from the selected crop
// ─────────────────────────────────────────────────────────────────────────────

class _LockedField extends StatelessWidget {
  final String value;
  const _LockedField({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppConstants.outline.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.outline.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, size: 16, color: AppConstants.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photo Preview — read-only, sourced from the selected batch's crop image
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoPreview extends StatelessWidget {
  final String? photoUrl;
  const _PhotoPreview({required this.photoUrl});

  bool get _hasImage => photoUrl != null && photoUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: double.infinity,
        height: 140,
        child: _hasImage
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppConstants.infoBlueBg,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.eco_rounded, color: AppConstants.primaryGreen, size: 28),
            const SizedBox(height: 6),
            Text(
              'No photo available',
              style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Preview Card
// ─────────────────────────────────────────────────────────────────────────────

class _LivePreviewCard extends StatelessWidget {
  final String cropName;
  final String? photoUrl;
  final double quantity;
  final double price;
  final double estimatedRevenue;

  const _LivePreviewCard({
    required this.cropName,
    required this.photoUrl,
    required this.quantity,
    required this.price,
    required this.estimatedRevenue,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = photoUrl != null && photoUrl!.isNotEmpty;

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
                            ? Image.network(photoUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
                            : _placeholder(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(cropName.isEmpty ? 'Listing Title' : cropName,
                              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppConstants.charcoal),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
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
  const _WhatHappensNextCard();

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
            'Your listing enters the cooperative admin\'s review queue before it appears to buyers.',
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
  final bool canSubmit;
  final VoidCallback onSubmit;
  final VoidCallback onViewListings;

  const _BottomActions({
    required this.isOnline,
    required this.isSubmitting,
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
                              Text('Submit for Review',
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
                Text('View Listing', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}