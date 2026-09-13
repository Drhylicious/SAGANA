import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_activity_model.dart';
import '../../../data/repositories/buyer_order_repository.dart';
import '../../../data/repositories/buyer_profile_repository.dart';

/// Buyer's Recent Activity — a peer to Edit Profile/Notifications/Settings
/// off the Account tab, matching where farmerRecentActivity and
/// adminActivityLog sit (both top-level routes, not nested under
/// Settings). Two categories only, by design: order lifecycle events and
/// profile changes — no passive-screen tracking, no generic activity log.
class BuyerRecentActivityScreen extends StatefulWidget {
  const BuyerRecentActivityScreen({super.key});

  @override
  State<BuyerRecentActivityScreen> createState() => _BuyerRecentActivityScreenState();
}

enum _ActivityFilter { all, orders, profile }

class _BuyerRecentActivityScreenState extends State<BuyerRecentActivityScreen> {
  final _orderRepo = BuyerOrderRepository();
  final _profileRepo = BuyerProfileRepository();

  bool _isLoading = true;
  List<BuyerActivityItem> _items = [];
  _ActivityFilter _filter = _ActivityFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    // Combined here, screen-side — matches the existing Future.wait
    // convention already used identically in PriceMonitoringScreen,
    // MyOrdersScreen, and BuyerAccountScreen to merge multiple repository
    // calls into one load, rather than introducing a third repository
    // whose only job would be to call these other two.
    final results = await Future.wait([
      _orderRepo.fetchOrderActivity(),
      _profileRepo.fetchProfileActivity(),
    ]);
    if (!mounted) return;
    final combined = [...results[0], ...results[1]]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    setState(() {
      _items = combined;
      _isLoading = false;
    });
  }

  List<BuyerActivityItem> get _filtered {
    switch (_filter) {
      case _ActivityFilter.orders:
        return _items.where((i) => i.type == BuyerActivityType.order).toList();
      case _ActivityFilter.profile:
        return _items.where((i) => i.type == BuyerActivityType.profile).toList();
      case _ActivityFilter.all:
        return _items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        leading: BackButton(color: AppConstants.primaryGreen),
        title: Text(l10n.buyerActivityTitle,
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSafeH, vertical: 8),
              child: Row(
                children: [
                  _filterChip(l10n.buyerNotifFilterAll, _ActivityFilter.all),
                  const SizedBox(width: 8),
                  _filterChip(l10n.buyerNavOrders, _ActivityFilter.orders),
                  const SizedBox(width: 8),
                  _filterChip(l10n.buyerActivityFilterProfile, _ActivityFilter.profile),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? _buildEmptyState(l10n)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                              AppConstants.spacingSafeH, 4, AppConstants.spacingSafeH, 20),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) => _ActivityCard(item: filtered[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, _ActivityFilter value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: AppConstants.primaryGreen,
      labelStyle: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : AppConstants.onSurfaceVariant,
      ),
      backgroundColor: context.saganaColors.cardBackground,
      side: BorderSide(color: AppConstants.outline.withValues(alpha: 0.3)),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 56, color: AppConstants.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(l10n.buyerActivityAllEmptyTitle, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(l10n.buyerActivityAllEmptyBody,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// Duplicated from buyer_account_screen.dart's _RecentActivityTile —
// same reasoning: BuyerActivityItem is Buyer-exclusive, but the fix keeps
// presentation logic in the widget layer rather than the repository.
String _activityOrderTitle(String? status, AppLocalizations l10n) {
  switch (status) {
    case 'pending':   return l10n.buyerOrderDetailStepPlaced;
    case 'approved':  return l10n.buyerActivityOrderApproved;
    case 'completed': return l10n.buyerActivityOrderCompleted;
    case 'cancelled': return l10n.buyerActivityOrderCancelled;
    default:          return l10n.buyerActivityOrderUpdated;
  }
}

class _ActivityCard extends StatelessWidget {
  final BuyerActivityItem item;
  const _ActivityCard({required this.item});

  IconData get _icon => item.type == BuyerActivityType.order
      ? Icons.receipt_long_rounded
      : Icons.person_rounded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: AppConstants.limeGreen, borderRadius: BorderRadius.circular(AppConstants.radiusSm)),
            child: Icon(_icon, size: 20, color: AppConstants.primaryGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.type == BuyerActivityType.order ? _activityOrderTitle(item.orderStatus, l10n) : item.title,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(item.type == BuyerActivityType.order ? item.subtitle : l10n.buyerActivityFilterProfile,
                    style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(DateFormat('MMM d, y · h:mm a', l10n.localeName).format(item.timestamp),
                    style: GoogleFonts.inter(fontSize: 10, color: AppConstants.outline)),
              ],
            ),
          ),
          if (item.valueLabel != null)
            Text(item.valueLabel!,
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: AppConstants.primaryGreen)),
        ],
      ),
    );
  }
}
