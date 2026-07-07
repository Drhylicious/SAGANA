import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/farmer_member_model.dart';
import '../../../data/repositories/farmer_management_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';

class FarmerManagementHeader extends StatelessWidget {
  final String title;
  final int memberCount;
  final VoidCallback onFilterTap;
  final VoidCallback onAddTap;
  final ColorScheme colorScheme;
  final SaganaColors saganaColors;
  final bool showFilterBadge;

  const FarmerManagementHeader({
    super.key,
    required this.title,
    required this.memberCount,
    required this.onFilterTap,
    required this.onAddTap,
    required this.colorScheme,
    required this.saganaColors,
    required this.showFilterBadge,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  '$memberCount Members',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Row(
          children: [
            _IconButton(
              icon: Icons.filter_list_rounded,
              onTap: onFilterTap,
              cs: colorScheme,
              sagana: saganaColors,
              showBadge: showFilterBadge,
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAddTap,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.20),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.add_rounded,
                    color: colorScheme.onPrimary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class FarmerManagementScreen extends StatefulWidget {
  const FarmerManagementScreen({super.key});

  @override
  State<FarmerManagementScreen> createState() =>
      _FarmerManagementScreenState();
}

class _FarmerManagementScreenState extends State<FarmerManagementScreen> {
  final _repo        = FarmerManagementRepository();
  final _searchCtrl  = TextEditingController();

  List<FarmerMemberModel> _allFarmers = [];
  MemberSummaryStats       _stats     = MemberSummaryStats.empty;
  List<String>             _cropNames = [];

  FarmerFilterState _filter = const FarmerFilterState();
  String            _searchQuery = '';

  bool _isLoading = true;
  bool _isOnline  = true;

  static const int _pageSize = 20;
  int _visibleCount = _pageSize;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery   = _searchCtrl.text;
        _visibleCount  = _pageSize;
      });
    });
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchFarmers(),
      _repo.fetchSummaryStats(),
      _repo.fetchDistinctCrops(),
    ]);
    if (!mounted) return;
    setState(() {
      _allFarmers = results[0] as List<FarmerMemberModel>;
      _stats      = results[1] as MemberSummaryStats;
      _cropNames  = results[2] as List<String>;
      _isLoading  = false;
    });
  }

  List<FarmerMemberModel> get _filteredFarmers =>
      _allFarmers.applyFilter(_filter, _searchQuery);

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        initial:   _filter,
        cropNames: _cropNames,
        onApply: (f) => setState(() {
          _filter        = f;
          _visibleCount  = _pageSize;
        }),
      ),
    );
  }

  void _showFarmerActions(FarmerMemberModel farmer) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FarmerActionsSheet(
        farmer: farmer,
        onViewProfile: () {
          Navigator.pop(context);
          context.push(AppRoutes.farmerDetails, extra: farmer.userId);
        },
        onSendNotice: () {
          Navigator.pop(context);
          context.push(AppRoutes.announcementDashboard);
        },
        onRecordPayment: () {
          Navigator.pop(context);
          context.push(AppRoutes.recordPayment, extra: farmer.userId);
        },
        onToggleStatus: () async {
          Navigator.pop(context);
          final newStatus = farmer.memberStatus == MemberStatus.active
              ? 'inactive'
              : 'active';
          await _repo.setFarmerStatus(
              userId: farmer.userId, status: newStatus);
          _loadAll();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n   = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs     = Theme.of(context).colorScheme;
    final farmers = _filteredFarmers;
    final visible = farmers.take(_visibleCount).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          if (!_isOnline) _OfflineBanner(),
          // ── Top App Bar ─────────────────────────────────────────────────
          _TopAppBar(sagana: sagana, cs: cs),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppConstants.primaryGreen),
                  )
                : RefreshIndicator(
                    color: AppConstants.primaryGreen,
                    onRefresh: _loadAll,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                      children: [

                        // ── Header row ───────────────────────────────────
                        FarmerManagementHeader(
                          title: l10n.farmerMgmtTitle,
                          memberCount: _stats.totalMembers,
                          onFilterTap: _showFilterSheet,
                          onAddTap: () => context.push(AppRoutes.addNewMember),
                          colorScheme: cs,
                          saganaColors: sagana,
                          showFilterBadge: !_filter.isDefault,
                        ),
                        const SizedBox(height: 14),

                        // ── Summary stat pills ───────────────────────────
                        SizedBox(
                          height: 38,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _StatPill(
                                label: 'Active',
                                value: _stats.activeMembers,
                                color: AppConstants.successGreen,
                                cs: cs,
                                sagana: sagana,
                              ),
                              const SizedBox(width: 8),
                              _StatPill(
                                label: 'Loans',
                                value: _stats.withActiveLoans +
                                    _stats.withOverdueLoans,
                                color: AppConstants.warningAmber,
                                cs: cs,
                                sagana: sagana,
                              ),
                              const SizedBox(width: 8),
                              _StatPill(
                                label: 'Pending',
                                value: _stats.pendingMembers,
                                color: cs.outline,
                                cs: cs,
                                sagana: sagana,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Search bar ────────────────────────────────────
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText:
                                'Search farmer name or member ID...',
                            hintStyle: GoogleFonts.inter(
                                fontSize: 13, color: cs.outline),
                            prefixIcon: Icon(Icons.search_rounded,
                                color: cs.outline, size: 22),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.close_rounded,
                                        color: cs.outline, size: 18),
                                    onPressed: () => _searchCtrl.clear(),
                                  )
                                : null,
                          ),
                          style: GoogleFonts.inter(
                              fontSize: 14, color: cs.onSurface),
                        ),
                        const SizedBox(height: 16),

                        // ── Farmer list ───────────────────────────────────
                        if (farmers.isEmpty)
                          _EmptyState(
                            hasFilters: !_filter.isDefault ||
                                _searchQuery.isNotEmpty,
                            cs: cs,
                          )
                        else ...[
                          ...visible.map((f) => Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 12),
                                child: _FarmerCard(
                                  farmer: f,
                                  cs: cs,
                                  sagana: sagana,
                                  onTap: () => context.push(
                                      AppRoutes.farmerDetails,
                                      extra: f.userId),
                                  onMoreTap: () =>
                                      _showFarmerActions(f),
                                ),
                              )),
                          if (_visibleCount < farmers.length)
                            Center(
                              child: TextButton(
                                onPressed: () => setState(
                                    () => _visibleCount += _pageSize),
                                child: Text(
                                  'Load More (${farmers.length - _visibleCount} remaining)',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar (shell-tab style — no back button)
// ─────────────────────────────────────────────────────────────────────────────

class _TopAppBar extends StatelessWidget {
  final SaganaColors sagana;
  final ColorScheme cs;

  const _TopAppBar({required this.sagana, required this.cs});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppConstants.primaryContainer,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: AppConstants.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'CoopAdmin',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
              const Spacer(),
              Icon(Icons.notifications_outlined,
                  color: cs.primary, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offline Banner
// ─────────────────────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppConstants.warningAmber,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 16, color: AppConstants.charcoal),
          const SizedBox(width: 6),
          Text(
            'Offline Mode - Changes will sync when back online',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppConstants.charcoal,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Icon Button with badge
// ─────────────────────────────────────────────────────────────────────────────

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;
  final bool showBadge;

  const _IconButton({
    required this.icon,
    required this.onTap,
    required this.cs,
    required this.sagana,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: sagana.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                  color: cs.outline.withValues(alpha: 0.15)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4),
              ],
            ),
            child: Icon(icon, color: cs.onSurfaceVariant, size: 20),
          ),
          if (showBadge)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat Pill
// ─────────────────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: GoogleFonts.inter(
                fontSize: 12, color: cs.onSurfaceVariant),
          ),
          Text(
            '$value',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Farmer Card
// ─────────────────────────────────────────────────────────────────────────────

class _FarmerCard extends StatelessWidget {
  final FarmerMemberModel farmer;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;

  const _FarmerCard({
    required this.farmer,
    required this.cs,
    required this.sagana,
    required this.onTap,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: farmer.isOverdue
              ? Border(
                  left: BorderSide(color: cs.error, width: 4),
                  top: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
                  right: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
                  bottom: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
                )
              : Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surfaceContainerHighest,
                    border: Border.all(
                        color: cs.primary.withValues(alpha: 0.10), width: 2),
                  ),
                  child: farmer.hasPhoto
                      ? ClipOval(
                          child: Image.network(
                            farmer.profilePhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                farmer.initials,
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            farmer.initials,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              farmer.fullName,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _StatusBadge(status: farmer.memberStatus, cs: cs),
                        ],
                      ),
                      Text(
                        farmer.memberId ?? 'No Member ID',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: cs.outline),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onMoreTap,
                  child: Icon(Icons.more_vert_rounded,
                      color: cs.onSurfaceVariant, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Crop tags + last harvest
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: farmer.primaryCrops.isEmpty
                        ? [
                            Text(
                              'No crops registered',
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: cs.outline),
                            ),
                          ]
                        : farmer.primaryCrops
                            .take(3)
                            .map((c) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(
                                        AppConstants.radiusSm),
                                  ),
                                  child: Text(
                                    c,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary,
                                    ),
                                  ),
                                ))
                            .toList(),
                  ),
                ),
                Text(
                  'Last: ${farmer.lastHarvestLabel}',
                  style: GoogleFonts.inter(
                      fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
            const SizedBox(height: 10),

            // Loan status + sync row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _LoanIndicator(farmer: farmer, cs: cs),
                Row(
                  children: [
                    Icon(
                      farmer.isSynced
                          ? Icons.check_circle_rounded
                          : Icons.sync_rounded,
                      size: 15,
                      color: farmer.isSynced
                          ? AppConstants.successGreen
                          : cs.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      farmer.isSynced ? 'Synced' : 'Pending',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: farmer.isSynced
                            ? AppConstants.successGreen
                            : cs.outline,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded,
                        color: cs.outline, size: 16),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final MemberStatus status;
  final ColorScheme cs;

  const _StatusBadge({required this.status, required this.cs});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case MemberStatus.active:
        color = AppConstants.successGreen;
        break;
      case MemberStatus.pending:
        color = AppConstants.warningAmber;
        break;
      case MemberStatus.inactive:
        color = cs.outline;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}

class _LoanIndicator extends StatelessWidget {
  final FarmerMemberModel farmer;
  final ColorScheme cs;

  const _LoanIndicator({required this.farmer, required this.cs});

  @override
  Widget build(BuildContext context) {
    if (farmer.loanStatus == LoanStatusSummary.none) {
      return Row(
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 17, color: AppConstants.successGreen),
          const SizedBox(width: 6),
          Text(
            'No loans',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppConstants.successGreen,
            ),
          ),
        ],
      );
    }

    final isOverdue = farmer.loanStatus == LoanStatusSummary.overdue;
    final color     = isOverdue ? cs.error : AppConstants.warningAmber;

    return Row(
      children: [
        Icon(
          isOverdue ? Icons.error_rounded : Icons.payments_rounded,
          size: 17,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          '₱${farmer.outstandingLoanBalance.toStringAsFixed(2)}',
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppConstants.amber,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          ),
          child: Text(
            isOverdue ? 'OVERDUE' : 'ACTIVE LOAN',
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasFilters;
  final ColorScheme cs;

  const _EmptyState({required this.hasFilters, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.group_off_outlined,
              size: 48, color: cs.outline.withValues(alpha: 0.40)),
          const SizedBox(height: 12),
          Text(
            hasFilters ? 'No farmers match your filters' : 'No farmers yet',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final FarmerFilterState initial;
  final List<String> cropNames;
  final ValueChanged<FarmerFilterState> onApply;

  const _FilterSheet({
    required this.initial,
    required this.cropNames,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late FarmerFilterState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXl)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline.withValues(alpha: 0.30),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filter Members',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _state = const FarmerFilterState()),
                  child: Text(
                    'Reset All',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Member Status
            _FilterSectionLabel(label: 'Member Status', cs: cs),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(
                  label: 'All',
                  active: _state.statusFilter == null,
                  onTap: () =>
                      setState(() => _state = _state.copyWith(statusFilter: null)),
                  cs: cs,
                ),
                ...MemberStatus.values.map((s) => _Chip(
                      label: s.label,
                      active: _state.statusFilter == s,
                      onTap: () => setState(
                          () => _state = _state.copyWith(statusFilter: s)),
                      cs: cs,
                    )),
              ],
            ),
            const SizedBox(height: 20),

            // Primary Crops
            _FilterSectionLabel(label: 'Primary Crops', cs: cs),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(
                  label: 'All Crops',
                  active: _state.cropFilter == null,
                  onTap: () =>
                      setState(() => _state = _state.copyWith(cropFilter: null)),
                  cs: cs,
                ),
                ...widget.cropNames.map((c) => _Chip(
                      label: c,
                      active: _state.cropFilter == c,
                      onTap: () => setState(
                          () => _state = _state.copyWith(cropFilter: c)),
                      cs: cs,
                    )),
              ],
            ),
            const SizedBox(height: 20),

            // Loan Status
            _FilterSectionLabel(label: 'Loan Status', cs: cs),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(
                  label: 'All',
                  active: _state.loanFilter == null,
                  onTap: () =>
                      setState(() => _state = _state.copyWith(loanFilter: null)),
                  cs: cs,
                ),
                ...LoanStatusSummary.values.map((l) => _Chip(
                      label: l.label,
                      active: _state.loanFilter == l,
                      onTap: () => setState(
                          () => _state = _state.copyWith(loanFilter: l)),
                      cs: cs,
                    )),
              ],
            ),
            const SizedBox(height: 20),

            // Sort By
            _FilterSectionLabel(label: 'Sort By', cs: cs),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.6,
              children: FarmerSortOption.values.map((opt) {
                final active = _state.sortBy == opt;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _state = _state.copyWith(sortBy: opt)),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: active
                          ? cs.primary.withValues(alpha: 0.08)
                          : cs.surfaceContainerHighest,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMd),
                      border: Border.all(
                        color: active
                            ? cs.primary
                            : cs.outline.withValues(alpha: 0.10),
                        width: active ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            opt.label,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: active ? cs.primary : cs.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (active)
                          Icon(Icons.check_circle_rounded,
                              size: 18, color: cs.primary),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: () {
                widget.onApply(_state);
                Navigator.pop(context);
              },
              child: Text(
                'Apply Filters',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSectionLabel extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  const _FilterSectionLabel({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: cs.outline,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.white : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Farmer Actions Sheet (three-dot menu)
// ─────────────────────────────────────────────────────────────────────────────

class _FarmerActionsSheet extends StatelessWidget {
  final FarmerMemberModel farmer;
  final VoidCallback onViewProfile;
  final VoidCallback onSendNotice;
  final VoidCallback onRecordPayment;
  final VoidCallback onToggleStatus;

  const _FarmerActionsSheet({
    required this.farmer,
    required this.onViewProfile,
    required this.onSendNotice,
    required this.onRecordPayment,
    required this.onToggleStatus,
  });

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusXl)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.30),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            farmer.fullName,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _ActionRow(
            icon: Icons.person_outline_rounded,
            label: 'View Profile',
            onTap: onViewProfile,
            cs: cs,
          ),
          _ActionRow(
            icon: Icons.campaign_outlined,
            label: 'Send Notification',
            onTap: onSendNotice,
            cs: cs,
          ),
          _ActionRow(
            icon: Icons.payments_outlined,
            label: 'Record Loan Payment',
            onTap: onRecordPayment,
            cs: cs,
          ),
          _ActionRow(
            icon: farmer.memberStatus == MemberStatus.active
                ? Icons.person_off_outlined
                : Icons.person_rounded,
            label: farmer.memberStatus == MemberStatus.active
                ? 'Set Inactive'
                : 'Set Active',
            onTap: onToggleStatus,
            cs: cs,
            isDestructive: farmer.memberStatus == MemberStatus.active,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ColorScheme cs;
  final bool isDestructive;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.cs,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? cs.error : cs.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 14, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
