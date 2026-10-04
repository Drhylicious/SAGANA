import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_order_model.dart';
import '../../../data/repositories/buyer_order_repository.dart';
import '../../widgets/fulfillment_info_card.dart';
import '../../widgets/order_result_pieces.dart';

/// The single Order Success design for every checkout path — Buy Now
/// (one order) and an all-succeeded Cart checkout (several orders) both
/// land here with a list of the orderId(s) that were just created, and
/// both render through this exact same widget tree. There is no second
/// implementation anywhere for "orders were placed successfully" — a
/// partial-failure Cart checkout is the one genuinely different message
/// (some items didn't go through) and stays on CartCheckoutResultScreen,
/// which still reuses this screen's own OrderResultIcon/OrderReferenceCard/
/// FulfillmentInfoCard pieces for everything it shares with this one.
///
/// Fixed section order, always, regardless of Pickup/Delivery or how many
/// orders: icon -> title -> subtitle -> fulfillment card (from the first
/// order — every order in one checkout shares the same fulfillment choice)
/// -> one OrderReferenceCard per order -> buttons. Only the fulfillment
/// card's own content and the number of order cards change; the screen
/// itself never restructures.
class OrderSuccessScreen extends StatefulWidget {
  final List<String> orderIds;
  // Phase 9 — same rationale as CartCheckoutResultScreen's isFarmerContext:
  // no Farmer "My Orders" destination exists yet (Phase 13), so the
  // farmer variant only offers "back to Marketplace."
  final bool isFarmerContext;
  const OrderSuccessScreen({
    super.key,
    required this.orderIds,
    this.isFarmerContext = false,
  });

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen> {
  final _repository = BuyerOrderRepository();
  bool _isLoading = true;
  List<BuyerOrderModel> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait(widget.orderIds.map(_repository.fetchOrderById));
    if (!mounted) return;
    setState(() {
      _orders = results.whereType<BuyerOrderModel>().toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    // Every order placed in one checkout shares the same fulfillment
    // choice — read it from whichever order loaded first rather than
    // repeating an identical card once per order.
    final firstOrder = _orders.isNotEmpty ? _orders.first : null;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSafeH, vertical: 24),
                children: [
                  const SizedBox(height: 12),
                  const Center(child: OrderResultIcon(icon: Icons.check_rounded, color: AppConstants.successGreen)),
                  const SizedBox(height: 20),
                  Text(
                    l10n.buyerOrderSuccessTitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.buyerOrderSuccessSubtitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  if (firstOrder != null && firstOrder.hasFulfillmentChoice) ...[
                    FulfillmentInfoCard(
                      fulfillmentMethod: firstOrder.fulfillmentMethod,
                      deliveryAddress: firstOrder.deliveryAddress,
                      deliveryContactNumber: firstOrder.deliveryContactNumber,
                      deliveryRecipientName: firstOrder.deliveryRecipientName,
                      deliveryLabel: firstOrder.deliveryLabel,
                      deliveryNotes: firstOrder.deliveryNotes,
                    ),
                    const SizedBox(height: 10),
                  ],
                  for (int i = 0; i < _orders.length; i++) ...[
                    OrderReferenceCard(
                      orderId: _orders[i].id,
                      status: _orders[i].status,
                      photoUrl: _orders[i].listingPhotoUrl,
                      displayName: _orders[i].displayName,
                      quantityKg: _orders[i].quantityKg,
                      pricePerKg: _orders[i].pricePerKg,
                      totalPrice: _orders[i].totalPrice,
                    ),
                    if (i < _orders.length - 1) const SizedBox(height: 10),
                  ],
                ],
              ),
      ),
      // Fixed position, outside the scrollable content — per explicit
      // request, the two actions never move regardless of how much
      // fulfillment/order content is above them.
      bottomNavigationBar: _isLoading ? null : OrderResultActions(isFarmerContext: widget.isFarmerContext),
    );
  }
}
