import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_order_model.dart';
import '../../../data/repositories/buyer_order_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/buyer_top_bar.dart';
import '../../widgets/shared_widgets.dart';

class MyOrdersScreen extends StatefulWidget {
  final int initialTabIndex;
  const MyOrdersScreen({super.key, this.initialTabIndex = 0});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _repository = BuyerOrderRepository();
  final _notificationRepo = NotificationRepository();

  bool _isLoading = true;
  List<BuyerOrderModel> _allOrders = [];
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repository.fetchMyOrders(),
      _notificationRepo.fetchUnreadCount(),
    ]);
    if (!mounted) return;
    setState(() {
      _allOrders = results[0] as List<BuyerOrderModel>;
      _unreadCount = results[1] as int;
      _isLoading = false;
    });
  }

  List<BuyerOrderModel> _byStatus(String status) =>
      _allOrders.where((o) => o.status == status).toList();

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final pending = _byStatus('pending');
    final approved = _byStatus('approved');
    final completed = _byStatus('completed');
    final cancelled = _byStatus('cancelled');

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      if (approved.isNotEmpty) _buildApprovedBanner(approved.length),
                      TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        labelColor: AppConstants.primaryGreen,
                        unselectedLabelColor: AppConstants.onSurfaceVariant,
                        indicatorColor: AppConstants.primaryGreen,
                        labelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700),
                        tabs: [
                          Tab(text: 'Pending (${pending.length})'),
                          Tab(text: 'Approved (${approved.length})'),
                          Tab(text: 'Completed (${completed.length})'),
                          Tab(text: 'Cancelled (${cancelled.length})'),
                        ],
                      ),
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildOrderList(pending, 'No pending orders'),
                                  _buildOrderList(approved, 'No approved orders yet'),
                                  _buildOrderList(completed, 'No completed orders yet'),
                                  _buildOrderList(cancelled, 'No cancelled orders'),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: BuyerTopBar(
              title: 'My Orders',
              unreadCount: _unreadCount,
              onNotificationTap: () => context.push(AppRoutes.buyerNotifications),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedBanner(int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 14, AppConstants.spacingSafeH, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.successGreen.withValues(alpha: 0.08),
        border: Border.all(color: AppConstants.successGreen.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded, color: AppConstants.successGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order Ready for Pickup!',
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                const SizedBox(height: 2),
                Text(
                  'You have $count approved order${count > 1 ? 's' : ''} waiting for pickup at ${AppConstants.cooperativeName}.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderList(List<BuyerOrderModel> orders, String emptyMessage) {
    if (orders.isEmpty) {
      return Center(
        child: Text(emptyMessage,
            style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 12, AppConstants.spacingSafeH, 100),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _OrderCard(order: orders[i], onChanged: _load),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order Card
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final BuyerOrderModel order;
  final VoidCallback onChanged;
  const _OrderCard({required this.order, required this.onChanged});

  Color get _statusColor {
    switch (order.status) {
      case 'approved': return AppConstants.successGreen;
      case 'pending': return AppConstants.warningAmber;
      case 'completed': return AppConstants.primaryGreen;
      default: return AppConstants.outline;
    }
  }

  void _openDetail(BuildContext context) {
    context.push(AppRoutes.orderDetail, extra: order.id);
  }

  @override
  Widget build(BuildContext context) {
    final isCancelled = order.isCancelled;

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Opacity(
        opacity: isCancelled ? 0.6 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border(left: BorderSide(color: _statusColor, width: 5)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.orderReference,
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppConstants.onSurfaceVariant, letterSpacing: 0.5)),
                      Text(order.displayName,
                          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                    child: Text(order.statusLabel.toUpperCase(),
                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: _statusColor)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!isCancelled)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppConstants.offWhite,
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Quantity', style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant)),
                          Text('${order.quantityKg.toStringAsFixed(0)} kg', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Total Amount', style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant)),
                          Text('₱${order.totalPrice.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Text('Cancelled on ${_formatDate(order.updatedAt)}',
                    style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: _buildActionButton(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    switch (order.status) {
      case 'approved':
        return PrimaryButton(label: 'View Pickup Details', height: 40, onPressed: () => _openDetail(context));
      case 'completed':
        return OutlinedButton(
          onPressed: () => context.push(AppRoutes.listingDetails, extra: order.listingId),
          child: const Text('Reorder'),
        );
      case 'cancelled':
        return OutlinedButton(
          onPressed: () => context.go(AppRoutes.marketplaceBrowse),
          child: const Text('Browse Again'),
        );
      default: // pending — no action, matches mockup exactly
        return Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 14, color: AppConstants.warningAmber),
            const SizedBox(width: 6),
            Text('Awaiting cooperative review',
                style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
          ],
        );
    }
  }

  String _formatDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}';
  }
}