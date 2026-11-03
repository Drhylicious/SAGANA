import '../../widgets/view_only_banner.dart';
import '../../../data/services/staff_permission_service.dart';
import '../../../data/models/cooperative_inventory_item.dart';
import 'dart:async';
import '../../../core/utils/client_id.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/services/table_change_watcher.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/cooperative_inventory_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/input_validation_utils.dart';
import '../../../data/repositories/admin_activity_repository.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../data/repositories/unit_repository.dart';
import '../../widgets/add_unit_dialog.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/report_summary_widgets.dart'
    show ReportIconStatCard, ReportSectionCard;
import '../../widgets/management_modal.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../../data/models/admin_log_message.dart';

// ── Models ───────────────────────────────────────────────────────────────────

/// Source is required on every inventory item (rule: checkInventorySource).
/// The database enforces the same limits and is the final authority.
String? _validateInventorySource(String? value, AppLocalizations l10n) {
  switch (checkInventorySource(value)) {
    case InventorySourceIssue.empty:
      return l10n.adminInvSourceRequired;
    case InventorySourceIssue.tooLong:
      return l10n.adminInvSourceTooLong;
    case null:
      return null;
  }
}

// ── Repository ───────────────────────────────────────────────────────────────

class _CoopInventoryRepository {
  final _client = Supabase.instance.client;

  Future<List<InventoryItem>> fetchAll({bool archived = false}) async {
    // Page through all rows; do not hide distinct Farmers with UI deduplication.
    final result = <InventoryItem>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await _client
          .from('cooperative_inventory')
          .select()
          .eq('is_active', !archived)
          .order('category')
          .order('item_name')
          .order('id')
          .range(offset, offset + 499);
      result.addAll(rows.map(InventoryItem.fromMap));
      if (rows.length < 500) return result;
    }
  }

  Future<bool> itemExists({required String name}) async {
    try {
      final rows = await _client
          .from('cooperative_inventory')
          .select('id, item_name')
          .isFilter('source_farmer_id', null)
          .isFilter('archived_at', null)
          .order('item_name');
      final normalizedName = name.trim().toLowerCase();
      // Name alone is the identity of an inventory item — category and unit
      // are attributes of that item, not part of what distinguishes it from
      // another item. Matching on all three let "Peanut Seeds" (Seeds, kg)
      // and "Peanut seeds" (Seeds, bag) coexist as two unlinked rows.
      return rows.any((row) {
        final existingName = (row['item_name'] as String? ?? '')
            .trim()
            .toLowerCase();
        return existingName == normalizedName;
      });
    } catch (_) {
      return false;
    }
  }

  // Same owner-folder upload idiom as uploadCropImage()/uploadListingPhoto(),
  // against the cooperative_inventory_images bucket provisioned in
  // supabase_schema_inventory_images_feature.sql.
  Future<String?> uploadInventoryImage(
    Uint8List bytes,
    String fileExtension,
  ) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;
      final path =
          '$uid/item_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      await _client.storage
          .from('cooperative_inventory_images')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      return _client.storage
          .from('cooperative_inventory_images')
          .getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  Future<bool> addItem({
    required String name,
    required String category,
    required String unit,
    double? unitCost,
    required double reorderLevel,
    required String source,
    String? imageUrl,
  }) async {
    try {
      final duplicate = await itemExists(name: name);
      if (duplicate) return false;
      await _client.from('cooperative_inventory').insert({
        'item_name': name.trim(),
        'category': category,
        'unit': unit,
        'unit_cost': unitCost,
        'reorder_level': reorderLevel,
        'source': source.trim(),
        'image_url': imageUrl,
        'created_by': _client.auth.currentUser?.id,
      });
      AdminActivityRepository().log(
        module: 'inventory',
        actionType: 'created',
        message: AdminLogMessage('adminLogInventoryItemAdded', {
          'name': name.trim(),
          'category': category,
        }),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> adjustStock({
    required String inventoryId,
    required double quantity, // positive = restock, negative = deduct
    required String transactionType,
    required String requestId,
    String? harvestDate,
    String? storageLocation,
    String? notes,
  }) async {
    try {
      // Row-locked and idempotent; actor and audit records are server-owned.
      await _client.rpc(
        'adjust_cooperative_stock',
        params: {
          'p_inventory_id': inventoryId,
          'p_quantity': quantity,
          'p_transaction_type': transactionType,
          'p_notes': notes?.trim(),
          'p_request_id': requestId,
          'p_harvest_date': harvestDate,
          'p_storage_location': storageLocation,
        },
      );
      AdminActivityRepository().log(
        module: 'inventory',
        actionType: transactionType,
        message: quantity >= 0
            ? AdminLogMessage('adminLogStockAdded', {
                'qty': '${quantity.abs()}',
                'type': transactionType,
              })
            : AdminLogMessage('adminLogStockDeducted', {
                'qty': '${quantity.abs()}',
                'type': transactionType,
              }),
        referenceId: inventoryId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateReorderLevel(String id, double level) async {
    try {
      await _client
          .from('cooperative_inventory')
          .update({'reorder_level': level})
          .eq('id', id);
      AdminActivityRepository().log(
        module: 'inventory',
        actionType: 'reorder_level_updated',
        message: const AdminLogMessage('adminLogReorderLevelUpdated'),
        referenceId: id,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateItem({
    required String id,
    required String name,
    required String category,
    required String unit,
    double? unitCost,
    required double reorderLevel,
    required String source,
    String? imageUrl,
  }) async {
    try {
      await _client
          .from('cooperative_inventory')
          .update({
            'item_name': name.trim(),
            'category': category,
            'unit': unit,
            'unit_cost': unitCost,
            'reorder_level': reorderLevel,
            'source': source.trim(),
            'image_url': imageUrl,
          })
          .eq('id', id);
      AdminActivityRepository().log(
        module: 'inventory',
        actionType: 'updated',
        message: AdminLogMessage('adminLogInventoryItemUpdated', {
          'name': name.trim(),
        }),
        referenceId: id,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteItem(String id) async {
    try {
      await _client.rpc(
        'delete_inventory_item',
        params: {'p_inventory_id': id},
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class AdminInventoryScreen extends StatefulWidget {
  /// Pre-selects this category's filter chip on load — used when
  /// navigating here from Cooperative Stock Report's item rows, so the
  /// admin lands with the relevant item already narrowed into view
  /// instead of having to find it in the full unfiltered list.
  final String? initialCategoryFilter;

  const AdminInventoryScreen({super.key, this.initialCategoryFilter});

  @override
  State<AdminInventoryScreen> createState() => _AdminInventoryScreenState();
}

class _AdminInventoryScreenState extends State<AdminInventoryScreen> {
  final _repo = _CoopInventoryRepository();
  final _categoryRepo = CategoryRepository();
  final _unitRepo = UnitRepository();

  List<InventoryItem> _items = [];
  List<String> _categories = [];
  bool _isLoading = true;
  bool _loadError = false;
  bool _showArchived = false;
  late final TableChangeWatcher _watcher;
  StreamSubscription<bool>? _connectivitySub;
  bool _isOnline = true;
  String? _categoryFilter;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Unit-of-measure options, read from the units table (shared with Price
  // Management); the fallback list only stands in until the first read.
  List<String> _units = UnitRepository.fallbackUnits;

  static const _transactionTypes = ['restock', 'adjustment', 'written_off'];

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _categoryFilter = widget.initialCategoryFilter;
    _isOnline = ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged
        .listen((v) {
          if (!mounted) return;
          setState(() => _isOnline = v);
          if (v) _load();
        });
    _watcher = TableChangeWatcher(
      tables: const ['cooperative_inventory'],
      onChange: () {
        if (mounted && _isOnline) _load();
      },
    )..start();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _watcher.dispose();
    _connectivitySub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = false;
    });
    try {
      final results = await Future.wait([
        _repo.fetchAll(archived: _showArchived),
        _categoryRepo.fetchInventoryCategories(),
        _unitRepo.fetchUnits(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<InventoryItem>;
        _categories = results[1] as List<String>;
        _units = results[2] as List<String>;
      });
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<InventoryItem> get _filtered {
    return _items.where((i) {
      final matchesCategory =
          _categoryFilter == null || i.category == _categoryFilter;
      final matchesSearch =
          _searchQuery.isEmpty ||
          i.itemName.toLowerCase().contains(_searchQuery) ||
          (i.source?.toLowerCase().contains(_searchQuery) ?? false);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  // Filter chips only ever show a category that currently has at least one
  // item — unlike _categories (the full master list, still used as-is for
  // the Add/Edit item category dropdown). Filtering _categories down rather
  // than deriving straight from _items keeps the master table's ordering.
  List<String> get _activeCategories =>
      _categories.where((c) => _items.any((i) => i.category == c)).toList();

  // Depleted (0 on hand) is always at or below any reorder level, so it
  // always needs replenishment — counted here regardless of whether a
  // reorder level has even been configured yet. A non-depleted item only
  // counts once its own reorder level is set and its stock has fallen to
  // or below it (that's what isLow checks).
  int get _lowStockCount => _items.where((i) => i.isDepleted || i.isLow).length;

  void _showAddSheet() {
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final reorderCtrl = TextEditingController();
    final sourceCtrl = TextEditingController();
    String? selectedCategory;
    String? selectedUnit;
    bool isSaving = false;
    Uint8List? pickedImageBytes;
    String? pickedImageExt;
    // Local copy so the sheet's own dropdown updates immediately when a
    // category is added inline, without waiting for the screen behind it
    // to rebuild (it isn't listening to this already-open dialog route).
    var categoryOptions = List<String>.of(_categories);
    var unitOptions = List<String>.of(_units);

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
              if (isSaving || !_isOnline) return;
              if (!formKey.currentState!.validate()) return;
              setSheet(() => isSaving = true);
              String? imageUrl;
              if (pickedImageBytes != null) {
                imageUrl = await _repo.uploadInventoryImage(
                  pickedImageBytes!,
                  pickedImageExt ?? 'jpg',
                );
              }
              final ok = await _repo.addItem(
                name: nameCtrl.text,
                category: selectedCategory!,
                unit: selectedUnit!,
                unitCost: costCtrl.text.trim().isEmpty
                    ? null
                    : double.tryParse(costCtrl.text.trim()),
                reorderLevel: double.tryParse(reorderCtrl.text.trim()) ?? 0,
                source: sourceCtrl.text,
                imageUrl: imageUrl,
              );
              if (!ctx.mounted || !mounted) return;
              Navigator.pop(ctx);
              if (ok) _load();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok ? l10n.adminInvItemAdded : l10n.adminInvItemSaveError,
                  ),
                  backgroundColor: ok
                      ? AppConstants.midGreen
                      : AppConstants.errorRed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }

            return ManagementModalShell(
              title: l10n.adminInvAddItemTitle,
              subtitle: l10n.adminInvAddItemSubtitle,
              body: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                          title: l10n.adminInvAddCategoryTitle,
                          hintText: 'e.g. Dairy',
                        );
                        if (name == null) return null;
                        final added = await _categoryRepo.addInventoryCategory(
                          name,
                        );
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
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.adminInvItemNameLabel,
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return l10n.adminInvItemNameRequired;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.adminInvItemPhotoLabel,
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
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate_outlined,
                                    color: Theme.of(
                                      ctx,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tap to add a photo',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: Theme.of(
                                        ctx,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: AppDropdownField<String>(
                            value: selectedUnit,
                            hintText: 'Unit',
                            labelText: l10n.adminInvUnitLabel,
                            // An item saved with a unit that is no longer in
                            // the list (older data) still shows its own unit.
                            items: [
                              ...unitOptions,
                              if (selectedUnit != null &&
                                  !unitOptions.contains(selectedUnit))
                                selectedUnit!,
                            ],
                            itemLabel: (u) => u,
                            onChanged: (v) => setSheet(() => selectedUnit = v),
                            validator: (v) =>
                                v == null ? l10n.adminInvUnitRequired : null,
                            addNewLabel: l10n.unitAddNewOption,
                            onAddNew: () async {
                              final added = await promptAddUnit(
                                ctx,
                                repo: _unitRepo,
                                existing: unitOptions,
                              );
                              if (added == null) return null;
                              setSheet(() {
                                if (!unitOptions.contains(added)) {
                                  unitOptions = [...unitOptions, added];
                                }
                              });
                              if (mounted && !_units.contains(added)) {
                                setState(() => _units = [..._units, added]);
                              }
                              return added;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Unit Cost *',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Theme.of(
                                    ctx,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: costCtrl,
                                style: GoogleFonts.inter(fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: '0.00',
                                  prefixText: '₱ ',
                                  isDense: true,
                                  // Same height as the Unit dropdown beside it (its box is 50 tall).
                                  constraints: const BoxConstraints(
                                    minHeight: 50,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Theme.of(ctx).colorScheme.outline
                                          .withValues(alpha: 0.4),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Theme.of(ctx).colorScheme.primary,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d*'),
                                  ),
                                ],
                                validator: (value) {
                                  if ((value ?? '').trim().isEmpty) {
                                    return 'Unit cost is required';
                                  }
                                  if (!isValidCurrencyValue(value)) {
                                    return l10n.adminInvEnterValidAmount;
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: reorderCtrl,
                      decoration: InputDecoration(
                        labelText: '${l10n.adminInvReorderLevel} *',
                        hintText: l10n.adminInvReorderHint,
                        suffixText: l10n.adminInvUnitsSuffix,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Reorder level is required';
                        }
                        if (!isValidWholeNumberValue(value)) {
                          return l10n.adminInvEnterWholeNumber;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: sourceCtrl,
                      decoration: InputDecoration(
                        labelText: '${l10n.adminInvSourceLabel} *',
                        hintText: l10n.adminInvSourceHint,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: kInventorySourceMaxLength,
                      maxLines: 2,
                      validator: (v) => _validateInventorySource(v, l10n),
                    ),
                  ],
                ),
              ),
              footer: ManagementModalActions(
                primaryLabel: isSaving
                    ? l10n.adminInvSaving
                    : l10n.adminInvAddItem,
                isLoading: isSaving,
                onPrimary: submit,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showLoanCatalogSheet(InventoryItem item) async {
    final l10n = AppLocalizations.of(context);
    final repo = InventoryRepository();
    final existing = await repo.fetchLoanCatalogLink(item.id);
    final priceCtrl = TextEditingController(
      text: existing?['unit_price']?.toString() ?? '',
    );
    // The catalog shows the inventory item's Source (read-only), not a loan
    // note. Any note already saved on an existing catalog row is kept as is.
    final existingLoanNotes = existing?['notes'] as String?;
    final sourceDisplayCtrl = TextEditingController(
      text: item.source ?? l10n.adminInvSourceNotRecorded,
    );
    bool isSaving = false;

    if (!mounted) return;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> submit() async {
              if (isSaving || !_isOnline) return;
              final loanPrice = double.tryParse(priceCtrl.text.trim());
              if (loanPrice == null || loanPrice < 0) return;

              setSheet(() => isSaving = true);
              final ok = existing == null
                  ? await repo.publishToLoanCatalog(
                      inventoryItemId: item.id,
                      loanPrice: loanPrice,
                    )
                  // Delegates to AdminLoanRepository — the loan-domain
                  // repository — rather than duplicating this write here.
                  // See loan_item_management_screen.dart for the other
                  // caller of the same method.
                  : await AdminLoanRepository().updateLoanCatalogRules(
                      loanItemId: existing['id'] as String,
                      unitPrice: loanPrice,
                      // Keep the item's current state: updating the price of
                      // an archived loan item must not bring it back.
                      isLoanEligible:
                          existing['is_loan_eligible'] as bool? ?? true,
                      notes: existingLoanNotes,
                    );

              if (!ctx.mounted || !mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? (existing == null
                              ? l10n.adminInvPublishedToCatalog
                              : l10n.adminInvLoanCatalogUpdated)
                        : l10n.adminInvLoanCatalogError,
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
                  ? l10n.adminInvPublishToCatalogTitle
                  : l10n.adminInvUpdateCatalogTitle,
              subtitle: item.source == null
                  ? item.itemName
                  : '${item.itemName} · ${l10n.adminInvSourceLabel}: ${item.source}',
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // An archived loan item stays manageable here (price, stock),
                  // but is not offered for new loans until restored in the
                  // Loan Item Catalog. Say so, so a restock isn't mistaken for
                  // putting it back on loan.
                  if (existing != null &&
                      existing['is_loan_eligible'] == false) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppConstants.warningAmber.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.archive_outlined,
                            size: 18,
                            color: AppConstants.warningAmber,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.adminInvLoanArchivedNote,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                height: 1.4,
                                color: Theme.of(ctx).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: priceCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.adminInvLoanPriceLabel,
                      prefixText: '₱ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sourceDisplayCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: l10n.adminInvSourceLabel,
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              footer: ManagementModalActions(
                primaryLabel: isSaving
                    ? l10n.adminInvSaving
                    : (existing == null
                          ? l10n.adminInvPublish
                          : l10n.adminInvUpdate),
                isLoading: isSaving,
                onPrimary: submit,
              ),
            );
          },
        );
      },
    );
  }

  void _showReorderLevelDialog(InventoryItem item) {
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    final levelCtrl = TextEditingController(
      text: item.reorderLevel > 0 ? item.reorderLevel.toStringAsFixed(0) : '',
    );
    bool isSaving = false;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> submit() async {
              if (isSaving || !_isOnline) return;
              final level = double.tryParse(levelCtrl.text.trim());
              if (level == null || level <= 0) return;
              setSheet(() => isSaving = true);
              final ok = await _repo.updateReorderLevel(item.id, level);
              if (!ctx.mounted || !mounted) return;
              Navigator.pop(ctx);
              if (ok) _load();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? l10n.adminInvStockUpdated
                        : l10n.adminInvFailedTryAgain,
                  ),
                  backgroundColor: ok
                      ? AppConstants.midGreen
                      : AppConstants.errorRed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }

            return ManagementModalShell(
              title: l10n.adminInvReorderAt,
              subtitle:
                  '${item.itemName} · Current: ${formatQuantity(item.quantityOnHand)} ${item.unit}',
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'This is the minimum stock level that flags this item as low '
                    'stock and triggers the reorder alert.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppConstants.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: levelCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '${l10n.adminInvReorderLevel} *',
                      suffixText: item.unit,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                  ),
                ],
              ),
              footer: ManagementModalActions(
                primaryLabel: isSaving
                    ? l10n.adminInvSaving
                    : l10n.adminInvUpdate,
                isLoading: isSaving,
                onPrimary: submit,
              ),
            );
          },
        );
      },
    );
  }

  void _showAdjustSheet(InventoryItem item) {
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    // Same behavior as the Farmer's Harvest Entry form: the date is picked
    // (today by default) and the storage location is the locked, single
    // cooperative location (AppConstants.harvestStorageLocations).
    var harvestDate = DateTime.now();
    final storageLocation = AppConstants.harvestStorageLocations.first;
    final requestId = newClientId();
    bool attempted = false;
    String selectedType = 'restock';
    bool isSaving = false;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final isDeduction =
                selectedType == 'written_off' || selectedType == 'adjustment';
            // Date and location describe stock that comes in, so they apply
            // to a restock of Harvest Stock only.
            final isHarvestAddition =
                item.category == 'Harvest Stock' && !isDeduction;

            Future<void> pickHarvestDate() async {
              // Same picker as the Farmer's Harvest Entry form: from 2000
              // (the batch numbering accepts 2000-2099) up to today.
              final picked = await showDatePicker(
                context: ctx,
                initialDate: harvestDate,
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
              if (picked != null) setSheet(() => harvestDate = picked);
            }

            Future<void> submit() async {
              if (isSaving || !_isOnline) return;
              final qty = parseDecimal(qtyCtrl.text);
              if (qty != null && qty == 0) {
                AppToast.show(ctx, l10n.coopInvQuantityZero, isError: true);
                return;
              }
              if (qty == null || (isDeduction && qty > item.available)) {
                AppToast.show(
                  ctx,
                  l10n.coopInvInvalidAdjustment,
                  isError: true,
                );
                return;
              }
              setSheet(() {
                isSaving = true;
                attempted = true;
              });
              final ok = await _repo.adjustStock(
                inventoryId: item.id,
                quantity: isDeduction ? -qty : qty,
                transactionType: selectedType,
                requestId: requestId,
                harvestDate: isHarvestAddition
                    ? DateFormat('yyyy-MM-dd').format(harvestDate)
                    : null,
                storageLocation: isHarvestAddition ? storageLocation : null,
                notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
              );
              if (!ctx.mounted) return;
              if (ok) {
                Navigator.pop(ctx);
                _load();
              } else {
                setSheet(() => isSaving = false);
              }
              if (mounted) {
                AppToast.show(
                  context,
                  ok ? l10n.adminInvStockUpdated : l10n.coopInvAdjustmentRetry,
                  isError: !ok,
                );
              }
            }

            return ManagementModalShell(
              title: l10n.adminInvAdjustStockTitle,
              subtitle:
                  '${item.itemName} · Current: ${formatQuantity(item.quantityOnHand)} ${item.unit}',
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The app's own dropdown, like the Add/Edit Item sheets. Locked
                  // after a submit so a retry sends the identical request.
                  IgnorePointer(
                    ignoring: attempted,
                    child: AppDropdownField<String>(
                      value: selectedType,
                      hintText: l10n.adminInvTransactionTypeLabel,
                      labelText: l10n.adminInvTransactionTypeLabel,
                      items: _transactionTypes,
                      itemLabel: (t) => {
                        'restock': l10n.adminInvRestockAddStock,
                        'adjustment': l10n.adminInvAdjustmentDeduct,
                        'written_off': l10n.adminInvWriteOffLossDamage,
                      }[t]!,
                      onChanged: (v) {
                        if (v != null) setSheet(() => selectedType = v);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyCtrl,
                    readOnly: attempted,
                    decoration: InputDecoration(
                      labelText: l10n.adminInvQuantityLabel,
                      suffixText: item.unit,
                      hintText: isDeduction
                          ? l10n.adminInvAmountToDeduct
                          : l10n.adminInvAmountToAdd,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                  ),
                  if (isHarvestAddition) ...[
                    const SizedBox(height: 12),
                    // Date picker, as in the Farmer's Harvest Entry form.
                    InkWell(
                      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                      onTap: attempted ? null : pickHarvestDate,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: l10n.coopInvHarvestDate,
                          suffixIcon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 18,
                            color: AppConstants.primaryGreen,
                          ),
                        ),
                        child: Text(
                          DateFormat('MMMM d, yyyy').format(harvestDate),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppConstants.onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Locked, like Storage Location on the Harvest Entry form:
                    // the cooperative has one physical storage location.
                    TextFormField(
                      key: ValueKey(storageLocation),
                      initialValue: storageLocation,
                      readOnly: true,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppConstants.onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.coopInvStorage,
                        filled: true,
                        fillColor: const Color(0xFFE6F6FF),
                        suffixIcon: const Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: AppConstants.outline,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    readOnly: attempted,
                    decoration: InputDecoration(
                      labelText: l10n.issueLoanNotes,
                      hintText: l10n.adminInvAdjustmentNoteHint,
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              footer: ManagementModalActions(
                primaryLabel: isSaving
                    ? l10n.adminInvSaving
                    : l10n.adminInvConfirmAdjustment,
                isLoading: isSaving,
                onPrimary: submit,
              ),
            );
          },
        );
      },
    );
  }

  void _showTransactionHistory(InventoryItem item) {
    showManagementModal(
      context: context,
      builder: (_) => CooperativeInventoryHistory(
        inventoryId: item.id,
        itemName: '${item.itemName} · ${item.source ?? ''}',
      ),
    );
  }

  Widget _menuRow(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.inter(fontSize: 13, color: color)),
      ],
    );
  }

  void _showEditSheet(InventoryItem item) {
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: item.itemName);
    final costCtrl = TextEditingController(
      text: item.unitCost != null ? item.unitCost!.toStringAsFixed(2) : '',
    );
    final reorderCtrl = TextEditingController(
      text: item.reorderLevel.toStringAsFixed(0),
    );
    final sourceCtrl = TextEditingController(text: item.source ?? '');
    String? selectedCategory = item.category;
    String? selectedUnit = item.unit;
    bool isSaving = false;
    Uint8List? pickedImageBytes;
    String? pickedImageExt;
    String? existingImageUrl = item.imageUrl;
    var categoryOptions = List<String>.of(_categories);
    var unitOptions = List<String>.of(_units);

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
              if (isSaving || !_isOnline) return;
              if (!formKey.currentState!.validate()) return;
              setSheet(() => isSaving = true);
              String? imageUrl = existingImageUrl;
              if (pickedImageBytes != null) {
                imageUrl = await _repo.uploadInventoryImage(
                  pickedImageBytes!,
                  pickedImageExt ?? 'jpg',
                );
              }
              final ok = await _repo.updateItem(
                id: item.id,
                name: nameCtrl.text,
                category: selectedCategory!,
                unit: selectedUnit!,
                unitCost: costCtrl.text.trim().isEmpty
                    ? null
                    : double.tryParse(costCtrl.text.trim()),
                reorderLevel: double.tryParse(reorderCtrl.text.trim()) ?? 0,
                source: sourceCtrl.text,
                imageUrl: imageUrl,
              );
              if (!ctx.mounted || !mounted) return;
              Navigator.pop(ctx);
              if (ok) _load();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok ? 'Item updated' : l10n.adminInvItemSaveError,
                  ),
                  backgroundColor: ok
                      ? AppConstants.midGreen
                      : AppConstants.errorRed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }

            return ManagementModalShell(
              title: 'Edit Item',
              subtitle: item.itemName,
              body: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.isFarmerHarvest) Text(l10n.coopInvIdentityLocked),
                    AbsorbPointer(
                      absorbing: item.isFarmerHarvest,
                      child: AppDropdownField<String>(
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
                            title: l10n.adminInvAddCategoryTitle,
                            hintText: 'e.g. Dairy',
                          );
                          if (name == null) return null;
                          final added = await _categoryRepo
                              .addInventoryCategory(name);
                          if (added == null) return null;
                          setSheet(() {
                            if (!categoryOptions.contains(added)) {
                              categoryOptions = [...categoryOptions, added];
                            }
                          });
                          if (mounted && !_categories.contains(added)) {
                            setState(
                              () => _categories = [..._categories, added],
                            );
                          }
                          return added;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      readOnly: item.isFarmerHarvest,
                      decoration: InputDecoration(
                        labelText: l10n.adminInvItemNameLabel,
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return l10n.adminInvItemNameRequired;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.adminInvItemPhotoLabel,
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
                            : (existingImageUrl != null &&
                                      existingImageUrl!.isNotEmpty
                                  ? Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(
                                          existingImageUrl!,
                                          fit: BoxFit.cover,
                                        ),
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: GestureDetector(
                                            onTap: () => setSheet(() {
                                              existingImageUrl = null;
                                              pickedImageBytes = null;
                                            }),
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(
                                                color: Colors.black54,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close_rounded,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
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
                                          'Tap to add a photo',
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
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: AbsorbPointer(
                            absorbing: item.isFarmerHarvest,
                            child: AppDropdownField<String>(
                              value: selectedUnit,
                              hintText: 'Unit',
                              labelText: l10n.adminInvUnitLabel,
                              // An item saved with a unit that is no longer in
                              // the list (older data) still shows its own unit.
                              items: [
                                ...unitOptions,
                                if (selectedUnit != null &&
                                    !unitOptions.contains(selectedUnit))
                                  selectedUnit!,
                              ],
                              itemLabel: (u) => u,
                              onChanged: (v) =>
                                  setSheet(() => selectedUnit = v),
                              validator: (v) =>
                                  v == null ? l10n.adminInvUnitRequired : null,
                              addNewLabel: l10n.unitAddNewOption,
                              onAddNew: () async {
                                final added = await promptAddUnit(
                                  ctx,
                                  repo: _unitRepo,
                                  existing: unitOptions,
                                );
                                if (added == null) return null;
                                setSheet(() {
                                  if (!unitOptions.contains(added)) {
                                    unitOptions = [...unitOptions, added];
                                  }
                                });
                                if (mounted && !_units.contains(added)) {
                                  setState(() => _units = [..._units, added]);
                                }
                                return added;
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Unit Cost *',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Theme.of(
                                    ctx,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: costCtrl,
                                style: GoogleFonts.inter(fontSize: 14),
                                decoration: const InputDecoration(
                                  hintText: '0.00',
                                  prefixText: '₱ ',
                                  isDense: true,
                                  // Same height as the Unit dropdown beside it (its box is 50 tall).
                                  constraints: BoxConstraints(minHeight: 50),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d*'),
                                  ),
                                ],
                                validator: (value) {
                                  if ((value ?? '').trim().isEmpty) {
                                    return 'Unit cost is required';
                                  }
                                  if (!isValidCurrencyValue(value)) {
                                    return l10n.adminInvEnterValidAmount;
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: reorderCtrl,
                      decoration: InputDecoration(
                        labelText: '${l10n.adminInvReorderLevel} *',
                        hintText: l10n.adminInvReorderHint,
                        suffixText: l10n.adminInvUnitsSuffix,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Reorder level is required';
                        }
                        if (!isValidWholeNumberValue(value)) {
                          return l10n.adminInvEnterWholeNumber;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: sourceCtrl,
                      readOnly: item.isFarmerHarvest,
                      decoration: InputDecoration(
                        labelText: '${l10n.adminInvSourceLabel} *',
                        hintText: l10n.adminInvSourceHint,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: kInventorySourceMaxLength,
                      maxLines: 2,
                      validator: (v) => _validateInventorySource(v, l10n),
                    ),
                  ],
                ),
              ),
              footer: ManagementModalActions(
                primaryLabel: isSaving
                    ? l10n.adminInvSaving
                    : l10n.adminInvUpdate,
                isLoading: isSaving,
                onPrimary: submit,
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteItem(InventoryItem item) async {
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l = AppLocalizations.of(context);
    if (item.quantityOnHand != 0 || item.quantityReserved != 0) {
      AppToast.show(context, l.coopInvArchiveStockFirst, isError: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.coopInvArchiveTitle),
        content: Text(l.coopInvArchiveExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonArchive),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await _repo.deleteItem(item.id);
    if (!mounted) return;
    AppToast.show(
      context,
      ok ? l.coopInvArchived : l.adminInvFailedTryAgain,
      isError: !ok,
    );
    if (ok) _load();
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  // Best-effort icon per category — categories are admin-managed and
  // open-ended (see category_repository.dart), so a category added after
  // this list falls back to the generic inventory icon rather than having
  // no icon at all. Same accepted tradeoff as FarmerCropModel.iconForCategory.
  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Fertilizer':
        return Icons.eco_rounded;
      case 'Seeds':
        return Icons.grass_rounded;
      case 'Animal Feeds':
        return Icons.pets_rounded;
      case 'Pesticide':
        return Icons.bug_report_rounded;
      case 'Tools & Equipment':
        return Icons.handyman_rounded;
      case 'Harvest Stock':
        return Icons.agriculture_rounded;
      case 'Livestock':
        return Icons.cruelty_free_rounded;
      default:
        return Icons.inventory_2_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;

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
          // Archive button at the top right, like the Loan Catalog; it switches
          // between active and archived/inactive items.
          SubPageTopBar(
            title: l10n.adminInvManagementTitle,
            onBack: () => context.pop(),
            trailing: IconButton(
              icon: Icon(
                _showArchived
                    ? Icons.unarchive_rounded
                    : Icons.archive_rounded,
                color: _showArchived ? AppConstants.primaryGreen : cs.onSurface,
              ),
              tooltip: _showArchived
                  ? l10n.coopInvShowActive
                  : l10n.coopInvShowArchived,
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() => _showArchived = !_showArchived);
                      _load();
                    },
            ),
          ),

          if (!_isOnline)
            Container(
              color: AppConstants.warningAmber,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 14,
                    color: AppConstants.charcoal,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context).offlineChangesNotSaved,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.charcoal,
                    ),
                  ),
                ],
              ),
            ),

          if (_showArchived)
            Container(
              width: double.infinity,
              color: AppConstants.primaryGreen.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.archive_rounded,
                    size: 16,
                    color: AppConstants.primaryGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.coopInvViewingArchived,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loadError
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.coopInvLoadError),
                        TextButton(onPressed: _load, child: Text(l10n.retry)),
                      ],
                    ),
                  )
                : _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : RefreshIndicator(
                    color: AppConstants.primaryGreen,
                    onRefresh: _load,
                    // Single outer scrollable so the KPI cards and category
                    // chips scroll away with the list below them, instead
                    // of staying pinned as static siblings above it (per
                    // your Item B request — matches Crop Management /
                    // Price Management's own KPI-inside-the-list pattern).
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                      children: [
                        if (_items.isNotEmpty) ...[
                          // KPI cards (dashboard.md section 3) — grouped
                          // inside the same outer titled container the
                          // Report tab uses (Executive Snapshot etc.),
                          // not just individually-restyled cards.
                          ReportSectionCard(
                            title: 'Inventory Overview',
                            icon: Icons.inventory_2_rounded,
                            accent: AppConstants.buyerBlue,
                            child: Row(
                              children: [
                                Expanded(
                                  child: ReportIconStatCard(
                                    icon: Icons.inventory_2_rounded,
                                    accent: AppConstants.buyerBlue,
                                    label: l10n.reportsTotalItems,
                                    value: '${_items.length}',
                                  ),
                                ),
                                const SizedBox(width: AppConstants.spacingSm),
                                Expanded(
                                  child: ReportIconStatCard(
                                    icon: Icons.warning_amber_rounded,
                                    accent: AppConstants.warningAmber,
                                    label: l10n.reportsLowStockItems,
                                    value: '$_lowStockCount',
                                  ),
                                ),
                                const SizedBox(width: AppConstants.spacingSm),
                                Expanded(
                                  child: ReportIconStatCard(
                                    icon: Icons.category_rounded,
                                    accent: AppConstants.primaryGreen,
                                    label: l10n.reportsCategories,
                                    value:
                                        '${{for (final i in _items) i.category}.length}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Search bar
                          TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: l10n.adminInvSearchHint,
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
                          // Category filter — only shows a category that
                          // currently has at least one item (_activeCategories),
                          // updating live as the catalog changes.
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.zero,
                            child: Row(
                              children: [
                                _Chip(
                                  label: l10n.reportsAll,
                                  selected: _categoryFilter == null,
                                  onTap: () =>
                                      setState(() => _categoryFilter = null),
                                  cs: cs,
                                  sagana: sagana,
                                ),
                                ..._activeCategories.map(
                                  (cat) => Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: _Chip(
                                      label: cat,
                                      selected: _categoryFilter == cat,
                                      onTap: () =>
                                          setState(() => _categoryFilter = cat),
                                      cs: cs,
                                      sagana: sagana,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (filtered.isEmpty)
                          Column(
                            children: [
                              const SizedBox(height: 60),
                              Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.inventory_2_rounded,
                                      size: 48,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      l10n.adminInvNoItemsYet,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: _showAddSheet,
                                      child: Text(l10n.adminInvAddFirstItem),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final item = filtered[i];
                              final stockColor = item.isDepleted
                                  ? AppConstants.errorRed
                                  : item.isLow
                                  ? AppConstants.warningAmber
                                  : AppConstants.successGreen;
                              final stockLabel = item.isDepleted
                                  ? l10n.adminDashDepletedBadge
                                  : item.isLow
                                  ? l10n.reportsLowStockBadge
                                  : l10n.adminInvInStockBadge;

                              return Container(
                                decoration: BoxDecoration(
                                  color: sagana.cardBackground,
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusLg,
                                  ),
                                  border: Border.all(
                                    color: cs.outline.withValues(alpha: 0.10),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.03,
                                      ),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Container(width: 4, color: stockColor),
                                      Padding(
                                        padding: const EdgeInsets.all(14),
                                        // Align, not a bare ClipRRect — the
                                        // outer card Row uses
                                        // CrossAxisAlignment.stretch (so the
                                        // left accent bar spans the full
                                        // card height), which was also
                                        // stretching this fixed 68x68 image
                                        // box to that same full height,
                                        // turning it into a tall rectangle
                                        // instead of a square. Align sizes
                                        // to the child's own size within the
                                        // stretched space instead of
                                        // stretching the child itself, and
                                        // centers it as a side effect.
                                        child: Align(
                                          alignment: Alignment.center,
                                          child: ClipRRect(
                                            // Matches Loan Item Catalog's
                                            // approved 68x68 rounded-square
                                            // presentation (was a 40x40
                                            // circle — too small to actually
                                            // see the photo).
                                            borderRadius: BorderRadius.circular(
                                              AppConstants.radiusMd,
                                            ),
                                            child: SizedBox(
                                              width: 68,
                                              height: 68,
                                              child:
                                                  (item.imageUrl != null &&
                                                      item.imageUrl!.isNotEmpty)
                                                  ? Image.network(
                                                      item.imageUrl!,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (
                                                            _,
                                                            __,
                                                            ___,
                                                          ) => Container(
                                                            color: stockColor
                                                                .withValues(
                                                                  alpha: 0.12,
                                                                ),
                                                            child: Icon(
                                                              _categoryIcon(
                                                                item.category,
                                                              ),
                                                              color: stockColor,
                                                              size: 28,
                                                            ),
                                                          ),
                                                    )
                                                  : Container(
                                                      color: stockColor
                                                          .withValues(
                                                            alpha: 0.12,
                                                          ),
                                                      child: Icon(
                                                        _categoryIcon(
                                                          item.category,
                                                        ),
                                                        color: stockColor,
                                                        size: 28,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          item.itemName,
                                                          style:
                                                              GoogleFonts.poppins(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: cs
                                                                    .onSurface,
                                                              ),
                                                        ),
                                                        Text(
                                                          item.category,
                                                          style: GoogleFonts.inter(
                                                            fontSize: 11,
                                                            color: cs
                                                                .onSurfaceVariant,
                                                          ),
                                                        ),
                                                        Text(
                                                          item.source == null
                                                              ? l10n.adminInvSourceNotRecorded
                                                              : item.isFarmerHarvest
                                                              ? '${l10n.coopInvFarmer}: ${item.source}'
                                                              : '${l10n.adminInvSourceLabel}: ${item.source}',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: GoogleFonts.inter(
                                                            fontSize: 11,
                                                            fontStyle:
                                                                item.source ==
                                                                    null
                                                                ? FontStyle
                                                                      .italic
                                                                : FontStyle
                                                                      .normal,
                                                            color: cs
                                                                .onSurfaceVariant,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: stockColor
                                                          .withValues(
                                                            alpha: 0.12,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            AppConstants
                                                                .radiusFull,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      stockLabel,
                                                      style: GoogleFonts.inter(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: stockColor,
                                                        letterSpacing: 0.4,
                                                      ),
                                                    ),
                                                  ),
                                                  PopupMenuButton<String>(
                                                    padding: EdgeInsets.zero,
                                                    icon: Icon(
                                                      Icons.more_vert_rounded,
                                                      size: 20,
                                                      color:
                                                          cs.onSurfaceVariant,
                                                    ),
                                                    onSelected: (value) {
                                                      switch (value) {
                                                        case 'edit':
                                                          if (_isOnline &&
                                                              !_showArchived) {
                                                            _showEditSheet(
                                                              item,
                                                            );
                                                          }
                                                        case 'adjust':
                                                          if (_isOnline &&
                                                              !_showArchived) {
                                                            _showAdjustSheet(
                                                              item,
                                                            );
                                                          }
                                                        case 'publish':
                                                          if (_isOnline &&
                                                              !_showArchived) {
                                                            _showLoanCatalogSheet(
                                                              item,
                                                            );
                                                          }
                                                        case 'history':
                                                          _showTransactionHistory(
                                                            item,
                                                          );
                                                        case 'delete':
                                                          if (_isOnline &&
                                                              !_showArchived) {
                                                            _confirmDeleteItem(
                                                              item,
                                                            );
                                                          }
                                                      }
                                                    },
                                                    itemBuilder: (ctx) => [
                                                      PopupMenuItem(
                                                        value: 'edit',
                                                        enabled:
                                                            _isOnline &&
                                                            !_showArchived,
                                                        child: _menuRow(
                                                          Icons.edit_outlined,
                                                          'Edit Item',
                                                          cs.onSurface,
                                                        ),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 'adjust',
                                                        enabled:
                                                            _isOnline &&
                                                            !_showArchived,
                                                        child: _menuRow(
                                                          Icons.tune_rounded,
                                                          l10n.adminInvAdjustStockTitle,
                                                          cs.onSurface,
                                                        ),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 'publish',
                                                        enabled:
                                                            _isOnline &&
                                                            !_showArchived,
                                                        child: _menuRow(
                                                          Icons
                                                              .request_page_rounded,
                                                          l10n.adminInvPublish,
                                                          cs.onSurface,
                                                        ),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 'history',
                                                        child: _menuRow(
                                                          Icons.history_rounded,
                                                          l10n.adminInvHistoryAction,
                                                          cs.onSurface,
                                                        ),
                                                      ),
                                                      const PopupMenuDivider(),
                                                      PopupMenuItem(
                                                        value: 'delete',
                                                        enabled:
                                                            _isOnline &&
                                                            !_showArchived,
                                                        child: _menuRow(
                                                          Icons
                                                              .delete_outline_rounded,
                                                          l10n.commonArchive,
                                                          AppConstants.errorRed,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              // Scrollable, not a bare Row —
                                              // the 68x68 item image (was
                                              // 40x40) leaves less width for
                                              // this 3-stat row, and it was
                                              // already tight enough with
                                              // longer unit strings (e.g.
                                              // "bag") to overflow rather
                                              // than just wrap awkwardly.
                                              SingleChildScrollView(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                child: Row(
                                                  children: [
                                                    _StockStat(
                                                      label:
                                                          l10n.adminInvOnHand,
                                                      value:
                                                          '${formatQuantity(item.quantityOnHand)} ${item.unit}',
                                                      color: stockColor,
                                                    ),
                                                    const SizedBox(width: 16),
                                                    _StockStat(
                                                      label: l10n
                                                          .adminInvAvailable,
                                                      value:
                                                          '${formatQuantity(item.available)} ${item.unit}',
                                                      color: cs.onSurface,
                                                    ),
                                                    const SizedBox(width: 16),
                                                    // Always shown (not just
                                                    // when > 0) and tappable —
                                                    // items created before
                                                    // Reorder Level became a
                                                    // required field have it
                                                    // unset at 0, which used to
                                                    // hide this stat entirely
                                                    // and left no way to fix it
                                                    // from the UI. Since Low
                                                    // Stock only counts items
                                                    // with a reorder level set
                                                    // (reorderLevel > 0), an
                                                    // unset item can never
                                                    // register as low — this is
                                                    // the actual fix for that,
                                                    // not just a display tweak.
                                                    GestureDetector(
                                                      onTap:
                                                          _isOnline &&
                                                              !_showArchived
                                                          ? () =>
                                                                _showReorderLevelDialog(
                                                                  item,
                                                                )
                                                          : null,
                                                      child: _StockStat(
                                                        label: l10n
                                                            .adminInvReorderAt,
                                                        value:
                                                            item.reorderLevel >
                                                                0
                                                            ? '${item.reorderLevel.toStringAsFixed(0)} ${item.unit}'
                                                            : 'Not set',
                                                        color:
                                                            item.reorderLevel >
                                                                0
                                                            ? cs.onSurfaceVariant
                                                            : AppConstants
                                                                  .warningAmber,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (item.unitCost != null ||
                                                  item.lastRestockedAt !=
                                                      null) ...[
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    if (item.unitCost != null)
                                                      Text(
                                                        '₱${item.unitCost!.toStringAsFixed(2)} / ${item.unit}',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: GoogleFonts.inter(
                                                          fontSize: 11,
                                                          color: cs
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    if (item.unitCost != null &&
                                                        item.lastRestockedAt !=
                                                            null)
                                                      Text(
                                                        ' · ',
                                                        style: GoogleFonts.inter(
                                                          fontSize: 11,
                                                          color: cs
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    if (item.lastRestockedAt !=
                                                        null)
                                                      Flexible(
                                                        child: Text(
                                                          l10n.adminInvLastRestocked(
                                                            _formatDate(
                                                              item.lastRestockedAt!,
                                                            ),
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: GoogleFonts.inter(
                                                            fontSize: 11,
                                                            color: cs
                                                                .onSurfaceVariant,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                              const SizedBox(height: 12),
                                              // Stock level progress bar
                                              if (item.reorderLevel > 0) ...[
                                                ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: LinearProgressIndicator(
                                                    value:
                                                        (item.quantityOnHand /
                                                                (item.reorderLevel *
                                                                    3))
                                                            .clamp(0.0, 1.0),
                                                    minHeight: 6,
                                                    backgroundColor: cs.outline
                                                        .withValues(
                                                          alpha: 0.12,
                                                        ),
                                                    valueColor:
                                                        AlwaysStoppedAnimation(
                                                          stockColor,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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

// Same camera-vs-gallery bottom sheet already established for farmer
// listing photos (create_listing_screen.dart's _PhotoSourceSheet) — a
// separate local copy here rather than a shared extraction, to keep this
// phase scoped to Inventory Management only.
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
                leading: const Icon(
                  Icons.photo_camera_rounded,
                  color: AppConstants.primaryGreen,
                ),
                title: Text(
                  'Take Photo',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: AppConstants.primaryGreen,
                ),
                title: Text(
                  'Upload Photo',
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

class _StockStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StockStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? cs.primary : sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: selected ? cs.primary : cs.outline.withValues(alpha: 0.20),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
