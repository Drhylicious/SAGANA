import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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
import '../../../data/services/connectivity_service.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/report_summary_widgets.dart' show ReportIconStatCard, ReportSectionCard;
import '../../widgets/management_modal.dart';

// ── Models ───────────────────────────────────────────────────────────────────

class InventoryItem {
  final String id;
  final String itemName;
  final String category;
  final String unit;
  final double quantityOnHand;
  final double quantityReserved;
  final double reorderLevel;
  final double? unitCost;
  final String? notes;
  final bool isActive;
  final DateTime? lastRestockedAt;
  final String? imageUrl;

  const InventoryItem({
    required this.id,
    required this.itemName,
    required this.category,
    required this.unit,
    required this.quantityOnHand,
    required this.quantityReserved,
    required this.reorderLevel,
    this.unitCost,
    this.notes,
    required this.isActive,
    this.lastRestockedAt,
    this.imageUrl,
  });

  double get available => quantityOnHand - quantityReserved;
  bool get isLow => reorderLevel > 0 && quantityOnHand <= reorderLevel;
  bool get isDepleted => quantityOnHand <= 0;

  factory InventoryItem.fromMap(Map<String, dynamic> m) => InventoryItem(
    id: m['id'] as String,
    itemName: m['item_name'] as String,
    category: m['category'] as String? ?? 'Agricultural Supplies',
    unit: m['unit'] as String? ?? 'kg',
    quantityOnHand: (m['quantity_on_hand'] as num?)?.toDouble() ?? 0,
    quantityReserved: (m['quantity_reserved'] as num?)?.toDouble() ?? 0,
    reorderLevel: (m['reorder_level'] as num?)?.toDouble() ?? 0,
    unitCost: m['unit_cost'] != null
        ? (m['unit_cost'] as num).toDouble()
        : null,
    notes: m['notes'] as String?,
    isActive: m['is_active'] as bool? ?? true,
    lastRestockedAt: m['last_restocked_at'] != null
        ? DateTime.parse(m['last_restocked_at'] as String)
        : null,
    imageUrl: m['image_url'] as String?,
  );
}

class InventoryTransaction {
  final String id;
  final String inventoryId;
  final String transactionType;
  final double quantity;
  final String? notes;
  final DateTime createdAt;

  const InventoryTransaction({
    required this.id,
    required this.inventoryId,
    required this.transactionType,
    required this.quantity,
    this.notes,
    required this.createdAt,
  });

  factory InventoryTransaction.fromMap(Map<String, dynamic> m) =>
      InventoryTransaction(
        id: m['id'] as String,
        inventoryId: m['inventory_id'] as String,
        transactionType: m['transaction_type'] as String,
        quantity: (m['quantity'] as num).toDouble(),
        notes: m['notes'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  bool get isIncoming => quantity > 0;
}

enum _DeleteResult { success, blockedHasPurchaseHistory, failed }

// ── Repository ───────────────────────────────────────────────────────────────

class _CoopInventoryRepository {
  final _client = Supabase.instance.client;

  Future<List<InventoryItem>> fetchAll({bool activeOnly = true}) async {
    try {
      final rows = activeOnly
          ? await _client
                .from('cooperative_inventory')
                .select()
                .eq('is_active', true)
                .order('category')
                .order('item_name')
          : await _client
                .from('cooperative_inventory')
                .select()
                .order('category')
                .order('item_name');
      final items = rows.map((r) => InventoryItem.fromMap(r)).toList();
      return _dedupeItems(items);
    } catch (_) {
      return [];
    }
  }

  List<InventoryItem> _dedupeItems(List<InventoryItem> items) {
    final seen = <String>{};
    final result = <InventoryItem>[];
    for (final item in items) {
      final key =
          '${item.itemName.trim().toLowerCase()}::${item.category.trim().toLowerCase()}::${item.unit.trim().toLowerCase()}';
      if (seen.add(key)) {
        result.add(item);
      }
    }
    return result;
  }

  Future<bool> itemExists({required String name}) async {
    try {
      final rows = await _client
          .from('cooperative_inventory')
          .select('id, item_name')
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

  Future<List<InventoryTransaction>> fetchTransactions(
    String inventoryId,
  ) async {
    try {
      final rows = await _client
          .from('inventory_transactions')
          .select()
          .eq('inventory_id', inventoryId)
          .order('created_at', ascending: false)
          .limit(20);
      return rows.map((r) => InventoryTransaction.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  // Same owner-folder upload idiom as uploadCropImage()/uploadListingPhoto(),
  // against the cooperative_inventory_images bucket provisioned in
  // supabase_schema_inventory_images_feature.sql.
  Future<String?> uploadInventoryImage(Uint8List bytes, String fileExtension) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;
      final path = '$uid/item_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      await _client.storage.from('cooperative_inventory_images').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      return _client.storage.from('cooperative_inventory_images').getPublicUrl(path);
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
    String? notes,
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
        'notes': notes?.trim(),
        'image_url': imageUrl,
        'created_by': _client.auth.currentUser?.id,
      });
      AdminActivityRepository().log(
        module: 'inventory',
        actionType: 'created',
        description: 'Added inventory item "${name.trim()}" ($category).',
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
    String? notes,
  }) async {
    try {
      // Atomic, row-locked via adjust_inventory_stock() RPC — see
      // supabase_schema_inventory_stock_adjustment_rpc.sql. Replaces the
      // previous unlocked read-then-write (Phase 2, item 2.6).
      await _client.rpc(
        'adjust_inventory_stock',
        params: {
          'p_inventory_id': inventoryId,
          'p_quantity': quantity,
          'p_transaction_type': transactionType,
          'p_notes': notes?.trim(),
          'p_recorded_by': _client.auth.currentUser?.id,
        },
      );
      AdminActivityRepository().log(
        module: 'inventory',
        actionType: transactionType,
        description:
            '${quantity >= 0 ? 'Added' : 'Deducted'} ${quantity.abs()} units of stock ($transactionType).',
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
    String? notes,
    String? imageUrl,
  }) async {
    try {
      await _client.from('cooperative_inventory').update({
        'item_name': name.trim(),
        'category': category,
        'unit': unit,
        'unit_cost': unitCost,
        'reorder_level': reorderLevel,
        'notes': notes?.trim(),
        'image_url': imageUrl,
      }).eq('id', id);
      AdminActivityRepository().log(
        module: 'inventory',
        actionType: 'updated',
        description: 'Updated inventory item "${name.trim()}".',
        referenceId: id,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // Soft-delete fallback for the one case delete_inventory_item() blocks —
  // an item with Product Sales purchase history. Reuses is_active, already
  // the filter every fetchAll() call applies.
  Future<bool> deactivateItem(String id) async {
    try {
      await _client
          .from('cooperative_inventory')
          .update({'is_active': false})
          .eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Atomic via delete_inventory_item() — see
  // supabase_schema_inventory_images_feature.sql for the full FK-chain
  // reasoning. Distinguishes the "blocked by purchase history" case (an
  // expected, recoverable outcome the UI offers deactivation for) from any
  // other failure.
  Future<_DeleteResult> deleteItem(String id) async {
    try {
      await _client.rpc('delete_inventory_item', params: {'p_inventory_id': id});
      AdminActivityRepository().log(
        module: 'inventory',
        actionType: 'deleted',
        description: 'Deleted inventory item.',
        referenceId: id,
      );
      return _DeleteResult.success;
    } catch (e) {
      if (e.toString().contains('CANNOT_DELETE_HAS_PURCHASE_HISTORY')) {
        return _DeleteResult.blockedHasPurchaseHistory;
      }
      return _DeleteResult.failed;
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

  List<InventoryItem> _items = [];
  List<String> _categories = [];
  bool _isLoading = true;
  bool _isOnline = true;
  String? _categoryFilter;

  static const _units = [
    'bag',
    'kg',
    'sack',
    'piece',
    'liter',
    'set',
    'bottle',
  ];

  static const _transactionTypes = ['restock', 'adjustment', 'written_off'];

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _categoryFilter = widget.initialCategoryFilter;
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchAll(),
      _categoryRepo.fetchInventoryCategories(),
    ]);
    if (!mounted) return;
    setState(() {
      _items = results[0] as List<InventoryItem>;
      _categories = results[1] as List<String>;
      _isLoading = false;
    });
  }

  List<InventoryItem> get _filtered {
    if (_categoryFilter == null) return _items;
    return _items.where((i) => i.category == _categoryFilter).toList();
  }

  // Depleted (0 on hand) is always at or below any reorder level, so it
  // always needs replenishment — counted here regardless of whether a
  // reorder level has even been configured yet. A non-depleted item only
  // counts once its own reorder level is set and its stock has fallen to
  // or below it (that's what isLow checks).
  int get _lowStockCount =>
      _items.where((i) => i.isDepleted || i.isLow).length;

  void _showAddSheet() {
    final l10n = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final reorderCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? selectedCategory;
    String? selectedUnit;
    bool isSaving = false;
    Uint8List? pickedImageBytes;
    String? pickedImageExt;
    // Local copy so the sheet's own dropdown updates immediately when a
    // category is added inline, without waiting for the screen behind it
    // to rebuild (it isn't listening to this already-open dialog route).
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
              final picked = await ImagePicker()
                  .pickImage(source: source, imageQuality: 80);
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
              setSheet(() => isSaving = true);
              String? imageUrl;
              if (pickedImageBytes != null) {
                imageUrl = await _repo.uploadInventoryImage(
                    pickedImageBytes!, pickedImageExt ?? 'jpg');
              }
              final ok = await _repo.addItem(
                name: nameCtrl.text,
                category: selectedCategory!,
                unit: selectedUnit!,
                unitCost: costCtrl.text.trim().isEmpty
                    ? null
                    : double.tryParse(costCtrl.text.trim()),
                reorderLevel: double.tryParse(reorderCtrl.text.trim()) ?? 0,
                notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                imageUrl: imageUrl,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (ok) _load();
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? l10n.adminInvItemAdded
                        : l10n.adminInvItemSaveError,
                  ),
                  backgroundColor: ok
                      ? AppConstants.successGreen
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
                    Text('Item Photo (optional)',
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
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined,
                                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                                  const SizedBox(height: 4),
                                  Text('Tap to add a photo',
                                      style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
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
                            items: _units,
                            itemLabel: (u) => u,
                            onChanged: (v) => setSheet(() => selectedUnit = v),
                            validator: (v) =>
                                v == null ? l10n.adminInvUnitRequired : null,
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
                                  if (!isValidCurrencyValue(value))
                                    return l10n.adminInvEnterValidAmount;
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
                        if (!isValidWholeNumberValue(value))
                          return l10n.adminInvEnterWholeNumber;
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: notesCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.issueLoanNotes,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              footer: ManagementModalActions(
                primaryLabel: isSaving ? l10n.adminInvSaving : l10n.adminInvAddItem,
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
    final notesCtrl = TextEditingController(
      text: existing?['notes'] as String? ?? '',
    );
    bool isSaving = false;

    if (!mounted) return;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> submit() async {
              final loanPrice = double.tryParse(priceCtrl.text.trim());
              if (loanPrice == null || loanPrice < 0) return;

              setSheet(() => isSaving = true);
              final ok = existing == null
                  ? await repo.publishToLoanCatalog(
                      inventoryItemId: item.id,
                      loanPrice: loanPrice,
                      notes: notesCtrl.text.trim().isEmpty
                          ? null
                          : notesCtrl.text.trim(),
                    )
                  // Delegates to AdminLoanRepository — the loan-domain
                  // repository — rather than duplicating this write here.
                  // See loan_item_management_screen.dart for the other
                  // caller of the same method.
                  : await AdminLoanRepository().updateLoanCatalogRules(
                      loanItemId: existing['id'] as String,
                      unitPrice: loanPrice,
                      isLoanEligible: true,
                      notes: notesCtrl.text.trim().isEmpty
                          ? null
                          : notesCtrl.text.trim(),
                    );

              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? (existing == null
                              ? l10n.adminInvPublishedToCatalog
                              : l10n.adminInvLoanCatalogUpdated)
                        : l10n.adminInvLoanCatalogError,
                  ),
                  backgroundColor: ok
                      ? AppConstants.successGreen
                      : AppConstants.errorRed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }

            return ManagementModalShell(
              title: existing == null
                  ? l10n.adminInvPublishToCatalogTitle
                  : l10n.adminInvUpdateCatalogTitle,
              subtitle: item.itemName,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
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
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.issueLoanNotes,
                      hintText: l10n.adminInvEligibilityHint,
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              footer: ManagementModalActions(
                primaryLabel: isSaving
                    ? l10n.adminInvSaving
                    : (existing == null ? l10n.adminInvPublish : l10n.adminInvUpdate),
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
              final level = double.tryParse(levelCtrl.text.trim());
              if (level == null || level <= 0) return;
              setSheet(() => isSaving = true);
              final ok = await _repo.updateReorderLevel(item.id, level);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (ok) _load();
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text(ok ? l10n.adminInvStockUpdated : l10n.adminInvFailedTryAgain),
                  backgroundColor: ok ? AppConstants.successGreen : AppConstants.errorRed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }

            return ManagementModalShell(
              title: l10n.adminInvReorderAt,
              subtitle: '${item.itemName} · Current: ${item.quantityOnHand.toStringAsFixed(1)} ${item.unit}',
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'This is the minimum stock level that flags this item as low '
                    'stock and triggers the reorder alert.',
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: levelCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '${l10n.adminInvReorderLevel} *',
                      suffixText: item.unit,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                  ),
                ],
              ),
              footer: ManagementModalActions(
                primaryLabel: isSaving ? l10n.adminInvSaving : l10n.adminInvUpdate,
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
    final l10n = AppLocalizations.of(context);
    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String selectedType = 'restock';
    bool isSaving = false;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final isDeduction =
                selectedType == 'written_off' || selectedType == 'adjustment';

            Future<void> submit() async {
              final qty = double.tryParse(qtyCtrl.text);
              if (qty == null || qty <= 0) return;
              setSheet(() => isSaving = true);
              final adjustedQty = isDeduction ? -qty : qty;
              final ok = await _repo.adjustStock(
                inventoryId: item.id,
                quantity: adjustedQty,
                transactionType: selectedType,
                notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (ok) _load();
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text(ok ? l10n.adminInvStockUpdated : l10n.adminInvFailedTryAgain),
                  backgroundColor: ok
                      ? AppConstants.successGreen
                      : AppConstants.errorRed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }

            return ManagementModalShell(
              title: l10n.adminInvAdjustStockTitle,
              subtitle:
                  '${item.itemName} · Current: ${item.quantityOnHand.toStringAsFixed(1)} ${item.unit}',
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: InputDecoration(
                      labelText: l10n.adminInvTransactionTypeLabel,
                    ),
                    items: _transactionTypes.map((t) {
                      final label = {
                        'restock': l10n.adminInvRestockAddStock,
                        'adjustment': l10n.adminInvAdjustmentDeduct,
                        'written_off': l10n.adminInvWriteOffLossDamage,
                      }[t]!;
                      return DropdownMenuItem(value: t, child: Text(label));
                    }).toList(),
                    onChanged: (v) => setSheet(() => selectedType = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyCtrl,
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.issueLoanNotes,
                      hintText: l10n.adminInvAdjustmentNoteHint,
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              footer: ManagementModalActions(
                primaryLabel: isSaving ? l10n.adminInvSaving : l10n.adminInvConfirmAdjustment,
                isLoading: isSaving,
                onPrimary: submit,
              ),
            );
          },
        );
      },
    );
  }

  void _showTransactionHistory(InventoryItem item) async {
    final l10n = AppLocalizations.of(context);
    final transactions = await _repo.fetchTransactions(item.id);
    if (!mounted) return;

    showManagementModal(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return ManagementModalShell(
          title: l10n.adminInvTransactionHistoryTitle,
          subtitle: item.itemName,
          bodyIsScrollable: true,
          body: transactions.isEmpty
              ? Center(
                  child: Text(
                    l10n.adminInvNoTransactionsYet,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  itemCount: transactions.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: cs.outline.withValues(alpha: 0.08),
                  ),
                  itemBuilder: (_, i) {
                    final t = transactions[i];
                    final isIn = t.isIncoming;
                    final color = isIn
                        ? AppConstants.successGreen
                        : AppConstants.errorRed;
                    final label =
                        {
                          'restock': l10n.adminInvTxnRestock,
                          'loan_issued': l10n.adminInvTxnLoanIssued,
                          'adjustment': l10n.adminInvTxnAdjustment,
                          'harvest_received': l10n.adminInvTxnHarvestIn,
                          'sold': l10n.adminInvTxnSold,
                          'returned': l10n.adminInvTxnReturned,
                          'written_off': l10n.adminInvTxnWriteOff,
                        }[t.transactionType] ??
                        t.transactionType;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isIn ? Icons.add_rounded : Icons.remove_rounded,
                              color: color,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: cs.onSurface,
                                  ),
                                ),
                                if (t.notes != null)
                                  Text(
                                    t.notes!,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${isIn ? '+' : ''}${t.quantity.toStringAsFixed(1)} ${item.unit}',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                ),
                              ),
                              Text(
                                _formatDate(t.createdAt),
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
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
    final l10n = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: item.itemName);
    final costCtrl = TextEditingController(
        text: item.unitCost != null ? item.unitCost!.toStringAsFixed(2) : '');
    final reorderCtrl =
        TextEditingController(text: item.reorderLevel.toStringAsFixed(0));
    final notesCtrl = TextEditingController(text: item.notes ?? '');
    String? selectedCategory = item.category;
    String? selectedUnit = item.unit;
    bool isSaving = false;
    Uint8List? pickedImageBytes;
    String? pickedImageExt;
    String? existingImageUrl = item.imageUrl;
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
              final picked = await ImagePicker()
                  .pickImage(source: source, imageQuality: 80);
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
              setSheet(() => isSaving = true);
              String? imageUrl = existingImageUrl;
              if (pickedImageBytes != null) {
                imageUrl = await _repo.uploadInventoryImage(
                    pickedImageBytes!, pickedImageExt ?? 'jpg');
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
                notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                imageUrl: imageUrl,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (ok) _load();
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok ? 'Item updated' : l10n.adminInvItemSaveError,
                  ),
                  backgroundColor: ok
                      ? AppConstants.successGreen
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
                    Text('Item Photo (optional)',
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
                            : (existingImageUrl != null && existingImageUrl!.isNotEmpty
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.network(existingImageUrl!, fit: BoxFit.cover),
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
                                            child: const Icon(Icons.close_rounded,
                                                size: 16, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_photo_alternate_outlined,
                                          color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                                      const SizedBox(height: 4),
                                      Text('Tap to add a photo',
                                          style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
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
                          child: AppDropdownField<String>(
                            value: selectedUnit,
                            hintText: 'Unit',
                            labelText: l10n.adminInvUnitLabel,
                            items: _units,
                            itemLabel: (u) => u,
                            onChanged: (v) => setSheet(() => selectedUnit = v),
                            validator: (v) =>
                                v == null ? l10n.adminInvUnitRequired : null,
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
                                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
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
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                ],
                                validator: (value) {
                                  if ((value ?? '').trim().isEmpty) {
                                    return 'Unit cost is required';
                                  }
                                  if (!isValidCurrencyValue(value))
                                    return l10n.adminInvEnterValidAmount;
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Reorder level is required';
                        }
                        if (!isValidWholeNumberValue(value))
                          return l10n.adminInvEnterWholeNumber;
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: notesCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.issueLoanNotes,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              footer: ManagementModalActions(
                primaryLabel: isSaving ? l10n.adminInvSaving : l10n.adminInvUpdate,
                isLoading: isSaving,
                onPrimary: submit,
              ),
            );
          },
        );
      },
    );
  }

  // Two-step: this confirmation dialog first, then delete_inventory_item()
  // does the actual work atomically. See supabase_schema_inventory_images_feature.sql
  // for the full FK-chain reasoning — a RESTRICT from program_product_purchases
  // (no item-name snapshot of its own) means an item that was ever sold
  // through Product Sales can never be safely hard-deleted, so that case is
  // blocked here with a deactivate-instead offer rather than attempted.
  void _confirmDeleteItem(InventoryItem item) async {
    final l10n = AppLocalizations.of(context);
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete "${item.itemName}"?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          'This permanently deletes this item, including its full stock '
          'transaction history. If it\'s currently published to the Loan '
          'Item Catalog, it will be un-published first. This cannot be undone.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Continue', style: TextStyle(color: AppConstants.errorRed)),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    // Second, explicit confirmation step — matches the approved "two-step
    // delete confirmation" decision.
    final finalConfirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Are you absolutely sure?'),
        content: Text(
          '"${item.itemName}" will be permanently removed. This is your final confirmation.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.errorRed),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (finalConfirm != true || !mounted) return;

    final result = await _repo.deleteItem(item.id);
    if (!mounted) return;
    if (result == _DeleteResult.blockedHasPurchaseHistory) {
      final deactivateInstead = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Can\'t delete this item'),
          content: Text(
            '"${item.itemName}" has purchase history in Product Sales and '
            'can\'t be permanently deleted without losing those records. '
            'You can deactivate it instead — it will stop appearing in '
            'the active list everywhere.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Deactivate Instead'),
            ),
          ],
        ),
      );
      if (deactivateInstead == true && mounted) {
        final ok = await _repo.deactivateItem(item.id);
        if (!mounted) return;
        if (ok) _load();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Item deactivated.' : l10n.adminInvFailedTryAgain),
            backgroundColor: ok ? AppConstants.successGreen : AppConstants.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final ok = result == _DeleteResult.success;
    if (ok) _load();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Item deleted.' : l10n.adminInvFailedTryAgain),
        backgroundColor: ok ? AppConstants.successGreen : AppConstants.errorRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
      case 'Fertilizer':             return Icons.eco_rounded;
      case 'Seeds':                  return Icons.grass_rounded;
      case 'Animal Feeds':           return Icons.pets_rounded;
      case 'Pesticide':              return Icons.bug_report_rounded;
      case 'Tools & Equipment':      return Icons.handyman_rounded;
      case 'Harvest Stock':          return Icons.agriculture_rounded;
      case 'Livestock':              return Icons.cruelty_free_rounded;
      default:                       return Icons.inventory_2_rounded;
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
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 64 + MediaQuery.of(context).padding.top,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                  left: 8,
                  right: 8,
                ),
                decoration: BoxDecoration(
                  color: sagana.glassBackground,
                  border: Border(bottom: BorderSide(color: sagana.glassBorder)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Text(
                        l10n.adminInvManagementTitle,
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
                    'Offline — changes will not be saved',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.charcoal,
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppConstants.primaryGreen,
                      strokeWidth: 2,
                    ),
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
                                    value: '${{for (final i in _items) i.category}.length}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Category filter
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.zero,
                            child: Row(
                              children: [
                                _Chip(
                                  label: l10n.reportsAll,
                                  selected: _categoryFilter == null,
                                  onTap: () => setState(() => _categoryFilter = null),
                                  cs: cs,
                                  sagana: sagana,
                                ),
                                ...{for (final i in _items) i.category}.map(
                                  (cat) => Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: _Chip(
                                      label: cat,
                                      selected: _categoryFilter == cat,
                                      onTap: () => setState(() => _categoryFilter = cat),
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
                                              AppConstants.radiusMd),
                                          child: SizedBox(
                                            width: 68,
                                            height: 68,
                                            child: (item.imageUrl != null &&
                                                    item.imageUrl!.isNotEmpty)
                                                ? Image.network(
                                                    item.imageUrl!,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => Container(
                                                        color: stockColor.withValues(alpha: 0.12),
                                                        child: Icon(
                                                          _categoryIcon(item.category),
                                                          color: stockColor,
                                                          size: 28,
                                                        )),
                                                  )
                                                : Container(
                                                    color: stockColor.withValues(alpha: 0.12),
                                                    child: Icon(
                                                      _categoryIcon(item.category),
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
                                                      color: cs.onSurfaceVariant,
                                                    ),
                                                    onSelected: (value) {
                                                      switch (value) {
                                                        case 'edit':
                                                          _showEditSheet(item);
                                                        case 'adjust':
                                                          if (_isOnline) _showAdjustSheet(item);
                                                        case 'publish':
                                                          if (_isOnline) _showLoanCatalogSheet(item);
                                                        case 'history':
                                                          _showTransactionHistory(item);
                                                        case 'delete':
                                                          if (_isOnline) _confirmDeleteItem(item);
                                                      }
                                                    },
                                                    itemBuilder: (ctx) => [
                                                      PopupMenuItem(
                                                        value: 'edit',
                                                        child: _menuRow(Icons.edit_outlined, 'Edit Item', cs.onSurface),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 'adjust',
                                                        enabled: _isOnline,
                                                        child: _menuRow(Icons.tune_rounded, l10n.adminInvAdjustStockTitle, cs.onSurface),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 'publish',
                                                        enabled: _isOnline,
                                                        child: _menuRow(Icons.request_page_rounded, l10n.adminInvPublish, cs.onSurface),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 'history',
                                                        child: _menuRow(Icons.history_rounded, l10n.adminInvHistoryAction, cs.onSurface),
                                                      ),
                                                      const PopupMenuDivider(),
                                                      PopupMenuItem(
                                                        value: 'delete',
                                                        enabled: _isOnline,
                                                        child: _menuRow(Icons.delete_outline_rounded, 'Delete Item', AppConstants.errorRed),
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
                                                scrollDirection: Axis.horizontal,
                                                child: Row(
                                                children: [
                                                  _StockStat(
                                                    label: l10n.adminInvOnHand,
                                                    value:
                                                        '${item.quantityOnHand.toStringAsFixed(1)} ${item.unit}',
                                                    color: stockColor,
                                                  ),
                                                  const SizedBox(width: 16),
                                                  _StockStat(
                                                    label: l10n.adminInvAvailable,
                                                    value:
                                                        '${item.available.toStringAsFixed(1)} ${item.unit}',
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
                                                    onTap: _isOnline
                                                        ? () =>
                                                              _showReorderLevelDialog(
                                                                item,
                                                              )
                                                        : null,
                                                    child: _StockStat(
                                                      label: l10n.adminInvReorderAt,
                                                      value: item.reorderLevel >
                                                              0
                                                          ? '${item.reorderLevel.toStringAsFixed(0)} ${item.unit}'
                                                          : 'Not set',
                                                      color: item.reorderLevel >
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
                                                        overflow: TextOverflow.ellipsis,
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
                                                          l10n.adminInvLastRestocked(_formatDate(item.lastRestockedAt!)),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
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
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: AppConstants.primaryGreen),
              title: Text('Take Photo', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppConstants.primaryGreen),
              title: Text('Upload Photo', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
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
