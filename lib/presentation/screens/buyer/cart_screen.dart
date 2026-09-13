import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/cart_item_model.dart';
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/cart_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

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
  int _checkoutIndex = 0;
  int _checkoutTotal = 0;
  List<CartItemModel> _items = [];

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
      _isLoading = false;
    });
  }

  double get _grandTotal => _items.fold(0.0, (sum, i) => sum + i.subtotal);

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
    _load();
  }

  // Phase 8, item 1: fetchCurrentRemainingKg() has existed since an
  // earlier backend-only pass (Buyer review finding 2.4), but nothing
  // called it until now. place_order()'s own server-side FOR UPDATE check
  // was always the real authority and still fully protects against
  // overselling without this step — this exists purely so the buyer sees
  // an accurate number up front instead of only discovering drift via a
  // checkout-time failure.
  Future<void> _checkout() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _isCheckingOut = true);

    final liveStock = await _marketRepo.fetchCurrentRemainingKg(
      _items.map((i) => i.listingId).toList(),
    );

    final adjustments = <String>[];
    for (final item in List<CartItemModel>.from(_items)) {
      final live = liveStock[item.listingId] ?? 0.0;
      if (live <= 0) {
        await _cartService.removeItem(item.listingId);
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

    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: _CartCheckoutDialog(items: _items, total: _grandTotal),
    );
    if (confirmed != true || !mounted) {
      setState(() => _isCheckingOut = false);
      return;
    }

    final succeeded = <CartItemModel>[];
    final failed = <(CartItemModel, String)>[];
    setState(() => _checkoutTotal = _items.length);

    // Reused entirely — same atomic RPC every single-item order already
    // uses. No new order workflow, no new RPC.
    for (final item in _items) {
      setState(() => _checkoutIndex = succeeded.length + failed.length + 1);
      try {
        await _marketRepo.placeOrder(listingId: item.listingId, quantityKg: item.quantityKg);
        succeeded.add(item);
        await _cartService.removeItem(item.listingId);
      } catch (e) {
        failed.add((item, e.toString().replaceFirst('Exception: ', '')));
      }
    }

    if (succeeded.isNotEmpty) {
      AppEventService.instance.notifyOrderPlaced();
    }

    if (!mounted) return;
    setState(() => _isCheckingOut = false);

    context.pushReplacement(AppRoutes.cartCheckoutResult, extra: {
      'succeeded': succeeded,
      'failed': failed,
    });
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
        title: Text(l10n.buyerCartTitle,
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
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
                          onIncrement: () => _updateQuantity(_items[i], 1),
                          onDecrement: () => _updateQuantity(_items[i], -1),
                          onRemove: () => _removeItem(_items[i]),
                        ),
                      ),
                    ),
                    _buildCheckoutBar(l10n),
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

  Widget _buildCheckoutBar(AppLocalizations l10n) {
    // Phase 8, item 3: checkout is still sequential, isolated per-item
    // place_order() calls (deliberately kept — Phase 5, item 3 — safer
    // error isolation than a batched call). This only makes that existing
    // sequence visible instead of a single opaque button spinner, for a
    // large cart on a slow connection.
    final showingProgress = _isCheckingOut && _checkoutTotal > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showingProgress) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.buyerCartPlacingOrder(_checkoutIndex, _checkoutTotal),
                    style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              child: LinearProgressIndicator(
                value: _checkoutIndex / _checkoutTotal,
                minHeight: 6,
                backgroundColor: AppConstants.outline.withValues(alpha: 0.15),
                color: AppConstants.primaryGreen,
              ),
            ),
            const SizedBox(height: 14),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.buyerCartItemCount(_items.length),
                    style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
                Text('₱${_grandTotal.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
              ],
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(label: l10n.buyerCartProceedCheckout, isLoading: _isCheckingOut, onPressed: _isCheckingOut ? null : _checkout),
          ),
        ],
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItemModel item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  const _CartItemTile({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.listingId),
      direction: DismissDirection.endToStart,
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
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
        decoration: BoxDecoration(color: context.saganaColors.cardBackground, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
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

class _CartCheckoutDialog extends StatelessWidget {
  final List<CartItemModel> items;
  final double total;
  const _CartCheckoutDialog({required this.items, required this.total});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxHeight: 480),
        decoration: BoxDecoration(color: context.saganaColors.cardBackground, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.buyerCartConfirmOrderTitle, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(l10n.buyerCartItemsFrom(items.length, AppConstants.cooperativeName),
                style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('${item.displayName} × ${_fmtCartQty(item.quantityKg)}kg', style: GoogleFonts.inter(fontSize: 12))),
                        Text('₱${item.subtotal.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.buyerCartTotalLabel, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                Text('₱${total.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
              ],
            ),
            const SizedBox(height: 6),
            Text(l10n.buyerCartPickupNotice(AppConstants.cooperativeLocation),
                style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel))),
                const SizedBox(width: 12),
                Expanded(child: PrimaryButton(label: l10n.buyerCartConfirm, height: 44, onPressed: () => Navigator.pop(context, true))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}