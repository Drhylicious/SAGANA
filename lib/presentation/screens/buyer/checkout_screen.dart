import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_address_model.dart';
import '../../../data/models/cart_item_model.dart';
import '../../../data/models/farmer_crop_model.dart' show marketTypeLabelFor;
import '../../../data/repositories/buyer_address_repository.dart';
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/cart_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/fulfillment_info_card.dart';
import '../../widgets/shared_widgets.dart';

enum _FulfillmentMethod { pickup, delivery }

/// Shared Checkout — serves both the Buy Now sheet (single item) and Cart
/// (N items) entry points, converging on CartItemModel so neither call
/// site needs its own copy of this screen. Fulfillment (Pickup/Delivery +
/// saved address) is captured here, once, atomically with order creation
/// — replacing the old post-approval "choose fulfillment later" flow.
class CheckoutScreen extends StatefulWidget {
  final List<CartItemModel> items;
  // false: Buy Now (exactly 1 item, 1 placeOrder call, → Order Success).
  // true: Cart (N items, 1 placeOrder call per item, → Cart Checkout
  // Result), same per-item try/catch isolation cart_screen.dart's own
  // checkout loop already used.
  final bool isCartCheckout;
  final bool isFarmerContext;

  const CheckoutScreen({
    super.key,
    required this.items,
    required this.isCartCheckout,
    this.isFarmerContext = false,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _marketRepo = BuyerMarketplaceRepository();
  final _addressRepo = BuyerAddressRepository();
  final _cartService = CartService();

  _FulfillmentMethod _method = _FulfillmentMethod.pickup;
  List<BuyerAddressModel> _addresses = [];
  BuyerAddressModel? _selectedAddress;
  bool _isLoadingAddresses = true;
  bool _isSubmitting = false;
  int _checkoutIndex = 0;
  String? _error;

  double get _total => widget.items.fold(0.0, (s, i) => s + i.subtotal);

  String get _orderSuccessRoute =>
      widget.isFarmerContext ? AppRoutes.farmerMarketplaceOrderSuccess : AppRoutes.orderSuccess;
  String get _cartCheckoutResultRoute =>
      widget.isFarmerContext ? AppRoutes.farmerMarketplaceCartResult : AppRoutes.cartCheckoutResult;

  bool get _canPlaceOrder =>
      !_isSubmitting && (_method == _FulfillmentMethod.pickup || _selectedAddress != null);

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    final addresses = await _addressRepo.fetchAddresses();
    if (!mounted) return;
    setState(() {
      _addresses = addresses;
      _selectedAddress = addresses.isEmpty
          ? null
          : addresses.firstWhere((a) => a.isDefault, orElse: () => addresses.first);
      _isLoadingAddresses = false;
    });
  }

  Future<void> _addNewAddress() async {
    final saved = await context.push<bool>(AppRoutes.addEditAddress);
    if (saved == true) _loadAddresses();
  }

  Future<void> _placeOrder() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
      _checkoutIndex = 0;
    });

    final method = _method == _FulfillmentMethod.pickup ? 'pickup' : 'delivery';
    final address = _method == _FulfillmentMethod.delivery ? _selectedAddress : null;

    if (!widget.isCartCheckout) {
      final item = widget.items.single;
      try {
        final orderId = await _marketRepo.placeOrder(
          listingId: item.listingId,
          quantityKg: item.quantityKg,
          fulfillmentMethod: method,
          deliveryAddress: address?.addressLine,
          deliveryLatitude: address?.latitude,
          deliveryLongitude: address?.longitude,
          deliveryContactNumber: address?.contactNumber,
          deliveryNotes: address?.notes,
          deliveryRecipientName: address?.recipientName,
          deliveryLabel: address?.label,
        );
        AppEventService.instance.notifyOrderPlaced();
        if (!mounted) return;
        context.pushReplacement(_orderSuccessRoute, extra: [orderId]);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }

    // Cart checkout — same per-item try/catch isolation as
    // cart_screen.dart's own checkout loop: one failing item never aborts
    // the rest, and every item shares this one fulfillment choice.
    final succeeded = <(CartItemModel, String)>[];
    final failed = <(CartItemModel, String)>[];
    for (final item in widget.items) {
      setState(() => _checkoutIndex = succeeded.length + failed.length + 1);
      try {
        final orderId = await _marketRepo.placeOrder(
          listingId: item.listingId,
          quantityKg: item.quantityKg,
          fulfillmentMethod: method,
          deliveryAddress: address?.addressLine,
          deliveryLatitude: address?.latitude,
          deliveryLongitude: address?.longitude,
          deliveryContactNumber: address?.contactNumber,
          deliveryNotes: address?.notes,
          deliveryRecipientName: address?.recipientName,
          deliveryLabel: address?.label,
        );
        succeeded.add((item, orderId));
        await _cartService.removeItem(item.listingId);
      } catch (e) {
        failed.add((item, e.toString().replaceFirst('Exception: ', '')));
      }
    }

    if (succeeded.isNotEmpty) {
      AppEventService.instance.notifyOrderPlaced();
    }
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (failed.isEmpty) {
      // Everything succeeded — this is the exact same "orders placed"
      // outcome as Buy Now, so it goes to the exact same screen instead
      // of a second implementation of "success."  CartCheckoutResultScreen
      // is reserved for the one genuinely different message: some items
      // didn't go through.
      context.pushReplacement(_orderSuccessRoute, extra: succeeded.map((s) => s.$2).toList());
      return;
    }
    context.pushReplacement(_cartCheckoutResultRoute, extra: {
      'succeeded': succeeded,
      'failed': failed,
      'fulfillmentMethod': method,
      'deliveryAddress': address?.addressLine,
      'deliveryContactNumber': address?.contactNumber,
      'deliveryRecipientName': address?.recipientName,
      'deliveryLabel': address?.label,
      'deliveryNotes': address?.notes,
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
        leading: const BackButton(color: AppConstants.primaryGreen),
        title: Text(l10n.checkoutTitle,
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 12, AppConstants.spacingSafeH, 24),
        children: [
          _sectionHeader(Icons.local_shipping_outlined, l10n.checkoutFulfillmentSectionTitle),
          const SizedBox(height: 12),
          _buildFulfillmentSelector(l10n),
          const SizedBox(height: 14),
          if (_method == _FulfillmentMethod.pickup)
            _buildPickupCard(l10n)
          else
            _buildDeliveryCard(l10n),
          const SizedBox(height: 18),
          _sectionHeader(Icons.shopping_bag_outlined, l10n.checkoutOrderSummary),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: sagana.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: AppConstants.cardBorder,
              boxShadow: AppConstants.cardShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < widget.items.length; i++) ...[
                  _buildItemRow(widget.items[i]),
                  if (i < widget.items.length - 1)
                    Divider(height: 1, indent: 14, endIndent: 14, color: AppConstants.outline.withValues(alpha: 0.08)),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  decoration: BoxDecoration(color: sagana.scaffoldBackground.withValues(alpha: 0.6)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.checkoutSubtotalLabel(widget.items.length),
                          style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
                      Text('₱${_total.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.onSurface)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildAdditionalInfoCard(l10n),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConstants.errorRed.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: AppConstants.errorRed.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 16, color: AppConstants.errorRed),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed))),
                ],
              ),
            ),
          ],
          // Space for the sticky Total/Place Order bar below.
          const SizedBox(height: 12),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 96),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 12, AppConstants.spacingSafeH, 12),
            decoration: BoxDecoration(
              color: sagana.cardBackground,
              border: Border(top: BorderSide(color: AppConstants.outline.withValues(alpha: 0.10))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.checkoutTotal, style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                      Text('₱${_total.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 130, maxWidth: 190),
                  child: PrimaryButton(
                    label: widget.isCartCheckout && _isSubmitting
                        ? l10n.checkoutPlacingOrders(_checkoutIndex, widget.items.length)
                        : l10n.checkoutPlaceOrder,
                    isLoading: _isSubmitting,
                    onPressed: _canPlaceOrder ? _placeOrder : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppConstants.primaryGreen),
        const SizedBox(width: 6),
        Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildFulfillmentSelector(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: _MethodChip(
            label: l10n.checkoutFulfillmentPickup,
            icon: Icons.storefront_rounded,
            selected: _method == _FulfillmentMethod.pickup,
            onTap: () => setState(() => _method = _FulfillmentMethod.pickup),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MethodChip(
            label: l10n.checkoutFulfillmentDelivery,
            icon: Icons.local_shipping_outlined,
            selected: _method == _FulfillmentMethod.delivery,
            onTap: () => setState(() => _method = _FulfillmentMethod.delivery),
          ),
        ),
      ],
    );
  }

  Widget _buildPickupCard(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: AppConstants.cardBorder,
        boxShadow: AppConstants.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44, height: 44,
            decoration: const BoxDecoration(color: AppConstants.primaryGreen, shape: BoxShape.circle),
            child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.checkoutPickupAt, style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(AppConstants.cooperativeName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(AppConstants.cooperativeLocation,
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryCard(AppLocalizations l10n) {
    if (_isLoadingAddresses) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_addresses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppConstants.warningAmber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: AppConstants.warningAmber.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: AppConstants.warningAmber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.checkoutNoAddressesPrompt,
                      style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addNewAddress,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.buyerAddressesAddNew),
              ),
            ),
          ],
        ),
      );
    }
    // Same shared card Order Detail/Success/Admin use to show a delivery's
    // fulfillment info — reused here (tappable, via onTap) instead of a
    // second hand-built layout, so the selected-address summary at
    // Checkout and its read-only display everywhere afterward are
    // pixel-for-pixel the same structure.
    final address = _selectedAddress!;
    return FulfillmentInfoCard(
      fulfillmentMethod: 'delivery',
      deliveryAddress: address.addressLine,
      deliveryContactNumber: address.contactNumber,
      deliveryRecipientName: address.recipientName,
      deliveryLabel: address.label,
      deliveryNotes: address.notes,
      onTap: () => _openAddressPicker(l10n),
    );
  }

  Future<void> _openAddressPicker(AppLocalizations l10n) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: context.saganaColors.cardBackground,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppConstants.radiusLg)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: AppConstants.outline.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(l10n.checkoutSelectAddressSheetTitle,
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        for (final address in _addresses)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AddressOptionTile(
                              address: address,
                              selected: _selectedAddress?.id == address.id,
                              onTap: () {
                                setState(() => _selectedAddress = address);
                                Navigator.of(sheetContext).pop();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _addNewAddress();
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(l10n.buyerAddressesAddNew),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAdditionalInfoCard(AppLocalizations l10n) {
    final totalQty = widget.items.fold<double>(0, (s, i) => s + i.quantityKg);
    final qtyLabel = totalQty == totalQty.roundToDouble() ? totalQty.toStringAsFixed(0) : totalQty.toStringAsFixed(2);
    final notes = _method == _FulfillmentMethod.delivery ? _selectedAddress?.notes : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: AppConstants.cardBorder,
        boxShadow: AppConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.checkoutAdditionalInfoTitle,
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.onSurfaceVariant)),
          const SizedBox(height: 12),
          _infoRow(Icons.inventory_2_outlined, l10n.checkoutItemsSummary(widget.items.length, qtyLabel)),
          const SizedBox(height: 10),
          _infoRow(
            _method == _FulfillmentMethod.pickup ? Icons.storefront_rounded : Icons.local_shipping_outlined,
            '${l10n.checkoutFulfillmentMethodLabel}: '
            '${_method == _FulfillmentMethod.pickup ? l10n.checkoutFulfillmentPickup : l10n.checkoutFulfillmentDelivery}',
          ),
          if (notes != null && notes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoRow(Icons.note_outlined, '${l10n.checkoutNotesLabel}: $notes'),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: AppConstants.outline.withValues(alpha: 0.1)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 15, color: AppConstants.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.checkoutReviewNote,
                    style: GoogleFonts.inter(fontSize: 11.5, color: AppConstants.onSurfaceVariant)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppConstants.primaryGreen),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 12.5, color: AppConstants.onSurface))),
      ],
    );
  }

  Widget _buildItemRow(CartItemModel item) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: SizedBox(
              width: 56, height: 56,
              child: item.photoUrl != null
                  ? Image.network(item.photoUrl!, fit: BoxFit.cover)
                  : Container(color: AppConstants.limeGreen),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.displayName, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppConstants.infoBlueBg.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  ),
                  child: Text(marketTypeLabelFor(item.marketType),
                      style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppConstants.infoBlueFg)),
                ),
                const SizedBox(height: 4),
                Text('${item.quantityKg.toStringAsFixed(item.quantityKg == item.quantityKg.roundToDouble() ? 0 : 2)} kg × ₱${item.pricePerKg.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
              ],
            ),
          ),
          Text('₱${item.subtotal.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
        ],
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _MethodChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppConstants.primaryGreen : context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: selected ? AppConstants.primaryGreen : AppConstants.outline.withValues(alpha: 0.2)),
          boxShadow: selected
              ? [BoxShadow(color: AppConstants.primaryGreen.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))]
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? Colors.white : AppConstants.primaryGreen, size: 22),
            const SizedBox(height: 6),
            Text(label,
                style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppConstants.primaryGreen,
                )),
          ],
        ),
      ),
    );
  }
}

// Full address option row, shown inside the picker sheet
// _CheckoutScreenState._openAddressPicker opens once a delivery address has
// already been selected — same radio/label-chip/detail layout the inline
// list used before it collapsed into the compact summary card.
class _AddressOptionTile extends StatelessWidget {
  final BuyerAddressModel address;
  final bool selected;
  final VoidCallback onTap;

  const _AddressOptionTile({required this.address, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppConstants.primaryGreen.withValues(alpha: 0.06) : context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: selected ? AppConstants.primaryGreen : AppConstants.outline.withValues(alpha: 0.15),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: AppConstants.primaryGreen,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    child: Text(address.label,
                        style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                  ),
                  const SizedBox(height: 6),
                  Text(address.recipientName ?? '',
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(address.addressLine, style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
                  if (address.contactNumber != null) ...[
                    const SizedBox(height: 2),
                    Text(address.contactNumber!, style: GoogleFonts.inter(fontSize: 11.5, color: AppConstants.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
