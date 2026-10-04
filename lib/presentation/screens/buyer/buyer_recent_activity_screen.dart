import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_activity_model.dart';
import '../../../data/repositories/buyer_order_repository.dart';
import '../../../data/repositories/buyer_profile_repository.dart';
import '../../widgets/buyer_activity_card.dart';

/// Buyer's Recent Activity — a peer to Edit Profile/Notifications/Settings
/// off the Profile tab, matching where farmerRecentActivity and
/// adminActivityLog sit (both top-level routes, not nested under
/// Settings). Two source categories (order lifecycle events and profile/
/// address/security changes), presented as a single search-only feed
/// (no filter chips) grouped by date — layout/cards shared with
/// BuyerAccountScreen's inline preview via buyer_activity_card.dart, so
/// the two surfaces can't drift apart.
class BuyerRecentActivityScreen extends StatefulWidget {
  const BuyerRecentActivityScreen({super.key});

  @override
  State<BuyerRecentActivityScreen> createState() =>
      _BuyerRecentActivityScreenState();
}

class _BuyerRecentActivityScreenState extends State<BuyerRecentActivityScreen> {
  final _orderRepo = BuyerOrderRepository();
  final _profileRepo = BuyerProfileRepository();
  final _searchCtrl = TextEditingController();

  bool _isLoading = true;
  List<BuyerActivityItem> _allItems = [];
  String _searchQuery = '';

  // "Load More" reveals more of the already-fetched, already-sorted
  // combined list rather than re-querying — fetchOrderActivity/
  // fetchProfileActivity don't support offset (each is a simple two-source
  // merge, unlike Admin/Farmer's paginated single feed), so _load() fetches
  // a generous flat batch from both sources once and pagination just
  // controls how much of that batch is shown.
  static const _pageSize = 30;
  int _visibleCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(
      () => setState(() => _searchQuery = _searchCtrl.text),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    // Combined here, screen-side — matches the existing Future.wait
    // convention already used identically in PriceMonitoringScreen,
    // MyOrdersScreen, and BuyerAccountScreen to merge multiple repository
    // calls into one load, rather than introducing a third repository
    // whose only job would be to call these other two.
    final results = await Future.wait([
      _orderRepo.fetchOrderActivity(limit: 200),
      _profileRepo.fetchProfileActivity(limit: 200),
    ]);
    if (!mounted) return;
    final combined = [...results[0], ...results[1]]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    setState(() {
      _allItems = combined;
      _visibleCount = _pageSize;
      _isLoading = false;
    });
  }

  List<BuyerActivityItem> get _filtered {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _allItems;
    return _allItems
        .where(
          (i) =>
              i.title.toLowerCase().contains(q) ||
              i.subtitle.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final filtered = _filtered;
    final visible = filtered.take(_visibleCount).toList();
    final hasMore = _visibleCount < filtered.length;
    final grouped = groupBuyerActivityByDate(visible, l10n);
    final dateKeys = grouped.keys.toList();

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        leading: const BackButton(color: AppConstants.primaryGreen),
        title: Text(
          l10n.buyerActivityTitle,
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppConstants.primaryGreen,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingSafeH,
                  4,
                  AppConstants.spacingSafeH,
                  8,
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppConstants.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: l10n.buyerActivitySearchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: _searchCtrl.clear,
                          )
                        : null,
                  ),
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppConstants.primaryGreen,
                  ),
                ),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                child: _EmptyState(hasSearch: _searchQuery.isNotEmpty),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingSafeH,
                  4,
                  AppConstants.spacingSafeH,
                  4,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final label = dateKeys[index];
                    final group = grouped[label]!;
                    return BuyerActivityDateGroup(label: label, items: group);
                  }, childCount: dateKeys.length),
                ),
              ),
              if (hasMore)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: GestureDetector(
                        onTap: () => setState(() => _visibleCount += _pageSize),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: sagana.cardBackground,
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull,
                            ),
                            border: Border.all(
                              color: AppConstants.outline.withValues(
                                alpha: 0.20,
                              ),
                            ),
                          ),
                          child: Text(
                            l10n.loadMore,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.primaryGreen,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  const _EmptyState({required this.hasSearch});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasSearch ? Icons.search_off_rounded : Icons.history_rounded,
              size: 56,
              color: AppConstants.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              hasSearch
                  ? l10n.buyerActivityNoMatchTitle
                  : l10n.buyerActivityAllEmptyTitle,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasSearch
                  ? l10n.buyerActivityNoMatchBody
                  : l10n.buyerActivityAllEmptyBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
