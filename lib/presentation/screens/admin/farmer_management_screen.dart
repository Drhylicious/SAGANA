import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../widgets/admin_top_bar.dart';
import '../../widgets/suspension_dialogs.dart';
import '../../widgets/app_navigation_drawer.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/member_title_row.dart';
import '../../widgets/members_controls.dart';
import '../../widgets/reason_dialogs.dart';
import '../../../data/models/farmer_member_model.dart';
import '../../../data/repositories/account_management_repository.dart';
import '../../../data/repositories/farmer_management_repository.dart';
import '../../../data/services/admin_profile_state_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/temp_password_dialog.dart';
import '../../widgets/skeleton.dart';

void _safePop(BuildContext context, [Object? result]) {
  if (Navigator.canPop(context)) {
    Navigator.pop(context, result);
  }
}

// Localized labels for model enums — kept here rather than in the data
// model so the model stays presentation-agnostic.
String _memberStatusLabel(AppLocalizations l10n, MemberStatus s) {
  switch (s) {
    case MemberStatus.active:
      return l10n.farmerMgmtStatusActiveLabel;
    case MemberStatus.inactive:
      return l10n.analyticsInactive;
    case MemberStatus.suspended:
      return l10n.farmerMgmtStatusSuspendedLabel;
    case MemberStatus.pending:
      return l10n.buyerOrderDetailPendingTimestamp;
    case MemberStatus.rejected:
      return l10n.farmerMgmtStatusRejectedLabel;
    case MemberStatus.draft:
      return l10n.farmerMgmtStatusDraftLabel;
  }
}

String _loanStatusLabel(AppLocalizations l10n, LoanStatusSummary s) {
  switch (s) {
    case LoanStatusSummary.none:
      return l10n.farmerMgmtLoanNone;
    case LoanStatusSummary.active:
      return l10n.farmerMgmtLoanActiveLabel;
    case LoanStatusSummary.overdue:
      return l10n.adminDashKpiOverdue;
  }
}

String _sortOptionLabel(AppLocalizations l10n, FarmerSortOption o) {
  switch (o) {
    case FarmerSortOption.nameAZ:
      return l10n.farmerMgmtSortNameAZ;
    case FarmerSortOption.recentHarvest:
      return l10n.farmerMgmtSortRecentHarvest;
    case FarmerSortOption.loanBalance:
      return l10n.farmerMgmtSortLoanBalance;
  }
}

class FarmerManagementScreen extends StatefulWidget {
  const FarmerManagementScreen({super.key});

  @override
  State<FarmerManagementScreen> createState() => _FarmerManagementScreenState();
}

class _FarmerManagementScreenState extends State<FarmerManagementScreen> {
  final _repo        = FarmerManagementRepository();
  final _accountRepo = AccountManagementRepository();
  final _searchCtrl  = TextEditingController();

  List<FarmerMemberModel> _allFarmers = [];
  List<String>             _cropNames = [];

  FarmerFilterState _filter = const FarmerFilterState();
  String            _searchQuery = '';

  bool _isLoading = true;
  bool _isOnline  = true;

  static const int _pageSize = 20;
  int _visibleCount = _pageSize;

  // Live updates: a Farmer who registers (or whose status changes) appears
  // here without the Manager having to refresh or add them by hand.
  RealtimeChannel? _membersChannel;
  Timer? _reloadDebounce;

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
    _subscribeToMemberChanges();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _membersChannel?.unsubscribe();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Reloads the list when any Farmer's user_roles row is inserted, updated
  /// or deleted. Several events in a burst (a registration writes a few rows)
  /// collapse into one reload. The list is read under the Manager's own
  /// permissions, so a Buyer is never part of it: only role = 'farmer' rows
  /// are fetched.
  void _subscribeToMemberChanges() {
    _membersChannel = Supabase.instance.client
        .channel('members_user_roles_${identityHashCode(this)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_roles',
          callback: (payload) {
            final role = payload.newRecord['role'] ?? payload.oldRecord['role'];
            if (role != null && role != 'farmer') return;
            _reloadDebounce?.cancel();
            _reloadDebounce = Timer(const Duration(milliseconds: 700), () {
              if (mounted) _loadAll(silent: true);
            });
          },
        )
        .subscribe();
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchFarmers(),
      _repo.fetchDistinctCrops(),
    ]);
    if (!mounted) return;
    setState(() {
      _allFarmers = results[0] as List<FarmerMemberModel>;
      _cropNames  = results[1] as List<String>;
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

  /// Every ⋯ menu action, for every status. The card only builds the
  /// entries; what each one does lives here.
  Future<void> _onMenuSelected(FarmerMemberModel farmer, String value) async {
    switch (value) {
      case 'view':
        context.push(AppRoutes.farmerDetails, extra: farmer.userId);
      case 'notice':
        context.push(AppRoutes.announcementDashboard);
      case 'payment':
        context.push(AppRoutes.recordPayment, extra: farmer.userId);
      case 'toggle':
        // Suspend is a two-step flow (Decision D17); reactivate is one tap.
        if (!farmer.memberStatus.supportsSuspendToggle) return;
        if (farmer.memberStatus.isEffectivelyActive) {
          await _suspendMemberFlow(farmer);
        } else {
          await _repo.reactivateMember(userId: farmer.userId);
          _loadAll();
        }
      case 'reset':
        await _resetPassword(farmer);
      case 'issueLoan':
        context.push(AppRoutes.issueNewLoan, extra: farmer.userId);
      case 'approve':
        await _approveMember(farmer);
      case 'reject':
        await _rejectMember(farmer);
      case 'delete':
        await _confirmDeleteRejected(farmer);
    }
  }

  Future<void> _resetPassword(FarmerMemberModel farmer) async {
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
          content: Text(
            AppLocalizations.of(context).farmerMgmtResetPasswordError,
          ),
          backgroundColor: AppConstants.errorRed,
        ),
      );
    }
  }

  /// Rejected applicants only. The RPC enforces the same rule, so this
  /// confirmation is the UI step, not the only guard.
  Future<void> _confirmDeleteRejected(FarmerMemberModel farmer) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(
            l10n.farmerMgmtDeleteRejectedTitle,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          content: Text(
            l10n.farmerMgmtDeleteRejectedBody(farmer.fullName),
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.farmerMgmtCancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.errorRed,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.farmerMgmtDeleteRejectedAction),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      await _repo.deleteRejectedApplicant(userId: farmer.userId);
      if (!mounted) return;
      PostActionFeedback.success(context, l10n.farmerMgmtDeleteRejectedSuccess);
      _loadAll();
    } catch (_) {
      if (!mounted) return;
      PostActionFeedback.error(context, l10n.farmerMgmtDeleteRejectedError);
    }
  }

  Future<void> _approveMember(FarmerMemberModel farmer) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(
            l10n.farmerMgmtApproveDialogTitle(farmer.fullName),
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          content: Text(
            l10n.farmerMgmtApproveDialogBody,
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.farmerMgmtCancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.successGreen,
              ),
              child: Text(
                l10n.farmerMgmtApproveAction,
                  style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.farmerMgmtApprovedToast(farmer.fullName)),
        backgroundColor: AppConstants.midGreen,
        behavior: SnackBarBehavior.floating,
        ),
      );
      _loadAll();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
        content: Text(l10n.farmerMgmtApproveFailedToast(result.error ?? '')),
        backgroundColor: AppConstants.errorRed,
        behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _rejectMember(FarmerMemberModel farmer) async {
    final l10n = AppLocalizations.of(context);
    // Step 1 — reason (required).
    final reason = await promptReason(
      context: context,
      title: l10n.farmerMgmtRejectDialogTitle(farmer.fullName),
      hint: l10n.farmerMgmtRejectHint,
      actionLabel: l10n.farmerMgmtNext,
    );
    if (reason == null || reason.trim().isEmpty) return;

    // Step 2 — summary confirm.
    final confirmed = await confirmSummary(
      context: context,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
        content: Text(l10n.farmerMgmtRejectedToast(farmer.fullName)),
        backgroundColor: AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
        ),
      );
      _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppConstants.errorRed,
        behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _suspendMemberFlow(FarmerMemberModel farmer) async {
    final l10n = AppLocalizations.of(context);
    final request = await promptSuspension(
      context: context,
      role: 'farmer',
      displayName: farmer.fullName,
    );
    if (request == null) return;

    try {
      await _repo.suspendMember(
        userId: farmer.userId,
        reason: request.reason,
        suspendedUntil: request.suspendedUntil,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
        content: Text(l10n.farmerMgmtSuspendedToast(farmer.fullName)),
        backgroundColor: AppConstants.charcoal,
        behavior: SnackBarBehavior.floating,
        ),
      );
      _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppConstants.errorRed,
        behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
            displayName: profile?.fullName ?? 'Manager',
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
          // ── Top App Bar ─────────────────────────────────────────────────
          AdminTopBar(
            title: l10n.adminNavMembers,
            onBroadcastTap: () => context.push(AppRoutes.announcementDashboard),
            onNotificationTap: () => context
                .push(AppRoutes.adminNotifications)
                .then((_) => _loadAll()),
            onProfileTap: () => context.push(AppRoutes.adminProfile),
            enableMenu: true,
          ),
          CachedDataNotice(
            screen: 'members_farmers',
            isOnline: _isOnline,
            offlineMessage: AppLocalizations.of(context).offlineStaffBody,
          ),

          Expanded(
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                : Column(
                    children: [
                      // ── Controls, pinned above the list ──────────────────
                      // Row 1: Add Member | Manage Accounts
                      // Row 2: Search | Filter
                      // Row 3: status chips (one line, scrolls sideways)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: MembersControls(
                          addLabel: l10n.farmerMgmtAddMember,
                          manageLabel: l10n.manageAccountsTitle,
                          onAddTap: _showAddMemberTypeSheet,
                          // Members tab is Admin-only (Decision D19) — an
                          // Officer never reaches this screen, so this is
                          // simply always available here.
                          onManageTap: () =>
                              context.push(AppRoutes.manageAdminAccounts),
                          searchController: _searchCtrl,
                          searchHint: l10n.farmerMgmtSearchHint,
                          onFilterTap: _showFilterSheet,
                          filterActive: !_filter.isDefault,
                          // Active · Inactive · Suspended · Pending · Rejected,
                          // each tappable; the count comes from the loaded
                          // list so the derived Inactive count is accurate.
                          chips: [
                            MembersStatusChip(
                              label: l10n.farmerMgmtAllFilter,
                              count: _allFarmers.length,
                              color: cs.primary,
                              selected: _filter.statusFilter == null,
                              onTap: () => _setStatusFilter(null),
                            ),
                            for (final s in MemberStatusExt.filterable)
                              MembersStatusChip(
                                label: _memberStatusLabel(l10n, s),
                                count: _statusCount(s),
                                color: _statusColor(s, cs),
                                selected: _filter.statusFilter == s,
                                onTap: () => _setStatusFilter(
                                  _filter.statusFilter == s ? null : s,
                                ),
                              ),
                          ],
                        ),
                      ),

                      // ── Farmer list ────────────────────────────────────────
                      Expanded(
                        child: RefreshIndicator(
                          color: AppConstants.primaryGreen,
                          onRefresh: _loadAll,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                            children: [
                              if (farmers.isEmpty)
                                _EmptyState(
                                  hasFilters:
                                      !_filter.isDefault || _searchQuery.isNotEmpty,
                                  cs: cs,
                                )
                              else ...[
                                ...visible.map(
                                  (f) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _FarmerCard(
                                      farmer: f,
                                      cs: cs,
                                      sagana: sagana,
                                      onTap: () => context.push(
                                        AppRoutes.farmerDetails,
                                        extra: f.userId,
                                      ),
                                      onMenuSelected: (value) =>
                                          _onMenuSelected(f, value),
                                    ),
                                  ),
                                ),
                                if (_visibleCount < farmers.length)
                                  Center(
                                    child: TextButton(
                                      onPressed: () => setState(
                                        () => _visibleCount += _pageSize,
                                      ),
                                      child: Text(
                                        l10n.farmerMgmtLoadMore(
                                          farmers.length - _visibleCount,
                                        ),
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
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status colour — shared by the filter chips and the status badge
// ─────────────────────────────────────────────────────────────────────────────

Color _statusColor(MemberStatus s, ColorScheme cs) {
  switch (s) {
    case MemberStatus.active:
      return AppConstants.successGreen;
    case MemberStatus.inactive:
      return cs.outline;
    case MemberStatus.suspended:
      return AppConstants.errorRed;
    case MemberStatus.pending:
      return AppConstants.warningAmber;
    case MemberStatus.rejected:
      return AppConstants.errorRed;
    case MemberStatus.draft:
      return cs.outline;
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
  final ValueChanged<String> onMenuSelected;

  const _FarmerCard({
    required this.farmer,
    required this.cs,
    required this.sagana,
    required this.onTap,
    required this.onMenuSelected,
  });

  /// The ⋯ menu for every status. Only the actions change by status; the
  /// design is the same for all: a popup with a divider before any
  /// destructive action.
  List<PopupMenuEntry<String>> _menuEntries(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx);
    final status = farmer.memberStatus;
    final entries = <PopupMenuEntry<String>>[];

    // What each status gets is decided in one place: MemberStatus.listActions.
    for (final action in status.listActions) {
      switch (action) {
        case MemberListAction.viewProfile:
          entries.add(_menuItem('view', Icons.person_outline_rounded,
              l10n.farmerMgmtActionViewProfile, cs.onSurface));
        case MemberListAction.approve:
          entries.add(_menuItem('approve', Icons.check_circle_rounded,
              l10n.farmerMgmtActionApproveMembership, AppConstants.successGreen));
        case MemberListAction.disapprove:
          entries.add(const PopupMenuDivider());
          entries.add(_menuItem('reject', Icons.cancel_rounded,
              l10n.farmerMgmtRejectApplicationAction, AppConstants.errorRed));
        case MemberListAction.sendNotification:
          entries.add(_menuItem('notice', Icons.campaign_outlined,
              l10n.farmerMgmtActionSendNotification, cs.onSurface));
        case MemberListAction.resetPassword:
          entries.add(_menuItem('reset', Icons.lock_reset_rounded,
              l10n.farmerMgmtActionResetPassword, cs.onSurface));
        case MemberListAction.issueLoan:
          entries.add(_menuItem('issueLoan', Icons.add_card_rounded,
              l10n.farmerDetailsIssueLoanAction, cs.onSurface));
        case MemberListAction.recordLoanPayment:
          entries.add(_menuItem('payment', Icons.payments_outlined,
              l10n.farmerMgmtActionRecordLoanPayment, cs.onSurface));
        case MemberListAction.toggleSuspend:
          final suspend = status.isEffectivelyActive;
          if (suspend) entries.add(const PopupMenuDivider());
          entries.add(_menuItem(
            'toggle',
            suspend ? Icons.person_off_outlined : Icons.person_rounded,
            suspend
                ? l10n.farmerMgmtActionSetSuspended
                : l10n.farmerMgmtActionSetActive,
            suspend ? AppConstants.errorRed : cs.onSurface,
          ));
        case MemberListAction.deleteApplicant:
          entries.add(const PopupMenuDivider());
          entries.add(_menuItem('delete', Icons.delete_outline_rounded,
              l10n.farmerMgmtDeleteRejectedAction, AppConstants.errorRed));
      }
    }
    return entries;
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem(
      value: value,
      child: _menuRow(icon, label, color),
    );
  }

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
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: the avatar, then name | status | menu on one line with the
            // contact lines beneath (see MemberTitleRow).
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
                      color: cs.primary.withValues(alpha: 0.10),
                      width: 2,
                    ),
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
                      // Name, status and menu on ONE line, centred together;
                      // the menu sits at the far right edge of the card.
                      MemberTitleRow(
                        name: farmer.fullName,
                        badge: _StatusBadge(status: farmer.memberStatus, cs: cs),
                        // One popup-menu style for every status (same as
                        // Inventory's ⋯ menu). Only the actions change by status.
                        menu: SizedBox(
                          width: 36,
                          height: 36,
                          child: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.more_vert_rounded,
                              color: cs.onSurfaceVariant,
                              size: 22,
                            ),
                            onSelected: onMenuSelected,
                            itemBuilder: (ctx) => _menuEntries(ctx),
                          ),
                        ),
                      ),
                      // Email and phone number on their own lines, under the
                      // name. A long address may wrap onto a second line
                      // instead of being cut off.
                      for (final line in farmer.contactLines) ...[
                        const SizedBox(height: 2),
                        Text(
                          line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            height: 1.3,
                            color: cs.outline,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Crop tags — every crop from this farmer's actual Crop Roster
            // (farmer_crops, same source the Farmer side and Farmer
            // Details both read), not just a 3-crop preview. Horizontal
            // scroll rather than Wrap so a farmer with many crops doesn't
            // blow out this card's height in the list.
            if (farmer.primaryCrops.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                          ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          l10n.farmerMgmtNoCropsRegistered,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: cs.outline,
                          ),
                        ),
              )
            else ...[
              Text(
                '${farmer.primaryCrops.length} crop${farmer.primaryCrops.length == 1 ? '' : 's'}',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
                      ),
              const SizedBox(height: 6),
              SizedBox(
                height: 26,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: farmer.primaryCrops.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => Container(
                            padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                            ),
                    alignment: Alignment.center,
                            child: Text(
                      farmer.primaryCrops[i],
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                            ),
            ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              l10n.farmerMgmtLastActivity(farmer.lastHarvestLabel),
              style: GoogleFonts.inter(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
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
                Flexible(
                  child: _LoanIndicator(farmer: farmer, cs: cs),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (farmer.isSynced
                                ? AppConstants.successGreen
                                : cs.outline)
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
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
                    Icon(
                      Icons.chevron_right_rounded,
                      color: cs.outline,
                      size: 16,
                    ),
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

/// One row in the rejected applicant's popup menu, styled like Inventory's
/// ⋯ menu rows.
Widget _menuRow(IconData icon, String label, Color color) {
  return Row(
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 12),
      Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    ],
  );
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        _memberStatusLabel(l10n, status).toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: GoogleFonts.inter(
          fontSize: 9,
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
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 15,
              color: AppConstants.successGreen,
            ),
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
            isOverdue
                ? l10n.farmerMgmtOverdueBadge
                : l10n.farmerMgmtActiveBadge,
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
          Icon(
            Icons.group_off_outlined,
            size: 48,
            color: cs.outline.withValues(alpha: 0.40),
          ),
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
                onTap: () => setState(
                  () => _state = _state.copyWith(statusFilter: null),
                ),
                  cs: cs,
                ),
                // Active / Inactive / Suspended / Pending / Rejected —
                // Draft is intentionally not a filter (those rows aren't
                // listed at all). Issue 5 / Decision D14.
              ...MemberStatusExt.filterable.map(
                (s) => _Chip(
                      label: _memberStatusLabel(l10n, s),
                      active: _state.statusFilter == s,
                  onTap: () =>
                      setState(() => _state = _state.copyWith(statusFilter: s)),
                      cs: cs,
                ),
              ),
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
              ...widget.cropNames.map(
                (c) => _Chip(
                      label: c,
                      active: _state.cropFilter == c,
                  onTap: () =>
                      setState(() => _state = _state.copyWith(cropFilter: c)),
                      cs: cs,
                ),
              ),
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
              ...LoanStatusSummary.values.map(
                (loanStatus) => _Chip(
                      label: _loanStatusLabel(l10n, loanStatus),
                      active: _state.loanFilter == loanStatus,
                      onTap: () => setState(
                    () => _state = _state.copyWith(loanFilter: loanStatus),
                  ),
                      cs: cs,
                ),
              ),
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
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
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
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: cs.primary,
                        ),
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
