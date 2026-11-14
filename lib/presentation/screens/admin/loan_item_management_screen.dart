import '../../../core/l10n/localized_labels.dart';
import 'package:flutter/material.dart';
import '../../../core/utils/item_type_utils.dart';
import '../../../data/services/staff_permission_service.dart';
import '../../widgets/view_only_banner.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_loan_model.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/repositories/coop_shelf_life_repository.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../widgets/record_details_sheet.dart';
import '../../../data/repositories/category_repository.dart';

import '../../../routes/app_routes.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/report_summary_widgets.dart'
    show ReportIconStatCard, ReportSectionCard;

// ── Screen ───────────────────────────────────────────────────────────────────
//
// Laid out like Crop Management: an archive button at the top right, KPI cards
// (the Archived one opens the archive), search, category chips and an image-
// forward grid with a ⋮ menu on each card.
//
// "Archived" is the loan catalog's existing eligibility flag
// (loan_items_master.is_loan_eligible = false). Issue New Loan's item picker
// already lists only eligible items, so an archived item is no longer offered
// for a new loan, while loans that already include it are untouched.

class LoanItemManagementScreen extends StatefulWidget {
  const LoanItemManagementScreen({super.key});

  @override
  State<LoanItemManagementScreen> createState() =>
      _LoanItemManagementScreenState();
}

class _LoanItemManagementScreenState extends State<LoanItemManagementScreen> {
  final _repo = AdminLoanRepository();
  final _categoryRepo = CategoryRepository();

  List<LoanCatalogItem> _items = [];
  // Each Inventory item's shelf-life standing: the catalog shows the same one.
  Map<String, CoopItemShelfLife> _shelf = {};

  CoopShelfState _shelfState(LoanCatalogItem i) =>
      (_shelf[i.inventoryItemId] ?? CoopItemShelfLife.none).state;

  List<String> _categories = [];
  bool _isLoading = true;

  String? _selectedCategory;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
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
      _repo.fetchAllCatalogItems(),
      // Sourced from Inventory Management's own category master table
      // (not the live-joined subset of categories that currently have a
      // published, active loan-catalog item), per the requirement that
      // these chips must come from actual Inventory Management category
      // data and pick up newly added categories automatically.
      _categoryRepo.fetchInventoryCategories(),
      CoopShelfLifeRepository().fetchByItem(),
    ]);
    if (!mounted) return;
    setState(() {
      _shelf = results[2] as Map<String, CoopItemShelfLife>;
      _items = results[0] as List<LoanCatalogItem>;
      _categories = results[1] as List<String>;
      _isLoading = false;
    });
  }

  /// Items offered for new loans.
  List<LoanCatalogItem> get _active =>
      _items.where((i) => i.isLoanEligible && !i.inventoryArchived).toList();

  /// Items taken out of new loans (archived), including every entry whose
  /// Inventory item was archived.
  List<LoanCatalogItem> get _archived =>
      _items.where((i) => !i.isLoanEligible || i.inventoryArchived).toList();

  List<LoanCatalogItem> get _filtered {
    return _active.where((item) {
      final matchesCategory =
          _selectedCategory == null || item.category == _selectedCategory;
      final matchesSearch =
          _searchQuery.isEmpty ||
          item.itemName.toLowerCase().contains(_searchQuery);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  // Filter chips only ever show a category that currently has at least one
  // active catalog item — unlike _categories (the full Inventory master list,
  // fetched above so a brand-new category shows up as soon as an item
  // exists in it).
  List<String> get _activeCategories =>
      _categories.where((c) => _active.any((i) => i.category == c)).toList();

  // ── Archive / restore ─────────────────────────────────────────────────────

  /// Archive a loan item after asking. The one place archiving is done: the
  /// card menu and the item sheet both call it. Returns true when archived.
  Future<bool> _archiveWithConfirm(
    LoanCatalogItem item,
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
            l10n.loanItemArchiveTitle(item.itemName),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            l10n.loanItemArchiveBody,
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
              child: Text(l10n.loanItemArchiveConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return false;

    final ok = await _repo.setLoanItemArchived(item.loanItemId, true);
    if (!mounted) return false;
    if (ok) _load();
    _snack(
      ok
          ? l10n.loanItemArchivedSuccess(item.itemName)
          : l10n.loanItemFailedTryAgain,
      ok,
    );
    return ok;
  }

  Future<bool> _restore(LoanCatalogItem item) async {
    if (!requireManage(context, StaffModule.dashboard)) return false;
    final l10n = AppLocalizations.of(context);
    final ok = await _repo.setLoanItemArchived(item.loanItemId, false);
    if (!mounted) return false;
    if (ok) _load();
    _snack(
      ok
          ? l10n.loanItemRestoredSuccess(item.itemName)
          : l10n.loanItemFailedTryAgain,
      ok,
    );
    return ok;
  }

  void _snack(String message, bool ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: ok ? AppConstants.midGreen : AppConstants.errorRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Archived Loan Items modal ─────────────────────────────────────────────

  void _showArchivedSheet() {
    final l10n = AppLocalizations.of(context);
    final archived = _archived;

    showManagementModal(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return ManagementModalShell(
          title: l10n.loanItemArchivedTitle,
          subtitle: l10n.loanItemArchivedCount(archived.length),
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
                          l10n.loanItemNoArchived,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.loanItemNoArchivedBody,
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
                      return Row(
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
                              l10n.loanItemArchivedInfo,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                height: 1.4,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    final item = archived[i - 1];
                    return ArchivedLoanItemCard(
                      item: item,
                      onRestore: () async {
                        // Archived in Inventory: it is restored there, never here.
                        if (item.inventoryArchived) return;
                        final ok = await _restore(item);
                        if (ok && ctx.mounted) Navigator.pop(ctx);
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  // ── Item sheet ────────────────────────────────────────────────────────────
  // Loan Item Catalog is view-only for pricing/notes — Unit Price and Notes
  // are only editable from Inventory Management's own Publish/Update Catalog
  // action (_showLoanCatalogSheet in admin_inventory_screen.dart). This sheet
  // shows the item and offers Archive.
  // Read-only details of a catalog entry (tap the card). Archive is in the
  // card's three-dot menu; price and notes are set from Inventory Management.
  void _showItemDetails(LoanCatalogItem item) {
    final l10n = AppLocalizations.of(context);
    final state = _shelfState(item);
    showRecordDetails(
      context,
      title: item.itemName,
      subtitle: '${item.category} • ${itemTypeLabel(l10n, item.itemType)}',
      imageUrl: item.imageUrl,
      placeholderIcon: _categoryIcon(item.category),
      sections: [
        DetailSection(
          title: l10n.detailsSectionInfo,
          rows: [
            DetailRow(l10n.buyerListingCategory, item.category),
            DetailRow(
              l10n.detailsItemType,
              itemTypeLabel(l10n, item.itemType),
            ),
            DetailRow(
              l10n.detailsLoanPrice,
              '₱${item.unitPrice.toStringAsFixed(2)} / ${item.unit}',
            ),
            DetailRow(
              l10n.detailsOnHand,
              formatQuantityUnit(item.quantityOnHand, item.unit),
            ),
            DetailRow(
              l10n.adminInvSourceLabel,
              item.source ?? l10n.adminInvSourceNotRecorded,
            ),
            DetailRow(
              l10n.detailsStatus,
              item.inventoryArchived || !item.isLoanEligible
                  ? l10n.cropMgmtArchivedBadge
                  : state == CoopShelfState.rottenLost
                  ? l10n.coopFilterRotten
                  : state == CoopShelfState.onHold
                  ? l10n.coopFilterHold
                  : l10n.detailsAvailableForLoan,
              valueColor:
                  state == CoopShelfState.onHold ||
                      state == CoopShelfState.rottenLost
                  ? AppConstants.errorRed
                  : null,
            ),
            if ((item.notes ?? '').trim().isNotEmpty)
              DetailRow(l10n.detailsNotes, item.notes!.trim()),
          ],
        ),
      ],
    );
  }

  Widget _emptyState(
    ColorScheme cs,
    IconData icon,
    String message, {
    Widget? action,
  }) {
    return Column(
      children: [
        const SizedBox(height: 60),
        Center(
          child: Column(
            children: [
              Icon(icon, size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 8), action],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final displayedItems = _filtered;
    final active = _active;
    final archived = _archived;

    final kpiCards = <Widget>[
      ReportIconStatCard(
        icon: Icons.inventory_2_rounded,
        accent: AppConstants.buyerBlue,
        label: l10n.loanItemKpiActive,
        value: '${active.length}',
      ),
      ReportIconStatCard(
        icon: Icons.category_rounded,
        accent: AppConstants.primaryGreen,
        label: l10n.reportsCategories,
        value: '${{for (final i in active) i.category}.length}',
      ),
      // Tappable, like Crop Management's Archived card: opens the archive.
      GestureDetector(
        onTap: _showArchivedSheet,
        child: ReportIconStatCard(
          icon: Icons.archive_outlined,
          accent: AppConstants.warningAmber,
          label: l10n.loanItemKpiArchived,
          value: '${archived.length}',
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Top bar, with the archive button at the top right.
          SubPageTopBar(
            title: l10n.loanItemCatalogTitle,
            onBack: () => context.pop(),
            trailing: IconButton(
              icon: Icon(Icons.archive_rounded, color: cs.onSurface),
              tooltip: l10n.loanItemViewArchived,
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
                    // Single outer scrollable so the KPI cards and category
                    // chips scroll away with the list below them.
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.spacingSafeH,
                        AppConstants.spacingGutter,
                        AppConstants.spacingSafeH,
                        AppConstants.spacingSafeH,
                      ),
                      children: [
                        if (_items.isNotEmpty) ...[
                          // KPI cards in the titled container the Report tab
                          // uses, as a horizontal row like the other
                          // Management modules.
                          ReportSectionCard(
                            title: AppLocalizations.of(
                              context,
                            ).enhCatalogOverview,
                            icon: Icons.inventory_2_rounded,
                            accent: AppConstants.buyerBlue,
                            child: SizedBox(
                              height: 104,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: kpiCards.length,
                                separatorBuilder: (_, __) => const SizedBox(
                                  width: AppConstants.spacingSm,
                                ),
                                itemBuilder: (_, i) =>
                                    SizedBox(width: 150, child: kpiCards[i]),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Search bar
                          TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: l10n.loanItemSearchHint,
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
                          // Category filter chips — only a category that
                          // currently has at least one active catalog item.
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.zero,
                            child: Row(
                              children: [
                                _CategoryChip(
                                  label:
                                      '${AppLocalizations.of(context).reportsAll} (${_active.length})',
                                  isSelected: _selectedCategory == null,
                                  onTap: () =>
                                      setState(() => _selectedCategory = null),
                                  cs: cs,
                                  sagana: sagana,
                                ),
                                ..._activeCategories.map(
                                  (cat) => Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: _CategoryChip(
                                      label:
                                          '$cat (${_active.where((i) => i.category == cat).length})',
                                      isSelected: _selectedCategory == cat,
                                      onTap: () => setState(
                                        () => _selectedCategory = cat,
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
                        ],
                        if (_items.isEmpty)
                          _emptyState(
                            cs,
                            Icons.inventory_2_rounded,
                            l10n.loanItemNoItemsYet,
                            action: TextButton(
                              onPressed: () =>
                                  context.push(AppRoutes.adminInventory),
                              child: Text(l10n.loanItemPublishFromInventory),
                            ),
                          )
                        else if (active.isEmpty)
                          _emptyState(
                            cs,
                            Icons.archive_outlined,
                            l10n.loanItemAllArchived,
                          )
                        else if (displayedItems.isEmpty)
                          _emptyState(
                            cs,
                            Icons.search_off_rounded,
                            l10n.loanItemNoMatches,
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
                                  childAspectRatio: 0.58,
                                ),
                            itemCount: displayedItems.length,
                            itemBuilder: (_, i) {
                              final item = displayedItems[i];
                              return LoanItemCard(
                                item: item,
                                cs: cs,
                                sagana: sagana,
                                // Same standing as the Inventory item.
                                unavailableLabel: switch (_shelfState(item)) {
                                  CoopShelfState.onHold =>
                                    l10n.coopBadgeUnavailable,
                                  CoopShelfState.rottenLost =>
                                    l10n.coopBadgeRotten,
                                  _ => null,
                                },
                                icon: _categoryIcon(item.category),
                                onTap: () => _showItemDetails(item),
                                onArchive: () =>
                                    _archiveWithConfirm(item, context),
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

  // LoanCatalogItem.category is joined through cooperative_inventory
  // (loan_items_master has no category column of its own — see
  // publishToLoanCatalog()), so it shares the same admin-managed,
  // open-ended vocabulary as Inventory Management. Same icon mapping and
  // same accepted fallback for a category added after this list.
  IconData _categoryIcon(String category) => loanCategoryIcon(category);
}

IconData loanCategoryIcon(String category) {
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

// ── Catalog grid card ────────────────────────────────────────────────────────

/// A loan item in the catalog grid: photo on top, then name,
/// category, price per unit, stock and Source. Public so its layout can be
/// widget-tested.
class LoanItemCard extends StatelessWidget {
  final LoanCatalogItem item;
  final ColorScheme cs;
  final SaganaColors sagana;
  final IconData icon;
  final VoidCallback onTap;

  /// The three-dot menu's Archive. Null hides the menu.
  final VoidCallback? onArchive;

  /// UNAVAILABLE or ROTTEN/LOST when the Inventory item is; the card is greyed
  /// and carries the badge. Null for an item that can be loaned.
  final String? unavailableLabel;

  const LoanItemCard({
    super.key,
    required this.item,
    required this.cs,
    required this.sagana,
    required this.icon,
    required this.onTap,
    this.onArchive,
    this.unavailableLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        foregroundDecoration: unavailableLabel == null
            ? null
            : BoxDecoration(
                color: sagana.cardBackground.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              ),
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
                  hasImage
                      ? Image.network(
                          item.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _CatalogThumb(cs: cs, icon: icon),
                        )
                      : _CatalogThumb(cs: cs, icon: icon),
                  if (onArchive != null)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: PopupMenuButton<String>(
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.more_vert_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        onSelected: (v) {
                          if (v == 'archive') onArchive!();
                        },
                        itemBuilder: (_) => [
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
                  if (unavailableLabel != null)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull,
                          ),
                        ),
                        child: Text(
                          unavailableLabel!,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.category} • ${itemTypeLabel(AppLocalizations.of(context), item.itemType)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₱${item.unitPrice.toStringAsFixed(2)} / ${item.unit}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context).enhStock(
                      (item.quantityOnHand.toStringAsFixed(0)).toString(),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    item.source == null
                        ? l10n.adminInvSourceNotRecorded
                        : '${l10n.adminInvSourceLabel}: ${item.source}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontStyle: item.source == null
                          ? FontStyle.italic
                          : FontStyle.normal,
                      color: cs.onSurfaceVariant,
                    ),
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

// ── Archived loan item card ──────────────────────────────────────────────────

/// One archived loan item: greyed photo, name, an Archived pill, category and
/// price chips, stock and Source, and a Restore button. Public so its layout
/// can be widget-tested.
class ArchivedLoanItemCard extends StatelessWidget {
  final LoanCatalogItem item;
  final VoidCallback onRestore;

  const ArchivedLoanItemCard({
    super.key,
    required this.item,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;

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

    final placeholder = _CatalogThumb(
      cs: cs,
      icon: loanCategoryIcon(item.category),
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
                            item.imageUrl!,
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
                      item.itemName,
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
                        chip(
                          localizeBuiltinLabel(
                            AppLocalizations.of(context),
                            item.category,
                          ),
                          cs.onSurfaceVariant,
                        ),
                        chip(
                          itemTypeLabel(l10n, item.itemType),
                          cs.onSurfaceVariant,
                        ),
                        chip(
                          '₱${item.unitPrice.toStringAsFixed(2)} / ${item.unit}',
                          cs.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            AppLocalizations.of(context).enhStock89(
              (item.quantityOnHand.toStringAsFixed(0)).toString(),
              (item.unit).toString(),
            ),
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            item.source == null
                ? l10n.adminInvSourceNotRecorded
                : '${l10n.adminInvSourceLabel}: ${item.source}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontStyle: item.source == null
                  ? FontStyle.italic
                  : FontStyle.normal,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
          const SizedBox(height: 10),
          if (item.inventoryArchived)
            Text(
              l10n.loanItemArchivedInInventory,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            )
          else
          SizedBox(
            width: double.infinity,
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
      child: Center(
        child: Icon(icon, size: 26, color: cs.outline.withValues(alpha: 0.40)),
      ),
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
