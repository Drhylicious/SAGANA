import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_loan_model.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/report_summary_widgets.dart' show ReportIconStatCard, ReportSectionCard;

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

  // Loan Item Catalog is view-only for pricing/notes — its purpose is
  // determining loan eligibility, not editing the item itself. Unit Price
  // and Notes are only editable from Inventory Management's own
  // Publish/Update Catalog action (_showLoanCatalogSheet in
  // admin_inventory_screen.dart), which already re-opens as "Update Loan
  // Catalog" for an already-published item. This sheet now only lets the
  // admin toggle eligibility, and passes the existing price/notes back
  // unchanged rather than exposing them as editable fields here too.
  void _showLoanSettingsSheet(LoanCatalogItem existing) {
    final l10n = AppLocalizations.of(context);
    final currency = existing.unitPrice.toStringAsFixed(2);
    bool isEligible = existing.isLoanEligible;
    bool isSaving = false;

    showManagementModal(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> submit() async {
            setSheet(() => isSaving = true);
            final ok = await _repo.updateLoanCatalogRules(
              loanItemId: existing.loanItemId,
              unitPrice: existing.unitPrice,
              isLoanEligible: isEligible,
              notes: existing.notes,
            );
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (ok) _load();
            ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
              content: Text(ok ? l10n.loanItemRulesUpdated : l10n.loanItemFailedTryAgain),
              backgroundColor: ok ? AppConstants.successGreen : AppConstants.errorRed,
              behavior: SnackBarBehavior.floating,
            ));
          }

          return ManagementModalShell(
            title: l10n.loanItemSettingsTitle,
            subtitle: '${existing.itemName} · ${existing.unit}',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _readOnlyField(l10n.loanItemNameLabel, existing.itemName, ctx),
                const SizedBox(height: 12),
                _readOnlyField(l10n.adminOrderDetailCategory, existing.category, ctx),
                const SizedBox(height: 12),
                _readOnlyField(l10n.loanItemUnitLabel, existing.unit, ctx),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.loanItemAvailableInStock,
                        style: GoogleFonts.inter(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                    Text('${existing.quantityOnHand.toStringAsFixed(0)} ${existing.unit}',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                _readOnlyField(l10n.loanItemUnitPriceLabel, '₱$currency', ctx),
                const SizedBox(height: 12),
                _readOnlyField(l10n.issueLoanNotes,
                    (existing.notes ?? '').isEmpty ? '—' : existing.notes!, ctx),
                const SizedBox(height: 4),
                Text(
                  'Price and notes are set from Inventory Management — use its Publish action to change them.',
                  style: GoogleFonts.inter(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.loanItemAvailableForIssuance),
                  value: isEligible,
                  onChanged: (v) => setSheet(() => isEligible = v),
                ),
              ],
            ),
            footer: ManagementModalActions(
              primaryLabel: isSaving ? l10n.adminInvSaving : l10n.cropMgmtSaveChanges,
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
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
          ),
          child: Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ],
    );
  }

  // LoanCatalogItem.category is joined through cooperative_inventory
  // (loan_items_master has no category column of its own — see
  // publishToLoanCatalog()), so it shares the same admin-managed,
  // open-ended vocabulary as Inventory Management. Same icon mapping and
  // same accepted fallback for a category added after this list.
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
                        l10n.loanItemCatalogTitle,
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

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppConstants.primaryGreen, strokeWidth: 2),
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
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.spacingSafeH,
                        AppConstants.spacingGutter,
                        AppConstants.spacingSafeH,
                        AppConstants.spacingSafeH,
                      ),
                      children: [
                        if (_items.isNotEmpty) ...[
                          // KPI cards (dashboard.md section 10) — grouped
                          // inside the same outer titled container the
                          // Report tab uses (Executive Snapshot etc.).
                          ReportSectionCard(
                            title: 'Catalog Overview',
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
                                    icon: Icons.category_rounded,
                                    accent: AppConstants.primaryGreen,
                                    label: l10n.reportsCategories,
                                    value:
                                        '${{for (final i in _items) i.category}.length}',
                                  ),
                                ),
                                const SizedBox(width: AppConstants.spacingSm),
                                Expanded(
                                  child: ReportIconStatCard(
                                    icon: Icons.check_circle_rounded,
                                    accent: AppConstants.successGreen,
                                    // "Loan-Eligible" wrapped to 2 lines in
                                    // this card's 1/3-width slot (unlike
                                    // "Total Items"/"Categories", which fit
                                    // on one), making this one card taller
                                    // than its siblings — ReportIconStatCard
                                    // sizes to its own content, so the fix
                                    // is a label that reliably fits one
                                    // line here too, not a layout change.
                                    label: 'Eligible',
                                    value:
                                        '${_items.where((i) => i.isLoanEligible).length}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Category filter chips
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.zero,
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
                          const SizedBox(height: 16),
                        ],
                        if (_filtered.isEmpty)
                          Column(
                            children: [
                              const SizedBox(height: 60),
                              Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.inventory_2_rounded, size: 48, color: cs.onSurfaceVariant),
                                    const SizedBox(height: 12),
                                    Text(
                                      l10n.loanItemNoItemsYet,
                                      style: GoogleFonts.inter(fontSize: 14, color: cs.onSurfaceVariant),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () => context.push(AppRoutes.adminInventory),
                                      child: Text(l10n.loanItemPublishFromInventory),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
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
                                // Individual horizontal cards, one per item
                                // — matches Marketplace All Listings'
                                // _AllListingCard layout (image left,
                                // rounded 68x68, info right), used here as
                                // the direct visual reference, replacing
                                // the previous shared-container-with-
                                // dividers list and its generic category
                                // icon.
                                for (final item in grouped[category]!)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: GestureDetector(
                                      onTap: () => _showLoanSettingsSheet(item),
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: sagana.cardBackground,
                                          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                                          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
                                          boxShadow: [
                                            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
                                          ],
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                              child: SizedBox(
                                                width: 68,
                                                height: 68,
                                                child: (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                                                    ? Image.network(
                                                        item.imageUrl!,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (_, __, ___) =>
                                                            _CatalogThumb(cs: cs, icon: _categoryIcon(item.category)),
                                                      )
                                                    : _CatalogThumb(cs: cs, icon: _categoryIcon(item.category)),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
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
                                                      child: Text(l10n.loanItemNotEligibleBadge,
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
                                  ),
                                const SizedBox(height: 8),
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

// Fallback thumbnail when an item has no photo — same shape/role as
// all_listings_screen.dart's own _Thumb, just parameterized by icon
// instead of hardcoded to a crop icon.
class _CatalogThumb extends StatelessWidget {
  final ColorScheme cs;
  final IconData icon;
  const _CatalogThumb({required this.cs, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(child: Icon(icon, size: 26, color: cs.outline.withValues(alpha: 0.40))),
    );
  }
}

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