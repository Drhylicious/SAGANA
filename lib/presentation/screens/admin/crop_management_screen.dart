import '../../../core/l10n/localized_labels.dart';
import '../../widgets/view_only_banner.dart';
import '../../../data/services/staff_permission_service.dart';
import 'package:flutter/material.dart';
import '../../widgets/listing_filter_modal.dart'
    show ListingStatusFilterChip;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/utils/db_error_utils.dart';
import '../../../data/repositories/shelf_life_repository.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/record_details_sheet.dart';
import '../../../core/utils/life_duration.dart';
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
import '../../widgets/channel_only_badge.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/report_summary_widgets.dart'
    show ReportIconStatCard, ReportSectionCard;
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../../data/models/admin_log_message.dart';
import '../../../data/services/market_types_service.dart';

// ── Model ────────────────────────────────────────────────────────────────────

class CropMasterItem {
  final String id;
  final String cropName;
  final String category;
  final String cropType;
  // The one selling channel this crop is reserved for (crop_master
  // .exclusive_channel), or null. Read-only here: set in the database only.
  final String? exclusiveChannel;
  final String? description;
  final String? imageUrl;
  final bool isActive;
  final int sortOrder;

  /// Default shelf life, in days, of a newly recorded harvest of this crop
  /// (crop_master.shelf_life_days). Null = not set yet: harvests of the crop
  /// are not shelf-life tracked until it is.
  final int? shelfLifeDays;

  /// Storage Life, in days, of this crop's planting materials while they are
  /// in cooperative storage (crop_master.storage_life_days). Null = not set.
  final int? storageLifeDays;

  const CropMasterItem({
    required this.id,
    required this.cropName,
    required this.category,
    required this.cropType,
    this.exclusiveChannel,
    this.description,
    this.imageUrl,
    required this.isActive,
    required this.sortOrder,
    this.shelfLifeDays,
    this.storageLifeDays,
  });

  factory CropMasterItem.fromMap(Map<String, dynamic> m) => CropMasterItem(
    id: m['id'] as String,
    cropName: m['crop_name'] as String,
    category: m['category'] as String? ?? 'Other',
    cropType: m['crop_type'] as String? ?? '',
    exclusiveChannel: m['exclusive_channel'] as String?,
    description: m['description'] as String?,
    imageUrl: m['image_url'] as String?,
    isActive: m['is_active'] as bool? ?? true,
    sortOrder: m['sort_order'] as int? ?? 0,
    shelfLifeDays: (m['shelf_life_days'] as num?)?.toInt(),
    storageLifeDays: (m['storage_life_days'] as num?)?.toInt(),
  );

  // Delegates to the shared MarketTypeDisplay label (sagana_colors.dart)
  // instead of a third local copy of the same switch — keeps Crop
  // Management, Home, Market Rate Details, and View Market from ever
  // disagreeing on what a crop_type value is called. Takes l10n (this
  // model has no BuildContext of its own) since the label is
  // language-dependent.
  String cropTypeLabel(AppLocalizations l10n) =>
      MarketTypeDisplay.label(l10n, cropType);
}

/// "20" for 20.0, "12.5" for 12.5.
String _formatPercent(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

/// A sourced shelf-life figure for the crop name being typed, with one tap to
/// use it. The source is shown so the Manager knows where the number is from.
class _ShelfLifeSuggestion extends StatelessWidget {
  final int days;
  final String source;
  final VoidCallback onUse;

  const _ShelfLifeSuggestion({
    required this.days,
    required this.source,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.menu_book_outlined, size: 16, color: cs.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.cropMgmtShelfLifeSuggested(days),
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onUse,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text(l10n.cropMgmtShelfLifeUse),
          ),
        ],
      ),
    );
  }
}

/// Crop Management's shelf-life settings row: the expiry-day Marketplace
/// discount, and how many crops still have no shelf life.
class _ShelfLifeSettingsTile extends StatelessWidget {
  final double? discountPercent;
  final int cropsWithoutShelfLife;
  final VoidCallback onEdit;

  const _ShelfLifeSettingsTile({
    required this.discountPercent,
    required this.cropsWithoutShelfLife,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final l10n = AppLocalizations.of(context);
    return Material(
      color: sagana.cardBackground,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppConstants.warningAmber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: const Icon(
                  Icons.timelapse_rounded,
                  size: 20,
                  color: AppConstants.warningAmber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.shelfDiscountTitle,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cropsWithoutShelfLife > 0
                          ? l10n.shelfCropsNotSet(cropsWithoutShelfLife)
                          : l10n.shelfDiscountTileSub,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        height: 1.35,
                        color: cropsWithoutShelfLife > 0
                            ? AppConstants.warningAmber
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                discountPercent == null
                    ? '—'
                    : '${_formatPercent(discountPercent!)}%',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Repository ───────────────────────────────────────────────────────────────

class CropDuplicateException implements Exception {
  final String message;
  const CropDuplicateException(this.message);
}

class _CropMasterRepository {
  final _client = Supabase.instance.client;

  /// Saves a crop with its shelf life. If the database does not have the
  /// shelf_life_days column yet (the shelf-life SQL is run by hand), the crop is
  /// saved without it, exactly as before, instead of failing.
  Future<void> _withShelfLife(
    int shelfLifeDays,
    int? storageLifeDays,
    Future<void> Function(Map<String, dynamic> extra) save,
  ) async {
    try {
      try {
        await save({
          'shelf_life_days': shelfLifeDays,
          'storage_life_days': storageLifeDays,
        });
      } on PostgrestException catch (e) {
        // A database without the Storage Life column yet: save the rest.
        if (!e.message.contains('storage_life_days')) rethrow;
        await save({'shelf_life_days': shelfLifeDays});
      }
    } on PostgrestException catch (e) {
      final missing =
          e.code == 'PGRST204' ||
          e.code == '42703' ||
          e.message.contains('shelf_life_days');
      if (!missing) rethrow;
      await save(const {});
    }
  }

  Future<List<CropMasterItem>> fetchAll() async {
    try {
      final rows = await _client
          .from('crop_master')
          .select()
          .order('sort_order')
          .order('crop_name');
      return rows.map((r) => CropMasterItem.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> addCrop({
    required String name,
    required String category,
    required String cropType,
    required int shelfLifeDays,
    int? storageLifeDays,
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
          'A crop named "$trimmedName" already exists.',
        );
      }
      final row = {
        'crop_name': trimmedName,
        'category': category,
        'crop_type': cropType,
        'description': description?.trim(),
        'image_url': imageUrl,
        'created_by': _client.auth.currentUser?.id,
      };
      await _withShelfLife(
        shelfLifeDays,
        storageLifeDays,
        (extra) => _client.from('crop_master').insert({...row, ...extra}),
      );
      AdminActivityRepository().log(
        module: 'crops',
        actionType: 'created',
        message: AdminLogMessage('adminLogCropCatalogAdded', {
          'name': trimmedName,
          'category': category,
        }),
      );
      return true;
    } on CropDuplicateException {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateCrop({
    required String id,
    required String name,
    required String category,
    required String cropType,
    required int shelfLifeDays,
    int? storageLifeDays,
    String? description,
    String? imageUrl,
  }) async {
    try {
      final trimmedName = name.trim();
      final row = {
        'crop_name': trimmedName,
        'category': category,
        'crop_type': cropType,
        'description': description?.trim(),
        'image_url': imageUrl,
      };
      await _withShelfLife(
        shelfLifeDays,
        storageLifeDays,
        (extra) => _client
            .from('crop_master')
            .update({...row, ...extra})
            .eq('id', id),
      );
      AdminActivityRepository().log(
        module: 'crops',
        actionType: 'updated',
        message: AdminLogMessage('adminLogCropCatalogUpdated', {
          'name': trimmedName,
          'category': category,
        }),
        referenceId: id,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // Mirrors uploadProfilePhoto()'s pattern (profile_photo_service.dart) —
  // same owner-folder upload idiom, against the already-provisioned
  // crop_images bucket (supabase_schema_fixes.sql), just never wired to a
  // column or an upload flow until this feature.
  Future<String?> uploadCropImage(Uint8List bytes, String fileExtension) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;
      final path =
          '$uid/crop_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      await _client.storage
          .from('crop_images')
          .uploadBinary(
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
      await _client
          .from('crop_master')
          .update({'is_active': newValue})
          .eq('id', id);
      AdminActivityRepository().log(
        module: 'crops',
        actionType: newValue ? 'activated' : 'deactivated',
        message: newValue
            ? const AdminLogMessage('adminLogCropReactivated')
            : const AdminLogMessage('adminLogCropDeactivated'),
        referenceId: id,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteCrop(String id) async {
    try {
      await _client.from('crop_master').delete().eq('id', id);
      AdminActivityRepository().log(
        module: 'crops',
        actionType: 'deleted',
        message: const AdminLogMessage('adminLogCropDeleted'),
        referenceId: id,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pre-delete impact check — mirrors the Farmer-side
  /// CropRepository.fetchCropDeleteImpact() pattern. crop_master.id
  /// has no ON DELETE action on farmer_crops.crop_master_id, so an
  /// in-use crop's delete would otherwise fail with an unexplained
  /// FK violation, silently swallowed by deleteCrop()'s catch block.
  Future<int> fetchCropUsageCount(String cropId) async {
    try {
      // Every table that points at the catalog row, so a crop with prices,
      // listings or sales is reported as in use instead of failing silently
      // on a foreign-key error.
      final counts = await Future.wait([
        for (final (table, column) in const [
          ('farmer_crops', 'crop_master_id'),
          ('marketplace_listings', 'crop_id'),
          ('member_sales_transactions', 'crop_id'),
          ('price_records', 'crop_id'),
        ])
          _client.from(table).select('id').eq(column, cropId),
      ]);
      return counts.fold<int>(0, (sum, rows) => sum + rows.length);
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
    } catch (_) {
      return 0;
    }
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
  final _shelfRepo = ShelfLifeRepository();

  // The expiry-day Marketplace discount (percent); null until it can be read
  // (for example before the shelf-life SQL is applied).
  double? _expiryDiscount;
  // Sourced shelf-life figures on file, keyed by lower-case crop name.
  Map<String, ({int days, String source})> _shelfReference = const {};
  // "cropId|marketType" of every crop that has a Reference Price; null until
  // (or if) the prices can be read.
  Set<String>? _pricedCropKeys;

  List<CropMasterItem> _crops = [];
  List<String> _categories = [];
  bool _isLoading = true;
  bool _isOnline = true;
  int _pendingRequestCount = 0;
  String? _categoryFilter;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchAll(),
      _repo.fetchPendingRequestCount(),
      _categoryRepo.fetchCropCategories(),
      _shelfRepo.fetchExpiryDiscountPercent(),
      _shelfRepo.fetchReference(),
      _shelfRepo.fetchPricedCropKeys(),
    ]);
    if (!mounted) return;
    setState(() {
      _crops = results[0] as List<CropMasterItem>;
      _pendingRequestCount = results[1] as int;
      _categories = results[2] as List<String>;
      _expiryDiscount = results[3] as double?;
      _shelfReference =
          results[4] as Map<String, ({int days, String source})>;
      _pricedCropKeys = results[5] as Set<String>?;
      _isLoading = false;
    });
  }

  /// The crop has no Reference Price in its own market type yet. False while
  /// the prices could not be read, so a crop is never marked by mistake. The
  /// mark clears by itself: this is re-read whenever the screen reloads,
  /// including on return from Price Management.
  bool _needsPrice(CropMasterItem crop) {
    final keys = _pricedCropKeys;
    if (keys == null) return false;
    return !keys.contains('${crop.id}|${crop.cropType}');
  }

  /// The sourced shelf life on file for a crop name (whole-word match, the
  /// longest name first), or null. The same rule the database uses.
  ({int days, String source})? _suggestedShelfLife(String cropName) {
    final name = cropName.trim().toLowerCase();
    if (name.isEmpty) return null;
    final keys = _shelfReference.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      final pattern = RegExp('(^|[^a-z])${RegExp.escape(key)}([^a-z]|\$)');
      if (pattern.hasMatch(name)) return _shelfReference[key];
    }
    return null;
  }

  /// The Manager / an Officer with Manage access sets the expiry-day discount.
  Future<void> _editExpiryDiscount() async {
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(
      text: _expiryDiscount == null ? '' : _formatPercent(_expiryDiscount!),
    );
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        ),
        title: Text(
          l10n.shelfDiscountTitle,
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.shelfDiscountBody,
                style: GoogleFonts.inter(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.shelfDiscountFieldLabel,
                  suffixText: '%',
                ),
                validator: (v) {
                  final value = double.tryParse((v ?? '').trim());
                  if (value == null || value < 0 || value > 90) {
                    return l10n.shelfDiscountInvalid;
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(l10n.farmerMgmtCancel),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dialogCtx, double.parse(ctrl.text.trim()));
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (saved == null || !mounted) return;
    try {
      await _shelfRepo.saveExpiryDiscountPercent(saved);
      if (!mounted) return;
      setState(() => _expiryDiscount = saved);
      PostActionFeedback.success(context, l10n.shelfDiscountSaved);
    } catch (e) {
      if (!mounted) return;
      PostActionFeedback.error(context, friendlyErrorMessage(e));
    }
  }

  // All active (non-archived) crops, unfiltered by search/category — the
  // KPI cards and the Archived count always reflect this, not the
  // narrowed-down grid below, so switching search/filter never makes the
  // stats appear to change.
  List<CropMasterItem> get _filtered =>
      _crops.where((c) => c.isActive).toList();

  // What the grid actually shows: _filtered further narrowed by the
  // selected category chip and the search query (crop name match).
  List<CropMasterItem> get _displayedCrops {
    return _filtered.where((c) {
      final matchesCategory =
          _categoryFilter == null || c.category == _categoryFilter;
      final matchesSearch =
          _searchQuery.isEmpty ||
          c.cropName.toLowerCase().contains(_searchQuery);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  void _showAddSheet() => _showCropSheet(null);
  void _showEditSheet(CropMasterItem crop) => _showCropSheet(crop);

  void _showCropSheet(CropMasterItem? existing) {
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.cropName ?? '');
    final shelfCtrl = TextEditingController(
      text: existing?.shelfLifeDays?.toString() ?? '',
    );
    final storageCtrl = TextEditingController(
      text: existing?.storageLifeDays?.toString() ?? '',
    );
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
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> pickImage() async {
              final source = await showModalBottomSheet<ImageSource>(
                context: ctx,
                backgroundColor: Colors.transparent,
                builder: (_) => const _PhotoSourceSheet(),
              );
              if (source == null) return;
              final picked = await ImagePicker().pickImage(
                source: source,
                imageQuality: 80,
              );
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
              // A crop image is required (a new one, or the one it has).
              if (pickedImageBytes == null &&
                  (existingImageUrl ?? '').trim().isEmpty) {
                AppToast.show(ctx, l10n.cropMgmtImageRequired, isError: true);
                return;
              }

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
                      title: Text(
                        l10n.cropMgmtDuplicateTitle,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                      ),
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
                  pickedImageBytes!,
                  pickedImageExt ?? 'jpg',
                );
              }

              bool ok;
              try {
                if (existing == null) {
                  ok = await _repo.addCrop(
                    name: nameCtrl.text,
                    category: selectedCategory!,
                    cropType: selectedCropType!,
                    shelfLifeDays: int.parse(shelfCtrl.text.trim()),
                    storageLifeDays: int.tryParse(storageCtrl.text.trim()),
                    imageUrl: imageUrl,
                  );
                } else {
                  ok = await _repo.updateCrop(
                    id: existing.id,
                    name: nameCtrl.text,
                    category: selectedCategory!,
                    cropType: selectedCropType!,
                    shelfLifeDays: int.parse(shelfCtrl.text.trim()),
                    storageLifeDays: int.tryParse(storageCtrl.text.trim()),
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
                    title: Text(
                      l10n.cropMgmtAlreadyExistsTitle,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                    ),
                    content: Text(
                      l10n.localeName.startsWith('tl')
                          ? l10n.errDuplicate
                          : e.message,
                      style: GoogleFonts.inter(fontSize: 13),
                    ),
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
              if (!mounted) return;
              if (ok) _load();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? existing == null
                              ? l10n.cropMgmtAddedSuccess
                              : l10n.cropMgmtUpdatedSuccess
                        : l10n.cropMgmtFailedTryAgain,
                  ),
                  backgroundColor: ok
                      ? AppConstants.midGreen
                      : AppConstants.errorRed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }

            return ManagementModalShell(
              title: existing == null
                  ? l10n.cropMgmtAddNewTitle
                  : l10n.cropMgmtEditTitle,
              body: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.cropMgmtCropNameLabel,
                        hintText: AppLocalizations.of(
                          context,
                        ).enhEGBananaTomato,
                      ),
                      textCapitalization: TextCapitalization.words,
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
                      validator: (v) =>
                          v == null ? l10n.adminInvCategoryRequired : null,
                      addNewLabel: l10n.adminInvAddNewCategory,
                      onAddNew: () async {
                        final name = await promptForNewOptionName(
                          ctx,
                          title: l10n.cropMgmtAddCategoryTitle,
                          hintText: AppLocalizations.of(context).enhEGHerb,
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
                    // Market type: every crop, Ginger included, is either of the
                    // market types in the database (Public / Cooperative). The
                    // options come from market_types. A crop's exclusive selling
                    // channel (Ginger → DA-AMAD Market Linking) is NOT a market
                    // type and cannot be chosen here: it is set in the database
                    // only, and is shown at the top of the form as information
                    // when present.
                    if (existing?.exclusiveChannel != null) ...[
                      Builder(
                        builder: (noteCtx) {
                          final cs = Theme.of(noteCtx).colorScheme;
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusMd,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    l10n.cropMgmtExclusiveChannelNote(
                                      MarketTypes.instance.channelLabel(
                                        existing!.exclusiveChannel,
                                      ),
                                    ),
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                    ],
                    AppDropdownField<String>(
                      value: selectedCropType,
                      hintText: l10n.cropMgmtMarketTypeHint,
                      labelText: l10n.cropMgmtMarketTypeLabel,
                      helperText: l10n.cropMgmtMarketTypeHelper,
                      items: MarketTypes.instance.activeTypes
                          .map((t) => t.code)
                          .toList(),
                      itemLabel: (v) => MarketTypeDisplay.label(l10n, v),
                      onChanged: (v) => setSheet(() => selectedCropType = v),
                      validator: (v) =>
                          v == null ? l10n.cropMgmtMarketTypeRequired : null,
                    ),
                    const SizedBox(height: 14),
                    // Shelf life: the default for every newly recorded harvest
                    // of this crop. Each harvest batch then counts down on its
                    // own from its harvest date.
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: nameCtrl,
                      builder: (_, name, __) {
                        final suggestion = _suggestedShelfLife(name.text);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: shelfCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              decoration: InputDecoration(
                                labelText: l10n.cropMgmtShelfLifeLabel,
                                hintText: l10n.cropMgmtShelfLifeHint,
                                suffixText: l10n.shelfDaysUnit,
                              ),
                              validator: (v) {
                                final days = int.tryParse((v ?? '').trim());
                                if ((v ?? '').trim().isEmpty) {
                                  return l10n.cropMgmtShelfLifeRequired;
                                }
                                if (days == null || days < 1 || days > 3650) {
                                  return l10n.cropMgmtShelfLifeInvalid;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.cropMgmtShelfLifeHelp,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: Theme.of(
                                  ctx,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            // A sourced figure is on file for this crop name.
                            if (suggestion != null &&
                                shelfCtrl.text.trim() !=
                                    suggestion.days.toString())
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _ShelfLifeSuggestion(
                                  days: suggestion.days,
                                  source: suggestion.source,
                                  onUse: () => setSheet(
                                    () => shelfCtrl.text = suggestion.days
                                        .toString(),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    // Storage Life: for this crop's planting materials while
                    // they are kept in cooperative inventory. Required, like
                    // the Shelf Life: every crop has both.
                    TextFormField(
                      controller: storageCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.cropMgmtStorageLifeLabel,
                        hintText: l10n.cropMgmtStorageLifeHint,
                        suffixText: l10n.shelfDaysUnit,
                      ),
                      validator: (v) {
                        final text = (v ?? '').trim();
                        if (text.isEmpty) {
                          return l10n.cropMgmtStorageLifeRequired;
                        }
                        final days = int.tryParse(text);
                        return days == null || days < 1 || days > 36500
                            ? l10n.cropMgmtStorageLifeInvalid
                            : null;
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.cropMgmtStorageLifeHelp,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.cropMgmtCropImageLabel,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
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
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                          border: Border.all(
                            color: Theme.of(
                              ctx,
                            ).colorScheme.outline.withValues(alpha: 0.2),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: pickedImageBytes != null
                            ? Image.memory(pickedImageBytes!, fit: BoxFit.cover)
                            : (existingImageUrl != null
                                  ? Image.network(
                                      existingImageUrl,
                                      fit: BoxFit.cover,
                                    )
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_photo_alternate_outlined,
                                          color: Theme.of(
                                            ctx,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          l10n.cropMgmtTapToAddPhoto,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: Theme.of(
                                              ctx,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    )),
                      ),
                    ),
                    // Archive: only for a crop that exists and is live. It goes
                    // through the same confirmation the card menu uses.
                    if (existing != null && existing.isActive) ...[
                      const SizedBox(height: 20),
                      Divider(
                        height: 1,
                        color: Theme.of(
                          ctx,
                        ).colorScheme.outline.withValues(alpha: 0.12),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: isSaving
                            ? null
                            : () async {
                                final archived = await _archiveWithConfirm(
                                  existing,
                                  ctx,
                                );
                                if (archived && ctx.mounted) Navigator.pop(ctx);
                              },
                        icon: const Icon(Icons.archive_outlined, size: 18),
                        label: Text(l10n.cropMgmtArchiveCropAction),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          foregroundColor: AppConstants.warningAmber,
                          side: BorderSide(
                            color: AppConstants.warningAmber.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          textStyle: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.cropMgmtArchiveHint,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          height: 1.4,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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
          },
        );
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
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 44,
                          color: cs.outline.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.cropMgmtNoArchivedCrops,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.cropMgmtNoArchivedBody,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  // One line up top says what archiving does, then the cards.
                  itemCount: archived.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.cropMgmtArchivedInfo,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final crop = archived[i - 1];
                    return ArchivedCropCard(
                      crop: crop,
                      onRestore: () async {
                        if (!requireManage(context, StaffModule.dashboard)) {
                          return;
                        }
                        final ok = await _repo.toggleActive(crop.id, true);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (ok) _load();
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  /// Archive a crop after asking. The one place archiving is done: the card's
  /// menu and the Edit Crop sheet both call it. Archiving only stops the crop
  /// being offered for a new reference price or a new Farmer crop request; it
  /// does not touch any existing price, record or listing. Returns true when
  /// the crop was archived.
  Future<bool> _archiveWithConfirm(
    CropMasterItem crop,
    BuildContext from,
  ) async {
    if (!requireManage(context, StaffModule.dashboard)) return false;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: from,
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;
        return AlertDialog(
          icon: const Icon(
            Icons.archive_outlined,
            size: 28,
            color: AppConstants.warningAmber,
          ),
          title: Text(
            l10n.cropMgmtArchiveTitle(crop.cropName),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            l10n.cropMgmtArchiveBody,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.45,
              color: cs.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(l10n.farmerMgmtCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppConstants.warningAmber,
                foregroundColor: Colors.white,
              ),
              child: Text(l10n.cropMgmtArchiveConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return false;

    final ok = await _repo.toggleActive(crop.id, false);
    if (!mounted) return false;
    if (ok) _load();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? l10n.cropMgmtArchivedSuccess(crop.cropName)
              : l10n.cropMgmtFailedTryAgain,
        ),
        backgroundColor: ok ? AppConstants.midGreen : AppConstants.errorRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return ok;
  }

  // Read-only details of a crop (tap the card). Edit Crop is in the menu.
  void _showCropDetails(CropMasterItem crop) {
    final l10n = AppLocalizations.of(context);
    showRecordDetails(
      context,
      title: crop.cropName,
      subtitle: localizeBuiltinLabel(l10n, crop.category),
      imageUrl: crop.imageUrl,
      placeholderIcon: Icons.eco_rounded,
      sections: [
        DetailSection(
          title: l10n.detailsSectionInfo,
          rows: [
            DetailRow(
              l10n.buyerListingCategory,
              localizeBuiltinLabel(l10n, crop.category),
            ),
            DetailRow(
              l10n.detailsMarketType,
              MarketTypeDisplay.label(l10n, crop.cropType),
            ),
            DetailRow(
              l10n.shelfLifeLabel,
              crop.shelfLifeDays == null
                  ? l10n.detailsNotSet
                  : lifeDurationText(l10n, crop.shelfLifeDays!),
              valueColor: crop.shelfLifeDays == null
                  ? AppConstants.errorRed
                  : null,
            ),
            DetailRow(
              l10n.cropMgmtStorageLifeLabel,
              crop.storageLifeDays == null
                  ? l10n.detailsNotSet
                  : lifeDurationText(l10n, crop.storageLifeDays!),
              valueColor: crop.storageLifeDays == null
                  ? AppConstants.errorRed
                  : null,
            ),
            DetailRow(
              l10n.detailsReferencePrice,
              _needsPrice(crop) ? l10n.detailsNotSet : l10n.detailsSet,
              valueColor: _needsPrice(crop) ? AppConstants.errorRed : null,
            ),
            DetailRow(
              l10n.detailsStatus,
              crop.isActive ? l10n.detailsActive : l10n.cropMgmtArchivedBadge,
            ),
            if ((crop.description ?? '').trim().isNotEmpty)
              DetailRow(l10n.detailsDescription, crop.description!.trim()),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;
    final displayedCrops = _displayedCrops;
    final categoryCount = {for (final c in filtered) c.category}.length;

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
          SubPageTopBar(
            title: l10n.cropMgmtTitle,
            onBack: () => context.pop(),
            trailing: IconButton(
              icon: Icon(Icons.archive_rounded, color: cs.onSurface),
              tooltip: l10n.cropMgmtViewArchivedCrops,
              onPressed: _showArchivedSheet,
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : RefreshIndicator(
                    color: AppConstants.primaryGreen,
                    onRefresh: _load,
                    child: filtered.isEmpty
                        ? ListView(
                            children: [
                              if (_pendingRequestCount > 0) ...[
                                GestureDetector(
                                  onTap: () => context
                                      .push(AppRoutes.cropRequestApproval)
                                      .then((_) => _load()),
                                  child: Container(
                                    margin: const EdgeInsets.fromLTRB(
                                      20,
                                      16,
                                      20,
                                      0,
                                    ),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: AppConstants.amber.withValues(
                                        alpha: 0.10,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppConstants.radiusLg,
                                      ),
                                      border: Border.all(
                                        color: AppConstants.amber.withValues(
                                          alpha: 0.25,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.pending_actions_rounded,
                                          color: AppConstants.amber,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            AppLocalizations.of(
                                              context,
                                            ).enhCropRequestAwaitingReview(
                                              (_pendingRequestCount).toString(),
                                              (_pendingRequestCount == 1
                                                      ? ''
                                                      : 's')
                                                  .toString(),
                                            ),
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: cs.onSurface,
                                            ),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color: AppConstants.amber,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 100),
                              Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.grass_rounded,
                                      size: 48,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      l10n.cropMgmtNoCropsInList,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: _showAddSheet,
                                      child: Text(l10n.cropMgmtAddFirstCrop),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
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
                                title: AppLocalizations.of(
                                  context,
                                ).enhCropOverview,
                                icon: Icons.grass_rounded,
                                accent: AppConstants.primaryGreen,
                                // 4 KPI cards, horizontal-scrolling row
                                // (matches Program Management/Price
                                // Management's KPI treatment) instead of a
                                // fixed 2x2 grid.
                                child: SizedBox(
                                  height: 104,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: 4,
                                    separatorBuilder: (_, __) => const SizedBox(
                                      width: AppConstants.spacingSm,
                                    ),
                                    itemBuilder: (_, i) {
                                      final cards = <Widget>[
                                        ReportIconStatCard(
                                          icon: Icons.grass_rounded,
                                          accent: AppConstants.primaryGreen,
                                          label: AppLocalizations.of(
                                            context,
                                          ).enhTotalCrops,
                                          value: '${filtered.length}',
                                        ),
                                        GestureDetector(
                                          onTap: _showArchivedSheet,
                                          child: ReportIconStatCard(
                                            icon: Icons.inventory_2_outlined,
                                            accent: AppConstants.warningAmber,
                                            label: AppLocalizations.of(
                                              context,
                                            ).loanItemKpiArchived,
                                            value:
                                                '${_crops.length - filtered.length}',
                                          ),
                                        ),
                                        ReportIconStatCard(
                                          icon: Icons.category_rounded,
                                          accent: AppConstants.buyerBlue,
                                          label: l10n.reportsCategories,
                                          value: '$categoryCount',
                                        ),
                                        GestureDetector(
                                          onTap: () => context
                                              .push(
                                                AppRoutes.cropRequestApproval,
                                              )
                                              .then((_) => _load()),
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              ReportIconStatCard(
                                                icon: Icons
                                                    .pending_actions_rounded,
                                                accent: AppConstants.amber,
                                                label: AppLocalizations.of(
                                                  context,
                                                ).cropRequestTitle,
                                                value: '$_pendingRequestCount',
                                              ),
                                              // Makes "something needs review" obvious
                                              // without reading the number — the KPI
                                              // card alone looked like a plain stat,
                                              // not a place pending work was waiting.
                                              if (_pendingRequestCount > 0)
                                                Positioned(
                                                  top: -4,
                                                  right: -4,
                                                  child: Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration: BoxDecoration(
                                                      color:
                                                          AppConstants.errorRed,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Colors.white,
                                                        width: 2,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ];
                                      return SizedBox(
                                        width: 150,
                                        child: cards[i],
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Shelf-life settings: the expiry-day Marketplace
                              // discount, and a nudge when crops still have no
                              // shelf life set.
                              _ShelfLifeSettingsTile(
                                discountPercent: _expiryDiscount,
                                cropsWithoutShelfLife: filtered
                                    .where((c) => c.shelfLifeDays == null)
                                    .length,
                                onEdit: _editExpiryDiscount,
                              ),
                              const SizedBox(height: 16),

                              // Search bar
                              TextField(
                                controller: _searchCtrl,
                                decoration: InputDecoration(
                                  hintText: l10n.cropMgmtSearchHint,
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  filled: true,
                                  fillColor: sagana.cardBackground,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppConstants.radiusLg,
                                    ),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Category filter chips — sourced from the
                              // crop_categories master table (_categories),
                              // not from distinct values among currently
                              // active crops, so a category with zero crops
                              // still appears and the row always reflects
                              // the true, admin-managed category list.
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: EdgeInsets.zero,
                                child: Row(
                                  children: [
                                    _Chip(
                                      label: l10n.reportsAll,
                                      count: filtered.length,
                                      selected: _categoryFilter == null,
                                      onTap: () => setState(
                                        () => _categoryFilter = null,
                                      ),
                                      cs: cs,
                                      sagana: sagana,
                                    ),
                                    ..._categories.map(
                                      (cat) => Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: _Chip(
                                          label: cat,
                                          count: filtered
                                              .where((c) => c.category == cat)
                                              .length,
                                          selected: _categoryFilter == cat,
                                          onTap: () => setState(
                                            () => _categoryFilter = cat,
                                          ),
                                          cs: cs,
                                          sagana: sagana,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Single unified, responsive grid — replaces
                              // the previous per-category horizontally-
                              // scrolling sections (Vegetable/Tree Crop/
                              // etc. as separate strips). 2-column grid,
                              // same rhythm as Price Management's crop grid
                              // (which was itself modeled on this card).
                              if (displayedCrops.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 40),
                                  child: Center(
                                    child: Text(
                                      l10n.cropMgmtNoCropsMatchFilter,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                GridView.builder(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                        childAspectRatio: 0.66,
                                      ),
                                  itemCount: displayedCrops.length,
                                  itemBuilder: (_, i) {
                                    final crop = displayedCrops[i];
                                    return CropCard(
                                      crop: crop,
                                      cs: cs,
                                      sagana: sagana,
                                      onTap: () => _showCropDetails(crop),
                                      onEdit: () => _showEditSheet(crop),
                                      // No Reference Price yet in its market:
                                      // Farmers cannot list it on the
                                      // Marketplace until one is set.
                                      needsReferencePrice: _needsPrice(crop),
                                      onSetPrice: () => context
                                          .push(
                                            AppRoutes.priceManagement,
                                            extra: crop.id,
                                          )
                                          .then((_) => _load()),
                                      onArchive: () =>
                                          _archiveWithConfirm(crop, context),
                                    );
                                  },
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

// Same camera-vs-gallery bottom sheet already established for Inventory
// Management (admin_inventory_screen.dart's _PhotoSourceSheet) — a
// separate local copy here rather than a shared extraction, matching that
// same convention.
class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        // Material, not a plain Container/DecoratedBox — ListTile paints
        // its ink splashes on the nearest Material ancestor, and a
        // DecoratedBox in between hides them (surfaced as a thrown
        // assertion, not just a lint).
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.photo_camera_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  AppLocalizations.of(context).enhTakePhoto,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(
                  Icons.photo_library_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  AppLocalizations.of(context).enhUploadPhoto,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Crop card (two-column grid) ─────────────────────────────────────────────

// Same category-chip style already established for Inventory Management
// and Loan Item Catalog — a separate local copy here rather than a shared
// extraction, matching that same convention.
class _Chip extends StatelessWidget {
  final String label;

  /// How many crops the chip holds, shown as "Label (n)".
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  // The standard SAGANA filter chip, so this row matches every other one.
  @override
  Widget build(BuildContext context) {
    return ListingStatusFilterChip(
      label: label,
      count: count,
      active: selected,
      color: cs.primary,
      onTap: onTap,
      cs: cs,
    );
  }
}

/// A crop in the Crop Management grid. Public so its layout can be tested.
class CropCard extends StatelessWidget {
  final CropMasterItem crop;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onTap;
  final VoidCallback onArchive;

  /// Opens the Edit Crop form (the menu's first action).
  final VoidCallback? onEdit;

  /// No longer offered: a crop is archived, never deleted. Kept so existing
  /// callers still compile.
  final VoidCallback? onDelete;

  /// The crop has no Reference Price yet: a red mark and a "Set Price" action
  /// (to Price Management, on this crop) are shown until one is configured.
  final bool needsReferencePrice;
  final VoidCallback? onSetPrice;

  const CropCard({
    super.key,
    required this.crop,
    required this.cs,
    required this.sagana,
    required this.onTap,
    required this.onArchive,
    this.onEdit,
    this.onDelete,
    this.needsReferencePrice = false,
    this.onSetPrice,
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
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
            ),
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
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.4,
                          ),
                          child: Icon(
                            Icons.eco_rounded,
                            size: 32,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      onSelected: (v) {
                        switch (v) {
                          case 'edit':
                            onEdit?.call();
                            break;
                          case 'archive':
                            onArchive();
                            break;
                        }
                      },
                      // Edit Crop and Archive only: a crop is never deleted.
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              const Icon(Icons.edit_outlined, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                l10n.cropMgmtEditCropAction,
                                style: GoogleFonts.inter(),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'archive',
                          child: Row(
                            children: [
                              const Icon(Icons.archive_rounded, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                l10n.commonArchive,
                                style: GoogleFonts.inter(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Red mark: this crop still needs a Reference Price. It sits
                  // over the photo, so the card keeps its height.
                  if (needsReferencePrice && crop.isActive) ...[
                    Positioned(
                      top: 6,
                      left: 6,
                      right: 34,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppConstants.errorRed,
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 11,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  l10n.cropMgmtNoReferencePrice,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 6,
                      child: FilledButton.icon(
                        onPressed: onSetPrice,
                        icon: const Icon(Icons.sell_outlined, size: 14),
                        label: Text(
                          l10n.cropMgmtSetReferencePrice,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppConstants.errorRed,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(32),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (!crop.isActive)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull,
                          ),
                        ),
                        child: Text(
                          l10n.cropMgmtArchivedBadge,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
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
                  // Crop name, then category, then market type: the name
                  // leads, the category reads as a quiet subtitle, and the
                  // market type is a small coloured badge.
                  Text(
                    crop.cropName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: crop.isActive ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    localizeBuiltinLabel(
                      AppLocalizations.of(context),
                      crop.category,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Market type badge on the left, shelf life on the right: one
                  // row, so the card keeps its height.
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: MarketTypeDisplay.color(
                              context,
                              crop.cropType,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull,
                            ),
                          ),
                          child: Text(
                            crop.cropTypeLabel(l10n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: MarketTypeDisplay.color(
                                context,
                                crop.cropType,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.timelapse_rounded,
                        size: 12,
                        color: crop.shelfLifeDays == null
                            ? AppConstants.warningAmber
                            : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        crop.shelfLifeDays == null
                            ? l10n.shelfNotSetShort
                            : l10n.shelfDaysShort(crop.shelfLifeDays!),
                        maxLines: 1,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: crop.shelfLifeDays == null
                              ? AppConstants.warningAmber
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
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
// ── Archived crop card ───────────────────────────────────────────────────────

/// One archived crop: photo, name, an Archived status pill, category, market
/// type and any exclusive selling channel, the description when there is one,
/// and the two things a Manager can do with it: restore it or delete it.
class ArchivedCropCard extends StatelessWidget {
  final CropMasterItem crop;
  final VoidCallback onRestore;

  /// No longer offered: a crop is archived, never deleted. Kept so existing
  /// callers still compile.
  final VoidCallback? onDelete;

  const ArchivedCropCard({
    super.key,
    required this.crop,
    required this.onRestore,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final marketColor = MarketTypeDisplay.color(context, crop.cropType);
    final hasImage = crop.imageUrl != null && crop.imageUrl!.isNotEmpty;
    final description = crop.description?.trim() ?? '';

    Widget chip(String text, Color color, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );

    final placeholder = Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Icon(
        Icons.eco_outlined,
        size: 26,
        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  // Greyed out: it is archived, not live.
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
                      0.6, 0.3, 0.1, 0, 0, //
                      0.6, 0.3, 0.1, 0, 0,
                      0.6, 0.3, 0.1, 0, 0,
                      0, 0, 0, 1, 0,
                    ]),
                    child: hasImage
                        ? Image.network(
                            crop.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => placeholder,
                          )
                        : placeholder,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      crop.cropName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        chip(
                          l10n.cropMgmtArchivedBadge,
                          AppConstants.warningAmber,
                          icon: Icons.archive_outlined,
                        ),
                        chip(crop.cropTypeLabel(l10n), marketColor),
                        chip(
                          localizeBuiltinLabel(
                            AppLocalizations.of(context),
                            crop.category,
                          ),
                          cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                    if (crop.exclusiveChannel != null) ...[
                      const SizedBox(height: 6),
                      ChannelOnlyBadge(channel: crop.exclusiveChannel),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.unarchive_outlined, size: 16),
                  label: Text(l10n.commonRestore),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.primaryGreen,
                    textStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
