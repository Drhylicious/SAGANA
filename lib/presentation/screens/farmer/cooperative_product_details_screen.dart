import '../../../core/l10n/localized_labels.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/cart_item_model.dart';
import '../../../data/models/cooperative_product_model.dart';
import '../../../data/repositories/farmer_program_repository.dart';
import '../../../data/services/cart_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/cooperative_address_text.dart';
import '../../widgets/product_buy_now_sheet.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/sub_page_top_bar.dart';

/// A Cooperative Product (a Product Sales program product) as a Farmer sees it in the
/// Marketplace.
///
/// It is laid out exactly like a Marketplace listing (ListingDetailsScreen): the photo with the
/// back button over it, the price and what was sold, the name, the cooperative card, "More from
/// SP3", and a bottom bar with Add to Cart and Buy Now. Buy Now opens the same sliding sheet.
/// It uses the same cart and the same checkout as a Marketplace listing. Only Farmers reach this
/// screen (the database shows Cooperative Products to Farmers only).
class CooperativeProductDetailsScreen extends StatefulWidget {
  final CooperativeProduct product;

  /// Where "More from SP3" comes from (tests replace it).
  final Future<List<CooperativeProduct>> Function()? loadRelated;

  const CooperativeProductDetailsScreen({
    super.key,
    required this.product,
    this.loadRelated,
  });

  @override
  State<CooperativeProductDetailsScreen> createState() =>
      _CooperativeProductDetailsScreenState();
}

class _CooperativeProductDetailsScreenState
    extends State<CooperativeProductDetailsScreen> {
  final _cart = CartService();
  bool _adding = false;
  List<CooperativeProduct> _related = [];

  CooperativeProduct get _p => widget.product;

  /// What Add to Cart and Buy Now open with: one unit, or whatever is left if that is less.
  double get _defaultQuantity => _p.availableToSell >= 1
      ? 1
      : _p.availableToSell.clamp(0.01, 999999).toDouble();

  @override
  void initState() {
    super.initState();
    _loadRelated();
  }

  Future<void> _loadRelated() async {
    try {
      final load =
          widget.loadRelated ??
          FarmerProgramRepository().fetchCooperativeProducts;
      final all = await load();
      if (!mounted) return;
      setState(
        () => _related = [
          for (final r in all)
            if (r.productId != _p.productId) r,
        ],
      );
    } catch (_) {
      // "More from SP3" is a convenience: without it the page is still complete.
    }
  }

  CartItemModel _line(double quantity) => CartItemModel(
    // For a Cooperative line the "listing id" is the PRODUCT id.
    listingId: _p.productId,
    cropName: _p.itemName,
    pricePerKg: _p.payPrice,
    unit: _p.unit,
    photoUrl: _p.imageUrl,
    category: _p.category.isEmpty ? null : _p.category,
    availableKgSnapshot: _p.availableToSell,
    quantityKg: quantity,
    source: kCartSourceCooperative,
    programId: _p.programId,
    programName: _p.programName,
    regularPrice: _p.regularPrice,
  );

  Future<void> _addToCart() async {
    final l10n = AppLocalizations.of(context);
    if (!ConnectivityService.instance.isOnline) {
      AppToast.show(context, l10n.offlineBuyerBody);
      return;
    }
    setState(() => _adding = true);
    await _cart.addItem(
      listingId: _p.productId,
      cropName: _p.itemName,
      pricePerKg: _p.payPrice,
      unit: _p.unit,
      photoUrl: _p.imageUrl,
      category: _p.category.isEmpty ? null : _p.category,
      availableKgSnapshot: _p.availableToSell,
      quantityKg: _defaultQuantity,
      source: kCartSourceCooperative,
      programId: _p.programId,
      programName: _p.programName,
      regularPrice: _p.regularPrice,
    );
    if (!mounted) return;
    setState(() => _adding = false);
    final router = GoRouter.of(context);
    AppToast.show(
      context,
      l10n.buyerListingAddedToCart(_p.itemName),
      actionLabel: l10n.buyerListingViewCart,
      onAction: () => router.push(AppRoutes.farmerMarketplaceCart),
    );
  }

  void _openBuyNowSheet() {
    final l10n = AppLocalizations.of(context);
    final router = GoRouter.of(context);
    ProductBuyNowSheet.show(
      context,
      photoUrl: _p.imageUrl,
      price: _p.payPrice,
      unit: _p.unit,
      available: _p.availableToSell,
      pillLabel: l10n.cpTitle,
      initialQuantity: _defaultQuantity,
      onConfirm: (quantity) => router.push(
        AppRoutes.farmerMarketplaceCheckout,
        extra: {
          "items": [_line(quantity)],
          'isCartCheckout': false,
        },
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

  BoxDecoration _elevatedCard(BuildContext context) => BoxDecoration(
    color: context.saganaColors.cardBackground,
    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
    border: AppConstants.cardBorder,
    boxShadow: AppConstants.cardShadow,
  );

  Widget _photo(String? url) => url != null && url.isNotEmpty
      ? Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(color: AppConstants.limeGreen),
        )
      : Container(color: AppConstants.limeGreen);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final soldOut = _p.isOutOfStock;
    final unit = unitOrDefault(_p.unit);

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
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
                      opacity: soldOut ? 0.55 : 1.0,
                      child: _photo(_p.imageUrl),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: SubPageBackButton(onPressed: () => context.pop()),
                    ),
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: _pill(l10n.cpTitle, AppConstants.primaryGreen),
                    ),
                    if (soldOut)
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
                    // Price, and how much has been sold, directly under the photo.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(
                                child: Text(
                                  formatPesos(_p.payPrice),
                                  key: Key(
                                    _p.memberPriceApplies
                                        ? 'cpMemberPrice'
                                        : 'cpPrice',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    color: soldOut
                                        ? Theme.of(context).colorScheme.outline
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                              Text(
                                '/$unit',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
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
                                  formatQuantityUnit(_p.soldQuantity, _p.unit),
                                ),
                                key: const Key('cpSold'),
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
                      _p.itemName,
                      key: const Key('cpName'),
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (_p.category.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        localizeBuiltinLabel(
                          AppLocalizations.of(context),
                          _p.category,
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    // The member price is the one Cooperative-specific detail: what the
                    // regular price is, and what the discount is.
                    if (_p.memberPriceApplies) ...[
                      const SizedBox(height: 6),
                      Text(
                        formatPricePerUnit(_p.regularPrice, _p.unit),
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.cpYouPayMember(
                          formatQuantity(_p.memberDiscountPercent),
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.successGreen,
                        ),
                      ),
                    ] else if (_p.hasMemberDiscount) ...[
                      const SizedBox(height: 10),
                      Container(
                        key: const Key('cpMembersPay'),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppConstants.programPurple.withValues(
                            alpha: 0.08,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                        ),
                        child: Text(
                          l10n.cpMembersPay(
                            formatPesos(_p.memberPrice),
                            formatQuantity(_p.memberDiscountPercent),
                            _p.programName,
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.4,
                            color: AppConstants.programPurple,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // The cooperative, and the program this product belongs to, in one card.
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: _elevatedCard(context),
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
                          const SizedBox(height: 14),
                          Text(
                            l10n.cpFromProgram(_p.programName),
                            key: const Key('cpProgram'),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (soldOut) ...[
                      const SizedBox(height: 16),
                      _soldOutNotice(l10n),
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
                          key: const Key('cpRelated'),
                          scrollDirection: Axis.horizontal,
                          itemCount: _related.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, i) =>
                              _relatedCard(_related[i]),
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
      bottomNavigationBar: soldOut
          ? null
          : SafeArea(
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
                        key: const Key('cpAddToCart'),
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
                        onPressed: _adding ? null : _addToCart,
                        child: _adding
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
                        key: const Key('cpBuyNow'),
                        label: l10n.buyerListingBuyNow,
                        onPressed: _openBuyNowSheet,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _relatedCard(CooperativeProduct r) {
    return GestureDetector(
      key: Key('cpRelated_${r.productId}'),
      onTap: () =>
          context.pushReplacement(AppRoutes.farmerCooperativeProduct, extra: r),
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
              child: _photo(r.imageUrl),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11),
                  ),
                  Text(
                    formatPricePerUnit(r.payPrice, r.unit),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
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

  Widget _soldOutNotice(AppLocalizations l10n) {
    return Container(
      key: const Key('cpSoldOutNotice'),
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
                  l10n.cpSoldOutBody,
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
}
