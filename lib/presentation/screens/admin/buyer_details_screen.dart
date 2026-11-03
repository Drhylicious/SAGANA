import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_profile_model.dart';
import '../../../data/repositories/admin_order_repository.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/order_status_style.dart';
import '../../widgets/buyer_status_badge.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

class BuyerDetailsScreen extends StatefulWidget {
  final String buyerId;
  const BuyerDetailsScreen({super.key, required this.buyerId});

  @override
  State<BuyerDetailsScreen> createState() => _BuyerDetailsScreenState();
}

class _BuyerDetailsScreenState extends State<BuyerDetailsScreen> {
  final _repo = BuyerProfileRepository();
  final _orderRepo = AdminOrderRepository();

  BuyerProfileModel? _buyer;
  List<AdminOrderModel> _recentOrders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchAdminView(widget.buyerId),
      _orderRepo.fetchOrders(buyerId: widget.buyerId),
    ]);
    if (!mounted) return;
    setState(() {
      _buyer = results[0] as BuyerProfileModel?;
      _recentOrders = (results[1] as List<AdminOrderModel>).take(10).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n   = AppLocalizations.of(context);
    final cs     = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // Read-only: Buyer Details only shows the buyer. Send Notification and
      // View Orders live in the Buyer Management three-dot menu.
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: _buyer?.fullName ?? l10n.buyerDetailsTitle,
              onBack: () => context.pop(),
              cs: cs,
            ),
            Expanded(
              child: _isLoading
                  ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                  : _buyer == null
                      ? _NotFoundState(cs: cs)
                      : RefreshIndicator(
                          color: AppConstants.primaryGreen,
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                            children: [
                          BuyerIdentityCard(buyer: _buyer!, cs: cs, sagana: sagana),
                              const SizedBox(height: 16),
                          _StatsRow(buyer: _buyer!, cs: cs, sagana: sagana),
                              const SizedBox(height: 16),
                              _RecentOrdersSection(
                                orders: _recentOrders,
                                totalOrders: _buyer!.totalOrders,
                                cs: cs,
                                sagana: sagana,
                                onOrderTap: (orderId) => context.push(
                                  AppRoutes.adminOrderDetail,
                                  extra: {'orderId': orderId, 'readOnly': true},
                                ),
                                onViewAll: () => context.push(
                                  AppRoutes.buyerOrderHistory,
                                  extra: {
                                    'buyerId': _buyer!.userId,
                                    'buyerName': _buyer!.fullName,
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final ColorScheme cs;
  const _TopBar({required this.title, required this.onBack, required this.cs});

  @override
  Widget build(BuildContext context) {
    return SubPageTopBar(title: title, onBack: onBack);
  }
}

// Photo and name, centred in one compact card, with the status badge in its
// top-right corner. No e-mail or phone: contact details are reached through the
// order workflows, not repeated here (they stay stored, and are not read).
class BuyerIdentityCard extends StatelessWidget {
  final BuyerProfileModel buyer;
  final ColorScheme cs;
  final SaganaColors sagana;
  const BuyerIdentityCard({
    required this.buyer,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = buyerStatusOf(buyer);
    final statusColor = buyerStatusColor(context, status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Stack(
        children: [
          // Spans the whole card, so the photo and name are centred in it
          // while the status badge below stays in the corner.
          SizedBox(
            width: double.infinity,
            child: Column(
            children: [
              // The ring takes the status colour, so the state reads at a glance.
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withValues(alpha: 0.08),
                  border: Border.all(color: statusColor, width: 3),
                ),
                child: buyer.hasPhoto
                    ? ClipOval(
                        child: Image.network(
                          buyer.profilePhotoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallback(statusColor),
                        ),
                      )
                    : _fallback(statusColor),
              ),
              const SizedBox(height: 14),
              Text(
                buyer.fullName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              // Why the account is Inactive, only when it is.
              if (status == BuyerStatus.inactive) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.buyerStatusInactiveNote,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ],
            ),
          ),
          // The status badge sits in the top-right corner of the card. It is laid
          // over the card rather than in its own row, so it adds no height.
          Positioned(
            top: 0,
            right: 0,
            child: BuyerStatusBadge(status: status),
          ),
        ],
      ),
    );
  }

  Widget _fallback(Color color) {
    return Center(
      child: Text(
        buyer.initials,
        style: GoogleFonts.poppins(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final BuyerProfileModel buyer;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _StatsRow({
    required this.buyer,
    required this.cs,
    required this.sagana,
  });

  // KPI-tile visual language — mirrors Admin Marketplace Dashboard's
  // _KpiStrip/_KpiTile (icon chip + tinted border/bg per stat, bold value)
  // instead of the flat neutral tile used previously, same restyle
  // already applied to the Buyer's own Purchase Summary on their Profile
  // tab. Values are unchanged — real order stats from fetchAdminView,
  // never hardcoded.
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget tile(String label, String value, IconData icon, Color color) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  label,
                    style: GoogleFonts.inter(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );

    return Row(
      children: [
        tile(
          l10n.buyerDetailsTotalOrders,
          '${buyer.totalOrders}',
          Icons.shopping_bag_rounded,
          AppConstants.buyerBlue,
        ),
        const SizedBox(width: 10),
        tile(
          l10n.statCompleted,
          '${buyer.completedOrders}',
          Icons.check_circle_rounded,
          AppConstants.successGreen,
        ),
        const SizedBox(width: 10),
        tile(
          l10n.buyerDetailsTotalSpent,
          '₱${buyer.totalSpent.toStringAsFixed(0)}',
          Icons.payments_rounded,
          AppConstants.primaryGreen,
        ),
      ],
    );
  }
}

// Replaces the old single "Order History" link card, which navigated
// straight into the fully-actionable OrderManagementScreen — the critical
// bug this phase fixes (an admin could approve/cancel/complete a buyer's
// order from inside their profile). Now shows the 5 most recent orders
// inline (read-only rows) plus a "View All" link into the new dedicated,
// genuinely read-only BuyerOrderHistoryScreen.
class _RecentOrdersSection extends StatelessWidget {
  final List<AdminOrderModel> orders;
  final int totalOrders;
  final ColorScheme cs;
  final SaganaColors sagana;
  final ValueChanged<String> onOrderTap;
  final VoidCallback onViewAll;

  const _RecentOrdersSection({
    required this.orders,
    required this.totalOrders,
    required this.cs,
    required this.sagana,
    required this.onOrderTap,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.buyerOrderHistoryTitleGeneric,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const Spacer(),
            if (totalOrders > 0)
              GestureDetector(
                onTap: onViewAll,
                child: Text(
                  l10n.listingsAllButton,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (orders.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: sagana.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
            ),
            child: Text(
              l10n.buyerOrderHistoryNoOrdersYet,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          // As tall as its rows, capped at 320: a Buyer with two orders no
          // longer gets a mostly empty box, and one with ten scrolls inside it.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.separated(
              shrinkWrap: true,
              // No automatic status-bar padding: this list sits inside a bigger scroll view.
              padding: EdgeInsets.zero,
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _RecentOrderRow(
                order: orders[i],
                cs: cs,
                sagana: sagana,
                onTap: () => onOrderTap(orders[i].id),
              ),
            ),
          ),
      ],
    );
  }
}

class _RecentOrderRow extends StatelessWidget {
  final AdminOrderModel order;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onTap;
  const _RecentOrderRow({
    required this.order,
    required this.cs,
    required this.sagana,
    required this.onTap,
  });

  Color get _statusColor => orderStatusColor(order.status);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border(left: BorderSide(color: _statusColor, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.displayName,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    '${order.orderReference} · ${formatQuantityUnit(order.quantityKg, order.unit)}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              formatPesos(order.totalPrice),
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppConstants.primaryGreen,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 18, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  final ColorScheme cs;
  const _NotFoundState({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_off_outlined,
              size: 48,
              color: cs.outline.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context).buyerDetailsNotFound,
                style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
