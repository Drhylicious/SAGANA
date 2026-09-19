import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_profile_model.dart' show buyerGenderLabel;
import '../../../data/models/farmer_member_model.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/models/loan_model.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/models/analytics_model.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/repositories/account_management_repository.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../data/repositories/capital_contribution_repository.dart';
import '../../../data/repositories/farmer_details_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/temp_password_dialog.dart';

class FarmerDetailsScreen extends StatefulWidget {
  final String farmerId;
  const FarmerDetailsScreen({super.key, required this.farmerId});

  @override
  State<FarmerDetailsScreen> createState() => _FarmerDetailsScreenState();
}

class _FarmerDetailsScreenState extends State<FarmerDetailsScreen> {
  final _repo = FarmerDetailsRepository();
  final _capitalRepo = CapitalContributionRepository();
  final _reportsRepo = AdminReportsRepository();
  final _accountRepo = AccountManagementRepository();

  FarmerProfileModel?       _profile;
  FarmPerformanceSummary    _harvestSummary = FarmPerformanceSummary.empty;
  Map<String, dynamic>      _harvestStats   = {};
  List<LoanModel>           _loans          = [];
  MemberContribution?       _contribution;
  // Carries the exact same figures shown for this farmer on Member
  // Patronage Report (Palay/Peanut/Other Crops/Cooperative Purchases/
  // Total/Share%) — sourced by reusing fetchMemberContributionReport()
  // wholesale (share % is only computable against the coop-wide total for
  // the year, so there's no cheaper single-farmer equivalent) and picking
  // out this farmer's own row, guaranteeing it can never drift from what
  // the Report itself shows for the same farmer/year.
  MemberContributionRow?    _patronageRow;
  final int _patronageYear = DateTime.now().year;
  CapitalSharesModel?       _capitalShares;
  MemberCapitalSummary?     _capitalSummary;
  List<CapitalContributionEvent> _capitalLedger = [];
  List<MemberStatusEvent>   _statusHistory = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _programs = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchFarmerProfile(widget.farmerId),
      _repo.fetchHarvestSummary(widget.farmerId),
      _repo.fetchHarvestStats(widget.farmerId),
      _repo.fetchFarmerLoans(widget.farmerId),
      _repo.fetchCurrentYearContribution(widget.farmerId),
      _repo.fetchCapitalShares(widget.farmerId),
      _repo.fetchFarmerExpenses(widget.farmerId),
      _repo.fetchAssignedPrograms(widget.farmerId),
      _capitalRepo.fetchCapitalSummary(widget.farmerId),
      _capitalRepo.fetchLedger(widget.farmerId),
      _repo.fetchStatusHistory(widget.farmerId),
      _reportsRepo.fetchMemberContributionReport(_patronageYear),
    ]);
    if (!mounted) return;
    final patronageReport = results[11] as MemberContributionReportData;
    setState(() {
      _profile        = results[0] as FarmerProfileModel?;
      _harvestSummary = results[1] as FarmPerformanceSummary;
      _harvestStats   = results[2] as Map<String, dynamic>;
      _loans          = results[3] as List<LoanModel>;
      _contribution   = results[4] as MemberContribution?;
      _capitalShares  = results[5] as CapitalSharesModel?;
      _expenses       = results[6] as List<Map<String, dynamic>>;
      _programs       = results[7] as List<Map<String, dynamic>>;
      _capitalSummary = results[8] as MemberCapitalSummary?;
      _capitalLedger  = results[9] as List<CapitalContributionEvent>;
      _statusHistory  = results[10] as List<MemberStatusEvent>;
      _patronageRow   = patronageReport.rows.cast<MemberContributionRow?>().firstWhere(
            (r) => r!.farmerId == widget.farmerId,
            orElse: () => null,
          );
      _isLoading      = false;
    });
  }

  Future<void> _recordContribution() async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<_RecordContributionInput>(
      context: context,
      builder: (_) => const _RecordContributionDialog(),
    );
    if (result == null) return;
    try {
      await _capitalRepo.recordContribution(
        farmerId: widget.farmerId,
        amount: result.amount,
        source: result.source,
        note: result.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.farmerDetailsContributionRecorded,
              style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: AppConstants.successGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadAll();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.farmerDetailsContributionError,
              style: GoogleFonts.inter(fontSize: 13)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  double get _totalOutstanding => _loans
      .where((l) => !l.isPaid)
      .fold(0.0, (sum, l) => sum + l.remainingBalance);

  Future<String?> _promptSuspendReason() {
    final ctrl = TextEditingController();
    final l10n = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (dc) {
        final cs = Theme.of(dc).colorScheme;
        return AlertDialog(
          title: Text(l10n.farmerDetailsSuspendMemberTitle,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: l10n.farmerDetailsSuspendReasonHint,
              hintStyle: GoogleFonts.inter(fontSize: 12, color: cs.outline),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dc),
                child: Text(l10n.farmerMgmtCancel)),
            ElevatedButton(
              onPressed: () => Navigator.pop(dc, ctrl.text.trim()),
              child: Text(l10n.farmerMgmtNext),
            ),
          ],
        );
      },
    );
  }

  void _showActionsMenu() {
    final l10n = AppLocalizations.of(context);
    showManagementModal(
      context: context,
      builder: (_) => _ActionsMenu(
        status: _profile?.memberStatus ?? MemberStatus.active,
        onNotify: () {
          Navigator.pop(context);
          context.push(AppRoutes.announcementDashboard);
        },
        onRecordPayment: () {
          Navigator.pop(context);
          context.push(AppRoutes.recordPayment, extra: widget.farmerId);
        },
        onResetPassword: () async {
          Navigator.pop(context);
          try {
            final tempPassword =
                await _accountRepo.resetUserPassword(widget.farmerId);
            if (!mounted) return;
            await showTempPasswordDialog(
              context: context,
              name: _profile?.fullName ?? '',
              tempPassword: tempPassword,
            );
          } catch (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text(AppLocalizations.of(context).farmerMgmtResetPasswordError),
                backgroundColor: AppConstants.errorRed,
              ),
            );
          }
        },
        onToggleStatus: () async {
          Navigator.pop(context);
          final status = _profile?.memberStatus ?? MemberStatus.active;
          // Bugfix (verification pass): the toggle only applies to
          // Active/Inactive/Suspended. Pending/Rejected/Draft must not
          // reach here — the menu itself hides the row for them — but
          // stay defensive in case a stale menu instance calls through.
          if (!status.supportsSuspendToggle) return;
          if (!status.isEffectivelyActive) {
            // Suspended — reactivate, single tap.
            await _repo.setFarmerStatus(
                farmerId: widget.farmerId, status: 'active');
            _loadAll();
            return;
          }
          // Active or Inactive — suspend, two-step (Decision D17).
          final reason = await _promptSuspendReason();
          if (reason == null || reason.trim().isEmpty || !mounted) return;
          final ok = await showDialog<bool>(
            context: context,
            builder: (dc) => AlertDialog(
              title: Text(l10n.farmerMgmtConfirmSuspensionTitle,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
              content: Text(
                '${l10n.farmerMgmtSuspendMemberLine(_profile?.fullName ?? '')}\n'
                '${l10n.farmerMgmtSuspendOutcomeLine}\n'
                '${l10n.farmerMgmtReasonLine(reason.trim())}',
                style: GoogleFonts.inter(fontSize: 13),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dc, false),
                    child: Text(l10n.farmerMgmtBack)),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dc, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.errorRed,
                      foregroundColor: Colors.white),
                  child: Text(l10n.farmerMgmtSuspendAccountAction),
                ),
              ],
            ),
          );
          if (ok != true) return;
          await _repo.setFarmerStatus(
              farmerId: widget.farmerId,
              status: 'suspended',
              reason: reason.trim());
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

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
          child: CircularProgressIndicator(color: AppConstants.primaryGreen),
        ),
      );
    }

    if (_profile == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 40, color: cs.outline),
              const SizedBox(height: 12),
              Text(l10n.farmerDetailsNotFound,
                  style: GoogleFonts.poppins(
                      fontSize: 15, color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.pop(),
                child: Text(l10n.farmerDetailsGoBack),
              ),
            ],
          ),
        ),
      );
    }

    final profile = _profile!;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 64),
              Expanded(
                child: RefreshIndicator(
                  color: cs.primary,
                  onRefresh: _loadAll,
                  child: DefaultTabController(
                    length: 6,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: TabBar(
                            isScrollable: true,
                            labelColor: cs.primary,
                            unselectedLabelColor: cs.onSurfaceVariant,
                            indicatorColor: cs.primary,
                            tabs: [
                              Tab(text: l10n.farmerDetailsTabProfile),
                              Tab(text: l10n.farmerDetailsTabHarvest),
                              Tab(text: l10n.farmerDetailsTabLoans),
                              Tab(text: l10n.farmerDetailsTabContribution),
                              Tab(text: l10n.farmerDetailsTabExpenses),
                              Tab(text: l10n.farmerDetailsTabPrograms),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              ListView(
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                                children: [
                                  if (profile.memberStatus == MemberStatus.rejected) ...[
                                    _RejectedApplicationBanner(
                                        profile: profile, cs: cs),
                                    const SizedBox(height: 16),
                                  ],
                                  _IdentityCard(profile: profile, cs: cs, sagana: sagana),
                                  const SizedBox(height: 16),
                                  _FarmDetailsCard(profile: profile, cs: cs, sagana: sagana),
                                  const SizedBox(height: 16),
                                  _MemberPatronageCard(
                                    row: _patronageRow,
                                    year: _patronageYear,
                                    cs: cs,
                                    sagana: sagana,
                                  ),
                                  if (_statusHistory.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    _StatusHistoryCard(
                                      events: _statusHistory,
                                      cs: cs,
                                      sagana: sagana,
                                    ),
                                  ],
                                ],
                              ),
                              ListView(
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                                children: [
                                  _HarvestActivityCard(
                                    summary: _harvestSummary,
                                    stats: _harvestStats,
                                    cs: cs,
                                    sagana: sagana,
                                    onViewAll: () => context.push(
                                      AppRoutes.farmerHarvestHistory,
                                      extra: widget.farmerId,
                                    ),
                                  ),
                                ],
                              ),
                              ListView(
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                                children: [
                                  _LoanSummaryCard(
                                    loans: _loans,
                                    totalOutstanding: _totalOutstanding,
                                    cs: cs,
                                    sagana: sagana,
                                  ),
                                ],
                              ),
                              ListView(
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                                children: [
                                  _ContributionCard(
                                    contribution: _contribution,
                                    capitalShares: _capitalShares,
                                    capitalSummary: _capitalSummary,
                                    capitalLedger: _capitalLedger,
                                    cs: cs,
                                    sagana: sagana,
                                    onRecordContribution: _recordContribution,
                                    onViewFull: () => context.push(
                                      AppRoutes.memberContributionReport,
                                    ),
                                  ),
                                ],
                              ),
                              _ExpensesTab(expenses: _expenses, cs: cs, sagana: sagana),
                              _ProgramsTab(programs: _programs, cs: cs, sagana: sagana),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Top App Bar ─────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopAppBar(
              title: profile.fullName,
              onBack: () => context.pop(),
              onMenu: _showActionsMenu,
              sagana: sagana,
              cs: cs,
            ),
          ),

          // ── Bottom action bar ───────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomActionBar(
              cs: cs,
              sagana: sagana,
              onNotify: () =>
                  context.push(AppRoutes.announcementDashboard),
              onPay: () => context.push(
                AppRoutes.recordPayment,
                extra: widget.farmerId,
              ),
              onIssueLoan: () => context.push(
                AppRoutes.issueNewLoan,
                extra: widget.farmerId,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopAppBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onMenu;
  final SaganaColors sagana;
  final ColorScheme cs;

  const _TopAppBar({
    required this.title,
    required this.onBack,
    required this.onMenu,
    required this.sagana,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_vert_rounded, color: cs.primary),
                onPressed: onMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rejected Application banner (verification-pass fix — Issue 5 workflow)
// ─────────────────────────────────────────────────────────────────────────────

class _RejectedApplicationBanner extends StatelessWidget {
  final FarmerProfileModel profile;
  final ColorScheme cs;

  const _RejectedApplicationBanner({required this.profile, required this.cs});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reason = profile.rejectionReason?.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.errorRed.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cancel_rounded,
                  size: 18, color: AppConstants.errorRed),
              const SizedBox(width: 8),
              Text(l10n.farmerDetailsApplicationRejected,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.errorRed)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            (reason != null && reason.isNotEmpty)
                ? l10n.farmerMgmtReasonLine(reason)
                : l10n.farmerDetailsNoReasonRecorded,
            style: GoogleFonts.inter(
                fontSize: 12, color: cs.onSurface, height: 1.5),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.farmerDetailsRejectedKeptNote,
            style: GoogleFonts.inter(
                fontSize: 11, color: cs.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Identity Card
// ─────────────────────────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  final FarmerProfileModel profile;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _IdentityCard({
    required this.profile,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          // Status badge now lives in its own full-width Row so it always
          // anchors to the card's right edge. Previously it sat inside a
          // Stack whose only sized child was the identity Column — a Stack
          // shrinks to the width of its widest non-positioned child, so the
          // Positioned badge drifted left/right depending on name length
          // ("Jhon Drhy M. Salangsang" wrapping to two lines vs. "Juan Dela
          // Cruz" on one). That was the source of the inconsistent badge
          // placement between member cards.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppConstants.successGreen.withValues(alpha: 0.10),
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  profile.isVerified
                      ? l10n.farmerDetailsActiveMemberBadge
                      : l10n.farmerDetailsPendingVerificationBadge,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: profile.isVerified
                        ? AppConstants.successGreen
                        : AppConstants.warningAmber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.primary, width: 3),
            ),
            child: profile.hasPhoto
                ? ClipOval(
                    child: Image.network(
                      profile.profilePhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _avatarFallback(profile.fullName, cs),
                    ),
                  )
                : _avatarFallback(profile.fullName, cs),
          ),
          const SizedBox(height: 12),
          Text(
            profile.fullName,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.farmerDetailsMemberIdLine(
                profile.memberId ?? l10n.farmerDetailsNotYetAssigned),
            style: GoogleFonts.inter(
                fontSize: 12, color: cs.outline),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.farmerDetailsMemberSince(profile.memberSinceLabel) +
                (profile.purok != null ? ' • ${profile.purok}' : ''),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Divider(color: cs.outline.withValues(alpha: 0.10)),
          const SizedBox(height: 12),

          // Every Edit Profile field always renders here, populated or
          // not (placeholder "–" when empty) — previously only phone/email
          // showed up, and only when set, leaving Full Name/Purok/Date of
          // Birth/Gender invisible from this screen entirely. Mirrors
          // Buyer Details' identical field-grid layout (Issue 5).
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    child: _fieldTile(Icons.email_rounded,
                        l10n.emailAddress, profile.contactEmail, cs)),
                const SizedBox(width: 10),
                Expanded(
                    child: _fieldTile(Icons.phone_rounded,
                        l10n.adminProfilePhoneNumber, profile.phoneNumber, cs)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    child: _fieldTile(Icons.cake_rounded,
                        l10n.dateOfBirthLabel, profile.dateOfBirthLabel, cs)),
                const SizedBox(width: 10),
                Expanded(
                    child: _fieldTile(
                        Icons.person_outline_rounded,
                        l10n.addMemberGenderLabel,
                        buyerGenderLabel(l10n, profile.gender),
                        cs)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _fieldTile(Icons.map_outlined, l10n.adminProfilePurok, profile.purok, cs),
        ],
      ),
    );
  }

  Widget _fieldTile(IconData icon, String label, String? value, ColorScheme cs) {
    final hasValue = value != null && value.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: hasValue ? cs.primary : cs.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            hasValue ? value : '–',
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hasValue ? cs.onSurface : cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String name, ColorScheme cs) {
    final parts = name.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'
        : (name.isNotEmpty ? name[0] : '?');
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surfaceContainerHighest,
      ),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Farm Details Card (read-only — no edit; that's farmer-owned data)
// ─────────────────────────────────────────────────────────────────────────────

class _FarmDetailsCard extends StatelessWidget {
  final FarmerProfileModel profile;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _FarmDetailsCard({
    required this.profile,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          // Mini map preview if coordinates exist
          if (profile.hasCoordinates)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppConstants.radiusXl)),
              child: SizedBox(
                height: 130,
                child: IgnorePointer(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(
                          profile.farmLatitude!, profile.farmLongitude!),
                      initialZoom: 15,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.sp3coop.sagana',
                        // flutter_map cancels in-flight tile requests for
                        // tiles that go out of view (e.g. the screen closes
                        // mid-fetch) — expected, not a real failure. Without
                        // this it surfaces as a noisy "EXCEPTION CAUGHT BY
                        // IMAGE RESOURCE SERVICE" log.
                        errorTileCallback: (tile, error, stackTrace) {},
                      ),
                      MarkerLayer(markers: [
                        Marker(
                          point: LatLng(
                              profile.farmLatitude!, profile.farmLongitude!),
                          width: 36,
                          height: 36,
                          child: Icon(Icons.location_on_rounded,
                              color: cs.primary, size: 36),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (profile.farmName != null)
                  Text(
                    profile.farmName!,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _StatLabel(
                        label: l10n.farmerDetailsTotalArea,
                        value: profile.landAreaHectares != null
                            ? '${profile.landAreaHectares!.toStringAsFixed(1)} ha'
                            : l10n.farmerDetailsNotRecorded,
                        cs: cs,
                      ),
                    ),
                    Expanded(
                      child: _StatLabel(
                        label: l10n.farmerDetailsExperience,
                        value: profile.yearsFarming != null
                            ? l10n.farmerDetailsYearsValue(profile.yearsFarming!)
                            : l10n.farmerDetailsNotRecorded,
                        cs: cs,
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (profile.primaryCrops.isEmpty)
                  Text(
                    l10n.farmerDetailsNoCropsYet,
                    style: GoogleFonts.inter(
                        fontSize: 12, color: cs.outline),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: profile.primaryCrops
                        .map((c) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppConstants.secondaryContainer
                                    .withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(
                                    AppConstants.radiusFull),
                              ),
                              child: Text(
                                c,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF694300),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.06),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 14, color: cs.primary),
                      const SizedBox(width: 6),
                      // Flexible + ellipsis: the Tagalog sentence is about
                      // 25% longer than the English source and this
                      // centered Row had no width guard of its own.
                      Flexible(
                        child: Text(
                          l10n.farmerDetailsManagedByFarmer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
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

class _StatLabel extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  final bool alignEnd;

  const _StatLabel({
    required this.label,
    required this.value,
    required this.cs,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Harvest Activity Card
// ─────────────────────────────────────────────────────────────────────────────

class _HarvestActivityCard extends StatelessWidget {
  final FarmPerformanceSummary summary;
  final Map<String, dynamic> stats;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onViewAll;

  const _HarvestActivityCard({
    required this.summary,
    required this.stats,
    required this.cs,
    required this.sagana,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final count = stats['count'] as int? ?? 0;
    final lastEntry = stats['last_entry'] as String?;
    final lastEntryLabel = lastEntry != null
        ? _shortDate(DateTime.parse(lastEntry))
        : '—';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  value: '$count',
                  label: l10n.farmerDetailsRecordsLabel,
                  cs: cs,
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: cs.outline.withValues(alpha: 0.10),
              ),
              Expanded(
                child: _MiniStat(
                  value: summary.totalYieldKg.toStringAsFixed(0),
                  label: l10n.farmerDetailsTotalKgLabel,
                  cs: cs,
                ),
              ),
              Container(
                width: 1,
                height: 32,
                color: cs.outline.withValues(alpha: 0.10),
              ),
              Expanded(
                child: _MiniStat(
                  value: lastEntryLabel,
                  label: l10n.farmerDetailsLastEntryLabel,
                  cs: cs,
                  small: true,
                ),
              ),
            ],
          ),
          if (summary.cropBreakdown.isNotEmpty) ...[
            const SizedBox(height: 18),
            ...summary.cropBreakdown.take(4).map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(c.cropName,
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: cs.onSurface)),
                          Text('${c.quantityKg.toStringAsFixed(0)}kg',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: cs.outline)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: c.percentOfMax,
                          minHeight: 6,
                          backgroundColor:
                              cs.surfaceContainerHighest,
                          valueColor:
                              AlwaysStoppedAnimation(cs.primary),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onViewAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Flexible + ellipsis: this "View X" + chevron pattern is
                  // reused across several summary-card footers in this file
                  // (see farmerDetailsViewFullContribution below) and none
                  // of them had a width guard on the label.
                  Flexible(
                    child: Text(
                      l10n.farmerDetailsViewAllHarvests,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: cs.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _shortDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final ColorScheme cs;
  final bool small;

  const _MiniStat({
    required this.value,
    required this.label,
    required this.cs,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: small ? 14 : 20,
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, color: cs.outline),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loan Summary Card
// ─────────────────────────────────────────────────────────────────────────────

class _LoanSummaryCard extends StatelessWidget {
  final List<LoanModel> loans;
  final double totalOutstanding;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _LoanSummaryCard({
    required this.loans,
    required this.totalOutstanding,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activeLoans = loans.where((l) => !l.isPaid).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            sagana.cardBackground,
            cs.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.farmerDetailsTotalOutstanding,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: cs.outline),
                  ),
                  Text(
                    '₱${totalOutstanding.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: totalOutstanding > 0
                          ? AppConstants.warningAmber
                          : AppConstants.successGreen,
                    ),
                  ),
                ],
              ),
              Icon(
                Icons.account_balance_wallet_rounded,
                size: 30,
                color: totalOutstanding > 0
                    ? AppConstants.warningAmber
                    : AppConstants.successGreen,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (activeLoans.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppConstants.successGreen.withValues(alpha: 0.08),
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: AppConstants.successGreen, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    l10n.farmerDetailsNoActiveLoans,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppConstants.successGreen),
                  ),
                ],
              ),
            )
          else
            ...activeLoans.take(2).map((loan) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: sagana.cardBackground.withValues(alpha: 0.70),
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMd),
                    border: Border.all(
                        color: cs.outline.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              loan.referenceNo,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            l10n.farmerDetailsPercentPaid(
                                (loan.repaidPercent * 100).toStringAsFixed(0)),
                            style: GoogleFonts.inter(
                                fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: loan.repaidPercent,
                          minHeight: 5,
                          backgroundColor:
                              cs.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                            loan.isOverdue
                                ? cs.error
                                : AppConstants.successGreen,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            l10n.farmerDetailsRemainingBalance(
                                loan.remainingBalance.toStringAsFixed(2)),
                            style: GoogleFonts.inter(
                                fontSize: 11, color: cs.outline),
                          ),
                          if (loan.isOverdue)
                            Text(
                              l10n.farmerMgmtOverdueBadge,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: cs.error,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contribution Card
// ─────────────────────────────────────────────────────────────────────────────

class _ContributionCard extends StatelessWidget {
  final MemberContribution? contribution;
  final CapitalSharesModel? capitalShares;
  final MemberCapitalSummary? capitalSummary;
  final List<CapitalContributionEvent> capitalLedger;
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onRecordContribution;
  final VoidCallback onViewFull;

  const _ContributionCard({
    required this.contribution,
    required this.capitalShares,
    required this.capitalSummary,
    required this.capitalLedger,
    required this.cs,
    required this.sagana,
    required this.onRecordContribution,
    required this.onViewFull,
  });

  static String _sourceLabel(AppLocalizations l10n, String source) {
    switch (source) {
      case 'member_payment':
        return l10n.farmerDetailsSourcePayment;
      case 'patronage_capital':
        return l10n.farmerDetailsSourcePatronage;
      case 'manual_adjustment':
        return l10n.farmerDetailsSourceAdjustment;
      case 'opening_balance':
        return l10n.farmerDetailsSourceOpeningBalance;
      default:
        return source;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = capitalSummary;
    final contributionTotal =
        summary?.shares.totalContribution ?? capitalShares?.totalContribution ?? 0;
    final completedShares =
        summary?.shares.totalShares ?? capitalShares?.totalShares ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _StatLabel(
                  label: l10n.farmerDetailsVolumeToSp3(DateTime.now().year),
                  value: contribution != null
                      ? '${(contribution!.palaySalesKg + contribution!.peanutSalesKg + contribution!.otherCropsQtyKg).toStringAsFixed(0)}kg'
                      : l10n.farmerDetailsNoRecords,
                  cs: cs,
                ),
              ),
              Expanded(
                child: _StatLabel(
                  label: l10n.farmerDetailsCompletedShares,
                  value: '$completedShares (₱${(completedShares * 2000).toStringAsFixed(0)})',
                  cs: cs,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Capital contribution (Issue 4d) ─────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.farmerDetailsCapitalContribution,
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant)),
                    Text('₱${contributionTotal.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface)),
                  ],
                ),
                if (summary != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: summary.shareProgress,
                      minHeight: 6,
                      backgroundColor: cs.outline.withValues(alpha: 0.15),
                      color: AppConstants.primaryGreen,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    summary.meetsLoanEligibility
                        ? l10n.farmerDetailsMeetsMinimum(
                            summary.minimumForLoan.toStringAsFixed(0))
                        : l10n.farmerDetailsNeedsMore(
                            summary.loanShortfall.toStringAsFixed(0),
                            summary.minimumForLoan.toStringAsFixed(0)),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: summary.meetsLoanEligibility
                          ? AppConstants.successGreen
                          : AppConstants.warningAmber,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onRecordContribution,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(l10n.farmerDetailsRecordContribution,
                        style: GoogleFonts.poppins(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
                if (capitalLedger.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...capitalLedger.take(4).map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${_sourceLabel(l10n, e.source)} · ${e.createdAt.year}-${e.createdAt.month.toString().padLeft(2, '0')}-${e.createdAt.day.toString().padLeft(2, '0')}',
                                style: GoogleFonts.inter(
                                    fontSize: 11, color: cs.onSurfaceVariant),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${e.amount < 0 ? '−' : '+'}₱${e.amount.abs().toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: e.amount < 0
                                    ? AppConstants.errorRed
                                    : cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.farmerDetailsEstBalikTangkilik,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                    Text(
                      contribution != null
                          ? '₱${contribution!.estimatedTotal.toStringAsFixed(2)}'
                          : '₱0.00',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
                Icon(Icons.trending_up_rounded,
                    color: cs.primary.withValues(alpha: 0.30), size: 28),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onViewFull,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Flexible + ellipsis: "Tingnan ang Buong Kontribusyon" is
                  // ~30% longer than "View Full Contribution" and this
                  // centered Row had no width guard of its own.
                  Flexible(
                    child: Text(
                      l10n.farmerDetailsViewFullContribution,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: cs.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpensesTab extends StatelessWidget {
  final List<Map<String, dynamic>> expenses;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ExpensesTab({
    required this.expenses,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (expenses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.farmerDetailsNoExpenseHistory,
            style: GoogleFonts.inter(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      itemCount: expenses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final expense = expenses[index];
        final amount = expense['amount'] as num? ?? 0;
        final date = expense['expense_date'] as String?;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: cs.primary.withValues(alpha: 0.10),
                child: Icon(Icons.receipt_long_rounded, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense['description'] as String? ?? l10n.farmerDetailsExpenseFallback,
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      date != null ? date.split('T').first : '—',
                      style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                '₱${amount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.primary),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgramsTab extends StatelessWidget {
  final List<Map<String, dynamic>> programs;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ProgramsTab({
    required this.programs,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (programs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.farmerDetailsNoAssignedPrograms,
            style: GoogleFonts.inter(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      itemCount: programs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final program = programs[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sagana.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events_rounded, color: AppConstants.programPurple, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      program['name'] as String? ?? l10n.farmerDetailsProgramFallback,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                program['description'] as String? ?? l10n.farmerDetailsAssignedProgramFallback,
                style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Action Bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  final ColorScheme cs;
  final SaganaColors sagana;
  final VoidCallback onNotify;
  final VoidCallback onPay;
  final VoidCallback onIssueLoan;

  const _BottomActionBar({
    required this.cs,
    required this.sagana,
    required this.onNotify,
    required this.onPay,
    required this.onIssueLoan,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(top: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _OutlineActionButton(
                  icon: Icons.sms_outlined,
                  label: l10n.farmerDetailsNotifyAction,
                  onTap: onNotify,
                  cs: cs,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OutlineActionButton(
                  icon: Icons.payments_outlined,
                  label: l10n.farmerDetailsPayAction,
                  onTap: onPay,
                  cs: cs,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: onIssueLoan,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppConstants.primaryGreen,
                          AppConstants.primaryContainer,
                        ],
                      ),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusMd),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_card_rounded,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            l10n.farmerDetailsIssueLoanAction,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _OutlineActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          border: Border.all(color: cs.primary),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 4),
            // Flexible + ellipsis: this button sits in a narrow Expanded
            // slot alongside a sibling button and the "Issue Loan" gradient
            // button (see _ActionBar above) — "Magbayad" (Pay) is much
            // longer than "Pay" and this centered Row had no width guard.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions Menu (top-right ⋮)
// ─────────────────────────────────────────────────────────────────────────────

class _ActionsMenu extends StatelessWidget {
  final MemberStatus status;
  final VoidCallback onNotify;
  final VoidCallback onRecordPayment;
  final VoidCallback onToggleStatus;
  final VoidCallback onResetPassword;

  const _ActionsMenu({
    required this.status,
    required this.onNotify,
    required this.onRecordPayment,
    required this.onToggleStatus,
    required this.onResetPassword,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isActive = status.isEffectivelyActive;
    // Same status set the Members-list three-dot menu (_FarmerActionsSheet)
    // excludes Record Loan Payment for — a Pending applicant isn't a
    // member yet, and a Rejected one never was (Issue 5 verification fix).
    final canRecordPayment =
        status != MemberStatus.pending && status != MemberStatus.rejected;

    Widget row({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool destructive = false,
    }) {
      final color = destructive ? cs.error : cs.onSurface;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 14),
              Text(label,
                  style: GoogleFonts.inter(fontSize: 14, color: color)),
            ],
          ),
        ),
      );
    }

    return ManagementModalShell(
      title: l10n.farmerDetailsMemberActionsTitle,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Consistent with the Members-list three-dot menu's naming and
          // row order (Send Notification, Record Loan Payment, Set
          // Suspend/Active, Reset Password) — View Profile is deliberately
          // omitted, since the admin is already viewing this profile.
          row(
            icon: Icons.campaign_outlined,
            label: l10n.farmerMgmtActionSendNotification,
            onTap: onNotify,
          ),
          if (canRecordPayment)
            row(
              icon: Icons.payments_outlined,
              label: l10n.farmerMgmtActionRecordLoanPayment,
              onTap: onRecordPayment,
            ),
          // Bugfix (verification pass): Pending/Rejected/Draft have no
          // Active⇄Suspended toggle — Pending is reviewed via
          // Approve/Reject on the Members list; Rejected is reviewed only
          // by the applicant resubmitting (up to 3 attempts), never by an
          // admin "reactivating" it here.
          if (status.supportsSuspendToggle)
            row(
              icon: isActive
                  ? Icons.person_off_outlined
                  : Icons.person_rounded,
              label: isActive
                  ? l10n.farmerMgmtActionSetSuspended
                  : l10n.farmerMgmtActionSetActive,
              onTap: onToggleStatus,
              destructive: isActive,
            )
          else if (status == MemberStatus.rejected)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      l10n.farmerDetailsRejectedNoToggleNote,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          row(
            icon: Icons.lock_reset_rounded,
            label: l10n.farmerMgmtActionResetPassword,
            onTap: onResetPassword,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Record Contribution dialog (Issue 4d)
// ─────────────────────────────────────────────────────────────────────────────

class _RecordContributionInput {
  final double amount;
  final String source;
  final String? note;
  const _RecordContributionInput({
    required this.amount,
    required this.source,
    this.note,
  });
}

class _RecordContributionDialog extends StatefulWidget {
  const _RecordContributionDialog();

  @override
  State<_RecordContributionDialog> createState() =>
      _RecordContributionDialogState();
}

class _RecordContributionDialogState extends State<_RecordContributionDialog> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _source = 'member_payment';
  String? _error;

  Map<String, String> _sources(AppLocalizations l10n) => {
    'member_payment': l10n.farmerDetailsSourcePaymentFull,
    'patronage_capital': l10n.farmerDetailsSourcePatronageFull,
    'manual_adjustment': l10n.farmerDetailsSourceAdjustmentFull,
    'opening_balance': l10n.farmerDetailsSourceOpeningBalance,
  };

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submit(AppLocalizations l10n) {
    final raw = _amountCtrl.text.trim().replaceAll(',', '');
    final amount = double.tryParse(raw);
    if (amount == null || amount == 0) {
      setState(() => _error = l10n.farmerDetailsEnterNonZero);
      return;
    }
    if (amount < 0 && _source != 'manual_adjustment') {
      setState(() => _error = l10n.farmerDetailsOnlyAdjustmentNegative);
      return;
    }
    Navigator.pop(
      context,
      _RecordContributionInput(
        amount: amount,
        source: _source,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sources = _sources(l10n);
    return AlertDialog(
      title: Text(l10n.farmerDetailsRecordContribution,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [
                // Digits only, an optional single leading minus, one dot.
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
              ],
              decoration: InputDecoration(
                labelText: l10n.farmerDetailsAmountLabel,
                hintText: l10n.farmerDetailsAmountHint,
                prefixText: '₱ ',
              ),
            ),
            const SizedBox(height: 12),
            AppDropdownField<String>(
              value: _source,
              hintText: l10n.farmerDetailsSelectType,
              labelText: l10n.farmerDetailsTypeLabel,
              items: sources.keys.toList(),
              itemLabel: (key) => sources[key]!,
              onChanged: (v) => setState(() => _source = v ?? _source),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                labelText: l10n.farmerDetailsNoteOptional,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppConstants.errorRed)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.farmerMgmtCancel),
        ),
        ElevatedButton(
          onPressed: () => _submit(l10n),
          child: Text(l10n.farmerDetailsRecordAction),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Member Patronage card — carries this farmer's exact row from Member
// Patronage Report (Palay/Peanut/Other Crops/Cooperative Purchases/Total/
// Share%) onto their own Profile tab, so opening a specific farmer shows
// the same patronage breakdown the Report's list already shows for them,
// without having to go back to the Report to see it. Sourced from the
// same fetchMemberContributionReport() call the Report itself uses — see
// _FarmerDetailsScreenState._loadAll() — so it can never disagree with it.
// ─────────────────────────────────────────────────────────────────────────────

class _MemberPatronageCard extends StatelessWidget {
  final MemberContributionRow? row;
  final int year;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _MemberPatronageCard({
    required this.row,
    required this.year,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final r = row;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.paid_rounded, size: 18, color: AppConstants.primaryGreen),
              const SizedBox(width: 8),
              Text(
                'Member Patronage ($year)',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (r == null || (!r.hasContributed && r.programPurchasesAmount <= 0))
            Text(
              'No patronage activity recorded for $year.',
              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  currency.format(r.totalAmount),
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: cs.onSurface),
                ),
                Text(
                  '${r.sharePercent.toStringAsFixed(1)}% share',
                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.primaryGreen),
                ),
              ],
            ),
            if (r.hasContributed) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _patronageStat('Palay', '${r.palayQtyKg.toStringAsFixed(0)} kg (${currency.format(r.palayAmount)})', AppConstants.primaryGreen, cs),
                  const SizedBox(width: 16),
                  _patronageStat('Peanut', '${r.peanutQtyKg.toStringAsFixed(0)} kg (${currency.format(r.peanutAmount)})', AppConstants.amber, cs),
                ],
              ),
              if (r.otherCropsAmount > 0) ...[
                const SizedBox(height: 4),
                _patronageStat('Other Crops', '${r.otherCropsQtyKg.toStringAsFixed(0)} kg (${currency.format(r.otherCropsAmount)})', AppConstants.buyerBlue, cs),
              ],
            ],
            if (r.programPurchasesAmount > 0) ...[
              const SizedBox(height: 4),
              // _patronageStat() returns an Expanded — it must be a Row's
              // direct child (bounded main-axis width), never a Column's
              // direct child (unbounded height in this scrollable
              // context), which is what the other 3 stats above already
              // do correctly by each sitting inside their own Row.
              Row(children: [_patronageStat('Product Sales Program Patronage', currency.format(r.programPurchasesAmount), AppConstants.buyerBlue, cs)]),
            ],
          ],
        ],
      ),
    );
  }

  Widget _patronageStat(String label, String value, Color color, ColorScheme cs) {
    return Expanded(
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$label: $value',
              style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status History card — member_status_events audit trail (Issue 5 / D13)
// ─────────────────────────────────────────────────────────────────────────────

class _StatusHistoryCard extends StatelessWidget {
  final List<MemberStatusEvent> events;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _StatusHistoryCard({
    required this.events,
    required this.cs,
    required this.sagana,
  });

  static String _label(AppLocalizations l10n, String s) {
    switch (s) {
      case 'active':    return l10n.farmerMgmtStatusActiveLabel;
      case 'inactive':  return l10n.analyticsInactive;
      case 'suspended': return l10n.farmerMgmtStatusSuspendedLabel;
      case 'pending':   return l10n.buyerOrderDetailPendingTimestamp;
      case 'rejected':  return l10n.farmerMgmtStatusRejectedLabel;
      case 'draft':     return l10n.farmerMgmtStatusDraftLabel;
      default:          return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(l10n.farmerDetailsStatusHistoryTitle,
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
            ],
          ),
          const SizedBox(height: 12),
          ...events.map((e) {
            final d = e.createdAt.toLocal();
            final date =
                '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: cs.primary, shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.fromStatus != null
                              ? '${_label(l10n, e.fromStatus!)} → ${_label(l10n, e.toStatus)}'
                              : _label(l10n, e.toStatus),
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface),
                        ),
                        if (e.reason != null && e.reason!.trim().isNotEmpty)
                          Text(e.reason!.trim(),
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                  height: 1.4)),
                        Text(date,
                            style: GoogleFonts.inter(
                                fontSize: 10, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}