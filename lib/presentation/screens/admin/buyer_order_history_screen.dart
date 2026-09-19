import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/admin_order_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/listing_filter_modal.dart' show ListingStatusFilterChip;
import '../../widgets/management_modal.dart' show adminOrderStatusLabel;
import '../../widgets/web_safe_blur_container.dart';

/// Read-only order history for one buyer, opened from Buyer Details.
///
/// Buyer Details previously linked straight into OrderManagementScreen
/// (scoped via its optional buyerId param) — which meant an admin could
/// approve/cancel/complete a buyer's pending order from inside their
/// profile, a path that was never meant to allow actions at all. This
/// screen replaces that link: same search + status-chip browsing, but
/// every row opens OrderDetailScreen in its readOnly mode (see
/// admin_order_detail_screen.dart), so no action is reachable from here.
class BuyerOrderHistoryScreen extends StatefulWidget {
  final String buyerId;
  final String? buyerName;

  const BuyerOrderHistoryScreen({super.key, required this.buyerId, this.buyerName});

  @override
  State<BuyerOrderHistoryScreen> createState() => _BuyerOrderHistoryScreenState();
}

class _BuyerOrderHistoryScreenState extends State<BuyerOrderHistoryScreen> {
  final _repo = AdminOrderRepository();
  final _searchCtrl = TextEditingController();

  String? _statusFilter; // null = All
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
          o.cropName.toLowerCase().contains(q) ||
          o.orderReference.toLowerCase().contains(q));
    }
    return list.toList();
  }

  String _emptyMessage(AppLocalizations l10n) {
    switch (_statusFilter) {
      case 'pending': return l10n.buyerOrderHistoryNoPending;
      case 'approved': return l10n.buyerOrderHistoryNoApproved;
      case 'completed': return l10n.buyerOrderHistoryNoCompleted;
      case 'cancelled': return l10n.buyerOrderHistoryNoCancelled;
      default: return l10n.buyerOrderHistoryNoOrdersYet;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final visible = _byStatus(_statusFilter);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _TopAppBar(
            title: widget.buyerName != null
                ? l10n.buyerOrderHistoryTitleFor(widget.buyerName!)
                : l10n.buyerOrderHistoryTitleGeneric,
            onBack: () => context.pop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: l10n.buyerOrderHistorySearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
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
                // Cooperative / All Listings / Order Management now — this
                // screen was built after that redesign and was missed.
                ListingStatusFilterChip(
                  label: l10n.farmerMgmtAllFilter, active: _statusFilter == null,
                  color: cs.primary, onTap: () => setState(() => _statusFilter = null), cs: cs,
                ),
                const SizedBox(width: 8),
                ListingStatusFilterChip(
                  label: adminOrderStatusLabel(l10n, 'pending'), active: _statusFilter == 'pending',
                  color: AppConstants.warningAmber, onTap: () => setState(() => _statusFilter = 'pending'), cs: cs,
                ),
                const SizedBox(width: 8),
                ListingStatusFilterChip(
                  label: adminOrderStatusLabel(l10n, 'approved'), active: _statusFilter == 'approved',
                  color: AppConstants.successGreen, onTap: () => setState(() => _statusFilter = 'approved'), cs: cs,
                ),
                const SizedBox(width: 8),
                ListingStatusFilterChip(
                  label: adminOrderStatusLabel(l10n, 'completed'), active: _statusFilter == 'completed',
                  color: AppConstants.primaryGreen, onTap: () => setState(() => _statusFilter = 'completed'), cs: cs,
                ),
                const SizedBox(width: 8),
                ListingStatusFilterChip(
                  label: adminOrderStatusLabel(l10n, 'cancelled'), active: _statusFilter == 'cancelled',
                  color: AppConstants.errorRed, onTap: () => setState(() => _statusFilter = 'cancelled'), cs: cs,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildList(visible, _emptyMessage(l10n)),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<AdminOrderModel> orders, String emptyMessage) {
    if (orders.isEmpty) {
      return Center(
        child: Text(emptyMessage,
            style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _OrderRow(
          order: orders[i],
          onTap: () => context.push(
            AppRoutes.adminOrderDetail,
            extra: {'orderId': orders[i].id, 'readOnly': true},
          ),
        ),
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
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
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
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                  Text(order.displayName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('${order.quantityKg.toStringAsFixed(0)} kg',
                      style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
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
                  child: Text(adminOrderStatusLabel(l10n, order.status).toUpperCase(),
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
class _TopAppBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _TopAppBar({required this.title, required this.onBack});

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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
