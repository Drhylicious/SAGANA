import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_listing_model.dart';
import '../../../data/repositories/buyer_marketplace_repository.dart';
import '../../../data/services/cart_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';

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
  int _quantity = 10;
  bool _isSubmitting = false;
  bool _isAddingToCart = false;

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
      _quantity = listing.displayAvailableKg >= 10 ? 10 : listing.displayAvailableKg.floor().clamp(1, 999999);
    }
    if (!mounted) return;
    setState(() {
      _listing = listing;
      _related = related;
      _isLoading = false;
    });
  }

  void _adjustQuantity(int delta) {
    final max = _listing!.displayAvailableKg.floor();
    setState(() {
      _quantity = (_quantity + delta).clamp(1, max);
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
        quantityKg: _quantity.toDouble(),
      );
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
    final listing = _listing!;
    setState(() => _isAddingToCart = true);
    await _cartService.addItem(
      listingId: listing.id,
      cropName: listing.cropName,
      variety: listing.variety,
      pricePerKg: listing.pricePerKg,
      photoUrl: listing.listingPhotoUrl,
      availableKgSnapshot: listing.displayAvailableKg,
      quantityKg: _quantity.toDouble(),
    );
    if (!mounted) return;
    setState(() => _isAddingToCart = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added to cart — ${listing.displayName}'),
        backgroundColor: AppConstants.successGreen,
        action: SnackBarAction(
          label: 'View Cart',
          textColor: Colors.white,
          onPressed: () => context.push(AppRoutes.buyerCart),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_listing == null) {
      return Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
        body: const Center(child: Text('This listing is no longer available.')),
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
                      if (listing.qualityGrade != null)
                        Positioned(
                          bottom: 16, left: 16,
                          child: _pill(listing.qualityGrade!, AppConstants.successGreen),
                        ),
                      Positioned(
                        bottom: 16, right: 16,
                        child: _pill('✓ SP3 Cooperative', AppConstants.primaryGreen),
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
                                listing.harvestedLabel,
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
                            _dataTile('Batch No.', '#${listing.batchNumber}'),
                          if (listing.harvestDate != null)
                            _dataTile('Harvest Date', _formatDate(listing.harvestDate!)),
                          _dataTile('Available', '${listing.displayAvailableKg.toStringAsFixed(0)} kg'),
                          if (listing.category != null)
                            _dataTile('Category', listing.category!),
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
                                Text('Selling Price',
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
                                      listing.isPriceWithinMarketRange ? 'Within market range' : 'Above market range',
                                      style: GoogleFonts.inter(
                                        fontSize: 10, fontWeight: FontWeight.w700,
                                        color: listing.isPriceWithinMarketRange
                                            ? AppConstants.successGreen : AppConstants.warningAmber,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Market Rate: ₱${listing.marketRefPricePerKg!.toStringAsFixed(0)}/kg',
                                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!listing.isSoldOut) _buildQuantitySection(listing, total),
                      const SizedBox(height: 16),
                      _buildPickupCard(),
                      if (_related.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text('More from SP3',
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
                                    color: Colors.white,
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
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                      label: const Text('Add to Cart'),
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
                      label: 'Place Order — ₱${total.toStringAsFixed(0)}',
                      isLoading: _isSubmitting,
                      onPressed: _confirmAndPlaceOrder,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuantitySection(BuyerListingModel listing, double total) {
    return GlassCard(
      child: Column(
        children: [
          Text('Order Quantity (kg)', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepperButton(Icons.remove, () => _adjustQuantity(-10)),
              SizedBox(
                width: 80,
                child: Text(
                  '$_quantity',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen),
                ),
              ),
              _stepperButton(Icons.add, () => _adjustQuantity(10)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Max: ${listing.displayAvailableKg.toStringAsFixed(0)} kg available',
              style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: AppConstants.offWhite,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$_quantity kg × ₱${listing.pricePerKg.toStringAsFixed(0)}',
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

  Widget _buildPickupCard() {
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
                Text('📍 Pickup Location', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(AppConstants.cooperativeLocation,
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurface)),
                const SizedBox(height: 4),
                Text('No delivery available. Buyer must arrange transport.',
                    style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: AppConstants.onSurfaceVariant)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('SP3 contact number coming soon.')),
                    ),
                    child: const Text('Contact SP3'),
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
          color: AppConstants.offWhite,
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

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
      child: Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }

  String _formatDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
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
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(icon, color: AppConstants.primaryGreen),
        ),
      ),
    );
  }
}

class _OrderConfirmationDialog extends StatelessWidget {
  final BuyerListingModel listing;
  final int quantity;
  final double total;

  const _OrderConfirmationDialog({
    required this.listing,
    required this.quantity,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confirm Order', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(listing.displayName,
                style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 16),
            _row('Quantity', '$quantity kg'),
            _row('Price per kg', '₱${listing.pricePerKg.toStringAsFixed(2)}'),
            const Divider(height: 24),
            _row('Total', '₱${total.toStringAsFixed(2)}', bold: true),
            const SizedBox(height: 8),
            Text(
              'Pickup at ${AppConstants.cooperativeLocation}. No delivery — you must arrange transport.',
              style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: AppConstants.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: 'Confirm',
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