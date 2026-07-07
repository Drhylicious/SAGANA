import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/dashboard_summary_model.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
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

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _loadActivity();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadActivity() async {
    setState(() => _isLoading = true);
    try {
      final items = await _repo.fetchAllActivity();
      if (!mounted) return;
      setState(() {
        _allItems = items;
        _applyFilter();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
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
      body: Stack(
        children: [
          // ── Content ──────────────────────────────────────────────────────
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
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Recent Activity',
                                style: GoogleFonts.poppins(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppConstants.charcoal,
                                ),
                              ),
                              const SizedBox(height: 16),
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
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, __) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _ActivityShimmer(),
                              ),
                              childCount: 5,
                            ),
                          ),
                        )
                      // Grouped timeline
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
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
                                onLoanPayTap: () => Navigator.of(
                                  context,
                                ).pushNamed(AppRoutes.myLoans),
                              );
                            }, childCount: dateKeys.length),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Top App Bar ───────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              onBack: () => Navigator.of(context).pop(),
              onProfileTap: () =>
                  context.goTab(AppRoutes.farmerProfile),
                onNotificationTap: () => context.pushRoute(AppRoutes.farmerNotifications),
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
  final VoidCallback onLoanPayTap;

  const _DateGroup({
    required this.label,
    required this.items,
    required this.onLoanPayTap,
  });

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
            child: _ActivityCard(item: item, onLoanPayTap: onLoanPayTap),
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
  final VoidCallback onLoanPayTap;

  const _ActivityCard({required this.item, required this.onLoanPayTap});

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
                    // Bottom row — value + status or action
                    _CardBottom(item: item, onLoanPayTap: onLoanPayTap),
                  ],
                ),
              ),
              // Chevron for orders
              if (item.type == ActivityType.order)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppConstants.outline,
                  size: 20,
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
  final VoidCallback onLoanPayTap;

  const _CardBottom({required this.item, required this.onLoanPayTap});

  @override
  Widget build(BuildContext context) {
    // Order card: price + status
    if (item.type == ActivityType.order) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            item.valueLabel ?? '',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppConstants.secondaryContainer,
            ),
          ),
          if (item.statusLabel != null)
            Text(
              item.statusLabel!,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppConstants.primaryGreen,
              ),
            ),
        ],
      );
    }

    // Loan card: status badge + Pay Now
    if (item.type == ActivityType.loan) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _StatusBadge(
            label: item.statusLabel ?? 'Reminder',
            color: AppConstants.errorRed,
          ),
          GestureDetector(
            onTap: onLoanPayTap,
            child: Text(
              'Pay Now',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppConstants.primaryGreen,
                decoration: TextDecoration.underline,
                decorationColor: AppConstants.primaryGreen,
              ),
            ),
          ),
        ],
      );
    }

    // Harvest + Listing: status badge only
    if (item.statusLabel != null) {
      final isAlert = item.isAlert;
      final isSuccess =
          !isAlert &&
          (item.statusLabel == 'Verified' ||
              item.statusLabel == 'Active on Marketplace' ||
              item.statusLabel == 'Synced');
      final isWarning =
          item.statusLabel == 'Pending Quality Check' ||
          item.statusLabel == 'Pending Sync';

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

      return _StatusBadge(label: item.statusLabel!, color: badgeColor);
    }

    return const SizedBox.shrink();
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

    if (isAlert) {
      icon = Icons.account_balance_wallet_outlined;
      bg = AppConstants.errorRed.withValues(alpha: 0.10);
      fg = AppConstants.errorRed;
    } else {
      switch (type) {
        case ActivityType.harvest:
          icon = Icons.agriculture_rounded;
          bg = AppConstants.primaryContainer.withValues(alpha: 0.10);
          fg = AppConstants.primaryGreen;
          break;
        case ActivityType.order:
          icon = Icons.shopping_cart_outlined;
          bg = AppConstants.secondaryContainer.withValues(alpha: 0.10);
          fg = AppConstants.amber;
          break;
        case ActivityType.listing:
          icon = Icons.verified_outlined;
          bg = AppConstants.primaryContainer.withValues(alpha: 0.10);
          fg = AppConstants.primaryGreen;
          break;
        case ActivityType.loan:
          icon = Icons.account_balance_wallet_outlined;
          bg = AppConstants.errorRed.withValues(alpha: 0.10);
          fg = AppConstants.errorRed;
          break;
      }
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
                : 'Your harvests, orders, and loan updates will appear here',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: AppConstants.outline),
          ),
        ],
      ),
    );
  }
}

