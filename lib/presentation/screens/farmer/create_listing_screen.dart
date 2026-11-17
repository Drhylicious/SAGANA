import '../../../core/theme/sagana_colors.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/models/shelf_life_model.dart';
import '../../../data/repositories/shelf_life_repository.dart';
import '../../widgets/shelf_life_widgets.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/farmer_crop_model.dart' show marketTypeLabelFor;
import '../../../data/models/inventory_batch_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/utils/db_error_utils.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/crop_photo_capture.dart';
import 'listing_success_screen.dart' show ListingSuccessArgs;
import '../../widgets/skeleton.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../data/services/feature_restriction_service.dart';

// Quantity and price are typed with the shared DecimalInputFormatter
// (quantity_utils.dart): it validates the WHOLE new value on every edit — at
// most 2 decimals, and for the quantity never more than the stock left — and
// refuses the edit otherwise. (A per-character
// FilteringTextInputFormatter.allow with an anchored pattern cannot do this.)

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
  final _cropRepo = CropRepository();

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
  ListingPriceRule? _priceRule;
  // True once the rule of the selected batch has been looked up. A batch whose
  // crop has no Reference Price in the batch's own unit cannot be listed on
  // the Marketplace (the database refuses it too); its other selling channels
  // are not affected.
  bool _priceRuleChecked = false;
  bool get _missingReferencePrice =>
      _selectedBatch != null && _priceRuleChecked && _priceRule == null;
  final _shelfRepo = ShelfLifeRepository();

  // The listing is measured in the batch's own unit. A reference price is only
  // suggested when it is quoted in that same unit.
  String get _unit => unitOrDefault(_selectedBatch?.unit);
  bool _isLoadingBatches = true;
  bool _isSubmitting = false;
  bool _isOnline = true;
  bool _batchWasPreselected = false;

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

    // Read via the constructor now — GoRouter's `extra` is delivered here,
    // not through ModalRoute.settings.arguments (that only ever gets
    // populated by raw Navigator.push(..., settings: RouteSettings(...)),
    // which is not how this screen is reached).
    final arg = widget.initialArg;
    if (arg is InventoryBatchModel) _batchWasPreselected = true;
    _loadBatches(preselect: arg is InventoryBatchModel ? arg : null);

    _quantityFocusNode.addListener(
      () => _selectAllOnFocus(_quantityFocusNode, _quantityController),
    );
    _priceFocusNode.addListener(
      () => _selectAllOnFocus(_priceFocusNode, _priceController),
    );
  }

  void _selectAllOnFocus(FocusNode node, TextEditingController controller) {
    if (node.hasFocus && controller.text.isNotEmpty) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
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

    InventoryBatchModel? initial =
        preselect ?? (batches.isNotEmpty ? batches.first : null);

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
      // The whole stock, exactly: 0.45 stays 0.45 (it used to be rounded to a
      // whole number, which made a small batch show "0").
      _quantityController.text = formatQuantity(batch.availableKg);
      _marketPrice = null;
      _priceRule = null;
      _priceRuleChecked = false;
    });
    final results = await Future.wait([
      _dashboardRepo.fetchLatestPriceForCrop(
        batch.cropName,
        priceType: batch.cropType,
        unit: batch.unit,
      ),
      // The Marketplace price rule from Price Management: a Fixed Price (the
      // listing is created at it and the field is locked) or a Reference Price
      // Range (the price must stay inside it). Null = no restriction.
      _shelfRepo.lookupPriceRule(batch.id),
    ]);
    if (!mounted || _selectedBatch?.id != batch.id) return;
    final price = results[0] as double?;
    final lookup = results[1] as ({ListingPriceRule? rule, bool known});
    final rule = lookup.rule;
    setState(() {
      _marketPrice = price;
      _priceRule = rule;
      _priceRuleChecked = lookup.known;
      final typed = parseDecimal(_priceController.text);
      if (rule != null && rule.isFixed) {
        _priceController.text = rule.max.toStringAsFixed(2);
      } else if (rule != null && (typed == null || !rule.allows(typed))) {
        // Start inside the range (its minimum); the Farmer may raise it.
        _priceController.text = rule.min.toStringAsFixed(2);
      } else if (price != null && _priceController.text.isEmpty) {
        _priceController.text = price.toStringAsFixed(2);
      }
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _handleSubmit() async {
    if (_selectedBatch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).enhPleaseSelectABatchToList,
          ),
        ),
      );
      return;
    }

    if (_missingReferencePrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).listingNoReferencePrice(
              _selectedBatch!.cropName,
              unitOrDefault(_selectedBatch!.unit),
            ),
          ),
        ),
      );
      return;
    }

    final available = _selectedBatch!.availableKg;
    final qty = parseDecimal(_quantityController.text, max: available);
    final price = parseDecimal(_priceController.text);

    if (qty == null) {
      // The reason is specific: empty, not a number, zero, too many decimals,
      // or more than the stock left.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            quantityErrorText(
                  _quantityController.text,
                  max: available,
                  unit: _selectedBatch!.unit,
                ) ??
                AppLocalizations.of(context).retQtyInvalid,
          ),
        ),
      );
      return;
    }

    final rule = _priceRule;
    if (price != null && rule != null && !rule.allows(price)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(listingPriceRuleText(context, rule))),
      );
      return;
    }

    if (price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            priceErrorText(
                  _priceController.text,
                  label: AppLocalizations.of(context).enhAskingPrice,
                ) ??
                AppLocalizations.of(context).enhEnterAValidAskingPrice,
          ),
        ),
      );
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).editListingDescriptionRequired,
          ),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      // The listing shows the Farmer's own camera photo of the crop (Crop
      // Roster is its one source) — never a catalog image. A crop without one
      // cannot be listed: the Farmer is asked to take it now, and the database
      // checks it again.
      var photoUrl = _selectedBatch?.displayImageUrl;
      if (photoUrl == null || photoUrl.isEmpty) {
        setState(() => _isSubmitting = false);
        photoUrl = await requireCropPhotoToSell(
          context,
          repo: _cropRepo,
          cropId: _selectedBatch!.cropId,
          cropName: _selectedBatch!.cropName,
          why: AppLocalizations.of(context).enhListThisOnTheMarketplace,
        );
        if (photoUrl == null || !mounted) return;
        setState(() {
          _selectedBatch = _selectedBatch!.withPhoto(photoUrl!);
          _isSubmitting = true;
        });
      }

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
      // the crop is reserved for another selling channel (Ginger → DA-AMAD
      // Market Linking) — surface both specifically instead of a generic
      // message, since they're actionable, expected failures rather than
      // network/server errors. The database's own sentence for the second
      // case ("<crop> can only be sold through <channel> — …") is shown as is.
      final errorText = e.toString();
      final message = restrictionMessageOf(e) != null
          ? restrictionMessageOf(e)!
          : errorText.contains('Not enough available quantity')
          ? AppLocalizations.of(
              context,
            ).enhNotEnoughAvailableStockForThatQuantityPlease
          : errorText.contains('can only be sold through') ||
                isPhotoRequiredError(e)
          ? friendlyErrorMessage(e)
          : AppLocalizations.of(context).enhFailedToSubmitListingPleaseTryAgain;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  double get _estimatedRevenue {
    final qty = double.tryParse(_quantityController.text.trim()) ?? 0;
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    return moneyOf(qty, price);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const TopBarSpacer(height: 72),
                    if (!_isOnline)
                      OfflineStatusCard(
                        message: AppLocalizations.of(
                          context,
                        ).offlineListingSubmit,
                      ),
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
                              _SectionLabel(
                                number: 1,
                                title: AppLocalizations.of(
                                  context,
                                ).enhChooseWhatToSell,
                              ),
                              const SizedBox(height: 10),
                              _isLoadingBatches
                                  ? const SkeletonBlock(height: 110)
                                  : _batches.isEmpty
                                  ? _NoBatchesNotice(
                                      onGoToInventory: () =>
                                          context.pushReplacementRoute(
                                            AppRoutes.manageInventory,
                                          ),
                                    )
                                  : _BatchSelector(
                                      batches: _batches,
                                      selected: _selectedBatch,
                                      onSelected: _onBatchSelected,
                                    ),
                              const SizedBox(height: 24),
                            ],
                            if (_batchWasPreselected &&
                                _selectedBatch != null) ...[
                              _SectionLabel(
                                number: 1,
                                title: AppLocalizations.of(
                                  context,
                                ).enhWhatYouReSelling,
                              ),
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
                            _SectionLabel(
                              number: 2,
                              title: AppLocalizations.of(
                                context,
                              ).enhSetYourPriceQuantity,
                            ),
                            const SizedBox(height: 10),
                            // No Reference Price for this crop in this unit:
                            // say so before the Farmer fills the form in.
                            if (_missingReferencePrice) ...[
                              ShelfLifeNote(
                                text: AppLocalizations.of(
                                  context,
                                ).listingNoReferencePrice(
                                  _selectedBatch!.cropName,
                                  unitOrDefault(_selectedBatch!.unit),
                                ),
                                color: AppConstants.errorRed,
                                icon: Icons.sell_outlined,
                              ),
                              const SizedBox(height: 10),
                            ],
                            _FormCard(
                              cropName: _selectedBatch?.cropName ?? '',
                              photoUrl: _selectedBatch?.displayImageUrl,
                              quantityController: _quantityController,
                              priceController: _priceController,
                              descriptionController: _descriptionController,
                              quantityFocusNode: _quantityFocusNode,
                              priceFocusNode: _priceFocusNode,
                              maxQty: _selectedBatch?.availableKg,
                              unit: _unit,
                              marketPrice: _marketPrice,
                              priceRule: _priceRule,
                              onChanged: () => setState(() {}),
                            ),
                            const SizedBox(height: 24),

                            // ── Section 3: Preview ───────────────────────────────
                            _SectionLabel(
                              number: 3,
                              title: AppLocalizations.of(
                                context,
                              ).enhReviewBeforeSubmitting,
                            ),
                            const SizedBox(height: 10),
                            _LivePreviewCard(
                              cropName: _selectedBatch?.cropName ?? '',
                              photoUrl: _selectedBatch?.displayImageUrl,
                              quantity:
                                  double.tryParse(
                                    _quantityController.text.trim(),
                                  ) ??
                                  0,
                              price:
                                  double.tryParse(
                                    _priceController.text.trim(),
                                  ) ??
                                  0,
                              unit: _unit,
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
                              canSubmit: _selectedBatch != null && _isOnline,
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
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FarmerTopBar(
                    title: AppLocalizations.of(context).enhCreateListing,
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
        Flexible(child: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        )),
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
            border: Border.all(
              color: AppConstants.warningAmber.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppConstants.warningAmber,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: AppLocalizations.of(
                          context,
                        ).enhYourListingWillBeReviewedByThe,
                      ),
                      TextSpan(
                        text: AppLocalizations.of(
                          context,
                        ).enhSPCooperativeManager,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      TextSpan(
                        text: AppLocalizations.of(
                          context,
                        ).enhBeforeBecomingVisibleToBuyersInTheMarketplace,
                      ),
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
        border: Border.all(
          color: AppConstants.primaryGreen.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).enhFrom(
                (batch.cropName).toString(),
                (formatQuantityUnit(batch.availableKg, batch.unit)).toString(),
                (formatBatchNumber(batch.batchNumber)).toString(),
              ),
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
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

  const _BatchSelector({
    required this.batches,
    required this.selected,
    required this.onSelected,
  });

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
                color: isActive
                    ? AppConstants.primaryGreen.withValues(alpha: 0.06)
                    : context.saganaColors.cardBackground.withValues(
                        alpha: 0.60,
                      ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isActive
                      ? AppConstants.primaryGreen
                      : Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.20),
                  width: isActive ? 2 : 1,
                ),
              ),
              child: Stack(
                children: [
                  if (isActive)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The number is long (#BATCH-POTATO-261025-A0001): it may take
                      // two lines, and keeps clear of the selected-check icon.
                      Padding(
                        padding: const EdgeInsets.only(right: 22),
                        child: Text(
                          formatBatchNumber(batch.batchNumber),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        batch.cropName,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              formatQuantityUnit(batch.availableKg, batch.unit),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
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
        color: context.saganaColors.cardBackground.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 32,
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.60),
          ),
          const SizedBox(height: 10),
          Text(
            AppLocalizations.of(context).enhNoAvailableInventoryToList,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(
              context,
            ).enhRecordAHarvestFirstToBuildUpInventory,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onGoToInventory,
            child: Text(
              AppLocalizations.of(context).issueLoanGoToInventory,
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
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
      _DetailChip(
        label: AppLocalizations.of(context).priceCropNameLabel,
        value: batch.cropName,
      ),
      if (batch.category != null)
        _DetailChip(
          label: AppLocalizations.of(context).buyerListingCategory,
          value: batch.category!,
        ),
      _DetailChip(
        label: AppLocalizations.of(context).priceMarketTypeLabel,
        value: marketTypeLabelFor(batch.cropType),
      ),
      _DetailChip(
        label: AppLocalizations.of(context).enhBatchNumber,
        value: formatBatchNumber(batch.batchNumber),
      ),
      _DetailChip(
        label: AppLocalizations.of(context).enhAvailableStock,
        value: formatQuantityUnit(batch.availableKg, batch.unit),
      ),
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
        color: context
            .adaptiveSurface(AppConstants.infoBlueBg)
            .withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.outline,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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
  final String unit;
  final double? marketPrice;

  /// The price rule from Price Management for this batch (null = none).
  final ListingPriceRule? priceRule;
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
    required this.unit,
    required this.marketPrice,
    required this.priceRule,
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
            color: context.saganaColors.cardBackground.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.05),
                blurRadius: 16,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title — locked, always the selected crop's own name. Not a
              // farmer-editable field: per explicit product direction, the
              // listing title must reflect exactly what was selected in
              // Step 1, never a disconnected value a farmer typed in.
              _FieldLabel(AppLocalizations.of(context).enhListingTitle),
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
                        _FieldLabel(
                          AppLocalizations.of(
                            context,
                          ).enhQuantity((unit).toString()),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: quantityController,
                          focusNode: quantityFocusNode,
                          onChanged: (_) => onChanged(),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [DecimalInputFormatter(max: maxQty)],
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          decoration: _inputDecoration(
                            context,
                            hint: '0.00',
                            suffix: unit,
                          ),
                        ),
                        if (maxQty != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 2),
                            child: Text(
                              AppLocalizations.of(context).enhMax(
                                (formatQuantityUnit(maxQty!, unit)).toString(),
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel(
                          AppLocalizations.of(context).editListingFieldPrice,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: priceController,
                          focusNode: priceFocusNode,
                          // A Fixed Price cannot be typed over.
                          readOnly: priceRule?.isLocked ?? false,
                          onChanged: (_) => onChanged(),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: const [DecimalInputFormatter()],
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: (priceRule?.isLocked ?? false)
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                          decoration: _inputDecoration(
                            context,
                            hint: '0.00',
                            prefix: '₱',
                            suffix: '/$unit',
                          ),
                        ),
                        if (priceRule != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 2),
                            child: ListingPriceRuleNote(rule: priceRule!),
                          )
                        else if (marketPrice != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 2),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.trending_up_rounded,
                                  size: 11,
                                  color: AppConstants.warningAmber,
                                ),
                                const SizedBox(width: 3),
                                Flexible(child: Text(
                                  AppLocalizations.of(context).enhMarket(
                                    (formatPricePerUnit(
                                      marketPrice!,
                                      unit,
                                    )).toString(),
                                  ),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppConstants.warningAmber,
                                  ),
                                )),
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
                  _FieldLabel(
                    AppLocalizations.of(context).programMgmtFieldDescription,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '*',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.errorRed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descriptionController,
                onChanged: (_) => onChanged(),
                minLines: 3,
                maxLines: 5,
                maxLength: 300,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration:
                    _inputDecoration(
                      context,
                      hint: AppLocalizations.of(
                        context,
                      ).editListingDescriptionHint,
                    ).copyWith(
                      counterStyle: GoogleFonts.inter(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
              ),
              const SizedBox(height: 4),

              // Photo — locked, sourced from the Crop Roster via the
              // selected batch. No upload control: per explicit product
              // direction, a listing must never carry a different image
              // than the crop's own registered photo, to avoid
              // inconsistent product images across the system.
              _FieldLabel(AppLocalizations.of(context).editListingFieldPhoto),
              const SizedBox(height: 8),
              _PhotoPreview(photoUrl: photoUrl),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String hint,
    String? prefix,
    String? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        fontSize: 14,
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.50),
      ),
      prefixText: prefix,
      prefixStyle: GoogleFonts.inter(
        fontSize: 13,
        color: Theme.of(context).colorScheme.outline,
      ),
      suffixText: suffix,
      suffixStyle: GoogleFonts.inter(
        fontSize: 12,
        color: Theme.of(context).colorScheme.outline,
      ),
      filled: true,
      fillColor: context.saganaColors.cardBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.20),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.20),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
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
                errorBuilder: (_, __, ___) => _placeholder(context),
              )
            : _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
    color: context.adaptiveSurface(AppConstants.infoBlueBg),
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.eco_rounded,
          color: Theme.of(context).colorScheme.primary,
          size: 28,
        ),
        const SizedBox(height: 6),
        Text(
          AppLocalizations.of(context).enhNoPhotoAvailable,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
  final String unit;
  final double estimatedRevenue;

  const _LivePreviewCard({
    required this.cropName,
    required this.photoUrl,
    required this.quantity,
    required this.price,
    required this.unit,
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
            color: context.saganaColors.cardBackground.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusXl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.05),
                blurRadius: 16,
              ),
            ],
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
                        width: 80,
                        height: 80,
                        child: hasImage
                            ? Image.network(
                                photoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _placeholder(context),
                              )
                            : _placeholder(context),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            cropName.isEmpty
                                ? AppLocalizations.of(context).enhListingTitle
                                : cropName,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppLocalizations.of(context).enhQty(
                                      (formatQuantityUnit(
                                        quantity,
                                        unit,
                                      )).toString(),
                                    ),
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                  ),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        '₱${price.toStringAsFixed(2)}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ),
                                      Text(
                                        ' /$unit',
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.05),
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: Text(
                      AppLocalizations.of(context).enhEstimatedTotalRevenue,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )),
                    Text(
                      '₱${estimatedRevenue.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
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

  Widget _placeholder(BuildContext context) => Container(
    color: context.adaptiveSurface(AppConstants.infoBlueBg),
    child: Icon(
      Icons.eco_rounded,
      color: Theme.of(context).colorScheme.primary,
      size: 30,
    ),
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
            AppLocalizations.of(context).enhWhatHappensAfterYouSubmit,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(
              context,
            ).enhYourListingEntersTheCooperativeManagerSReview,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.60),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(
                        AppLocalizations.of(
                          context,
                        ).enhGoOnlineToSubmitYourListing,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.70),
                        ),
                      )),
                    ],
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppConstants.primaryGreen, Color(0xFF2E7D32)],
                    ),
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    boxShadow: [
                      BoxShadow(
                        color: AppConstants.primaryGreen.withValues(
                          alpha: 0.30,
                        ),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: (isSubmitting || !canSubmit) ? null : onSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusLg,
                        ),
                      ),
                    ),
                    child: isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Flexible(child: Text(
                                AppLocalizations.of(context).enhSubmitForReview,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              )),
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
              foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.list_alt_rounded, size: 18),
                const SizedBox(width: 8),
                Flexible(child: Text(
                  AppLocalizations.of(context).enhViewListing,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                )),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
