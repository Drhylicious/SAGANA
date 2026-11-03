import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_order_model.dart';
import '../../../data/repositories/buyer_order_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/buyer_top_bar.dart';
import '../../widgets/listing_filter_modal.dart' show ListingStatusFilterChip;
import '../../widgets/order_status_style.dart';
import '../../../core/utils/order_status.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/table_change_watcher.dart';
import '../../widgets/skeleton.dart';

// Same status -> filter color mapping Admin's OrderManagementScreen uses
// for its ListingStatusFilterChip row — reused here rather than
// reinvented, so the chip colors mean the same thing in both places.
Color _orderFilterColor(String? status, ColorScheme cs) {
  if (status == null) return cs.primary; // null = "All"
  return orderStatusColor(status);
}


class MyOrdersScreen extends StatefulWidget {
  final int initialTabIndex;
  const MyOrdersScreen({super.key, this.initialTabIndex = 0});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

// Maps the legacy tab-index contract (still used by app_router.dart and
// buyer_account_screen.dart) onto the status-filter values used by the
// pill-chip filter, so both existing call sites keep working unchanged.
const List<String?> _kTabIndexToStatus = ['pending', 'approved', 'completed', 'cancelled'];

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  final _repository = BuyerOrderRepository();
  final _notificationRepo = NotificationRepository();
  final _searchCtrl = TextEditingController();

  // null = "All" — same convention as Admin's OrderManagementScreen,
  // replacing the previous TabBar so this screen matches Admin's filter
  // widget and interaction model.
  String? _statusFilter;
  String _searchQuery = '';

  bool _isLoading = true;
  List<BuyerOrderModel> _allOrders = [];
  int _unreadCount = 0;
  TableChangeWatcher? _orderWatcher;

  @override
  void initState() {
    super.initState();
    final index = widget.initialTabIndex < 0 || widget.initialTabIndex >= _kTabIndexToStatus.length
        ? 0
        : widget.initialTabIndex;
    _statusFilter = _kTabIndexToStatus[index];
    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text));
    _load();
    AppEventService.instance.addListener(_load);
    // The Manager approving or completing an order shows up here live.
    _orderWatcher = TableChangeWatcher(
      tables: const ['orders'],
      onChange: () {
        if (mounted) _load(silent: true);
      },
    )..start();
  }

  @override
  void dispose() {
    _orderWatcher?.dispose();
    AppEventService.instance.removeListener(_load);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
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

  // Added alongside the notification-staleness fix: a lightweight refresh
  // for just the unread count, so returning from the notifications screen
  // doesn't need to re-fetch the full order list via the full _load().
  Future<void> _loadUnreadCount() async {
    final count = await _notificationRepo.fetchUnreadCount();
    if (!mounted) return;
    setState(() => _unreadCount = count);
  }

  List<BuyerOrderModel> _byStatus(String status) =>
      _allOrders.where((o) => o.status == status).toList();

  List<BuyerOrderModel> _filtered(String? status) {
    var list = status == null ? _allOrders : _allOrders.where((o) => o.status == status);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((o) =>
          o.displayName.toLowerCase().contains(q) ||
          o.orderReference.toLowerCase().contains(q));
    }
    return list.toList();
  }

  String _emptyMessage(AppLocalizations l10n) {
    switch (_statusFilter) {
      case 'pending': return l10n.buyerOrdersEmptyPending;
      case 'approved': return l10n.buyerOrdersEmptyApproved;
      case 'completed': return l10n.buyerOrdersEmptyCompleted;
      case 'cancelled': return l10n.buyerOrdersEmptyCancelled;
      case null: return l10n.buyerOrdersEmptyAll;
      default: return l10n.ordersEmptyStatus(buyerOrderStatusLabel(_statusFilter!, l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    // Orders the consumer can now collect or has been sent (the banner's subject).
    final approved = _allOrders
        .where((o) => o.isReadyForPickup || o.isOutForDelivery || o.isDelivered)
        .toList();
    final visible = _filtered(_statusFilter);

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              TopBarSpacer(height: 64),
              CachedDataNotice(
                screen: 'orders',
                isOnline: ConnectivityService.instance.isOnline,
                offlineMessage: l10n.offlineBuyerBody,
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      if (approved.isNotEmpty) _buildApprovedBanner(approved),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 12, AppConstants.spacingSafeH, 0),
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: l10n.buyerOrdersSearchHint,
                            prefixIcon: const Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 34,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSafeH),
                          scrollDirection: Axis.horizontal,
                          children: [
                            ListingStatusFilterChip(
                              label: l10n.farmerMgmtAllFilter, active: _statusFilter == null,
                              color: _orderFilterColor(null, cs), onTap: () => setState(() => _statusFilter = null), cs: cs,
                            ),
                            const SizedBox(width: 8),
                            for (final s in kOrderStatuses) ...[
                              ListingStatusFilterChip(
                                label: buyerOrderStatusLabel(s, l10n), active: _statusFilter == s,
                                color: _orderFilterColor(s, cs), onTap: () => setState(() => _statusFilter = s), cs: cs,
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _isLoading
                            ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                            : _buildOrderList(visible, _emptyMessage(l10n)),
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
              title: l10n.buyerOrdersTitle,
              unreadCount: _unreadCount,
              onNotificationTap: () async {
                await context.push(AppRoutes.buyerNotifications);
                _loadUnreadCount();
              },
              enableMenu: true,
            ),
          ),
        ],
      ),
    );
  }

  // Dynamic per the actual mix of fulfillment methods among the buyer's
  // approved orders — previously always said "ready for pickup," which
  // was wrong the moment a Delivery order was also approved (its stock
  // isn't sitting at the cooperative waiting to be collected).
  Widget _buildApprovedBanner(List<BuyerOrderModel> approved) {
    final l10n = AppLocalizations.of(context);
    final pickupCount = approved.where((o) => o.isPickupChoice).length;
    final deliveryCount = approved.where((o) => o.isDelivery).length;
    final count = approved.length;

    final String title;
    final String body;
    if (deliveryCount == 0) {
      title = l10n.buyerOrdersPickupBannerTitle;
      body = l10n.buyerOrdersPickupBannerBody(count, AppConstants.cooperativeName);
    } else if (pickupCount == 0) {
      title = l10n.buyerOrdersDeliveryBannerTitle;
      body = l10n.buyerOrdersDeliveryBannerBody(count);
    } else {
      title = l10n.buyerOrdersMixedBannerTitle;
      body = l10n.buyerOrdersMixedBannerBody(count);
    }

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
                Text(title,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                const SizedBox(height: 2),
                Text(
                  body,
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

  Color get _statusColor => orderStatusColor(order.status);

  void _openDetail(BuildContext context) {
    context.push(AppRoutes.orderDetail, extra: order.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEnded = order.isCancelled;

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Opacity(
        opacity: isEnded ? 0.6 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.saganaColors.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border(left: BorderSide(color: _statusColor, width: 4)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                    child: order.listingPhotoUrl != null
                        ? Image.network(order.listingPhotoUrl!, width: 52, height: 52, fit: BoxFit.cover)
                        : Container(width: 52, height: 52, color: AppConstants.limeGreen,
                            child: const Icon(Icons.eco_rounded, size: 22, color: AppConstants.primaryGreen)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(order.displayName,
                                  style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: _statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                              child: Text(buyerOrderStatusLabel(order.status, l10n),
                                  style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: _statusColor)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text('${order.orderReference} · ${_formatDate(order.createdAt)}',
                            style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppConstants.onSurfaceVariant, letterSpacing: 0.3)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: AppConstants.outline.withValues(alpha: 0.10)),
              const SizedBox(height: 10),
              if (order.hasFulfillmentChoice) ...[
                Row(
                  children: [
                    Icon(
                      order.isPickupChoice ? Icons.storefront_rounded : Icons.local_shipping_outlined,
                      size: 13, color: AppConstants.primaryGreen,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      order.isPickupChoice ? l10n.checkoutFulfillmentPickup : l10n.checkoutFulfillmentDelivery,
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (!isEnded)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.saganaColors.scaffoldBackground,
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.buyerOrdersQuantityLabel, style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant)),
                          Text(formatQuantityUnit(order.quantityKg, order.unit), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(l10n.buyerOrdersTotalLabel, style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant)),
                          Text('₱${order.totalPrice.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Text(
                    l10n.buyerOrdersCancelledOn(_formatDate(order.updatedAt)),
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
    final l10n = AppLocalizations.of(context);
    switch (order.status) {
      case 'approved':
      case 'ready_for_pickup':
      case 'out_for_delivery':
      case 'delivered':
        return PrimaryButton(
          label: order.canConfirmReceipt ? l10n.buyerOrderReceivedAction : l10n.buyerOrdersViewDetails,
          height: 40,
          onPressed: () => _openDetail(context),
        );
      case 'completed':
        return OutlinedButton(
          onPressed: () => context.push(AppRoutes.listingDetails, extra: order.listingId),
          child: Text(l10n.buyerOrdersReorder),
        );
      case 'cancelled':
        return OutlinedButton(
          onPressed: () => context.go(AppRoutes.marketplaceBrowse),
          child: Text(l10n.buyerOrdersBrowseAgain),
        );
      default: // pending — no action, matches mockup exactly
        return Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 14, color: AppConstants.warningAmber),
            const SizedBox(width: 6),
            Expanded(
              child: Text(l10n.buyerOrdersAwaitingReview,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
            ),
          ],
        );
    }
  }

  String _formatDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}';
  }
}