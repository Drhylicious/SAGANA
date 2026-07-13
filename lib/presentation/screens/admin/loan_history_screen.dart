import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_loan_model.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/export_model.dart';
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
              IconButton(
                icon: Icon(Icons.file_download_outlined, color: cs.onSurfaceVariant),
                onPressed: () => context.push(
                  AppRoutes.exportCenter,
                  extra: ExportCenterArgs(
                    preselectedModule: ReportModuleType.loan,
                    period: _period,
                  ),
                ),
                tooltip: l10n.reportsExportCenter,
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
          _buildSummaryCard(context, l10n, cs),
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildStatusChips(context, l10n, cs),
          const SizedBox(height: AppConstants.spacingSm),
          _buildPeriodChips(context, cs),
          const SizedBox(height: AppConstants.spacingGutter),
          _buildSearchField(context, l10n, cs),
          const SizedBox(height: AppConstants.spacingGutter),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (visibleLoans.isEmpty)
            _buildMessageState(Icons.receipt_long_outlined, l10n.loanHistoryNoResults, cs)
          else
            ...visibleLoans.map((loan) => _buildLoanRow(context, loan, cs, sagana)),
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

  Widget _buildSummaryCard(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final healthColor = _summary.isHealthy ? AppConstants.successGreen : AppConstants.warningAmber;
    final healthLabel = _summary.isHealthy ? l10n.loanHistoryHealthy : l10n.loanHistoryNeedsAttention;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        gradient: AppConstants.primaryButtonGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
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
                    l10n.loanHistoryAllTimeSummary,
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.85)),
                  ),
                  Text(
                    currency.format(_summary.totalIssued),
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 22, color: Colors.white),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Column(
                  children: [
                    Text(
                      '${_summary.repaymentRatePercent.toStringAsFixed(0)}%',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
                    ),
                    Text(
                      l10n.loanHistoryRate,
                      style: GoogleFonts.inter(fontSize: 9, color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              Expanded(
                child: _summaryStat(l10n.loanHistoryTotalIssued(_summary.totalLoanCount)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.loanHistoryTotalCollected, style: GoogleFonts.inter(fontSize: 10, color: Colors.white70)),
                    Text(
                      currency.format(_summary.totalCollected),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.loanDashTotalOutstanding, style: GoogleFonts.inter(fontSize: 10, color: Colors.white70)),
                    Text(
                      currency.format(_summary.totalOutstanding),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: healthColor.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            ),
            child: Text(
              healthLabel,
              style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String label) {
    return Text(label, style: GoogleFonts.inter(fontSize: 10, color: Colors.white70));
  }

  Widget _buildStatusChips(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    final options = <String?, String>{
      null: l10n.loanHistoryFilterAll,
      'active': l10n.loanDashActiveLoans,
      'overdue': l10n.loanDashOverdueLoans,
      'paid': l10n.loanHistoryFilterPaid,
    };

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: options.entries.map((entry) {
          final active = _statusFilter == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(entry.value, style: GoogleFonts.inter(fontSize: 12)),
              selected: active,
              onSelected: (_) => _setStatusFilter(entry.key),
              selectedColor: AppConstants.primaryGreen,
              labelStyle: TextStyle(color: active ? Colors.white : cs.onSurface),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPeriodChips(BuildContext context, ColorScheme cs) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: ReportPeriod.values.map((p) {
          final active = _period == p;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(p.label, style: GoogleFonts.inter(fontSize: 12)),
              selected: active,
              onSelected: (_) => _setPeriod(p),
              selectedColor: AppConstants.buyerBlue,
              labelStyle: TextStyle(color: active ? Colors.white : cs.onSurface),
            ),
          );
        }).toList(),
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
  ) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final statusColor = loan.isPaid
        ? AppConstants.buyerBlue
        : loan.isOverdue
            ? AppConstants.errorRed
            : AppConstants.successGreen;
    final statusLabel = loan.isPaid ? 'PAID' : loan.isOverdue ? 'OVERDUE' : 'ACTIVE';

    return GestureDetector(
      onTap: () => context.push(AppRoutes.loanDetails, extra: loan.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          loan.farmerName,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                        ),
                        child: Text(
                          statusLabel,
                          style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: statusColor),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${loan.memberId} • ${loan.referenceNo} • ${DateFormat('MMM d, yyyy').format(loan.issuedDate)}',
                    style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spacingSm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  currency.format(loan.totalValue),
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface),
                ),
                if (!loan.isPaid)
                  Text(
                    currency.format(loan.remainingBalance),
                    style: GoogleFonts.inter(fontSize: 10, color: statusColor),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}