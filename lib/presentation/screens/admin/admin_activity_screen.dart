import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_dashboard_model.dart';
import '../../../data/repositories/admin_dashboard_repository.dart';
import '../../../routes/app_routes.dart';

class AdminActivityScreen extends StatefulWidget {
  const AdminActivityScreen({super.key});

  @override
  State<AdminActivityScreen> createState() => _AdminActivityScreenState();
}

class _AdminActivityScreenState extends State<AdminActivityScreen> {
  final _repo = AdminDashboardRepository();

  List<AdminActivityItem> _items = [];
  bool _isLoading = true;
  AdminActivityType? _filter;
  int _page = 0;
  static const _pageSize = 30;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _loadPage(reset: true);
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (reset) {
      setState(() { _page = 0; _items = []; _hasMore = true; _isLoading = true; });
    }
    final fetched = await _repo.fetchRecentActivity(
      limit: _pageSize,
      offset: _page * _pageSize,
      typeFilter: _filter,
    );
    if (!mounted) return;
    setState(() {
      _items.addAll(fetched);
      _hasMore = fetched.length == _pageSize;
      _isLoading = false;
    });
  }

  void _onFilterTap(AdminActivityType? type) {
    setState(() => _filter = type);
    _loadPage(reset: true);
  }

  void _onItemTap(AdminActivityItem item) {
    switch (item.type) {
      case AdminActivityType.listing:
        if (item.referenceId != null) {
          context.push(AppRoutes.listingReview, extra: item.referenceId);
        }
      case AdminActivityType.loan:
        if (item.referenceId != null) {
          context.push(AppRoutes.loanDetails, extra: item.referenceId);
        }
      case AdminActivityType.member:
      case AdminActivityType.harvest:
        if (item.referenceId != null) {
          context.push(AppRoutes.farmerDetails, extra: item.referenceId);
        }
      case AdminActivityType.order:
        context.go(AppRoutes.pendingApprovals);
      case AdminActivityType.price:
        context.push(AppRoutes.priceManagement);
      case AdminActivityType.inventory:
        context.push(AppRoutes.adminInventory);
      case AdminActivityType.program:
        context.push(AppRoutes.programManagement);
      case AdminActivityType.cropRequest:
        context.push(AppRoutes.cropRequestApproval);
    }
  }

  Color _typeColor(AdminActivityType type, ColorScheme cs) {
    switch (type) {
      case AdminActivityType.harvest:     return AppConstants.primaryGreen;
      case AdminActivityType.listing:     return cs.primary;
      case AdminActivityType.member:      return AppConstants.primaryGreen;
      case AdminActivityType.order:       return AppConstants.buyerBlue;
      case AdminActivityType.loan:        return AppConstants.errorRed;
      case AdminActivityType.price:       return cs.outline;
      case AdminActivityType.inventory:   return AppConstants.warningAmber;
      case AdminActivityType.program:     return AppConstants.programPurple;
      case AdminActivityType.cropRequest: return AppConstants.warningAmber;
    }
  }

  IconData _typeIcon(AdminActivityType type) {
    switch (type) {
      case AdminActivityType.harvest:     return Icons.agriculture_rounded;
      case AdminActivityType.listing:     return Icons.store_rounded;
      case AdminActivityType.member:      return Icons.person_add_rounded;
      case AdminActivityType.order:       return Icons.shopping_bag_rounded;
      case AdminActivityType.loan:        return Icons.account_balance_rounded;
      case AdminActivityType.price:       return Icons.sell_rounded;
      case AdminActivityType.inventory:   return Icons.inventory_2_rounded;
      case AdminActivityType.program:     return Icons.star_rounded;
      case AdminActivityType.cropRequest: return Icons.eco_outlined;
    }
  }

  String _typeLabel(AdminActivityType? type) {
    if (type == null) return 'All';
    switch (type) {
      case AdminActivityType.harvest:     return 'Harvest';
      case AdminActivityType.listing:     return 'Listings';
      case AdminActivityType.member:      return 'Members';
      case AdminActivityType.order:       return 'Orders';
      case AdminActivityType.loan:        return 'Loans';
      case AdminActivityType.price:       return 'Prices';
      case AdminActivityType.inventory:   return 'Inventory';
      case AdminActivityType.program:     return 'Programs';
      case AdminActivityType.cropRequest: return 'Crop Requests';
    }
  }

  static const _filterTypes = [
    null,
    AdminActivityType.harvest,
    AdminActivityType.listing,
    AdminActivityType.member,
    AdminActivityType.loan,
    AdminActivityType.order,
    AdminActivityType.price,
  ];

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Glass top bar
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 64 + MediaQuery.of(context).padding.top,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                  left: 8, right: 20,
                ),
                decoration: BoxDecoration(
                  color: sagana.glassBackground,
                  border: Border(bottom: BorderSide(color: sagana.glassBorder)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                      onPressed: () => context.pop(),
                    ),
                    Text(
                      'Activity Log',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Filter chips
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: _filterTypes.map((type) {
                  final isSelected = _filter == type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _onFilterTap(type),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary
                              : sagana.cardBackground,
                          borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull),
                          border: Border.all(
                            color: isSelected
                                ? cs.primary
                                : cs.outline.withValues(alpha: 0.20),
                          ),
                        ),
                        child: Text(
                          _typeLabel(type),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppConstants.primaryGreen, strokeWidth: 2))
                : RefreshIndicator(
                    color: AppConstants.primaryGreen,
                    onRefresh: () => _loadPage(reset: true),
                    child: _items.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 120),
                              Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.history_rounded,
                                        size: 48,
                                        color: cs.onSurfaceVariant),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No activity yet',
                                      style: GoogleFonts.inter(
                                          fontSize: 14,
                                          color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                                20, 8, 20, 40),
                            itemCount:
                                _items.length + (_hasMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i == _items.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  child: Center(
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() => _page++);
                                        _loadPage();
                                      },
                                      child: Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 10),
                                        decoration: BoxDecoration(
                                          color: sagana.cardBackground,
                                          borderRadius:
                                              BorderRadius.circular(
                                                  AppConstants.radiusFull),
                                          border: Border.all(
                                            color: cs.outline
                                                .withValues(alpha: 0.20),
                                          ),
                                        ),
                                        child: Text(
                                          'Load more',
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: cs.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final item = _items[i];
                              final color = _typeColor(item.type, cs);
                              final icon = _typeIcon(item.type);
                              final isNavigable =
                                  item.referenceId != null ||
                                      item.type ==
                                          AdminActivityType.order ||
                                      item.type ==
                                          AdminActivityType.price;

                              return Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 10),
                                child: GestureDetector(
                                  onTap: isNavigable
                                      ? () => _onItemTap(item)
                                      : null,
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: sagana.cardBackground,
                                      borderRadius:
                                          BorderRadius.circular(
                                              AppConstants.radiusLg),
                                      border: Border.all(
                                        color: cs.outline
                                            .withValues(alpha: 0.10),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.03),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: color.withValues(
                                                alpha: 0.12),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(icon,
                                              color: color, size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .start,
                                            children: [
                                              Text(
                                                item.description,
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  color: cs.onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration:
                                                        BoxDecoration(
                                                      color: color
                                                          .withValues(
                                                              alpha: 0.10),
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(
                                                        AppConstants
                                                            .radiusFull,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      _typeLabel(
                                                          item.type),
                                                      style:
                                                          GoogleFonts.inter(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: color,
                                                        letterSpacing: 0.3,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                      width: 6),
                                                  Text(
                                                    item.timeLabel,
                                                    style:
                                                        GoogleFonts.inter(
                                                      fontSize: 11,
                                                      color: cs
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isNavigable)
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            size: 18,
                                            color: cs.onSurfaceVariant,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}