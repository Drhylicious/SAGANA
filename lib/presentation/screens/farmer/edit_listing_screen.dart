import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/db_error_utils.dart';
import '../../../core/utils/listing_edit_utils.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/inventory_batch_model.dart';
import '../../../data/models/listing_edit_request_model.dart';
import '../../../data/models/marketplace_listing_model.dart';
import '../../../data/repositories/crop_repository.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../data/repositories/listing_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/server_only.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/crop_photo_capture.dart';
import '../../widgets/edit_request_widgets.dart';
import '../../widgets/listing_status_badge.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/top_bar_spacer.dart';

/// Farmer > Listing > Edit Listing.
///
/// A Farmer can change the quantity, asking price, description and product photo
/// of their own listing while it is Pending Approval or Available (approved with
/// quantity left). The crop (its name and identity) and the unit are fixed: the
/// unit is the one recorded on the harvest, and is only ever shown here.
///
/// The database does the work (`update_my_listing`): it reserves or releases the
/// difference on the harvest batch and leaves existing orders alone. This form
/// checks the same rules first so the Farmer gets a plain answer, and bounds the
/// quantity to what the batch can actually give.
class EditListingScreen extends StatefulWidget {
  final MarketplaceListingModel listing;
  const EditListingScreen({super.key, required this.listing});

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  final _listingRepo = ListingRepository();
  final _inventoryRepo = InventoryRepository();
  final _cropRepo = CropRepository();

  late MarketplaceListingModel _listing;
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _quantityFocus = FocusNode();
  final _priceFocus = FocusNode();

  InventoryBatchModel? _batch;
  CapturedCropPhoto? _newPhoto;

  /// The open edit request for this listing, if there is one (approved listings only).
  ListingEditRequest? _pending;
  bool _loading = true;
  bool _saving = false;
  bool _isOnline = ConnectivityService.instance.isOnline;

  String get _unit => unitOrDefault(_listing.unit);

  /// What buyers have already ordered. The new quantity must stay above it.
  double get _ordered => roundQuantity(_listing.volumeKg - _listing.remainingKg);

  /// The most the listing can become: today's quantity plus what the batch still
  /// has free. Null until the batch has loaded (the database decides then).
  double? get _maxQuantity => _batch == null
      ? null
      : roundQuantity(_listing.volumeKg + _batch!.availableKg);

  /// A published listing is changed only through a request that a Manager or
  /// Officer approves; a listing still waiting for approval is edited directly.
  bool get _requestMode => _listing.isLive;

  bool get _editable =>
      _listing.isPending ||
      (_listing.isLive && _listing.remainingKg > 0 && _pending == null);

  @override
  void initState() {
    super.initState();
    _listing = widget.listing;
    _fillFrom(_listing);
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    for (final pair in [
      (_quantityFocus, _quantityController),
      (_priceFocus, _priceController),
    ]) {
      pair.$1.addListener(() {
        if (pair.$1.hasFocus && pair.$2.text.isNotEmpty) {
          pair.$2.selection = TextSelection(
            baseOffset: 0,
            extentOffset: pair.$2.text.length,
          );
        }
      });
    }
    _load();
  }

  void _fillFrom(MarketplaceListingModel l) {
    _quantityController.text = formatQuantity(l.volumeKg);
    _priceController.text = l.pricePerKg.toStringAsFixed(2);
    _descriptionController.text = l.description ?? '';
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _quantityFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  /// Starts from the live listing and batch, not the copy the list was holding:
  /// orders may have come in, or the Manager may have acted, since it opened.
  Future<void> _load() async {
    final fresh = await _listingRepo.fetchListing(widget.listing.id);
    ListingEditRequest? pending;
    if ((fresh ?? widget.listing).isLive) {
      final requests = await _listingRepo.fetchMyEditRequests(widget.listing.id);
      for (final r in requests) {
        if (r.isPending) pending = r;
      }
    }
    InventoryBatchModel? batch;
    final batchId = (fresh ?? widget.listing).inventoryBatchId;
    if (batchId != null) batch = await _inventoryRepo.fetchBatchById(batchId);
    if (!mounted) return;
    setState(() {
      if (fresh != null) {
        _listing = fresh;
        _fillFrom(fresh);
      }
      _batch = batch;
      _pending = pending;
      _loading = false;
    });
  }

  String _problemText(AppLocalizations l, ListingEditProblem problem) {
    switch (problem) {
      case ListingEditProblem.quantity:
        return quantityErrorText(
              _quantityController.text,
              max: _maxQuantity ?? kMaxQuantity,
              unit: _unit,
              label: 'Quantity',
            ) ??
            'Enter a valid quantity.';
      case ListingEditProblem.quantityNotAboveOrdered:
        return l.editListingQtyTooLow(formatQuantityUnit(_ordered, _unit));
      case ListingEditProblem.price:
        return priceErrorText(_priceController.text, label: 'Asking price') ??
            'Enter a valid asking price.';
      case ListingEditProblem.description:
        return l.editListingDescriptionRequired;
    }
  }

  Future<void> _takePhoto() async {
    final photo = await captureCropPhoto(context);
    if (photo == null || !mounted) return;
    setState(() => _newPhoto = photo);
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (_saving) return;
    if (!ConnectivityService.instance.isOnline) {
      AppToast.show(context, l.editListingOffline, isError: true);
      return;
    }

    final result = checkListingEdit(
      quantityText: _quantityController.text,
      priceText: _priceController.text,
      description: _descriptionController.text,
      orderedQuantity: _ordered,
      maxQuantity: _maxQuantity,
    );
    if (!result.isValid) {
      AppToast.show(context, _problemText(l, result.problem!), isError: true);
      return;
    }
    if (!listingEditChanged(
      quantity: result.quantity!,
      price: result.price!,
      description: result.description!,
      currentQuantity: _listing.volumeKg,
      currentPrice: _listing.pricePerKg,
      currentDescription: _listing.description,
      newPhoto: _newPhoto != null,
    )) {
      AppToast.show(context, l.editListingNoChanges);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    if (_requestMode) {
      await _sendRequest(l, result);
      return;
    }
    try {
      final photo = _newPhoto;
      final batch = _batch;
      if (photo != null && batch != null) {
        // The listing always shows the Farmer's own crop photo: retaking it
        // updates the Crop Roster photo, and the database copies that onto the
        // listing. Camera only, like everywhere else.
        await _cropRepo.setCropPhotoOnline(
          bytes: photo.bytes,
          fileExtension: photo.extension,
          cropId: batch.cropId,
          cropName: batch.cropName,
        );
      }
      await _listingRepo.updateListing(
        listingId: _listing.id,
        quantity: result.quantity!,
        pricePerUnit: result.price!,
        description: result.description!,
        refreshPhoto: photo != null && batch != null,
      );
      if (!mounted) return;
      AppToast.show(context, l.editListingSaved);
      context.popRoute(true);
    } on ServerOnlyException {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, l.editListingOffline, isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // The database's own sentence ("Not enough available quantity in this
      // batch.", "This listing is sold out ...") is written for the reader.
      final readable = readableDatabaseMessage(e);
      AppToast.show(context, readable ?? l.editListingFailed, isError: true);
    }
  }

  /// A published listing: the proposed values go to the Manager / Officer. The
  /// listing is not changed, no stock moves. A new photo is uploaded to this
  /// listing's own photo storage and only replaces the listing photo if approved.
  Future<void> _sendRequest(AppLocalizations l, ListingEditResult result) async {
    try {
      String? photoUrl;
      final photo = _newPhoto;
      if (photo != null) {
        photoUrl = await _listingRepo.uploadListingPhoto(
          batchNumber: _batch?.batchNumber ?? 'listing',
          imageBytes: photo.bytes,
          fileExtension: photo.extension,
        );
        if (photoUrl == null) {
          if (!mounted) return;
          setState(() => _saving = false);
          AppToast.show(context, l.lePhotoUploadFailed, isError: true);
          return;
        }
      }
      await _listingRepo.requestEdit(
        listingId: _listing.id,
        quantity: result.quantity!,
        pricePerUnit: result.price!,
        description: result.description!,
        photoUrl: photoUrl,
      );
      if (!mounted) return;
      AppToast.show(context, l.leRequestSent);
      context.popRoute(true);
    } on ServerOnlyException {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, l.editListingOffline, isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, readableDatabaseMessage(e) ?? l.leRequestFailed, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Column(
            children: [
              TopBarSpacer(height: 72),
              if (!_isOnline) OfflineStatusCard(message: l.editListingOffline),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _notice(l),
                            const SizedBox(height: 16),
                            if (_editable) _form(l) else _notEditable(l),
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
              title: _requestMode ? l.leRequestTitle : l.editListingTitle,
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(AppLocalizations l) {
    final approved = _listing.isLive;
    final color = approved ? AppConstants.successGreen : AppConstants.warningAmber;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            approved ? Icons.check_circle_outline_rounded : Icons.hourglass_top_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              approved ? l.editListingApprovedNote : l.editListingPendingNote,
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.4,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notEditable(AppLocalizations l) {
    if (_pending != null) {
      return EditRequestNotice(
        text: '${l.lePendingBannerTitle}. ${l.lePendingBannerBody}',
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: flatCardDecoration(context),
      child: Text(
        l.editListingNotEditable,
        style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
      ),
    );
  }

  Widget _form(AppLocalizations l) {
    final qty = double.tryParse(_quantityController.text.trim()) ?? 0;
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final max = _maxQuantity;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: flatCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(l.editListingFieldProduct),
          const SizedBox(height: 8),
          _locked(_listing.displayName),
          const SizedBox(height: 6),
          Text(
            l.editListingCropLocked,
            style: GoogleFonts.inter(fontSize: 11, color: AppConstants.outline),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(l.editListingFieldQuantity(_unit)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _quantityController,
                      focusNode: _quantityFocus,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [DecimalInputFormatter(max: max)],
                      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
                      decoration: _decoration(hint: '0.00', suffix: _unit),
                    ),
                    const SizedBox(height: 4),
                    if (max != null)
                      Text(
                        l.editListingMaxHint(formatQuantityUnit(max, _unit)),
                        style: _hint,
                      ),
                    if (_ordered > 0)
                      Text(
                        l.editListingOrdered(formatQuantityUnit(_ordered, _unit)),
                        style: _hint,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(l.editListingFieldPrice),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _priceController,
                      focusNode: _priceFocus,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: const [DecimalInputFormatter()],
                      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
                      decoration: _decoration(hint: '0.00', prefix: '₱', suffix: '/$_unit'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l.editListingEstimatedTotal,
                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
                ),
                Text(
                  formatPesos(moneyOf(qty, price)),
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.primaryGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _label(l.editListingFieldDescription),
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
            controller: _descriptionController,
            onChanged: (_) => setState(() {}),
            minLines: 3,
            maxLines: 5,
            maxLength: 300,
            style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
            decoration: _decoration(
              hint: l.editListingDescriptionHint,
            ).copyWith(
              counterStyle: GoogleFonts.inter(fontSize: 10, color: AppConstants.outline),
            ),
          ),
          const SizedBox(height: 8),
          _label(l.editListingFieldPhoto),
          const SizedBox(height: 8),
          _photo(l),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_saving || !_isOnline) ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _requestMode ? l.leSubmitRequest : l.editListingSave,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photo(AppLocalizations l) {
    final url = _listing.photoUrl;
    Widget image;
    if (_newPhoto != null) {
      image = Image.memory(_newPhoto!.bytes, fit: BoxFit.cover);
    } else if (url != null && url.isNotEmpty) {
      image = Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
    } else {
      image = _placeholder();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(width: double.infinity, height: 160, child: image),
        ),
        const SizedBox(height: 8),
        Text(
          _newPhoto != null
              ? (_requestMode ? l.lePhotoChanged : l.editListingPhotoPending)
              : (_requestMode ? l.lePhotoUnchanged : l.editListingPhotoNote),
          style: _hint,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: (_saving || _batch == null) ? null : _takePhoto,
          icon: const Icon(Icons.photo_camera_rounded, size: 18),
          label: Text(l.editListingRetakePhoto, style: GoogleFonts.poppins(fontSize: 13)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppConstants.primaryGreen,
            side: BorderSide(color: AppConstants.primaryGreen.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholder() => Container(
    color: AppConstants.infoBlueBg,
    alignment: Alignment.center,
    child: const Icon(Icons.eco_rounded, color: AppConstants.primaryGreen, size: 32),
  );

  TextStyle get _hint => GoogleFonts.inter(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    color: AppConstants.outline,
  );

  Widget _label(String text) => Text(
    text,
    style: GoogleFonts.poppins(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: AppConstants.onSurfaceVariant,
    ),
  );

  Widget _locked(String value) => Container(
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
        ListingStatusBadge.forListing(
          context,
          status: _listing.status,
          remainingKg: _listing.remainingKg,
        ),
      ],
    ),
  );

  InputDecoration _decoration({required String hint, String? prefix, String? suffix}) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        fontSize: 14,
        color: AppConstants.outline.withValues(alpha: 0.50),
      ),
      prefixText: prefix,
      prefixStyle: GoogleFonts.inter(fontSize: 13, color: AppConstants.outline),
      suffixText: suffix,
      suffixStyle: GoogleFonts.inter(fontSize: 12, color: AppConstants.outline),
      filled: true,
      fillColor: Colors.white,
      border: border(AppConstants.outline.withValues(alpha: 0.20)),
      enabledBorder: border(AppConstants.outline.withValues(alpha: 0.20)),
      focusedBorder: border(AppConstants.primaryGreen, 2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}
