import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_profile_model.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/buyer_status_badge.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class BuyerManagementScreen extends StatefulWidget {
  const BuyerManagementScreen({super.key});

  @override
  State<BuyerManagementScreen> createState() => _BuyerManagementScreenState();
}

class _BuyerManagementScreenState extends State<BuyerManagementScreen> {
  final _repo = BuyerProfileRepository();
  final _searchCtrl = TextEditingController();

  List<BuyerProfileModel> _buyers = [];
  bool _isLoading = true;
  bool _isOnline = true;
  String _searchQuery = '';
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

  // Every Buyer, searched by name only (contact details are not shown on this
  // screen), in name order.
  List<BuyerProfileModel> get _filtered {
    final q = _searchQuery.trim().toLowerCase();
    final list = q.isEmpty
        ? [..._buyers]
        : _buyers.where((b) => b.fullName.toLowerCase().contains(q)).toList();
    list.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );
    return list;
  }

  Widget _buyerCard(BuyerProfileModel b, ColorScheme cs, SaganaColors sagana) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BuyerManagementCard(
        buyer: b,
        cs: cs,
        sagana: sagana,
        onTap: () => context.push(AppRoutes.buyerDetails, extra: b.userId),
        onViewOrders: () => context.push(
          AppRoutes.buyerOrderHistory,
          extra: {'buyerId': b.userId, 'buyerName': b.fullName},
        ),
        onSendNotification: () => context.push(
          AppRoutes.announcementDashboard,
          extra: {'buyerId': b.userId, 'buyerName': b.fullName},
        ),
      ),
    );
  }

  // A group heading: the status and how many Buyers it holds.
  Widget _groupHeader(String label, int count, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
      child: Text(
        '$label ($count)',
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;
    final visible = _filtered;
    final active = visible
        .where((b) => buyerStatusOf(b) == BuyerStatus.active)
        .toList();
    final inactive = visible
        .where((b) => buyerStatusOf(b) == BuyerStatus.inactive)
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              CachedDataNotice(
                screen: 'buyers_all',
                isOnline: _isOnline,
                offlineMessage: AppLocalizations.of(context).offlineStaffBody,
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _load,
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: SkeletonList(),
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
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

                            // ── Buyer cards ──────────────────────────────
                            // Active Buyers first, then Inactive ones, each
                            // group in name order under its own heading.
                            if (visible.isEmpty)
                              _EmptyState(cs: cs)
                            else ...[
                              if (active.isNotEmpty) ...[
                                _groupHeader(
                                  l10n.farmerMgmtStatusActiveLabel,
                                  active.length,
                                  cs,
                                ),
                                for (final b in active)
                                  _buyerCard(b, cs, sagana),
                              ],
                              if (inactive.isNotEmpty) ...[
                                if (active.isNotEmpty)
                                  const SizedBox(height: 8),
                                _groupHeader(
                                  l10n.analyticsInactive,
                                  inactive.length,
                                  cs,
                                ),
                                for (final b in inactive)
                                  _buyerCard(b, cs, sagana),
                              ],
                            ],
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
    return SubPageTopBar(
      title: AppLocalizations.of(context).buyerMgmtTitle,
      onBack: onBack,
    );
  }
}

// ─── Buyer Card ───────────────────────────────────────────────────────────────
// [avatar]  Name                      ● Status   ⋮      (one row)
// No e-mail, phone, order count or last-active line: contact details are reached
// through the order workflows, and the order totals live on Buyer Details.

class BuyerManagementCard extends StatelessWidget {
  final BuyerProfileModel buyer;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onTap;
  final VoidCallback onViewOrders;
  final VoidCallback onSendNotification;
  const BuyerManagementCard({
    super.key,
    required this.buyer,
    required this.cs,
    required this.sagana,
    required this.onTap,
    required this.onViewOrders,
    required this.onSendNotification,
  });

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
    final status = buyerStatusOf(buyer);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ProfileAvatar(
              photoUrl: buyer.profilePhotoUrl,
              displayName: buyer.fullName,
              radius: 24,
            ),
            const SizedBox(width: 14),

            // One row: picture | name | status | menu. Nothing else.
            Expanded(
              child: Text(
                buyer.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: buyer.isActive ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Capped so a very narrow screen shortens the badge, not the name.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: BuyerStatusBadge(status: status),
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
