import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../core/utils/bod_schedule_utils.dart';
import '../../core/utils/loan_sorting.dart';
import '../../data/models/loan_model.dart';
import '../../data/models/program_assistance_model.dart';
import 'assistance_record_card.dart';
import 'farmer_loan_widgets.dart';
import 'skeleton.dart';

/// The Farmer's input loans as they read on screen: Outstanding Loans, Next Payment
/// Due, the input-only note, Loan History and Payment History.
///
/// ONE implementation for both sides. The Farmer's My Input Loans screen and the
/// Manager / Officer's Farmer Details > Loans tab build their lists from
/// [loansViewChildren], so the two always show the same figures in the same design.
/// Everything here is display only; the Farmer screen adds its own request button.
///
/// The Farmer's landing page keeps to the latest few records and links to the full
/// Loan History and Payment History screens ([onViewAllLoans], [onViewAllPayments]).
/// The Manager side has no such screens to open, so it passes [showAll] and lists
/// every loan and every payment instead.
List<Widget> loansViewChildren(
  BuildContext context, {
  required List<LoanModel> loans,
  required bool isLoading,
  bool showAll = false,
  // The Manager / Officer layout: Loan History and Payment History are collapsible
  // sections of the latest [collapsedRecords] records each, closing with a button
  // to the full (read-only) screen. Overrides [showAll].
  bool collapsible = false,
  VoidCallback? onViewAllLoans,
  VoidCallback? onViewAllPayments,
  // The Farmer's approved assistance (not a loan), newest first. Listed before the loans in Loan History.
  List<AssistanceRequest> assistance = const [],
}) {
  const recentLoansCount = 3;
  const recentPaymentsCount = 5;
  const collapsedRecords = 5;
  final l10n = AppLocalizations.of(context);

  final unpaid = loans.where((l) => !l.isPaid).toList();
  final overdue = loans.where((l) => l.isOverdue).toList();

  /// What is still owed: the remaining balance of every loan that is not paid.
  final outstanding = unpaid.fold<double>(0, (sum, l) => sum + l.remainingBalance);
  // What the unpaid loans were worth, and how much of it is already paid.
  final borrowed = unpaid.fold<double>(0, (sum, l) => sum + l.totalValue);
  final repaid = unpaid.fold<double>(0, (sum, l) => sum + l.amountPaid);
  final overdueBalance = overdue.fold<double>(0, (sum, l) => sum + l.remainingBalance);

  // The earliest payment date among the unpaid loans; the next BOD Saturday when no
  // loan carries one.
  final dates = unpaid.map((l) => l.nextPaymentDate).whereType<DateTime>().toList()
    ..sort();
  final nextPaymentDate = dates.isEmpty ? BodSchedule.upcoming() : dates.first;

  // One month's payment across the unpaid loans (never more than what is left).
  final expectedPayment = unpaid.fold<double>(0, (sum, l) {
    if (l.monthlyPayment <= 0) return sum;
    return sum +
        (l.monthlyPayment < l.remainingBalance
            ? l.monthlyPayment
            : l.remainingBalance);
  });

  final allLoans = loansNewestFirst(loans);
  final shownLoans = collapsible
      ? allLoans.take(collapsedRecords).toList()
      : showAll
      ? allLoans
      : allLoans.take(recentLoansCount).toList();
  final shownAssistance = showAll || collapsible
      ? assistance
      : assistance.take(recentLoansCount).toList();
  final allPayments = paymentsNewestFirst(loans);
  final shownPayments = collapsible
      ? allPayments.take(collapsedRecords).toList()
      : showAll
      ? allPayments
      : allPayments.take(recentPaymentsCount).toList();

  return [
    _OutstandingCard(
      outstanding: outstanding,
      borrowed: borrowed,
      repaid: repaid,
      activeCount: loans.where((l) => l.isActive).length,
      overdueCount: overdue.length,
      paidCount: loans.where((l) => l.isPaid).length,
      hasLoans: loans.isNotEmpty,
      isLoading: isLoading,
    ),
    const SizedBox(height: 14),
    _NextPaymentCard(
      nextDate: nextPaymentDate,
      hasUnpaid: unpaid.isNotEmpty,
      expected: expectedPayment,
      overdueCount: overdue.length,
      overdueBalance: overdueBalance,
      isLoading: isLoading,
    ),
    const SizedBox(height: 14),
    const _InputLoanInfoCard(),
    const SizedBox(height: 24),

    if (collapsible) ...[
      // ── Loan History (latest 5, collapsible) ────────────────────────────────
      CollapsibleHistorySection(
        title: l10n.loanMyHistoryTitle,
        footerLabel: l10n.loanViewHistoryAction,
        onFooter: loans.isEmpty && assistance.isEmpty ? null : onViewAllLoans,
        children: [
          if (isLoading)
            const SkeletonBlock(height: 120)
          else if (shownLoans.isEmpty && shownAssistance.isEmpty)
            LoanEmptyNote(
              icon: Icons.agriculture_outlined,
              text: l10n.loanMyNoLoans,
            )
          else ...[
            for (final a in shownAssistance)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AssistanceRecordCard(request: a),
              ),
            for (final loan in shownLoans)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FarmerLoanCard(loan: loan, compact: true),
              ),
          ],
        ],
      ),
      const SizedBox(height: 18),

      // ── Payment History (latest 5, collapsible) ─────────────────────────────
      CollapsibleHistorySection(
        title: l10n.loanMyPaymentsTitle,
        footerLabel: l10n.loanViewPaymentsAction,
        onFooter: allPayments.isEmpty ? null : onViewAllPayments,
        children: [
          if (isLoading)
            const SkeletonBlock(height: 70)
          else if (shownPayments.isEmpty)
            LoanEmptyNote(
              icon: Icons.payments_outlined,
              text: l10n.loanMyNoPayments,
            )
          else
            for (final row in shownPayments)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FarmerPaymentRow(loan: row.loan, payment: row.payment),
              ),
        ],
      ),
    ] else ...[
      // ── Loan History ────────────────────────────────────────────────────────
      LoanSectionHeader(
        title: l10n.loanMyHistoryTitle,
        viewAllLabel: l10n.loanMyViewAll,
        onViewAll: showAll || isLoading || (loans.isEmpty && assistance.isEmpty)
            ? null
            : onViewAllLoans,
      ),
      const SizedBox(height: 10),
      if (isLoading)
        ...List.generate(
          2,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: SkeletonBlock(height: 120),
          ),
        )
      else if (shownLoans.isEmpty && shownAssistance.isEmpty)
        LoanEmptyNote(icon: Icons.agriculture_outlined, text: l10n.loanMyNoLoans)
      else ...[
        for (final a in shownAssistance)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AssistanceRecordCard(request: a),
          ),
        for (final loan in shownLoans)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            // The landing page is compact; the full list (Loan History, and the
            // Manager side) lists every item with its price.
            child: FarmerLoanCard(loan: loan, compact: !showAll),
          ),
      ],

      // ── Payment History ─────────────────────────────────────────────────────
      const SizedBox(height: 12),
      LoanSectionHeader(
        title: l10n.loanMyPaymentsTitle,
        viewAllLabel: l10n.loanMyViewAll,
        onViewAll:
            showAll || isLoading || allPayments.isEmpty ? null : onViewAllPayments,
      ),
      const SizedBox(height: 10),
      if (isLoading)
        const SkeletonBlock(height: 70)
      else if (shownPayments.isEmpty)
        LoanEmptyNote(icon: Icons.payments_outlined, text: l10n.loanMyNoPayments)
      else
        for (final row in shownPayments)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FarmerPaymentRow(loan: row.loan, payment: row.payment),
          ),
    ],
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// A history section the reader can fold away: the title with an arrow at the far
// right, the records when open, and a button to the full history under them. Open
// at first. Keeps the Manager / Officer's Farmer Details from growing with every loan.
// ─────────────────────────────────────────────────────────────────────────────

class CollapsibleHistorySection extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final String footerLabel;

  /// Opens the full (read-only) history. Null hides the button (nothing to open).
  final VoidCallback? onFooter;

  const CollapsibleHistorySection({
    super.key,
    required this.title,
    required this.children,
    required this.footerLabel,
    this.onFooter,
  });

  @override
  State<CollapsibleHistorySection> createState() =>
      _CollapsibleHistorySectionState();
}

class _CollapsibleHistorySectionState extends State<CollapsibleHistorySection> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 24,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _open
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    ...widget.children,
                    if (widget.onFooter != null)
                      Center(
                        child: TextButton(
                          onPressed: widget.onFooter,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.footerLabel,
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
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
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
        : (owing
              ? AppConstants.errorRed
              : Theme.of(context).colorScheme.primary);
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
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 18,
                  color: accent,
                ),
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!isLoading && borrowed > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
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
            Container(
              width: 180,
              height: 32,
              color: context.adaptiveSurface(const Color(0xFFE8E8E8)),
            )
          else if (allPaid)
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppConstants.successGreen,
                  size: 22,
                ),
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
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.loanMyOfBorrowed(money.format(borrowed)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: fg,
              height: 1.1,
            ),
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
                color: highlight
                    ? Colors.white.withValues(alpha: 0.92)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
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
            colors: [
              AppConstants.errorRed.withValues(alpha: 0.92),
              const Color(0xFFB71C1C),
            ],
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
                      overdue
                          ? Icons.warning_amber_rounded
                          : Icons.event_available_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        overdue
                            ? l10n.loanMyOverdueTitle(overdueCount)
                            : (hasUnpaid
                                  ? l10n.loanMyNextPaymentTitle
                                  : l10n.loanMyNoPaymentDue),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (hasUnpaid && !overdue)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppConstants.secondaryContainer,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusFull,
                          ),
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
                    color: context.saganaColors.cardBackground.withValues(
                      alpha: 0.14,
                    ),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
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
        color: context.adaptiveSurface(AppConstants.infoBlueBg),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.agriculture_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
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
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.loanMyInfoBody,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    height: 1.4,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
