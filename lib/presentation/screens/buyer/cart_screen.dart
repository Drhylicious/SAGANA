import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/cart_item_model.dart';
import '../../../data/models/farmer_crop_model.dart' show marketTypeLabelFor;
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/services/cart_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';

class CartScreen extends StatefulWidget {
  // Phase 9 — reused as-is for the Farmer Marketplace tab's cart; only the
  // post-checkout destination route differs (see _checkout()).
  final bool isFarmerContext;
  const CartScreen({super.key, this.isFarmerContext = false});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

String _fmtCartQty(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);

class _CartScreenState extends State<CartScreen> {
  final _cartService = CartService();
  final _marketRepo = BuyerMarketplaceRepository();

  bool _isLoading = true;
  bool _isCheckingOut = false;
  // Cart UI overhaul — selection checkboxes are always visible (not just in
  // Edit Mode); they drive which items go to Checkout. Edit Mode reuses the
  // exact same selection set, just for bulk delete instead — see
  // _toggleEditMode(), which clears selection on every mode switch so a
  // "select to delete" choice can never silently carry into "select to
  // checkout" or vice versa.
  bool _isEditMode = false;
  List<CartItemModel> _items = [];
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final items = await _cartService.getItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _selectedIds.removeWhere((id) => !items.any((i) => i.listingId == id));
      _isLoading = false;
    });
  }

  double get _selectedTotal => _items
      .where((i) => _selectedIds.contains(i.listingId))
      .fold(0.0, (sum, i) => sum + i.subtotal);

  bool get _allSelected => _items.isNotEmpty && _selectedIds.length == _items.length;

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      _selectedIds.clear();
    });
  }

  void _toggleItem(String listingId) {
    setState(() {
      if (_selectedIds.contains(listingId)) {
        _selectedIds.remove(listingId);
      } else {
        _selectedIds.add(listingId);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_items.map((i) => i.listingId));
      }
    });
  }

  Future<void> _deleteSelected() async {
    for (final id in _selectedIds.toList()) {
      await _cartService.removeItem(id);
    }
    setState(() {
      _selectedIds.clear();
      _isEditMode = false;
    });
    _load();
  }

  Future<void> _updateQuantity(CartItemModel item, double delta) async {
    // Lower bound must never exceed availableKgSnapshot — a hardcoded 1.0
    // floor would throw (ArgumentError: lowerLimit > upperLimit) for any
    // listing with under 1kg remaining, which is a real, valid state now
    // that fractional kg is properly supported end-to-end.
    final upper = item.availableKgSnapshot;
    final lower = upper > 0 ? (upper < 0.01 ? upper : 0.01) : 0.0;
    final newQty = (item.quantityKg + delta).clamp(lower, upper);
    await _cartService.updateQuantity(item.listingId, newQty);
    _load();
  }

  Future<void> _removeItem(CartItemModel item) async {
    await _cartService.removeItem(item.listingId);
    _selectedIds.remove(item.listingId);
    _load();
  }

  // Phase 8, item 1: fetchCurrentRemainingKg() has existed since an
  // earlier backend-only pass (Buyer review finding 2.4), but nothing
  // called it until now. place_order()'s own server-side FOR UPDATE check
  // was always the real authority and still fully protects against
  // overselling without this step — this exists purely so the buyer sees
  // an accurate number up front instead of only discovering drift via a
  // checkout-time failure.
  //
  // Cart UI overhaul: only SELECTED items are checked/reserved/checked out
  // — unselected items are left completely untouched in the cart, per
  // explicit direction.
  Future<void> _checkout() async {
    if (_selectedIds.isEmpty) {
      await AppDialog.show<void>(
        context: context,
        child: const _NoItemsSelectedDialog(),
      );
      return;
    }

    final l10n = AppLocalizations.of(context);
    setState(() => _isCheckingOut = true);

    final selectedItems = _items.where((i) => _selectedIds.contains(i.listingId)).toList();

    final liveStock = await _marketRepo.fetchCurrentRemainingKg(
      selectedItems.map((i) => i.listingId).toList(),
    );

    final adjustments = <String>[];
    for (final item in List<CartItemModel>.from(selectedItems)) {
      final live = liveStock[item.listingId] ?? 0.0;
      if (live <= 0) {
        await _cartService.removeItem(item.listingId);
        _selectedIds.remove(item.listingId);
        adjustments.add(l10n.buyerCartAdjustedRemoved(item.displayName));
      } else if (live < item.quantityKg) {
        await _cartService.updateQuantity(item.listingId, live);
        adjustments.add(l10n.buyerCartAdjustedReduced(item.displayName, _fmtCartQty(live)));
      }
    }

    if (!mounted) return;

    if (adjustments.isNotEmpty) {
      await _load(); // refresh _items to reflect the adjustments above
      if (!mounted) return;
      setState(() => _isCheckingOut = false);
      await AppDialog.show<void>(
        context: context,
        child: _StockChangedDialog(messages: adjustments),
      );
      // Buyer reviews the now-accurate cart and taps Checkout again
      // themselves — not auto-advanced past a silently-changed order.
      return;
    }

    // Checkout + My Addresses (Phase 6b): the confirmation dialog and the
    // per-item placeOrder loop both moved to the shared CheckoutScreen,
    // which is where fulfillment is now chosen and where the placement
    // progress ("Placing X of Y") is shown instead. This screen's job
    // stops at handing over a stock-accurate, selection-scoped item list.
    setState(() => _isCheckingOut = false);
    if (!mounted) return;
    final finalItems = _items.where((i) => _selectedIds.contains(i.listingId)).toList();
    context.push(
      widget.isFarmerContext ? AppRoutes.farmerMarketplaceCheckout : AppRoutes.checkout,
      extra: {
        'items': finalItems,
        'isCartCheckout': true,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        leading: BackButton(onPressed: () => context.pop(), color: AppConstants.primaryGreen),
        title: Text(
          _items.isEmpty ? l10n.buyerCartTitle : '${l10n.buyerCartTitle} (${_items.length})',
          style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen),
        ),
        actions: [
          if (_items.isNotEmpty)
            TextButton(
              onPressed: _toggleEditMode,
              child: Text(
                _isEditMode ? l10n.buyerCartDone : l10n.buyerCartEdit,
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _buildEmptyState(l10n)
              : Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 12, AppConstants.spacingSafeH, 12),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _CartItemTile(
                          item: _items[i],
                          selected: _selectedIds.contains(_items[i].listingId),
                          swipeToDeleteEnabled: !_isEditMode,
                          onToggleSelect: () => _toggleItem(_items[i].listingId),
                          onIncrement: () => _updateQuantity(_items[i], 1),
                          onDecrement: () => _updateQuantity(_items[i], -1),
                          onRemove: () => _removeItem(_items[i]),
                        ),
                      ),
                    ),
                    _buildBottomBar(l10n),
                  ],
                ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 56, color: AppConstants.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(l10n.buyerCartEmptyTitle, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(l10n.buyerCartEmptyBody,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 16),
            PrimaryButton(label: l10n.browseMarketplace, onPressed: () => context.pop()),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    // The per-item placement progress ("Placing X of Y") that used to show
    // here moved to CheckoutScreen (Phase 6b) — this bar's own _isCheckingOut
    // now only covers the brief stock-refresh step before navigating there.
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 20, 14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        border: Border(top: BorderSide(color: AppConstants.outline.withValues(alpha: 0.10))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -3))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Expanded (not a trailing Spacer): this is the one shrinkable
            // slot in the row. The Total price and the checkout/delete
            // button on the right must never truncate, so they stay as
            // plain, naturally-sized children — if space ever runs out,
            // it's this "Select All" label that gives way first, not them.
            Expanded(
              child: GestureDetector(
                onTap: _toggleSelectAll,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Checkbox(
                      value: _allSelected,
                      activeColor: AppConstants.primaryGreen,
                      onChanged: (_) => _toggleSelectAll(),
                    ),
                    Flexible(
                      child: Text(l10n.buyerCartSelectAll,
                          overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_isEditMode)
              OutlinedButton(
                onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.errorRed,
                  side: BorderSide(color: _selectedIds.isEmpty ? AppConstants.outline.withValues(alpha: 0.3) : AppConstants.errorRed),
                  // The app-wide OutlinedButtonThemeData forces minimumSize
                  // to Size(double.infinity, 52) — fine when this button is
                  // the sole child of a full-width SizedBox, but here it's a
                  // plain Row child, so that infinite width has to be
                  // overridden or layout crashes with "BoxConstraints forces
                  // an infinite width".
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: Text(l10n.buyerCartDelete),
              )
            else ...[
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(l10n.buyerCartTotalLabel, style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                  Text('₱${_selectedTotal.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
                ],
              ),
              const SizedBox(width: 12),
              PrimaryButton(
                label: l10n.buyerCartProceedCheckoutCount(_selectedIds.length),
                isLoading: _isCheckingOut,
                onPressed: _isCheckingOut ? null : _checkout,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItemModel item;
  final bool selected;
  final bool swipeToDeleteEnabled;
  final VoidCallback onToggleSelect;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  const _CartItemTile({
    required this.item,
    required this.selected,
    required this.swipeToDeleteEnabled,
    required this.onToggleSelect,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.listingId),
      direction: swipeToDeleteEnabled ? DismissDirection.endToStart : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppConstants.errorRed, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onRemove(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: selected ? Border.all(color: AppConstants.primaryGreen, width: 1.5) : AppConstants.cardBorder,
          boxShadow: AppConstants.cardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: selected,
              activeColor: AppConstants.primaryGreen,
              onChanged: (_) => onToggleSelect(),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              child: item.photoUrl != null
                  ? Image.network(item.photoUrl!, width: 56, height: 56, fit: BoxFit.cover)
                  : Container(width: 56, height: 56, color: AppConstants.limeGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.displayName, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                  Text('₱${item.pricePerKg.toStringAsFixed(2)}/kg',
                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                  if (item.category != null || item.marketType != null) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (item.category != null) _CartTag(item.category!),
                        if (item.marketType != null) _CartTag(marketTypeLabelFor(item.marketType)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _stepperBtn(context, Icons.remove, item.quantityKg > 0.01 ? onDecrement : null),
                      SizedBox(
                        width: 40,
                        child: Text(_fmtCartQty(item.quantityKg),
                            textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                      _stepperBtn(context, Icons.add, item.quantityKg < item.availableKgSnapshot ? onIncrement : null),
                    ],
                  ),
                ],
              ),
            ),
            Text('₱${item.subtotal.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
          ],
        ),
      ),
    );
  }

  Widget _stepperBtn(BuildContext context, IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: onTap == null ? AppConstants.outline.withValues(alpha: 0.1) : context.saganaColors.scaffoldBackground,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: onTap == null ? AppConstants.outline : AppConstants.primaryGreen),
      ),
    );
  }
}

// Small pill for Category/Market Type on the cart tile — same info a buyer
// already saw on Listing Details, carried through so the cart isn't a
// stripped-down summary of what they were looking at.
class _CartTag extends StatelessWidget {
  final String label;
  const _CartTag(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppConstants.infoBlueBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Text(label,
          style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppConstants.infoBlueFg)),
    );
  }
}

class _NoItemsSelectedDialog extends StatelessWidget {
  const _NoItemsSelectedDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: AppConstants.cardBorder,
          boxShadow: AppConstants.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppConstants.warningAmber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.buyerCartNoSelectionTitle,
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(l10n.buyerCartNoSelectionBody,
                style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: l10n.buyerCartNoSelectionOk, onPressed: () => Navigator.pop(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockChangedDialog extends StatelessWidget {
  final List<String> messages;
  const _StockChangedDialog({required this.messages});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: AppConstants.cardBorder,
          boxShadow: AppConstants.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_rounded, color: AppConstants.warningAmber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.buyerCartStockChangedTitle,
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(l10n.buyerCartStockChangedBody,
                style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: messages
                      .map((m) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text('• $m', style: GoogleFonts.inter(fontSize: 13, height: 1.4)),
                          ))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: l10n.buyerCartReviewCart, onPressed: () => Navigator.pop(context)),
            ),
          ],
        ),
      ),
    );
  }
}
