import '../../../core/theme/sagana_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/db_error_utils.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/farmer_crop_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/repositories/harvest_entry_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/add_unit_dialog.dart';
import '../../widgets/quantity_unit_field.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/channel_only_badge.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../../core/l10n/app_localizations.dart';

class HarvestEntryFormScreen extends StatefulWidget {
  final FarmerCropModel? crop; // optional pre-fill from Crop Roster's shortcut
  const HarvestEntryFormScreen({super.key, this.crop});

  @override
  State<HarvestEntryFormScreen> createState() => _HarvestEntryFormScreenState();
}

class _HarvestEntryFormScreenState extends State<HarvestEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _repo = HarvestEntryRepository();
  final _cropRepo = CropRepository();
  final _unitRepo = UnitRepository();

  List<FarmerCropModel> _myCrops = [];
  FarmerCropModel? _selectedCrop;
  FarmerCropModel? _blockedCrop;
  bool _isLoadingCrops = true;

  // The units come from the same public.units list Inventory Management and
  // Price Management use, so a unit the Manager adds there appears here with no
  // app change. The farmer must choose one (no default), for every crop: a crop
  // reserved for one selling channel (Ginger) is no longer fixed to kg, because
  // the harvest's unit is the one source for every selling channel.
  List<String> _units = [];
  String? _selectedUnit;
  final String _selectedStorageLocation =
      AppConstants.harvestStorageLocations.first;

  DateTime _harvestDate = DateTime.now();
  bool _isLoading = false;
  bool _isSuccess = false;
  String? _errorMessage;
  bool _isOnline = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
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
    _loadCrops();
  }

  Future<void> _loadCrops() async {
    setState(() {
      _isLoadingCrops = true;
      _loadFailed = false;
    });
    List<FarmerCropModel> crops;
    List<String> units;
    try {
      final results = await Future.wait([
        _cropRepo
            .fetchCrops(approvedOnly: true)
            .timeout(const Duration(seconds: 15)),
        _unitRepo.fetchUnits(),
      ]);
      crops = results[0] as List<FarmerCropModel>;
      units = results[1] as List<String>;
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
      _units = units;
      _selectedUnit = null;
      _isLoadingCrops = false;
    });
  }

  // "+ Unit": the same dialog, validation and save Price Management and
  // Inventory Management use. The new unit joins the list at once and is
  // selected (the dropdown selects whatever this returns), no reload needed.
  Future<String?> _addUnit() async {
    final added = await promptAddUnit(
      context,
      repo: _unitRepo,
      existing: _units,
    );
    if (added == null || !mounted) return null;
    setState(() {
      if (!_units.contains(added)) _units = [..._units, added];
    });
    return added;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    // firstDate deliberately far in the past rather than a recent literal
    // year (e.g. 2020) — a fixed near-term floor silently cuts off older
    // historical harvest data as time passes. lastDate stays DateTime.now(),
    // which is itself re-evaluated on every open, so the upper bound already
    // advances automatically with no hardcoded year on that side either.
    final picked = await showDatePicker(
      context: context,
      initialDate: _harvestDate,
      // The database numbers a batch with a 2-digit year and refuses a harvest
      // date outside 2000-2099, so the picker starts at 2000.
      firstDate: DateTime(2000),
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

  /// The harvest date entered is already beyond the crop's default shelf life
  /// (harvest date + shelf life is before today). The harvest can still be
  /// recorded; it just cannot be sold until the Farmer confirms the produce.
  bool _harvestIsPastShelfLife(FarmerCropModel crop) {
    final days = crop.shelfLifeDays;
    if (days == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expires = DateTime(
      _harvestDate.year,
      _harvestDate.month,
      _harvestDate.day,
    ).add(Duration(days: days));
    return expires.isBefore(today);
  }

  Future<void> _handleSubmit() async {
    setState(() => _errorMessage = null);
    if (_selectedCrop == null) {
      setState(
        () => _errorMessage = _blockedCrop != null
            ? AppLocalizations.of(
                context,
              ).enhIsStillAwaitingManagerApprovalAndCanT(
                (_blockedCrop!.cropName).toString(),
              )
            : AppLocalizations.of(context).enhPleaseSelectACrop,
      );
      return;
    }
    if (_selectedCrop!.isPendingApproval) {
      setState(
        () => _errorMessage = AppLocalizations.of(
          context,
        ).enhThisCropIsStillAwaitingManagerApprovalAnd,
      );
      return;
    }
    // Quantity and Unit show their own message under their own field.
    if (!_formKey.currentState!.validate()) return;

    final qty = parseDecimal(_quantityController.text);
    final unit = _selectedUnit;
    if (qty == null || unit == null) return; // validate() already said why

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      // The batch number is issued by the database when the harvest is saved,
      // so it is read back from the saved row. A harvest saved offline has
      // none yet: it is numbered when it syncs.
      final harvest = await _repo.submitHarvest(
        cropId: _selectedCrop!.id,
        cropName: _selectedCrop!.cropName,
        cropCategory: _selectedCrop!.category,
        quantityKg: qty,
        unit: unit,
        harvestDate: _harvestDate,
        storageLocation: _selectedStorageLocation,
      );

      AppEventService.instance.notifyHarvestRecorded();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isSuccess = true;
      });

      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        _showSuccessDialog(
          qty,
          unit,
          formatBatchNumber(harvest.batchNumber),
          wasQueuedOffline: !harvest.isSynced,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        // The database's own sentence when it wrote one for people (for
        // example an unknown unit or a harvest date it refuses); otherwise
        // the generic connection message.
        _errorMessage =
            readableDatabaseMessage(e) ??
            AppLocalizations.of(
              context,
            ).enhFailedToSubmitHarvestPleaseCheckYourConnection;
      });
    }
  }

  void _showSuccessDialog(
    double qty,
    String unit,
    String batchNumber, {
    required bool wasQueuedOffline,
  }) {
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
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color:
                    (wasQueuedOffline
                            ? AppConstants.amber
                            : AppConstants.successGreen)
                        .withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                wasQueuedOffline
                    ? Icons.cloud_off_rounded
                    : Icons.check_circle_rounded,
                color: wasQueuedOffline
                    ? AppConstants.amber
                    : AppConstants.successGreen,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              wasQueuedOffline
                  ? AppLocalizations.of(context).enhSavedOffline
                  : AppLocalizations.of(context).enhHarvestSubmitted,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              wasQueuedOffline
                  ? AppLocalizations.of(
                      context,
                    ).enhOfRecordedNoConnectionRightNowThisWill(
                      (formatQuantityUnit(qty, unit)).toString(),
                      (_selectedCrop!.cropName).toString(),
                    )
                  : AppLocalizations.of(
                      context,
                    ).enhOfRecordedCheckInventoryToSellOfferIt(
                      (formatQuantityUnit(qty, unit)).toString(),
                      (_selectedCrop!.cropName).toString(),
                      (batchNumber).toString(),
                    ),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
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
            child: Text(
              AppLocalizations.of(context).buyerCartDone,
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

  @override
  Widget build(BuildContext context) {
    if (_isLoadingCrops) {
      return Scaffold(
        body: Stack(
          children: [
            const Column(
              children: [
                TopBarSpacer(height: 72),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FarmerTopBar(
                title: '',
                onBack: () => Navigator.of(context).pop(),
                profilePhotoUrl: null,
                onProfileTap: () {},
                onNotificationTap: () {},
                onSettingsTap: null,
                hideProfileAvatar: true,
                showNotificationButton: false,
              ),
            ),
          ],
        ),
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
          buttonLabel: AppLocalizations.of(context).enhGoToCropRoster,
          onButtonTap: () => context.pushRoute(AppRoutes.cropListing),
        );
      }
      return _NoCropsEmptyState(
        onGoToMyCrops: () => context.pushRoute(AppRoutes.cropListing),
      );
    }

    if (_selectedCrop == null) {
      // The crop passed in isn't usable (pending/rejected), but other
      // approved crops exist — the Crop field is locked on this screen
      // now (no more in-form reselection), so recovery routes through the
      // dedicated crop picker instead of an inline dropdown.
      return _PendingCropBlockedState(
        cropName: _blockedCrop!.cropName,
        buttonLabel: AppLocalizations.of(context).enhChooseADifferentCrop,
        onButtonTap: () => context.pushRoute(AppRoutes.selectCropForHarvest),
      );
    }

    final selectedCrop = _selectedCrop!;

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 72),
              if (!_isOnline)
                OfflineStatusCard(
                  message: AppLocalizations.of(
                    context,
                  ).offlineHarvestEntriesSave,
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
                        // Crop — locked. The crop is already chosen by the
                        // time a farmer reaches this screen (select_crop_
                        // screen.dart or a "Record Harvest" shortcut always
                        // supplies one); re-selection here would be
                        // redundant, so this is a read-only display, not a
                        // dropdown.
                        _FieldLabel(
                          AppLocalizations.of(context).priceTrendCropLabel,
                        ),
                        const SizedBox(height: 8),
                        _LockedField(value: selectedCrop.cropName),
                        const SizedBox(height: 20),

                        // ── Quantity ──────────────────────────────────────
                        QuantityUnitField(
                          controller: _quantityController,
                          units: _units,
                          selectedUnit: _selectedUnit,
                          unitLocked: false,
                          onUnitChanged: (u) =>
                              setState(() => _selectedUnit = u),
                          onAddUnit: _addUnit,
                          addUnitLabel: AppLocalizations.of(
                            context,
                          ).unitAddCompact,
                        ),
                        const SizedBox(height: 20),

                        // ── Market Type ───────────────────────────────────
                        // Replaces the old Variety field. Locked — this is
                        // the crop's registered market type, carried
                        // through from Request New Crop / Crop Roster, not
                        // something set per-harvest.
                        _FieldLabel(
                          AppLocalizations.of(context).priceMarketTypeLabel,
                        ),
                        const SizedBox(height: 8),
                        _LockedField(value: selectedCrop.marketTypeLabel),
                        if (selectedCrop.exclusiveChannel != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ChannelOnlyBadge(
                              channel: selectedCrop.exclusiveChannel,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // ── Batch Number ──────────────────────────────────
                        _FieldLabel(
                          AppLocalizations.of(context).enhBatchNumber,
                        ),
                        const SizedBox(height: 8),
                        // Issued by the database when the harvest is saved
                        // (BATCH-CROP-YYMMDD-X0001), so it cannot be shown
                        // before then without risking a different number.
                        _LockedField(
                          value: AppLocalizations.of(
                            context,
                          ).enhAssignedWhenYouSubmit,
                        ),
                        const SizedBox(height: 16),

                        // ── Harvest Date ──────────────────────────────────
                        _FieldLabel(
                          AppLocalizations.of(context).enhHarvestDate,
                        ),
                        const SizedBox(height: 8),
                        _DateField(date: _harvestDate, onTap: _pickDate),
                        const SizedBox(height: 16),

                        // ── Shelf Life ────────────────────────────────────
                        // The crop's default from Crop Management. Locked: it
                        // starts counting at the harvest date above, for this
                        // harvest only.
                        _FieldLabel(AppLocalizations.of(context).shelfLifeLabel),
                        const SizedBox(height: 8),
                        _LockedField(
                          value: selectedCrop.shelfLifeDays == null
                              ? AppLocalizations.of(context).shelfNotSetByCoop
                              : AppLocalizations.of(
                                  context,
                                ).shelfDaysCount(selectedCrop.shelfLifeDays!),
                        ),
                        if (_harvestIsPastShelfLife(selectedCrop)) ...[
                          const SizedBox(height: 8),
                          _ShelfLifeOverdueNote(
                            days: selectedCrop.shelfLifeDays!,
                          ),
                        ],
                        const SizedBox(height: 16),

                        // ── Storage Location ──────────────────────────────
                        // Locked, same as Batch Number above — SP3 has one
                        // physical storage location today (see
                        // AppConstants.harvestStorageLocations); the farmer
                        // never chooses it. Was previously an interactive
                        // dropdown despite having only one option.
                        _FieldLabel(
                          AppLocalizations.of(context).enhStorageLocation,
                        ),
                        const SizedBox(height: 8),
                        _LockedField(value: _selectedStorageLocation),
                        const SizedBox(height: 16),

                        // ── Error ─────────────────────────────────────────
                        if (_errorMessage != null)
                          _ErrorBanner(message: _errorMessage!),

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
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: selectedCrop.cropName,
              onBack: () => Navigator.of(context).pop(),
              profilePhotoUrl: null,
              onProfileTap: () {},
              onNotificationTap: () =>
                  context.pushRoute(AppRoutes.farmerNotifications),
              onSettingsTap: null,
              hideProfileAvatar: true,
              showNotificationButton: false,
              // trailing badge removed; use the standardized OfflineStatusCard above
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown under Shelf Life when the harvest date is already past it. A warning,
/// not an error: the harvest is still recorded.
class _ShelfLifeOverdueNote extends StatelessWidget {
  final int days;
  const _ShelfLifeOverdueNote({required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.warningAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: AppConstants.warningAmber.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppConstants.warningAmber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).shelfHarvestOverdueWarning(days),
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.45,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// _OnlineBadge and _PulsingDot removed — standardized OfflineStatusCard is used instead

// _CropSelectorField removed — the Crop field is locked (read-only) now
// that every navigation path into this screen always supplies a crop;
// see _LockedField below.

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
      backgroundColor: context.saganaColors.scaffoldBackground,

      body: Column(
        children: [
          SubPageTopBar(title: '', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOnline
                          ? Icons.error_outline_rounded
                          : Icons.wifi_off_rounded,
                      size: 40,
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.60),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isOnline
                          ? AppLocalizations.of(
                              context,
                            ).enhCouldNotLoadYourCrops
                          : AppLocalizations.of(context).youAreOffline,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (!isOnline) ...[
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(
                          context,
                        ).enhYourCropsWillLoadOnceYouReBack,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: onRetry,
                      child: Text(
                        AppLocalizations.of(context).retry,
                        style: GoogleFonts.poppins(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
      backgroundColor: context.saganaColors.scaffoldBackground,

      body: Column(
        children: [
          SubPageTopBar(title: '', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppConstants.primaryGreen.withValues(
                          alpha: 0.08,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.eco_outlined,
                        size: 40,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppLocalizations.of(context).enhYouDonTHaveAnyCropsYet,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(
                        context,
                      ).enhAddACropFromTheCooperativeSList285,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
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
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusLg,
                          ),
                        ),
                      ),
                      child: Text(
                        AppLocalizations.of(context).enhGoToCropRoster,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
  final String buttonLabel;
  final VoidCallback onButtonTap;
  const _PendingCropBlockedState({
    required this.cropName,
    required this.buttonLabel,
    required this.onButtonTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,

      body: Column(
        children: [
          SubPageTopBar(title: '', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppConstants.amber.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.hourglass_top_rounded,
                        size: 40,
                        color: AppConstants.amber,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppLocalizations.of(
                        context,
                      ).enhIsStillAwaitingApproval((cropName).toString()),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(
                        context,
                      ).enhYouCanRecordAHarvestOnceTheCooperative,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: onButtonTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusLg,
                          ),
                        ),
                      ),
                      child: Text(
                        buttonLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
          const Icon(
            Icons.hourglass_top_rounded,
            size: 18,
            color: AppConstants.amber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(
                context,
              ).enhIsStillAwaitingManagerApprovalAndCanT288(
                (cropName).toString(),
              ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Locked Field — read-only display styled to look and behave locked
// (light-blue fill + lock icon). Used for Crop, Market Type, and Batch
// Number: all three are decided before/outside this form, not edited here.
// ─────────────────────────────────────────────────────────────────────────────

class _LockedField extends StatelessWidget {
  final String value;
  const _LockedField({required this.value});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        TextFormField(
          initialValue: value,
          readOnly: true,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: context.adaptiveSurface(const Color(0xFFE6F6FF)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              borderSide: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.20),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              borderSide: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.20),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              borderSide: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.20),
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.outline,
          ),
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
          color: context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.20),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                DateFormat('MMMM d, yyyy').format(date),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
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
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
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
          color: AppConstants.errorRed.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppConstants.errorRed,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppConstants.errorRed,
              ),
            ),
          ),
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
              blurRadius: 24,
              offset: const Offset(0, 8),
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
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  isSuccess
                      ? AppLocalizations.of(context).enhSubmitted
                      : AppLocalizations.of(context).enhSubmitHarvest,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
