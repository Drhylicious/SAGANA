import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_utils.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/consumer_order_row.dart';
import '../../../data/repositories/buyer_order_repository.dart';
import '../../../data/repositories/cooperative_order_repository.dart';
import '../../widgets/order_payment_widgets.dart' show OrderSourceBadge;
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/table_change_watcher.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/listing_filter_modal.dart' show ListingStatusFilterChip;
import '../../widgets/order_status_style.dart';
import '../../../core/utils/order_status.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/skeleton.dart';

// Phase 13 — farmer-as-buyer order history, under Profile -> Farm Records.
// Mirrors Phase 8's redesigned Buyer Orders screen (search + status pill
// row + single filtered list, no TabBar) with Farm Records' own pushed-
// screen chrome (FarmerTopBar back button, offline banner — same as
// farmer_transaction_history_screen.dart, its sibling row). Reuses
// BuyerOrderRepository/BuyerOrderModel directly since orders are scoped by
// buyer_id = current user regardless of whether that user is a Buyer or a
// Farmer-as-buyer (Phase 1 already made place_order() accept either role).
class FarmerOrdersScreen extends StatefulWidget {
  const FarmerOrdersScreen({super.key});

  @override
  State<FarmerOrdersScreen> createState() => _FarmerOrdersScreenState();
}

const List<String?> _kStatuses = [null, ...kOrderStatuses];

class _FarmerOrdersScreenState extends State<FarmerOrdersScreen> {
  final _repo = BuyerOrderRepository();
  final _coopRepo = CooperativeOrderRepository();
  final _searchCtrl = TextEditingController();

  List<ConsumerOrderRow> _allOrders = [];
  String? _statusFilter;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isOnline = true;
  TableChangeWatcher? _orderWatcher;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _searchCtrl.addListener(
      () => setState(() => _searchQuery = _searchCtrl.text),
    );
    _load();
    _orderWatcher = TableChangeWatcher(
      tables: const ['orders', 'program_product_purchases'],
      onChange: () {
        if (mounted) _load(silent: true);
      },
    )..start();
  }

  @override
  void dispose() {
    _orderWatcher?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final market = await _repo.fetchMyOrders();
    final coop = await _coopRepo.fetchMyOrders();
    if (!mounted) return;
    setState(() {
      _allOrders = mergeConsumerOrders(market, coop);
      _isLoading = false;
    });
  }

  List<ConsumerOrderRow> get _filtered {
    var list = _statusFilter == null
        ? _allOrders
        : _allOrders.where((o) => o.status == _statusFilter);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where(
        (o) =>
            o.title.toLowerCase().contains(q) ||
            o.reference.toLowerCase().contains(q),
      );
    }
    return list.toList();
  }

  Color _statusColor(String? status, ColorScheme cs) {
    if (status == null) return cs.primary; // null = "All"
    return orderStatusColor(status);
  }

  // Same dynamic banner my_orders_screen.dart uses — was missing here
  // entirely, so a farmer with approved orders never got the same
  // "ready for pickup/delivery" notice a buyer in the identical
  // situation sees. Title/body branch on the actual mix of fulfillment
  // methods among the approved orders, same as Buyer's version.
  Widget _buildApprovedBanner(
    AppLocalizations l10n,
    List<ConsumerOrderRow> approved,
  ) {
    final pickupCount = approved.where((o) => o.isPickup).length;
    final deliveryCount = approved.where((o) => o.isDelivery).length;
    final count = approved.length;

    final String title;
    final String body;
    if (deliveryCount == 0) {
      title = l10n.buyerOrdersPickupBannerTitle;
      body = l10n.buyerOrdersPickupBannerBody(
        count,
        AppConstants.cooperativeName,
      );
    } else if (pickupCount == 0) {
      title = l10n.buyerOrdersDeliveryBannerTitle;
      body = l10n.buyerOrdersDeliveryBannerBody(count);
    } else {
      title = l10n.buyerOrdersMixedBannerTitle;
      body = l10n.buyerOrdersMixedBannerBody(count);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.successGreen.withValues(alpha: 0.08),
        border: Border.all(
          color: AppConstants.successGreen.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppConstants.successGreen,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _emptyMessage(AppLocalizations l10n) {
    switch (_statusFilter) {
      case 'pending':
        return l10n.buyerOrdersEmptyPending;
      case 'approved':
        return l10n.buyerOrdersEmptyApproved;
      case 'completed':
        return l10n.buyerOrdersEmptyCompleted;
      case 'cancelled':
        return l10n.buyerOrdersEmptyCancelled;
      case null:
        return l10n.buyerOrdersEmptyAll;
      default:
        return l10n.ordersEmptyStatus(
          buyerOrderStatusLabel(_statusFilter!, l10n),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final visible = _filtered;
    // Orders the consumer can now collect or has been sent (the banner's subject).
    final approved = _allOrders
        .where(
          (o) =>
              o.status == 'ready_for_pickup' ||
              o.status == 'out_for_delivery' ||
              o.status == 'delivered',
        )
        .toList();

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const TopBarSpacer(height: 72),
                    CachedDataNotice(
                      screen: 'orders',
                      isOnline: _isOnline,
                      offlineMessage: AppLocalizations.of(
                        context,
                      ).offlineOrders,
                    ),
                    if (approved.isNotEmpty)
                      _buildApprovedBanner(l10n, approved),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final status in _kStatuses) ...[
                            ListingStatusFilterChip(
                              label: status == null
                                  ? l10n.farmerMgmtAllFilter
                                  : buyerOrderStatusLabel(status, l10n),
                              // "Label (n)": how many orders the chip holds.
                              count: status == null
                                  ? _allOrders.length
                                  : _allOrders
                                        .where((o) => o.status == status)
                                        .length,
                              active: _statusFilter == status,
                              color: _statusColor(status, cs),
                              onTap: () =>
                                  setState(() => _statusFilter = status),
                              cs: cs,
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: SkeletonList(),
                            )
                          : visible.isEmpty
                          ? Center(
                              child: Text(
                                _emptyMessage(l10n),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              color: Theme.of(context).colorScheme.primary,
                              onRefresh: _load,
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  24,
                                ),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, i) =>
                                    _OrderCard(order: visible[i]),
                              ),
                            ),
                    ),
                  ],
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FarmerTopBar(
                    title: l10n.buyerOrdersTitle,
                    onBack: () => Navigator.of(context).pop(),
                    hideProfileAvatar: true,
                    onProfileTap: () {},
                    onNotificationTap: () {},
                    showNotificationButton: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order Card — same shape as Buyer's own order card, with farmer-context
// navigation targets (Farmer Marketplace/Listing tab, not Buyer Browse).
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final ConsumerOrderRow order;
  const _OrderCard({required this.order});

  Color get _statusColor => orderStatusColor(order.status);

  void _openDetail(BuildContext context) {
    context.pushRoute(
      order.isCooperative
          ? AppRoutes.farmerProgramOrderDetail
          : AppRoutes.farmerOrderDetail,
      extra: order.id,
    );
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
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
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
                    child: order.photoUrl != null
                        ? Image.network(
                            order.photoUrl!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 52,
                            height: 52,
                            color: AppConstants.limeGreen,
                            child: Icon(
                              Icons.eco_rounded,
                              size: 22,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
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
                              child: Text(
                                order.title,
                                style: GoogleFonts.poppins(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                buyerOrderStatusLabel(order.status, l10n),
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: _statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${order.reference} · ${_formatDate(order.createdAt)}',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                letterSpacing: 0.3,
                              ),
                            ),
                            if (order.isCooperative)
                              const OrderSourceBadge(
                                source: kOrderSourceCooperative,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.10),
              ),
              const SizedBox(height: 10),
              if (order.hasFulfillmentChoice) ...[
                Row(
                  children: [
                    Icon(
                      order.isPickup
                          ? Icons.storefront_rounded
                          : Icons.local_shipping_outlined,
                      size: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 5),
                    Flexible(child: Text(
                      order.isPickup
                          ? l10n.checkoutFulfillmentPickup
                          : l10n.checkoutFulfillmentDelivery,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )),
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
                          Text(
                            l10n.buyerOrdersQuantityLabel,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            order.quantityLabel,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            l10n.buyerOrdersTotalLabel,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '₱${order.total.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Text(
                  l10n.buyerOrdersCancelledOn(_formatDate(order.updatedAt)),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: _buildActionButton(context, l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, AppLocalizations l10n) {
    switch (order.status) {
      case 'approved':
      case 'ready_for_pickup':
      case 'out_for_delivery':
      case 'delivered':
        return PrimaryButton(
          label: order.canConfirmReceipt
              ? l10n.buyerOrderReceivedAction
              : (order.isWaitingForPayment
                    ? l10n.uoWaitingPaymentTitle
                    : l10n.buyerOrdersViewDetails),
          height: 40,
          onPressed: () => _openDetail(context),
        );
      case 'completed':
        return OutlinedButton(
          onPressed: order.listingId == null
              ? () => context.goTab(AppRoutes.myListings)
              : () => context.pushRoute(
                  AppRoutes.farmerMarketplaceListingDetail,
                  extra: order.listingId,
                ),
          child: Text(l10n.buyerOrdersReorder),
        );
      case 'cancelled':
        return OutlinedButton(
          onPressed: () => context.goTab(AppRoutes.myListings),
          child: Text(l10n.buyerOrdersBrowseAgain),
        );
      default: // pending — no action
        return Row(
          children: [
            const Icon(
              Icons.schedule_rounded,
              size: 14,
              color: AppConstants.warningAmber,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.buyerOrdersAwaitingReview,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
    }
  }

  String _formatDate(DateTime d) => AppUtils.formatListingDate(d);
}
