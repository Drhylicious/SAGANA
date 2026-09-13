import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/input_validation_utils.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/app_dropdown_field.dart';
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

  Future<bool> itemExists({
    required String name,
  }) async {
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

  Future<bool> addItem({
    required String name,
    required String category,
    required String unit,
    double? unitCost,
    required double reorderLevel,
    String? notes,
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
        'created_by': _client.auth.currentUser?.id,
      });
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
      await _client.rpc('adjust_inventory_stock', params: {
        'p_inventory_id': inventoryId,
        'p_quantity': quantity,
        'p_transaction_type': transactionType,
        'p_notes': notes?.trim(),
        'p_recorded_by': _client.auth.currentUser?.id,
      });
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
}

// ── Screen ───────────────────────────────────────────────────────────────────

class AdminInventoryScreen extends StatefulWidget {
  const AdminInventoryScreen({super.key});

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

  int get _lowStockCount =>
      _items.where((i) => i.isLow && !i.isDepleted).length;
  int get _depletedCount => _items.where((i) => i.isDepleted).length;

  void _showAddSheet() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final reorderCtrl = TextEditingController(text: '0');
    final notesCtrl = TextEditingController();
    String? selectedCategory;
    String? selectedUnit;
    bool isSaving = false;
    // Local copy so the sheet's own dropdown updates immediately when a
    // category is added inline, without waiting for the screen behind it
    // to rebuild (it isn't listening to this already-open dialog route).
    var categoryOptions = List<String>.of(_categories);

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              setSheet(() => isSaving = true);
              final ok = await _repo.addItem(
                name: nameCtrl.text,
                category: selectedCategory!,
                unit: selectedUnit!,
                unitCost: costCtrl.text.trim().isEmpty
                    ? null
                    : double.tryParse(costCtrl.text.trim()),
                reorderLevel: double.tryParse(reorderCtrl.text.trim()) ?? 0,
                notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (ok) _load();
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? 'Item added'
                        : 'That item already exists or could not be saved.',
                  ),
                  backgroundColor: ok
                      ? AppConstants.successGreen
                      : AppConstants.errorRed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }

            return ManagementModalShell(
              title: 'Add Inventory Item',
              subtitle:
                  'New items start with 0 stock. Use Adjust Stock to add quantity.',
              body: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                          title: 'Add Inventory Category',
                          hintText: 'e.g. Dairy',
                        );
                        if (name == null) return null;
                        final added = await _categoryRepo.addInventoryCategory(name);
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
                      decoration: const InputDecoration(
                        labelText: 'Item Name *',
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Item name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: AppDropdownField<String>(
                            value: selectedUnit,
                            hintText: 'Select a unit',
                            labelText: 'Unit *',
                            items: _units,
                            itemLabel: (u) => u,
                            onChanged: (v) => setSheet(() => selectedUnit = v),
                            validator: (v) => v == null ? 'Unit is required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Unit Cost (₱)',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
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
                                      horizontal: 14, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Theme.of(ctx)
                                          .colorScheme
                                          .outline
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
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d*'),
                                  ),
                                ],
                                validator: (value) {
                                  if ((value ?? '').trim().isEmpty) return null;
                                  if (!isValidCurrencyValue(value))
                                    return 'Enter a valid amount';
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
                      decoration: const InputDecoration(
                        labelText: 'Reorder Level',
                        hintText: 'Alert when stock drops below this',
                        suffixText: 'units',
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
                        if ((value ?? '').trim().isEmpty) return null;
                        if (!isValidWholeNumberValue(value))
                          return 'Enter a whole number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              footer: ManagementModalActions(
                primaryLabel: isSaving ? 'Saving…' : 'Add Item',
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
                              ? 'Published to loan catalog'
                              : 'Loan catalog updated')
                        : 'Could not update the loan catalog.',
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
                  ? 'Publish to Loan Catalog'
                  : 'Update Loan Catalog',
              subtitle: item.itemName,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Loan Price (₱) *',
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
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Eligibility or pricing note',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              footer: ManagementModalActions(
                primaryLabel: isSaving
                    ? 'Saving…'
                    : (existing == null ? 'Publish' : 'Update'),
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
                  content: Text(ok ? 'Stock updated' : 'Failed. Try again.'),
                  backgroundColor: ok
                      ? AppConstants.successGreen
                      : AppConstants.errorRed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }

            return ManagementModalShell(
              title: 'Adjust Stock',
              subtitle:
                  '${item.itemName} · Current: ${item.quantityOnHand.toStringAsFixed(1)} ${item.unit}',
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Transaction Type *',
                    ),
                    items: _transactionTypes.map((t) {
                      final label = {
                        'restock': 'Restock (add stock)',
                        'adjustment': 'Adjustment (deduct)',
                        'written_off': 'Write-off (loss/damage)',
                      }[t]!;
                      return DropdownMenuItem(value: t, child: Text(label));
                    }).toList(),
                    onChanged: (v) => setSheet(() => selectedType = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyCtrl,
                    decoration: InputDecoration(
                      labelText: 'Quantity *',
                      suffixText: item.unit,
                      hintText: isDeduction
                          ? 'Amount to deduct'
                          : 'Amount to add',
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
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Reason, supplier, reference number',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              footer: ManagementModalActions(
                primaryLabel: isSaving ? 'Saving…' : 'Confirm Adjustment',
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
    final transactions = await _repo.fetchTransactions(item.id);
    if (!mounted) return;

    showManagementModal(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return ManagementModalShell(
          title: 'Transaction History',
          subtitle: item.itemName,
          bodyIsScrollable: true,
          body: transactions.isEmpty
              ? Center(
                  child: Text(
                    'No transactions yet',
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
                          'restock': 'Restock',
                          'loan_issued': 'Loan Issued',
                          'adjustment': 'Adjustment',
                          'harvest_received': 'Harvest In',
                          'sold': 'Sold',
                          'returned': 'Returned',
                          'written_off': 'Write-off',
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

  @override
  Widget build(BuildContext context) {
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
                        'Inventory Management',
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

          // Alert bar
          if (!_isLoading && (_lowStockCount > 0 || _depletedCount > 0))
            Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _depletedCount > 0
                    ? AppConstants.errorRed.withValues(alpha: 0.08)
                    : AppConstants.warningAmber.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                  color: _depletedCount > 0
                      ? AppConstants.errorRed.withValues(alpha: 0.20)
                      : AppConstants.warningAmber.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _depletedCount > 0
                        ? Icons.error_rounded
                        : Icons.warning_rounded,
                    size: 16,
                    color: _depletedCount > 0
                        ? AppConstants.errorRed
                        : AppConstants.warningAmber,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    [
                      if (_depletedCount > 0) '$_depletedCount depleted',
                      if (_lowStockCount > 0) '$_lowStockCount low stock',
                    ].join(' · '),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _depletedCount > 0
                          ? AppConstants.errorRed
                          : AppConstants.warningAmber,
                    ),
                  ),
                ],
              ),
            ),

          // Category filter
          if (!_isLoading && _items.isNotEmpty)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _Chip(
                      label: 'All',
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
                    child: filtered.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 100),
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
                                      'No inventory items yet',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: _showAddSheet,
                                      child: const Text('Add First Item'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
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
                                  ? 'DEPLETED'
                                  : item.isLow
                                  ? 'LOW STOCK'
                                  : 'IN STOCK';

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
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Row(
                                                children: [
                                                  _StockStat(
                                                    label: 'On Hand',
                                                    value:
                                                        '${item.quantityOnHand.toStringAsFixed(1)} ${item.unit}',
                                                    color: stockColor,
                                                  ),
                                                  const SizedBox(width: 16),
                                                  _StockStat(
                                                    label: 'Available',
                                                    value:
                                                        '${item.available.toStringAsFixed(1)} ${item.unit}',
                                                    color: cs.onSurface,
                                                  ),
                                                  if (item.reorderLevel >
                                                      0) ...[
                                                    const SizedBox(width: 16),
                                                    _StockStat(
                                                      label: 'Reorder At',
                                                      value:
                                                          '${item.reorderLevel.toStringAsFixed(0)} ${item.unit}',
                                                      color:
                                                          cs.onSurfaceVariant,
                                                    ),
                                                  ],
                                                ],
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
                                                      Text(
                                                        'Last restocked ${_formatDate(item.lastRestockedAt!)}',
                                                        style: GoogleFonts.inter(
                                                          fontSize: 11,
                                                          color: cs
                                                              .onSurfaceVariant,
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
                                              // Action buttons
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: GestureDetector(
                                                      onTap: _isOnline
                                                          ? () =>
                                                                _showAdjustSheet(
                                                                  item,
                                                                )
                                                          : null,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 9,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: cs.primary
                                                              .withValues(
                                                                alpha: 0.08,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                AppConstants
                                                                    .radiusMd,
                                                              ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .tune_rounded,
                                                              size: 16,
                                                              color: cs.primary,
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            Flexible(
                                                              child: Text(
                                                                'Adjust Stock',
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                maxLines: 1,
                                                                style: GoogleFonts.poppins(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: cs.primary,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: GestureDetector(
                                                      onTap: _isOnline
                                                          ? () =>
                                                                _showLoanCatalogSheet(
                                                                  item,
                                                                )
                                                          : null,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 9,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: AppConstants
                                                              .primaryGreen
                                                              .withValues(
                                                                alpha: 0.10,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                AppConstants
                                                                    .radiusMd,
                                                              ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .request_page_rounded,
                                                              size: 16,
                                                              color: AppConstants
                                                                  .primaryGreen,
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            Flexible(
                                                              child: Text(
                                                                'Publish',
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                maxLines: 1,
                                                                style: GoogleFonts.poppins(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: AppConstants
                                                                      .primaryGreen,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  GestureDetector(
                                                    onTap: () =>
                                                        _showTransactionHistory(
                                                          item,
                                                        ),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 14,
                                                            vertical: 9,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: cs
                                                            .surfaceContainerHighest,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              AppConstants
                                                                  .radiusMd,
                                                            ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .history_rounded,
                                                            size: 16,
                                                            color: cs
                                                                .onSurfaceVariant,
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Flexible(
                                                            child: Text(
                                                              'History',
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              maxLines: 1,
                                                              style: GoogleFonts.poppins(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: cs
                                                                    .onSurfaceVariant,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
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
                  ),
          ),
        ],
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