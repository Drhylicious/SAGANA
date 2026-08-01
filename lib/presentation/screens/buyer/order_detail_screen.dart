import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_order_model.dart';
import '../../../data/repositories/buyer_order_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
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

  Color get _statusColor {
    switch (_order?.status) {
      case 'approved': return AppConstants.successGreen;
      case 'pending': return AppConstants.warningAmber;
      case 'completed': return AppConstants.primaryGreen;
      default: return AppConstants.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_order == null) {
      return Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
        body: const Center(child: Text('Order not found.')),
      );
    }

    final order = _order!;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        leading: BackButton(onPressed: () => context.pop(), color: AppConstants.primaryGreen),
        title: Text('Order #${order.orderReference}',
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 8, AppConstants.spacingSafeH, 32),
        children: [
          _buildStatusSection(order),
          const SizedBox(height: 16),
          if (!order.isCancelled) ...[
            _buildTimeline(order),
            const SizedBox(height: 16),
          ],
          _buildProductSection(order),
          const SizedBox(height: 16),
          _buildOrderSummary(order),
          const SizedBox(height: 16),
          _buildPaymentInfo(),
          const SizedBox(height: 16),
          _buildPickupSection(),
          const SizedBox(height: 20),
          _buildSupportSection(context),
        ],
      ),
    );
  }

  Widget _buildStatusSection(BuyerOrderModel order) {
    final subtitle = switch (order.status) {
      'approved' => 'Ready for Pickup',
      'pending' => 'Awaiting cooperative review',
      'completed' => 'Picked up',
      _ => 'Order cancelled',
    };
    final message = switch (order.status) {
      'approved' => 'Your order has been approved by ${AppConstants.cooperativeName}. Please contact SP3 to arrange your pickup schedule.',
      'pending' => 'Your order is awaiting review by ${AppConstants.cooperativeName}. You\'ll be notified once it\'s approved.',
      'completed' => 'This order has been picked up. Thank you for supporting SP3 farmers!',
      _ => 'This order was cancelled and is no longer active.',
    };

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: _statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
                child: Text(order.statusLabel.toUpperCase(),
                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w800, color: _statusColor)),
              ),
              const SizedBox(width: 8),
              Text('— $subtitle', style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          Text(message, style: GoogleFonts.inter(fontSize: 13, height: 1.5)),
          if (!order.isCancelled) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Contact SP3 Cooperative',
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('SP3 contact number coming soon.')),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeline(BuyerOrderModel order) {
    // Honest simplification: only "Order Placed" (created_at) and the
    // current status (updated_at) have real timestamps. Everything in
    // between is complete-but-untimestamped; everything after is upcoming.
    const steps = ['Order Placed', 'Pending Review', 'Approved', 'Completed'];
    final currentIndex = switch (order.status) {
      'pending' => 1,
      'approved' => 2,
      'completed' => 3,
      _ => 0,
    };

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order Journey', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          for (int i = 0; i < steps.length; i++)
            _timelineStep(
              label: steps[i],
              isDone: i < currentIndex,
              isCurrent: i == currentIndex,
              isLast: i == steps.length - 1,
              timestamp: i == 0
                  ? _formatDateTime(order.createdAt)
                  : i == currentIndex
                      ? _formatDateTime(order.updatedAt)
                      : (i < currentIndex ? null : 'Pending'),
            ),
        ],
      ),
    );
  }

  Widget _timelineStep({
    required String label,
    required bool isDone,
    required bool isCurrent,
    required bool isLast,
    String? timestamp,
  }) {
    final color = isDone || isCurrent ? AppConstants.primaryGreen : AppConstants.outline.withValues(alpha: 0.3);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: isDone ? AppConstants.primaryGreen : (isCurrent ? AppConstants.primaryGreen.withValues(alpha: 0.1) : Colors.transparent),
                  shape: BoxShape.circle,
                  border: isCurrent ? Border.all(color: AppConstants.primaryGreen, width: 2) : null,
                ),
                child: isDone
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : isCurrent
                        ? Center(child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppConstants.primaryGreen, shape: BoxShape.circle)))
                        : null,
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: color)),
            ],
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                  color: isDone || isCurrent ? AppConstants.onSurface : AppConstants.onSurfaceVariant.withValues(alpha: 0.5),
                )),
                if (timestamp != null)
                  Text(timestamp, style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSection(BuyerOrderModel order) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  child: order.listingPhotoUrl != null
                      ? Image.network(order.listingPhotoUrl!, width: 64, height: 64, fit: BoxFit.cover)
                      : Container(width: 64, height: 64, color: AppConstants.limeGreen),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.displayName, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.verified_rounded, size: 13, color: AppConstants.primaryGreen),
                          const SizedBox(width: 4),
                          Text(AppConstants.cooperativeName,
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppConstants.primaryGreen)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                if (order.batchNumber != null)
                  Expanded(child: _miniField('Batch Reference', '#${order.batchNumber}')),
                if (order.harvestDate != null)
                  Expanded(child: _miniField('Freshness', order.harvestedLabel, alignEnd: true)),
              ],
            ),
          ),
          if (order.harvestDate != null || order.category != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  if (order.harvestDate != null)
                    Expanded(child: _miniField('Harvest Date', _formatDate(order.harvestDate!))),
                  if (order.category != null)
                    Expanded(child: _miniField('Category', order.category!, alignEnd: true)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniField(String label, String value, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant)),
        Text(value, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildOrderSummary(BuyerOrderModel order) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order Summary', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _summaryRow('Quantity', '${order.quantityKg.toStringAsFixed(0)} kg'),
          _summaryRow('Price per kg', '₱${order.pricePerKg.toStringAsFixed(2)}'),
          const Divider(height: 20),
          _summaryRow('Total Amount', '₱${order.totalPrice.toStringAsFixed(2)}', bold: true),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('REFERENCE', style: GoogleFonts.inter(fontSize: 9, letterSpacing: 0.5, color: AppConstants.onSurfaceVariant)),
                  Text(order.orderReference, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('ORDER DATE', style: GoogleFonts.inter(fontSize: 9, letterSpacing: 0.5, color: AppConstants.onSurfaceVariant)),
                  Text(_formatDate(order.createdAt), style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: bold ? 15 : 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: bold ? AppConstants.primaryGreen : AppConstants.onSurfaceVariant)),
          Text(value, style: GoogleFonts.poppins(fontSize: bold ? 18 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: bold ? AppConstants.primaryGreen : AppConstants.onSurface)),
        ],
      ),
    );
  }

  Widget _buildPaymentInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.gold.withValues(alpha: 0.08),
        border: Border.all(color: AppConstants.gold.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.payments_rounded, color: AppConstants.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PAYMENT INFORMATION', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(
                  'Payment for this order is collected at the time of pickup at the cooperative. SP3 accepts cash payment upon collection.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupSection() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pickup Location', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('${AppConstants.cooperativeName}, ${AppConstants.cooperativeLocation}',
              style: GoogleFonts.inter(fontSize: 13)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppConstants.offWhite,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.calendar_today_rounded, size: 16, color: AppConstants.primaryGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BOD Meeting Schedule', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                      const SizedBox(height: 2),
                      Text('Every 1st Saturday of the month — payments and pickups can be coordinated during this meeting.',
                          style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportSection(BuildContext context) {
    return Column(
      children: [
        Text('Need help with this order?', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('Contact SP3 Agriculture Cooperative directly for assistance.',
            style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.call_rounded, size: 18),
            label: const Text('Call SP3 Cooperative'),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('SP3 contact number coming soon.')),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.shopping_basket_outlined, size: 18),
          label: const Text('Browse More Products'),
          onPressed: () => context.go(AppRoutes.marketplaceBrowse),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _formatDateTime(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final minute = d.minute.toString().padLeft(2, '0');
    return '${_formatDate(d)}, $hour:$minute $ampm';
  }
} 