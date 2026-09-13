import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_profile_model.dart';
import '../../../data/models/buyer_activity_model.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../../data/repositories/buyer_order_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/buyer_top_bar.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/shared_widgets.dart';

// Local bypass — BuyerProfileModel.memberSinceLabel hardcodes English
// month abbreviations, and the model is shared with Admin's
// fetchAllBuyers()/fetchAdminView() paths, so it isn't modified directly.
String _memberSinceLabel(DateTime memberSince, AppLocalizations l10n) {
  return l10n.buyerMemberSince(DateFormat('MMM y', l10n.localeName).format(memberSince));
}

class BuyerAccountScreen extends StatefulWidget {
  const BuyerAccountScreen({super.key});

  @override
  State<BuyerAccountScreen> createState() => _BuyerAccountScreenState();
}

class _BuyerAccountScreenState extends State<BuyerAccountScreen> {
  final _repository = BuyerProfileRepository();
  final _notificationRepo = NotificationRepository();
  final _buyerOrderRepo = BuyerOrderRepository();

  bool _isLoading = true;
  BuyerProfileModel? _profile;
  int _unreadCount = 0;

  bool _isActivityLoading = true;
  List<BuyerActivityItem> _recentActivity = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadActivity();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repository.fetchProfile(),
      _notificationRepo.fetchUnreadCount(),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as BuyerProfileModel?;
      _unreadCount = results[1] as int;
      _isLoading = false;
    });
  }

  // Added alongside the notification-staleness fix: a lightweight refresh
  // for just the unread count, so returning from the notifications screen
  // doesn't need to re-fetch the profile via the full _load().
  Future<void> _loadUnreadCount() async {
    final count = await _notificationRepo.fetchUnreadCount();
    if (!mounted) return;
    setState(() => _unreadCount = count);
  }

  Future<void> _loadActivity() async {
    setState(() => _isActivityLoading = true);
    final results = await Future.wait([
      _buyerOrderRepo.fetchRecentOrderActivity(),
      _repository.fetchRecentProfileActivity(),
    ]);
    if (!mounted) return;
    final combined = [...results[0], ...results[1]]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    setState(() {
      _recentActivity = combined.take(5).toList();
      _isActivityLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final hasOrders = (_profile?.totalOrders ?? 0) > 0;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                            AppConstants.spacingSafeH, 16, AppConstants.spacingSafeH, 40,
                          ),
                          children: [
                            _buildIdentityCard(l10n),
                            const SizedBox(height: 20),
                            SectionLabel(label: l10n.purchaseSummary),
                            hasOrders ? _buildStatsRow(l10n) : _buildFirstOrderPrompt(context, l10n),
                            const SizedBox(height: 20),
                            _RecentActivitySection(
                              items: _recentActivity,
                              isLoading: _isActivityLoading,
                              onViewAll: () => context.push(AppRoutes.buyerRecentActivity),
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
              title: l10n.account,
              unreadCount: _unreadCount,
              onNotificationTap: () async {
                await context.push(AppRoutes.buyerNotifications);
                _loadUnreadCount();
              },
              onSettingsTap: () => context.push(AppRoutes.buyerSettings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(AppLocalizations l10n) {
    final profile = _profile;
    return GlassCard(
      child: Row(
        children: [
          ProfileAvatar(
            photoUrl: profile?.profilePhotoUrl,
            displayName: profile?.fullName ?? l10n.buyerDefaultName,
            radius: 32,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile?.fullName ?? l10n.buyerDefaultName,
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(profile?.email ?? '',
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
                const SizedBox(height: 2),
                if (profile != null)
                  Text(_memberSinceLabel(profile.memberSince, l10n),
                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Purchase stats — tappable, jumping into My Orders pre-filtered.
  // NOTE: this depends on a new optional `initialTabIndex` param on
  // MyOrdersScreen and a matching router change (both below) — flagging
  // again here since it's the one change from the last proposal round
  // that touches an existing, already-tested screen's public API.

  Widget _buildStatsRow(AppLocalizations l10n) {
    final profile = _profile;
    return Row(
      children: [
        Expanded(
          child: _statTile(l10n.statOrders, '${profile?.totalOrders ?? 0}',
              onTap: () => context.go(AppRoutes.myOrders)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(l10n.statCompleted, '${profile?.completedOrders ?? 0}',
              onTap: () => context.go(AppRoutes.myOrders, extra: 2)), // Completed tab index
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(l10n.statSpent, '₱${(profile?.totalSpent ?? 0).toStringAsFixed(0)}'),
        ),
      ],
    );
  }

  Widget _statTile(String label, String value, {VoidCallback? onTap}) {
    final tile = Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Text(value, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
        ],
      ),
    );
    if (onTap == null) return tile;
    return InkWell(borderRadius: BorderRadius.circular(AppConstants.radiusLg), onTap: onTap, child: tile);
  }

  Widget _buildFirstOrderPrompt(BuildContext context, AppLocalizations l10n) {
    return GlassCard(
      child: Column(
        children: [
          Icon(Icons.shopping_basket_outlined, size: 36, color: AppConstants.primaryGreen.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(l10n.buyerNoOrdersTitle, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.buyerNoOrdersSubtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(label: l10n.browseMarketplace, onPressed: () => context.go(AppRoutes.marketplaceBrowse)),
          ),
        ],
      ),
    );
  }
}

// Superseded — was a single tappable row to the full activity screen;
// replaced with the inline preview section below (_RecentActivitySection),
// which shows the most recent items directly on this screen instead of
// requiring a tap-through to see anything.
class _RecentActivitySection extends StatelessWidget {
  final List<BuyerActivityItem> items;
  final bool isLoading;
  final VoidCallback onViewAll;

  const _RecentActivitySection({
    required this.items,
    required this.isLoading,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SectionLabel(label: l10n.buyerActivityTitle),
            GestureDetector(
              onTap: onViewAll,
              child: Text(l10n.buyerActivityViewAll,
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (isLoading)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: context.saganaColors.cardBackground, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(color: context.saganaColors.cardBackground, borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
            child: Column(
              children: [
                Icon(Icons.history_rounded, size: 36, color: AppConstants.outline.withValues(alpha: 0.5)),
                const SizedBox(height: 8),
                Text(l10n.buyerActivityEmpty, style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: context.saganaColors.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Column(
              children: items.asMap().entries.map((e) {
                return Column(
                  children: [
                    _RecentActivityTile(item: e.value),
                    if (e.key < items.length - 1)
                      Divider(height: 1, color: AppConstants.outline.withValues(alpha: 0.08)),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

// Buyer-local bypasses for BuyerActivityItem's order-derived text —
// mirrors the same pattern used throughout this project for shared/
// cross-cutting models, applied here even though this model is
// Buyer-exclusive, to move presentation logic out of the repository.
// Duplicated in buyer_recent_activity_screen.dart's _ActivityCard.
String _activityOrderTitle(String? status, AppLocalizations l10n) {
  switch (status) {
    case 'pending':   return l10n.buyerOrderDetailStepPlaced;
    case 'approved':  return l10n.buyerActivityOrderApproved;
    case 'completed': return l10n.buyerActivityOrderCompleted;
    case 'cancelled': return l10n.buyerActivityOrderCancelled;
    default:          return l10n.buyerActivityOrderUpdated;
  }
}

String _activityStatusLabel(String? status, AppLocalizations l10n) {
  switch (status) {
    case 'pending':   return l10n.buyerOrderDetailPendingTimestamp;
    case 'approved':  return l10n.buyerOrderDetailStepApproved;
    case 'completed': return l10n.buyerOrderDetailStepCompleted;
    case 'cancelled': return l10n.buyerActivityStatusCancelled;
    default:          return status ?? '';
  }
}

class _RecentActivityTile extends StatelessWidget {
  final BuyerActivityItem item;
  const _RecentActivityTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isOrder = item.type == BuyerActivityType.order;
    final title = isOrder ? _activityOrderTitle(item.orderStatus, l10n) : item.title;
    final subtitle = isOrder ? item.subtitle : l10n.buyerActivityFilterProfile;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppConstants.limeGreen,
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            ),
            child: Icon(isOrder ? Icons.receipt_long_rounded : Icons.person_rounded,
                size: 18, color: AppConstants.primaryGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
              ],
            ),
          ),
          if (item.valueLabel != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(item.valueLabel!,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
                if (isOrder && item.orderStatus != null)
                  Text(_activityStatusLabel(item.orderStatus, l10n),
                      style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: AppConstants.successGreen)),
              ],
            ),
        ],
      ),
    );
  }
}