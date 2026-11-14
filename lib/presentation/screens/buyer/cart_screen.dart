import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../widgets/app_toast.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/cart_eligibility.dart';
import '../../../data/models/cart_item_model.dart';
import '../../../data/models/cooperative_product_model.dart';
import '../../../data/repositories/farmer_program_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/market_types_service.dart';
import '../../../data/models/farmer_crop_model.dart' show marketTypeLabelFor;
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/services/cart_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/quantity_stepper.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

class CartScreen extends StatefulWidget {
  // Phase 9 — reused as-is for the Farmer Marketplace tab's cart; only the
  // post-checkout destination route differs (see _checkout()).
  final bool isFarmerContext;
  const CartScreen({super.key, this.isFarmerContext = false});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _cartService = CartService();
  final _marketRepo = BuyerMarketplaceRepository();
  final _programRepo = FarmerProgramRepository();

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
  // Lines that can no longer be bought, with the reason. Filled by
  // _refreshIssues() while online; empty when offline (nothing is checked then).
  Map<String, CartIssue> _issues = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [silent] reloads in the background and keeps the list on screen. Only the
  /// first load shows the skeleton; reloading after a change (a removal, a
  /// stock adjustment) must not blank the whole cart.
  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    var items = await _cartService.getItems();
    // Cooperative Products are for Farmers only. A Buyer's cart never shows one (a Buyer cannot
    // add one, and the database refuses to place it), so any such line is dropped, never shown.
    if (!widget.isFarmerContext && items.any((i) => i.isCooperative)) {
      for (final i in items.where((i) => i.isCooperative)) {
        await _cartService.removeItem(i.listingId);
      }
      items = items.where((i) => !i.isCooperative).toList();
    }
    final issues = await _evaluate(items);
    if (!mounted) return;
    setState(() {
      _items = items;
      _issues = issues;
      // A line that cannot be bought is never left selected for checkout.
      _selectedIds.removeWhere(
        (id) => !items.any((i) => i.listingId == id) || _blocked(id),
      );
      _isLoading = false;
    });
  }

  /// Checks every saved line against the live listing and this account's
  /// market access. Offline (or if the lookup fails) nothing is flagged: the
  /// database still refuses an ineligible order at checkout.
  Future<Map<String, CartIssue>> _evaluate(List<CartItemModel> items) async {
    if (items.isEmpty || !ConnectivityService.instance.isOnline) return {};
    final result = <String, CartIssue>{};

    // Cooperative lines are checked against the live product (still on sale, stock left).
    final coop = items.where((i) => i.isCooperative).toList();
    if (coop.isNotEmpty) {
      final coopRows = await _programRepo.fetchCooperativeCartRows(
        coop.map((i) => i.listingId).toList(),
      );
      if (coopRows != null) {
        for (final item in coop) {
          switch (evaluateCooperativeCartLine(coopRows[item.listingId])) {
            case CooperativeCartIssue.none:
              break;
            case CooperativeCartIssue.unavailable:
              result[item.listingId] = CartIssue.unavailable;
            case CooperativeCartIssue.soldOut:
              result[item.listingId] = CartIssue.soldOut;
          }
        }
      }
    }

    final market = items.where((i) => !i.isCooperative).toList();
    if (market.isEmpty) return result;
    final rows = await _marketRepo.fetchCartListingRows(
      market.map((i) => i.listingId).toList(),
    );
    if (rows == null) return result;
    final uid = AuthService.currentUser?.id;
    for (final item in market) {
      final issue = evaluateCartItem(
        item: item,
        listing: rows[item.listingId],
        currentUserId: uid,
        canSeeMarket: MarketTypes.instance.visibleToCurrentUser,
      );
      if (issue != CartIssue.none) result[item.listingId] = issue;
    }
    return result;
  }

  bool _blocked(String listingId) =>
      (_issues[listingId] ?? CartIssue.none) != CartIssue.none;

  String _issueText(AppLocalizations l10n, CartIssue issue) {
    switch (issue) {
      case CartIssue.restricted:
        return l10n.buyerCartIssueRestricted;
      case CartIssue.soldOut:
        return l10n.buyerCartIssueSoldOut;
      case CartIssue.ownListing:
        return l10n.buyerCartIssueOwn;
      case CartIssue.unavailable:
      case CartIssue.none:
        return l10n.buyerCartIssueUnavailable;
    }
  }

  /// Removes every line that cannot be purchased.
  Future<void> _removeBlocked() async {
    if (!ConnectivityService.instance.isOnline) {
      AppToast.show(context, AppLocalizations.of(context).offlineBuyerBody);
      return;
    }
    for (final id in _issues.keys.toList()) {
      await _cartService.removeItem(id);
      _selectedIds.remove(id);
    }
    _load(silent: true);
  }

  double get _selectedTotal => _items
      .where((i) => _selectedIds.contains(i.listingId))
      .fold(0.0, (sum, i) => sum + i.subtotal);

  // Lines that can be selected for checkout. In Edit Mode every line can be
  // selected (to delete it), including one that can no longer be bought.
  List<CartItemModel> get _selectable => _isEditMode
      ? _items
      : _items.where((i) => !_blocked(i.listingId)).toList();

  bool get _allSelected =>
      _selectable.isNotEmpty && _selectedIds.length == _selectable.length;

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      _selectedIds.clear();
    });
  }

  void _toggleItem(String listingId) {
    // A line that cannot be bought cannot be selected for checkout (it can
    // still be selected in Edit Mode, to delete it).
    if (!_isEditMode && _blocked(listingId)) return;
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
          ..addAll(_selectable.map((i) => i.listingId));
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (!ConnectivityService.instance.isOnline) {
      AppToast.show(context, AppLocalizations.of(context).offlineBuyerBody);
      return;
    }
    final deleted = _selectedIds.toList();
    for (final id in deleted) {
      await _cartService.removeItem(id);
    }
    if (!mounted) return;
    setState(() {
      _items.removeWhere((i) => deleted.contains(i.listingId));
      _selectedIds.clear();
      _isEditMode = false;
    });
    _load(silent: true);
  }

  /// A new quantity for one line (from the - / + buttons or typed). Only that
  /// line changes: it is updated in place and saved, so the cart does not
  /// reload, show the skeleton or re-check every listing for a quantity change.
  /// The stepper has already limited it to 0.01 .. the stock left, and refuses
  /// the change while offline (see [_changesAllowed]).
  void _setQuantity(CartItemModel item, double quantity) {
    setState(() => item.quantityKg = quantity);
    unawaited(_cartService.updateQuantity(item.listingId, quantity));
  }

  // The cart is only changed while online (as before): offline the quantity
  // control puts the old number back and says why.
  bool _changesAllowed() => ConnectivityService.instance.isOnline;

  void _changesBlocked() =>
      AppToast.show(context, AppLocalizations.of(context).offlineBuyerBody);

  Future<void> _removeItem(CartItemModel item) async {
    if (!ConnectivityService.instance.isOnline) {
      AppToast.show(context, AppLocalizations.of(context).offlineBuyerBody);
      // A swiped-away line comes back: it was not removed.
      if (mounted) setState(() {});
      return;
    }
    // Out of the list at once: a swiped line must not stay in the tree.
    setState(() {
      _items.removeWhere((i) => i.listingId == item.listingId);
      _selectedIds.remove(item.listingId);
    });
    await _cartService.removeItem(item.listingId);
    _load(silent: true);
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

    final selectedItems = _items
        .where((i) => _selectedIds.contains(i.listingId))
        .toList();

    // Re-check eligibility right before checkout (a listing may have been
    // withdrawn, sold out, or moved out of this account's reach since the cart
    // was opened). Ineligible lines are taken out of the selection and the
    // buyer is told why; nothing is sent to checkout.
    final latestIssues = await _evaluate(selectedItems);
    if (latestIssues.isNotEmpty) {
      final lines = [
        for (final i in selectedItems)
          if (latestIssues.containsKey(i.listingId))
            l10n.buyerCartIssueLine(
              i.displayName,
              _issueText(l10n, latestIssues[i.listingId]!),
            ),
      ];
      _selectedIds.removeAll(latestIssues.keys);
      await _load();
      if (!mounted) return;
      setState(() => _isCheckingOut = false);
      await AppDialog.show<void>(
        context: context,
        child: _CartBlockedDialog(messages: lines),
      );
      return;
    }

    final liveStock = await _marketRepo.fetchCurrentRemainingKg(
      selectedItems
          .where((i) => !i.isCooperative)
          .map((i) => i.listingId)
          .toList(),
    );
    // Cooperative lines: what is left of the stock set aside for the program.
    final coopLines = selectedItems.where((i) => i.isCooperative).toList();
    if (coopLines.isNotEmpty) {
      final rows = await _programRepo.fetchCooperativeCartRows(
        coopLines.map((i) => i.listingId).toList(),
      );
      for (final i in coopLines) {
        final p = rows == null
            ? null
            : CooperativeProduct.fromRow(
                rows[i.listingId] ?? const {},
                isMember: false,
              );
        // When the lookup fails the saved figure stands: the database still decides at checkout.
        liveStock[i.listingId] = rows == null
            ? i.availableKgSnapshot
            : (p?.availableToSell ?? 0);
      }
    }

    final adjustments = <String>[];
    for (final item in List<CartItemModel>.from(selectedItems)) {
      final live = liveStock[item.listingId] ?? 0.0;
      if (live <= 0) {
        await _cartService.removeItem(item.listingId);
        _selectedIds.remove(item.listingId);
        adjustments.add(l10n.buyerCartAdjustedRemoved(item.displayName));
      } else if (live < item.quantityKg) {
        await _cartService.updateQuantity(item.listingId, live);
        adjustments.add(
          l10n.buyerCartAdjustedReduced(
            item.displayName,
            formatQuantityUnit(live, item.unit),
          ),
        );
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
    final finalItems = _items
        .where((i) => _selectedIds.contains(i.listingId))
        .toList();
    context.push(
      widget.isFarmerContext
          ? AppRoutes.farmerMarketplaceCheckout
          : AppRoutes.checkout,
      extra: {"items": finalItems, 'isCartCheckout': true},
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,

      body: Column(
        children: [
          SubPageTopBar(
            title: _items.isEmpty
                ? l10n.buyerCartTitle
                : '${l10n.buyerCartTitle} (${_items.length})',
            onBack: () => Navigator.of(context).pop(),
            trailing: _items.isNotEmpty
                ? TextButton(
                    onPressed: _toggleEditMode,
                    child: Text(
                      _isEditMode ? l10n.buyerCartDone : l10n.buyerCartEdit,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  )
                : null,
          ),
          OfflineStatusCard(
            title: l10n.offlineStatusTitle,
            message: l10n.offlineBuyerBody,
          ),
          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : _items.isEmpty
                ? _buildEmptyState(l10n)
                : Column(
                    children: [
                      if (_issues.isNotEmpty) _buildBlockedBanner(l10n),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            AppConstants.spacingSafeH,
                            12,
                            AppConstants.spacingSafeH,
                            12,
                          ),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) => _CartItemTile(
                            item: _items[i],
                            selected: _selectedIds.contains(
                              _items[i].listingId,
                            ),
                            swipeToDeleteEnabled: !_isEditMode,
                            issueText: _blocked(_items[i].listingId)
                                ? _issueText(
                                    l10n,
                                    _issues[_items[i].listingId]!,
                                  )
                                : null,
                            selectable:
                                _isEditMode || !_blocked(_items[i].listingId),
                            onToggleSelect: () =>
                                _toggleItem(_items[i].listingId),
                            onQuantityChanged: (q) =>
                                _setQuantity(_items[i], q),
                            allowQuantityChange: _changesAllowed,
                            onQuantityBlocked: _changesBlocked,
                            onRemove: () => _removeItem(_items[i]),
                          ),
                        ),
                      ),
                      _buildBottomBar(l10n),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedBanner(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppConstants.spacingSafeH,
        12,
        AppConstants.spacingSafeH,
        0,
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppConstants.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: AppConstants.errorRed.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.remove_shopping_cart_outlined,
            size: 18,
            color: AppConstants.errorRed,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.buyerCartBlockedBanner(_issues.length),
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppConstants.errorRed,
              ),
            ),
          ),
          TextButton(
            onPressed: _removeBlocked,
            child: Text(
              l10n.buyerCartRemoveBlocked,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppConstants.errorRed,
              ),
            ),
          ),
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
            Icon(
              Icons.shopping_cart_outlined,
              size: 56,
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.buyerCartEmptyTitle,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.buyerCartEmptyBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: l10n.browseMarketplace,
              onPressed: () => context.pop(),
            ),
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
        border: Border(
          top: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.10),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
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
                      child: Text(
                        l10n.buyerCartSelectAll,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
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
                  side: BorderSide(
                    color: _selectedIds.isEmpty
                        ? Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.3)
                        : AppConstants.errorRed,
                  ),
                  // The app-wide OutlinedButtonThemeData forces minimumSize
                  // to Size(double.infinity, 52) — fine when this button is
                  // the sole child of a full-width SizedBox, but here it's a
                  // plain Row child, so that infinite width has to be
                  // overridden or layout crashes with "BoxConstraints forces
                  // an infinite width".
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: Text(l10n.buyerCartDelete),
              )
            else ...[
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    l10n.buyerCartTotalLabel,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '₱${_selectedTotal.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
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
  // Why this line cannot be purchased (null when it can), and whether its
  // checkbox may be used (always in Edit Mode, so it can still be deleted).
  final String? issueText;
  final bool selectable;
  final VoidCallback onToggleSelect;
  // The quantity is typed or stepped (see QuantityStepper); it is reported as
  // it changes, and a change can be refused (offline).
  final ValueChanged<double> onQuantityChanged;
  final bool Function() allowQuantityChange;
  final VoidCallback onQuantityBlocked;
  final VoidCallback onRemove;

  const _CartItemTile({
    required this.item,
    required this.selected,
    required this.swipeToDeleteEnabled,
    required this.issueText,
    required this.selectable,
    required this.onToggleSelect,
    required this.onQuantityChanged,
    required this.allowQuantityChange,
    required this.onQuantityBlocked,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.listingId),
      direction: swipeToDeleteEnabled
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppConstants.errorRed,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onRemove(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: selected
              ? Border.all(color: AppConstants.primaryGreen, width: 1.5)
              : AppConstants.cardBorder,
          boxShadow: AppConstants.cardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: selected,
              activeColor: AppConstants.primaryGreen,
              onChanged: selectable ? (_) => onToggleSelect() : null,
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              child: item.photoUrl != null
                  ? Image.network(
                      item.photoUrl!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      color: AppConstants.limeGreen,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.displayName,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '₱${item.subtotal.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    formatPricePerUnit(item.pricePerKg, item.unit),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (issueText != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      issueText!,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.errorRed,
                      ),
                    ),
                  ],
                  if (item.isCooperative) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _CartTag(AppLocalizations.of(context).cpSourceLabel),
                        if (item.programName != null)
                          _CartTag(item.programName!),
                      ],
                    ),
                  ] else if (item.category != null ||
                      item.marketType != null) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (item.category != null) _CartTag(item.category!),
                        if (item.marketType != null)
                          _CartTag(marketTypeLabelFor(item.marketType)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Editable: type a quantity or use - / +. A line that
                      // cannot be bought (issueText) is locked.
                      QuantityStepper(
                        key: ValueKey('qty-${item.listingId}'),
                        compact: true,
                        value: item.quantityKg,
                        max: item.availableKgSnapshot,
                        enabled: issueText == null,
                        allowChange: allowQuantityChange,
                        onBlocked: onQuantityBlocked,
                        onChanged: onQuantityChanged,
                      ),
                      const SizedBox(width: 8),
                      // This product's own unit (kg, sack, pack, piece, ...).
                      Flexible(
                        child: Text(
                          unitOrDefault(item.unit),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
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
        color: context
            .adaptiveSurface(AppConstants.infoBlueBg)
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
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
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppConstants.warningAmber,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.buyerCartNoSelectionTitle,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.buyerCartNoSelectionBody,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: l10n.buyerCartNoSelectionOk,
                onPressed: () => Navigator.pop(context),
              ),
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
                const Icon(
                  Icons.info_rounded,
                  color: AppConstants.warningAmber,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.buyerCartStockChangedTitle,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.buyerCartStockChangedBody,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: messages
                      .map(
                        (m) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '• $m',
                            style: GoogleFonts.inter(fontSize: 13, height: 1.4),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: l10n.buyerCartReviewCart,
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the lines picked for checkout include ones that can no longer be
/// bought. Same look as the stock-changed dialog, with its own wording.
class _CartBlockedDialog extends StatelessWidget {
  final List<String> messages;
  const _CartBlockedDialog({required this.messages});

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
                const Icon(
                  Icons.remove_shopping_cart_outlined,
                  color: AppConstants.errorRed,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.buyerCartCannotCheckoutTitle,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.buyerCartCannotCheckoutBody,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: messages
                      .map(
                        (m) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '• $m',
                            style: GoogleFonts.inter(fontSize: 13, height: 1.4),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: l10n.buyerCartReviewCart,
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
