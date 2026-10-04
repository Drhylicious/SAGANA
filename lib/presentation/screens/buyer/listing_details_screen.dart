import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_listing_model.dart';
import '../../../data/models/cart_item_model.dart';
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/services/cart_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/shared_widgets.dart';

// Same fix pattern as create_listing_screen.dart's _DecimalInputFormatter
// (max variant) — the previous formatter here only validated decimal
// *format* (digits + up to 2 places), not the *value*, so a buyer could
// freely type well past the listing's real available stock and only see
// it silently clamped once the field lost focus. This rejects the
// keystroke outright once the parsed value would exceed max, so the
// field itself never shows more than what's actually available.
class _MaxQuantityInputFormatter extends TextInputFormatter {
  final double max;
  const _MaxQuantityInputFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(newValue.text)) return oldValue;
    final parsed = double.tryParse(newValue.text);
    if (parsed != null && parsed > max) return oldValue;
    return newValue;
  }
}

// A visibly deeper card treatment than the shared flatCardDecoration()
// (alpha 0.04 / blur 8 — reads as almost no shadow at all) for this
// screen's primary content cards, per explicit feedback that shadows here
// were "barely visible." Kept local rather than changing the shared
// helper, which many other screens rely on for a flatter look.
BoxDecoration _elevatedCardDecoration(BuildContext context) {
  final sagana = context.saganaColors;
  return BoxDecoration(
    color: sagana.cardBackground,
    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
    border: AppConstants.cardBorder,
    boxShadow: AppConstants.cardShadow,
  );
}

class ListingDetailsScreen extends StatefulWidget {
  final String listingId;
  // Phase 9 — Farmer Marketplace tab reuses this exact screen (farmer role
  // is now a valid place_order() caller as of Phase 1) rather than a
  // duplicated clone. This only changes which routes the "next step"
  // pushes go to and turns on the self-purchase guard; everything else
  // (layout, pricing, related listings) is identical for both roles.
  final bool isFarmerContext;
  const ListingDetailsScreen({
    super.key,
    required this.listingId,
    this.isFarmerContext = false,
  });

  @override
  State<ListingDetailsScreen> createState() => _ListingDetailsScreenState();
}

class _ListingDetailsScreenState extends State<ListingDetailsScreen> {
  final _repository = BuyerMarketplaceRepository();
  final _cartService = CartService();

  bool _isLoading = true;
  BuyerListingModel? _listing;
  List<BuyerListingModel> _related = [];
  // Default quantity for Add to Cart only (Buy Now rework — the on-page
  // stepper moved into _BuyNowSheet, which owns its own quantity state).
  // CartScreen already lets the buyer adjust quantity before checkout, so a
  // fixed default here isn't a dead end.
  double _quantity = 10;
  bool _isAddingToCart = false;

  bool get _isOwnListing =>
      widget.isFarmerContext &&
      _listing?.farmerId != null &&
      _listing!.farmerId == Supabase.instance.client.auth.currentUser?.id;

  String get _cartRoute =>
      widget.isFarmerContext ? AppRoutes.farmerMarketplaceCart : AppRoutes.buyerCart;

  String get _checkoutRoute => widget.isFarmerContext
      ? AppRoutes.farmerMarketplaceCheckout
      : AppRoutes.checkout;

  String get _listingDetailsRoute => widget.isFarmerContext
      ? AppRoutes.farmerMarketplaceListingDetail
      : AppRoutes.listingDetails;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final listing = await _repository.fetchListingById(widget.listingId);
    List<BuyerListingModel> related = [];
    if (listing != null) {
      related = await _repository.fetchRelatedListings(excludeListingId: listing.id);
      // Was: .floor().clamp(1, ...) — silently truncated a fractional
      // remainder (low-stock listings under 10kg were floored, making the
      // true fractional remainder unreachable).
      _quantity = listing.displayAvailableKg >= 10
          ? 10
          : listing.displayAvailableKg.clamp(0.01, 999999);
    }
    if (!mounted) return;
    setState(() {
      _listing = listing;
      _related = related;
      _isLoading = false;
    });
  }

  void _openBuyNowSheet() {
    final listing = _listing!;
    // A real bottom sheet (flush to the screen edges, native slide-up),
    // not AppBottomSheet's centered-card-style transition — that read as a
    // modal/pop-up rather than a bottom sheet.
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _BuyNowSheet(
        listing: listing,
        checkoutRoute: _checkoutRoute,
      ),
    );
  }

  Future<void> _addToCart() async {
    final l10n = AppLocalizations.of(context);
    final listing = _listing!;
    setState(() => _isAddingToCart = true);
    await _cartService.addItem(
      listingId: listing.id,
      cropName: listing.cropName,
      variety: listing.variety,
      pricePerKg: listing.pricePerKg,
      photoUrl: listing.listingPhotoUrl,
      category: listing.category,
      marketType: listing.marketType,
      availableKgSnapshot: listing.displayAvailableKg,
      quantityKg: _quantity,
    );
    if (!mounted) return;
    setState(() => _isAddingToCart = false);
    // AppToast (root-Overlay, its own Timer-driven auto-dismiss), not a
    // ScaffoldMessenger SnackBar — the SnackBar here was reported stuck on
    // screen, never auto-dismissing, matching the same class of visibility/
    // lifecycle issue AppToast was introduced to avoid elsewhere.
    final router = GoRouter.of(context);
    AppToast.show(
      context,
      l10n.buyerListingAddedToCart(listing.displayName),
      actionLabel: l10n.buyerListingViewCart,
      onAction: () => router.push(_cartRoute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_listing == null) {
      return Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
        body: Center(child: Text(l10n.buyerListingNotAvailable)),
      );
    }

    final listing = _listing!;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      // SingleChildScrollView+Column, not CustomScrollView+SliverAppBar —
      // a Sliver-based scroll view always occupies the Scaffold's full body
      // height even when its content is much shorter (it just leaves the
      // remainder as plain background), which is exactly why this page had
      // a large empty gap between the content and the pinned action bar
      // below once the on-page purchase controls were removed. A plain
      // scrolling Column only ever takes the height its content needs.
      // The back button, previously supplied by SliverAppBar's `leading`,
      // is now a Positioned overlay on the image Stack instead.
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 400,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: listing.isSoldOut ? 0.55 : 1.0,
                      child: listing.listingPhotoUrl != null
                          ? Image.network(listing.listingPhotoUrl!, fit: BoxFit.cover)
                          : Container(color: AppConstants.limeGreen),
                    ),
                    Positioned(
                      top: 8, left: 8,
                      child: _CircleIconButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => context.pop(),
                      ),
                    ),
                    // Was a static "✓ SP3 Cooperative" verification badge
                    // sitting exactly where a buyer would expect to see
                    // this listing's actual Market Type — a real source
                    // of confusion (it never reflected crop_type at all).
                    // Now shows the real Market Type; seller identity
                    // already has its own dedicated card below, so
                    // nothing about the cooperative is lost here.
                    Positioned(
                      bottom: 16, right: 16,
                      child: _pill(listing.marketTypeLabel, AppConstants.primaryGreen),
                    ),
                    // Sold Out indicator — this screen previously showed
                    // none at all, so it visually "disappeared" the moment
                    // a buyer tapped in from a grid card that did show one.
                    // Right side, not left — the back button already sits
                    // top-left and the pill was covering it.
                    if (listing.isSoldOut)
                      Positioned(
                        top: 16, right: 16,
                        child: _pill(l10n.buyerBrowseSoldOut, AppConstants.errorRed),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingSafeH, 16, AppConstants.spacingSafeH, 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Price + units sold, directly under the image — moved
                      // here (was its own boxed "Selling Price" card further
                      // down) to match a standard marketplace product-page
                      // hierarchy: price/sold is the first thing a buyer
                      // reads, before the name.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('₱${listing.pricePerKg.toStringAsFixed(0)}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 26, fontWeight: FontWeight.w800,
                                    color: listing.isSoldOut ? AppConstants.outline : AppConstants.primaryGreen,
                                  )),
                              Text('/kg', style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.sell_outlined, size: 14, color: AppConstants.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.buyerBrowseUnitsSold(listing.soldKg.toStringAsFixed(0)),
                                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        listing.displayName,
                        style: GoogleFonts.poppins(
                          fontSize: 24, fontWeight: FontWeight.w800,
                          color: AppConstants.primaryGreen,
                        ),
                      ),
                      if (listing.category != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          listing.category!,
                          style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Cooperative info + the farmer's own free-text
                      // description, in one card (Buyer Browse-tab rework —
                      // was two separate cards; the standalone "Product
                      // Details" chip card is gone, per requirement 4).
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: _elevatedCardDecoration(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48, height: 48,
                                  decoration: const BoxDecoration(
                                    color: AppConstants.primaryGreen, shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.agriculture_rounded, color: Colors.white),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(AppConstants.cooperativeName,
                                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                                      Text(AppConstants.cooperativeLocation,
                                          style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (listing.description != null && listing.description!.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(listing.description!,
                                  style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant, height: 1.5)),
                            ],
                          ],
                        ),
                      ),
                      if (_isOwnListing || listing.isSoldOut) ...[
                        const SizedBox(height: 16),
                        if (_isOwnListing)
                          _buildOwnListingNotice(l10n)
                        else
                          _buildSoldOutNotice(l10n),
                      ],
                      if (_related.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(l10n.buyerListingMoreFromSp3,
                            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 130,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _related.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 10),
                            itemBuilder: (context, i) {
                              final r = _related[i];
                              return GestureDetector(
                                onTap: () => context.pushReplacement(
                                  _listingDetailsRoute,
                                  extra: r.id,
                                ),
                                child: Container(
                                  width: 140,
                                  decoration: flatCardDecoration(context),
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        height: 80, width: double.infinity,
                                        child: r.listingPhotoUrl != null
                                            ? Image.network(r.listingPhotoUrl!, fit: BoxFit.cover)
                                            : Container(color: AppConstants.limeGreen),
                                      ),
                                      Padding(
                                        // Vertical 6 not 8 — at 8 this Column
                                        // overflowed its 130px card by a
                                        // single pixel once real font
                                        // metrics (not the naive fontSize×1.2
                                        // estimate) are accounted for.
                                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(r.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.inter(fontSize: 11)),
                                            Text('₱${r.pricePerKg.toStringAsFixed(0)}/kg',
                                                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      // Reverted back to bottomNavigationBar (per explicit instruction) —
      // the inline placement attempt is undone.
      bottomNavigationBar: (!listing.isSoldOut && !_isOwnListing)
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingSafeH, 10, AppConstants.spacingSafeH, 10,
                ),
                decoration: BoxDecoration(
                  color: sagana.cardBackground,
                  border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.10))),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52, height: 52,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppConstants.primaryGreen,
                          side: const BorderSide(color: AppConstants.primaryGreen),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
                        ),
                        onPressed: _isAddingToCart ? null : _addToCart,
                        child: _isAddingToCart
                            ? const SizedBox(
                                height: 18, width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.primaryGreen),
                              )
                            : const Icon(Icons.add_shopping_cart_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PrimaryButton(
                        label: l10n.buyerListingBuyNow,
                        onPressed: _openBuyNowSheet,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  // Phase 9 self-purchase guard's UI half — place_order() already rejects
  // this server-side (Phase 1), this just avoids showing a buy flow that
  // would only fail at submit time.
  Widget _buildOwnListingNotice(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.onPrimaryContainer.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.primaryGreen.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_rounded, color: AppConstants.primaryGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.buyerListingOwnListingNotice,
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  // Shown in place of the quantity/order section once a listing is sold
  // out, so the screen doesn't just end abruptly after the price card.
  Widget _buildSoldOutNotice(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.errorRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.errorRed.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_outlined, color: AppConstants.errorRed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.buyerBrowseSoldOut,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: AppConstants.errorRed)),
                const SizedBox(height: 2),
                Text('Check back later, or browse similar listings below.',
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
      child: Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }

}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: context.saganaColors.cardBackground, shape: BoxShape.circle),
          child: Icon(icon, color: AppConstants.primaryGreen),
        ),
      ),
    );
  }
}

String _fmtQtyStatic(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);

// Buyer Browse-tab rework, Phase 6 — repackages the quantity-picking logic
// that used to live inline on ListingDetailsScreen into a bottom sheet,
// opened from its "Buy Now" action. Checkout + My Addresses (Phase 6a):
// this sheet no longer places the order itself — it builds a single-item
// CartItemModel from the chosen quantity and hands off to the shared
// CheckoutScreen, which is where fulfillment is chosen and the order is
// actually created. Takes checkoutRoute explicitly (rather than an
// isFarmerContext flag) since that's the one piece of the parent screen's
// role-aware routing this sheet needs — it has no access to
// ListingDetailsScreen's own State to resolve it itself.
class _BuyNowSheet extends StatefulWidget {
  final BuyerListingModel listing;
  final String checkoutRoute;

  const _BuyNowSheet({
    required this.listing,
    required this.checkoutRoute,
  });

  @override
  State<_BuyNowSheet> createState() => _BuyNowSheetState();
}

class _BuyNowSheetState extends State<_BuyNowSheet> {
  late double _quantity;
  late final TextEditingController _qtyController;
  late final FocusNode _qtyFocusNode;

  BuyerListingModel get _listing => widget.listing;

  @override
  void initState() {
    super.initState();
    // Same default-quantity formula _load() used to apply on the parent
    // screen (10kg, or full stock if less).
    _quantity = _listing.displayAvailableKg >= 10
        ? 10
        : _listing.displayAvailableKg.clamp(0.01, 999999);
    _qtyController = TextEditingController(text: _fmtQtyStatic(_quantity));
    _qtyFocusNode = FocusNode()
      ..addListener(() {
        if (!_qtyFocusNode.hasFocus) _commitQuantityInput();
      });
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _qtyFocusNode.dispose();
    super.dispose();
  }

  void _adjustQuantity(double delta) {
    final max = _listing.displayAvailableKg;
    final minQty = max < 1 ? max : 1.0;
    setState(() {
      _quantity = (_quantity + delta).clamp(minQty, max);
      _qtyController.text = _fmtQtyStatic(_quantity);
    });
  }

  void _commitQuantityInput() {
    final max = _listing.displayAvailableKg;
    final minQty = max < 1 ? max : 1.0;
    final parsed = double.tryParse(_qtyController.text.trim());
    setState(() {
      _quantity = (parsed ?? minQty).clamp(minQty, max);
      _qtyController.text = _fmtQtyStatic(_quantity);
    });
  }

  // Captures the router before popping the sheet, so navigation doesn't
  // depend on this widget's own context still being mounted/valid
  // afterward — same defensive pattern the old placeOrder call used here.
  void _goToCheckout() {
    final router = GoRouter.of(context);
    final item = CartItemModel(
      listingId: _listing.id,
      cropName: _listing.cropName,
      variety: _listing.variety,
      pricePerKg: _listing.pricePerKg,
      photoUrl: _listing.listingPhotoUrl,
      category: _listing.category,
      marketType: _listing.marketType,
      availableKgSnapshot: _listing.displayAvailableKg,
      quantityKg: _quantity,
    );
    Navigator.of(context).pop();
    router.push(widget.checkoutRoute, extra: {
      'items': [item],
      'isCartCheckout': false,
    });
  }

  // 40px — a proper touch target with a visible gap on either side of the
  // quantity value (added in build()), not packed edge-to-edge against it.
  // No border of its own — sits inside the single shared pill container
  // built in build(), which supplies the one shared border around
  // minus/value/plus together.
  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: AppConstants.primaryGreen),
      ),
    );
  }

  Widget _marketTypePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppConstants.primaryGreen,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        _listing.marketTypeLabel,
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // A real bottom sheet: flush against the left/right/bottom screen
    // edges (rounded top corners only — no outer margin, which is what
    // made the previous version read as a floating card/modal instead).
    // SafeArea handles the bottom system inset since showModalBottomSheet
    // doesn't add one itself, matching this codebase's own sheet
    // convention (e.g. crop_catalog_sheet.dart's _PhotoSourceSheet).
    return SafeArea(
      top: false,
      child: Material(
        color: context.saganaColors.cardBackground,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    child: SizedBox(
                      width: 76, height: 76,
                      child: _listing.listingPhotoUrl != null
                          ? Image.network(_listing.listingPhotoUrl!, fit: BoxFit.cover)
                          : Container(color: AppConstants.limeGreen),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('₱${_listing.pricePerKg.toStringAsFixed(0)}',
                                style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
                            Text('/kg', style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.buyerListingMaxAvailable(_listing.displayAvailableKg.toStringAsFixed(0)),
                          style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _marketTypePill(),
              const SizedBox(height: 28),
              // Wrap, not Row — a fixed 80px gap plus the label plus the
              // pill doesn't always leave enough width to keep everything
              // on one line (this hit a RenderFlex overflow once already,
              // then a truncated label once the gap widened to 80px). Wrap
              // keeps the exact same one-line look whenever there's room
              // for it, and only drops the pill to its own line below the
              // label on genuinely narrow widths — never clips the label
              // and never overflows, unlike a Row with a fixed-width gap.
              Wrap(
                spacing: 80,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l10n.buyerListingOrderQty,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  // One shared bordered pill around all three elements —
                  // was three individually-boxed controls with gaps between
                  // them, which read as three separate buttons rather than
                  // a single compact stepper.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppConstants.primaryGreen.withValues(alpha: 0.35)),
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _stepperButton(Icons.remove, () => _adjustQuantity(-1)),
                        SizedBox(
                          width: 32,
                          child: TextField(
                            controller: _qtyController,
                            focusNode: _qtyFocusNode,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [_MaxQuantityInputFormatter(_listing.displayAvailableKg)],
                            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen),
                            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none),
                            onSubmitted: (_) => _commitQuantityInput(),
                          ),
                        ),
                        _stepperButton(Icons.add, () => _adjustQuantity(1)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: l10n.buyerListingBuyNow,
                onPressed: _goToCheckout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}