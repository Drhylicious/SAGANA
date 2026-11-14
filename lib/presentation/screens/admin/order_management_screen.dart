import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/table_change_watcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../data/models/program_model.dart' show ProgramPurchase;
import '../../../data/models/staff_order_row.dart';
import '../../../data/repositories/admin_order_repository.dart';
import '../../../data/repositories/cooperative_order_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/listing_filter_modal.dart'
    show MarketplaceFilterBar, MarketplaceFilterOption;
import '../../widgets/management_modal.dart' show adminOrderStatusLabel;
import '../../widgets/choice_filter_modal.dart';
import '../../widgets/filter_icon_button.dart';
import '../../widgets/order_payment_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/order_status_style.dart';
import '../../../core/utils/order_status.dart';

/// Staff order list: Marketplace orders and Cooperative Product orders in ONE list.
///
/// The two kinds stay separate records (and separate workflows) in the database; this screen
/// only shows them together. A source selector narrows the list, every row carries a source
/// badge, and the status chips are the six staff statuses plus All and Needs Action. A
/// delivery that was handed over and paid is filed under Out for Delivery and says so.
class OrderManagementScreen extends StatefulWidget {
  /// When set, the screen opens pre-filtered to one buyer's orders —
  /// reused by BuyerManagementScreen's "View Order History" instead of
  /// building a second order-browsing screen. Cooperative orders belong to
  /// Farmers, so that view shows Marketplace orders only.
  final String? buyerId;
  final String? buyerName;

  /// A filter to open on (the Marketplace dashboard opens Needs Action).
  final String? initialFilter;

  const OrderManagementScreen({
    super.key,
    this.buyerId,
    this.buyerName,
    this.initialFilter,
  });

  @override
  State<OrderManagementScreen> createState() => _OrderManagementScreenState();
}

class _OrderManagementScreenState extends State<OrderManagementScreen> {
  final _repo = AdminOrderRepository();
  final _coopRepo = CooperativeOrderRepository();
  final _searchCtrl = TextEditingController();

  // null = "All".
  late String? _statusFilter = widget.initialFilter;
  // null = both sources.
  String? _sourceFilter;

  List<StaffOrderRow> _allOrders = [];
  bool _isLoading = true;
  bool _hasLoadedOnce = false;
  bool _isOnline = ConnectivityService.instance.isOnline;
  String _searchQuery = '';
  TableChangeWatcher? _orderWatcher;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _searchCtrl.addListener(
      () => setState(() => _searchQuery = _searchCtrl.text),
    );
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
    // A Buyer or Farmer placing or cancelling an order shows up here without a refresh.
    _orderWatcher = TableChangeWatcher(
      tables: const ['orders', 'program_product_purchases'],
      onChange: () {
        if (mounted) _load();
      },
    )..start();
  }

  @override
  void dispose() {
    _orderWatcher?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_hasLoadedOnce) setState(() => _isLoading = true);
    final marketplace = await _repo.fetchOrders(buyerId: widget.buyerId);
    final cooperative = widget.buyerId != null
        ? const <ProgramPurchase>[]
        : await _coopRepo.fetchAllOrders();
    if (!mounted) return;
    setState(() {
      _allOrders = mergeStaffOrders(marketplace, cooperative);
      _isLoading = false;
      _hasLoadedOnce = true;
    });
  }

  // Rows of the chosen source (the status chips count inside it).
  List<StaffOrderRow> get _inSource =>
      filterStaffOrders(_allOrders, source: _sourceFilter);

  // How many orders each status chip holds, inside the chosen source.
  Map<String, int> get _statusCounts {
    final counts = <String, int>{};
    for (final o in _inSource) {
      counts[o.displayStatus] = (counts[o.displayStatus] ?? 0) + 1;
    }
    return counts;
  }

  int _sourceCount(String? source) => source == null
      ? _allOrders.length
      : _allOrders.where((o) => o.source == source).length;

  String _emptyMessage(AppLocalizations l10n) {
    switch (_statusFilter) {
      case 'pending':
        return l10n.buyerOrderHistoryNoPending;
      case 'approved':
        return l10n.buyerOrderHistoryNoApproved;
      case 'completed':
        return l10n.buyerOrderHistoryNoCompleted;
      case 'cancelled':
        return l10n.buyerOrderHistoryNoCancelled;
      case kOrderNeedsActionFilter:
        return l10n.orderMgmtNoNeedsAction;
      case null:
        return l10n.buyerOrderHistoryNoOrdersYet;
      default:
        return l10n.ordersEmptyStatus(
          adminOrderStatusLabel(l10n, _statusFilter!),
        );
    }
  }

  Future<void> _openFilter() async {
    final l10n = AppLocalizations.of(context);
    final result = await showChoiceFilterModal<String?>(
      context,
      title: l10n.omFilterTitle,
      subtitle: l10n.omFilterSubtitle,
      sectionLabel: l10n.omFilterSource,
      selected: _sourceFilter,
      resetTo: null,
      choices: [
        FilterChoice<String?>(
          null,
          '${l10n.uoSourceAll} (${_sourceCount(null)})',
        ),
        FilterChoice<String?>(
          kOrderSourceMarketplace,
          '${l10n.uoSourceMarketplace} (${_sourceCount(kOrderSourceMarketplace)})',
        ),
        FilterChoice<String?>(
          kOrderSourceCooperative,
          '${l10n.uoSourceCooperative} (${_sourceCount(kOrderSourceCooperative)})',
        ),
      ],
    );
    if (result != null && mounted) setState(() => _sourceFilter = result.value);
  }

  Future<void> _open(StaffOrderRow row) async {
    if (row.isCooperative) {
      await context.push(AppRoutes.adminProgramOrderDetail, extra: row.id);
    } else {
      await context.push(AppRoutes.adminOrderDetail, extra: row.id);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final visible = filterStaffOrders(
      _allOrders,
      source: _sourceFilter,
      status: _statusFilter,
      query: _searchQuery,
    );
    final inSource = _inSource;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _TopAppBar(
            title: widget.buyerName != null
                ? l10n.orderMgmtTitleFor(widget.buyerName!)
                : l10n.orderMgmtTitleGeneric,
            onBack: () => context.pop(),
            // Pickup / Delivery settings live here: a Manager changes them, an Officer views them.
            trailing: widget.buyerId != null
                ? null
                : IconButton(
                    key: const Key('orderSettings'),
                    tooltip: l10n.dsTitle,
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () =>
                        context.push(AppRoutes.adminDeliverySettings),
                  ),
          ),
          CachedDataNotice(
            screen: 'orders_all_all',
            isOnline: _isOnline,
            offlineMessage: l10n.offlineOrders,
          ),
          // Search, and the shared filter button beside it (the source of the order: All sources,
          // Marketplace or Cooperative). One buyer's history is Marketplace only, so no filter there.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: l10n.orderMgmtSearchHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                if (widget.buyerId == null) ...[
                  const SizedBox(width: 10),
                  FilterIconButton(
                    buttonKey: const Key('orderFilterButton'),
                    dotKey: const Key('orderFilterDot'),
                    semanticLabel: l10n.omFilterTitle,
                    active: _sourceFilter != null,
                    onTap: _openFilter,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          MarketplaceFilterBar<String?>(
            key: const Key('statusFilter'),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            selected: _statusFilter,
            onSelected: (v) => setState(() => _statusFilter = v),
            options: [
              MarketplaceFilterOption<String?>(
                value: null,
                label: l10n.farmerMgmtAllFilter,
                count: inSource.length,
                color: cs.primary,
              ),
              MarketplaceFilterOption<String?>(
                value: kOrderNeedsActionFilter,
                label: l10n.orderMgmtChipNeedsAction,
                count: inSource.where((o) => o.needsAction).length,
                color: AppConstants.programPurple,
              ),
              for (final s in kStaffOrderStatuses)
                MarketplaceFilterOption<String?>(
                  value: s,
                  label: s == 'pending'
                      ? l10n.orderMgmtChipPending
                      : adminOrderStatusLabel(l10n, s),
                  count: _statusCounts[s] ?? 0,
                  color: orderStatusColor(s),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : _buildList(visible, _emptyMessage(l10n)),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<StaffOrderRow> orders, String emptyMessage) {
    if (orders.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) =>
            _OrderRow(order: orders[i], onTap: () => _open(orders[i])),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final StaffOrderRow order;
  final VoidCallback onTap;
  const _OrderRow({required this.order, required this.onTap});

  Color get _statusColor => orderStatusColor(order.displayStatus);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      key: Key('orderRow_${order.id}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border(left: BorderSide(color: _statusColor, width: 4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        order.reference,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      OrderSourceBadge(source: order.source),
                    ],
                  ),
                  Text(
                    order.customerName,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${order.itemLabel} · ${order.quantityLabel}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        order.isDelivery
                            ? Icons.local_shipping_outlined
                            : Icons.storefront_rounded,
                        size: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        order.isDelivery
                            ? l10n.checkoutFulfillmentDelivery
                            : l10n.checkoutFulfillmentPickup,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  if (order.awaitingConfirmation) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.uoHandedOver,
                      key: Key('handedOver_${order.id}'),
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatPesos(order.total),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    adminOrderStatusLabel(l10n, order.displayStatus),
                    style: GoogleFonts.inter(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: _statusColor,
                    ),
                  ),
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
  final Widget? trailing;

  const _TopAppBar({required this.title, required this.onBack, this.trailing});

  @override
  Widget build(BuildContext context) {
    return SubPageTopBar(title: title, onBack: onBack, trailing: trailing);
  }
}
