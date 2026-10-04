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
import '../../widgets/app_toast.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/suspend_reason_dialog.dart';

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
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _searchCtrl.addListener(
      () => setState(() => _searchQuery = _searchCtrl.text),
    );
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
    setState(() {
      _buyers = data;
      _isLoading = false;
    });
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
      list = list
          .where(
            (b) =>
          b.fullName.toLowerCase().contains(q) ||
                (b.phoneNumber?.contains(q) ?? false),
          )
          .toList();
    }
    return list;
  }

  // ─── Suspend flow — two-step (reason, then confirm), same shape as
  // FarmerDetailsScreen's flow (both now share promptSuspendReason from
  // suspend_reason_dialog.dart). Reactivate stays single-tap, also
  // matching Farmer.

  Future<void> _suspendOrReactivate(BuyerProfileModel buyer) async {
    final l10n = AppLocalizations.of(context);
    if (buyer.isActive) {
      final reason = await promptSuspendReason(
      context: context,
        title: l10n.buyerDetailsSuspendTitle,
        hint: l10n.buyerDetailsSuspendReasonHint,
          );
      if (reason == null || reason.trim().isEmpty || !mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (dc) => AlertDialog(
          title: Text(
            l10n.farmerMgmtConfirmSuspensionTitle,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          content: Text(
            '${l10n.buyerMgmtSuspendBuyerLine(buyer.fullName)}\n'
            '${l10n.farmerMgmtSuspendOutcomeLine}\n'
            '${l10n.farmerMgmtReasonLine(reason.trim())}',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dc, false),
              child: Text(l10n.farmerMgmtBack),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dc, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.errorRed,
                foregroundColor: Colors.white,
              ),
              child: Text(l10n.farmerMgmtSuspendAccountAction),
            ),
          ],
        ),
          );
      if (ok != true) return;
      try {
          await _repo.setBuyerStatus(
            buyerId: buyer.userId,
          status: 'suspended',
          reason: reason.trim(),
          );
      } catch (_) {
        if (mounted)
          AppToast.show(context, l10n.suspendActionError, isError: true);
        return;
      }
    } else {
      try {
        await _repo.setBuyerStatus(buyerId: buyer.userId, status: 'active');
      } catch (_) {
        if (mounted)
          AppToast.show(context, l10n.suspendActionError, isError: true);
        return;
      }
    }
          _load();
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
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppConstants.primaryGreen,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
                          children: [
                            // ── Search ───────────────────────────────────
                            TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: l10n.buyerMgmtSearchHint,
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: cs.outline,
                                ),
                                prefixIcon: Icon(
                                  Icons.search_rounded,
                                  color: cs.outline,
                                  size: 22,
                                ),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(
                                          Icons.close_rounded,
                                          color: cs.outline,
                                          size: 18,
                                        ),
                                        onPressed: () => _searchCtrl.clear(),
                                      )
                                    : null,
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── Status tabs ───────────────────────────────
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _TextTab(
                                    label: l10n.farmerMgmtAllFilter,
                                    active: _statusFilter == null,
                                    onTap: () =>
                                        setState(() => _statusFilter = null),
                                    cs: cs,
                                  ),
                                  _TextTab(
                                    label: l10n.farmerMgmtStatusActiveLabel,
                                    active: _statusFilter == 'active',
                                    onTap: () => setState(
                                      () => _statusFilter = 'active',
                                    ),
                                    cs: cs,
                                  ),
                                  _TextTab(
                                    label: l10n.analyticsInactive,
                                    active: _statusFilter == 'inactive',
                                    onTap: () => setState(
                                      () => _statusFilter = 'inactive',
                                    ),
                                    cs: cs,
                                  ),
                                  _TextTab(
                                    label: l10n.farmerMgmtStatusSuspendedLabel,
                                    active: _statusFilter == 'suspended',
                                    onTap: () => setState(
                                      () => _statusFilter = 'suspended',
                                    ),
                                    cs: cs,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── Buyer cards ──────────────────────────────
                            if (visible.isEmpty)
                              _EmptyState(cs: cs)
                            else
                              ...visible.map(
                                (b) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                    child: _BuyerCard(
                                      buyer: b,
                                      cs: cs,
                                      sagana: sagana,
                                      onTap: () => context.push(
                                          AppRoutes.buyerDetails,
                                      extra: b.userId,
                                    ),
                                    onViewOrders: () => context.push(
                                      AppRoutes.buyerOrderHistory,
                                      extra: {
                                        'buyerId': b.userId,
                                        'buyerName': b.fullName,
                                      },
                                    ),
                                    onSendNotification: () => context.push(
                                      AppRoutes.announcementDashboard,
                                      extra: {
                                        'buyerId': b.userId,
                                        'buyerName': b.fullName,
                                      },
                                    ),
                                    onToggleStatus: _isOnline
                                        ? () => _suspendOrReactivate(b)
                                        : null,
                                  ),
                                ),
                                    ),
                          ],
                        ),
                ),
              ),
            ],
          ),

          // ── Top App Bar ─────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
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
  const _TopAppBar({
    required this.onBack,
    required this.sagana,
    required this.cs,
  });

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
                child: Text(
                  AppLocalizations.of(context).buyerMgmtTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
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

class _TextTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final ColorScheme cs;
  const _TextTab({
    required this.label,
    required this.active,
    required this.onTap,
    required this.cs,
  });

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
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─── Buyer Card ───────────────────────────────────────────────────────────────
// Redesigned: [avatar] Name … [status badge] / Email or Phone (whichever
// exists; neither shown if both are unset). Order count/spent/"since" — a
// second, cluttering subtitle line — removed entirely; that summary lives
// on Buyer Details' own KPI cards instead, not duplicated here.

class _BuyerCard extends StatelessWidget {
  final BuyerProfileModel buyer;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onTap;
  final VoidCallback onViewOrders;
  final VoidCallback onSendNotification;
  final VoidCallback? onToggleStatus;
  const _BuyerCard({
    required this.buyer,
    required this.cs,
    required this.sagana,
    required this.onTap,
    required this.onViewOrders,
    required this.onSendNotification,
    required this.onToggleStatus,
  });

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

  Widget _menuRow(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.inter(fontSize: 13, color: color)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final contactLine = (buyer.contactEmail?.isNotEmpty ?? false)
        ? buyer.contactEmail
        : buyer.phoneNumber;

    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: buyer.isActive
            ? cs.outline.withValues(alpha: 0.10)
                : cs.outline.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
            ),
          ],
      ),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            ProfileAvatar(
              photoUrl: buyer.profilePhotoUrl,
              displayName: buyer.fullName,
              radius: 22,
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  Row(
                    children: [
                  Expanded(
                        child: Text(
                          buyer.fullName,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: buyer.isActive
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                    decoration: BoxDecoration(
                      color: _badgeColor(cs).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull,
                  ),
                ),
                          child: Text(
                          _badgeLabel(l10n),
                              style: GoogleFonts.inter(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: _badgeColor(cs),
                          ),
                        ),
                          ),
                      ],
                    ),
                  if (contactLine != null && contactLine.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      contactLine,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                  ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
              ],
            ),
          ),

            const SizedBox(width: 4),
            // Same interaction pattern as Admin Inventory Management's
            // per-row menu — a PopupMenuButton, not a bottom-sheet modal.
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.more_vert_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'orders':
                    onViewOrders();
                  case 'notify':
                    onSendNotification();
                  case 'toggle':
                    onToggleStatus?.call();
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'orders',
                  child: _menuRow(
                    Icons.history_rounded,
                    l10n.buyerMgmtViewOrderHistory,
                    cs.onSurface,
                  ),
                ),
                PopupMenuItem(
                  value: 'notify',
                  child: _menuRow(
                    Icons.campaign_outlined,
                    l10n.farmerMgmtActionSendNotification,
                    cs.onSurface,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'toggle',
                  enabled: onToggleStatus != null,
                  child: _menuRow(
                    buyer.isActive
                        ? Icons.block_rounded
                        : Icons.check_circle_outline_rounded,
                    buyer.isActive
                        ? l10n.farmerMgmtSuspendAccountAction
                        : l10n.buyerMgmtReactivateAccount,
                    buyer.isActive ? AppConstants.errorRed : cs.onSurface,
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

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyState({required this.cs});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(
            Icons.person_search_rounded,
            size: 48,
            color: cs.outline.withValues(alpha: 0.35),
          ),
        const SizedBox(height: 12),
          Text(
            l10n.buyerMgmtNoBuyersFound,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 4),
          Text(
            l10n.buyerMgmtNoBuyersHint,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
