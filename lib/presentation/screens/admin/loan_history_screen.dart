import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../widgets/management_modal.dart';
import '../../../data/models/admin_loan_model.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';

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
      _repo.fetchAllLoans(statusFilter: _statusFilter, issuedAfter: _periodCutoff()),
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

  Widget _buildTopBar(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    final sagana = context.saganaColors;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSm),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  l10n.loanHistoryTitle,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: cs.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    if (_offlineUnavailable) {
      return _buildMessageState(Icons.wifi_off_rounded, l10n.loanHistoryUnavailableOffline, cs);
    }

    final visibleLoans = _loans.applySearch(_searchQuery);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingSafeH,
          AppConstants.spacingGutter,
          AppConstants.spacingSafeH,
          32,
        ),
        children: [
          _buildStatCard(context, l10n, cs, sagana),
          const SizedBox(height: AppConstants.spacingGutter),
          Row(
            children: [
              Expanded(child: _buildSearchField(context, l10n, cs)),
              const SizedBox(width: AppConstants.spacingSm),
              _buildFilterButton(context, l10n, cs),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          _buildStatusSegmentedControl(context, l10n, cs, sagana),
          const SizedBox(height: AppConstants.spacingGutter),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (visibleLoans.isEmpty)
            _buildMessageState(Icons.receipt_long_outlined,
                _statusFilter == null ? l10n.loanHistoryNoResults : l10n.loanHistoryNoResultsForFilter, cs)
          else
            ...visibleLoans.map((loan) => _buildLoanRow(context, loan, cs, sagana, l10n)),
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

  Widget _buildStatCard(BuildContext context, AppLocalizations l10n, ColorScheme cs, SaganaColors sagana) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final healthColor = _summary.isHealthy ? AppConstants.successGreen : AppConstants.warningAmber;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.loanHistoryTotalIssued(_summary.totalLoanCount),
                  style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: healthColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(_summary.isHealthy ? l10n.loanHistoryHealthy : l10n.loanHistoryNeedsAttention,
                    style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: healthColor)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(currency.format(_summary.totalIssued),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 26, color: cs.primary)),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              Expanded(child: _statBlock(l10n.loanHistoryTotalCollected, currency.format(_summary.totalCollected), cs)),
              const SizedBox(width: AppConstants.spacingSm),
              Expanded(child: _statBlock(l10n.loanDashTotalOutstanding, currency.format(_summary.totalOutstanding), cs)),
              const SizedBox(width: AppConstants.spacingSm),
              Expanded(child: _statBlock(l10n.loanHistoryRate, '${_summary.repaymentRatePercent.toStringAsFixed(0)}%', cs)),
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
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12, color: cs.onSurface)),
        ],
      ),
    );
  }

  Widget _buildStatusSegmentedControl(BuildContext context, AppLocalizations l10n, ColorScheme cs, SaganaColors sagana) {
    final options = {
      null: l10n.loanHistoryFilterAll,
      'active': l10n.loanDashActiveLoans,
      'overdue': l10n.loanDashOverdueLoans,
      'paid': l10n.loanHistoryFilterPaid,
    };

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        children: options.entries.map((entry) {
          final active = _statusFilter == entry.key;
          return Expanded(
            child: GestureDetector(
              onTap: () => _setStatusFilter(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: active ? sagana.cardBackground : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)] : null,
                ),
                child: Text(entry.value, textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600,
                        color: active ? cs.primary : cs.onSurfaceVariant)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _openFilterSheet(BuildContext context, AppLocalizations l10n) {
    ReportPeriod tempPeriod = _period;
    showManagementModal(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return ManagementModalShell(
          title: l10n.loanHistoryFilterTitle,
          body: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ReportPeriod.values.map((p) {
              final active = tempPeriod == p;
              return ChoiceChip(
                label: Text(p.label, style: GoogleFonts.inter(fontSize: 12)),
                selected: active,
                onSelected: (_) => setSheet(() => tempPeriod = p),
                selectedColor: AppConstants.buyerBlue,
                labelStyle: TextStyle(color: active ? Colors.white : Theme.of(ctx).colorScheme.onSurface),
              );
            }).toList(),
          ),
          footer: ManagementModalActions(
            primaryLabel: l10n.loanHistoryApplyFilter,
            onPrimary: () {
              Navigator.pop(ctx);
              _setPeriod(tempPeriod);
            },
          ),
        );
      }),
    );
  }

  Widget _buildFilterButton(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.20)),
      ),
      child: IconButton(
        icon: Icon(Icons.filter_list_rounded, color: cs.primary),
        onPressed: () => _openFilterSheet(context, l10n),
        tooltip: l10n.loanHistoryFilterTitle,
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
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
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final statusColor = loan.isPaid
        ? AppConstants.buyerBlue
        : loan.isOverdue
            ? AppConstants.errorRed
            : AppConstants.successGreen;
    final statusLabel = loan.isPaid ? 'PAID' : loan.isOverdue ? 'OVERDUE' : 'ACTIVE';
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: cs.primary.withValues(alpha: 0.10),
                  child: Icon(Icons.person_rounded, color: cs.primary, size: 18),
                ),
                const SizedBox(width: AppConstants.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loan.farmerName,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
                      Text('${loan.memberId} • ${loan.referenceNo}',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(statusLabel,
                      style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: statusColor)),
                ),
              ],
            ),
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
                      Text(l10n.issueLoanTotalValue,
                          style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(currency.format(loan.totalValue),
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface)),
                      if (!loan.isPaid)
                        Text(currency.format(loan.remainingBalance),
                            style: GoogleFonts.inter(fontSize: 10, color: statusColor)),
                    ],
                  ),
                ),
                if (!loan.isPaid && dueDate != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(l10n.issueLoanNextPaymentDue,
                          style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(DateFormat('MMM d, yyyy').format(dueDate),
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: loan.isOverdue ? AppConstants.errorRed : cs.onSurface)),
                    ],
                  ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}