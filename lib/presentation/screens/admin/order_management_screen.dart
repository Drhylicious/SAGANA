import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/admin_order_repository.dart';
import '../../../routes/app_routes.dart';

class OrderManagementScreen extends StatefulWidget {
  /// When set, the screen opens pre-filtered to one buyer's orders —
  /// reused by BuyerManagementScreen's "View Order History" instead of
  /// building a second order-browsing screen.
  final String? buyerId;
  final String? buyerName;

  const OrderManagementScreen({super.key, this.buyerId, this.buyerName});

  @override
  State<OrderManagementScreen> createState() => _OrderManagementScreenState();
}

class _OrderManagementScreenState extends State<OrderManagementScreen>
    with SingleTickerProviderStateMixin {
  final _repo = AdminOrderRepository();
  final _searchCtrl = TextEditingController();
  late final TabController _tabController;

  List<AdminOrderModel> _allOrders = [];
  bool _isLoading = true;
  bool _hasLoadedOnce = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _tabController = TabController(length: 4, vsync: this);
    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_hasLoadedOnce) setState(() => _isLoading = true);
    final orders = await _repo.fetchOrders(buyerId: widget.buyerId);
    if (!mounted) return;
    setState(() {
      _allOrders = orders;
      _isLoading = false;
      _hasLoadedOnce = true;
    });
  }

  List<AdminOrderModel> _byStatus(String status) {
    var list = _allOrders.where((o) => o.status == status);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((o) =>
          o.buyerName.toLowerCase().contains(q) ||
          o.cropName.toLowerCase().contains(q) ||
          o.orderReference.toLowerCase().contains(q));
    }
    return list.toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pending = _byStatus('pending');
    final approved = _byStatus('approved');
    final completed = _byStatus('completed');
    final cancelled = _byStatus('cancelled');

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _TopAppBar(
            title: widget.buyerName != null ? '${widget.buyerName}\'s Orders' : 'Order Management',
            onBack: () => context.pop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search buyer, crop, or order #...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
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
                      _buildList(pending, 'No pending orders'),
                      _buildList(approved, 'No approved orders'),
                      _buildList(completed, 'No completed orders'),
                      _buildList(cancelled, 'No cancelled orders'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<AdminOrderModel> orders, String emptyMessage) {
    if (orders.isEmpty) {
      return Center(
        child: Text(emptyMessage, style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _OrderRow(order: orders[i], onTap: () async {
          await context.push(AppRoutes.adminOrderDetail, extra: orders[i].id);
          _load();
        }),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final AdminOrderModel order;
  final VoidCallback onTap;
  const _OrderRow({required this.order, required this.onTap});

  Color get _statusColor {
    switch (order.status) {
      case 'approved': return AppConstants.successGreen;
      case 'pending': return AppConstants.warningAmber;
      case 'completed': return AppConstants.primaryGreen;
      default: return AppConstants.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border(left: BorderSide(color: _statusColor, width: 4)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.orderReference,
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppConstants.onSurfaceVariant)),
                  Text(order.buyerName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('${order.displayName} · ${order.quantityKg.toStringAsFixed(0)} kg',
                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₱${order.totalPrice.toStringAsFixed(0)}',
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: _statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text(order.statusLabel.toUpperCase(),
                      style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w800, color: _statusColor)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Top App Bar ──────────────────────────────────────────────────────────────
// Same pattern as BuyerManagementScreen's own _TopAppBar — copied rather
// than shared, per instruction to keep this change scoped to this file.

class _TopAppBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _TopAppBar({
    required this.title,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: onBack,
              ),
              Expanded(
                child: Text(title,
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: cs.primary),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}