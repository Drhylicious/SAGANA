import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_loan_model.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/listing_filter_modal.dart';
import '../../widgets/loan_choice_chip.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// Loan History — Admin (all-loans registry).
/// Pushed above the shell. Route: /admin/loans/history, extra: String? statusFilter
///
/// Doubles as the destination for the Dashboard's "See all" links under
/// Overdue/Active — statusFilter arrives pre-set in that case. Online-only,
/// same rationale as Loan Details: this is a review screen, not part of the
/// BOD-meeting workflow that needed offline support.
///
/// Date filtering now uses the shared ReportPeriod enum (same one driving
/// Sales/Harvest/Expense/Loan Report's period chips) instead of a
/// screen-local _DateRange — this both keeps the filter UI consistent
/// across the Reports module and lets the export button hand the
/// currently selected period straight to Export Center.
class LoanHistoryScreen extends StatefulWidget {
  final String? initialStatusFilter;

  const LoanHistoryScreen({super.key, this.initialStatusFilter});

  @override
  State<LoanHistoryScreen> createState() => _LoanHistoryScreenState();
}

class _LoanHistoryScreenState extends State<LoanHistoryScreen> {
  final _repo = AdminLoanRepository();
  final _searchController = TextEditingController();

  bool _isOnline = true;
  bool _isLoading = true;
  bool _offlineUnavailable = false;

  String? _statusFilter;
  ReportPeriod _period = ReportPeriod.allTime;
  String _searchQuery = '';

  AllTimeLoanSummary _summary = AllTimeLoanSummary.empty();
  List<AdminLoanSummary> _loans = [];

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.initialStatusFilter;
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime? _periodCutoff() {
    final now = DateTime.now();
    switch (_period) {
      case ReportPeriod.thisMonth:
        return DateTime(now.year, now.month, 1);
      case ReportPeriod.thisQuarter:
        final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        return DateTime(now.year, quarterStartMonth, 1);
      case ReportPeriod.thisYear:
        return DateTime(now.year, 1, 1);
      case ReportPeriod.allTime:
        return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _offlineUnavailable = false;
    });

    if (!_isOnline) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _offlineUnavailable = true;
      });
      return;
    }

    final results = await Future.wait([
      _repo.fetchAllTimeLoanSummary(),
      _repo.fetchAllLoans(
        statusFilter: _statusFilter,
        issuedAfter: _periodCutoff(),
      ),
    ]);

    if (!mounted) return;
    setState(() {
      _summary = results[0] as AllTimeLoanSummary;
      _loans = results[1] as List<AdminLoanSummary>;
      _isLoading = false;
    });
  }

  void _setStatusFilter(String? status) {
    setState(() => _statusFilter = status);
    _load();
  }

  void _setPeriod(ReportPeriod period) {
    setState(() => _period = period);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildTopBar(context, l10n, cs),
          Expanded(child: _buildBody(context, l10n, cs, sagana)),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return SubPageTopBar(title: l10n.loanHistoryTitle, onBack: () => context.pop());
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    if (_offlineUnavailable) {
      return _buildMessageState(
        Icons.wifi_off_rounded,
        l10n.loanHistoryUnavailableOffline,
        cs,
      );
    }

    final visibleLoans = _loans.applySearch(_searchQuery);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingSafeH,
          AppConstants.spacingGutter,
          AppConstants.spacingSafeH,
          AppConstants.spacingSafeH,
        ),
        children: [
          _buildStatCard(context, l10n, cs, sagana),
          const SizedBox(height: AppConstants.spacingGutter),
          _buildSearchRow(context, l10n, cs),
          const SizedBox(height: AppConstants.spacingMd),
          _buildStatusChips(l10n, cs),
          if (_period != ReportPeriod.allTime) ...[
            const SizedBox(height: AppConstants.spacingSm),
            _buildActivePeriodTag(l10n, cs),
          ],
          const SizedBox(height: AppConstants.spacingGutter),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Padding(padding: EdgeInsets.all(16), child: SkeletonList()),
            )
          else if (visibleLoans.isEmpty)
            _buildMessageState(
              Icons.receipt_long_outlined,
              _statusFilter == null
                  ? l10n.loanHistoryNoResults
                  : l10n.loanHistoryNoResultsForFilter,
              cs,
            )
          else
            ...visibleLoans.map(
              (loan) => _buildLoanRow(context, loan, cs, sagana, l10n),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageState(IconData icon, String message, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );
    final healthColor = _summary.isHealthy
        ? AppConstants.successGreen
        : AppConstants.warningAmber;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        // Accent-tinted, matching the KPI-card visual language used
        // throughout the rest of this review — was a plain white card
        // with just a drop shadow, which read as flat/unfinished next to
        // everything else.
        color: healthColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: healthColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: healthColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusSm,
                      ),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 15,
                      color: healthColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.loanHistoryTotalIssued(_summary.totalLoanCount),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: healthColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  _summary.isHealthy
                      ? l10n.loanHistoryHealthy
                      : l10n.loanHistoryNeedsAttention,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: healthColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            currency.format(_summary.totalIssued),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 26,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              Expanded(
                child: _statBlock(
                  l10n.loanHistoryTotalCollected,
                  currency.format(_summary.totalCollected),
                  cs,
                ),
              ),
              const SizedBox(width: AppConstants.spacingSm),
              Expanded(
                child: _statBlock(
                  l10n.loanDashTotalOutstanding,
                  currency.format(_summary.totalOutstanding),
                  cs,
                ),
              ),
              const SizedBox(width: AppConstants.spacingSm),
              Expanded(
                child: _statBlock(
                  l10n.loanHistoryRate,
                  '${_summary.repaymentRatePercent.toStringAsFixed(0)}%',
                  cs,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBlock(String label, String value, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  /// Row 1: the search box with the Filter button beside it. The button is as
  /// tall as the box and drawn like it; it turns green while a date period is
  /// applied.
  Widget _buildSearchRow(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final periodActive = _period != ReportPeriod.allTime;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildSearchField(context, l10n, cs)),
          const SizedBox(width: AppConstants.spacingSm),
          Tooltip(
            message: l10n.loanHistoryFilterTooltip,
            child: Material(
              color: periodActive
                  ? AppConstants.primaryGreen
                  : context.saganaColors.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: InkWell(
                onTap: _openPeriodFilter,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                child: Container(
                  width: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    border: Border.all(
                      color: periodActive
                          ? AppConstants.primaryGreen
                          : cs.outline.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 22,
                    color: periodActive ? Colors.white : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Row 2: the status chips (All / Active Loans / Overdue Loans / Paid), each
  /// its own selectable chip, in a row that scrolls sideways when the screen is
  /// too narrow to show all four.
  Widget _buildStatusChips(AppLocalizations l10n, ColorScheme cs) {
    final options = <String?, String>{
      null: l10n.loanHistoryFilterAll,
      'active': l10n.loanDashActiveLoans,
      'overdue': l10n.loanDashOverdueLoans,
      'paid': l10n.loanHistoryFilterPaid,
    };

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // The platform's own scrolling feel (bounce on iOS, glow on Android).
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = options.entries.elementAt(index);
          // Center keeps each chip at its own natural height, whatever the
          // row's height is.
          return Center(
            child: LoanChoiceChip(
              label: entry.value,
              selected: _statusFilter == entry.key,
              onTap: () => _setStatusFilter(entry.key),
              selectedColor: AppConstants.buyerBlue,
            ),
          );
        },
      ),
    );
  }

  /// The applied date period, shown as a removable tag under the status chips.
  Widget _buildActivePeriodTag(AppLocalizations l10n, ColorScheme cs) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => _setPeriod(ReportPeriod.allTime),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  l10n.loanHistoryIssuedPeriodTag(
                    reportPeriodLabel(l10n, _period),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.close_rounded, size: 14, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPeriodFilter() async {
    final picked = await showManagementModal<ReportPeriod>(
      context: context,
      builder: (_) => LoanPeriodFilterModal(initial: _period),
    );
    if (picked != null && picked != _period) _setPeriod(picked);
  }

  Widget _buildSearchField(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _searchQuery = v),
      decoration: InputDecoration(
        hintText: l10n.loanHistorySearchHint,
        hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
        prefixIcon: Icon(Icons.search_rounded, color: cs.outline, size: 22),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.close_rounded, color: cs.outline, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
      ),
      style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
    );
  }

  Widget _buildLoanRow(
    BuildContext context,
    AdminLoanSummary loan,
    ColorScheme cs,
    SaganaColors sagana,
    AppLocalizations l10n,
  ) {
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );
    final statusColor = loan.isPaid
        ? AppConstants.buyerBlue
        : loan.isOverdue
            ? AppConstants.errorRed
            : AppConstants.successGreen;
    final statusLabel = loan.isPaid
        ? 'PAID'
        : loan.isOverdue
        ? 'OVERDUE'
        : 'ACTIVE';
    final dueDate = loan.nextPaymentDate;

    return GestureDetector(
      onTap: () => context.push(AppRoutes.loanDetails, extra: loan.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: cs.primary.withValues(alpha: 0.10),
                  child: Icon(
                    Icons.person_rounded,
                    color: cs.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loan.farmerName,
                          overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        loan.referenceNo,
                          overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (loan.isFromProgramDistribution) ...[
              const SizedBox(height: AppConstants.spacingSm),
              Row(
                children: [
                  Icon(
                    Icons.eco_rounded,
                    size: 13,
                    color: AppConstants.programPurple,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'From Program Distribution: ${loan.sourceProgramName}',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.programPurple,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppConstants.spacingSm),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
            const SizedBox(height: AppConstants.spacingSm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.issueLoanTotalValue,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currency.format(loan.totalValue),
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: cs.onSurface,
                        ),
                      ),
                      if (!loan.isPaid)
                        Text(
                          currency.format(loan.remainingBalance),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: statusColor,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!loan.isPaid && dueDate != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        l10n.issueLoanNextPaymentDue,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('MMM d, yyyy').format(dueDate),
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                          color: loan.isOverdue
                              ? AppConstants.errorRed
                              : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Date issued" filter for Loan History: the same card as the Listings and
/// Members filters (title and subtitle, one labelled group of options, Reset
/// All / Apply Filters). Pops with the chosen [ReportPeriod]; Reset pops
/// [ReportPeriod.allTime].
class LoanPeriodFilterModal extends StatefulWidget {
  final ReportPeriod initial;

  const LoanPeriodFilterModal({super.key, required this.initial});

  @override
  State<LoanPeriodFilterModal> createState() => _LoanPeriodFilterModalState();
}

class _LoanPeriodFilterModalState extends State<LoanPeriodFilterModal> {
  late ReportPeriod _period = widget.initial;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return ManagementModalShell(
      title: l10n.loanHistoryFilterTitle,
      subtitle: l10n.loanHistoryFilterSubtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.loanHistoryFilterIssued,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: cs.outline,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in reportPeriodChipOrder)
                ListingCropFilterChip(
                  label: reportPeriodLabel(l10n, p),
                  active: _period == p,
                  onTap: () => setState(() => _period = p),
                  cs: cs,
                ),
            ],
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
              onPressed: () => Navigator.pop(context, ReportPeriod.allTime),
              child: Text(
                l10n.farmerMgmtResetAll,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
              onPressed: () => Navigator.pop(context, _period),
              child: Text(
                l10n.farmerMgmtApplyFilters,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
