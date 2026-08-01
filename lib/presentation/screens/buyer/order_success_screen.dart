import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_order_model.dart';
import '../../../data/repositories/buyer_order_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';

class OrderSuccessScreen extends StatefulWidget {
  final String orderId;
  const OrderSuccessScreen({super.key, required this.orderId});

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen> {
  final _repository = BuyerOrderRepository();
  bool _isLoading = true;
  BuyerOrderModel? _order;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final order = await _repository.fetchOrderById(widget.orderId);
    if (!mounted) return;
    setState(() {
      _order = order;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSafeH),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    _buildCheckmark(),
                    const SizedBox(height: 24),
                    Text(
                      'Order Placed!',
                      style: GoogleFonts.poppins(
                        fontSize: 24, fontWeight: FontWeight.w800,
                        color: AppConstants.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'SP3 Agriculture Cooperative will review your order shortly.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    if (_order != null) _buildSummaryCard(_order!),
                    const Spacer(),
                    PrimaryButton(
                      label: 'View My Orders',
                      onPressed: () => context.go(AppRoutes.myOrders),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.marketplaceBrowse),
                      child: Text(
                        'Continue Shopping',
                        style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: AppConstants.primaryGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildCheckmark() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(scale: value, child: child),
      child: Container(
        width: 96, height: 96,
        decoration: const BoxDecoration(
          color: AppConstants.successGreen,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 52),
      ),
    );
  }

  Widget _buildSummaryCard(BuyerOrderModel order) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(order.orderReference,
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppConstants.onSurfaceVariant)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppConstants.warningAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(order.statusLabel,
                    style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: AppConstants.warningAmber)),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                child: order.listingPhotoUrl != null
                    ? Image.network(order.listingPhotoUrl!, width: 48, height: 48, fit: BoxFit.cover)
                    : Container(width: 48, height: 48, color: AppConstants.limeGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.displayName, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                    Text('${order.quantityKg.toStringAsFixed(0)} kg × ₱${order.pricePerKg.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                  ],
                ),
              ),
              Text('₱${order.totalPrice.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
            ],
          ),
        ],
      ),
    );
  }
}