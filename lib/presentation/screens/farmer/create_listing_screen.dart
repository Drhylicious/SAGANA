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
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});

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
  bool _argsRead = false;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsRead) {
      _argsRead = true;
      final arg = ModalRoute.of(context)?.settings.arguments;
      if (arg is MarketplaceListingModel) {
        _editingListing = arg;
        _titleController.text = arg.displayName;
        _quantityController.text = arg.volumeKg.toStringAsFixed(0);
        _priceController.text = arg.pricePerKg.toStringAsFixed(2);
      }
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
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
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
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.listingSuccess,
        arguments: submittedListing,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit listing. Please try again.')),
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
      body: Stack(
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
                      const SizedBox(height: 20),

                      // Batch source selector
                      if (_editingListing == null) ...[
                        Text('Select Batch Source',
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppConstants.onSurfaceVariant)),
                        const SizedBox(height: 10),
                        _isLoadingBatches
                            ? const SizedBox(height: 110, child: Center(child: CircularProgressIndicator(color: AppConstants.primaryGreen)))
                            : _batches.isEmpty
                                ? _NoBatchesNotice(onGoToInventory: () =>
                                    Navigator.of(context).pushReplacementNamed(AppRoutes.manageInventory))
                                : _BatchSelector(
                                    batches: _batches,
                                    selected: _selectedBatch,
                                    onSelected: _onBatchSelected,
                                  ),
                        const SizedBox(height: 20),
                      ],

                      // Auto-filled details
                      if (_selectedBatch != null) ...[
                        _AutoFilledGrid(batch: _selectedBatch!),
                        const SizedBox(height: 20),
                      ],

                      // Form card
                      _FormCard(
                        titleController: _titleController,
                        quantityController: _quantityController,
                        priceController: _priceController,
                        maxQty: _selectedBatch?.availableKg,
                        marketPrice: _marketPrice,
                        photo: _photo,
                        existingPhotoUrl: _editingListing?.photoUrl,
                        onPickPhoto: _pickPhoto,
                        onRemovePhoto: _removePhoto,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 20),

                      // Live preview
                      _LivePreviewCard(
                        title: _titleController.text.trim().isEmpty
                            ? (_selectedBatch?.cropName ?? '')
                            : _titleController.text.trim(),
                        cropName: _selectedBatch?.cropName ?? '',
                        grade: _selectedBatch?.qualityGrade ?? 'Grade A',
                        quantity: double.tryParse(_quantityController.text.trim()) ?? 0,
                        price: double.tryParse(_priceController.text.trim()) ?? 0,
                        photo: _photo,
                        existingPhotoUrl: _editingListing?.photoUrl,
                        estimatedRevenue: _estimatedRevenue,
                      ),
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
              profilePhotoUrl: null,
              onProfileTap: () {},
                onNotificationTap: () => context.pushRoute(AppRoutes.farmerNotifications),
              onSettingsTap: null,
            ),
          ),
        ],
      ),
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
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.verified_outlined, size: 12, color: AppConstants.outline),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(batch.qualityGrade,
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
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: [
        _DetailChip(label: 'Crop Name', value: batch.cropName),
        _DetailChip(label: 'Batch Number', value: batch.batchNumber),
        _DetailChip(label: 'Quality', value: batch.qualityGrade),
        _DetailChip(label: 'Available Stock', value: '${batch.availableKg.toStringAsFixed(0)} kg'),
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
        color: const Color(0xFFDBF1FE).withValues(alpha: 0.30),
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
            boxShadow: [BoxShadow(color: const Color(0xFF455A64).withValues(alpha: 0.05), blurRadius: 16)],
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
                          onChanged: (_) => onChanged(),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                      errorBuilder: (_, __, ___) => Container(color: const Color(0xFFDBF1FE))),
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
  final String grade;
  final double quantity;
  final double price;
  final XFile? photo;
  final String? existingPhotoUrl;
  final double estimatedRevenue;

  const _LivePreviewCard({
    required this.title,
    required this.cropName,
    required this.grade,
    required this.quantity,
    required this.price,
    required this.photo,
    required this.existingPhotoUrl,
    required this.estimatedRevenue,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = photo != null || (existingPhotoUrl != null && existingPhotoUrl!.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Live Preview', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppConstants.onSurfaceVariant)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.70),
                borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
                boxShadow: [BoxShadow(color: const Color(0xFF455A64).withValues(alpha: 0.05), blurRadius: 16)],
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
                                  Text('$cropName • $grade',
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
        ),
      ],
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFFDBF1FE),
        child: const Icon(Icons.eco_rounded, color: AppConstants.primaryGreen, size: 30),
      );
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
