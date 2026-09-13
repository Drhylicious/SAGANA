import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/management_modal.dart';
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
  // disagreeing on what a crop_type value is called.
  String get cropTypeLabel => MarketTypeDisplay.label(cropType);
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
                    title: Text('Possible Duplicate Crop',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                    content: Text(
                      'A similar crop name already exists in the master list. '
                      'Add "$trimmedName" anyway?',
                      style: GoogleFonts.inter(fontSize: 13),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: const Text('Add Anyway'),
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
                  title: Text('Crop Already Exists',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                  content: Text(e.message, style: GoogleFonts.inter(fontSize: 13)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: const Text('OK'),
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
                      ? 'Crop added successfully'
                      : 'Crop updated'
                  : 'Failed. Please try again.'),
              backgroundColor:
                  ok ? AppConstants.successGreen : AppConstants.errorRed,
              behavior: SnackBarBehavior.floating,
            ));
          }

          return ManagementModalShell(
            title: existing == null ? 'Add New Crop' : 'Edit Crop',
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
                                'Market Type: DA-AMAD Market (exclusive to Ginger)',
                                style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return AppDropdownField<String>(
                      value: selectedCropType == 'da_amad_market' ? null : selectedCropType,
                      hintText: 'Select a market type',
                      labelText: 'Market Type *',
                      helperText: 'Determines which price types apply to this crop',
                      items: const ['sp3_cooperative', 'open_market'],
                      itemLabel: (v) => MarketTypeDisplay.label(v),
                      onChanged: (v) => setSheet(() => selectedCropType = v),
                      validator: (v) => v == null ? 'Market type is required' : null,
                    );
                  }),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Crop Name *',
                      hintText: 'e.g. Ginger, Banana',
                    ),
                    textCapitalization: TextCapitalization.words,
                    onChanged: (v) => setSheet(() {
                      if (v.trim().toLowerCase() == 'ginger') selectedCropType = 'da_amad_market';
                    }),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Crop name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  AppDropdownField<String>(
                    value: selectedCategory,
                    hintText: 'Select a category',
                    labelText: 'Category *',
                    items: categoryOptions,
                    itemLabel: (c) => c,
                    onChanged: (v) => setSheet(() => selectedCategory = v),
                    validator: (v) => v == null ? 'Category is required' : null,
                    addNewLabel: 'Add new category',
                    onAddNew: () async {
                      final name = await promptForNewOptionName(
                        ctx,
                        title: 'Add Crop Category',
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
                  Text('Crop Image',
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
                                    Text('Tap to add a photo (optional)',
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
                  ? 'Saving…'
                  : existing == null
                      ? 'Add Crop'
                      : 'Save Changes',
              isLoading: isSaving,
              onPrimary: submit,
            ),
          );
        });
      },
    );
  }

  void _showArchivedSheet() async {
    final all = await _repo.fetchAll();
    final archived = all.where((c) => !c.isActive).toList();
    if (!mounted) return;

    showManagementModal(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return ManagementModalShell(
          title: 'Archived Crops',
          subtitle: '${archived.length} archived',
          bodyIsScrollable: true,
          body: archived.isEmpty
              ? Center(
                  child: Text(
                    'No archived crops',
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
                          child: Text('Restore',
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
    final usageCount = await _repo.fetchCropUsageCount(crop.id);
    if (!mounted) return;

    if (usageCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: Text('Cannot Delete "${crop.cropName}"',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            content: Text(
              'This crop is currently used by $usageCount farmer '
              '${usageCount == 1 ? 'record' : 'records'}. Deactivate it '
              'instead, or remove it from those farmer records first.',
              style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
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
          title: Text('Delete "${crop.cropName}"?',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: Text(
            'This will permanently remove the crop from the master list. '
            'This crop is not currently used by any farmer records.',
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await _repo.deleteCrop(crop.id);
                if (ok) _load();
              },
              child: const Text('Delete',
                  style: TextStyle(color: AppConstants.errorRed)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                        'Crop Management',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
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
                  Text('Offline — changes will not be saved',
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
                                Text('No crops in master list',
                                    style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant)),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _showAddSheet,
                                  child: const Text('Add First Crop'),
                                ),
                              ]),
                            ),
                          ])
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(
                                20, 16, 20, 40),
                            children: [
                              // Pending crop requests banner
                              if (_pendingRequestCount > 0) ...[
                                GestureDetector(
                                  onTap: () => context
                                      .push(AppRoutes.cropRequestApproval)
                                      .then((_) => _load()),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 16),
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
                              // Summary pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(
                                      AppConstants.radiusMd),
                                ),
                                child: Row(children: [
                                  Icon(Icons.grass_rounded,
                                      size: 16, color: cs.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${filtered.length} crop${filtered.length == 1 ? '' : 's'} in master list',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary,
                                    ),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 16),

                              // Grouped by category, each group a two-column
                              // card grid (image, name, market type).
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
                                GridView.builder(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 0.8,
                                  ),
                                  itemCount: grouped[category]!.length,
                                  itemBuilder: (_, i) {
                                    final crop = grouped[category]![i];
                                    return _CropCard(
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
                                    );
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: _showArchivedSheet,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: sagana.cardBackground,
                                    borderRadius: BorderRadius.circular(
                                        AppConstants.radiusLg),
                                    border: Border.all(
                                        color: cs.outline.withValues(alpha: 0.10)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.archive_rounded,
                                          size: 18,
                                          color: cs.onSurfaceVariant),
                                      const SizedBox(width: 8),
                                      Text(
                                        'View Archived Crops',
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
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
                            Text('Archive', style: GoogleFonts.inter()),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            const Icon(Icons.delete_rounded, size: 16, color: AppConstants.errorRed),
                            const SizedBox(width: 8),
                            Text('Delete', style: GoogleFonts.inter(color: AppConstants.errorRed)),
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
                        child: Text('ARCHIVED',
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
                    crop.cropTypeLabel,
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