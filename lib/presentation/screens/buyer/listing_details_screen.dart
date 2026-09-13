import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/buyer_listing_model.dart';
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/cart_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';

// Local bypass — same pattern as the notification/price/order bypasses
// elsewhere in this project. BuyerListingModel.harvestedLabel hardcodes
// English; this operates on the model's public harvestDate field instead.
String _harvestedLabel(DateTime? harvestDate, AppLocalizations l10n) {
  if (harvestDate == null) return '';
  final diff = DateTime.now().difference(harvestDate);
  if (diff.inDays <= 0) return l10n.buyerHarvestedToday;
  if (diff.inDays == 1) return l10n.buyerHarvestedYesterday;
  return l10n.buyerHarvestedDaysAgo(diff.inDays);
}

class ListingDetailsScreen extends StatefulWidget {
  final String listingId;
  const ListingDetailsScreen({super.key, required this.listingId});

  @override
  State<ListingDetailsScreen> createState() => _ListingDetailsScreenState();
}

class _ListingDetailsScreenState extends State<ListingDetailsScreen> {
  final _repository = BuyerMarketplaceRepository();
  final _cartService = CartService();

  bool _isLoading = true;
  BuyerListingModel? _listing;
  List<BuyerListingModel> _related = [];
  double _quantity = 10;
  bool _isSubmitting = false;
  bool _isAddingToCart = false;

  late final TextEditingController _qtyController;
  late final FocusNode _qtyFocusNode;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: _fmtQty(_quantity));
    _qtyFocusNode = FocusNode()
      ..addListener(() {
        if (!_qtyFocusNode.hasFocus) _commitQuantityInput();
      });
    _load();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _qtyFocusNode.dispose();
    super.dispose();
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
      _qtyController.text = _fmtQty(_quantity);
    });
  }

  void _adjustQuantity(double delta) {
    final max = _listing!.displayAvailableKg; // real value, not floored
    // Floor of 1kg for normal stock. For listings with under 1kg
    // remaining, floor must not exceed max (Dart's clamp() throws if
    // min > max) — those rare sub-1kg listings pin to their exact
    // available quantity instead, which is correct: there's no
    // meaningful partial-kg stepping to do below 1kg anyway.
    final minQty = max < 1 ? max : 1.0;
    setState(() {
      _quantity = (_quantity + delta).clamp(minQty, max);
      _qtyController.text = _fmtQty(_quantity);
    });
  }

  // Validates and clamps whatever the buyer typed directly, on submit or
  // on losing focus (tapping elsewhere). Invalid/empty input falls back
  // to the safe minimum rather than silently keeping a stale value.
  void _commitQuantityInput() {
    final listing = _listing;
    if (listing == null) return;
    final max = listing.displayAvailableKg;
    final minQty = max < 1 ? max : 1.0;
    final parsed = double.tryParse(_qtyController.text.trim());
    setState(() {
      _quantity = (parsed ?? minQty).clamp(minQty, max);
      _qtyController.text = _fmtQty(_quantity);
    });
  }

  Future<void> _confirmAndPlaceOrder() async {
    final listing = _listing!;
    final total = _quantity * listing.pricePerKg;

    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: _OrderConfirmationDialog(
        listing: listing,
        quantity: _quantity,
        total: total,
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final orderId = await _repository.placeOrder(
        listingId: listing.id,
        quantityKg: _quantity,
      );
      AppEventService.instance.notifyOrderPlaced();
      if (!mounted) return;
      context.pushReplacement(AppRoutes.orderSuccess, extra: orderId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppConstants.errorRed,
        ),
      );
      // Order failed — likely stock changed underneath us. Reload to
      // reflect the real current available_kg rather than leave a stale UI.
      _load();
    }
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
      availableKgSnapshot: listing.displayAvailableKg,
      quantityKg: _quantity,
    );
    if (!mounted) return;
    setState(() => _isAddingToCart = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.buyerListingAddedToCart(listing.displayName)),
        backgroundColor: AppConstants.successGreen,
        action: SnackBarAction(
          label: l10n.buyerListingViewCart,
          textColor: Colors.white,
          onPressed: () => context.push(AppRoutes.buyerCart),
        ),
      ),
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
    final total = _quantity * listing.pricePerKg;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 300,
                backgroundColor: sagana.scaffoldBackground,
                leading: _CircleIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => context.pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      listing.listingPhotoUrl != null
                          ? Image.network(listing.listingPhotoUrl!, fit: BoxFit.cover)
                          : Container(color: AppConstants.limeGreen),
                      Positioned(
                        bottom: 16, right: 16,
                        child: _pill(l10n.buyerListingSp3Badge, AppConstants.primaryGreen),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.spacingSafeH, 20, AppConstants.spacingSafeH, 140,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              listing.displayName,
                              style: GoogleFonts.poppins(
                                fontSize: 24, fontWeight: FontWeight.w800,
                                color: AppConstants.primaryGreen,
                              ),
                            ),
                          ),
                          if (listing.harvestDate != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppConstants.onPrimaryContainer.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                              ),
                              child: Text(
                                _harvestedLabel(listing.harvestDate, l10n),
                                style: GoogleFonts.inter(fontSize: 11, color: AppConstants.primaryGreen),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GlassCard(
                        child: Row(
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
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.4,
                        children: [
                          if (listing.batchNumber != null)
                            _dataTile(l10n.buyerListingBatchNo, '#${listing.batchNumber}'),
                          if (listing.harvestDate != null)
                            _dataTile(l10n.buyerListingHarvestDate, AppUtils.formatDate(listing.harvestDate!, l10n.localeName)),
                          _dataTile(l10n.buyerListingAvailable, '${listing.displayAvailableKg.toStringAsFixed(0)} kg'),
                          if (listing.category != null)
                            _dataTile(l10n.buyerListingCategory, listing.category!),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GlassCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.buyerListingSellingPrice,
                                    style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('₱${listing.pricePerKg.toStringAsFixed(0)}',
                                        style: GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
                                    Text('/kg', style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
                                  ],
                                ),
                              ],
                            ),
                            if (listing.marketRefPricePerKg != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (listing.isPriceWithinMarketRange
                                              ? AppConstants.successGreen
                                              : AppConstants.warningAmber)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                                    ),
                                    child: Text(
                                      listing.isPriceWithinMarketRange ? l10n.buyerListingWithinRange : l10n.buyerListingAboveRange,
                                      style: GoogleFonts.inter(
                                        fontSize: 10, fontWeight: FontWeight.w700,
                                        color: listing.isPriceWithinMarketRange
                                            ? AppConstants.successGreen : AppConstants.warningAmber,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(l10n.buyerListingMarketRate(listing.marketRefPricePerKg!.toStringAsFixed(0)),
                                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!listing.isSoldOut) _buildQuantitySection(listing, total, l10n),
                      const SizedBox(height: 16),
                      _buildPickupCard(l10n),
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
                                onTap: () => context.pushReplacement(AppRoutes.listingDetails, extra: r.id),
                                child: Container(
                                  width: 140,
                                  decoration: BoxDecoration(
                                    color: context.saganaColors.cardBackground,
                                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                                  ),
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
                                        padding: const EdgeInsets.all(8),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(r.cropName, maxLines: 1, overflow: TextOverflow.ellipsis,
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
              ),
            ],
          ),
          if (!listing.isSoldOut)
            Positioned(
              left: 16, right: 16, bottom: 16,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.saganaColors.cardBackground,
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -3))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                        label: Text(l10n.buyerListingAddToCart),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppConstants.primaryGreen,
                          side: const BorderSide(color: AppConstants.primaryGreen),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isAddingToCart ? null : _addToCart,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(
                        label: l10n.buyerListingPlaceOrder(total.toStringAsFixed(0)),
                        isLoading: _isSubmitting,
                        onPressed: _confirmAndPlaceOrder,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuantitySection(BuyerListingModel listing, double total, AppLocalizations l10n) {
    return GlassCard(
      child: Column(
        children: [
          Text(l10n.buyerListingOrderQty, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepperButton(Icons.remove, () => _adjustQuantity(-1)),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _qtyController,
                  focusNode: _qtyFocusNode,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen),
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none),
                  onSubmitted: (_) => _commitQuantityInput(),
                ),
              ),
              _stepperButton(Icons.add, () => _adjustQuantity(1)),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.buyerListingMaxAvailable(listing.displayAvailableKg.toStringAsFixed(0)),
              style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: context.saganaColors.scaffoldBackground,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_fmtQty(_quantity)} kg × ₱${listing.pricePerKg.toStringAsFixed(0)}',
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
                Text('₱${total.toStringAsFixed(0)}',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupCard(AppLocalizations l10n) {
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppConstants.warningAmber.withValues(alpha: 0.12), shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_on_rounded, color: AppConstants.warningAmber, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.buyerListingPickupLocation, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(AppConstants.cooperativeLocation,
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurface)),
                const SizedBox(height: 4),
                Text(l10n.buyerListingNoDelivery,
                    style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: AppConstants.onSurfaceVariant)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.buyerOrderDetailComingSoon)),
                    ),
                    child: Text(l10n.contactSp3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: context.saganaColors.scaffoldBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Icon(icon, color: AppConstants.primaryGreen),
      ),
    );
  }

  Widget _dataTile(String label, String value) {
    return GlassCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant)),
          Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
        ],
      ),
    );
  }

  String _fmtQty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);

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

class _OrderConfirmationDialog extends StatelessWidget {
  final BuyerListingModel listing;
  final double quantity;
  final double total;

  const _OrderConfirmationDialog({
    required this.listing,
    required this.quantity,
    required this.total,
  });

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
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.buyerCartConfirmOrderTitle, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(listing.displayName,
                style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 16),
            _row(l10n.buyerOrdersQuantityLabel, '${_fmtQtyStatic(quantity)} kg'),
            _row(l10n.buyerPricePerKg, '₱${listing.pricePerKg.toStringAsFixed(2)}'),
            const Divider(height: 24),
            _row(l10n.buyerCartTotalLabel, '₱${total.toStringAsFixed(2)}', bold: true),
            const SizedBox(height: 8),
            Text(
              l10n.buyerCartPickupNotice(AppConstants.cooperativeLocation),
              style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: AppConstants.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: l10n.buyerCartConfirm,
                    height: 44,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
          Text(value, style: GoogleFonts.poppins(
            fontSize: bold ? 16 : 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: bold ? AppConstants.primaryGreen : AppConstants.onSurface,
          )),
        ],
      ),
    );
  }
}