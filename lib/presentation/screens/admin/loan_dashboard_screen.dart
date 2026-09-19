import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/bod_schedule_utils.dart';
import '../../../data/models/admin_loan_model.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/services/admin_profile_state_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/admin_top_bar.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_navigation_drawer.dart';

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
  (int, int) _paidCountTrend = (0, 0);
  List<Map<String, dynamic>> _syncIssues = [];

  /// Overdue first (most urgent), topped up with active loans to a max
  /// of 5 cards — replaces the old separate Overdue/Active sections.
  List<AdminLoanSummary> get _recentLoans {
    final combined = <AdminLoanSummary>[..._overdueLoans];
    final remainingSlots = (5 - combined.length).clamp(0, 5);
    combined.addAll(_activeLoans.take(remainingSlots));
    return combined;
  }

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
    await _repo.reconcileOverdueLoans();
    final results = await Future.wait([
      _repo.fetchDashboardStats(),
      _repo.fetchOverdueLoans(limit: 3),
      _repo.fetchActiveLoans(limit: 5),
      _repo.fetchPaidCountThisVsLastMonth(),
    ]);
    if (!mounted) return;
    setState(() {
      _stats = results[0] as LoanDashboardStats;
      _overdueLoans = results[1] as List<AdminLoanSummary>;
      _activeLoans = results[2] as List<AdminLoanSummary>;
      _paidCountTrend = results[3] as (int, int);
      _syncIssues = HiveService.getLoanSyncIssues();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

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
          AdminTopBar(
            title: l10n.loanDashTitle,
            onBroadcastTap: () => context.push(AppRoutes.announcementDashboard),
            onNotificationTap: () => context.push(AppRoutes.adminNotifications).then((_) => _loadAll()),
            onProfileTap: () => context.push(AppRoutes.adminProfile),
            enableMenu: true,
          ),
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
                        AppConstants.spacingSafeH,
                      ),
                      children: [
                        if (_syncIssues.isNotEmpty) ...[
                          _SyncIssuesCard(
                            issues: _syncIssues,
                            cs: cs,
                            sagana: sagana,
                            onTap: (issue) => AppDialog.show<void>(
                              context: context,
                              child: _SyncIssueDetailDialog(issue: issue),
                            ),
                          ),
                          const SizedBox(height: AppConstants.spacingMd),
                        ],
                        _buildBodBanner(context, l10n, cs, sagana),
                        const SizedBox(height: AppConstants.spacingMd),
                        _buildQuickActions(context, l10n),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        _buildKpiGrid(context, l10n, cs, sagana),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        _buildSectionHeader(
                          context,
                          title: l10n.loanDashRecentActivitySection,
                          onSeeAll: () => _goToHistory(),
                          l10n: l10n,
                        ),
                        const SizedBox(height: AppConstants.spacingMd),
                        if (_recentLoans.isEmpty)
                          _buildEmptyState(
                            l10n.loanDashNoRecentActivity,
                            cs,
                            subtitle: l10n.loanDashNoRecentActivitySubtitle,
                          )
                        else
                          ..._recentLoans.map(
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

  // Top bar is provided by shared AdminTopBar

  // ─── BOD Meeting banner ─────────────────────────────────────────────────

  Widget _buildBodBanner(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final hasOverdue = _stats.overdueLoansCount > 0;
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);

    if (hasOverdue) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppConstants.spacingGutter),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [AppConstants.errorRed.withValues(alpha: 0.92), const Color(0xFFB71C1C)],
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                const SizedBox(width: AppConstants.spacingSm),
                Text(
                  l10n.loanDashOverdueSection(_stats.overdueLoansCount),
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              currency.format(_stats.totalOverdueAmount),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 24, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.loanDashOverdueHeroSubtitle,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: AppConstants.spacingMd),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _goToHistory('overdue'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppConstants.errorRed,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  l10n.loanDashReviewOverdue,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final nextDate = BodSchedule.upcoming();
    final dateLabel = DateFormat('MMMM d, yyyy').format(nextDate);
    final amountLabel = currency.format(_stats.totalExpectedThisCycle);

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
    final (thisMonth, lastMonth) = _paidCountTrend;
    final hasDelta = lastMonth > 0;
    final deltaPercent = hasDelta ? ((thisMonth - lastMonth) / lastMonth * 100) : 0.0;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppConstants.spacingMd,
      crossAxisSpacing: AppConstants.spacingMd,
      // Shorter than the original 1.7 so the value row has room to render
      // near its set size instead of a shallow card forcing the
      // FittedBox(fit: scaleDown) to shrink it back down regardless of
      // fontSize — 1.5 (vs. an earlier 1.35) keeps that room without the
      // card reading as oversized.
      childAspectRatio: 1.5,
      children: [
        _kpiCard(l10n.loanDashActiveLoans, '${_stats.activeLoansCount}', AppConstants.successGreen, cs, sagana,
            icon: Icons.check_circle_rounded),
        _kpiCard(l10n.loanDashTotalOutstanding, currency.format(_stats.totalOutstanding), AppConstants.buyerBlue, cs, sagana,
            icon: Icons.account_balance_wallet_rounded),
        _kpiCard(l10n.loanDashOverdueLoans, '${_stats.overdueLoansCount}', AppConstants.errorRed, cs, sagana,
            icon: Icons.warning_amber_rounded),
        _kpiCard(
          l10n.loanDashPaidThisMonth,
          '${_stats.paidThisMonthCount}',
          AppConstants.amber,
          cs,
          sagana,
          icon: Icons.payments_rounded,
          delta: hasDelta ? deltaPercent : null,
        ),
      ],
    );
  }

  Widget _kpiCard(
    String label,
    String value,
    Color accent,
    ColorScheme cs,
    SaganaColors sagana, {
    IconData icon = Icons.insights_rounded,
    double? delta,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              if (delta != null)
                Row(
                  children: [
                    Icon(
                      delta >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      size: 11,
                      color: delta >= 0 ? AppConstants.successGreen : AppConstants.errorRed,
                    ),
                    Text(
                      '${delta.abs().toStringAsFixed(0)}%',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: delta >= 0 ? AppConstants.successGreen : AppConstants.errorRed,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Flexible(
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 21, color: cs.onSurface),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
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
        // Flexible + ellipsis: translated section titles ("Kasaysayan ng
        // Pautang") run longer than the English source and this Row has
        // no other slack next to the "See all" link — without this a
        // long title overflows past the available width.
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface),
          ),
        ),
        const SizedBox(width: 8),
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

  Widget _buildEmptyState(String message, ColorScheme cs, {String? subtitle}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingSectionV, horizontal: AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Icon(Icons.receipt_long_outlined, color: cs.primary, size: 24),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Text(message, textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, AppLocalizations l10n) {
    // Officers can issue loans (Decision D21 resolves the deferred Staff
    // gap). The backend RPC is the authority; this just keeps the button
    // visible for everyone who reaches this screen.
    const canIssueLoans = true;

    return Row(
      children: [
        if (canIssueLoans) ...[
          Expanded(
            child: _quickActionButton(
              icon: Icons.add_card_rounded,
              label: l10n.loanDashActionIssue,
              onTap: _goToIssueLoan,
            ),
          ),
          const SizedBox(width: AppConstants.spacingSm),
        ],
        Expanded(
          child: _quickActionButton(
            icon: Icons.payments_outlined,
            label: l10n.loanDashActionPayments,
            onTap: () => _goToPayment(),
          ),
        ),
      ],
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppConstants.primaryGreen,
        side: const BorderSide(color: AppConstants.primaryGreen),
        minimumSize: const Size(double.infinity, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
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
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
          border: Border.all(
            color: loan.isOverdue
                ? cs.error.withValues(alpha: 0.18)
                : cs.outline.withValues(alpha: 0.10),
          ),
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
            if (loan.isFromProgramDistribution) ...[
              const SizedBox(height: AppConstants.spacingSm),
              Row(
                children: [
                  Icon(Icons.eco_rounded, size: 13, color: AppConstants.programPurple),
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
    final l10n = AppLocalizations.of(context);
    final color = loan.isOverdue ? AppConstants.errorRed : AppConstants.successGreen;
    final label = loan.isOverdue ? l10n.farmerMgmtOverdueBadge : l10n.farmerMgmtActiveBadge;
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

class _SyncIssuesCard extends StatelessWidget {
  final List<Map<String, dynamic>> issues;
  final void Function(Map<String, dynamic>) onTap;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _SyncIssuesCard({
    required this.issues,
    required this.onTap,
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
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppConstants.warningAmber,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.loanDashSyncIssues,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(
                    l10n.buyerCartItemCount(issues.length),
                    style: GoogleFonts.inter(
                        fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.08)),
          ...issues.asMap().entries.map((entry) {
            final i = entry.key;
            final issue = entry.value;
            final isIssuance = issue['type'] == 'issue';
            final isLast = i == issues.length - 1;
            return Column(
              children: [
                GestureDetector(
                  onTap: () => onTap(issue),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.sync_problem_rounded,
                            color: AppConstants.warningAmber, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isIssuance
                                    ? l10n.loanDashIssuanceFailedSync
                                    : l10n.loanDashPaymentFailedSync,
                                style: GoogleFonts.poppins(
                                    fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
                              ),
                              Text(
                                issue['error'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: AppConstants.warningAmber.withValues(alpha: 0.60), size: 18),
                      ],
                    ),
                  ),
                ),
                if (!isLast)
                  Divider(height: 1, indent: 16, color: cs.outline.withValues(alpha: 0.08)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _SyncIssueDetailDialog extends StatelessWidget {
  final Map<String, dynamic> issue;

  const _SyncIssueDetailDialog({required this.issue});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isIssuance = issue['type'] == 'issue';
    final failedAt = DateTime.tryParse(issue['failedAt'] as String? ?? '');

    return AlertDialog(
      title: Text(isIssuance ? l10n.loanDashIssuanceFailedSync : l10n.loanDashPaymentFailedSync),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(issue['error'] as String),
          if (failedAt != null) ...[
            const SizedBox(height: 12),
            Text(
              l10n.loanDashLastAttempted(DateFormat('MMM d, h:mm a').format(failedAt)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}