import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/admin_order_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/listing_filter_modal.dart' show ListingStatusFilterChip;
import '../../widgets/web_safe_blur_container.dart';

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

class _OrderManagementScreenState extends State<OrderManagementScreen> {
  final _repo = AdminOrderRepository();
  final _searchCtrl = TextEditingController();

  // null = "All". Replaces the previous TabBar — All Listings/Pending
  // Review both use this same pill-chip filter style, so Order Management
  // now matches instead of being the one screen with a different filter
  // widget and different interaction model (see M-marketplace-3).
  String? _statusFilter;

  List<AdminOrderModel> _allOrders = [];
  bool _isLoading = true;
  bool _hasLoadedOnce = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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

  List<AdminOrderModel> _byStatus(String? status) {
    var list = status == null ? _allOrders : _allOrders.where((o) => o.status == status);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((o) =>
          o.buyerName.toLowerCase().contains(q) ||
          o.cropName.toLowerCase().contains(q) ||
          o.orderReference.toLowerCase().contains(q));
    }
    return list.toList();
  }

  String get _emptyMessage {
    switch (_statusFilter) {
      case 'pending': return 'No pending orders';
      case 'approved': return 'No approved orders';
      case 'completed': return 'No completed orders';
      case 'cancelled': return 'No cancelled orders';
      default: return 'No orders yet';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = _byStatus(_statusFilter);

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
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              children: [
                // Same plain-pill style as Pending Approval / Offer to
                // Cooperative now (no count badge) — the instant, no-reload
                // switching behavior this screen already had is unchanged,
                // only the chip's own look changed.
                ListingStatusFilterChip(
                  label: 'All', active: _statusFilter == null,
                  color: cs.primary, onTap: () => setState(() => _statusFilter = null), cs: cs,
                ),
                const SizedBox(width: 8),
                ListingStatusFilterChip(
                  label: 'Pending', active: _statusFilter == 'pending',
                  color: AppConstants.warningAmber, onTap: () => setState(() => _statusFilter = 'pending'), cs: cs,
                ),
                const SizedBox(width: 8),
                ListingStatusFilterChip(
                  label: 'Approved', active: _statusFilter == 'approved',
                  color: AppConstants.successGreen, onTap: () => setState(() => _statusFilter = 'approved'), cs: cs,
                ),
                const SizedBox(width: 8),
                ListingStatusFilterChip(
                  label: 'Completed', active: _statusFilter == 'completed',
                  color: AppConstants.primaryGreen, onTap: () => setState(() => _statusFilter = 'completed'), cs: cs,
                ),
                const SizedBox(width: 8),
                ListingStatusFilterChip(
                  label: 'Cancelled', active: _statusFilter == 'cancelled',
                  color: AppConstants.errorRed, onTap: () => setState(() => _statusFilter = 'cancelled'), cs: cs,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildList(visible, _emptyMessage),
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
      case 'cancelled': return AppConstants.errorRed;
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
// Now delegates its blur to the shared WebSafeBlurContainer (same
// consolidation already applied to GlassCard and crop_listing_screen.dart's
// _CropCard) rather than keeping its own independent BackdropFilter copy.

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

    return SizedBox(
      height: 64,
      child: WebSafeBlurContainer(
        blurSigma: 20,
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
    );
  }
}