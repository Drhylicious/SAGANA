import '../../widgets/view_only_banner.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/management_modal.dart';
import '../../../core/utils/db_error_utils.dart';
import '../../../data/services/staff_permission_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/buyer_address_model.dart';
import '../../../data/models/farmer_member_model.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/models/loan_model.dart';
import '../../../data/models/contribution_model.dart';
import '../../../data/models/expense_model.dart';
import '../../../data/models/analytics_model.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../data/repositories/capital_contribution_repository.dart';
import '../../../data/repositories/farmer_details_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/member_contribution_card.dart';
import '../../widgets/member_profile_cards.dart';
import '../../widgets/member_discipline_card.dart';
import '../../widgets/expenses_view.dart';
import '../../widgets/loans_view.dart';
import '../../widgets/monthly_contribution_widgets.dart';
import '../../../data/models/monthly_contribution_model.dart';
import '../../../data/repositories/monthly_contribution_repository.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/program_origin_chip.dart';
import '../../../data/models/program_assistance_model.dart';
import '../../../data/repositories/program_assistance_repository.dart';
import '../farmer/my_programs_screen.dart' show MyProgramCard, MyProgramRound, groupProgramRounds;

class FarmerDetailsScreen extends StatefulWidget {
  final String farmerId;

  /// The tab to open on (0 = Profile, 1 = Harvest ...).
  final int initialTab;
  const FarmerDetailsScreen({
    super.key,
    required this.farmerId,
    this.initialTab = 0,
  });

  @override
  State<FarmerDetailsScreen> createState() => _FarmerDetailsScreenState();
}

class _FarmerDetailsScreenState extends State<FarmerDetailsScreen> {
  final _repo = FarmerDetailsRepository();
  final _capitalRepo = CapitalContributionRepository();
  final _reportsRepo = AdminReportsRepository();

  FarmerProfileModel? _profile;
  FarmPerformanceSummary _harvestSummary = FarmPerformanceSummary.empty;
  Map<String, dynamic> _harvestStats = {};
  List<LoanModel> _loans = [];
  // This Farmer's approved assistance (not a loan), shown first in the Loans tab. Read-only.
  List<AssistanceRequest> _assistance = [];
  // Carries the exact same figures shown for this farmer on Member
  // Contribution Report (Palay/Peanut/Other Crops/Cooperative Purchases/
  // Total/Share%) — sourced by reusing fetchMemberContributionReport()
  // wholesale (share % is only computable against the coop-wide total for
  // the year, so there's no cheaper single-farmer equivalent) and picking
  // out this farmer's own row, guaranteeing it can never drift from what
  // the Report itself shows for the same farmer/year.
  MemberContributionRow? _patronageRow;
  final int _patronageYear = DateTime.now().year;
  CapitalSharesModel? _capitalShares;
  MemberCapitalSummary? _capitalSummary;
  List<CapitalContributionEvent> _capitalLedger = [];
  // The Farmer's PHP 100 months (Contribution section), newest first.
  List<MonthlyContribution> _monthly = [];
  final _monthlyRepo = MonthlyContributionRepository();
  List<MemberStatusEvent> _statusHistory = [];
  List<Map<String, dynamic>> _expenses = [];
  FarmerProgramCards _programCards = const FarmerProgramCards();
  // Every address the farmer saved (the registration address for an outsider
  // applicant), default first. Empty when none is saved.
  List<BuyerAddressModel> _addresses = [];

  bool _isLoading = true;
  bool _isOnline = ConnectivityService.instance.isOnline;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay(context);
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    // Without a Farmer there is nothing to show, and every query would be
    // rejected by the database: go back instead of loading.
    if (widget.farmerId.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.farmerManagement);
        }
      });
      return;
    }
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchFarmerProfile(widget.farmerId),
      _repo.fetchHarvestSummary(widget.farmerId),
      _repo.fetchHarvestStats(widget.farmerId),
      _repo.fetchFarmerLoans(widget.farmerId),
      _repo.fetchCapitalShares(widget.farmerId),
      _repo.fetchFarmerExpenses(widget.farmerId),
      _repo.fetchProgramCards(widget.farmerId),
      _capitalRepo.fetchCapitalSummary(widget.farmerId),
      _capitalRepo.fetchLedger(widget.farmerId),
      _repo.fetchStatusHistory(widget.farmerId),
      _reportsRepo.fetchMemberContributionReport(_patronageYear),
      _repo.fetchAddresses(widget.farmerId),
      // Makes any month that is missing, then reads them all.
      () async {
        await _monthlyRepo.sync();
        return _monthlyRepo.fetchForFarmer(widget.farmerId);
      }(),
    ]);
    if (!mounted) return;
    final assistance = await ProgramAssistanceRepository().fetchApprovedFor(widget.farmerId);
    if (!mounted) return;
    final patronageReport = results[10] as MemberContributionReportData;
    setState(() {
      _profile = results[0] as FarmerProfileModel?;
      _addresses = results[11] as List<BuyerAddressModel>;
      _harvestSummary = results[1] as FarmPerformanceSummary;
      _harvestStats = results[2] as Map<String, dynamic>;
      _loans = results[3] as List<LoanModel>;
      _assistance = assistance;
      _capitalShares = results[4] as CapitalSharesModel?;
      _expenses = results[5] as List<Map<String, dynamic>>;
      _programCards = results[6] as FarmerProgramCards;
      _capitalSummary = results[7] as MemberCapitalSummary?;
      _capitalLedger = results[8] as List<CapitalContributionEvent>;
      _monthly = results[12] as List<MonthlyContribution>;
      _statusHistory = results[9] as List<MemberStatusEvent>;
      _patronageRow = patronageReport.rows
          .cast<MemberContributionRow?>()
          .firstWhere(
            (r) => r!.farmerId == widget.farmerId,
            orElse: () => null,
          );
      _isLoading = false;
    });
  }

  static String _stamp(DateTime t) =>
      DateFormat('MMM d, y · h:mm a').format(t.toLocal());

  CapitalContributionEvent? _reversalOf(CapitalContributionEvent e) {
    for (final x in _capitalLedger) {
      if (x.reversesEventId == e.id) return x;
    }
    return null;
  }

  CapitalContributionEvent? _originalOf(CapitalContributionEvent e) {
    for (final x in _capitalLedger) {
      if (x.id == e.reversesEventId) return x;
    }
    return null;
  }

  Future<void> _openEntry(CapitalContributionEvent e) async {
    await showManagementModal<void>(
      context: context,
      builder: (_) => _ContributionEntrySheet(
        entry: e,
        reversal: _reversalOf(e),
        original: _originalOf(e),
        stamp: _stamp,
      ),
    );
  }

  Future<void> _openHistory() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showManagementModal<CapitalContributionEvent>(
      context: context,
      builder: (ctx) {
        final reversedIds = {
          for (final x in _capitalLedger)
            if (x.reversesEventId != null) x.reversesEventId!,
        };
        final cs = Theme.of(ctx).colorScheme;
        return ManagementModalShell(
          title: l10n.farmerDetailsContributionHistory,
          bodyIsScrollable: true,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              for (final x in _capitalLedger)
                _LedgerRow(
                  entry: x,
                  reversed: reversedIds.contains(x.id),
                  sourceLabel: _ContributionCard._sourceLabel(
                    l10n,
                    x.source,
                    month: x.contributionMonth,
                    asOf: x.effectiveDate,
                  ),
                  cs: cs,
                  onTap: () => Navigator.of(ctx).pop(x),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) await _openEntry(picked);
  }

  Future<void> _recordMonthlyPayment(MonthlyContribution month) async {
    if (!requireManage(context, StaffModule.members)) return;
    final l10n = AppLocalizations.of(context);
    final input = await showRecordMonthlyPaymentDialog(context, month);
    if (input == null || !mounted) return;
    try {
      await _monthlyRepo.recordPayment(
        farmerId: widget.farmerId,
        month: month.month,
        amount: input.amount,
        paidOn: input.paidOn,
        reference: input.reference,
      );
      if (!mounted) return;
      AppToast.show(context, l10n.monthlyPaymentRecorded);
      await _loadAll();
    } catch (err) {
      if (!mounted) return;
      AppToast.show(context, friendlyErrorMessage(err), isError: true);
    }
  }

  Future<void> _setMonthWaiver(MonthlyContribution month, bool waive) async {
    if (!requireManage(context, StaffModule.members)) return;
    final l10n = AppLocalizations.of(context);
    String? reason;
    if (waive) {
      reason = await showWaiveMonthDialog(context, month);
      if (reason == null || !mounted) return;
    }
    try {
      await _monthlyRepo.setWaiver(
        farmerId: widget.farmerId,
        month: month.month,
        waive: waive,
        reason: reason,
      );
      if (!mounted) return;
      AppToast.show(
        context,
        waive ? l10n.monthlyWaiveDone : l10n.monthlyReinstateDone,
      );
      await _loadAll();
    } catch (err) {
      if (!mounted) return;
      AppToast.show(context, friendlyErrorMessage(err), isError: true);
    }
  }

  Future<void> _recordContribution() async {
    if (!requireManage(context, StaffModule.members)) return;
    final l10n = AppLocalizations.of(context);
    final result = await showManagementModal<_RecordContributionInput>(
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
        effectiveDate: result.effectiveDate,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.farmerDetailsContributionRecorded,
            style: GoogleFonts.inter(fontSize: 13),
          ),
          backgroundColor: AppConstants.midGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadAll();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.farmerDetailsContributionError,
            style: GoogleFonts.inter(fontSize: 13),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sagana = context.saganaColors;
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          children: [
            SubPageTopBar(
              title: l10n.farmerDetailsTitle,
              onBack: () => context.pop(),
            ),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SkeletonList(),
              ),
            ),
          ],
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
              Icon(Icons.error_outline_rounded, size: 40, color: cs.outline),
              const SizedBox(height: 12),
              Text(
                l10n.farmerDetailsNotFound,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                ),
              ),
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
              const TopBarSpacer(height: 64),
              CachedDataNotice(
                screen: FarmerDetailsRepository.cacheScreens(
                  widget.farmerId,
                ).first,
                otherScreens: FarmerDetailsRepository.cacheScreens(
                  widget.farmerId,
                ).skip(1).toList(),
                isOnline: _isOnline,
                offlineMessage: AppLocalizations.of(context).offlineStaffBody,
              ),
              Expanded(
                child: RefreshIndicator(
                  color: cs.primary,
                  onRefresh: _loadAll,
                  child: DefaultTabController(
                    length: 6,
                    initialIndex: widget.initialTab.clamp(0, 5),
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
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  24,
                                ),
                                children: [
                                  if (profile.memberStatus ==
                                      MemberStatus.rejected) ...[
                                    _RejectedApplicationBanner(
                                      profile: profile,
                                      cs: cs,
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  MemberIdentityCard(profile: profile),
                                  const SizedBox(height: 16),
                                  MemberResidentialAddressCard(
                                    addresses: _addresses,
                                  ),
                                  const SizedBox(height: 16),
                                  MemberFarmSection(profile: profile),
                                  // Restrictions and suspensions on record (read-only; staff
                                  // act from the ⋯ menu on the Members list).
                                  if (!profile.memberStatus.isApplicant) ...[
                                    const SizedBox(height: 16),
                                    MemberDisciplineCard(memberId: profile.userId),
                                  ],
                                  // Status History: every approval, disapproval,
                                  // suspension and reactivation, with the staff member
                                  // who made it and when. Every staff member reads it
                                  // (script 24); only the Manager sees Staff Accountability.
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
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  24,
                                ),
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
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  24,
                                ),
                                children: [
                                  ...loansViewChildren(
                                    context,
                                    loans: _loans,
                                    assistance: _assistance,
                                    isLoading: false,
                                    // The latest 5 loans and payments, folded away on
                                    // request; the full lists open read-only below.
                                    collapsible: true,
                                    onViewAllLoans: () => context.push(
                                      AppRoutes.farmerLoanHistory,
                                      extra: widget.farmerId,
                                    ),
                                    onViewAllPayments: () => context.push(
                                      AppRoutes.farmerPaymentHistory,
                                      extra: widget.farmerId,
                                    ),
                                  ),
                                ],
                              ),
                              ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  24,
                                ),
                                children: [
                                  _TabSectionHeader(
                                    icon: Icons.savings_rounded,
                                    title: l10n.contribSectionTitle,
                                    cs: cs,
                                  ),
                                  const SizedBox(height: 10),
                                  _ContributionCard(
                                    capitalShares: _capitalShares,
                                    capitalSummary: _capitalSummary,
                                    capitalLedger: _capitalLedger,
                                    cs: cs,
                                    sagana: sagana,
                                    canRecordContribution:
                                        !profile.memberStatus.isApplicant,
                                    onRecordContribution: _recordContribution,
                                    onOpenEntry: _openEntry,
                                    onViewAll: _openHistory,
                                    memberName: (profile.firstName?.trim().isNotEmpty ?? false)
                                        ? profile.firstName!.trim()
                                        : profile.fullName.split(' ').first,
                                    monthly: MonthlyContributionsCard(
                                      embedded: true,
                                      months: _monthly,
                                      isLoading: _isLoading,
                                      unassigned: _capitalLedger
                                          .where(
                                            (e) =>
                                                e.source == 'member_payment' &&
                                                e.contributionMonth == null,
                                          )
                                          .fold<double>(
                                            0,
                                            (t, e) => t + e.amount,
                                          ),
                                      onRecordPayment:
                                          profile.memberStatus.isApplicant
                                          ? null
                                          : _recordMonthlyPayment,
                                      onWaiver: profile.memberStatus.isApplicant
                                          ? null
                                          : _setMonthWaiver,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  _TabSectionHeader(
                                    icon: Icons.handshake_rounded,
                                    title:
                                        l10n.memberContributionPatronageSection,
                                    cs: cs,
                                  ),
                                  const SizedBox(height: 10),
                                  MemberContributionCard(
                                    row: _patronageRow,
                                    year: _patronageYear,
                                    onViewFull: () => context.push(
                                      AppRoutes.memberContributionReport,
                                    ),
                                  ),
                                ],
                              ),
                              _ExpensesTab(
                                expenses: _expenses,
                                cs: cs,
                                sagana: sagana,
                              ),
                              _ProgramsTab(
                                cards: _programCards,
                                cs: cs,
                                sagana: sagana,
                              ),
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
          // View-only: no ⋮ menu and no action bar. Every action on a member
          // (notify, reset password, issue loan, record a payment, suspend,
          // approve / disapprove) is in the ⋯ menu on the member's card in the
          // Members list.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SubPageTopBar(
              title: l10n.farmerDetailsTitle,
              onBack: () => context.pop(),
            ),
          ),
        ],
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
        border: Border.all(
          color: AppConstants.errorRed.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cancel_rounded,
                size: 18,
                color: AppConstants.errorRed,
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(
                l10n.farmerDetailsApplicationRejected,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.errorRed,
                ),
              )),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            (reason != null && reason.isNotEmpty)
                ? l10n.farmerMgmtReasonLine(reason)
                : l10n.farmerDetailsNoReasonRecorded,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: cs.onSurface,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.farmerDetailsRejectedKeptNote,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
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
    final totalHarvestCount = stats['count'] as int? ?? 0;
    final thisYearYieldKg = (stats['this_year_kg'] as num?)?.toDouble() ?? 0.0;
    final unsyncedCount = stats['unsynced_count'] as int? ?? 0;
    final yieldLabel = thisYearYieldKg % 1 == 0
        ? thisYearYieldKg.toStringAsFixed(0)
        : thisYearYieldKg.toStringAsFixed(1);
    final hasUnsynced = unsyncedCount > 0;
    final receivedCount = stats['received_count'] as int? ?? 0;
    final receivedKg = (stats['received_kg'] as num?)?.toDouble() ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          // Same 3 KPIs as the farmer-facing Harvest History screen
          // (Total Harvest / This Year's Yield / Sync Status) — previously
          // Records/Total KG/Last Entry, which didn't correspond to
          // anything the farmer themselves sees.
          Row(
            children: [
              Expanded(
                child: ReportIconStatCard(
                  icon: Icons.calendar_month_rounded,
                  accent: AppConstants.primaryGreen,
                  label: AppLocalizations.of(context).reportsTotalHarvest,
                  value: '$totalHarvestCount',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ReportIconStatCard(
                  icon: Icons.eco_rounded,
                  accent: AppConstants.successGreen,
                  label: AppLocalizations.of(context).enhThisYearSYield,
                  value: '$yieldLabel kg',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ReportIconStatCard(
                  icon: hasUnsynced
                      ? Icons.sync_rounded
                      : Icons.check_circle_outline_rounded,
                  accent: hasUnsynced
                      ? AppConstants.warningAmber
                      : AppConstants.successGreen,
                  label: AppLocalizations.of(context).enhSyncStatus,
                  value: hasUnsynced
                      ? AppLocalizations.of(
                          context,
                        ).enhUnsynced((unsyncedCount).toString())
                      : AppLocalizations.of(context).reportsSynced,
                ),
              ),
            ],
          ),
          // Produce received from a Cooperative Program: labeled, and kept out of the harvest figures above.
          if (receivedCount > 0) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProgramOriginChip(label: l10n.cropFromProgram),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.farmerDetailsProgramReceived(receivedCount, formatQuantity(receivedKg)),
                    style: GoogleFonts.inter(fontSize: 11, height: 1.4, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
          if (summary.cropBreakdown.isNotEmpty) ...[
            const SizedBox(height: 18),
            ...summary.cropBreakdown
                .take(4)
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: Text(
                              c.cropName,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: cs.onSurface,
                              ),
                            )),
                            Text(
                              '${formatQuantity(c.quantityKg)}kg',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: cs.outline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: c.percentOfMax,
                            minHeight: 6,
                            backgroundColor: cs.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(cs.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
                  // (see farmerDetailsViewPatronageReport below) and none
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
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: cs.primary,
                  ),
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
// Loan Summary Card
// ─────────────────────────────────────────────────────────────────────────────

class _TabSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final ColorScheme cs;
  const _TabSectionHeader({
    required this.icon,
    required this.title,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contribution Card
// ─────────────────────────────────────────────────────────────────────────────

class _ContributionCard extends StatelessWidget {
  final CapitalSharesModel? capitalShares;
  final MemberCapitalSummary? capitalSummary;
  final List<CapitalContributionEvent> capitalLedger;
  final ColorScheme cs;
  final SaganaColors sagana;

  /// False for an applicant: capital is recorded for members only.
  final bool canRecordContribution;
  final VoidCallback onRecordContribution;
  final void Function(CapitalContributionEvent) onOpenEntry;
  final VoidCallback onViewAll;

  /// The member's first name, for the Capital Share Progress message.
  final String memberName;

  /// The Monthly Contributions card, shown inside this one.
  final Widget monthly;

  const _ContributionCard({
    required this.capitalShares,
    required this.capitalSummary,
    required this.capitalLedger,
    required this.cs,
    required this.sagana,
    required this.canRecordContribution,
    required this.onRecordContribution,
    required this.onOpenEntry,
    required this.onViewAll,
    required this.memberName,
    required this.monthly,
  });

  static String _sourceLabel(
    AppLocalizations l10n,
    String source, {
    DateTime? month,
    DateTime? asOf,
  }) {
    switch (source) {
      case 'member_payment':
        // A monthly payment says which month it was for.
        return month == null
            ? l10n.farmerDetailsSourcePayment
            : '${l10n.contribSourceMonthly} (${DateFormat('MMM yyyy').format(month)})';
      case 'purchase_discount':
        return l10n.contribSourceDiscount;
      case 'purchase_share':
        return l10n.contribSourcePurchaseShare;
      case 'offer_share':
        return l10n.contribSourceOfferShare;
      case 'patronage_capital':
        return l10n.farmerDetailsSourcePatronage;
      case 'manual_adjustment':
        return l10n.farmerDetailsSourceAdjustment;
      case 'opening_balance':
        // Starting Capital says the date the member held it, when it has one.
        return asOf == null
            ? l10n.farmerDetailsSourceOpeningBalance
            : l10n.contribStartingAsOf(DateFormat('MMM d, y').format(asOf));
      default:
        return source;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = capitalSummary;
    final contributionTotal =
        summary?.shares.totalContribution ??
        capitalShares?.totalContribution ??
        0;
    final completedShares =
        summary?.shares.totalShares ?? capitalShares?.totalShares ?? 0;
    // The next full share: (completed + 1) whole shares. The bar fills toward it.
    final shareValue =
        summary?.shares.shareValuePerUnit ?? capitalShares?.shareValuePerUnit ?? 2000;
    final requiredAmount = (completedShares + 1) * shareValue;
    final remaining = (requiredAmount - contributionTotal).clamp(0.0, double.infinity).toDouble();
    final progress = requiredAmount > 0
        ? (contributionTotal / requiredAmount).clamp(0.0, 1.0).toDouble()
        : 0.0;
    String peso(double v) => v == v.roundToDouble()
        ? '₱${NumberFormat('#,##0').format(v)}'
        : '₱${NumberFormat('#,##0.00').format(v)}';
    final reversedIds = {
      for (final e in capitalLedger)
        if (e.reversesEventId != null) e.reversesEventId!,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Capital Share Progress: how close the member is to the next full share ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  l10n.capShareProgressTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              // Opening balance and corrections only: payments are recorded per month.
              if (canRecordContribution)
                PopupMenuButton<String>(
                  tooltip: l10n.contribAdjustCapital,
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.more_vert_rounded, size: 20, color: cs.outline),
                  onSelected: (_) => onRecordContribution(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'adjust',
                      child: Text(l10n.contribAdjustCapital),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  peso(contributionTotal),
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l10n.capShareRequired(peso(requiredAmount)),
                  style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: cs.outline.withValues(alpha: 0.15),
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.capSharePercentDone((progress * 100).floor()),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              Text(
                l10n.capShareRemaining(peso(remaining)),
                style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            completedShares == 0
                ? l10n.capShareMsgNone(
                    memberName,
                    peso(contributionTotal),
                    peso(shareValue),
                  )
                : l10n.capShareMsgSome(
                    memberName,
                    completedShares,
                    peso(contributionTotal),
                  ),
            style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: cs.onSurface),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
          const SizedBox(height: 12),
          Text(
            l10n.capShareResult(completedShares),
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          // Loan eligibility stays: it is checked against the Capital Share.
          if (summary != null) ...[
            const SizedBox(height: 6),
            Text(
              summary.meetsLoanEligibility
                  ? l10n.farmerDetailsMeetsMinimum(
                      summary.minimumForLoan.toStringAsFixed(0),
                    )
                  : l10n.farmerDetailsNeedsMore(
                      summary.loanShortfall.toStringAsFixed(0),
                      summary.minimumForLoan.toStringAsFixed(0),
                    ),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: summary.meetsLoanEligibility
                    ? AppConstants.successGreen
                    : AppConstants.warningAmber,
              ),
            ),
          ],

          // ── Monthly Contributions: what is due each month ───────────────────
          const SizedBox(height: 14),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
          const SizedBox(height: 14),
          Text(
            l10n.monthlyContribTitle,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          monthly,

          // ── History: every entry, whatever its source ───────────────────────
          if (capitalLedger.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
            const SizedBox(height: 14),
            Text(
              l10n.contribHistoryTitle,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            ...capitalLedger
                .take(4)
                .map(
                  (e) => _LedgerRow(
                    entry: e,
                    reversed: reversedIds.contains(e.id),
                    sourceLabel: _sourceLabel(
                      l10n,
                      e.source,
                      month: e.contributionMonth,
                      asOf: e.effectiveDate,
                    ),
                    cs: cs,
                    onTap: () => onOpenEntry(e),
                  ),
                ),
            if (capitalLedger.length > 4)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onViewAll,
                  child: Text(
                    l10n.farmerDetailsViewAllEntries(capitalLedger.length),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One ledger entry: type and date on the left, the signed amount on the right.
/// A reversed entry is struck through and tagged; a reversal carries its own tag.
class _LedgerRow extends StatelessWidget {
  final CapitalContributionEvent entry;
  final bool reversed;
  final String sourceLabel;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _LedgerRow({
    required this.entry,
    required this.reversed,
    required this.sourceLabel,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final e = entry;
    final tag = e.isReversal
        ? l10n.farmerDetailsReversalTag
        : (reversed ? l10n.farmerDetailsReversedTag : null);
    final muted = reversed;
    final day = DateFormat('MMM d, y').format(e.createdAt.toLocal());
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: Row(
          children: [
            Expanded(
              // What it is, then when (and a tag for an old cancellation).
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sourceLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: muted ? cs.onSurfaceVariant : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tag == null ? day : '$day · $tag',
                    style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${e.amount < 0 ? '−' : '+'}₱${NumberFormat('#,##0.00').format(e.amount.abs())}',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                decoration: muted ? TextDecoration.lineThrough : null,
                color: muted
                    ? cs.onSurfaceVariant
                    : (e.amount < 0 ? AppConstants.errorRed : cs.onSurface),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

/// Everything about one ledger entry: who recorded it and when, and, if it was
/// reversed earlier, who reversed it, when and why. Read only: a wrong amount is
/// fixed with a Correction.
class _ContributionEntrySheet extends StatelessWidget {
  final CapitalContributionEvent entry;
  final CapitalContributionEvent? reversal; // the entry that cancels this one
  final CapitalContributionEvent? original; // the entry this one cancels
  final String Function(DateTime) stamp;

  const _ContributionEntrySheet({
    required this.entry,
    required this.reversal,
    required this.original,
    required this.stamp,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final e = entry;
    final unknown = l10n.farmerDetailsRecordedBySystem;
    final money = NumberFormat('#,##0.00');
    String sign(double v) => '${v < 0 ? '−' : '+'}₱${money.format(v.abs())}';

    Widget line(IconData icon, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color ?? cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: color ?? cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );

    final reversed = reversal != null;

    return ManagementModalShell(
      title: l10n.farmerDetailsContributionDetails,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _ContributionCard._sourceLabel(
                    l10n,
                    e.source,
                    month: e.contributionMonth,
                    asOf: e.effectiveDate,
                  ),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                sign(e.amount),
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  decoration: reversed ? TextDecoration.lineThrough : null,
                  color: reversed
                      ? cs.onSurfaceVariant
                      : (e.amount < 0 ? AppConstants.errorRed : cs.onSurface),
                ),
              ),
            ],
          ),
          if (e.isReversal) ...[
            line(
              Icons.undo_rounded,
              l10n.farmerDetailsReversedByOn(
                e.recordedByName ?? unknown,
                stamp(e.createdAt),
              ),
            ),
            if ((e.reversalReason ?? '').isNotEmpty)
              line(
                Icons.notes_rounded,
                l10n.farmerDetailsReversalReason(e.reversalReason!),
              ),
            if (original != null)
              line(
                Icons.link_rounded,
                l10n.farmerDetailsCancelsEntry(
                  '₱${money.format(original!.amount.abs())}',
                  original!.recordedByName ?? unknown,
                  stamp(original!.createdAt),
                ),
              ),
          ] else ...[
            line(
              Icons.edit_note_rounded,
              l10n.farmerDetailsRecordedByOn(
                e.recordedByName ?? unknown,
                stamp(e.createdAt),
              ),
            ),
            if ((e.note ?? '').isNotEmpty)
              line(Icons.notes_rounded, l10n.farmerDetailsNoteLine(e.note!)),
            if (reversal != null) ...[
              line(
                Icons.undo_rounded,
                l10n.farmerDetailsReversedByOn(
                  reversal!.recordedByName ?? unknown,
                  stamp(reversal!.createdAt),
                ),
                color: AppConstants.warningAmber,
              ),
              if ((reversal!.reversalReason ?? '').isNotEmpty)
                line(
                  Icons.notes_rounded,
                  l10n.farmerDetailsReversalReason(reversal!.reversalReason!),
                ),
            ],
            if (e.source == 'patronage_capital' && !reversed)
              line(
                Icons.info_outline_rounded,
                l10n.farmerDetailsReverseElsewhere,
              ),
          ],
          // A wrong amount is fixed with a Correction, never by cancelling the record.
          if (!reversed && !e.isReversal) ...[
            const SizedBox(height: 14),
            Text(
              l10n.farmerDetailsFixWithCorrection,
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.4,
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expenses and Programs tabs. The layout and card design follow the farmer's
// own My Expenses and My Programs screens. The rows come from the same
// fetchFarmerExpenses / fetchAssignedPrograms calls as before. The period and
// purpose filters run on those loaded rows, so nothing is fetched again.
// ─────────────────────────────────────────────────────────────────────────────

/// One expense row, read from the map fetchFarmerExpenses returns.
/// The Farmer's expenses, exactly as their own My Expenses screen shows them (period
/// total and chips, category breakdown, subsidy note, every entry with its detail
/// sheet), but strictly read-only: the display widgets are the Farmer screen's own
/// (expensesViewChildren), and nothing here can add, edit or delete a record.
class _ExpensesTab extends StatefulWidget {
  final List<Map<String, dynamic>> expenses;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ExpensesTab({
    required this.expenses,
    required this.cs,
    required this.sagana,
  });

  @override
  State<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<_ExpensesTab> {
  // Same default period as the Farmer's My Expenses screen.
  ExpensePeriod _period = ExpensePeriod.thisMonth;

  /// The entries of the chosen period, newest first (the Farmer's query keeps
  /// rows from the period's start date on, ordered by expense date).
  List<ExpenseModel> get _inPeriod {
    final start = _period.startDate;
    final rows = <ExpenseModel>[];
    for (final map in widget.expenses) {
      try {
        final e = ExpenseModel.fromMap(map);
        final day = DateTime(e.expenseDate.year, e.expenseDate.month, e.expenseDate.day);
        if (start == null || !day.isBefore(DateTime(start.year, start.month, start.day))) {
          rows.add(e);
        }
      } catch (_) {
        // A row that cannot be read is left out rather than breaking the tab.
      }
    }
    rows.sort((a, b) {
      final byDate = b.expenseDate.compareTo(a.expenseDate);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final items = _inPeriod;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: expensesViewChildren(
        context,
        period: _period,
        onPeriodChanged: (p) => setState(() => _period = p),
        expenses: items,
        breakdown: buildExpenseBreakdown(items),
        isLoading: false,
      ),
    );
  }
}

/// The Farmer's programs, exactly as their own My Programs screen shows them (every round, the outcome, the
/// decision, the harvest return, the loan request), but strictly read-only: no buttons, nothing to open.
class _ProgramsTab extends StatefulWidget {
  final FarmerProgramCards cards;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ProgramsTab({
    required this.cards,
    required this.cs,
    required this.sagana,
  });

  @override
  State<_ProgramsTab> createState() => _ProgramsTabState();
}

class _ProgramsTabState extends State<_ProgramsTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  // 'all' | 'distribution' | 'sales'
  String _purpose = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = widget.cs;

    // One card per program: the latest round. Earlier rounds sit under History on that card.
    final groups = groupProgramRounds(widget.cards.entries);
    final entries = groups.current;
    if (entries.isEmpty) {
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

    final visible = entries.where((p) {
      if (_purpose == 'sales' && !p.isSalesProgram) return false;
      if (_purpose == 'distribution' && p.isSalesProgram) return false;
      if (_query.isEmpty) return true;
      return p.programName.toLowerCase().contains(_query);
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          decoration: InputDecoration(
            hintText: l10n.farmerDetailsProgSearchHint,
            prefixIcon: const Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 12),
        // The same chips as the Farmer's Programs screen, each with its count.
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final (value, label) = [
                ('all', l10n.farmerMgmtAllFilter),
                ('distribution', l10n.programMgmtFilterDistribution),
                ('sales', l10n.programMgmtFilterSales),
              ][i];
              final count = value == 'all'
                  ? entries.length
                  : entries
                        .where((p) => p.isSalesProgram == (value == 'sales'))
                        .length;
              final isSelected = _purpose == value;
              return GestureDetector(
                onTap: () => setState(() => _purpose = value),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppConstants.primaryGreen
                        : context.saganaColors.cardBackground,
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                    border: Border.all(
                      color: isSelected
                          ? AppConstants.primaryGreen
                          : cs.outline.withValues(alpha: 0.25),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$label ($count)',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              l10n.farmerDetailsProgNoMatch,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final p in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MyProgramCard(
                readOnly: true,
                entry: p,
                report: widget.cards.reportByMember[p.id],
                harvestReturn: widget.cards.returns.byMember[p.id],
                resolution: widget.cards.returns.resolutionByMember[p.id],
                redistStatus: widget.cards.redistByMember[p.id],
                assistRequest: widget.cards.assistByMember[p.id],
                history: [
                  for (final e in groups.earlier[p.id] ?? const [])
                    MyProgramRound(
                      entry: e,
                      report: widget.cards.reportByMember[e.id],
                      resolution: widget.cards.returns.resolutionByMember[e.id],
                      assistRequest: widget.cards.assistByMember[e.id],
                    ),
                ],
                formatDate: (d) => DateFormat('MMM d, y').format(d),
                statusLabel: (s) => switch (s) {
                  'withdrawn' => l10n.farmerProgStatusWithdrawn,
                  'completed' => l10n.farmerProgStatusCompleted,
                  _ => l10n.farmerProgStatusActive,
                },
              ),
            ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Record Contribution dialog (Issue 4d)
// ─────────────────────────────────────────────────────────────────────────────

/// The small caption above a form field, the same style the dropdown uses, so every
/// field in a form is labelled the same way.
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _RecordContributionInput {
  final double amount;
  final String source;
  final String? note;

  /// Starting Capital only: the date the member actually held the capital.
  final DateTime? effectiveDate;
  const _RecordContributionInput({
    required this.amount,
    required this.source,
    this.note,
    this.effectiveDate,
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
  String _source = 'manual_adjustment';
  String? _error;
  DateTime? _startingDate;
  String? _dateError;

  bool get _isStarting => _source == 'opening_balance';

  Future<void> _pickStartingDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startingDate ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: AppLocalizations.of(context).startingCapitalDateLabel,
    );
    if (picked != null) {
      setState(() {
        _startingDate = picked;
        _dateError = null;
      });
    }
  }

  // Only a correction can take money out, so only it may carry a minus sign.
  bool get _allowsNegative => _source == 'manual_adjustment';

  /// What the chosen type means, shown under the Type field.
  String _typeHint(AppLocalizations l10n) => switch (_source) {
    'opening_balance' => l10n.contribTypeHintStarting,
    _ => l10n.contribTypeHintCorrection,
  };

  Map<String, String> _sources(AppLocalizations l10n) => {
    // A monthly payment is recorded against its month in Monthly Contributions.
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
    if (amount < 0 && !_allowsNegative) {
      setState(() => _error = l10n.farmerDetailsOnlyAdjustmentNegative);
      return;
    }
    // Starting Capital must say when the member actually held it (day, month, year).
    if (_isStarting && _startingDate == null) {
      setState(() => _dateError = l10n.startingCapitalDateRequired);
      return;
    }
    Navigator.pop(
      context,
      _RecordContributionInput(
        amount: amount,
        source: _source,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        effectiveDate: _isStarting ? _startingDate : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sources = _sources(l10n);
    return ManagementModalShell(
      title: l10n.contribAdjustTitle,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // What kind of entry first, then how much: the type decides whether a
          // minus sign is allowed. Every field has its caption above it, and the
          // Type field explains the chosen type right under itself.
          AppDropdownField<String>(
            value: _source,
            hintText: l10n.farmerDetailsSelectType,
            labelText: l10n.farmerDetailsTypeLabel,
            helperText: _typeHint(l10n),
            items: sources.keys.toList(),
            itemLabel: (key) => sources[key]!,
            onChanged: (v) => setState(() {
              _source = v ?? _source;
              _error = null;
              _dateError = null;
            }),
          ),
          // Starting Capital needs the date the member actually held the capital,
          // so a past year lands in that year's Member Contribution Report.
          if (_isStarting) ...[
            const SizedBox(height: 16),
            _FieldLabel(l10n.startingCapitalDateLabel),
            InkWell(
              onTap: _pickStartingDate,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: InputDecorator(
                decoration: InputDecoration(
                  hintText: l10n.startingCapitalDateHint,
                  suffixIcon: const Icon(Icons.calendar_month_rounded),
                ),
                isEmpty: _startingDate == null,
                child: Text(
                  _startingDate == null
                      ? ''
                      : DateFormat('MMMM d, y').format(_startingDate!),
                  style: GoogleFonts.inter(fontSize: 14),
                ),
              ),
            ),
            // Under the field, flush left like the Type field's note (not inset
            // by the input decoration), and red when the date is missing.
            const SizedBox(height: 4),
            Text(
              _dateError ?? l10n.startingCapitalDateHelp,
              textAlign: TextAlign.start,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: _dateError != null
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _FieldLabel(l10n.contribAmountLabel),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.numberWithOptions(
              decimal: true,
              signed: _allowsNegative,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                _allowsNegative
                    ? RegExp(r'^-?\d*\.?\d{0,2}')
                    : RegExp(r'^\d*\.?\d{0,2}'),
              ),
            ],
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              hintText: l10n.farmerDetailsAmountHint,
              prefixText: '₱ ',
            ),
          ),
          // Notes sit flush left under the field, like the Type field's note.
          if (_error != null || _allowsNegative) ...[
            const SizedBox(height: 4),
            Text(
              _error ?? l10n.contribAdjustSignHint,
              textAlign: TextAlign.start,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: _error != null
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _FieldLabel(l10n.contribNoteLabel),
          TextField(
            controller: _noteCtrl,
            maxLength: 200,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: l10n.contribNoteHint,
              counterText: '',
            ),
          ),
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: l10n.farmerDetailsRecordAction,
        onPrimary: () => _submit(l10n),
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
      case 'active':
        return l10n.farmerMgmtStatusActiveLabel;
      case 'inactive':
        return l10n.analyticsInactive;
      case 'suspended':
        return l10n.farmerMgmtStatusSuspendedLabel;
      case 'pending':
        return l10n.buyerOrderDetailPendingTimestamp;
      case 'rejected':
        return l10n.farmerMgmtStatusRejectedLabel;
      case 'draft':
        return l10n.farmerMgmtStatusDraftLabel;
      default:
        return s;
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
              Flexible(child: Text(
                l10n.farmerDetailsStatusHistoryTitle,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              )),
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
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
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
                            color: cs.onSurface,
                          ),
                        ),
                        if (e.reason != null && e.reason!.trim().isNotEmpty)
                          Text(
                            e.reason!.trim(),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        if ((e.actorName ?? '').trim().isNotEmpty)
                          Text(
                            l10n.farmerDetailsHistoryBy(
                              e.actorName!.trim(),
                              e.actorRole == 'admin'
                                  ? l10n.staffRoleManager
                                  : l10n.staffRoleOfficer,
                            ),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        Text(
                          date,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
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
