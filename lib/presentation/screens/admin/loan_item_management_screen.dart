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
import '../../../data/services/connectivity_service.dart';

// ── Model ────────────────────────────────────────────────────────────────────

class LoanMasterItem {
  final String id;
  final String itemName;
  final String category;
  final String unit;
  final double unitPrice;
  final String? description;
  final bool isActive;
  final int sortOrder;

  const LoanMasterItem({
    required this.id,
    required this.itemName,
    required this.category,
    required this.unit,
    required this.unitPrice,
    this.description,
    required this.isActive,
    required this.sortOrder,
  });

  factory LoanMasterItem.fromMap(Map<String, dynamic> m) => LoanMasterItem(
    id: m['id'] as String,
    itemName: m['item_name'] as String,
    category: m['category'] as String? ?? 'Agricultural Supplies',
    unit: m['unit'] as String? ?? 'bag',
    unitPrice: (m['unit_price'] as num).toDouble(),
    description: m['description'] as String?,
    isActive: m['is_active'] as bool? ?? true,
    sortOrder: m['sort_order'] as int? ?? 0,
  );
}

// ── Repository ───────────────────────────────────────────────────────────────

class _LoanItemMasterRepository {
  final _client = Supabase.instance.client;

  Future<List<LoanMasterItem>> fetchAll() async {
    try {
      final rows = await _client
          .from('loan_items_master')
          .select()
          .order('sort_order')
          .order('item_name');
      return rows.map((r) => LoanMasterItem.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> addItem({
    required String name,
    required String category,
    required String unit,
    required double unitPrice,
    String? description,
  }) async {
    try {
      await _client.from('loan_items_master').insert({
        'item_name': name.trim(),
        'category': category,
        'unit': unit,
        'unit_price': unitPrice,
        'description': description?.trim(),
        'created_by': _client.auth.currentUser?.id,
      });
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
    required double unitPrice,
    String? description,
  }) async {
    try {
      await _client
          .from('loan_items_master')
          .update({
            'item_name': name.trim(),
            'category': category,
            'unit': unit,
            'unit_price': unitPrice,
            'description': description?.trim(),
          })
          .eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleActive(String id, bool newValue) async {
    try {
      await _client
          .from('loan_items_master')
          .update({'is_active': newValue})
          .eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteItem(String id) async {
    try {
      await _client.from('loan_items_master').delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class LoanItemManagementScreen extends StatefulWidget {
  const LoanItemManagementScreen({super.key});

  @override
  State<LoanItemManagementScreen> createState() =>
      _LoanItemManagementScreenState();
}

class _LoanItemManagementScreenState extends State<LoanItemManagementScreen> {
  final _repo = _LoanItemMasterRepository();

  List<LoanMasterItem> _items = [];
  bool _isLoading = true;
  bool _isOnline = true;
  String? _selectedCategory;

  static const _categories = [
    'Fertilizer',
    'Seeds',
    'Animal Feeds',
    'Pesticide',
    'Tools & Equipment',
    'Agricultural Supplies',
  ];

  static const _units = [
    'bag',
    'kg',
    'sack',
    'piece',
    'liter',
    'set',
    'bottle',
  ];

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
    final result = await _repo.fetchAll();
    if (!mounted) return;
    setState(() {
      _items = result;
      _isLoading = false;
    });
  }

  List<LoanMasterItem> get _filtered {
    return _items.where((item) {
      if (!item.isActive) {
        return false;
      }
      if (_selectedCategory != null && item.category != _selectedCategory) {
        return false;
      }
      return true;
    }).toList();
  }

  Map<String, List<LoanMasterItem>> get _grouped {
    final Map<String, List<LoanMasterItem>> map = {};
    for (final item in _filtered) {
      map.putIfAbsent(item.category, () => []).add(item);
    }
    return map;
  }

  void _showItemSheet(LoanMasterItem? existing) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.itemName ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final priceCtrl = TextEditingController(
      text: existing != null ? existing.unitPrice.toStringAsFixed(2) : '',
    );
    String selectedCategory = existing?.category ?? 'Agricultural Supplies';
    String selectedUnit = existing?.unit ?? 'bag';
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final sagana = ctx.saganaColors;
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: sagana.cardBackground,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppConstants.radiusXl),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: cs.outline.withValues(alpha: 0.30),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          existing == null ? 'Add Loan Item' : 'Edit Loan Item',
                          style: GoogleFonts.poppins(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Items added here will be available when issuing loans.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Item Name *',
                            hintText: 'e.g. Urea Fertilizer 50kg',
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
                        DropdownButtonFormField<String>(
                          initialValue: selectedCategory,
                          decoration: const InputDecoration(
                            labelText: 'Category *',
                          ),
                          items: _categories
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setSheet(() => selectedCategory = v!),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: selectedUnit,
                                decoration: const InputDecoration(
                                  labelText: 'Unit *',
                                ),
                                items: _units
                                    .map(
                                      (u) => DropdownMenuItem(
                                        value: u,
                                        child: Text(u),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) =>
                                    setSheet(() => selectedUnit = v!),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: priceCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Unit Price (₱) *',
                                  hintText: '0.00',
                                  prefixText: '₱ ',
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
                                    return 'Unit price is required';
                                  }
                                  if (!isValidCurrencyValue(value)) {
                                    return 'Enter a valid amount';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Description (optional)',
                            hintText: 'Specifications, notes, subsidy info',
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate()) {
                                      return;
                                    }
                                    final price =
                                        double.tryParse(
                                          priceCtrl.text.trim(),
                                        ) ??
                                        0;
                                    setSheet(() => isSaving = true);
                                    bool ok;
                                    if (existing == null) {
                                      ok = await _repo.addItem(
                                        name: nameCtrl.text,
                                        category: selectedCategory,
                                        unit: selectedUnit,
                                        unitPrice: price,
                                        description: descCtrl.text.isEmpty
                                            ? null
                                            : descCtrl.text,
                                      );
                                    } else {
                                      ok = await _repo.updateItem(
                                        id: existing.id,
                                        name: nameCtrl.text,
                                        category: selectedCategory,
                                        unit: selectedUnit,
                                        unitPrice: price,
                                        description: descCtrl.text.isEmpty
                                            ? null
                                            : descCtrl.text,
                                      );
                                    }
                                    if (!ctx.mounted) return;
                                    Navigator.pop(ctx);
                                    if (ok) _load();
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          ok
                                              ? existing == null
                                                    ? 'Item added'
                                                    : 'Item updated'
                                              : 'Failed. Try again.',
                                        ),
                                        backgroundColor: ok
                                            ? AppConstants.successGreen
                                            : AppConstants.errorRed,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                            child: Text(
                              isSaving
                                  ? 'Saving…'
                                  : existing == null
                                  ? 'Add Item'
                                  : 'Save Changes',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showArchivedSheet() async {
    final all = await _repo.fetchAll();
    final archived = all.where((item) => !item.isActive).toList();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final sagana = ctx.saganaColors;
        final cs = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.60,
          maxChildSize: 0.90,
          builder: (ctx, ctrl) => Container(
            decoration: BoxDecoration(
              color: sagana.cardBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppConstants.radiusXl),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: cs.outline.withValues(alpha: 0.30),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Archived Items',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusFull,
                              ),
                            ),
                            child: Text(
                              '${archived.length}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
                Expanded(
                  child: archived.isEmpty
                      ? Center(
                          child: Text(
                            'No archived items',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: ctrl,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          itemCount: archived.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: cs.outline.withValues(alpha: 0.08),
                          ),
                          itemBuilder: (_, i) {
                            final item = archived[i];
                            return ListTile(
                              tileColor: Colors.transparent,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              title: Text(
                                item.itemName,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: cs.onSurface,
                                ),
                              ),
                              subtitle: Text(
                                item.category,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              trailing: GestureDetector(
                                onTap: () async {
                                  final ok = await _repo.toggleActive(
                                    item.id,
                                    true,
                                  );
                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);
                                  if (ok) _load();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppConstants.primaryGreen.withValues(
                                      alpha: 0.10,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppConstants.radiusFull,
                                    ),
                                  ),
                                  child: Text(
                                    'Restore',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppConstants.primaryGreen,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(LoanMasterItem item) {
    showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(
            'Delete "${item.itemName}"?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'This will permanently remove the item from the loan catalog. '
            'Existing loan records that include this item will not be affected.',
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
                final ok = await _repo.deleteItem(item.id);
                if (ok) _load();
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: AppConstants.errorRed),
              ),
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
    final grouped = _grouped;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: _isOnline
          ? FloatingActionButton(
              onPressed: () => _showItemSheet(null),
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
                        'Loan Item Catalog',
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

          // Category filter chips
          if (!_isLoading && _items.isNotEmpty)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _CategoryChip(
                      label: 'All',
                      isSelected: _selectedCategory == null,
                      onTap: () => setState(() => _selectedCategory = null),
                      cs: cs,
                      sagana: sagana,
                    ),
                    ...{for (final i in _items) i.category}.map(
                      (cat) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _CategoryChip(
                          label: cat,
                          isSelected: _selectedCategory == cat,
                          onTap: () => setState(() => _selectedCategory = cat),
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
                    child: _filtered.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 100),
                              Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.category_rounded,
                                      size: 48,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No items in catalog',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () => _showItemSheet(null),
                                      child: const Text('Add First Item'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                            children: [
                              // Stats bar
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusMd,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.category_rounded,
                                      size: 16,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${_filtered.length} item${_filtered.length == 1 ? '' : 's'} '
                                      '· ${grouped.keys.length} '
                                      'categor${grouped.keys.length == 1 ? 'y' : 'ies'}',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              for (final category in grouped.keys) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: 8,
                                    top: 4,
                                  ),
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
                                Container(
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
                                  child: Column(
                                    children: grouped[category]!.asMap().entries.map((
                                      entry,
                                    ) {
                                      final i = entry.key;
                                      final item = entry.value;
                                      final isLast =
                                          i == grouped[category]!.length - 1;
                                      return Column(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Flexible(
                                                            child: Text(
                                                              item.itemName,
                                                              style: GoogleFonts.poppins(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    item.isActive
                                                                    ? cs.onSurface
                                                                    : cs.onSurfaceVariant,
                                                              ),
                                                            ),
                                                          ),
                                                          if (!item
                                                              .isActive) ...[
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            _Badge(
                                                              'ARCHIVED',
                                                              cs.outline
                                                                  .withValues(
                                                                    alpha: 0.15,
                                                                  ),
                                                              cs.onSurfaceVariant,
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Row(
                                                        children: [
                                                          Text(
                                                            '₱${item.unitPrice.toStringAsFixed(2)} / ${item.unit}',
                                                            style:
                                                                GoogleFonts.poppins(
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color: cs
                                                                      .primary,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                      if (item.description !=
                                                          null)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 2,
                                                              ),
                                                          child: Text(
                                                            item.description!,
                                                            style: GoogleFonts.inter(
                                                              fontSize: 11,
                                                              color: cs
                                                                  .onSurfaceVariant,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuButton<String>(
                                                  icon: Icon(
                                                    Icons.more_vert_rounded,
                                                    size: 20,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                  onSelected: (v) async {
                                                    switch (v) {
                                                      case 'edit':
                                                        _showItemSheet(item);
                                                        break;
                                                      case 'archive':
                                                        final ok = await _repo
                                                            .toggleActive(
                                                              item.id,
                                                              false,
                                                            );
                                                        if (ok) _load();
                                                        break;
                                                      case 'delete':
                                                        _confirmDelete(item);
                                                        break;
                                                    }
                                                  },
                                                  itemBuilder: (_) => [
                                                    PopupMenuItem(
                                                      value: 'edit',
                                                      child: Row(
                                                        children: [
                                                          const Icon(
                                                            Icons.edit_rounded,
                                                            size: 16,
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Text(
                                                            'Edit',
                                                            style:
                                                                GoogleFonts.inter(),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'archive',
                                                      child: Row(
                                                        children: [
                                                          const Icon(
                                                            Icons
                                                                .archive_rounded,
                                                            size: 16,
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Text(
                                                            'Archive',
                                                            style:
                                                                GoogleFonts.inter(),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'delete',
                                                      child: Row(
                                                        children: [
                                                          const Icon(
                                                            Icons
                                                                .delete_rounded,
                                                            size: 16,
                                                            color: AppConstants
                                                                .errorRed,
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Text(
                                                            'Delete',
                                                            style: GoogleFonts.inter(
                                                              color:
                                                                  AppConstants
                                                                      .errorRed,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (!isLast)
                                            Divider(
                                              height: 1,
                                              indent: 14,
                                              endIndent: 14,
                                              color: cs.outline.withValues(
                                                alpha: 0.08,
                                              ),
                                            ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: _showArchivedSheet,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: sagana.cardBackground,
                                    borderRadius: BorderRadius.circular(
                                      AppConstants.radiusLg,
                                    ),
                                    border: Border.all(
                                      color: cs.outline.withValues(alpha: 0.10),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.archive_rounded,
                                        size: 18,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'View Archived Items',
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

// ── Shared widgets ────────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
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
          color: isSelected ? cs.primary : sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.20),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Badge(this.label, this.bg, this.fg);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
