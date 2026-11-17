import '../../core/l10n/localized_labels.dart';
import '../../core/theme/sagana_colors.dart';
import '../../core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/farmer_crop_model.dart' show marketTypeLabelFor;
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/crop_repository.dart';
import '../../data/services/connectivity_service.dart';
import 'app_dropdown_field.dart';
import 'management_modal.dart';
import 'material_list_tile.dart';
import 'skeleton.dart';
import 'channel_only_badge.dart';
import '../../data/services/market_types_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CropCatalogSheet
// Shown from Crop Roster. Farmer adds an existing crop from the Admin's
// official catalog, or requests one that isn't there yet.
//
// Rebuilt as a single ManagementModal with two internal steps (Browse /
// Request) instead of a sliding bottom sheet that launched a second,
// independent AlertDialog on top of it. Only one modal is ever on screen:
// tapping "Request New Crop" swaps the body in place; the header's title
// and subtitle change with it. "Cancel" and the in-body "Back to crop
// list" link both return to Browse rather than closing the whole flow —
// only the outer ✕ (or a successful add/request) closes it entirely.
// ─────────────────────────────────────────────────────────────────────────────

enum _CropCatalogStep { browse, request }

Future<bool?> showCropCatalogSheet(
  BuildContext context, {
  required CropRepository repo,
  required List<String> existingCropMasterIds,
}) {
  return showManagementModal<bool>(
    context: context,
    builder: (_) => _CropCatalogModal(
      repo: repo,
      existingCropMasterIds: existingCropMasterIds,
    ),
  );
}

class _CropCatalogModal extends StatefulWidget {
  final CropRepository repo;
  final List<String> existingCropMasterIds;

  const _CropCatalogModal({
    required this.repo,
    required this.existingCropMasterIds,
  });

  @override
  State<_CropCatalogModal> createState() => _CropCatalogModalState();
}

class _CropCatalogModalState extends State<_CropCatalogModal> {
  _CropCatalogStep _step = _CropCatalogStep.browse;
  final _categoryRepo = CategoryRepository();

  // ── Browse step state ──
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  String?
  _addingId; // tracks which tile is mid-submit, for a small inline spinner

  // ── Request step state ──
  final _nameController = TextEditingController();
  final _shelfLifeController = TextEditingController();
  String? _shelfLifeError;
  List<String> _categories = [];
  String? _category;
  String? _cropType = MarketTypes.instance.defaultCode;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _shelfLifeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.repo.fetchCropCatalog(),
      _categoryRepo.fetchCropCategories(),
    ]);
    if (!mounted) return;
    final catalog = results[0] as List<Map<String, dynamic>>;
    setState(() {
      _catalog = catalog
          .where(
            (c) => !widget.existingCropMasterIds.contains(c['id'] as String),
          )
          .toList();
      _filtered = _catalog;
      _categories = results[1] as List<String>;
      _isLoading = false;
    });
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? _catalog
          : _catalog
                .where(
                  (c) =>
                      (c['crop_name'] as String).toLowerCase().contains(query),
                )
                .toList();
    });
  }

  Future<void> _addFromCatalog(Map<String, dynamic> entry) async {
    setState(() => _addingId = entry['id'] as String);
    try {
      await widget.repo.addCrop(
        cropName: entry['crop_name'] as String,
        category: entry['category'] as String,
        cropMasterId: entry['id'] as String,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _addingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).enhCouldNotAddCropPleaseTryAgain,
              style: GoogleFonts.inter(fontSize: 13),
            ),
          ),
        );
      }
    }
  }

  void _goToRequestStep() => setState(() => _step = _CropCatalogStep.request);

  void _goBackToBrowse() => setState(() => _step = _CropCatalogStep.browse);

  Future<void> _submitRequest() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (_category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).enhPleaseSelectACategory),
        ),
      );
      return;
    }
    // Shelf life is required: a whole number of days.
    final shelfLifeDays = int.tryParse(_shelfLifeController.text.trim());
    if (shelfLifeDays == null || shelfLifeDays < 1 || shelfLifeDays > 3650) {
      setState(
        () => _shelfLifeError = _shelfLifeController.text.trim().isEmpty
            ? AppLocalizations.of(context).cropMgmtShelfLifeRequired
            : AppLocalizations.of(context).cropMgmtShelfLifeInvalid,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.repo.requestNewCrop(
        cropName: name,
        category: _category!,
        cropType: _cropType,
        shelfLifeDays: shelfLifeDays,
      );
      // The crop is usable immediately (per the copy below) — closing the
      // whole modal here, rather than bouncing back to Browse, since the
      // farmer's task ("add a crop") is done.
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              ).enhCouldNotSubmitRequestPleaseTryAgain,
              style: GoogleFonts.inter(fontSize: 13),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == _CropCatalogStep.request) {
      return ManagementModalShell(
        title: AppLocalizations.of(context).enhRequestNewCrop,
        subtitle: AppLocalizations.of(context).enhYouCanUseThisCropRightAwaySP,
        body: _buildRequestBody(),
        footer: _buildRequestFooter(context),
      );
    }
    return ManagementModalShell(
      title: AppLocalizations.of(context).enhAddACropToGrow,
      subtitle: AppLocalizations.of(context).enhChooseFromSPSOfficialCropList,
      body: _buildBrowseBody(context),
    );
  }

  // ── Browse step ────────────────────────────────────────────────────────

  Widget _buildBrowseBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context).enhSearchCrops,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            filled: true,
            fillColor: context.saganaColors.scaffoldBackground,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 0,
              horizontal: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
          )
        else if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              // Offline with no saved catalog is "needs a connection", never
              // "you already added every crop".
              _catalog.isEmpty && !ConnectivityService.instance.isOnline
                  ? AppLocalizations.of(context).offlineNeedsInternet
                  : _catalog.isEmpty
                  ? AppLocalizations.of(
                      context,
                    ).enhYouVeAlreadyAddedEveryCropInThe
                  : AppLocalizations.of(
                      context,
                    ).enhNoMatchesTryADifferentSearchOrRequest,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.36,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              // No automatic status-bar padding: this list sits inside a bigger scroll view.
              padding: EdgeInsets.zero,
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final entry = _filtered[i];
                final isAdding = _addingId == entry['id'];
                final imageUrl = entry['image_url'] as String?;
                return MaterialListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: (imageUrl != null && imageUrl.isNotEmpty)
                        ? Image.network(imageUrl, fit: BoxFit.cover)
                        : Icon(
                            Icons.eco_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                  ),
                  title: Text(
                    entry['crop_name'] as String,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entry['category']} · ${marketTypeLabelFor(entry['crop_type'] as String?)}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (entry['shelf_life_days'] != null)
                        Text(
                          AppLocalizations.of(context).cropCatalogShelfLife(
                            (entry['shelf_life_days'] as num).toInt(),
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (entry['exclusive_channel'] != null) ...[
                        const SizedBox(height: 4),
                        ChannelOnlyBadge(
                          channel: entry['exclusive_channel'] as String?,
                        ),
                      ],
                    ],
                  ),
                  trailing: isAdding
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        )
                      : Icon(
                          Icons.add_circle_outline_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  onTap: isAdding ? null : () => _addFromCatalog(entry),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        MaterialListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.help_outline_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          title: Text(
            AppLocalizations.of(context).enhCanTFindYourCrop,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          subtitle: Text(
            AppLocalizations.of(context).enhRequestNewCrop,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          onTap: _goToRequestStep,
        ),
      ],
    );
  }

  // ── Request step ───────────────────────────────────────────────────────

  // One look for the four request fields. A text field is 56 px tall with
  // this text style and padding; a dropdown given 54 lines up with it (the
  // same pairing Price Management uses for its Price and Unit fields).
  static const double _fieldGap = 16;
  static const double _dropdownHeight = 54;
  static const EdgeInsets _fieldPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 16,
  );

  TextStyle get _fieldTextStyle => GoogleFonts.inter(
    fontSize: 16,
    height: 1.5,
    color: Theme.of(context).colorScheme.onSurface,
  );

  // The same label the dropdowns draw above themselves.
  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _buildRequestBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _isSubmitting ? null : _goBackToBrowse,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Flexible(child: Text(
                AppLocalizations.of(context).enhBackToCropList,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Every field: its label above, the same height, the same gap.
        _fieldLabel(AppLocalizations.of(context).enhCropName),
        TextField(
          controller: _nameController,
          autofocus: true,
          style: _fieldTextStyle,
          decoration: const InputDecoration(contentPadding: _fieldPadding),
        ),
        const SizedBox(height: _fieldGap),
        AppDropdownField<String>(
          value: _category,
          fieldHeight: _dropdownHeight,
          hintText: AppLocalizations.of(context).commonSelectCategory,
          labelText: AppLocalizations.of(context).buyerListingCategory,
          items: _categories,
          itemLabel: (c) =>
              localizeBuiltinLabel(AppLocalizations.of(context), c),
          onChanged: (v) => setState(() => _category = v),
        ),
        const SizedBox(height: _fieldGap),
        AppDropdownField<String>(
          value: _cropType,
          fieldHeight: _dropdownHeight,
          hintText: AppLocalizations.of(context).cropMgmtMarketTypeHint,
          labelText: AppLocalizations.of(context).enhMarketTypeSPWillConfirm,
          items: MarketTypes.instance.activeTypes.map((t) => t.code).toList(),
          itemLabel: (v) => MarketTypes.instance.label(v),
          onChanged: (v) => setState(() => _cropType = v ?? _cropType),
        ),
        const SizedBox(height: _fieldGap),
        _fieldLabel(AppLocalizations.of(context).shelfLifeLabel),
        // Shelf life: the Farmer knows their crop, so they state how long a
        // harvest of it stays good. It becomes the crop's shelf life when the
        // cooperative approves the request.
        TextField(
          controller: _shelfLifeController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          onChanged: (_) {
            if (_shelfLifeError != null) setState(() => _shelfLifeError = null);
          },
          style: _fieldTextStyle,
          decoration: InputDecoration(
            contentPadding: _fieldPadding,
            hintText: AppLocalizations.of(context).cropMgmtShelfLifeHint,
            suffixText: AppLocalizations.of(context).shelfDaysUnit,
            errorText: _shelfLifeError,
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppLocalizations.of(context).cropMgmtShelfLifeHelp,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: _fieldGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.photo_camera_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.of(context).enhNoPhotoNeededForARequestOnceThe,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRequestFooter(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: cs.outline.withValues(alpha: 0.30)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            onPressed: _isSubmitting ? null : _goBackToBrowse,
            child: Text(
              AppLocalizations.of(context).cancel,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitRequest,
            child: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    AppLocalizations.of(context).createAccountSubmitConfirm,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }
}
