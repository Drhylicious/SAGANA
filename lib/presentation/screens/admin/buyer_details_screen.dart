import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_profile_model.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/management_modal.dart';

class BuyerDetailsScreen extends StatefulWidget {
  final String buyerId;
  const BuyerDetailsScreen({super.key, required this.buyerId});

  @override
  State<BuyerDetailsScreen> createState() => _BuyerDetailsScreenState();
}

class _BuyerDetailsScreenState extends State<BuyerDetailsScreen> {
  final _repo = BuyerProfileRepository();

  BuyerProfileModel? _buyer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final buyer = await _repo.fetchAdminView(widget.buyerId);
    if (!mounted) return;
    setState(() {
      _buyer = buyer;
      _isLoading = false;
    });
  }

  void _showActionsMenu() {
    final buyer = _buyer;
    if (buyer == null) return;
    showManagementModal(
      context: context,
      builder: (_) => _BuyerActionsMenu(
        buyer: buyer,
        onNotify: () {
          Navigator.pop(context);
          context.push(
            AppRoutes.announcementDashboard,
            extra: {'buyerId': buyer.userId, 'buyerName': buyer.fullName},
          );
        },
        onToggleStatus: () async {
          Navigator.pop(context);
          await _repo.setBuyerStatus(
            buyerId: buyer.userId,
            status: buyer.isActive ? 'suspended' : 'active',
          );
          _load();
        },
      ),
    );
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
              onMenu: _buyer != null ? _showActionsMenu : null,
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
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                            children: [
                              _IdentityCard(
                                  buyer: _buyer!, cs: cs, sagana: sagana),
                              const SizedBox(height: 16),
                              _StatsRow(
                                  buyer: _buyer!, cs: cs, sagana: sagana),
                              const SizedBox(height: 16),
                              _OrderHistoryLink(
                                buyer: _buyer!,
                                cs: cs,
                                sagana: sagana,
                                onTap: () => context.push(
                                  AppRoutes.adminOrders,
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
  final VoidCallback? onMenu;
  final ColorScheme cs;
  const _TopBar({
    required this.title,
    required this.onBack,
    this.onMenu,
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
          if (onMenu != null)
            IconButton(
              icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
              onPressed: onMenu,
            ),
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
                  color: (buyer.isActive
                          ? AppConstants.successGreen
                          : cs.outline)
                      .withValues(alpha: 0.10),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  buyer.isActive ? 'Active Buyer' : 'Suspended',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color:
                        buyer.isActive ? AppConstants.successGreen : cs.outline,
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
            '${buyer.sitio != null ? ' • ${buyer.sitio}' : ''}',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          if (buyer.phoneNumber != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    buyer.phoneNumber!,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface),
                  ),
                ],
              ),
            ),
          ],
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

class _OrderHistoryLink extends StatelessWidget {
  final BuyerProfileModel buyer;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onTap;
  const _OrderHistoryLink({
    required this.buyer,
    required this.cs,
    required this.sagana,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Icon(Icons.history_rounded, color: cs.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order History',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                  Text(
                      '${buyer.totalOrders} order${buyer.totalOrders == 1 ? '' : 's'} placed',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.outline),
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

class _BuyerActionsMenu extends StatelessWidget {
  final BuyerProfileModel buyer;
  final VoidCallback onNotify;
  final VoidCallback onToggleStatus;
  const _BuyerActionsMenu({
    required this.buyer,
    required this.onNotify,
    required this.onToggleStatus,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ManagementModalShell(
      title: buyer.fullName,
      subtitle: 'Manage buyer account',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onNotify,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.campaign_outlined, size: 20, color: cs.onSurface),
                  const SizedBox(width: 14),
                  Text('Send Notification',
                      style:
                          GoogleFonts.inter(fontSize: 14, color: cs.onSurface)),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: onToggleStatus,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(
                    buyer.isActive
                        ? Icons.block_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 20,
                    color: buyer.isActive ? cs.error : cs.onSurface,
                  ),
                  const SizedBox(width: 14),
                  Text(
                    buyer.isActive ? 'Suspend Account' : 'Reactivate Account',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: buyer.isActive ? cs.error : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}