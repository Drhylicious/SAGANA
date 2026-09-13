import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/input_validation_utils.dart';
import '../../../data/models/admin_loan_model.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/management_modal.dart';

// ── Screen ───────────────────────────────────────────────────────────────────

class LoanItemManagementScreen extends StatefulWidget {
  const LoanItemManagementScreen({super.key});

  @override
  State<LoanItemManagementScreen> createState() =>
      _LoanItemManagementScreenState();
}

class _LoanItemManagementScreenState extends State<LoanItemManagementScreen> {
  final _repo = AdminLoanRepository();

  List<LoanCatalogItem> _items = [];
  bool _isLoading = true;
  bool _isOnline = true;
  String? _selectedCategory;

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
    final result = await _repo.fetchAllCatalogItems();
    if (!mounted) return;
    setState(() {
      _items = result;
      _isLoading = false;
    });
  }

  List<LoanCatalogItem> get _filtered {
    return _items.where((item) {
      if (_selectedCategory != null && item.category != _selectedCategory) {
        return false;
      }
      return true;
    }).toList();
  }

  Map<String, List<LoanCatalogItem>> get _grouped {
    final Map<String, List<LoanCatalogItem>> map = {};
    for (final item in _filtered) {
      map.putIfAbsent(item.category, () => []).add(item);
    }
    return map;
  }

  void _showLoanSettingsSheet(LoanCatalogItem existing) {
    final formKey = GlobalKey<FormState>();
    final notesCtrl = TextEditingController(text: existing.notes ?? '');
    final priceCtrl = TextEditingController(
      text: existing.unitPrice.toStringAsFixed(2),
    );
    bool isEligible = existing.isLoanEligible;
    bool isSaving = false;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
            setSheet(() => isSaving = true);
            final ok = await _repo.updateLoanCatalogRules(
              loanItemId: existing.loanItemId,
              unitPrice: price,
              isLoanEligible: isEligible,
              notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
            );
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (ok) _load();
            ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
              content: Text(ok ? 'Loan rules updated' : 'Failed. Try again.'),
              backgroundColor: ok ? AppConstants.successGreen : AppConstants.errorRed,
              behavior: SnackBarBehavior.floating,
            ));
          }

          return ManagementModalShell(
            title: 'Loan Settings',
            subtitle: '${existing.itemName} · ${existing.unit}',
            body: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _readOnlyField('Item Name', existing.itemName, ctx),
                  const SizedBox(height: 12),
                  _readOnlyField('Category', existing.category, ctx),
                  const SizedBox(height: 12),
                  _readOnlyField('Unit', existing.unit, ctx),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Available in stock',
                          style: GoogleFonts.inter(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                      Text('${existing.quantityOnHand.toStringAsFixed(0)} ${existing.unit}',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Available for loan issuance'),
                    value: isEligible,
                    onChanged: (v) => setSheet(() => isEligible = v),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Unit Price (₱) *',
                      hintText: '0.00',
                      prefixText: '₱ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Unit price is required';
                      }
                      if (!isValidCurrencyValue(value)) return 'Enter a valid amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Subsidy terms, eligibility notes',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving ? 'Saving…' : 'Save Changes',
              isLoading: isSaving,
              onPrimary: submit,
            ),
          );
        });
      },
    );
  }

  Widget _readOnlyField(String label, String value, BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          ),
          child: Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final grouped = _grouped;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                  const Icon(Icons.cloud_off_rounded, size: 14, color: AppConstants.charcoal),
                  const SizedBox(width: 6),
                  Text('Offline — changes will not be saved',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppConstants.charcoal)),
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
                    child: CircularProgressIndicator(color: AppConstants.primaryGreen, strokeWidth: 2),
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
                                    Icon(Icons.inventory_2_rounded, size: 48, color: cs.onSurfaceVariant),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No loanable items yet',
                                      style: GoogleFonts.inter(fontSize: 14, color: cs.onSurfaceVariant),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () => context.push(AppRoutes.adminInventory),
                                      child: const Text('Publish from Inventory'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(
                              AppConstants.spacingSafeH,
                              AppConstants.spacingGutter,
                              AppConstants.spacingSafeH,
                              AppConstants.spacingSafeH,
                            ),
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.category_rounded, size: 16, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${_filtered.length} item${_filtered.length == 1 ? '' : 's'} · ${grouped.keys.length} categor${grouped.keys.length == 1 ? 'y' : 'ies'}',
                                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              for (final category in grouped.keys) ...[
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8, top: 4),
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
                                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                                    border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6),
                                    ],
                                  ),
                                  child: Column(
                                    children: grouped[category]!.asMap().entries.map((entry) {
                                      final i = entry.key;
                                      final item = entry.value;
                                      final isLast = i == grouped[category]!.length - 1;
                                      return Column(children: [
                                        GestureDetector(
                                          onTap: () => _showLoanSettingsSheet(item),
                                          behavior: HitTestBehavior.opaque,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        item.itemName,
                                                        style: GoogleFonts.poppins(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w600,
                                                          color: cs.onSurface,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Row(
                                                        children: [
                                                          Text(
                                                            '₱${item.unitPrice.toStringAsFixed(2)} / ${item.unit}',
                                                            style: GoogleFonts.poppins(
                                                              fontSize: 13,
                                                              fontWeight: FontWeight.w700,
                                                              color: cs.primary,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          Text(
                                                            'Stock: ${item.quantityOnHand.toStringAsFixed(0)}',
                                                            style: GoogleFonts.inter(
                                                              fontSize: 11,
                                                              color: cs.onSurfaceVariant,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      if (!item.isLoanEligible)
                                                        Container(
                                                          margin: const EdgeInsets.only(top: 4),
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: AppConstants.warningAmber.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                                                          ),
                                                          child: Text('NOT ELIGIBLE',
                                                              style: GoogleFonts.inter(
                                                                  fontSize: 9, fontWeight: FontWeight.w700, color: AppConstants.amber)),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                Icon(Icons.chevron_right_rounded, size: 20, color: cs.onSurfaceVariant),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (!isLast)
                                          Divider(height: 1, indent: 14, endIndent: 14, color: cs.outline.withValues(alpha: 0.08)),
                                      ]);
                                    }).toList(),
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
          border: Border.all(color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.20)),
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