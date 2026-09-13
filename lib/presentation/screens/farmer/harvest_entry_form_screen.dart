import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/repositories/harvest_entry_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

class HarvestEntryFormScreen extends StatefulWidget {
  final FarmerCropModel? crop; // optional pre-fill from My Crops' shortcut
  const HarvestEntryFormScreen({super.key, this.crop});

  @override
  State<HarvestEntryFormScreen> createState() =>
      _HarvestEntryFormScreenState();
}

class _HarvestEntryFormScreenState extends State<HarvestEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _varietyController = TextEditingController();
  final _storageController = TextEditingController();
  final _notesController = TextEditingController();
  final _repo = HarvestEntryRepository();
  final _cropRepo = CropRepository();

  List<FarmerCropModel> _myCrops = [];
  FarmerCropModel? _selectedCrop;
  FarmerCropModel? _blockedCrop;
  bool _isLoadingCrops = true;
  String? _previewBatchNumber;

  DateTime _harvestDate = DateTime.now();
  bool _isLoading = false;
  bool _isSuccess = false;
  String? _errorMessage;
  bool _isOnline = true;
  bool _loadFailed = false;

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
    _loadCrops();
  }

  Future<void> _loadCrops() async {
    setState(() {
      _isLoadingCrops = true;
      _loadFailed = false;
    });
    List<FarmerCropModel> crops;
    try {
      crops = await _cropRepo
          .fetchCrops(approvedOnly: true)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingCrops = false;
        _loadFailed = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _myCrops = crops;
      // Pre-fill from the shortcut if one was passed; otherwise auto-select
      // when there's only one crop to begin with — one less tap for the
      // common case of a farmer who grows a single crop.
      //
      // Resolve widget.crop to the matching instance from this fresh fetch
      // (by id) rather than using the passed-in object directly — the
      // dropdown's items list is built from `crops`, so its initialValue
      // must be one of those exact instances or DropdownButtonFormField's
      // "exactly one matching item" assertion fails. (FarmerCropModel now
      // also has value equality by id, so this is a defensive backstop.)
      if (widget.crop != null) {
        final match = crops.where((c) => c.id == widget.crop!.id);
        if (match.isNotEmpty) {
          _selectedCrop = match.first;
          _blockedCrop = null;
        } else {
          // The crop that was passed in isn't in the approved list —
          // either still pending or rejected. Don't silently fall back
          // to using it; surface that plainly instead.
          _selectedCrop = null;
          _blockedCrop = widget.crop;
        }
      } else if (crops.length == 1) {
        _selectedCrop = crops.first;
      } else {
        _selectedCrop = null;
      }
      _previewBatchNumber =
          _selectedCrop != null ? _generateBatchNumber(_selectedCrop!) : null;
      _isLoadingCrops = false;
    });
  }

  void _onCropChanged(FarmerCropModel crop) {
    setState(() {
      _selectedCrop = crop;
      _previewBatchNumber = _generateBatchNumber(crop);
    });
  }

  String _generateBatchNumber(FarmerCropModel crop) {
    final code = crop.cropName.length >= 4
        ? crop.cropName.substring(0, 4).toUpperCase()
        : crop.cropName.toUpperCase();
    return AppUtils.generateBatchNumber(code);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _varietyController.dispose();
    _storageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _harvestDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppConstants.primaryGreen,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _harvestDate = picked);
  }

  Future<void> _handleSubmit() async {
    setState(() => _errorMessage = null);
    if (_selectedCrop == null) {
      setState(() => _errorMessage = _blockedCrop != null
          ? '${_blockedCrop!.cropName} is still awaiting admin approval and can\'t be harvested yet.'
          : 'Please select a crop.');
      return;
    }
    if (_selectedCrop!.isPendingApproval) {
      setState(() => _errorMessage = 'This crop is still awaiting admin approval and can\'t be harvested yet.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final qty = double.tryParse(_quantityController.text.trim());
    if (qty == null || qty <= 0) {
      setState(() => _errorMessage = 'Please enter a valid quantity.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      // Reuse the number already shown in the form's read-only Batch
      // Number field instead of regenerating — AppUtils.generateBatchNumber()
      // embeds a millisecond-based random suffix, so a second call here
      // produced a different value than what the farmer saw and confirmed.
      final batchNumber = _previewBatchNumber!;
      final harvest = await _repo.submitHarvest(
        cropId: _selectedCrop!.id,
        cropName: _selectedCrop!.cropName,
        cropCategory: _selectedCrop!.category,
        quantityKg: qty,
        harvestDate: _harvestDate,
        batchNumber: batchNumber,
        variety: _varietyController.text.trim().isEmpty
            ? null
            : _varietyController.text.trim(),
        storageLocation: _storageController.text.trim().isEmpty
            ? null
            : _storageController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      AppEventService.instance.notifyHarvestRecorded();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isSuccess = true;
      });

      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        _showSuccessDialog(qty, batchNumber, wasQueuedOffline: !harvest.isSynced);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Failed to submit harvest. Please check your connection and try again.';
      });
    }
  }

  void _showSuccessDialog(double qty, String batchNumber, {required bool wasQueuedOffline}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: (wasQueuedOffline ? AppConstants.amber : AppConstants.successGreen)
                    .withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                wasQueuedOffline ? Icons.cloud_off_rounded : Icons.check_circle_rounded,
                color: wasQueuedOffline ? AppConstants.amber : AppConstants.successGreen,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              wasQueuedOffline ? 'Saved Offline' : 'Harvest Submitted!',
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: AppConstants.charcoal),
            ),
            const SizedBox(height: 8),
            Text(
              wasQueuedOffline
                  ? '${qty.toStringAsFixed(0)} kg of ${_selectedCrop!.cropName} recorded '
                    '(Batch #$batchNumber).\n\nNo connection right now — this will sync '
                    'automatically once you\'re back online.'
                  : '${qty.toStringAsFixed(0)} kg of ${_selectedCrop!.cropName} recorded '
                    '(Batch #$batchNumber).\n\nCheck Inventory to sell, offer it '
                    'to the cooperative, or record a sale.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppConstants.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text('Done',
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingCrops) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(
            color: AppConstants.primaryGreen)),
      );
    }

    if (_loadFailed) {
      return _CropsLoadError(onRetry: _loadCrops, isOnline: _isOnline);
    }

    if (_myCrops.isEmpty) {
      if (_blockedCrop != null) {
        // The farmer's only crop is the one that was passed in, and it's
        // not approved yet — the generic "you have no crops" message would
        // be misleading here, since they do have one, it just isn't usable.
        return _PendingCropBlockedState(
          cropName: _blockedCrop!.cropName,
          onGoToMyCrops: () => context.pushRoute(AppRoutes.cropListing),
        );
      }
      return _NoCropsEmptyState(
        onGoToMyCrops: () => context.pushRoute(AppRoutes.cropListing),
      );
    }

    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 72),
              if (!_isOnline)
                const OfflineBanner(
                  message:
                      "You're offline — new harvest entries are saved on your device and will sync automatically once you're reconnected.",
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Blocked-crop banner — shown when the crop passed
                        // in via the shortcut isn't approved yet. The farmer
                        // can still pick a different approved crop below.
                        if (_blockedCrop != null) ...[
                          _PendingCropBanner(cropName: _blockedCrop!.cropName),
                          const SizedBox(height: 16),
                        ],
                        // Crop selector — now the first field, not a fixed header
                        _CropSelectorField(
                          crops: _myCrops,
                          selected: _selectedCrop,
                          onChanged: _onCropChanged,
                        ),
                        const SizedBox(height: 20),

                        // ── Quantity ──────────────────────────────────────
                        _QuantityField(controller: _quantityController),
                        const SizedBox(height: 20),

                        // ── Variety ───────────────────────────────────────
                        const _FieldLabel('Variety (Optional)'),
                        const SizedBox(height: 8),
                        _SimpleTextField(
                          controller: _varietyController,
                          hint: 'e.g. IR64, Sinandomeng',
                          icon: Icons.spa_outlined,
                        ),
                        const SizedBox(height: 16),

                        // ── Batch Number ──────────────────────────────────
                        const _FieldLabel('Batch Number'),
                        const SizedBox(height: 8),
                        _BatchNumberField(
                            batchNumber: _previewBatchNumber ?? '—'),
                        const SizedBox(height: 16),

                        // ── Harvest Date ──────────────────────────────────
                        const _FieldLabel('Harvest Date'),
                        const SizedBox(height: 8),
                        _DateField(date: _harvestDate, onTap: _pickDate),
                        const SizedBox(height: 16),

                        // ── Storage Location ──────────────────────────────
                        const _FieldLabel('Storage Location'),
                        const SizedBox(height: 8),
                        _SimpleTextField(
                          controller: _storageController,
                          hint: 'e.g. Bodega 1, Home Storage',
                          icon: Icons.location_on_outlined,
                        ),
                        const SizedBox(height: 16),

                        // ── Notes ─────────────────────────────────────────
                        const _FieldLabel('Notes'),
                        const SizedBox(height: 8),
                        _NotesField(controller: _notesController),
                        const SizedBox(height: 16),

                        // ── Error ─────────────────────────────────────────
                        if (_errorMessage != null) _ErrorBanner(message: _errorMessage!),

                        // ── Submit Button ─────────────────────────────────
                        const SizedBox(height: 24),
                        _SubmitButton(
                          isLoading: _isLoading,
                          isSuccess: _isSuccess,
                          onPressed: _handleSubmit,
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
            top: 0, left: 0, right: 0,
            child: FarmerTopBar(
              title: _selectedCrop?.cropName ?? 'Record Harvest',
              onBack: () => Navigator.of(context).pop(),
              profilePhotoUrl: null,
              onProfileTap: () {},
              onNotificationTap: () => context.pushRoute(AppRoutes.farmerNotifications),
              onSettingsTap: null,
              // trailing badge removed; use the standardized OfflineBanner above
            ),
          ),

        ],
      ),
    );
  }
}


// _OnlineBadge and _PulsingDot removed — standardized OfflineBanner is used instead

// ─────────────────────────────────────────────────────────────────────────────
// Crop Selector Field
// ─────────────────────────────────────────────────────────────────────────────

class _CropSelectorField extends StatelessWidget {
  final List<FarmerCropModel> crops;
  final FarmerCropModel? selected;
  final ValueChanged<FarmerCropModel> onChanged;

  const _CropSelectorField({
    required this.crops,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('Crop',
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w500,
                  color: AppConstants.charcoal)),
        ),
        DropdownButtonFormField<FarmerCropModel>(
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(Icons.eco_outlined,
                size: 20, color: AppConstants.outline),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              borderSide: BorderSide(
                  color: AppConstants.outline.withValues(alpha: 0.20)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              borderSide: BorderSide(
                  color: AppConstants.outline.withValues(alpha: 0.20)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              borderSide: const BorderSide(
                  color: AppConstants.primaryContainer, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
          ),
          hint: Text('Select a crop',
              style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppConstants.outline.withValues(alpha: 0.60))),
          items: crops.map((crop) => DropdownMenuItem(
            value: crop,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(crop.cropName, style: GoogleFonts.inter(fontSize: 14)),
                if (crop.isPendingApproval) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppConstants.warningAmber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                    ),
                    child: Text('Pending',
                        style: GoogleFonts.inter(
                            fontSize: 10, color: AppConstants.warningAmber)),
                  ),
                ],
              ],
            ),
          )).toList(),
          validator: (v) => v == null ? 'Please select a crop' : null,
          onChanged: (crop) { if (crop != null) onChanged(crop); },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// No Crops Empty State
// ─────────────────────────────────────────────────────────────────────────────

// ───────────────────────────────────────────────────────────────────────────────
// Crops Load Error — shown when fetchCrops() fails or times out, instead of
// falling through to _NoCropsEmptyState (which would misleadingly imply the
// farmer has no crops at all). Message/icon distinguish "you're offline"
// from a genuine load failure, matching _ProfileLoadError's pattern.
// ───────────────────────────────────────────────────────────────────────────────

class _CropsLoadError extends StatelessWidget {
  final VoidCallback onRetry;
  final bool isOnline;
  const _CropsLoadError({required this.onRetry, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOnline ? Icons.error_outline_rounded : Icons.wifi_off_rounded,
                size: 40,
                color: AppConstants.outline.withValues(alpha: 0.60),
              ),
              const SizedBox(height: 12),
              Text(
                isOnline ? 'Could not load your crops' : 'You\'re offline',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.charcoal,
                ),
              ),
              if (!isOnline) ...[
                const SizedBox(height: 4),
                Text(
                  'Your crops will load once you\'re back online.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppConstants.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: onRetry,
                child: Text(
                  'Retry',
                  style: GoogleFonts.poppins(color: AppConstants.primaryGreen),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoCropsEmptyState extends StatelessWidget {
  final VoidCallback onGoToMyCrops;
  const _NoCropsEmptyState({required this.onGoToMyCrops});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.08),
                    shape: BoxShape.circle),
                child: const Icon(Icons.eco_outlined,
                    size: 40, color: AppConstants.primaryGreen),
              ),
              const SizedBox(height: 20),
              Text("You don't have any crops yet",
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: AppConstants.charcoal)),
              const SizedBox(height: 8),
              Text(
                'Add a crop from the cooperative\'s list before recording a harvest.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 13, color: AppConstants.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onGoToMyCrops,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
                ),
                child: Text('Go to My Crops',
                    style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Pending Crop Blocked State — shown instead of _NoCropsEmptyState when
// the farmer's only crop is the one passed in and it isn't approved yet.
// ───────────────────────────────────────────────────────────────────────────────

class _PendingCropBlockedState extends StatelessWidget {
  final String cropName;
  final VoidCallback onGoToMyCrops;
  const _PendingCropBlockedState({
    required this.cropName,
    required this.onGoToMyCrops,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                    color: AppConstants.amber.withValues(alpha: 0.10),
                    shape: BoxShape.circle),
                child: const Icon(Icons.hourglass_top_rounded,
                    size: 40, color: AppConstants.amber),
              ),
              const SizedBox(height: 20),
              Text('$cropName is still awaiting approval',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: AppConstants.charcoal)),
              const SizedBox(height: 8),
              Text(
                'You can record a harvest once the cooperative approves this crop.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 13, color: AppConstants.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onGoToMyCrops,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
                ),
                child: Text('Go to My Crops',
                    style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Pending Crop Banner — inline warning shown above the crop selector when
// the crop passed in via a shortcut isn't approved yet, but the farmer has
// other approved crops to choose from instead.
// ───────────────────────────────────────────────────────────────────────────────

class _PendingCropBanner extends StatelessWidget {
  final String cropName;
  const _PendingCropBanner({required this.cropName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppConstants.amber.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, size: 18, color: AppConstants.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$cropName is still awaiting admin approval and can\'t be harvested yet. '
              'Pick another crop below, or go back once it\'s approved.',
              style: GoogleFonts.inter(fontSize: 13, color: AppConstants.amber),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quantity Field
// ─────────────────────────────────────────────────────────────────────────────

class _QuantityField extends StatelessWidget {
  final TextEditingController controller;
  const _QuantityField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Quantity (kg)*'),
        const SizedBox(height: 8),
        Stack(
          alignment: Alignment.centerRight,
          children: [
            TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: GoogleFonts.poppins(
                  fontSize: 36, fontWeight: FontWeight.w700,
                  color: AppConstants.primaryGreen),
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: GoogleFonts.poppins(
                    fontSize: 36, fontWeight: FontWeight.w700,
                    color: AppConstants.outline.withValues(alpha: 0.30)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 20, horizontal: 48),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  borderSide: BorderSide(
                      color: AppConstants.outline.withValues(alpha: 0.20), width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  borderSide: BorderSide(
                      color: AppConstants.outline.withValues(alpha: 0.20), width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  borderSide: const BorderSide(
                      color: AppConstants.primaryContainer, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  borderSide: const BorderSide(
                      color: AppConstants.errorRed, width: 2),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Quantity is required';
                final qty = double.tryParse(v);
                if (qty == null || qty <= 0) return 'Enter a valid quantity';
                return null;
              },
            ),
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Text('KG',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: AppConstants.outline)),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch Number Field
// ─────────────────────────────────────────────────────────────────────────────

class _BatchNumberField extends StatelessWidget {
  final String batchNumber;
  const _BatchNumberField({required this.batchNumber});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        TextFormField(
          initialValue: batchNumber,
          readOnly: true,
          style: GoogleFonts.inter(
              fontSize: 13, color: AppConstants.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()]),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFE6F6FF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              borderSide: BorderSide(
                  color: AppConstants.outline.withValues(alpha: 0.20)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              borderSide: BorderSide(
                  color: AppConstants.outline.withValues(alpha: 0.20)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              borderSide: BorderSide(
                  color: AppConstants.outline.withValues(alpha: 0.20)),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(right: 14),
          child: Icon(Icons.lock_outline_rounded,
              size: 18, color: AppConstants.outline),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date Field
// ─────────────────────────────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;

  const _DateField({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
              color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(DateFormat('MMMM d, yyyy').format(date),
                  style: GoogleFonts.inter(
                      fontSize: 14, color: AppConstants.onSurface)),
            ),
            const Icon(Icons.calendar_today_rounded,
                size: 18, color: AppConstants.primaryGreen),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Simple Text Field
// ─────────────────────────────────────────────────────────────────────────────

class _SimpleTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;

  const _SimpleTextField({
    required this.controller,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
            fontSize: 14,
            color: AppConstants.outline.withValues(alpha: 0.50)),
        suffixIcon: Icon(icon, size: 20, color: AppConstants.primaryGreen),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
              color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
              color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(
              color: AppConstants.primaryContainer, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notes Field
// ─────────────────────────────────────────────────────────────────────────────

class _NotesField extends StatelessWidget {
  final TextEditingController controller;
  const _NotesField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: 3,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: InputDecoration(
        hintText: 'Describe crop conditions, humidity, weather, etc.',
        hintStyle: GoogleFonts.inter(
            fontSize: 14,
            color: AppConstants.outline.withValues(alpha: 0.50)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
              color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
              color: AppConstants.outline.withValues(alpha: 0.20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(
              color: AppConstants.primaryContainer, width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Field Label
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w500,
              color: AppConstants.onSurfaceVariant)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error Banner
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppConstants.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
            color: AppConstants.errorRed.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppConstants.errorRed),
          const SizedBox(width: 10),
          Expanded(child: Text(message,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppConstants.errorRed))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Submit Button
// ─────────────────────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final bool isLoading;
  final bool isSuccess;
  final VoidCallback onPressed;

  const _SubmitButton({
    required this.isLoading,
    required this.isSuccess,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: isSuccess
                ? [AppConstants.successGreen, AppConstants.successGreen]
                : [AppConstants.primaryGreen, AppConstants.primaryContainer],
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          boxShadow: [
            BoxShadow(
              color: AppConstants.primaryGreen.withValues(alpha: 0.30),
              blurRadius: 24, offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: (isLoading || isSuccess) ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
              : Text(
                  isSuccess ? 'Submitted!' : 'Submit Harvest',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w500,
                      color: Colors.white)),
        ),
      ),
    );
  }
}