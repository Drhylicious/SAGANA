import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/admin_activity_repository.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/report_summary_widgets.dart' show ReportIconStatCard, ReportSectionCard;
import '../../widgets/material_list_tile.dart';

// ── Model ────────────────────────────────────────────────────────────────────

class CropMasterItem {
  final String id;
  final String cropName;
  final String category;
  final String cropType;
  final String? description;
  final String? imageUrl;
  final bool isActive;
  final int sortOrder;

  const CropMasterItem({
    required this.id,
    required this.cropName,
    required this.category,
    required this.cropType,
    this.description,
    this.imageUrl,
    required this.isActive,
    required this.sortOrder,
  });

  factory CropMasterItem.fromMap(Map<String, dynamic> m) => CropMasterItem(
        id: m['id'] as String,
        cropName: m['crop_name'] as String,
        category: m['category'] as String? ?? 'Other',
        cropType: m['crop_type'] as String? ?? 'open_market',
        description: m['description'] as String?,
        imageUrl: m['image_url'] as String?,
        isActive: m['is_active'] as bool? ?? true,
        sortOrder: m['sort_order'] as int? ?? 0,
      );

  // Delegates to the shared MarketTypeDisplay label (sagana_colors.dart)
  // instead of a third local copy of the same switch — keeps Crop
  // Management, Home, Market Rate Details, and View Market from ever
  // disagreeing on what a crop_type value is called. Takes l10n (this
  // model has no BuildContext of its own) since the label is
  // language-dependent.
  String cropTypeLabel(AppLocalizations l10n) => MarketTypeDisplay.label(l10n, cropType);
}

// ── Repository ───────────────────────────────────────────────────────────────

class CropDuplicateException implements Exception {
  final String message;
  const CropDuplicateException(this.message);
}

class _CropMasterRepository {
  final _client = Supabase.instance.client;

  Future<List<CropMasterItem>> fetchAll() async {
    try {
      final rows = await _client
          .from('crop_master')
          .select()
          .order('sort_order')
          .order('crop_name');
      return rows.map((r) => CropMasterItem.fromMap(r)).toList();
    } catch (_) { return []; }
  }

  Future<bool> addCrop({
    required String name,
    required String category,
    required String cropType,
    String? description,
    String? imageUrl,
  }) async {
    final trimmedName = name.trim();
    try {
      final existing = await _client
          .from('crop_master')
          .select('id')
          .ilike('crop_name', trimmedName)
          .maybeSingle();
      if (existing != null) {
        throw CropDuplicateException(
            'A crop named "$trimmedName" already exists.');
      }
      await _client.from('crop_master').insert({
        'crop_name': trimmedName,
        'category': category,
        'crop_type': cropType,
        'description': description?.trim(),
        'image_url': imageUrl,
        'created_by': _client.auth.currentUser?.id,
      });
      AdminActivityRepository().log(
        module: 'crops',
        actionType: 'created',
        description: 'Added "$trimmedName" to the crop catalog ($category).',
      );
      return true;
    } on CropDuplicateException {
      rethrow;
    } catch (_) { return false; }
  }

  Future<bool> updateCrop({
    required String id,
    required String name,
    required String category,
    required String cropType,
    String? description,
    String? imageUrl,
  }) async {
    try {
      await _client.from('crop_master').update({
        'crop_name': name.trim(),
        'category': category,
        'crop_type': cropType,
        'description': description?.trim(),
        'image_url': imageUrl,
      }).eq('id', id);
      return true;
    } catch (_) { return false; }
  }

  // Mirrors uploadProfilePhoto()'s pattern (profile_photo_service.dart) —
  // same owner-folder upload idiom, against the already-provisioned
  // crop_images bucket (supabase_schema_fixes.sql), just never wired to a
  // column or an upload flow until this feature.
  Future<String?> uploadCropImage(Uint8List bytes, String fileExtension) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;
      final path = '$uid/crop_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      await _client.storage.from('crop_images').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      return _client.storage.from('crop_images').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  Future<bool> toggleActive(String id, bool newValue) async {
    try {
      await _client.from('crop_master')
          .update({'is_active': newValue}).eq('id', id);
      return true;
    } catch (_) { return false; }
  }

  Future<bool> deleteCrop(String id) async {
    try {
      await _client.from('crop_master').delete().eq('id', id);
      return true;
    } catch (_) { return false; }
  }

  /// Pre-delete impact check — mirrors the Farmer-side
  /// CropRepository.fetchCropDeleteImpact() pattern. crop_master.id
  /// has no ON DELETE action on farmer_crops.crop_master_id, so an
  /// in-use crop's delete would otherwise fail with an unexplained
  /// FK violation, silently swallowed by deleteCrop()'s catch block.
  Future<int> fetchCropUsageCount(String cropId) async {
    try {
      final rows = await _client
          .from('farmer_crops')
          .select('id')
          .eq('crop_master_id', cropId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> fetchPendingRequestCount() async {
    try {
      final rows = await _client
          .from('crop_requests')
          .select('id')
          .eq('status', 'pending');
      return rows.length;
    } catch (_) { return 0; }
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class CropManagementScreen extends StatefulWidget {
  const CropManagementScreen({super.key});

  @override
  State<CropManagementScreen> createState() => _CropManagementScreenState();
}

class _CropManagementScreenState extends State<CropManagementScreen> {
  final _repo = _CropMasterRepository();
  final _categoryRepo = CategoryRepository();

  List<CropMasterItem> _crops = [];
  List<String> _categories = [];
  bool _isLoading = true;
  bool _isOnline = true;
  int _pendingRequestCount = 0;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen(
        (v) { if (mounted) setState(() => _isOnline = v); });
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchAll(),
      _repo.fetchPendingRequestCount(),
      _categoryRepo.fetchCropCategories(),
    ]);
    if (!mounted) return;
    setState(() {
      _crops = results[0] as List<CropMasterItem>;
      _pendingRequestCount = results[1] as int;
      _categories = results[2] as List<String>;
      _isLoading = false;
    });
  }

  List<CropMasterItem> get _filtered =>
      _crops.where((c) => c.isActive).toList();

  void _showAddSheet() => _showCropSheet(null);
  void _showEditSheet(CropMasterItem crop) => _showCropSheet(crop);

  void _showCropSheet(CropMasterItem? existing) {
    final l10n = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.cropName ?? '');
    String? selectedCategory = existing?.category;
    String? selectedCropType = existing?.cropType;
    String? existingImageUrl = existing?.imageUrl;
    Uint8List? pickedImageBytes;
    String? pickedImageExt;
    bool isSaving = false;
    var categoryOptions = List<String>.of(_categories);

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> pickImage() async {
            final picked = await ImagePicker()
                .pickImage(source: ImageSource.gallery, imageQuality: 80);
            if (picked == null) return;
            final bytes = await picked.readAsBytes();
            setSheet(() {
              pickedImageBytes = bytes;
              pickedImageExt = picked.name.contains('.')
                  ? picked.name.split('.').last.toLowerCase()
                  : 'jpg';
            });
          }

          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;

            final trimmedName = nameCtrl.text.trim();

            // Non-blocking warning for near-duplicates (e.g. "Rice (Palay)"
            // vs "Palay") — only for new crops, and skipped for an exact
            // match since that's caught explicitly by CropDuplicateException
            // below instead.
            if (existing == null) {
              final newLower = trimmedName.toLowerCase();
              final nearDuplicate = _crops.where((c) => c.isActive).any((c) {
                final existingLower = c.cropName.trim().toLowerCase();
                if (existingLower == newLower) return false;
                return existingLower.contains(newLower) ||
                    newLower.contains(existingLower);
              });

              if (nearDuplicate) {
                final proceed = await showDialog<bool>(
                  context: ctx,
                  builder: (dialogCtx) => AlertDialog(
                    title: Text(l10n.cropMgmtDuplicateTitle,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                    content: Text(
                      l10n.cropMgmtDuplicateBody(trimmedName),
                      style: GoogleFonts.inter(fontSize: 13),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: Text(l10n.farmerMgmtCancel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: Text(l10n.cropMgmtAddAnyway),
                      ),
                    ],
                  ),
                );
                if (proceed != true) return;
                if (!ctx.mounted) return;
              }
            }

            setSheet(() => isSaving = true);

            String? imageUrl = existingImageUrl;
            if (pickedImageBytes != null) {
              imageUrl = await _repo.uploadCropImage(
                  pickedImageBytes!, pickedImageExt ?? 'jpg');
            }

            bool ok;
            try {
              if (existing == null) {
                ok = await _repo.addCrop(
                  name: nameCtrl.text,
                  category: selectedCategory!,
                  cropType: selectedCropType!,
                  imageUrl: imageUrl,
                );
              } else {
                ok = await _repo.updateCrop(
                  id: existing.id,
                  name: nameCtrl.text,
                  category: selectedCategory!,
                  cropType: selectedCropType!,
                  imageUrl: imageUrl,
                );
              }
            } on CropDuplicateException catch (e) {
              setSheet(() => isSaving = false);
              if (!ctx.mounted) return;
              // Shown in front of the Add/Edit Crop modal itself, not as a
              // SnackBar tucked at the screen edge — this error needs to be
              // seen immediately, in the same place the user is looking.
              await showDialog<void>(
                context: ctx,
                builder: (dialogCtx) => AlertDialog(
                  title: Text(l10n.cropMgmtAlreadyExistsTitle,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                  content: Text(e.message, style: GoogleFonts.inter(fontSize: 13)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: Text(l10n.cropMgmtOk),
                    ),
                  ],
                ),
              );
              return;
            }
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (ok) _load();
            ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
              content: Text(ok
                  ? existing == null
                      ? l10n.cropMgmtAddedSuccess
                      : l10n.cropMgmtUpdatedSuccess
                  : l10n.cropMgmtFailedTryAgain),
              backgroundColor:
                  ok ? AppConstants.successGreen : AppConstants.errorRed,
              behavior: SnackBarBehavior.floating,
            ));
          }

          return ManagementModalShell(
            title: existing == null ? l10n.cropMgmtAddNewTitle : l10n.cropMgmtEditTitle,
            body: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // DA-AMAD Market is exclusive to Ginger — it never
                  // appears as a choosable option for any other crop, and
                  // for Ginger itself the field locks to it rather than
                  // leaving it pickable, since several server-side guards
                  // (create_listing_with_reservation, is_cooperative_eligible)
                  // now depend on Ginger's crop_type actually being
                  // da_amad_market. See M-marketplace-7.
                  Builder(builder: (fieldCtx) {
                    final isGinger = nameCtrl.text.trim().toLowerCase() == 'ginger';
                    if (isGinger) {
                      final cs = Theme.of(fieldCtx).colorScheme;
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline_rounded, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.cropMgmtMarketTypeGingerNote,
                                style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return AppDropdownField<String>(
                      value: selectedCropType == 'da_amad_market' ? null : selectedCropType,
                      hintText: l10n.cropMgmtMarketTypeHint,
                      labelText: l10n.cropMgmtMarketTypeLabel,
                      helperText: l10n.cropMgmtMarketTypeHelper,
                      items: const ['sp3_cooperative', 'open_market'],
                      itemLabel: (v) => MarketTypeDisplay.label(l10n, v),
                      onChanged: (v) => setSheet(() => selectedCropType = v),
                      validator: (v) => v == null ? l10n.cropMgmtMarketTypeRequired : null,
                    );
                  }),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.cropMgmtCropNameLabel,
                      hintText: 'e.g. Ginger, Banana',
                    ),
                    textCapitalization: TextCapitalization.words,
                    onChanged: (v) => setSheet(() {
                      if (v.trim().toLowerCase() == 'ginger') selectedCropType = 'da_amad_market';
                    }),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return l10n.cropMgmtCropNameRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  AppDropdownField<String>(
                    value: selectedCategory,
                    hintText: l10n.commonSelectCategory,
                    labelText: l10n.adminInvCategoryLabel,
                    items: categoryOptions,
                    itemLabel: (c) => c,
                    onChanged: (v) => setSheet(() => selectedCategory = v),
                    validator: (v) => v == null ? l10n.adminInvCategoryRequired : null,
                    addNewLabel: l10n.adminInvAddNewCategory,
                    onAddNew: () async {
                      final name = await promptForNewOptionName(
                        ctx,
                        title: l10n.cropMgmtAddCategoryTitle,
                        hintText: 'e.g. Herb',
                      );
                      if (name == null) return null;
                      final added = await _categoryRepo.addCropCategory(name);
                      if (added == null) return null;
                      setSheet(() {
                        if (!categoryOptions.contains(added)) {
                          categoryOptions = [...categoryOptions, added];
                        }
                      });
                      if (mounted && !_categories.contains(added)) {
                        setState(() => _categories = [..._categories, added]);
                      }
                      return added;
                    },
                  ),
                  const SizedBox(height: 14),
                  Text(l10n.cropMgmtCropImageLabel,
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: pickImage,
                    child: Container(
                      height: 120,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                        border: Border.all(
                            color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.2)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: pickedImageBytes != null
                          ? Image.memory(pickedImageBytes!, fit: BoxFit.cover)
                          : (existingImageUrl != null
                              ? Image.network(existingImageUrl, fit: BoxFit.cover)
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate_outlined,
                                        color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                                    const SizedBox(height: 4),
                                    Text(l10n.cropMgmtTapToAddPhoto,
                                        style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                                  ],
                                )),
                    ),
                  ),
                ],
              ),
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving
                  ? l10n.adminInvSaving
                  : existing == null
                      ? l10n.cropMgmtAddCropAction
                      : l10n.cropMgmtSaveChanges,
              isLoading: isSaving,
              onPrimary: submit,
            ),
          );
        });
      },
    );
  }

  void _showArchivedSheet() async {
    final l10n = AppLocalizations.of(context);
    final all = await _repo.fetchAll();
    final archived = all.where((c) => !c.isActive).toList();
    if (!mounted) return;

    showManagementModal(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return ManagementModalShell(
          title: l10n.cropMgmtArchivedTitle,
          subtitle: l10n.cropMgmtArchivedCount(archived.length),
          bodyIsScrollable: true,
          body: archived.isEmpty
              ? Center(
                  child: Text(
                    l10n.cropMgmtNoArchivedCrops,
                    style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  itemCount: archived.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: cs.outline.withValues(alpha: 0.08)),
                  itemBuilder: (_, i) {
                    final crop = archived[i];
                    return MaterialListTile(
                      tileColor: Colors.transparent,
                      contentPadding: EdgeInsets.zero,
                      title: Text(crop.cropName,
                          style: GoogleFonts.inter(
                              fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface)),
                      subtitle: Text(crop.category,
                          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                      trailing: GestureDetector(
                        onTap: () async {
                          final ok = await _repo.toggleActive(crop.id, true);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (ok) _load();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                          ),
                          child: Text(l10n.commonRestore,
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppConstants.primaryGreen)),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  void _confirmDelete(CropMasterItem crop) async {
    final l10n = AppLocalizations.of(context);
    final usageCount = await _repo.fetchCropUsageCount(crop.id);
    if (!mounted) return;

    if (usageCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: Text(l10n.cropMgmtCannotDeleteTitle(crop.cropName),
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            content: Text(
              l10n.cropMgmtInUseBody(usageCount,
                  usageCount == 1 ? l10n.cropMgmtRecordSingular : l10n.cropMgmtRecordPlural),
              style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.cropMgmtOk),
              ),
            ],
          );
        },
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(l10n.cropMgmtDeleteTitle(crop.cropName),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: Text(
            l10n.cropMgmtDeleteBody,
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.farmerMgmtCancel),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await _repo.deleteCrop(crop.id);
                if (ok) _load();
              },
              child: Text(l10n.commonDelete,
                  style: const TextStyle(color: AppConstants.errorRed)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;

    // Group by category
    final Map<String, List<CropMasterItem>> grouped = {};
    for (final c in filtered) {
      grouped.putIfAbsent(c.category, () => []).add(c);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: _isOnline
          ? FloatingActionButton(
              onPressed: _showAddSheet,
              backgroundColor: AppConstants.primaryGreen,
              child: const Icon(Icons.add_rounded, color: Colors.white),
            )
          : null,
      body: Column(
        children: [
          // Top bar
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 64 + MediaQuery.of(context).padding.top,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                  left: 8, right: 8,
                ),
                decoration: BoxDecoration(
                  color: sagana.glassBackground,
                  border: Border(
                      bottom: BorderSide(color: sagana.glassBorder)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded,
                          color: cs.onSurface),
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(
                        l10n.cropMgmtTitle,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.archive_rounded, color: cs.onSurface),
                      tooltip: l10n.cropMgmtViewArchivedCrops,
                      onPressed: _showArchivedSheet,
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (!_isOnline)
            Container(
              color: AppConstants.warningAmber,
              padding: const EdgeInsets.symmetric(
                  vertical: 6, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      size: 14, color: AppConstants.charcoal),
                  const SizedBox(width: 6),
                  Text(l10n.cropMgmtOfflineNotice,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.charcoal)),
                ],
              ),
            ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppConstants.primaryGreen,
                        strokeWidth: 2))
                : RefreshIndicator(
                    color: AppConstants.primaryGreen,
                    onRefresh: _load,
                    child: filtered.isEmpty
                        ? ListView(children: [
                            if (_pendingRequestCount > 0) ...[
                              GestureDetector(
                                onTap: () => context
                                    .push(AppRoutes.cropRequestApproval)
                                    .then((_) => _load()),
                                child: Container(
                                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppConstants.amber
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(
                                        AppConstants.radiusLg),
                                    border: Border.all(
                                        color: AppConstants.amber
                                            .withValues(alpha: 0.25)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                          Icons.pending_actions_rounded,
                                          color: AppConstants.amber,
                                          size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '$_pendingRequestCount crop request${_pendingRequestCount == 1 ? '' : 's'} awaiting review',
                                          style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: cs.onSurface),
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded,
                                          color: AppConstants.amber),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 100),
                            Center(
                              child: Column(children: [
                                Icon(Icons.grass_rounded,
                                    size: 48,
                                    color: cs.onSurfaceVariant),
                                const SizedBox(height: 12),
                                Text(l10n.cropMgmtNoCropsInList,
                                    style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant)),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _showAddSheet,
                                  child: Text(l10n.cropMgmtAddFirstCrop),
                                ),
                              ]),
                            ),
                          ])
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(
                                20, 16, 20, 40),
                            children: [
                              // KPI cards (dashboard.md section 4) — replaces
                              // the old "N crops in master list" text pill.
                              // The Crop Requests KPI card below (tappable,
                              // same destination) now covers what the old
                              // pending-requests banner showed here —
                              // removed to avoid showing the same count
                              // twice, same reasoning as the Inventory
                              // Management depleted-count fix.
                              // "Archived" (not "Inactive" — matches this
                              // screen's own established terminology: the
                              // is_active=false state is called Archived
                              // everywhere else here, e.g. _showArchivedSheet,
                              // cropMgmtArchivedTitle) and tappable straight
                              // into that existing archived-crops list.
                              // Farmer Crop Requests mirrors the same
                              // pending-count pattern, tappable into the
                              // existing crop request approval workflow.
                              // Grouped inside the same outer titled
                              // container the Report tab uses (Executive
                              // Snapshot etc.), not just individually
                              // restyled cards.
                              ReportSectionCard(
                                title: 'Crop Overview',
                                icon: Icons.grass_rounded,
                                accent: AppConstants.primaryGreen,
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ReportIconStatCard(
                                            icon: Icons.grass_rounded,
                                            accent: AppConstants.primaryGreen,
                                            label: 'Total Crops',
                                            value: '${filtered.length}',
                                          ),
                                        ),
                                        const SizedBox(width: AppConstants.spacingSm),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: _showArchivedSheet,
                                            child: ReportIconStatCard(
                                              icon: Icons.inventory_2_outlined,
                                              accent: AppConstants.warningAmber,
                                              label: 'Archived',
                                              value: '${_crops.length - filtered.length}',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppConstants.spacingSm),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ReportIconStatCard(
                                            icon: Icons.category_rounded,
                                            accent: AppConstants.buyerBlue,
                                            label: l10n.reportsCategories,
                                            value: '${grouped.keys.length}',
                                          ),
                                        ),
                                        const SizedBox(width: AppConstants.spacingSm),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => context
                                                .push(AppRoutes.cropRequestApproval)
                                                .then((_) => _load()),
                                            child: ReportIconStatCard(
                                              icon: Icons.pending_actions_rounded,
                                              accent: AppConstants.amber,
                                              label: 'Crop Requests',
                                              value: '$_pendingRequestCount',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Grouped by category — each group a
                              // horizontally-scrolling row (image, name,
                              // market type) instead of a fixed 2x2 grid,
                              // so a category with many crops (e.g.
                              // Vegetable) doesn't crowd the screen
                              // vertically; the admin swipes through it
                              // instead. Archived crops are reached via the
                              // Archive icon in the top bar now, not a
                              // bottom button.
                              for (final category in grouped.keys) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: 8, top: 4),
                                  child: Text(
                                    category.toUpperCase(),
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: 200,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: grouped[category]!.length,
                                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                                    itemBuilder: (_, i) {
                                      final crop = grouped[category]![i];
                                      return SizedBox(
                                        width: 140,
                                        child: _CropCard(
                                          crop: crop,
                                          cs: cs,
                                          sagana: sagana,
                                          onTap: () => _showEditSheet(crop),
                                          onArchive: () async {
                                            final ok = await _repo.toggleActive(
                                                crop.id, false);
                                            if (ok) _load();
                                          },
                                          onDelete: () => _confirmDelete(crop),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Crop card (two-column grid) ─────────────────────────────────────────────

class _CropCard extends StatelessWidget {
  final CropMasterItem crop;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const _CropCard({
    required this.crop,
    required this.cs,
    required this.sagana,
    required this.onTap,
    required this.onArchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  (crop.imageUrl != null && crop.imageUrl!.isNotEmpty)
                      ? Image.network(crop.imageUrl!, fit: BoxFit.cover)
                      : Container(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                          child: Icon(Icons.eco_rounded,
                              size: 32, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                        ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, size: 18, color: Colors.white),
                      onSelected: (v) {
                        switch (v) {
                          case 'archive': onArchive(); break;
                          case 'delete': onDelete(); break;
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'archive',
                          child: Row(children: [
                            const Icon(Icons.archive_rounded, size: 16),
                            const SizedBox(width: 8),
                            Text(l10n.commonArchive, style: GoogleFonts.inter()),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            const Icon(Icons.delete_rounded, size: 16, color: AppConstants.errorRed),
                            const SizedBox(width: 8),
                            Text(l10n.commonDelete, style: GoogleFonts.inter(color: AppConstants.errorRed)),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  if (!crop.isActive)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                        ),
                        child: Text(l10n.cropMgmtArchivedBadge,
                            style: GoogleFonts.inter(
                                fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    crop.cropName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: crop.isActive ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    crop.cropTypeLabel(l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}