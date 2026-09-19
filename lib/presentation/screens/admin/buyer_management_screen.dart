import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_profile_model.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/management_modal.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class BuyerManagementScreen extends StatefulWidget {
  const BuyerManagementScreen({super.key});

  @override
  State<BuyerManagementScreen> createState() => _BuyerManagementScreenState();
}

class _BuyerManagementScreenState extends State<BuyerManagementScreen> {
  final _repo       = BuyerProfileRepository();
  final _searchCtrl = TextEditingController();

  List<BuyerProfileModel> _buyers      = [];
  bool _isLoading = true;
  bool _isOnline  = true;
  String _searchQuery = '';
  // null=all, 'active', 'inactive' (derived, 30-day-idle — see
  // BuyerProfileModel.isInactive), 'suspended'.
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged
        .listen((v) { if (mounted) setState(() => _isOnline = v); });
    _searchCtrl.addListener(() =>
        setState(() => _searchQuery = _searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await _repo.fetchAllBuyers();
    if (!mounted) return;
    setState(() { _buyers = data; _isLoading = false; });
  }

  List<BuyerProfileModel> get _filtered {
    var list = _buyers;
    switch (_statusFilter) {
      case 'active':
        list = list.where((b) => b.isActive && !b.isInactive).toList();
        break;
      case 'inactive':
        list = list.where((b) => b.isInactive).toList();
        break;
      case 'suspended':
        list = list.where((b) => !b.isActive).toList();
        break;
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((b) =>
          b.fullName.toLowerCase().contains(q) ||
          (b.phoneNumber?.contains(q) ?? false) ||
          (b.purok?.toLowerCase().contains(q) ?? false)).toList();
    }
    return list;
  }

  void _showActions(BuyerProfileModel buyer) {
    showManagementModal(
      context: context,
      builder: (_) => _ActionsSheet(
        buyer: buyer,
        isOnline: _isOnline,
        onSendNotification: () {
          Navigator.pop(context);
          context.push(
            AppRoutes.announcementDashboard,
            extra: {'buyerId': buyer.userId, 'buyerName': buyer.fullName},
          );
        },
        onViewOrders: () {
          Navigator.pop(context);
          // Read-only history, not OrderManagementScreen — this used to
          // route into the fully-actionable screen, the same critical bug
          // Buyer Details' Order History link had (see M-marketplace-4).
          context.push(
            AppRoutes.buyerOrderHistory,
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
    final l10n    = AppLocalizations.of(context);
    final sagana  = context.saganaColors;
    final cs      = Theme.of(context).colorScheme;
    final visible = _filtered;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(
                          color: AppConstants.primaryGreen))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
                          children: [
                            // KPI cards removed — the status filter tabs
                            // below already surface the same Total/Active/
                            // Inactive/Suspended breakdown, so the cards
                            // were purely redundant.

                            // ── Search ───────────────────────────────────
                            TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: l10n.buyerMgmtSearchHint,
                                hintStyle: GoogleFonts.inter(
                                    fontSize: 13, color: cs.outline),
                                prefixIcon: Icon(Icons.search_rounded,
                                    color: cs.outline, size: 22),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.close_rounded,
                                            color: cs.outline, size: 18),
                                        onPressed: () =>
                                            _searchCtrl.clear())
                                    : null,
                              ),
                              style: GoogleFonts.inter(
                                  fontSize: 14, color: cs.onSurface),
                            ),
                            const SizedBox(height: 12),

                            // ── Status tabs ───────────────────────────────
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
                                _TextTab(label: l10n.farmerMgmtAllFilter,
                                    active: _statusFilter == null,
                                    onTap: () => setState(
                                        () => _statusFilter = null),
                                    cs: cs),
                                _TextTab(label: l10n.farmerMgmtStatusActiveLabel,
                                    active: _statusFilter == 'active',
                                    onTap: () => setState(
                                        () => _statusFilter = 'active'),
                                    cs: cs),
                                _TextTab(label: l10n.analyticsInactive,
                                    active: _statusFilter == 'inactive',
                                    onTap: () => setState(
                                        () => _statusFilter = 'inactive'),
                                    cs: cs),
                                _TextTab(label: l10n.farmerMgmtStatusSuspendedLabel,
                                    active: _statusFilter == 'suspended',
                                    onTap: () => setState(
                                        () => _statusFilter = 'suspended'),
                                    cs: cs),
                              ]),
                            ),
                            const SizedBox(height: 12),

                            // ── Buyer cards ──────────────────────────────
                            if (visible.isEmpty)
                              _EmptyState(cs: cs)
                            else
                              ...visible.map((b) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: _BuyerCard(
                                      buyer: b,
                                      cs: cs,
                                      sagana: sagana,
                                      onTap: () => context.push(
                                          AppRoutes.buyerDetails,
                                          extra: b.userId),
                                      onMoreTap: () => _showActions(b),
                                    ),
                                  )),
                          ],
                        ),
                ),
              ),
            ],
          ),

          // ── Top App Bar ─────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: _TopAppBar(
              onBack: () => context.pop(),
              sagana: sagana,
              cs: cs,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top App Bar ──────────────────────────────────────────────────────────────

class _TopAppBar extends StatelessWidget {
  final VoidCallback onBack;
  final SaganaColors sagana;
  final ColorScheme cs;
  const _TopAppBar({required this.onBack, required this.sagana, required this.cs});

  @override
  Widget build(BuildContext context) {
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
                child: Text(AppLocalizations.of(context).buyerMgmtTitle,
                    style: GoogleFonts.poppins(fontSize: 18,
                        fontWeight: FontWeight.w700, color: cs.primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final ColorScheme cs;
  const _TextTab({required this.label, required this.active,
    required this.onTap, required this.cs});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 20),
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? cs.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(label,
            style: GoogleFonts.inter(fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? cs.primary : cs.onSurfaceVariant)),
      ),
    );
  }
}

// ─── Buyer Card ───────────────────────────────────────────────────────────────

class _BuyerCard extends StatelessWidget {
  final BuyerProfileModel buyer;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;
  const _BuyerCard({required this.buyer, required this.cs,
    required this.sagana, required this.onTap, required this.onMoreTap});

  String _badgeLabel(AppLocalizations l10n) {
    if (!buyer.isActive) return l10n.buyerMgmtSuspendedBadge;
    if (buyer.isInactive) return l10n.buyerMgmtInactiveBadge;
    return l10n.buyerMgmtActiveBadge;
  }

  Color _badgeColor(ColorScheme cs) {
    if (!buyer.isActive) return cs.outline;
    if (buyer.isInactive) return AppConstants.warningAmber;
    return AppConstants.successGreen;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: buyer.isActive
            ? cs.outline.withValues(alpha: 0.10)
            : cs.outline.withValues(alpha: 0.06)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: buyer.isActive
                  ? AppConstants.buyerBlue.withValues(alpha: 0.12)
                  : cs.surfaceContainerHighest,
            ),
            child: Center(child: Text(buyer.initials,
                style: GoogleFonts.poppins(fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: buyer.isActive
                        ? AppConstants.buyerBlue
                        : cs.outline))),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(buyer.fullName,
                        style: GoogleFonts.poppins(fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: buyer.isActive
                                ? cs.onSurface
                                : cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _badgeColor(cs).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull),
                    ),
                    child: Text(_badgeLabel(l10n),
                        style: GoogleFonts.inter(fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: _badgeColor(cs))),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(
                  '${buyer.phoneNumber ?? l10n.buyerMgmtNoPhone}'
                  '${buyer.purok != null ? '  •  ${buyer.purok}' : ''}',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(children: [
                  // Wrapped in Flexible so this cluster (order count +
                  // optional total spent) shrinks/ellipsizes instead of
                  // pushing "Since ..." off the right edge — at 360px with
                  // both pieces present, the unwrapped Row overflowed.
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_bag_outlined,
                            size: 13, color: cs.outline),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                              buyer.totalOrders == 1
                                  ? l10n.buyerMgmtOrderCountOne(buyer.totalOrders)
                                  : l10n.buyerMgmtOrderCountOther(buyer.totalOrders),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: cs.onSurfaceVariant)),
                        ),
                        if (buyer.totalSpent > 0) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.payments_outlined,
                              size: 13, color: cs.outline),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(l10n.buyerMgmtTotalSpentSuffix(buyer.totalSpent.toStringAsFixed(0)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(l10n.buyerMgmtSinceShort(buyerJoinedLabel(l10n, buyer.memberSince)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 10, color: cs.outline)),
                ]),
              ],
            ),
          ),

          const SizedBox(width: 8),
          GestureDetector(
            onTap: onMoreTap,
            child: Icon(Icons.more_vert_rounded,
                color: cs.onSurfaceVariant, size: 20),
          ),
        ],
      ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyState({required this.cs});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(children: [
        Icon(Icons.person_search_rounded,
            size: 48, color: cs.outline.withValues(alpha: 0.35)),
        const SizedBox(height: 12),
        Text(l10n.buyerMgmtNoBuyersFound,
            style: GoogleFonts.poppins(fontSize: 14,
                fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(l10n.buyerMgmtNoBuyersHint,
            style: GoogleFonts.inter(
                fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

// ─── Actions Sheet ────────────────────────────────────────────────────────────

class _ActionsSheet extends StatelessWidget {
  final BuyerProfileModel buyer;
  final bool isOnline;
  final VoidCallback onSendNotification;
  final VoidCallback onViewOrders;
  final VoidCallback onToggleStatus;
  const _ActionsSheet({required this.buyer, required this.isOnline,
    required this.onSendNotification, required this.onViewOrders,
    required this.onToggleStatus});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return ManagementModalShell(
      title: buyer.fullName,
      subtitle: l10n.buyerMgmtOrdersSinceLine(buyer.totalOrders, buyerJoinedLabel(l10n, buyer.memberSince)),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ActionRow(icon: Icons.history_rounded,
              label: l10n.buyerMgmtViewOrderHistory,
              onTap: onViewOrders, cs: cs),
          _ActionRow(icon: Icons.campaign_outlined,
              label: l10n.farmerMgmtActionSendNotification,
              onTap: onSendNotification, cs: cs),
          _ActionRow(
            icon: buyer.isActive
                ? Icons.block_rounded
                : Icons.check_circle_outline_rounded,
            label: buyer.isActive
                ? l10n.farmerMgmtSuspendAccountAction
                : l10n.buyerMgmtReactivateAccount,
            onTap: isOnline ? onToggleStatus : null,
            cs: cs,
            isDestructive: buyer.isActive,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final ColorScheme cs;
  final bool isDestructive;
  const _ActionRow({required this.icon, required this.label,
    this.onTap, required this.cs, this.isDestructive = false});

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? cs.outline
        : (isDestructive ? cs.error : cs.onSurface);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 14),
          Text(label,
              style: GoogleFonts.inter(fontSize: 14, color: color)),
        ]),
      ),
    );
  }
}