import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_loan_model.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';

/// Loan Management — Admin Dashboard.
/// Shell tab (branch 3, adminLoansKey). No back button.
class LoanDashboardScreen extends StatefulWidget {
  const LoanDashboardScreen({super.key});

  @override
  State<LoanDashboardScreen> createState() => _LoanDashboardScreenState();
}

class _LoanDashboardScreenState extends State<LoanDashboardScreen> {
  final _repo = AdminLoanRepository();

  bool _isLoading = true;
  bool _isOnline = true;

  LoanDashboardStats _stats = LoanDashboardStats.empty();
  List<AdminLoanSummary> _overdueLoans = [];
  List<AdminLoanSummary> _activeLoans = [];

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchDashboardStats(),
      _repo.fetchOverdueLoans(limit: 3),
      _repo.fetchActiveLoans(limit: 5),
    ]);
    if (!mounted) return;
    setState(() {
      _stats = results[0] as LoanDashboardStats;
      _overdueLoans = results[1] as List<AdminLoanSummary>;
      _activeLoans = results[2] as List<AdminLoanSummary>;
      _isLoading = false;
    });
  }

  /// Next BOD meeting date — the 1st Saturday of the current or next month,
  /// matching the same logic used on the farmer side (My Input Loans).
  DateTime _nextBodSaturday() {
    final now = DateTime.now();
    var candidate = _firstSaturdayOf(now.year, now.month);
    if (candidate.isBefore(DateTime(now.year, now.month, now.day))) {
      final nextMonth = now.month == 12 ? 1 : now.month + 1;
      final nextYear = now.month == 12 ? now.year + 1 : now.year;
      candidate = _firstSaturdayOf(nextYear, nextMonth);
    }
    return candidate;
  }

  DateTime _firstSaturdayOf(int year, int month) {
    var d = DateTime(year, month, 1);
    while (d.weekday != DateTime.saturday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
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
          _buildTopBar(context, l10n, cs, sagana),
          if (!_isOnline) const OfflineBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAll,
              child: _isLoading
                  ? _buildShimmer()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.spacingSafeH,
                        AppConstants.spacingGutter,
                        AppConstants.spacingSafeH,
                        32,
                      ),
                      children: [
                        _buildBodBanner(context, l10n, cs, sagana),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        _buildKpiGrid(context, l10n, cs, sagana),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        _buildQuickActions(context, l10n, cs, sagana),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        _buildSectionHeader(
                          context,
                          title: l10n.loanDashOverdueSection(_overdueLoans.length),
                          onSeeAll: () => _goToHistory('overdue'),
                          l10n: l10n,
                        ),
                        const SizedBox(height: AppConstants.spacingMd),
                        if (_overdueLoans.isEmpty)
                          _buildEmptyState(l10n.loanDashNoOverdue, cs)
                        else
                          ..._overdueLoans.map(
                            (loan) => Padding(
                              padding: const EdgeInsets.only(bottom: AppConstants.spacingMd),
                              child: _AdminLoanCard(
                                loan: loan,
                                l10n: l10n,
                                onTap: () => _goToDetails(loan.id),
                                onPay: () => _goToPayment(loan.id),
                              ),
                            ),
                          ),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        _buildSectionHeader(
                          context,
                          title: l10n.loanDashActiveSection,
                          onSeeAll: () => _goToHistory('active'),
                          l10n: l10n,
                        ),
                        const SizedBox(height: AppConstants.spacingMd),
                        if (_activeLoans.isEmpty)
                          _buildEmptyState(l10n.loanDashNoActive, cs)
                        else
                          ..._activeLoans.map(
                            (loan) => Padding(
                              padding: const EdgeInsets.only(bottom: AppConstants.spacingMd),
                              child: _AdminLoanCard(
                                loan: loan,
                                l10n: l10n,
                                onTap: () => _goToDetails(loan.id),
                                onPay: () => _goToPayment(loan.id),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Navigation ─────────────────────────────────────────────────────────

  void _goToIssueLoan() {
    context.push(AppRoutes.issueNewLoan).then((_) => _loadAll());
  }

  void _goToPayment([String? loanId]) {
    context.push(AppRoutes.recordPayment, extra: loanId).then((_) => _loadAll());
  }

  void _goToDetails(String loanId) {
    context.push(AppRoutes.loanDetails, extra: loanId).then((_) => _loadAll());
  }

  void _goToHistory([String? statusFilter]) {
    context.push(AppRoutes.loanHistory, extra: statusFilter);
  }

  // ─── Top bar (fixed, glass) ─────────────────────────────────────────────

  Widget _buildTopBar(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSafeH),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(
              bottom: BorderSide(color: sagana.glassBorder),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.loanDashTitle,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: cs.onSurface,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.notifications_outlined, color: cs.onSurface),
                onPressed: () => context.push(AppRoutes.adminNotifications),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_rounded, color: AppConstants.primaryGreen),
                onPressed: _goToIssueLoan,
                tooltip: l10n.loanDashActionIssue,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── BOD Meeting banner ─────────────────────────────────────────────────

  Widget _buildBodBanner(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final nextDate = _nextBodSaturday();
    final dateLabel = DateFormat('MMMM d, yyyy').format(nextDate);
    final amountLabel = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0)
        .format(_stats.totalExpectedThisCycle);

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
            children: [
              const Icon(Icons.event_available_rounded, color: Colors.white, size: 20),
              const SizedBox(width: AppConstants.spacingSm),
              Text(
                l10n.loanDashNextCollection,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            dateLabel,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.loanDashFarmersOutstanding(_stats.farmersOutstandingCount),
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.9)),
          ),
          Text(
            l10n.loanDashTotalExpected(amountLabel),
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _goToPayment(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppConstants.primaryGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                l10n.adminGoToLoanPayments,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── KPI grid ───────────────────────────────────────────────────────────

  Widget _buildKpiGrid(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppConstants.spacingMd,
      crossAxisSpacing: AppConstants.spacingMd,
      childAspectRatio: 1.7,
      children: [
        _kpiCard(l10n.loanDashActiveLoans, '${_stats.activeLoansCount}', AppConstants.successGreen, cs, sagana),
        _kpiCard(l10n.loanDashTotalOutstanding, currency.format(_stats.totalOutstanding), AppConstants.buyerBlue, cs, sagana),
        _kpiCard(l10n.loanDashOverdueLoans, '${_stats.overdueLoansCount}', AppConstants.errorRed, cs, sagana),
        _kpiCard(l10n.loanDashPaidThisMonth, '${_stats.paidThisMonthCount}', AppConstants.amber, cs, sagana),
      ],
    );
  }

  Widget _kpiCard(String label, String value, Color accent, ColorScheme cs, SaganaColors sagana) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            value,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 20, color: cs.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ─── Quick actions ──────────────────────────────────────────────────────

  Widget _buildQuickActions(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Row(
      children: [
        Expanded(
          child: _quickActionButton(
            icon: Icons.add_card_rounded,
            label: l10n.loanDashActionIssue,
            onTap: _goToIssueLoan,
            cs: cs,
            sagana: sagana,
          ),
        ),
        const SizedBox(width: AppConstants.spacingMd),
        Expanded(
          child: _quickActionButton(
            icon: Icons.payments_rounded,
            label: l10n.loanDashActionRecordPayment,
            onTap: () => _goToPayment(),
            cs: cs,
            sagana: sagana,
          ),
        ),
        const SizedBox(width: AppConstants.spacingMd),
        Expanded(
          child: _quickActionButton(
            icon: Icons.history_rounded,
            label: l10n.loanDashActionViewHistory,
            onTap: () => _goToHistory(),
            cs: cs,
            sagana: sagana,
          ),
        ),
      ],
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required ColorScheme cs,
    required SaganaColors sagana,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingMd, horizontal: 4),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppConstants.primaryGreen, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 11, color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Section header ─────────────────────────────────────────────────────

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required VoidCallback onSeeAll,
    required AppLocalizations l10n,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface),
        ),
        GestureDetector(
          onTap: onSeeAll,
          child: Text(
            l10n.loanDashSeeAll,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: AppConstants.primaryGreen),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView(
      padding: const EdgeInsets.all(AppConstants.spacingSafeH),
      children: List.generate(
        4,
        (i) => Container(
          height: 90,
          margin: const EdgeInsets.only(bottom: AppConstants.spacingMd),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
        ),
      ),
    );
  }
}

// ─── Loan card (shared by Overdue + Active sections) ───────────────────────

class _AdminLoanCard extends StatelessWidget {
  final AdminLoanSummary loan;
  final AppLocalizations l10n;
  final VoidCallback onTap;
  final VoidCallback onPay;

  const _AdminLoanCard({
    required this.loan,
    required this.l10n,
    required this.onTap,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final initials = loan.farmerName.isNotEmpty
        ? loan.farmerName.trim().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join()
        : '?';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: loan.isOverdue
              ? Border(
                  left: BorderSide(color: cs.error, width: 4),
                  top: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
                  right: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
                  bottom: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
                )
              : Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppConstants.primaryContainer,
                  child: Text(
                    initials.toUpperCase(),
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
                const SizedBox(width: AppConstants.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loan.farmerName,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface),
                      ),
                      Text(
                        '${loan.memberId} • ${loan.referenceNo}',
                        style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                _statusBadge(context),
              ],
            ),
            if (loan.itemNames.isNotEmpty) ...[
              const SizedBox(height: AppConstants.spacingSm),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: loan.itemNames
                    .take(3)
                    .map((name) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                          ),
                          child: Text(
                            name,
                            style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
                          ),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: AppConstants.spacingMd),
            Row(
              children: [
                _statColumn(l10n.loanDashValue, currency.format(loan.totalValue), cs),
                _statColumn(l10n.loanDashPaid, currency.format(loan.amountPaid), cs),
                _statColumn(l10n.loanDashBalance, currency.format(loan.remainingBalance), cs),
              ],
            ),
            const SizedBox(height: AppConstants.spacingSm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              child: LinearProgressIndicator(
                value: loan.repaidPercent,
                minHeight: 6,
                backgroundColor: cs.outline.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(
                  loan.isOverdue ? AppConstants.errorRed : AppConstants.successGreen,
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingSm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    loan.isOverdue && loan.nextPaymentDate != null
                        ? l10n.loanDashOverdueSince(DateFormat('MMM d').format(loan.nextPaymentDate!))
                        : loan.nextPaymentDate != null
                            ? '${l10n.loanDashNext}: ${DateFormat('MMM d').format(loan.nextPaymentDate!)}'
                            : '',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: loan.isOverdue ? AppConstants.errorRed : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.payments_outlined, size: 20),
                  color: AppConstants.primaryGreen,
                  onPressed: onPay,
                  tooltip: l10n.loanDashActionRecordPayment,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 22),
                  color: cs.onSurfaceVariant,
                  onPressed: onTap,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(BuildContext context) {
    final color = loan.isOverdue ? AppConstants.errorRed : AppConstants.successGreen;
    final label = loan.isOverdue ? 'OVERDUE' : 'ACTIVE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _statColumn(String label, String value, ColorScheme cs) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant)),
          Text(
            value,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12, color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}