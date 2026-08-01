import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/cart_item_model.dart';
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/services/cart_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _cartService = CartService();
  final _marketRepo = BuyerMarketplaceRepository();

  bool _isLoading = true;
  bool _isCheckingOut = false;
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

  Future<void> _updateQuantity(CartItemModel item, int delta) async {
    final newQty = (item.quantityKg + delta).clamp(1.0, item.availableKgSnapshot);
    await _cartService.updateQuantity(item.listingId, newQty);
    _load();
  }

  Future<void> _removeItem(CartItemModel item) async {
    await _cartService.removeItem(item.listingId);
    _load();
  }

  Future<void> _checkout() async {
    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: _CartCheckoutDialog(items: _items, total: _grandTotal),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isCheckingOut = true);

    final succeeded = <CartItemModel>[];
    final failed = <(CartItemModel, String)>[];

    // Reused entirely — same atomic RPC every single-item order already
    // uses. No new order workflow, no new RPC.
    for (final item in _items) {
      try {
        await _marketRepo.placeOrder(listingId: item.listingId, quantityKg: item.quantityKg);
        succeeded.add(item);
        await _cartService.removeItem(item.listingId);
      } catch (e) {
        failed.add((item, e.toString().replaceFirst('Exception: ', '')));
      }
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
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        leading: BackButton(onPressed: () => context.pop(), color: AppConstants.primaryGreen),
        title: Text('My Cart',
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _buildEmptyState()
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
                    _buildCheckoutBar(),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 56, color: AppConstants.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('Your cart is empty', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Add produce from the marketplace to start a multi-item order.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 16),
            PrimaryButton(label: 'Browse Marketplace', onPressed: () => context.pop()),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_items.length} item${_items.length > 1 ? 's' : ''}',
                  style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
              Text('₱${_grandTotal.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(label: 'Proceed to Checkout', isLoading: _isCheckingOut, onPressed: _checkout),
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
          color: Colors.white,
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
                      _stepperBtn(Icons.remove, item.quantityKg > 1 ? onDecrement : null),
                      SizedBox(
                        width: 40,
                        child: Text('${item.quantityKg.toStringAsFixed(0)}',
                            textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                      _stepperBtn(Icons.add, item.quantityKg < item.availableKgSnapshot ? onIncrement : null),
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

  Widget _stepperBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: onTap == null ? AppConstants.outline.withValues(alpha: 0.1) : AppConstants.offWhite,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: onTap == null ? AppConstants.outline : AppConstants.primaryGreen),
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
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxHeight: 480),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confirm Order', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800)),
            Text('${items.length} item${items.length > 1 ? 's' : ''} from ${AppConstants.cooperativeName}',
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
                        Expanded(child: Text('${item.displayName} × ${item.quantityKg.toStringAsFixed(0)}kg', style: GoogleFonts.inter(fontSize: 12))),
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
                Text('Total', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                Text('₱${total.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
              ],
            ),
            const SizedBox(height: 6),
            Text('Pickup at ${AppConstants.cooperativeLocation}. No delivery — you must arrange transport.',
                style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(child: PrimaryButton(label: 'Confirm', height: 44, onPressed: () => Navigator.pop(context, true))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
