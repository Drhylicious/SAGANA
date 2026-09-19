import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../widgets/admin_top_bar.dart';
import '../../widgets/app_navigation_drawer.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/management_modal.dart';
import '../../../data/models/farmer_member_model.dart';
import '../../../data/repositories/account_management_repository.dart';
import '../../../data/repositories/farmer_management_repository.dart';
import '../../../data/services/admin_profile_state_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/temp_password_dialog.dart';

void _safePop(BuildContext context, [Object? result]) {
  if (Navigator.canPop(context)) {
    Navigator.pop(context, result);
  }

}

// Localized labels for model enums — kept here rather than in the data
// model so the model stays presentation-agnostic.
String _memberStatusLabel(AppLocalizations l10n, MemberStatus s) {
  switch (s) {
    case MemberStatus.active:    return l10n.farmerMgmtStatusActiveLabel;
    case MemberStatus.inactive:  return l10n.analyticsInactive;
    case MemberStatus.suspended: return l10n.farmerMgmtStatusSuspendedLabel;
    case MemberStatus.pending:   return l10n.buyerOrderDetailPendingTimestamp;
    case MemberStatus.rejected:  return l10n.farmerMgmtStatusRejectedLabel;
    case MemberStatus.draft:     return l10n.farmerMgmtStatusDraftLabel;
  }
}

String _loanStatusLabel(AppLocalizations l10n, LoanStatusSummary s) {
  switch (s) {
    case LoanStatusSummary.none:    return l10n.farmerMgmtLoanNone;
    case LoanStatusSummary.active:  return l10n.farmerMgmtLoanActiveLabel;
    case LoanStatusSummary.overdue: return l10n.adminDashKpiOverdue;
  }
}

String _sortOptionLabel(AppLocalizations l10n, FarmerSortOption o) {
  switch (o) {
    case FarmerSortOption.nameAZ:        return l10n.farmerMgmtSortNameAZ;
    case FarmerSortOption.recentHarvest: return l10n.farmerMgmtSortRecentHarvest;
    case FarmerSortOption.memberId:      return l10n.farmerMgmtSortMemberId;
    case FarmerSortOption.loanBalance:   return l10n.farmerMgmtSortLoanBalance;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Farmer Management Header
// ─────────────────────────────────────────────────────────────────────────────

class FarmerManagementHeader extends StatelessWidget {
  final String title;
  final int memberCount;
  final bool showTitle;
  final VoidCallback onFilterTap;
  final VoidCallback onAddTap;
  final VoidCallback? onManageAccountsTap;
  final ColorScheme colorScheme;
  final SaganaColors saganaColors;
  final bool showFilterBadge;

  const FarmerManagementHeader({
    super.key,
    required this.title,
    required this.memberCount,
    this.showTitle = true,
    required this.onFilterTap,
    required this.onAddTap,
    this.onManageAccountsTap,
    required this.colorScheme,
    required this.saganaColors,
    required this.showFilterBadge,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!showTitle) {
      // "+ Add Member" is the only flexible element in this row — it
      // absorbs whatever width is left after the fixed-size icon buttons
      // and the member-count pill. Previously every element here was a
      // fixed size with a trailing Spacer, so on narrower screens the row
      // overflowed and the count pill got clipped ("2 Membe..."). Giving
      // the primary action Expanded guarantees the row always fits.
      return Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onAddTap,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.20),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, color: colorScheme.onPrimary, size: 20),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        l10n.farmerMgmtAddMember,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _IconButton(
            icon: Icons.filter_list_rounded,
            onTap: onFilterTap,
            cs: colorScheme,
            sagana: saganaColors,
            showBadge: showFilterBadge,
          ),
          const SizedBox(width: 8),
          if (onManageAccountsTap != null) ...[
            _IconButton(
              icon: Icons.manage_accounts_rounded,
              onTap: onManageAccountsTap!,
              cs: colorScheme,
              sagana: saganaColors,
              showBadge: false,
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            ),
            child: Text(
              l10n.farmerMgmtMembersCount(memberCount),
              maxLines: 1,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

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
                  l10n.farmerMgmtMembersCount(memberCount),
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
            if (onManageAccountsTap != null)
              _IconButton(
                icon: Icons.manage_accounts_rounded,
                onTap: onManageAccountsTap!,
                cs: colorScheme,
                sagana: saganaColors,
                showBadge: false,
              ),
            if (onManageAccountsTap != null) const SizedBox(width: 8),
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
  final _accountRepo = AccountManagementRepository();
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

  /// Live count per status from the loaded list — this is what makes the
  /// derived Inactive count (and Suspended) correct without a server stat.
  int _statusCount(MemberStatus s) =>
      _allFarmers.where((f) => f.memberStatus == s).length;

  void _setStatusFilter(MemberStatus? s) {
    setState(() => _filter = _filter.copyWith(statusFilter: s));
  }

  void _showAddMemberTypeSheet() {
    final l10n = AppLocalizations.of(context);
    showManagementModal(
      context: context,
      builder: (dialogContext) => ManagementModalShell(
        title: l10n.farmerMgmtCreateNewAccountTitle,
        subtitle: l10n.farmerMgmtCreateNewAccountSubtitle,
        body: Row(
          children: [
            Expanded(
              child: _AddTypeCard(
                icon: Icons.person_add_alt_1_rounded,
                title: l10n.farmerMgmtAddFarmerTitle,
                subtitle: l10n.farmerMgmtAddFarmerSubtitle,
                onTap: () {
                  _safePop(dialogContext);
                  context.push(AppRoutes.addNewMember);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AddTypeCard(
                icon: Icons.badge_outlined,
                title: l10n.farmerMgmtAddOfficerTitle,
                subtitle: l10n.farmerMgmtAddOfficerSubtitle,
                onTap: () {
                  _safePop(dialogContext);
                  context.push(AppRoutes.createOfficerAccount);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet() {
    showManagementModal(
      context: context,
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
    showManagementModal(
      context: context,
      builder: (dialogContext) => _FarmerActionsSheet(
        farmer: farmer,
        onViewProfile: () {
          _safePop(dialogContext);
          context.push(AppRoutes.farmerDetails, extra: farmer.userId);
        },
        onSendNotice: () {
          _safePop(dialogContext);
          context.push(AppRoutes.announcementDashboard);
        },
        onRecordPayment: () {
          _safePop(dialogContext);
          context.push(AppRoutes.recordPayment, extra: farmer.userId);
        },
        onToggleStatus: () async {
          _safePop(dialogContext);
          // Bugfix (verification pass): only Active/Inactive/Suspended
          // support this toggle. Pending has its own Approve/Reject;
          // Rejected/Draft have no status toggle at all — this sheet
          // hides the row for those, but stay defensive here too.
          if (!farmer.memberStatus.supportsSuspendToggle) return;
          if (farmer.memberStatus.isEffectivelyActive) {
            // Active or Inactive — suspend, two-step (Decision D17).
            await _suspendMemberFlow(farmer);
          } else {
            // Suspended — reactivate, single tap.
            await _repo.reactivateMember(userId: farmer.userId);
            _loadAll();
          }
        },
        onResetPassword: () async {
          _safePop(dialogContext);
          try {
            final tempPassword = await _accountRepo.resetUserPassword(farmer.userId);
            if (!mounted) return;
            await showTempPasswordDialog(
              context: context,
              name: farmer.fullName,
              tempPassword: tempPassword,
            );
          } catch (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).farmerMgmtResetPasswordError),
                backgroundColor: AppConstants.errorRed,
              ),
            );
          }
        },
        onApprove: () async {
          _safePop(dialogContext);
          await _approveMember(farmer);
        },
        onReject: () async {
          _safePop(dialogContext);
          await _rejectMember(farmer);
        },
      ),
    );
  }

  Future<void> _approveMember(FarmerMemberModel farmer) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(l10n.farmerMgmtApproveDialogTitle(farmer.fullName),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: Text(
            l10n.farmerMgmtApproveDialogBody,
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.farmerMgmtCancel)),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.successGreen),
              child: Text(l10n.farmerMgmtApproveAction,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final result = await _repo.approveMember(
      userId:   farmer.userId,
      fullName: farmer.fullName,
    );

    if (!mounted) return;

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          l10n.farmerMgmtApprovedToast(farmer.fullName,
              result.memberId ?? '', result.username?.toUpperCase() ?? ''),
        ),
        backgroundColor: AppConstants.successGreen,
        behavior: SnackBarBehavior.floating,
      ));
      _loadAll();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.farmerMgmtApproveFailedToast(result.error ?? '')),
        backgroundColor: AppConstants.errorRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _rejectMember(FarmerMemberModel farmer) async {
    final l10n = AppLocalizations.of(context);
    // Step 1 — reason (required).
    final reason = await _promptReason(
      title: l10n.farmerMgmtRejectDialogTitle(farmer.fullName),
      hint: l10n.farmerMgmtRejectHint,
      actionLabel: l10n.farmerMgmtNext,
    );
    if (reason == null || reason.trim().isEmpty) return;

    // Step 2 — summary confirm.
    final confirmed = await _confirmSummary(
      title: l10n.farmerMgmtConfirmRejectionTitle,
      lines: [
        l10n.farmerMgmtRejectApplicantLine(farmer.fullName),
        l10n.farmerMgmtRejectOutcomeLine,
        l10n.farmerMgmtReasonLine(reason.trim()),
        l10n.farmerMgmtRejectResubmitLine,
      ],
      actionLabel: l10n.farmerMgmtRejectApplicationAction,
      danger: true,
    );
    if (confirmed != true) return;

    try {
      await _repo.rejectMember(userId: farmer.userId, reason: reason.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.farmerMgmtRejectedToast(farmer.fullName)),
        backgroundColor: AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
      ));
      _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppConstants.errorRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _suspendMemberFlow(FarmerMemberModel farmer) async {
    final l10n = AppLocalizations.of(context);
    final reason = await _promptReason(
      title: l10n.farmerMgmtSuspendDialogTitle(farmer.fullName),
      hint: l10n.farmerMgmtSuspendHint,
      actionLabel: l10n.farmerMgmtNext,
    );
    if (reason == null || reason.trim().isEmpty) return;

    final confirmed = await _confirmSummary(
      title: l10n.farmerMgmtConfirmSuspensionTitle,
      lines: [
        l10n.farmerMgmtSuspendMemberLine(farmer.fullName),
        l10n.farmerMgmtSuspendOutcomeLine,
        l10n.farmerMgmtReasonLine(reason.trim()),
        l10n.farmerMgmtSuspendReactivateLine,
      ],
      actionLabel: l10n.farmerMgmtSuspendAccountAction,
      danger: true,
    );
    if (confirmed != true) return;

    try {
      await _repo.suspendMember(userId: farmer.userId, reason: reason.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.farmerMgmtSuspendedToast(farmer.fullName)),
        backgroundColor: AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
      ));
      _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppConstants.errorRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<String?> _promptReason({
    required String title,
    required String hint,
    required String actionLabel,
  }) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dc) {
        final cs = Theme.of(dc).colorScheme;
        return AlertDialog(
          title: Text(title,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(fontSize: 12, color: cs.outline),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dc),
                child: Text(AppLocalizations.of(dc).farmerMgmtCancel)),
            ElevatedButton(
              onPressed: () => Navigator.pop(dc, ctrl.text.trim()),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirmSummary({
    required String title,
    required List<String> lines,
    required String actionLabel,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dc) {
        final cs = Theme.of(dc).colorScheme;
        return AlertDialog(
          title: Text(title,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines
                .map((l) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(l,
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                              height: 1.4)),
                    ))
                .toList(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dc, false),
                child: Text(AppLocalizations.of(dc).farmerMgmtBack)),
            ElevatedButton(
              onPressed: () => Navigator.pop(dc, true),
              style: danger
                  ? ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.errorRed,
                      foregroundColor: Colors.white)
                  : null,
              child: Text(actionLabel),
            ),
          ],
        );
      },
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
      drawer: AnimatedBuilder(
        animation: AdminProfileStateService.instance,
        builder: (context, _) {
          final profile = AdminProfileStateService.instance.profile;
          return AppNavigationDrawer(
            photoUrl: profile?.profilePhotoUrl,
            displayName: profile?.fullName ?? 'Admin',
            contactEmail: profile?.contactEmail ?? profile?.email,
            phoneNumber: profile?.phoneNumber,
            onEditProfile: () {
              Navigator.pop(context);
              context.push(AppRoutes.adminEditProfile);
            },
            onSignOut: () => confirmAdminSignOut(context),
            onAboutSagana: () => context.push(AppRoutes.aboutSagana),
            onAboutOrganization: () => context.push(AppRoutes.aboutCooperative),
            onPrivacyPolicy: () => context.push(AppRoutes.privacyPolicy),
            onTermsOfUse: () => context.push(AppRoutes.termsOfUse),
          );
        },
      ),
      body: Column(
        children: [
          if (!_isOnline) const OfflineBanner(),
          // ── Top App Bar ─────────────────────────────────────────────────
          AdminTopBar(
            title: l10n.adminNavMembers,
            onBroadcastTap: () => context.push(AppRoutes.announcementDashboard),
            onNotificationTap: () => context.push(AppRoutes.adminNotifications).then((_) => _loadAll()),
            onProfileTap: () => context.push(AppRoutes.adminProfile),
            enableMenu: true,
          ),

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
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      children: [

                        // ── Header row ───────────────────────────────────
                        FarmerManagementHeader(
                          title: l10n.farmerMgmtTitle,
                          memberCount: _stats.totalMembers,
                          showTitle: false,
                          onFilterTap: _showFilterSheet,
                          onAddTap: _showAddMemberTypeSheet,
                          // Members tab is Admin-only (Decision D19) — an
                          // Officer never reaches this screen, so this is
                          // simply always available here.
                          onManageAccountsTap: () =>
                              context.push(AppRoutes.manageAdminAccounts),
                          colorScheme: cs,
                          saganaColors: sagana,
                          showFilterBadge: !_filter.isDefault,
                        ),
                        const SizedBox(height: 14),

                        // ── Status filter chips (Issue 5 / D14) ──────────
                        // Active · Inactive · Suspended · Pending · Rejected,
                        // each tappable; the count comes from the loaded
                        // list so the derived Inactive count is accurate.
                        SizedBox(
                          height: 38,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _StatusFilterChip(
                                label: l10n.farmerMgmtAllFilter,
                                value: _allFarmers.length,
                                color: cs.primary,
                                selected: _filter.statusFilter == null,
                                onTap: () => _setStatusFilter(null),
                                cs: cs,
                                sagana: sagana,
                              ),
                              const SizedBox(width: 8),
                              for (final s in MemberStatusExt.filterable) ...[
                                _StatusFilterChip(
                                  label: _memberStatusLabel(l10n, s),
                                  value: _statusCount(s),
                                  color: _statusColor(s, cs),
                                  selected: _filter.statusFilter == s,
                                  onTap: () => _setStatusFilter(
                                      _filter.statusFilter == s ? null : s),
                                  cs: cs,
                                  sagana: sagana,
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Search bar ────────────────────────────────────
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: l10n.farmerMgmtSearchHint,
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
                                  l10n.farmerMgmtLoadMore(farmers.length - _visibleCount),
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
                  border: Border.all(color: sagana.cardBackground, width: 1.5),
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

Color _statusColor(MemberStatus s, ColorScheme cs) {
  switch (s) {
    case MemberStatus.active:    return AppConstants.successGreen;
    case MemberStatus.inactive:  return cs.outline;
    case MemberStatus.suspended: return AppConstants.errorRed;
    case MemberStatus.pending:   return AppConstants.warningAmber;
    case MemberStatus.rejected:  return AppConstants.errorRed;
    case MemberStatus.draft:     return cs.outline;
  }
}

/// Tappable status chip for the Members-tab header — label + live count,
/// filled when selected. Replaces the old display-only stat pills.
class _StatusFilterChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _StatusFilterChip({
    required this.label,
    required this.value,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.14)
              : sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.55)
                : cs.outline.withValues(alpha: 0.10),
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text('$label: ',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? color : cs.onSurfaceVariant)),
            Text('$value',
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected ? color : cs.primary)),
          ],
        ),
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
    final l10n = AppLocalizations.of(context);
    // Rejected applicants are kept for reference (3-attempt resubmission
    // history + audit trail) but are not an active/inactive member —
    // greyed out here, and sorted to the bottom of the list (see
    // FarmerListFilter.applyFilter). Opacity doesn't block hit-testing,
    // so View Profile / the ⋯ menu stay tappable.
    final isRejected = farmer.memberStatus == MemberStatus.rejected;
    final card = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRejected
              ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
              : sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(
            color: farmer.isOverdue
                ? cs.error.withValues(alpha: 0.18)
                : cs.outline.withValues(alpha: 0.10),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: avatar + name/ID grouped together, status + menu
            // aligned on their own trailing column so both sit consistently
            // regardless of name length.
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
                      Text(
                        farmer.fullName,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        farmer.memberId ?? l10n.farmerMgmtNoMemberId,
                        style: GoogleFonts.inter(
                            fontSize: 11.5, color: cs.outline),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _StatusBadge(status: farmer.memberStatus, cs: cs),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: onMoreTap,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.more_vert_rounded,
                            color: cs.onSurfaceVariant, size: 20),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Crop tags — tinted pills for real crops, muted/dashed treatment
            // for "no crops" so the empty state reads as distinctly lower
            // priority rather than just another chip.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: farmer.primaryCrops.isEmpty
                  ? [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusFull),
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          l10n.farmerMgmtNoCropsRegistered,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: cs.outline,
                          ),
                        ),
                      ),
                    ]
                  : farmer.primaryCrops
                      .take(3)
                      .map((c) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusFull),
                            ),
                            child: Text(
                              c,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                            ),
                          ))
                      .toList(),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.farmerMgmtLastActivity(farmer.lastHarvestLabel),
              style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
            const SizedBox(height: 12),

            // Loan status pill + sync status, each visually separated as
            // their own pill rather than plain inline icon+text.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Flexible: the Tagalog labels this pill can show ("Walang
                // Pautang", peso amounts) are longer than their English
                // source, and this Row has no other slack — without this,
                // a long label pushes the sync-status pill on the right
                // past the available width and overflows.
                Flexible(child: _LoanIndicator(farmer: farmer, cs: cs)),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (farmer.isSynced
                                ? AppConstants.successGreen
                                : cs.outline)
                            .withValues(alpha: 0.10),
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusFull),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            farmer.isSynced
                                ? Icons.check_circle_rounded
                                : Icons.sync_rounded,
                            size: 14,
                            color: farmer.isSynced
                                ? AppConstants.successGreen
                                : cs.outline,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            farmer.isSynced
                                ? l10n.farmerMgmtSyncedStatus
                                : l10n.buyerOrderDetailPendingTimestamp,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: farmer.isSynced
                                  ? AppConstants.successGreen
                                  : cs.outline,
                            ),
                          ),
                        ],
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

    return isRejected ? Opacity(opacity: 0.55, child: card) : card;
  }
}

class _StatusBadge extends StatelessWidget {
  final MemberStatus status;
  final ColorScheme cs;

  const _StatusBadge({required this.status, required this.cs});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Color color;
    switch (status) {
      case MemberStatus.active:
        color = AppConstants.successGreen;
        break;
      case MemberStatus.inactive:
        color = cs.outline;
        break;
      case MemberStatus.pending:
        color = AppConstants.warningAmber;
        break;
      case MemberStatus.suspended:
        color = AppConstants.errorRed;
        break;
      case MemberStatus.rejected:
        color = AppConstants.errorRed;
        break;
      case MemberStatus.draft:
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
        _memberStatusLabel(l10n, status).toUpperCase(),
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
    final l10n = AppLocalizations.of(context);
    if (farmer.loanStatus == LoanStatusSummary.none) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppConstants.successGreen.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                size: 15, color: AppConstants.successGreen),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.farmerMgmtLoanNone,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.successGreen,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isOverdue = farmer.loanStatus == LoanStatusSummary.overdue;
    final color     = isOverdue ? cs.error : AppConstants.warningAmber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOverdue ? Icons.error_rounded : Icons.payments_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            '₱${farmer.outstandingLoanBalance.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppConstants.amber,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isOverdue ? l10n.farmerMgmtOverdueBadge : l10n.farmerMgmtActiveBadge,
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
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
  final bool hasFilters;
  final ColorScheme cs;

  const _EmptyState({required this.hasFilters, required this.cs});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.group_off_outlined,
              size: 48, color: cs.outline.withValues(alpha: 0.40)),
          const SizedBox(height: 12),
          Text(
            hasFilters
                ? l10n.farmerMgmtNoFarmersFiltered
                : l10n.farmerMgmtNoFarmersYet,
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
    final l10n   = AppLocalizations.of(context);
    final cs     = Theme.of(context).colorScheme;

    return ManagementModalShell(
      title: l10n.farmerMgmtFilterTitle,
      subtitle: l10n.farmerMgmtFilterSubtitle,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // Member Status
            _FilterSectionLabel(label: l10n.farmerMgmtStatusSectionLabel, cs: cs),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(
                  label: l10n.farmerMgmtAllFilter,
                  active: _state.statusFilter == null,
                  onTap: () =>
                      setState(() => _state = _state.copyWith(statusFilter: null)),
                  cs: cs,
                ),
                // Active / Inactive / Suspended / Pending / Rejected —
                // Draft is intentionally not a filter (those rows aren't
                // listed at all). Issue 5 / Decision D14.
                ...MemberStatusExt.filterable.map((s) => _Chip(
                      label: _memberStatusLabel(l10n, s),
                      active: _state.statusFilter == s,
                      onTap: () => setState(
                          () => _state = _state.copyWith(statusFilter: s)),
                      cs: cs,
                    )),
              ],
            ),
            const SizedBox(height: 20),

            // Primary Crops
            _FilterSectionLabel(label: l10n.farmerMgmtCropsSectionLabel, cs: cs),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(
                  label: l10n.farmerMgmtAllCrops,
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
            _FilterSectionLabel(label: l10n.farmerMgmtLoanSectionLabel, cs: cs),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(
                  label: l10n.farmerMgmtAllFilter,
                  active: _state.loanFilter == null,
                  onTap: () =>
                      setState(() => _state = _state.copyWith(loanFilter: null)),
                  cs: cs,
                ),
                ...LoanStatusSummary.values.map((loanStatus) => _Chip(
                      label: _loanStatusLabel(l10n, loanStatus),
                      active: _state.loanFilter == loanStatus,
                      onTap: () => setState(
                          () => _state = _state.copyWith(loanFilter: loanStatus)),
                      cs: cs,
                    )),
              ],
            ),
            const SizedBox(height: 20),

            // Sort By
            _FilterSectionLabel(label: l10n.farmerMgmtSortBySectionLabel, cs: cs),
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
                            _sortOptionLabel(l10n, opt),
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
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: cs.outline.withValues(alpha: 0.30)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              onPressed: () =>
                  setState(() => _state = const FarmerFilterState()),
              child: Text(
                l10n.farmerMgmtResetAll,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () {
                widget.onApply(_state);
                _safePop(context);
              },
              child: Text(
                l10n.farmerMgmtApplyFilters,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
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
  final VoidCallback onResetPassword;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _FarmerActionsSheet({
    required this.farmer,
    required this.onViewProfile,
    required this.onSendNotice,
    required this.onRecordPayment,
    required this.onToggleStatus,
    required this.onResetPassword,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final l10n   = AppLocalizations.of(context);
    final cs     = Theme.of(context).colorScheme;
    final status = farmer.memberStatus;
    final isPending  = status == MemberStatus.pending;
    final isRejected = status == MemberStatus.rejected;

    return ManagementModalShell(
      title: farmer.fullName,
      subtitle: isPending
          ? l10n.farmerMgmtSubtitlePendingApp
          : isRejected
              ? l10n.farmerMgmtSubtitleRejectedApp
              : l10n.farmerMgmtSubtitleManageMember,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ActionRow(
            icon: Icons.person_outline_rounded,
            label: l10n.farmerMgmtActionViewProfile,
            onTap: onViewProfile,
            cs: cs,
          ),
          if (isPending) ...[
            _ActionRow(
              icon: Icons.check_circle_rounded,
              label: l10n.farmerMgmtActionApproveMembership,
              onTap: onApprove,
              cs: cs,
              iconColor: AppConstants.successGreen,
            ),
            _ActionRow(
              icon: Icons.cancel_rounded,
              label: l10n.farmerMgmtRejectApplicationAction,
              onTap: onReject,
              cs: cs,
              isDestructive: true,
            ),
          ] else if (isRejected) ...[
            // Rejected is not treated as an active/inactive member (Issue
            // 5 verification fix): no Record Loan Payment (they were never
            // a farmer member), no status toggle — they can only be
            // re-reviewed by resubmitting their own application, up to 3
            // total attempts. View Profile / Send Notification / Reset
            // Password remain available for reference and assistance.
            if (farmer.rejectionReason != null &&
                farmer.rejectionReason!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppConstants.errorRed.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Text(l10n.farmerMgmtReasonLine(farmer.rejectionReason!.trim()),
                      style: GoogleFonts.inter(
                          fontSize: 12, color: cs.onSurface, height: 1.4)),
                ),
              ),
            _ActionRow(
              icon: Icons.campaign_outlined,
              label: l10n.farmerMgmtActionSendNotification,
              onTap: onSendNotice,
              cs: cs,
            ),
            _ActionRow(
              icon: Icons.lock_reset_rounded,
              label: l10n.farmerMgmtActionResetPassword,
              onTap: onResetPassword,
              cs: cs,
            ),
          ] else ...[
            _ActionRow(
              icon: Icons.campaign_outlined,
              label: l10n.farmerMgmtActionSendNotification,
              onTap: onSendNotice,
              cs: cs,
            ),
            _ActionRow(
              icon: Icons.payments_outlined,
              label: l10n.farmerMgmtActionRecordLoanPayment,
              onTap: onRecordPayment,
              cs: cs,
            ),
            if (status.supportsSuspendToggle)
              _ActionRow(
                icon: status.isEffectivelyActive
                    ? Icons.person_off_outlined
                    : Icons.person_rounded,
                label: status.isEffectivelyActive
                    ? l10n.farmerMgmtActionSetSuspended
                    : l10n.farmerMgmtActionSetActive,
                onTap: onToggleStatus,
                cs: cs,
                isDestructive: status.isEffectivelyActive,
              ),
            _ActionRow(
              icon: Icons.lock_reset_rounded,
              label: l10n.farmerMgmtActionResetPassword,
              onTap: onResetPassword,
              cs: cs,
            ),
          ],
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
  final Color? iconColor;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.cs,
    this.isDestructive = false,
    this.iconColor,
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
            Icon(icon, size: 20, color: iconColor ?? color),
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

// ─────────────────────────────────────────────────────────────────────────────
// Add Type Card (for creating new account type)
// ─────────────────────────────────────────────────────────────────────────────

class _AddTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AddTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Container(
          decoration: BoxDecoration(
            color: sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Icon(icon, color: cs.primary, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}