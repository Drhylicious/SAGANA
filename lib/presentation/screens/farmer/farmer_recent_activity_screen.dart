import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/dashboard_summary_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/shared_widgets.dart';

class FarmerRecentActivityScreen extends StatefulWidget {
  const FarmerRecentActivityScreen({super.key});

  @override
  State<FarmerRecentActivityScreen> createState() =>
      _FarmerRecentActivityScreenState();
}

class _FarmerRecentActivityScreenState
    extends State<FarmerRecentActivityScreen> {
  final _repo = DashboardRepository();
  final _searchController = TextEditingController();

  List<ActivityItem> _allItems = [];
  List<ActivityItem> _filtered = [];
  ActivityFilter _activeFilter = ActivityFilter.all;
  bool _isLoading = true;
  String _searchQuery = '';
  bool _isOnline = true;

  // "Load More" pill at the end of the list — same pattern as Admin
  // Recent Activity's own Load More. fetchActivity already supports
  // offset/limit (it fetches a generous flat amount per source, combines,
  // sorts, then applies skip/take — see DashboardRepository.fetchActivity),
  // so each tap is a genuine incremental fetch, not just revealing more of
  // an already-loaded batch.
  int _page = 0;
  static const _pageSize = 30;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _loadActivity();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadActivity() async {
    setState(() {
      _page = 0;
      _allItems = [];
      _hasMore = true;
      _isLoading = true;
    });
    try {
      final items = await _repo.fetchActivity(limit: _pageSize, offset: 0);
      if (!mounted) return;
      setState(() {
        _allItems = items;
        _hasMore = items.length == _pageSize;
        _applyFilter();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _page++);
    try {
      final items = await _repo.fetchActivity(
        limit: _pageSize,
        offset: _page * _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _allItems.addAll(items);
        _hasMore = items.length == _pageSize;
        _applyFilter();
      });
    } catch (_) {
      // Best-effort — the already-loaded page stays visible; the pill
      // simply remains tappable for a retry.
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _applyFilter();
    });
  }

  void _setFilter(ActivityFilter filter) {
    setState(() {
      _activeFilter = filter;
      _applyFilter();
    });
  }

  void _applyFilter() {
    final q = _searchQuery.trim().toLowerCase();
    _filtered = _allItems.where((item) {
      final matchesFilter = _activeFilter.matches(item);
      if (!matchesFilter) return false;
      if (q.isEmpty) return true;
      return item.title.toLowerCase().contains(q) ||
          item.subtitle.toLowerCase().contains(q);
    }).toList();
  }

  // ─── Group by date label ─────────────────────────────────────────────────────

  Map<String, List<ActivityItem>> _groupByDate(List<ActivityItem> items) {
    final Map<String, List<ActivityItem>> groups = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final item in items) {
      final itemDate = DateTime(
        item.timestamp.year,
        item.timestamp.month,
        item.timestamp.day,
      );
      String label;
      if (itemDate == today) {
        label = 'Today';
      } else if (itemDate == yesterday) {
        label = 'Yesterday';
      } else {
        label = DateFormat('MMMM d').format(item.timestamp);
      }
      groups.putIfAbsent(label, () => []).add(item);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate(_filtered);
    final dateKeys = grouped.keys.toList();

    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(
              message:
                  "You're offline — your activity history may not be up to date.",
            ),
          Expanded(
            child: Stack(
              children: [
                // ── Content ──────────────────────────────────────────────
                Column(
                  children: [
                    const SizedBox(height: 72), // space for top bar
                    Expanded(
                      child: RefreshIndicator(
                        color: AppConstants.primaryGreen,
                        onRefresh: _loadActivity,
                        child: CustomScrollView(
                          slivers: [
                            // Header + search + chips
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 8),
                                    _SearchBar(controller: _searchController),
                                    const SizedBox(height: 16),
                                    _FilterChips(
                                      active: _activeFilter,
                                      onSelected: _setFilter,
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ),

                            // Empty state
                            if (!_isLoading && _filtered.isEmpty)
                              SliverFillRemaining(
                                child: _EmptyState(
                                  hasSearch:
                                      _searchQuery.isNotEmpty ||
                                      _activeFilter != ActivityFilter.all,
                                ),
                              )
                            // Loading shimmer
                            else if (_isLoading)
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  100,
                                ),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (_, __) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: _ActivityShimmer(),
                                    ),
                                    childCount: 5,
                                  ),
                                ),
                              )
                            // Grouped timeline
                            else ...[
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  0,
                                ),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate((
                                    context,
                                    index,
                                  ) {
                                    final label = dateKeys[index];
                                    final group = grouped[label]!;
                                    return _DateGroup(
                                      label: label,
                                      items: group,
                                    );
                                  }, childCount: dateKeys.length),
                                ),
                              ),
                              // Load More pill — same pattern as Admin
                              // Recent Activity. Stays enabled regardless of
                              // search/filter (both are client-side, same as
                              // Admin's own search) — each tap fetches the
                              // next page of the unfiltered feed, then
                              // _applyFilter() re-narrows the bigger set.
                              if (_hasMore)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      0,
                                      20,
                                      16,
                                    ),
                                    child: Center(
                                      child: GestureDetector(
                                        onTap: _loadMore,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              AppConstants.radiusFull,
                                            ),
                                            border: Border.all(
                                              color: AppConstants.outline
                                                  .withValues(alpha: 0.20),
                                            ),
                                          ),
                                          child: Text(
                                            'Load more',
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
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 84),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Top App Bar ──────────────────────────────────────────
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FarmerTopBar(
                    title: 'Recent Activity',
                    onBack: () => Navigator.of(context).pop(),
                    hideProfileAvatar: true,
                    onProfileTap: () {},
                    onNotificationTap: () {},
                    showNotificationButton: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search Bar
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
      decoration: InputDecoration(
        hintText: 'Search batches or crops...',
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppConstants.outline.withValues(alpha: 0.60),
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppConstants.outline,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: AppConstants.outline.withValues(alpha: 0.20),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(
            color: AppConstants.outline.withValues(alpha: 0.20),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: const BorderSide(color: AppConstants.primaryGreen),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter Chips
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  final ActivityFilter active;
  final ValueChanged<ActivityFilter> onSelected;

  const _FilterChips({required this.active, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ActivityFilter.values.map((filter) {
          final isActive = filter == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppConstants.primaryGreen
                      : Colors.white.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: Border.all(
                    color: isActive
                        ? AppConstants.primaryGreen
                        : Colors.white.withValues(alpha: 0.30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF455A64).withValues(alpha: 0.05),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Text(
                  filter.label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? Colors.white
                        : AppConstants.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date Group
// ─────────────────────────────────────────────────────────────────────────────

class _DateGroup extends StatelessWidget {
  final String label;
  final List<ActivityItem> items;

  const _DateGroup({required this.label, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 4),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppConstants.outline,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ActivityCard(item: item),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Activity Card
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final ActivityItem item;

  const _ActivityCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardIcon(type: item.type, isAlert: item.isAlert),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppConstants.charcoal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(item.timestamp),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppConstants.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppConstants.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Bottom row — value + status
                    _CardBottom(item: item),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(dt.year, dt.month, dt.day);

    if (itemDay == today) {
      return DateFormat('h:mm a').format(dt);
    }
    return DateFormat('MMM d').format(dt);
  }
}

class _CardBottom extends StatelessWidget {
  final ActivityItem item;

  const _CardBottom({required this.item});

  @override
  Widget build(BuildContext context) {
    // Loan reminders are informational only — no in-app payment action.
    // Loan payments are handled in person at the cooperative's scheduled
    // meeting (first Sunday of each month), so this falls through to the
    // same plain value/status rendering every other type uses below.

    if (item.valueLabel == null && item.statusLabel == null) {
      return const SizedBox.shrink();
    }

    Widget? statusBadge;
    if (item.statusLabel != null) {
      final isAlert = item.isAlert;
      final isSuccess =
          !isAlert &&
          (item.statusLabel == 'Verified' ||
              item.statusLabel == 'Active on Marketplace' ||
              item.statusLabel == 'Approved' ||
              item.statusLabel == 'Synced');
      final isWarning =
          item.statusLabel == 'Pending Sync' ||
          item.statusLabel == 'Pending Review' ||
          item.statusLabel == 'Pending';

      Color badgeColor;
      if (isAlert) {
        badgeColor = AppConstants.errorRed;
      } else if (isWarning) {
        badgeColor = AppConstants.warningAmber;
      } else if (isSuccess) {
        badgeColor = AppConstants.successGreen;
      } else {
        badgeColor = AppConstants.primaryGreen;
      }

      statusBadge = _StatusBadge(label: item.statusLabel!, color: badgeColor);
    }

    // Fixed after Final Verification found it: this screen previously never
    // rendered valueLabel at all (only Home's own _ActivityTile did), so the
    // ₱ amount on Order Placed / Expense Added / Capital Reinvestment — and
    // the kg amount on Harvest — was invisible here regardless of screen.
    if (item.valueLabel == null) {
      return statusBadge!;
    }

    final valueText = Text(
      item.valueLabel!,
      style: GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: item.isAlert ? AppConstants.errorRed : AppConstants.charcoal,
      ),
    );

    if (statusBadge == null) return valueText;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [valueText, statusBadge],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CardIcon extends StatelessWidget {
  final ActivityType type;
  final bool isAlert;

  const _CardIcon({required this.type, required this.isAlert});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color bg;
    Color fg;

    switch (type) {
      case ActivityType.harvest:
        icon = Icons.agriculture_rounded;
        bg = AppConstants.primaryContainer.withValues(alpha: 0.10);
        fg = AppConstants.primaryGreen;
        break;
      case ActivityType.listing:
        icon = Icons.verified_outlined;
        bg = AppConstants.primaryContainer.withValues(alpha: 0.10);
        fg = AppConstants.primaryGreen;
        break;
      case ActivityType.orderPlaced:
        icon = Icons.shopping_cart_outlined;
        bg = AppConstants.secondaryContainer.withValues(alpha: 0.10);
        fg = AppConstants.amber;
        break;
      case ActivityType.cropRequest:
        icon = Icons.local_florist_outlined;
        bg = (isAlert ? AppConstants.errorRed : AppConstants.primaryGreen)
            .withValues(alpha: 0.10);
        fg = isAlert ? AppConstants.errorRed : AppConstants.primaryGreen;
        break;
      case ActivityType.cropAdded:
        icon = Icons.grass_rounded;
        bg = AppConstants.primaryContainer.withValues(alpha: 0.10);
        fg = AppConstants.primaryGreen;
        break;
      case ActivityType.informalSale:
        icon = Icons.sell_outlined;
        bg = AppConstants.secondaryContainer.withValues(alpha: 0.10);
        fg = AppConstants.amber;
        break;
      case ActivityType.cropPhotoUpdated:
        icon = Icons.photo_camera_outlined;
        bg = AppConstants.primaryContainer.withValues(alpha: 0.10);
        fg = AppConstants.primaryGreen;
        break;
      case ActivityType.cooperativeOffer:
        icon = Icons.groups_outlined;
        bg = AppConstants.secondaryContainer.withValues(alpha: 0.10);
        fg = AppConstants.amber;
        break;
      case ActivityType.marketLinkingEnrollment:
        icon = Icons.handshake_outlined;
        bg = AppConstants.primaryContainer.withValues(alpha: 0.10);
        fg = AppConstants.primaryGreen;
        break;
      case ActivityType.gingerBatchSubmission:
        icon = Icons.outbox_outlined;
        bg = AppConstants.secondaryContainer.withValues(alpha: 0.10);
        fg = AppConstants.amber;
        break;
      case ActivityType.profile:
        icon = Icons.person_outline_rounded;
        bg = AppConstants.outline.withValues(alpha: 0.10);
        fg = AppConstants.outline;
        break;
      case ActivityType.addressUpdated:
        icon = Icons.location_on_outlined;
        bg = AppConstants.outline.withValues(alpha: 0.10);
        fg = AppConstants.outline;
        break;
      case ActivityType.expenseAdded:
        icon = Icons.receipt_long_outlined;
        bg = AppConstants.outline.withValues(alpha: 0.10);
        fg = AppConstants.outline;
        break;
      case ActivityType.programEnrollment:
        icon = Icons.assignment_turned_in_outlined;
        bg = AppConstants.primaryContainer.withValues(alpha: 0.10);
        fg = AppConstants.primaryGreen;
        break;
      case ActivityType.programPurchase:
        icon = Icons.shopping_bag_outlined;
        bg = AppConstants.secondaryContainer.withValues(alpha: 0.10);
        fg = AppConstants.amber;
        break;
      case ActivityType.capitalReinvestment:
        icon = Icons.savings_outlined;
        bg = AppConstants.primaryContainer.withValues(alpha: 0.10);
        fg = AppConstants.primaryGreen;
        break;
      case ActivityType.syncCompleted:
        icon = Icons.sync_rounded;
        bg = AppConstants.outline.withValues(alpha: 0.10);
        fg = AppConstants.outline;
        break;
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: 26, color: fg),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer Loader
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityShimmer extends StatefulWidget {
  @override
  State<_ActivityShimmer> createState() => _ActivityShimmerState();
}

class _ActivityShimmerState extends State<_ActivityShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(
      begin: -1,
      end: 2,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _block(double w, double h) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: [
              (_anim.value - 1).clamp(0.0, 1.0),
              _anim.value.clamp(0.0, 1.0),
              (_anim.value + 1).clamp(0.0, 1.0),
            ],
            colors: const [
              Color(0xFFE8E8E8),
              Color(0xFFF5F5F5),
              Color(0xFFE8E8E8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          _block(48, 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _block(160, 14),
                const SizedBox(height: 8),
                _block(120, 11),
                const SizedBox(height: 10),
                _block(80, 10),
              ],
            ),
          ),
        ],
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSearch ? Icons.search_off_rounded : Icons.inbox_outlined,
            size: 56,
            color: AppConstants.outline.withValues(alpha: 0.50),
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch ? 'No matching activity' : 'No activity yet',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasSearch
                ? 'Try a different search or filter'
                : 'Your harvests, listings, and loan updates will appear here',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: AppConstants.outline),
          ),
        ],
      ),
    );
  }
}
