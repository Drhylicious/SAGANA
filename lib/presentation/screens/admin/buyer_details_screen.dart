import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_profile_model.dart';
import '../../../data/repositories/admin_order_repository.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../routes/app_routes.dart';

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
    final cs     = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: _buyer?.fullName ?? 'Buyer Details',
              onBack: () => context.pop(),
              cs: cs,
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppConstants.primaryGreen))
                  : _buyer == null
                      ? _NotFoundState(cs: cs)
                      : RefreshIndicator(
                          color: AppConstants.primaryGreen,
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                            children: [
                              _IdentityCard(
                                  buyer: _buyer!, cs: cs, sagana: sagana),
                              const SizedBox(height: 16),
                              _StatsRow(
                                  buyer: _buyer!, cs: cs, sagana: sagana),
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
      bottomNavigationBar: _buyer == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(
                          AppRoutes.announcementDashboard,
                          extra: {
                            'buyerId': _buyer!.userId,
                            'buyerName': _buyer!.fullName,
                          },
                        ),
                        icon: const Icon(Icons.campaign_outlined, size: 18),
                        label: Text('Notify',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await _repo.setBuyerStatus(
                            buyerId: _buyer!.userId,
                            status:
                                _buyer!.isActive ? 'suspended' : 'active',
                          );
                          _load();
                        },
                        style: _buyer!.isActive
                            ? ElevatedButton.styleFrom(
                                backgroundColor: AppConstants.errorRed)
                            : null,
                        icon: Icon(
                          _buyer!.isActive
                              ? Icons.block_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _buyer!.isActive ? 'Suspend' : 'Reactivate',
                          style:
                              GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final ColorScheme cs;
  const _TopBar({
    required this.title,
    required this.onBack,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w700, color: cs.primary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // The "..." menu that used to live here (Send Notification /
          // Suspend Account) was removed — both actions are already always
          // visible in the bottom bar, so the menu was pure duplication.
        ],
      ),
    );
  }
}

// Badge sits in its own full-width Row, not a Positioned-in-Stack — built
// correctly from the start this time, same fix as farmer_details_screen.dart.
class _IdentityCard extends StatelessWidget {
  final BuyerProfileModel buyer;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _IdentityCard(
      {required this.buyer, required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _badgeColor(buyer, cs).withValues(alpha: 0.10),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  _badgeLabel(buyer),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _badgeColor(buyer, cs),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppConstants.buyerBlue.withValues(alpha: 0.10),
              border: Border.all(color: AppConstants.buyerBlue, width: 3),
            ),
            child: buyer.hasPhoto
                ? ClipOval(
                    child: Image.network(
                      buyer.profilePhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _fallback(),
                    ),
                  )
                : _fallback(),
          ),
          const SizedBox(height: 12),
          Text(
            buyer.fullName,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            'Buyer since ${buyer.joinedLabel}'
            '${buyer.purok != null ? ' • ${buyer.purok}' : ''}',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          // Every Edit Profile field always renders here, populated or
          // not (placeholder "–" when empty) — previously phone/email
          // only showed up when set, and birth date/gender didn't exist
          // here at all.
          _fieldRow(Icons.phone_rounded, buyer.phoneNumber, cs),
          const SizedBox(height: 8),
          _fieldRow(Icons.email_rounded, buyer.contactEmail, cs),
          const SizedBox(height: 8),
          _fieldRow(Icons.cake_rounded, buyer.dateOfBirthLabel, cs),
          const SizedBox(height: 8),
          _fieldRow(Icons.person_outline_rounded, buyer.genderLabel, cs),
        ],
      ),
    );
  }

  Widget _fieldRow(IconData icon, String? value, ColorScheme cs) {
    final hasValue = value != null && value.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: hasValue ? cs.primary : cs.outline),
          const SizedBox(width: 8),
          Text(
            hasValue ? value : '–',
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hasValue ? cs.onSurface : cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _fallback() {
    return Center(
      child: Text(
        buyer.initials,
        style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppConstants.buyerBlue),
      ),
    );
  }

  String _badgeLabel(BuyerProfileModel buyer) {
    if (!buyer.isActive) return 'Suspended';
    if (buyer.isInactive) return 'Inactive';
    return 'Active Buyer';
  }

  Color _badgeColor(BuyerProfileModel buyer, ColorScheme cs) {
    if (!buyer.isActive) return cs.outline;
    if (buyer.isInactive) return AppConstants.warningAmber;
    return AppConstants.successGreen;
  }
}

class _StatsRow extends StatelessWidget {
  final BuyerProfileModel buyer;
  final ColorScheme cs;
  final SaganaColors sagana;
  const _StatsRow(
      {required this.buyer, required this.cs, required this.sagana});

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, String value, IconData icon) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sagana.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: cs.primary),
                const SizedBox(height: 8),
                Text(value,
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
                Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 10, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        tile('Total Orders', '${buyer.totalOrders}',
            Icons.shopping_bag_outlined),
        const SizedBox(width: 10),
        tile('Completed', '${buyer.completedOrders}',
            Icons.check_circle_outline_rounded),
        const SizedBox(width: 10),
        tile('Total Spent', '₱${buyer.totalSpent.toStringAsFixed(0)}',
            Icons.payments_outlined),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Order History',
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const Spacer(),
            if (totalOrders > 0)
              GestureDetector(
                onTap: onViewAll,
                child: Text('View All',
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
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
            child: Text('No orders yet',
                style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
          )
        else
          // Bounded height with its own internal scroll — up to 10 rows
          // rendered, but this section no longer stretches the whole page
          // to fit them all; only ~4-5 show at once, the rest scroll
          // within this box.
          SizedBox(
            height: 320,
            child: ListView.separated(
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
  const _RecentOrderRow({required this.order, required this.cs, required this.sagana, required this.onTap});

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
                  Text(order.displayName,
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
                  Text('${order.orderReference} · ${order.quantityKg.toStringAsFixed(0)} kg',
                      style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Text('₱${order.totalPrice.toStringAsFixed(0)}',
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
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
            Icon(Icons.person_off_outlined,
                size: 48, color: cs.outline.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('Buyer not found',
                style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

