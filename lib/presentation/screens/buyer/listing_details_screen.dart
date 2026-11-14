import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/buyer_listing_model.dart';
import '../../../data/models/cart_item_model.dart';
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/services/cart_service.dart';
import '../../../routes/app_routes.dart';
import '../../../data/services/guest_mode_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/guest_prompt.dart';
import '../../widgets/shared_widgets.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/table_change_watcher.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/cooperative_address_text.dart';
import '../../widgets/product_buy_now_sheet.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

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
  bool _isOnline = ConnectivityService.instance.isOnline;
  BuyerListingModel? _listing;
  List<BuyerListingModel> _related = [];
  // Default quantity for Add to Cart only (Buy Now rework — the on-page
  // stepper moved into _BuyNowSheet, which owns its own quantity state).
  // CartScreen already lets the buyer adjust quantity before checkout, so a
  // fixed default here isn't a dead end.
  double _quantity = 10;
  bool _isAddingToCart = false;
  TableChangeWatcher? _stockWatcher;

  bool get _isOwnListing =>
      widget.isFarmerContext &&
      _listing?.farmerId != null &&
      _listing!.farmerId == Supabase.instance.client.auth.currentUser?.id;

  String get _cartRoute => widget.isFarmerContext
      ? AppRoutes.farmerMarketplaceCart
      : AppRoutes.buyerCart;

  String get _checkoutRoute => widget.isFarmerContext
      ? AppRoutes.farmerMarketplaceCheckout
      : AppRoutes.checkout;

  String get _listingDetailsRoute => widget.isFarmerContext
      ? AppRoutes.farmerMarketplaceListingDetail
      : AppRoutes.listingDetails;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
    // Someone else ordering from this listing changes what is left.
    if (!GuestModeService.active) {
      _stockWatcher = TableChangeWatcher(
        tables: const ['marketplace_listings'],
        onChange: () {
          if (mounted) _load(silent: true);
        },
      )..start();
    }
  }

  @override
  void dispose() {
    _stockWatcher?.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final listing = await _repository.fetchListingById(widget.listingId);
    List<BuyerListingModel> related = [];
    if (listing != null) {
      related = await _repository.fetchRelatedListings(
        excludeListingId: listing.id,
      );
      // Was: .floor().clamp(1, ...) — silently truncated a fractional
      // remainder (low-stock listings under 10kg were floored, making the
      // true fractional remainder unreachable).
      final max = listing.displayAvailableKg.clamp(0.01, 999999).toDouble();
      // A quiet reload keeps what the Buyer already typed, only pulling it
      // down if the stock left is now smaller than that.
      _quantity = silent
          ? (_quantity > max ? max : _quantity)
          : (listing.displayAvailableKg >= 10 ? 10 : max);
    }
    if (!mounted) return;
    setState(() {
      _listing = listing;
      _related = related;
      _isLoading = false;
    });
  }

  void _openBuyNowSheet() {
    if (GuestModeService.active) {
      context.promptGuest(
        (l) => l.guestBuyNowTitle,
        (l) => l.guestBuyNowMessage,
        icon: Icons.shopping_bag_outlined,
      );
      return;
    }
    final listing = _listing!;
    // The router is taken now, so going on to the checkout does not depend on this
    // screen's context once the sheet has closed.
    final router = GoRouter.of(context);
    final checkoutRoute = _checkoutRoute;
    // The same sliding sheet a Cooperative Product uses (see ProductBuyNowSheet). It does not
    // place the order: it hands the chosen quantity on to the shared CheckoutScreen, which is
    // where fulfillment is chosen and the order is actually created.
    ProductBuyNowSheet.show(
      context,
      photoUrl: listing.listingPhotoUrl,
      price: listing.pricePerKg,
      unit: listing.unit,
      available: listing.displayAvailableKg,
      pillLabel: listing.marketTypeLabel,
      // 10 of the unit, or the full stock if less.
      initialQuantity: listing.displayAvailableKg >= 10
          ? 10
          : listing.displayAvailableKg.clamp(0.01, 999999).toDouble(),
      onConfirm: (quantity) {
        final item = CartItemModel(
          listingId: listing.id,
          cropName: listing.cropName,
          variety: listing.variety,
          pricePerKg: listing.pricePerKg,
          unit: listing.unit,
          photoUrl: listing.listingPhotoUrl,
          category: listing.category,
          marketType: listing.marketType,
          availableKgSnapshot: listing.displayAvailableKg,
          quantityKg: quantity,
        );
        router.push(
          checkoutRoute,
          extra: {
            "items": [item],
            'isCartCheckout': false,
          },
        );
      },
    );
  }

  Future<void> _addToCart() async {
    if (GuestModeService.active) {
      context.promptGuest(
        (l) => l.guestCartTitle,
        (l) => l.guestCartMessage,
        icon: Icons.shopping_cart_outlined,
      );
      return;
    }
    if (!ConnectivityService.instance.isOnline) {
      AppToast.show(context, AppLocalizations.of(context).offlineBuyerBody);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final listing = _listing!;
    setState(() => _isAddingToCart = true);
    await _cartService.addItem(
      listingId: listing.id,
      cropName: listing.cropName,
      variety: listing.variety,
      pricePerKg: listing.pricePerKg,
      unit: listing.unit,
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
      // Same layout as the loaded page: photo area on top, back button over it.
      return Scaffold(
        body: Stack(
          children: [
            const Column(
              children: [
                SkeletonBlock(height: 260, radius: 0),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  ),
                ),
              ],
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: SubPageBackButton(onPressed: () => context.pop()),
            ),
          ],
        ),
      );
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
              CachedDataNotice(
                screen: 'buyer_listing_${widget.listingId}',
                isOnline: _isOnline,
                offlineMessage: l10n.offlineBuyerBody,
              ),
              SizedBox(
                height: 400,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: listing.isSoldOut ? 0.55 : 1.0,
                      child: listing.listingPhotoUrl != null
                          ? Image.network(
                              listing.listingPhotoUrl!,
                              fit: BoxFit.cover,
                            )
                          : Container(color: AppConstants.limeGreen),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: SubPageBackButton(onPressed: () => context.pop()),
                    ),
                    // Was a static "✓ SP3 Cooperative" verification badge
                    // sitting exactly where a buyer would expect to see
                    // this listing's actual Market Type — a real source
                    // of confusion (it never reflected crop_type at all).
                    // Now shows the real Market Type; seller identity
                    // already has its own dedicated card below, so
                    // nothing about the cooperative is lost here.
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: _pill(
                        listing.marketTypeLabel,
                        AppConstants.primaryGreen,
                      ),
                    ),
                    // Sold Out indicator — this screen previously showed
                    // none at all, so it visually "disappeared" the moment
                    // a buyer tapped in from a grid card that did show one.
                    // Right side, not left — the back button already sits
                    // top-left and the pill was covering it.
                    if (listing.isSoldOut)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: _pill(
                          l10n.buyerBrowseSoldOut,
                          AppConstants.errorRed,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingSafeH,
                  16,
                  AppConstants.spacingSafeH,
                  24,
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
                            Text(
                              formatPesos(listing.pricePerKg),
                              style: GoogleFonts.poppins(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: listing.isSoldOut
                                    ? Theme.of(context).colorScheme.outline
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            Text(
                              '/${unitOrDefault(listing.unit)}',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.sell_outlined,
                                size: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                l10n.buyerBrowseUnitsSold(
                                  formatQuantityUnit(
                                    listing.soldKg,
                                    listing.unit,
                                  ),
                                ),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
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
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (listing.category != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        listing.category!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
                                width: 48,
                                height: 48,
                                decoration: const BoxDecoration(
                                  color: AppConstants.primaryGreen,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.agriculture_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppConstants.cooperativeName,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    CooperativeAddressText(
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (listing.description != null &&
                              listing.description!.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              listing.description!,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
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
                      Text(
                        l10n.buyerListingMoreFromSp3,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 130,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _related.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
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
                                      height: 80,
                                      width: double.infinity,
                                      child: r.listingPhotoUrl != null
                                          ? Image.network(
                                              r.listingPhotoUrl!,
                                              fit: BoxFit.cover,
                                            )
                                          : Container(
                                              color: AppConstants.limeGreen,
                                            ),
                                    ),
                                    Padding(
                                      // Vertical 6 not 8 — at 8 this Column
                                      // overflowed its 130px card by a
                                      // single pixel once real font
                                      // metrics (not the naive fontSize×1.2
                                      // estimate) are accounted for.
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        6,
                                        8,
                                        6,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            r.displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                            ),
                                          ),
                                          Text(
                                            formatPricePerUnit(
                                              r.pricePerKg,
                                              r.unit,
                                            ),
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                          ),
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
                  AppConstants.spacingSafeH,
                  10,
                  AppConstants.spacingSafeH,
                  10,
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
                  children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppConstants.primaryGreen,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusMd,
                            ),
                          ),
                        ),
                        onPressed: _isAddingToCart ? null : _addToCart,
                        child: _isAddingToCart
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppConstants.primaryGreen,
                                ),
                              )
                            : const Icon(
                                Icons.add_shopping_cart_rounded,
                                size: 20,
                              ),
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
        border: Border.all(
          color: AppConstants.primaryGreen.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.storefront_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.buyerListingOwnListingNotice,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
        border: Border.all(
          color: AppConstants.errorRed.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_outlined, color: AppConstants.errorRed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.buyerBrowseSoldOut,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppConstants.errorRed,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).enhCheckBackLaterOrBrowseSimilarListingsBelow,
                  style: GoogleFonts.inter(
                    fontSize: 12,
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

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
