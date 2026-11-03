import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/bod_schedule_utils.dart';
import '../../../core/utils/loan_sorting.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/loan_model.dart';
import '../../../data/repositories/loan_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/farmer_loan_widgets.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/top_bar_spacer.dart';

/// Farmer > Profile > Input Loans.
///
/// Laid out like Manager > Loans so both roles read a loan the same way:
///   1. Outstanding Loans            (what is still owed, and how much is repaid)
///   2. Next Payment Due             (the next BOD payment, or what is overdue)
///   3. Input-only loans note
///   4. Loan History                 (the latest few loans; View All opens them all)
///   5. Payment History              (the latest few payments; View All opens them all)
/// and a + button to request a loan.
///
/// The landing page keeps to the most recent records so it stays short: the latest
/// [_recentLoans] loans and [_recentPayments] payments, newest first. View All opens
/// the full Loan History (with the status chips) and Payment History screens, which
/// sort the very same way (see loan_sorting.dart).
///
/// Every figure comes from the Farmer's own loans (farmer_loans with their items
/// and payments), so the balance, the history and the payments always agree. The
/// statuses are the stored ones: active, overdue (set by the daily maintenance /
/// the Manager's dashboard when a payment is late) and paid.
class MyLoansScreen extends StatefulWidget {
  const MyLoansScreen({super.key});

  @override
  State<MyLoansScreen> createState() => _MyLoansScreenState();
}

class _MyLoansScreenState extends State<MyLoansScreen> {
  static const _recentLoans = 3;
  static const _recentPayments = 5;

  final _repo = LoanRepository();

  List<LoanModel> _loans = [];
  bool _isLoading = true;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final loans = await _repo.fetchLoans();
    if (!mounted) return;
    setState(() {
      _loans = loans;
      _isLoading = false;
    });
  }

  // ─── Derived figures (all from the same list of loans) ────────────────────

  List<LoanModel> get _unpaid => _loans.where((l) => !l.isPaid).toList();

  List<LoanModel> get _overdue => _loans.where((l) => l.isOverdue).toList();

  /// What is still owed: the remaining balance of every loan that is not paid.
  double get _outstanding =>
      _unpaid.fold<double>(0, (sum, l) => sum + l.remainingBalance);

  /// What the unpaid loans were worth, and how much of it is already paid.
  double get _borrowed => _unpaid.fold<double>(0, (sum, l) => sum + l.totalValue);

  double get _repaid => _unpaid.fold<double>(0, (sum, l) => sum + l.amountPaid);

  double get _overdueBalance =>
      _overdue.fold<double>(0, (sum, l) => sum + l.remainingBalance);

  /// The earliest payment date among the unpaid loans; the next BOD Saturday
  /// when no loan carries one.
  DateTime get _nextPaymentDate {
    final dates = _unpaid
        .map((l) => l.nextPaymentDate)
        .whereType<DateTime>()
        .toList()
      ..sort();
    return dates.isEmpty ? BodSchedule.upcoming() : dates.first;
  }

  /// One month's payment across the unpaid loans (never more than what is left).
  double get _expectedPayment => _unpaid.fold<double>(0, (sum, l) {
    if (l.monthlyPayment <= 0) return sum;
    return sum + (l.monthlyPayment < l.remainingBalance ? l.monthlyPayment : l.remainingBalance);
  });

  Future<void> _requestLoan() async {
    await context.pushRoute<void>(AppRoutes.requestLoan);
    if (mounted) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recentLoans = loansNewestFirst(_loans).take(_recentLoans).toList();
    final allPayments = paymentsNewestFirst(_loans);
    final recentPayments = allPayments.take(_recentPayments).toList();

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              CachedDataNotice(
                screen: 'loans',
                isOnline: _isOnline,
                offlineMessage: l10n.offlineLoans,
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                    children: [
                      _OutstandingCard(
                        outstanding: _outstanding,
                        borrowed: _borrowed,
                        repaid: _repaid,
                        activeCount: _loans.where((l) => l.isActive).length,
                        overdueCount: _overdue.length,
                        paidCount: _loans.where((l) => l.isPaid).length,
                        hasLoans: _loans.isNotEmpty,
                        isLoading: _isLoading,
                      ),
                      const SizedBox(height: 14),
                      _NextPaymentCard(
                        nextDate: _nextPaymentDate,
                        hasUnpaid: _unpaid.isNotEmpty,
                        expected: _expectedPayment,
                        overdueCount: _overdue.length,
                        overdueBalance: _overdueBalance,
                        isLoading: _isLoading,
                      ),
                      const SizedBox(height: 14),
                      const _InputLoanInfoCard(),
                      const SizedBox(height: 24),

                      // ── Loan History (latest few) ─────────────────────────
                      LoanSectionHeader(
                        title: l10n.loanMyHistoryTitle,
                        viewAllLabel: l10n.loanMyViewAll,
                        onViewAll: _isLoading || _loans.isEmpty
                            ? null
                            : () => context.pushRoute<void>(AppRoutes.myLoanHistory),
                      ),
                      const SizedBox(height: 10),
                      if (_isLoading)
                        ...List.generate(
                          2,
                          (_) => const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: SkeletonBlock(height: 120),
                          ),
                        )
                      else if (recentLoans.isEmpty)
                        LoanEmptyNote(
                          icon: Icons.agriculture_outlined,
                          text: l10n.loanMyNoLoans,
                        )
                      else
                        for (final loan in recentLoans)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: FarmerLoanCard(loan: loan, compact: true),
                          ),

                      // ── Payment History (latest few) ──────────────────────
                      const SizedBox(height: 12),
                      LoanSectionHeader(
                        title: l10n.loanMyPaymentsTitle,
                        viewAllLabel: l10n.loanMyViewAll,
                        onViewAll: _isLoading || allPayments.isEmpty
                            ? null
                            : () => context.pushRoute<void>(AppRoutes.myPaymentHistory),
                      ),
                      const SizedBox(height: 10),
                      if (_isLoading)
                        const SkeletonBlock(height: 70)
                      else if (recentPayments.isEmpty)
                        LoanEmptyNote(
                          icon: Icons.payments_outlined,
                          text: l10n.loanMyNoPayments,
                        )
                      else
                        for (final row in recentPayments)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: FarmerPaymentRow(loan: row.loan, payment: row.payment),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: l10n.loanMyScreenTitle,
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _requestLoan,
        tooltip: l10n.loanReqRequestButton,
        backgroundColor: AppConstants.primaryGreen,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded, size: 30),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Outstanding Loans — the same KPI card style as Manager > Loans.
//    One accent colour runs through the whole card (red while something is
//    owed, green once everything is paid), and the full width is used: the
//    repaid share beside the title, a progress bar across, and three counts.
// ─────────────────────────────────────────────────────────────────────────────

class _OutstandingCard extends StatelessWidget {
  final double outstanding;
  final double borrowed;
  final double repaid;
  final int activeCount;
  final int overdueCount;
  final int paidCount;
  final bool hasLoans;
  final bool isLoading;

  const _OutstandingCard({
    required this.outstanding,
    required this.borrowed,
    required this.repaid,
    required this.activeCount,
    required this.overdueCount,
    required this.paidCount,
    required this.hasLoans,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final money = NumberFormat('#,##0.00');
    final allPaid = !isLoading && hasLoans && outstanding <= 0;
    final owing = outstanding > 0;
    final accent = allPaid
        ? AppConstants.successGreen
        : (owing ? AppConstants.errorRed : AppConstants.primaryGreen);
    final share = borrowed > 0 ? (repaid / borrowed).clamp(0.0, 1.0) : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Icon(Icons.account_balance_wallet_rounded, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.loanMyOutstandingTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.onSurfaceVariant,
                  ),
                ),
              ),
              if (!isLoading && borrowed > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(
                    l10n.loanMyRepaid((share * 100).round()),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (isLoading)
            Container(width: 180, height: 32, color: const Color(0xFFE8E8E8))
          else if (allPaid)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppConstants.successGreen, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.loanMyAllPaid,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.successGreen,
                    ),
                  ),
                ),
              ],
            )
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '₱${money.format(outstanding)}',
                style: GoogleFonts.poppins(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: accent,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          if (!isLoading && borrowed > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 8,
                backgroundColor: accent.withValues(alpha: 0.14),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.loanMyRepaidAmount(money.format(repaid)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11.5, color: AppConstants.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.loanMyOfBorrowed(money.format(borrowed)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11.5, color: AppConstants.onSurfaceVariant),
                ),
              ],
            ),
          ],
          if (!isLoading && hasLoans) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _CountTile(
                    count: activeCount,
                    label: l10n.loanDashActiveLoans,
                    accent: accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CountTile(
                    count: overdueCount,
                    label: l10n.loanDashOverdueLoans,
                    accent: accent,
                    highlight: overdueCount > 0,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CountTile(
                    count: paidCount,
                    label: l10n.loanHistoryFilterPaid,
                    accent: accent,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A count and its label, tinted with the card's own accent so it always matches
/// the card. [highlight] fills it (used for overdue loans, the one that needs
/// attention).
class _CountTile extends StatelessWidget {
  final int count;
  final String label;
  final Color accent;
  final bool highlight;

  const _CountTile({
    required this.count,
    required this.label,
    required this.accent,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = highlight ? Colors.white : accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? accent : accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: fg, height: 1.1),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: highlight ? Colors.white.withValues(alpha: 0.92) : AppConstants.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Next Payment Due — the same banner as Manager > Loans (green; red when a
//    loan is overdue).
// ─────────────────────────────────────────────────────────────────────────────

class _NextPaymentCard extends StatelessWidget {
  final DateTime nextDate;
  final bool hasUnpaid;
  final double expected;
  final int overdueCount;
  final double overdueBalance;
  final bool isLoading;

  const _NextPaymentCard({
    required this.nextDate,
    required this.hasUnpaid,
    required this.expected,
    required this.overdueCount,
    required this.overdueBalance,
    required this.isLoading,
  });

  // Calendar-day difference, ignoring the time of day on both sides.
  int get _daysUntil {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(nextDate.year, nextDate.month, nextDate.day);
    return target.difference(today).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final money = NumberFormat('#,##0.00');
    final overdue = overdueCount > 0;
    final days = _daysUntil;
    final badge = days <= 0
        ? l10n.loanMyDueToday
        : (days == 1 ? l10n.loanMyDueInOneDay : l10n.loanMyDueInDays(days));
    final dateLabel = DateFormat('MMMM d, yyyy').format(nextDate);

    final gradient = overdue
        ? LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [AppConstants.errorRed.withValues(alpha: 0.92), const Color(0xFFB71C1C)],
          )
        : AppConstants.primaryButtonGradient;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: isLoading
          ? const SizedBox(height: 60)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      overdue ? Icons.warning_amber_rounded : Icons.event_available_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        overdue
                            ? l10n.loanMyOverdueTitle(overdueCount)
                            : (hasUnpaid ? l10n.loanMyNextPaymentTitle : l10n.loanMyNoPaymentDue),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (hasUnpaid && !overdue)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppConstants.secondaryContainer,
                          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                        ),
                        child: Text(
                          badge,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF2A1800),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (overdue) ...[
                  Text(
                    '₱${money.format(overdueBalance)}',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.loanMyOverdueBody,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ] else if (hasUnpaid) ...[
                  Text(
                    dateLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  if (expected > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      l10n.loanMyExpected(money.format(expected)),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ] else
                  Text(
                    l10n.loanMyNoPaymentDueBody(dateLabel),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: Colors.white.withValues(alpha: 0.9)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.loanMyBodNote,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.92),
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
// 3. Input-only loans note
// ─────────────────────────────────────────────────────────────────────────────

class _InputLoanInfoCard extends StatelessWidget {
  const _InputLoanInfoCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.infoBlueBg,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.outline.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.agriculture_rounded, color: AppConstants.primaryGreen, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.loanMyInfoTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.primaryGreen,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.loanMyInfoBody,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppConstants.onSurfaceVariant,
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

