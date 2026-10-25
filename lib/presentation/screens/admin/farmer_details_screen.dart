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
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/member_patronage_card.dart';
import '../../widgets/member_profile_cards.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../data/services/connectivity_service.dart';

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

  FarmerProfileModel? _profile;
  FarmPerformanceSummary _harvestSummary = FarmPerformanceSummary.empty;
  Map<String, dynamic> _harvestStats = {};
  List<LoanModel> _loans = [];
  MemberContribution? _contribution;
  // Carries the exact same figures shown for this farmer on Member
  // Patronage Report (Palay/Peanut/Other Crops/Cooperative Purchases/
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
  List<MemberStatusEvent> _statusHistory = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _programs = [];
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
      _repo.fetchAddresses(widget.farmerId),
    ]);
    if (!mounted) return;
    final patronageReport = results[11] as MemberContributionReportData;
    setState(() {
      _profile = results[0] as FarmerProfileModel?;
      _addresses = results[12] as List<BuyerAddressModel>;
      _harvestSummary = results[1] as FarmPerformanceSummary;
      _harvestStats = results[2] as Map<String, dynamic>;
      _loans = results[3] as List<LoanModel>;
      _contribution = results[4] as MemberContribution?;
      _capitalShares = results[5] as CapitalSharesModel?;
      _expenses = results[6] as List<Map<String, dynamic>>;
      _programs = results[7] as List<Map<String, dynamic>>;
      _capitalSummary = results[8] as MemberCapitalSummary?;
      _capitalLedger = results[9] as List<CapitalContributionEvent>;
      _statusHistory = results[10] as List<MemberStatusEvent>;
      _patronageRow = patronageReport.rows
          .cast<MemberContributionRow?>()
          .firstWhere(
            (r) => r!.farmerId == widget.farmerId,
            orElse: () => null,
          );
      _isLoading = false;
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

  double get _totalOutstanding => _loans
      .where((l) => !l.isPaid)
      .fold(0.0, (sum, l) => sum + l.remainingBalance);

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
              const SizedBox(height: 64),
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
                                  // Status History is shown while an application is
                                  // under review (Pending) or was Disapproved. Once
                                  // approved it is hidden; the records themselves
                                  // stay in the database untouched.
                                  if (_statusHistory.isNotEmpty &&
                                      (profile.memberStatus ==
                                              MemberStatus.pending ||
                                          profile.memberStatus ==
                                              MemberStatus.rejected)) ...[
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
                                  _LoanSummaryCard(
                                    loans: _loans,
                                    totalOutstanding: _totalOutstanding,
                                    cs: cs,
                                    sagana: sagana,
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
                                    title: l10n.memberContributionCapitalSection,
                                    cs: cs,
                                  ),
                                  const SizedBox(height: 10),
                                  _ContributionCard(
                                    capitalShares: _capitalShares,
                                    capitalSummary: _capitalSummary,
                                    capitalLedger: _capitalLedger,
                                    cs: cs,
                                    sagana: sagana,
                                    canRecordContribution: !profile.memberStatus.isApplicant,
                                    onRecordContribution: _recordContribution,
                                  ),
                                  const SizedBox(height: 20),
                                  _TabSectionHeader(
                                    icon: Icons.handshake_rounded,
                                    title: l10n.memberContributionPatronageSection,
                                    cs: cs,
                                  ),
                                  const SizedBox(height: 10),
                                  MemberPatronageCard(
                                    row: _patronageRow,
                                    contribution: _contribution,
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
                                programs: _programs,
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
              Text(
                l10n.farmerDetailsApplicationRejected,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.errorRed,
                ),
              ),
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

class _StatLabel extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;

  const _StatLabel({
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fixed height reserved for up to 2 lines — a longer label
        // wrapping to a second line (e.g. "Volume to Cooperative
        // (2026)") would otherwise push its own value down while a
        // shorter one-line label next to it (e.g. "Completed Shares")
        // doesn't, misaligning the two values that follow.
        SizedBox(
          height: 30,
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
          ),
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
    final totalHarvestCount = stats['count'] as int? ?? 0;
    final thisYearYieldKg = (stats['this_year_kg'] as num?)?.toDouble() ?? 0.0;
    final unsyncedCount = stats['unsynced_count'] as int? ?? 0;
    final yieldLabel = thisYearYieldKg % 1 == 0
        ? thisYearYieldKg.toStringAsFixed(0)
        : thisYearYieldKg.toStringAsFixed(1);
    final hasUnsynced = unsyncedCount > 0;

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
                  label: 'Total Harvest',
                  value: '$totalHarvestCount',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ReportIconStatCard(
                  icon: Icons.eco_rounded,
                  accent: AppConstants.successGreen,
                  label: "This Year's Yield",
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
                  label: 'Sync Status',
                  value: hasUnsynced ? '$unsyncedCount Unsynced' : 'Synced',
                ),
              ),
            ],
          ),
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
                            Text(
                              c.cropName,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: cs.onSurface,
                              ),
                            ),
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
          colors: [sagana.cardBackground, cs.surfaceContainerHighest],
        ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.farmerDetailsTotalOutstanding,
                    style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
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
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: AppConstants.successGreen,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.farmerDetailsNoActiveLoans,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppConstants.successGreen,
                    ),
                  ),
                ],
              ),
            )
          else
            ...activeLoans
                .take(2)
                .map(
                  (loan) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: sagana.cardBackground.withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMd,
                      ),
                      border: Border.all(
                        color: cs.outline.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                (loan.repaidPercent * 100).toStringAsFixed(0),
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: loan.repaidPercent,
                            minHeight: 5,
                            backgroundColor: cs.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(
                              loan.isOverdue
                                  ? cs.error
                                  : AppConstants.successGreen,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.farmerDetailsRemainingBalance(
                                loan.remainingBalance.toStringAsFixed(2),
                              ),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: cs.outline,
                              ),
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
                  ),
                ),
        ],
      ),
    );
  }
}

/// The heading above each group of cards on the Contribution tab, so Capital
/// and Patronage read as two separate things.
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

  const _ContributionCard({
    required this.capitalShares,
    required this.capitalSummary,
    required this.capitalLedger,
    required this.cs,
    required this.sagana,
    required this.canRecordContribution,
    required this.onRecordContribution,
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
        summary?.shares.totalContribution ??
        capitalShares?.totalContribution ??
        0;
    final completedShares =
        summary?.shares.totalShares ?? capitalShares?.totalShares ?? 0;

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
          _StatLabel(
            label: l10n.farmerDetailsCompletedShares,
            value:
                '$completedShares (₱${(completedShares * 2000).toStringAsFixed(0)})',
            cs: cs,
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
                    Text(
                      l10n.farmerDetailsCapitalContribution,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '₱${contributionTotal.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
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
                            summary.minimumForLoan.toStringAsFixed(0),
                          )
                        : l10n.farmerDetailsNeedsMore(
                            summary.loanShortfall.toStringAsFixed(0),
                            summary.minimumForLoan.toStringAsFixed(0),
                          ),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: summary.meetsLoanEligibility
                          ? AppConstants.successGreen
                          : AppConstants.warningAmber,
                    ),
                  ),
                ],
                if (canRecordContribution) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onRecordContribution,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(
                      l10n.farmerDetailsRecordContribution,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                ],
                if (capitalLedger.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...capitalLedger
                      .take(4)
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${_sourceLabel(l10n, e.source)} · ${e.createdAt.year}-${e.createdAt.month.toString().padLeft(2, '0')}-${e.createdAt.day.toString().padLeft(2, '0')}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
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
                        ),
                      ),
                ],
              ],
            ),
          ),
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
class _ExpenseRecord {
  final String category;
  final String description;
  final double amount;
  final DateTime date;
  final bool isSubsidy;

  const _ExpenseRecord({
    required this.category,
    required this.description,
    required this.amount,
    required this.date,
    required this.isSubsidy,
  });

  static _ExpenseRecord? fromMap(Map<String, dynamic> map) {
    final date = DateTime.tryParse(map['expense_date'] as String? ?? '');
    if (date == null) return null;
    return _ExpenseRecord(
      category: map['category'] as String? ?? 'Other',
      description: map['description'] as String? ?? '',
      amount: (map['amount'] as num? ?? 0).toDouble(),
      date: date,
      isSubsidy: map['is_subsidy'] as bool? ?? false,
    );
  }
}

/// Keeps the rows in the selected period, using the same start dates as
/// ExpensePeriod.startDate and comparing calendar days.
bool _inPeriod(_ExpenseRecord e, ExpensePeriod period) {
  final start = period.startDate;
  if (start == null) return true;
  final day = DateTime(e.date.year, e.date.month, e.date.day);
  return !day.isBefore(DateTime(start.year, start.month, start.day));
}

/// Same rules as ExpenseRepository.buildBreakdown: subsidised entries count
/// as zero, subsidy-only categories still appear, and the result is sorted
/// by total.
List<CategoryBreakdown> _breakdownFor(List<_ExpenseRecord> rows) {
  final totals = <String, double>{};
  final hasSubsidy = <String, bool>{};
  for (final e in rows) {
    if (e.isSubsidy) {
      hasSubsidy[e.category] = true;
    } else {
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    }
  }
  for (final cat in hasSubsidy.keys) {
    totals.putIfAbsent(cat, () => 0);
  }
  if (totals.isEmpty) return [];
  final maxVal = totals.values.reduce((a, b) => a > b ? a : b);
  return totals.entries
      .map(
        (e) => CategoryBreakdown(
          category: e.key,
          total: e.value,
          percentOfMax: maxVal > 0 ? (e.value / maxVal).clamp(0.0, 1.0) : 1.0,
          hasSubsidy: hasSubsidy.containsKey(e.key),
        ),
      )
      .toList()
    ..sort((a, b) => b.total.compareTo(a.total));
}

String _periodLabel(AppLocalizations l10n, ExpensePeriod p) {
  switch (p) {
    case ExpensePeriod.allTime:
      return l10n.farmerAnalyticsPeriodAllTime;
    case ExpensePeriod.thisMonth:
      return l10n.farmerAnalyticsPeriodThisMonth;
    case ExpensePeriod.thisQuarter:
      return l10n.farmerAnalyticsPeriodThisQuarter;
    case ExpensePeriod.thisYear:
      return l10n.farmerAnalyticsPeriodThisYear;
  }
}

/// Pill filter chip, same look as the farmer's period filter.
class _FilterPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? AppConstants.primaryContainer
                : const Color(0xFFD5ECF8),
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: active
                  ? AppConstants.onPrimaryContainer
                  : AppConstants.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: AppConstants.onSurfaceVariant,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppConstants.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  final List<CategoryBreakdown> breakdown;
  final String title;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _BreakdownCard({
    required this.breakdown,
    required this.title,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          for (final b in breakdown)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        b.category,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        b.total > 0 ? '₱${money.format(b.total)}' : '₱0.00',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: b.hasSubsidy && b.total == 0
                          ? 1.0
                          : b.percentOfMax,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFCFE6F2),
                      valueColor: AlwaysStoppedAnimation(
                        b.hasSubsidy && b.total == 0
                            ? AppConstants.successGreen
                            : categoryColor(b.category),
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

class _TransactionCard extends StatelessWidget {
  final _ExpenseRecord record;
  final String subsidyTag;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _TransactionCard({
    required this.record,
    required this.subsidyTag,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: record.isSubsidy
            ? const BorderRadius.horizontal(
                right: Radius.circular(AppConstants.radiusLg),
              )
            : BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: categoryBgColor(record.category).withValues(alpha: 0.40),
              shape: BoxShape.circle,
            ),
            child: Icon(
              categoryIcon(record.category),
              color: categoryColor(record.category),
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.category,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    if (record.isSubsidy) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppConstants.successGreen,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull,
                          ),
                        ),
                        child: Text(
                          subsidyTag,
                          style: GoogleFonts.inter(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  record.description.isEmpty ? '—' : record.description,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  DateFormat('MMM d, yyyy').format(record.date),
                  style: GoogleFonts.inter(fontSize: 10, color: cs.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₱${NumberFormat('#,##0.00').format(record.amount)}',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: record.isSubsidy
                  ? AppConstants.successGreen
                  : cs.onSurface,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 18, color: cs.outline),
        ],
      ),
    );

    if (!record.isSubsidy) {
      return SizedBox(width: double.infinity, child: card);
    }
    // A subsidy row gets its own accent stripe. A single BoxDecoration can't
    // combine a border radius with a one-sided colour, so the stripe is a
    // separate widget beside the card.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: const BoxDecoration(
              color: AppConstants.successGreen,
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(AppConstants.radiusLg),
              ),
            ),
          ),
          Expanded(child: card),
        ],
      ),
    );
  }
}

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
  // Same default period as the farmer's My Expenses screen.
  ExpensePeriod _period = ExpensePeriod.thisMonth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = widget.cs;
    final sagana = widget.sagana;
    final all = widget.expenses
        .map(_ExpenseRecord.fromMap)
        .whereType<_ExpenseRecord>()
        .toList();

    if (all.isEmpty) {
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

    final rows = all.where((e) => _inPeriod(e, _period)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final breakdown = _breakdownFor(rows);
    // The period total leaves out subsidised entries, as on the farmer's
    // screen: it is the sum of the breakdown bars.
    final periodTotal = breakdown.fold(0.0, (sum, b) => sum + b.total);
    CategoryBreakdown? top;
    for (final b in breakdown) {
      if (b.total > 0) {
        top = b;
        break;
      }
    }
    final money = NumberFormat('#,##0');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        SizedBox(
          height: 98,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _MetricTile(
                label: l10n.farmerDetailsExpPeriodTotal,
                value: '₱${money.format(periodTotal)}',
                color: AppConstants.primaryGreen,
                icon: Icons.payments_rounded,
              ),
              const SizedBox(width: 10),
              _MetricTile(
                label: l10n.farmerDetailsExpTopCategory,
                value: top?.category ?? l10n.farmerDetailsExpNoneYet,
                color: top != null
                    ? categoryColor(top.category)
                    : AppConstants.outline,
                icon: top != null
                    ? categoryIcon(top.category)
                    : Icons.category_outlined,
              ),
              const SizedBox(width: 10),
              _MetricTile(
                label: l10n.farmerDetailsExpEntries,
                value: '${rows.length}',
                color: AppConstants.buyerBlue,
                icon: Icons.receipt_long_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in ExpensePeriod.values)
                _FilterPill(
                  label: _periodLabel(l10n, p),
                  active: p == _period,
                  onTap: () => setState(() => _period = p),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (breakdown.isNotEmpty) ...[
          _BreakdownCard(
            breakdown: breakdown,
            title: l10n.farmerDetailsExpCategoryBreakdown,
            cs: cs,
            sagana: sagana,
          ),
          const SizedBox(height: 18),
        ],
        Text(
          l10n.farmerAnalyticsRecentTransactionsTitle,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              l10n.farmerDetailsExpNoTransactions,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final e in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TransactionCard(
                record: e,
                subsidyTag: l10n.farmerDetailsExpSubsidyTag,
                cs: cs,
                sagana: sagana,
              ),
            ),
      ],
    );
  }
}

class _ProgramCard extends StatelessWidget {
  final Map<String, dynamic> program;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ProgramCard({
    required this.program,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isSales = program['program_purpose'] == 'sales';
    final accent = isSales
        ? AppConstants.successGreen
        : AppConstants.programPurple;
    final description = program['description'] as String? ?? '';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(AppConstants.radiusLg),
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: sagana.cardBackground,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(AppConstants.radiusLg),
                ),
                border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusMd,
                          ),
                        ),
                        child: Icon(
                          isSales
                              ? Icons.storefront_rounded
                              : Icons.volunteer_activism_rounded,
                          color: accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              program['name'] as String? ??
                                  l10n.farmerDetailsProgramFallback,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isSales
                                  ? l10n.farmerDetailsProgSalesPurpose
                                  : l10n.farmerDetailsProgDistributionPurpose,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull,
                          ),
                        ),
                        child: Text(
                          l10n.farmerDetailsProgStatusActive,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Divider(
                      height: 1,
                      color: cs.outline.withValues(alpha: 0.10),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
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

class _ProgramsTab extends StatefulWidget {
  final List<Map<String, dynamic>> programs;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _ProgramsTab({
    required this.programs,
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

    if (widget.programs.isEmpty) {
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

    final visible = widget.programs.where((p) {
      final isSales = p['program_purpose'] == 'sales';
      if (_purpose == 'sales' && !isSales) return false;
      if (_purpose == 'distribution' && isSales) return false;
      if (_query.isEmpty) return true;
      return (p['name'] as String? ?? '').toLowerCase().contains(_query);
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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterPill(
                label: l10n.farmerMgmtAllFilter,
                active: _purpose == 'all',
                onTap: () => setState(() => _purpose = 'all'),
              ),
              _FilterPill(
                label: l10n.programMgmtFilterDistribution,
                active: _purpose == 'distribution',
                onTap: () => setState(() => _purpose = 'distribution'),
              ),
              _FilterPill(
                label: l10n.programMgmtFilterSales,
                active: _purpose == 'sales',
                onTap: () => setState(() => _purpose = 'sales'),
              ),
            ],
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
              child: _ProgramCard(program: p, cs: cs, sagana: widget.sagana),
            ),
      ],
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
      title: Text(
        l10n.farmerDetailsRecordContribution,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
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
              Text(
                _error!,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppConstants.errorRed,
                ),
              ),
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
              Text(
                l10n.farmerDetailsStatusHistoryTitle,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
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
