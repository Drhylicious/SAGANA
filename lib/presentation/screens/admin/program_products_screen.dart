import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../data/models/program_model.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/services/staff_permission_service.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/listing_filter_modal.dart' show MarketplaceFilterBar, MarketplaceFilterOption;
import '../../widgets/report_summary_widgets.dart' show ReportIconStatCard;
import '../../../core/utils/app_error_message.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/view_only_banner.dart';

/// Manage the products of a Product Sales program, as a page of its own.
///
/// A product is never deleted: the On sale switch is what lets farmers buy it.
/// Turn it off and it stops selling; its history and any purchases stay.
/// Route: /admin/programs/products
class ProgramProductsScreen extends StatefulWidget {
  final String programId;
  final String programName;

  /// The program's member discount, so the member price can be shown.
  final double memberDiscountPercent;

  /// True right after the program was created: the page then asks for the
  /// first products instead of showing an empty list.
  final bool justCreated;

  const ProgramProductsScreen({
    super.key,
    required this.programId,
    required this.programName,
    this.memberDiscountPercent = 0,
    this.justCreated = false,
  });

  @override
  State<ProgramProductsScreen> createState() => _ProgramProductsScreenState();
}

class _ProgramProductsScreenState extends State<ProgramProductsScreen> {
  final _repo = ProgramRepository();
  List<ProgramProduct> _products = [];
  List<DistributionItem> _eligible = [];
  bool _loading = true;
  // The inventory categories this program distributes from.
  List<String> _sources = [];
  String? _editingId;
  final _editPriceCtrl = TextEditingController();
  final _editAllocCtrl = TextEditingController();
  String? _editError;
  // The program's sales figures, its status, and the search / filter (shown only when there
  // are more than a handful of products).
  ProgramSalesSummary _summary = const ProgramSalesSummary();
  String _programStatus = 'active';
  ProductFilter _filter = ProductFilter.all;
  final _searchCtrl = TextEditingController();
  String _query = '';

  // A completed program's products can no longer be changed (the database refuses too).
  bool get _completed => _programStatus == 'completed';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
    _load().then((_) {
      // Right after a program is created, go straight to adding its first product.
      if (widget.justCreated && mounted) _openAddModal();
    });
  }

  @override
  void dispose() {
    _editPriceCtrl.dispose();
    _editAllocCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final products = await _repo.fetchProgramProducts(widget.programId);
    // If the sources cannot be read, none are offered: nothing is guessed.
    final sources = await _repo
        .fetchProgramSources(widget.programId)
        .catchError((_) => <String>[]);
    final eligible = await _repo.fetchEligibleInventoryForSaleProgram(categories: sources);
    final summary = await _repo.fetchProgramSalesSummary(widget.programId);
    final status = await _repo.fetchProgramStatus(widget.programId);
    if (!mounted) return;
    setState(() {
      _products = products;
      _sources = sources;
      _eligible = eligible;
      _summary = summary;
      _programStatus = status;
      _loading = false;
    });
  }

  List<DistributionItem> get _addable {
    final used = _products.map((p) => p.inventoryItemId).toSet();
    return _eligible.where((i) => !used.contains(i.id)).toList();
  }

  String _peso(double v) => '₱${v.toStringAsFixed(2)}';

  // The Add Product form is a modal opened by the floating + button; the page
  // itself stays a clean list.
  Future<void> _openAddModal() async {
    if (_completed) return;
    if (!requireManage(context, StaffModule.dashboard)) return;
    final items = _addable;
    final names = itemPickerNames(items);
    String? itemId;
    final priceCtrl = TextEditingController();
    final allocCtrl = TextEditingController();
    String? error;
    String? allocError;
    var saving = false;

    final added = await showManagementModal<bool>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> submit() async {
              if (saving) return;
              if (!requireManage(ctx, StaffModule.dashboard)) return;
              final price = double.tryParse(priceCtrl.text.trim());
              final alloc = double.tryParse(allocCtrl.text.trim());
              if (itemId == null) {
                setModal(() => error = l10n.prodChooseItem);
                return;
              }
              if (price == null || price < 0) {
                setModal(() => error = l10n.prodPriceInvalid);
                return;
              }
              if (alloc == null || alloc <= 0) {
                setModal(() {
                  error = null;
                  allocError = l10n.prodStockInvalid;
                });
                return;
              }
              setModal(() {
                saving = true;
                error = null;
                allocError = null;
              });
              try {
                await _repo.addProgramProduct(
                  programId: widget.programId,
                  inventoryItemId: itemId!,
                  unitPrice: price,
                  allocated: alloc,
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e, st) {
                // Over the modal: AppToast sits in front of dialogs.
                if (ctx.mounted) {
                  AppToast.show(ctx, friendlyError(l10n, e, st), isError: true);
                }
                setModal(() => saving = false);
              }
            }

            final String? blocked = _sources.isEmpty
                ? l10n.prodNoSources
                : items.isEmpty
                    // Nothing in stock in those categories, or every item is already a product.
                    ? (_eligible.isEmpty ? l10n.prodNoItemsInSources(_sources.join(', ')) : l10n.prodAddNothingLeft)
                    : null;

            return ManagementModalShell(
              title: l10n.prodAddTitle,
              onClose: saving ? null : () => Navigator.pop(ctx, false),
              body: blocked != null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              blocked,
                              key: const Key('addProductBlocked'),
                              style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: Theme.of(ctx).colorScheme.onSurface),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.justCreated)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              l10n.prodJustCreated,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                height: 1.4,
                                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        AppDropdownField<String>(
                          value: itemId,
                          hintText: l10n.prodChooseItem,
                          labelText: l10n.prodItemLabel,
                          items: items.map((i) => i.id).toList(),
                          // The name (with its source only when another item has the
                          // same name), then its stock and unit.
                          itemLabel: (id) {
                            final i = items.firstWhere((e) => e.id == id);
                            return '${names[id] ?? i.displayName} · ${formatQuantityUnit(i.quantityOnHand, i.unit)}';
                          },
                          onChanged: (v) => setModal(() => itemId = v),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: priceCtrl,
                          enabled: !saving,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                          decoration: InputDecoration(
                            labelText: l10n.prodPriceLabel,
                            prefixText: '₱ ',
                            errorText: error,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const Key('addStockField'),
                          controller: allocCtrl,
                          enabled: !saving,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                          decoration: InputDecoration(
                            labelText: l10n.prodStockForProgram,
                            helperText: l10n.prodStockForProgramHelp,
                            helperMaxLines: 3,
                            errorText: allocError,
                          ),
                        ),
                      ],
                    ),
              footer: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: saving ? null : () => Navigator.pop(ctx, false),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  if (blocked == null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: saving ? null : submit,
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(l10n.prodAddButton),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
    priceCtrl.dispose();
    allocCtrl.dispose();
    if (added == true && mounted) {
      AppToast.show(context, AppLocalizations.of(context).prodAdded);
      _load();
    }
  }

  Future<void> _toggle(ProgramProduct p, bool on) async {
    if (_completed) return;
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    final ok = await _repo.updateProgramProduct(
      productId: p.id,
      unitPrice: p.unitPrice,
      isAvailable: on,
    );
    if (!mounted) return;
    AppToast.show(
      context,
      ok ? (on ? l10n.prodTurnedOn : l10n.prodTurnedOff) : l10n.errGeneric,
      isError: !ok,
    );
    if (ok) _load();
  }

  Future<void> _savePrice(ProgramProduct p) async {
    if (_completed) return;
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    final price = double.tryParse(_editPriceCtrl.text.trim());
    if (price == null || price < 0) {
      setState(() => _editError = l10n.prodPriceInvalid);
      return;
    }
    final alloc = double.tryParse(_editAllocCtrl.text.trim());
    if (alloc == null || alloc < 0) {
      setState(() => _editError = l10n.prodStockInvalid);
      return;
    }
    final ok = await _repo.updateProgramProduct(
      productId: p.id,
      unitPrice: price,
      isAvailable: p.isAvailable,
    );
    if (!mounted) return;
    if (!ok) {
      AppToast.show(context, l10n.errGeneric, isError: true);
      return;
    }
    // The stock for this program is changed by its own guarded function.
    if ((alloc - p.stockAllocated).abs() > 0.004) {
      try {
        await _repo.setProductAllocation(productId: p.id, allocated: alloc);
      } catch (e, st) {
        if (!mounted) return;
        AppToast.show(context, friendlyError(l10n, e, st), isError: true);
        _load();
        return;
      }
    }
    if (!mounted) return;
    AppToast.show(context, l10n.prodSaved);
    setState(() => _editingId = null);
    _load();
  }

  Future<void> _release(ProgramProduct p) async {
    if (_completed) return;
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    try {
      await _repo.releaseProductAllocation(p.id);
      if (!mounted) return;
      AppToast.show(context, l10n.prodStockReleased);
      setState(() => _editingId = null);
      _load();
    } catch (e, st) {
      if (!mounted) return;
      AppToast.show(context, friendlyError(l10n, e, st), isError: true);
    }
  }

  String _percentText(double v) => formatQuantity(v); // up to 2 decimals, as the database keeps them

  // The On sale switch and Edit price. Side by side with a clear gap when both fit; otherwise
  // the button goes under the switch, at the right. They never touch.
  Widget _footer(ProgramProduct p, AppLocalizations l10n, ColorScheme cs, bool readOnly, bool editing) {
    final label = p.isAvailable ? l10n.prodOnSale : l10n.prodOffHidden;
    final labelStyle = GoogleFonts.inter(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: p.isAvailable ? AppConstants.successGreen : cs.onSurfaceVariant,
    );
    final toggle = <Widget>[
      Switch(
        key: Key('productSwitch_${p.id}'),
        value: p.isAvailable,
        activeColor: AppConstants.successGreen,
        onChanged: readOnly ? null : (v) => _toggle(p, v),
      ),
      const SizedBox(width: 6),
      Expanded(child: Text(label, style: labelStyle)),
    ];
    final edit = OutlinedButton.icon(
      key: Key('editPrice_${p.id}'),
      onPressed: () => setState(() {
        _editingId = editing ? null : p.id;
        _editError = null;
        _editPriceCtrl.text = p.unitPrice.toStringAsFixed(2);
        _editAllocCtrl.text = p.stockAllocated.toStringAsFixed(p.stockAllocated % 1 == 0 ? 0 : 2);
      }),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.edit_outlined, size: 16),
      label: Text(l10n.prodEditPrice),
    );
    if (readOnly) return Row(children: toggle);
    return LayoutBuilder(
      builder: (context, box) {
        double w(String t, TextStyle s) => (TextPainter(
              text: TextSpan(text: t, style: s),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout())
            .width;
        // switch (about 60) + gap + label, then a gap, then the button (icon, text, padding).
        final needed = 66 + w(label, labelStyle) + 16 + 16 + 8 + w(l10n.prodEditPrice, GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)) + 24 + 12;
        if (needed <= box.maxWidth) {
          return Row(children: [...toggle, const SizedBox(width: 12), edit]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: toggle),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: edit),
          ],
        );
      },
    );
  }

  Widget _productCard(ProgramProduct p, AppLocalizations l10n, ColorScheme cs) {
    final readOnly = _completed;
    final hasDiscount = widget.memberDiscountPercent > 0;
    final editing = _editingId == p.id && !readOnly;
    final sales = _summary.byProduct[p.id];
    // The member discount: one line when the card is wide, two short lines when it is narrow,
    // so it can still sit at the right of the name on a phone.
    final pill = hasDiscount
        ? LayoutBuilder(
            builder: (context, box) {
              final compact = MediaQuery.sizeOf(context).width / MediaQuery.textScalerOf(context).scale(1) < 420;
              return Container(
                key: Key('discountPill_${p.id}'),
                constraints: BoxConstraints(maxWidth: compact ? 88 : double.infinity),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppConstants.successGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l10n.prodMembersGetOff(_percentText(widget.memberDiscountPercent)),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 10.5, height: 1.2, fontWeight: FontWeight.w700, color: AppConstants.successGreen),
                ),
              );
            },
          )
        : null;
    final name = Text(
      p.itemName,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700),
    );
    return Container(
      key: Key('productCard_${p.id}'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A turned-off product is dimmed; the switch below stays at full strength.
          Opacity(
            opacity: p.isAvailable ? 1 : 0.6,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: (p.imageUrl != null && p.imageUrl!.isNotEmpty)
                        ? Image.network(
                            p.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _photoFallback(cs),
                          )
                        : _photoFallback(cs),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The name, and the member discount at its right. If both do not fit on
                      // one line, the discount drops below the name instead of squeezing it.
                      if (pill == null)
                        name
                      else
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [name, pill],
                        ),
                      const SizedBox(height: 2),
                      p.isOutOfStock
                          ? Text(
                              l10n.prodOutOfStock,
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppConstants.errorRed),
                            )
                          : Text(
                              key: Key('productStock_${p.id}'),
                              l10n.prodStockAvailable(formatQuantityGrouped(p.availableToSell), p.unit),
                              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                      if (p.stockReserved > 0)
                        Text(
                          key: Key('productReserved_${p.id}'),
                          l10n.prodStockReserved(formatQuantityGrouped(p.stockReserved), p.unit),
                          style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                        ),
                      const SizedBox(height: 8),
                      if (hasDiscount)
                        Wrap(
                          spacing: 10,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              l10n.prodMemberPrice(_peso(memberUnitPrice(p.unitPrice, widget.memberDiscountPercent))),
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppConstants.successGreen),
                            ),
                            Text(
                              l10n.prodRegularPrice(_peso(p.unitPrice)),
                              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        )
                      else
                        Text(
                          l10n.prodRegularPrice(_peso(p.unitPrice)),
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        key: Key('productSales_${p.id}'),
                        sales == null || sales.sold <= 0
                            ? l10n.prodNoSalesYet
                            : '${l10n.prodBuyers(sales.buyers)} · ${l10n.prodSoldLine(formatQuantityGrouped(sales.sold), p.unit)}',
                        style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
          const SizedBox(height: 8),
          _footer(p, l10n, cs, readOnly, editing),
          if (editing) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _editPriceCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              decoration: InputDecoration(
                labelText: l10n.prodPriceLabel,
                prefixText: '₱ ',
                errorText: _editError,
              ),
              onSubmitted: (_) => _savePrice(p),
            ),
            const SizedBox(height: 10),
            TextField(
              key: Key('editStock_${p.id}'),
              controller: _editAllocCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              decoration: InputDecoration(
                labelText: l10n.prodStockForProgram,
                helperText: l10n.prodStockOnHandHelp(formatQuantityGrouped(p.quantityOnHand), p.unit),
                helperMaxLines: 3,
              ),
              onSubmitted: (_) => _savePrice(p),
            ),
            if (p.availableToSell > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: Key('releaseStock_${p.id}'),
                  onPressed: () => _release(p),
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: Text(l10n.prodReleaseStock),
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _editingId = null),
                  child: Text(l10n.cancel),
                ),
                const Spacer(),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => _savePrice(p),
                  child: Text(l10n.prodSave),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // Four cards that scroll sideways, whatever the screen width.
  Widget _kpis(AppLocalizations l10n) {
    String peso(double v) => '₱${formatQuantityGrouped(v)}';
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final cards = <Widget>[
      ReportIconStatCard(icon: Icons.payments_rounded, accent: AppConstants.successGreen, label: l10n.prodKpiSales, value: peso(_summary.totalSales)),
      ReportIconStatCard(icon: Icons.groups_rounded, accent: AppConstants.buyerBlue, label: l10n.prodKpiBuyers, value: '${_summary.buyers}'),
      ReportIconStatCard(icon: Icons.savings_rounded, accent: AppConstants.programPurple, label: l10n.prodKpiSavings, value: peso(_summary.savings)),
      ReportIconStatCard(icon: Icons.hourglass_top_rounded, accent: AppConstants.warningAmber, label: l10n.prodKpiPending, value: '${_summary.pending}'),
    ];
    return SizedBox(
      key: const Key('productKpis'),
      height: 104 * (scale > 1 ? 1 + (scale - 1) * 0.75 : 1),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppConstants.spacingSm),
        itemBuilder: (_, i) => SizedBox(width: 168, child: cards[i]),
      ),
    );
  }

  // Search and filter chips, offered only when there are more than a handful of products.
  Widget _controls(AppLocalizations l10n, ColorScheme cs) {
    int count(ProductFilter f) => _products.where((p) => productMatchesFilter(p, f)).length;
    return Column(
      key: const Key('productControls'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: l10n.prodSearchHint,
            prefixIcon: const Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 10),
        MarketplaceFilterBar<ProductFilter>(
          selected: _filter,
          onSelected: (v) => setState(() => _filter = v),
          options: [
            MarketplaceFilterOption(value: ProductFilter.all, label: l10n.prodChipAll, count: _products.length, color: cs.primary),
            MarketplaceFilterOption(value: ProductFilter.onSale, label: l10n.prodChipOnSale, count: count(ProductFilter.onSale), color: AppConstants.successGreen),
            MarketplaceFilterOption(value: ProductFilter.outOfStock, label: l10n.prodChipOutOfStock, count: count(ProductFilter.outOfStock), color: AppConstants.errorRed),
            MarketplaceFilterOption(value: ProductFilter.off, label: l10n.prodChipOff, count: count(ProductFilter.off), color: cs.onSurfaceVariant),
          ],
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  List<Widget> _productList(AppLocalizations l10n, ColorScheme cs) {
    var shown = _products.where((p) => productMatchesFilter(p, _filter));
    if (_query.isNotEmpty) {
      shown = shown.where((p) => p.itemName.toLowerCase().contains(_query));
    }
    // Active products first, archived ones last (dimmed), by name inside each.
    final visible = sortProductsForDisplay(shown);
    if (visible.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Center(
            child: Text(l10n.prodNoMatch, style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
        ),
      ];
    }
    // One list, unless the products come from more than one category. Then each category is a
    // section of its active products, and ALL archived products follow in a last section, so
    // archived ones are at the bottom of the page and never between active ones.
    final cats = productCategories(_products);
    if (cats.length <= 1) return [for (final p in visible) _productCard(p, l10n, cs)];
    Widget header(Key key, String text) => Padding(
          key: key,
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            text,
            style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
          ),
        );
    final active = visible.where((p) => p.isAvailable).toList();
    final archived = visible.where((p) => !p.isAvailable).toList();
    return [
      for (final cat in cats) ...() {
        final inCat = active.where((p) => p.category.trim().toLowerCase() == cat.toLowerCase()).toList();
        if (inCat.isEmpty) return <Widget>[];
        return <Widget>[
          header(Key('category_${cat.toLowerCase()}'), '${cat.isEmpty ? '—' : cat} · ${inCat.length}'),
          for (final p in inCat) _productCard(p, l10n, cs),
        ];
      }(),
      if (archived.isNotEmpty) ...[
        header(const Key('archivedSection'), '${l10n.prodChipOff} · ${archived.length}'),
        for (final p in archived) _productCard(p, l10n, cs),
      ],
    ];
  }

  Widget _photoFallback(ColorScheme cs) => Container(
    color: cs.surfaceContainerHighest,
    child: Icon(Icons.storefront_rounded, color: cs.outline.withValues(alpha: 0.5)),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // The same + button as Program Management, Inventory and Crops. A completed program's
      // products can no longer be changed, so it has none.
      floatingActionButton: _loading || _completed
          ? null
          : FloatingActionButton(
              heroTag: 'add_program_product',
              tooltip: l10n.prodAddAction,
              backgroundColor: AppConstants.primaryGreen,
              onPressed: _openAddModal,
              child: const Icon(Icons.add_rounded, color: Colors.white),
            ),
      body: SafeArea(
        child: Column(
          children: [
            SubPageTopBar(title: l10n.prodTitle, onBack: () => context.pop()),
            Expanded(
              child: _loading
                  ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        // Room at the bottom so the round + button never covers a card.
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                        children: [
                          if (_completed)
                            Container(
                              key: const Key('completedBanner'),
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.onSurfaceVariant.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.lock_outline_rounded, size: 16, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.prodCompletedBanner,
                                      style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: cs.onSurface),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_products.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: Column(
                                children: [
                                  Icon(Icons.storefront_outlined, size: 48, color: cs.onSurfaceVariant),
                                  const SizedBox(height: 10),
                                  Text(
                                    l10n.prodEmpty,
                                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.prodEmptyHint,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            _kpis(l10n),
                            const SizedBox(height: 16),
                            _controls(l10n, cs),
                            ..._productList(l10n, cs),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
