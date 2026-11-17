import 'package:flutter/material.dart';
import '../../../data/services/connectivity_service.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_address_model.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../core/utils/client_id.dart';
import '../../../core/utils/order_reference.dart';
import '../../../data/models/cart_item_model.dart';
import '../../../data/models/cooperative_delivery_model.dart';
import '../../../data/repositories/cooperative_delivery_repository.dart';
import '../../../data/repositories/cooperative_order_repository.dart';
import '../../../data/models/farmer_crop_model.dart' show marketTypeLabelFor;
import '../../../data/repositories/buyer_address_repository.dart';
import '../../../data/repositories/buyer_marketplace_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../../data/services/cooperative_address_service.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/cart_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/fulfillment_info_card.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/feature_restriction_notice.dart';
import '../../../data/models/member_restriction.dart';

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

  // The data layer, replaceable in tests. In the app every one of these is left out.
  @visibleForTesting
  final BuyerMarketplaceRepository? marketRepo;
  @visibleForTesting
  final BuyerAddressRepository? addressRepo;
  @visibleForTesting
  final CooperativeDeliveryRepository? deliveryRepo;
  @visibleForTesting
  final CooperativeOrderRepository? coopRepo;
  @visibleForTesting
  final CartService? cartService;

  const CheckoutScreen({
    super.key,
    required this.items,
    required this.isCartCheckout,
    this.isFarmerContext = false,
    this.marketRepo,
    this.addressRepo,
    this.deliveryRepo,
    this.coopRepo,
    this.cartService,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late final _marketRepo = widget.marketRepo ?? BuyerMarketplaceRepository();
  late final _addressRepo = widget.addressRepo ?? BuyerAddressRepository();
  late final _cartService = widget.cartService ?? CartService();
  late final _deliveryRepo =
      widget.deliveryRepo ?? CooperativeDeliveryRepository();
  late final _coopRepo = widget.coopRepo ?? CooperativeOrderRepository();

  // The delivery rules (distance-based fee, Barangay Payanas only). Off until the Manager has
  // set everything up and switched them on: then Delivery behaves as it always did for a
  // Marketplace-only checkout, and is not offered for Cooperative Products.
  DeliveryStatus _delivery = DeliveryStatus.off;
  CooperativeDetails? _coopDetails;
  DeliveryQuote? _quote;
  DeliveryRefusal? _quoteProblem;
  bool _quoting = false;
  // One delivery group per checkout: a retry sends the same id and gets the same group.
  final String _groupRequestId = newClientId();

  _FulfillmentMethod _method = _FulfillmentMethod.pickup;
  List<BuyerAddressModel> _addresses = [];
  BuyerAddressModel? _selectedAddress;
  bool _isLoadingAddresses = true;
  bool _isOnline = ConnectivityService.instance.isOnline;
  bool _isSubmitting = false;
  int _checkoutIndex = 0;
  String? _error;

  double get _total => widget.items.fold(0.0, (s, i) => s + i.subtotal);

  bool get _rulesOn => _delivery.enabled;

  /// Delivery is offered only while the Manager has it switched ON (and set up): for everyone,
  /// Marketplace orders and Cooperative Products alike. The database refuses a Delivery order
  /// otherwise.
  bool get _deliveryAvailable => _rulesOn;

  /// Pickup is offered unless the Manager has switched it off.
  bool get _pickupAvailable => _delivery.pickupEnabled;

  bool get _usesFee => _method == _FulfillmentMethod.delivery && _rulesOn;

  /// The one delivery fee of this checkout (not per item), added to the total.
  double get _deliveryFee => _usesFee ? (_quote?.fee ?? 0) : 0;
  double get _grandTotal => _total + _deliveryFee;

  String get _orderSuccessRoute => widget.isFarmerContext
      ? AppRoutes.farmerMarketplaceOrderSuccess
      : AppRoutes.orderSuccess;
  String get _cartCheckoutResultRoute => widget.isFarmerContext
      ? AppRoutes.farmerMarketplaceCartResult
      : AppRoutes.cartCheckoutResult;

  bool get _canPlaceOrder =>
      !_isSubmitting &&
      ((_method == _FulfillmentMethod.pickup && _pickupAvailable) ||
          (_method == _FulfillmentMethod.delivery &&
              _selectedAddress != null &&
              _deliveryAvailable &&
              (!_rulesOn || (_quote != null && !_quoting))));

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadAddresses();
    _loadDelivery();
  }

  Future<void> _loadDelivery() async {
    final status = await _deliveryRepo.fetchDeliveryStatus();
    CooperativeDetails? details;
    try {
      details = await _deliveryRepo.fetchDetails();
      CooperativeAddressService.instance.remember(details);
    } catch (_) {
      // The last good copy (if this device has read it before) keeps the address on screen.
      details = CooperativeAddressService.instance.cached;
    }
    if (!mounted) return;
    setState(() {
      _delivery = status;
      _coopDetails = details;
      // A method that cannot be used is never left selected.
      if (!_deliveryAvailable && _pickupAvailable) {
        _method = _FulfillmentMethod.pickup;
      }
      if (!_pickupAvailable && _deliveryAvailable) {
        _method = _FulfillmentMethod.delivery;
      }
    });
    _refreshQuote();
  }

  /// With the delivery rules on, asks the database what delivery to the chosen saved address
  /// costs (and whether it is allowed at all). Nothing is charged here.
  Future<void> _refreshQuote() async {
    final address = _selectedAddress;
    if (!_usesFee || address == null) {
      if (_quote != null || _quoteProblem != null) {
        setState(() {
          _quote = null;
          _quoteProblem = null;
        });
      }
      return;
    }
    setState(() {
      _quoting = true;
      _quote = null;
      _quoteProblem = null;
    });
    try {
      final q = await _deliveryRepo.fetchQuote(address.id);
      if (!mounted || _selectedAddress?.id != address.id) return;
      setState(() {
        _quote = q;
        _quoting = false;
      });
    } catch (e) {
      if (!mounted || _selectedAddress?.id != address.id) return;
      setState(() {
        _quoteProblem = deliveryRefusalOf(e);
        _quoting = false;
      });
    }
  }

  /// A sentence for a failed order: a database refusal in the person's own language, else the
  /// message as it came.
  String _errorText(Object e) {
    final l10n = AppLocalizations.of(context);
    if (e is PostgrestException) return friendlyError(l10n, e);
    final raw = e.toString().replaceFirst('Exception: ', '');
    return messageForDatabaseText(l10n, raw) ?? raw;
  }

  Future<void> _loadAddresses() async {
    final addresses = await _addressRepo.fetchAddresses();
    if (!mounted) return;
    setState(() {
      _addresses = addresses;
      _selectedAddress = addresses.isEmpty
          ? null
          : addresses.firstWhere(
              (a) => a.isDefault,
              orElse: () => addresses.first,
            );
      _isLoadingAddresses = false;
    });
    _refreshQuote();
  }

  Future<void> _addNewAddress() async {
    final saved = await context.push<bool>(AppRoutes.addEditAddress);
    if (saved == true) _loadAddresses();
  }

  Future<void> _placeOrder() async {
    // A second tap before the first order returns would place the order twice
    // (place_order takes the kg off the listing each time it runs), so the
    // second tap is ignored rather than relying on the button having rebuilt.
    if (_isSubmitting) return;
    // The flag goes up first, so a second tap during the restriction check below is
    // ignored too.
    setState(() {
      _isSubmitting = true;
      _error = null;
      _checkoutIndex = 0;
    });
    // The last stop before an order exists: a restriction applied while this screen
    // was open is respected here too (the database refuses it as well).
    final allowed = await ensureFeatureAvailable(
      context,
      RestrictableFeature.checkout,
    );
    if (!allowed || !mounted) {
      if (mounted) setState(() => _isSubmitting = false);
      return;
    }

    final method = _method == _FulfillmentMethod.pickup ? 'pickup' : 'delivery';
    final address = _method == _FulfillmentMethod.delivery
        ? _selectedAddress
        : null;

    // Delivery with the rules on: ONE delivery group for the whole checkout (Buy Now and the
    // cart alike). The database takes the address, the distance and the single fee from it.
    String? groupId;
    if (_usesFee && address != null) {
      try {
        groupId = (await _deliveryRepo.createCheckoutGroup(
          addressId: address.id,
          requestId: _groupRequestId,
        )).groupId;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          _error = _errorText(e);
        });
        return;
      }
    }

    if (!widget.isCartCheckout) {
      final item = widget.items.single;
      try {
        final orderId = await _placeLine(item, method, address, groupId);
        AppEventService.instance.notifyOrderPlaced();
        if (!mounted) return;
        context.pushReplacement(_orderSuccessRoute, extra: [orderId]);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          _error = _errorText(e);
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
        final orderId = await _placeLine(item, method, address, groupId);
        succeeded.add((item, orderId));
        await _cartService.removeItem(item.listingId);
      } catch (e) {
        failed.add((item, _errorText(e)));
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
      context.pushReplacement(
        _orderSuccessRoute,
        extra: succeeded.map((s) => s.$2).toList(),
      );
      return;
    }
    context.pushReplacement(
      _cartCheckoutResultRoute,
      extra: {
        'succeeded': succeeded,
        'failed': failed,
        'fulfillmentMethod': method,
        'deliveryAddress': address?.addressLine,
        'deliveryContactNumber': address?.contactNumber,
        'deliveryRecipientName': address?.recipientName,
        'deliveryLabel': address?.label,
        'deliveryNotes': address?.notes,
      },
    );
  }

  /// Places one line through its own source: a Marketplace listing through place_order, a
  /// Cooperative Product through place_program_order. The line keeps one request id, so a retry
  /// returns the order that already exists instead of placing it again. Returns the id the
  /// success screens use (a Cooperative order carries a prefix).
  Future<String> _placeLine(
    CartItemModel item,
    String method,
    BuyerAddressModel? address,
    String? groupId,
  ) async {
    if (item.isCooperative) {
      final placed = await _coopRepo.placeOrder(
        programId: item.programId!,
        productId: item.listingId,
        quantity: roundQuantity(item.quantityKg),
        fulfillmentMethod: method,
        requestId: item.requestId,
        groupId: groupId,
      );
      return programOrderToken(placed.orderId);
    }
    return _marketRepo.placeOrder(
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
      requestId: item.requestId,
      groupId: groupId,
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
            title: l10n.checkoutTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          CachedDataNotice(
            screen: 'buyer_addresses',
            isOnline: _isOnline,
            offlineMessage: l10n.offlineBuyerBody,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingSafeH,
                12,
                AppConstants.spacingSafeH,
                24,
              ),
              children: [
                _sectionHeader(
                  Icons.local_shipping_outlined,
                  l10n.checkoutFulfillmentSectionTitle,
                ),
                const SizedBox(height: 12),
                _buildFulfillmentSelector(l10n),
                const SizedBox(height: 14),
                if (!_deliveryAvailable) ...[
                  _buildNote(
                    l10n.uoCheckoutDeliveryOff,
                    key: const Key('deliveryOffNote'),
                  ),
                  const SizedBox(height: 10),
                ],
                if (!_pickupAvailable) ...[
                  _buildNote(
                    l10n.uoCheckoutPickupOff,
                    key: const Key('pickupOffNote'),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_method == _FulfillmentMethod.pickup)
                  _buildPickupCard(l10n)
                else ...[
                  _buildDeliveryCard(l10n),
                  if (_usesFee && _selectedAddress != null) ...[
                    const SizedBox(height: 10),
                    _buildQuoteCard(l10n),
                  ],
                ],
                const SizedBox(height: 18),
                _sectionHeader(
                  Icons.shopping_bag_outlined,
                  l10n.checkoutOrderSummary,
                ),
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
                          Divider(
                            height: 1,
                            indent: 14,
                            endIndent: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.08),
                          ),
                      ],
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                        decoration: BoxDecoration(
                          color: sagana.scaffoldBackground.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(
                              l10n.checkoutSubtotalLabel(widget.items.length),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            )),
                            Text(
                              '₱${_total.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_usesFee && _quote != null)
                        Container(
                          key: const Key('deliveryFeeRow'),
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          color: sagana.scaffoldBackground.withValues(
                            alpha: 0.6,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(child: Text(
                                l10n.uoPaymentDeliveryFee,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              )),
                              Text(
                                '₱${_quote!.fee.toStringAsFixed(2)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
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
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                      border: Border.all(
                        color: AppConstants.errorRed.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 16,
                          color: AppConstants.errorRed,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppConstants.errorRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Space for the sticky Total/Place Order bar below.
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: ConstrainedBox(
          // Grows with the text size, so enlarged text is not cut off.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.textScalerOf(context).scale(96),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingSafeH,
              12,
              AppConstants.spacingSafeH,
              12,
            ),
            decoration: BoxDecoration(
              color: sagana.cardBackground,
              border: Border(
                top: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.10),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.checkoutTotal,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      // A large total (items plus the delivery fee) shrinks to fit instead of wrapping.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '₱${_grandTotal.toStringAsFixed(2)}',
                          key: const Key('grandTotal'),
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 130,
                    maxWidth: 190,
                  ),
                  child: PrimaryButton(
                    label: widget.isCartCheckout && _isSubmitting
                        ? l10n.checkoutPlacingOrders(
                            _checkoutIndex,
                            widget.items.length,
                          )
                        : l10n.checkoutPlaceOrder,
                    isLoading: _isSubmitting,
                    onPressed:
                        (_canPlaceOrder &&
                            ConnectivityService.instance.isOnline)
                        ? _placeOrder
                        : null,
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
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        // Can wrap on a narrow screen or with large text instead of running off the edge.
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
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
            onTap: !_pickupAvailable
                ? null
                : () {
                    setState(() => _method = _FulfillmentMethod.pickup);
                    _refreshQuote();
                  },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MethodChip(
            label: l10n.checkoutFulfillmentDelivery,
            icon: Icons.local_shipping_outlined,
            selected: _method == _FulfillmentMethod.delivery,
            onTap: !_deliveryAvailable
                ? null
                : () {
                    setState(() => _method = _FulfillmentMethod.delivery);
                    _refreshQuote();
                  },
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
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppConstants.primaryGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.checkoutPickupAt,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _coopDetails?.cooperativeName ?? AppConstants.cooperativeName,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                // The address of Cooperative Details, exactly as the Manager has it saved.
                Text(
                  _coopDetails?.addressLine ?? l10n.cdAddressUnavailable,
                  key: const Key('pickupAddress'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                // Only a real, entered number: never the placeholder.
                if (_coopDetails?.hasRealContact ?? false) ...[
                  const SizedBox(height: 2),
                  Text(
                    _coopDetails!.contactNumber!,
                    key: const Key('pickupContact'),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  l10n.uoCheckoutCashNote,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
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
        child: SkeletonBlock(height: 72),
      );
    }
    if (_addresses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppConstants.warningAmber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: AppConstants.warningAmber.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppConstants.warningAmber,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.checkoutNoAddressesPrompt,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
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

  Widget _buildNote(String text, {Key? key}) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.warningAmber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: AppConstants.warningAmber.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: AppConstants.warningAmber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The delivery fee of the chosen address, or why delivery cannot go there.
  Widget _buildQuoteCard(AppLocalizations l10n) {
    if (_quoting) {
      return Row(
        key: const Key('quoteLoading'),
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(
            l10n.uoCheckoutQuoteLoading,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )),
        ],
      );
    }
    final q = _quote;
    if (q != null) {
      return Container(
        key: const Key('quoteCard'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppConstants.primaryGreen.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Row(
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.uoCheckoutFeeNote(q.distanceKm.toStringAsFixed(2)),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              formatPesos(q.fee),
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      );
    }
    final problem = _quoteProblem;
    if (problem == null) return const SizedBox.shrink();
    final message = switch (problem) {
      DeliveryRefusal.outsideArea => l10n.errOutsideArea,
      DeliveryRefusal.noPin => l10n.errNoPin,
      DeliveryRefusal.tooFar => l10n.errTooFar,
      DeliveryRefusal.noBand => l10n.errNoBand,
      DeliveryRefusal.off || DeliveryRefusal.notReady => l10n.errDeliveryOff,
      _ => l10n.errGeneric,
    };
    return Column(
      key: const Key('quoteProblem'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNote(message),
        if (problem == DeliveryRefusal.noPin)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('editAddressForPin'),
              onPressed: () async {
                final saved = await context.push<bool>(
                  AppRoutes.addEditAddress,
                  extra: _selectedAddress,
                );
                if (saved == true) _loadAddresses();
              },
              icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
              label: Text(l10n.uoCheckoutEditAddress),
            ),
          ),
      ],
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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppConstants.radiusLg),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.checkoutSelectAddressSheetTitle,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                                _refreshQuote();
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
    // Totalled per unit: kilograms and sacks are never added together.
    final qtyLabel = formatQuantitiesByUnit(
      widget.items.map((i) => (quantity: i.quantityKg, unit: i.unit)),
    );
    final notes = _method == _FulfillmentMethod.delivery
        ? _selectedAddress?.notes
        : null;

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
          Text(
            l10n.checkoutAdditionalInfoTitle,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _infoRow(
            Icons.inventory_2_outlined,
            l10n.checkoutItemsSummary(widget.items.length, qtyLabel),
          ),
          const SizedBox(height: 10),
          _infoRow(
            _method == _FulfillmentMethod.pickup
                ? Icons.storefront_rounded
                : Icons.local_shipping_outlined,
            '${l10n.checkoutFulfillmentMethodLabel}: '
            '${_method == _FulfillmentMethod.pickup ? l10n.checkoutFulfillmentPickup : l10n.checkoutFulfillmentDelivery}',
          ),
          if (notes != null && notes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoRow(Icons.note_outlined, '${l10n.checkoutNotesLabel}: $notes'),
          ],
          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.checkoutReviewNote,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
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
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
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
              width: 56,
              height: 56,
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
                Text(
                  item.displayName,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context
                        .adaptiveSurface(AppConstants.infoBlueBg)
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  ),
                  child: Text(
                    item.isCooperative
                        ? AppLocalizations.of(context).cpSourceLabel
                        : marketTypeLabelFor(item.marketType),
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatQuantityUnit(item.quantityKg, item.unit)} × ${formatPricePerUnit(item.pricePerKg, item.unit)}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '₱${item.subtotal.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _MethodChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppConstants.primaryGreen
                : context.saganaColors.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(
              color: selected
                  ? AppConstants.primaryGreen
                  : Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.primary,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
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

  const _AddressOptionTile({
    required this.address,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppConstants.primaryGreen.withValues(alpha: 0.06)
              : context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: selected
                ? AppConstants.primaryGreen
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      address.label,
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    address.recipientName ?? '',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address.addressLine,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (address.contactNumber != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      address.contactNumber!,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
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
