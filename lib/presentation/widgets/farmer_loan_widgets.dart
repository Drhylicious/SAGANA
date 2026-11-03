import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/loan_model.dart';
import 'loan_choice_chip.dart';

// The pieces of the Farmer's Input Loans area, shared by the landing page and the
// two "View All" screens (Loan History, Payment History) so a loan or a payment
// looks the same wherever it is shown.

final NumberFormat _money = NumberFormat('#,##0.00');

/// "Loan History  ·····  View All" — a section title with the View All button at
/// the right.
class LoanSectionHeader extends StatelessWidget {
  final String title;
  final String? viewAllLabel;
  final VoidCallback? onViewAll;

  const LoanSectionHeader({
    super.key,
    required this.title,
    this.viewAllLabel,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppConstants.charcoal,
            ),
          ),
        ),
        if (onViewAll != null && viewAllLabel != null)
          TextButton(
            onPressed: onViewAll,
            style: TextButton.styleFrom(
              foregroundColor: AppConstants.primaryGreen,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  viewAllLabel!,
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

/// All / Active Loans / Overdue Loans / Paid — the same chips and words as
/// Manager > Loan History. [counts], when given, adds the number of loans each
/// chip would show (keyed by status; null key = All).
class LoanStatusChips extends StatelessWidget {
  final String? active;
  final ValueChanged<String?> onChanged;
  final Map<String?, int>? counts;

  const LoanStatusChips({
    super.key,
    required this.active,
    required this.onChanged,
    this.counts,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <String?, String>{
      null: l10n.loanHistoryFilterAll,
      'active': l10n.loanDashActiveLoans,
      'overdue': l10n.loanDashOverdueLoans,
      'paid': l10n.loanHistoryFilterPaid,
    };
    String label(String? key) =>
        counts == null ? options[key]! : '${options[key]} (${counts![key] ?? 0})';

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final key = options.keys.elementAt(i);
          return Center(
            child: LoanChoiceChip(
              label: label(key),
              selected: active == key,
              selectedColor: AppConstants.buyerBlue,
              onTap: () => onChanged(key),
            ),
          );
        },
      ),
    );
  }
}

/// A centred icon and a sentence, for an empty list.
class LoanEmptyNote extends StatelessWidget {
  final IconData icon;
  final String text;
  const LoanEmptyNote({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppConstants.outline.withValues(alpha: 0.7)),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.4,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One loan. [compact] (the landing page) shows the items on one line; the full
/// card (Loan History) lists every item with its price.
class FarmerLoanCard extends StatelessWidget {
  final LoanModel loan;
  final bool compact;

  const FarmerLoanCard({super.key, required this.loan, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    // Same colours as Manager > Loan History: paid blue, overdue red, active green.
    final statusColor = loan.isPaid
        ? AppConstants.buyerBlue
        : (loan.isOverdue ? AppConstants.errorRed : AppConstants.successGreen);
    final statusLabel = loan.isPaid
        ? l10n.loanStatusPaid
        : (loan.isOverdue ? l10n.loanStatusOverdue : l10n.loanStatusActive);
    final accent = loan.isPaid
        ? AppConstants.buyerBlue
        : (loan.isOverdue ? AppConstants.errorRed : AppConstants.primaryGreen);
    final payment = loan.monthlyPayment > 0 && loan.monthlyPayment < loan.remainingBalance
        ? loan.monthlyPayment
        : loan.remainingBalance;

    String itemSummary() {
      final names = loan.items.map((i) => i.displayLabel).toList();
      if (names.isEmpty) return '';
      if (names.length <= 2) return names.join(', ');
      return '${names.take(2).join(', ')} ${l10n.loanMyMoreItems(names.length - 2)}';
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: loan.isOverdue
              ? AppConstants.errorRed.withValues(alpha: 0.25)
              : cs.outline.withValues(alpha: 0.10),
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loan.referenceNo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            l10n.loanMyIssued(DateFormat('MMM d, yyyy').format(loan.issuedDate)),
                            style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                      ),
                      child: Text(
                        statusLabel.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                if (loan.isFromProgramDistribution) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.volunteer_activism_rounded, size: 13, color: AppConstants.programPurple),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          l10n.loanMyFromProgram(loan.sourceProgramName ?? ''),
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
                const SizedBox(height: 10),
                if (compact)
                  Text(
                    itemSummary(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: cs.onSurface),
                  )
                else
                  for (final item in loan.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.displayLabel,
                              style: GoogleFonts.inter(fontSize: 12.5, color: cs.onSurface),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '₱${NumberFormat('#,##0').format(item.lineTotal)}',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F6FF).withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppConstants.radiusLg)),
              border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.08))),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _Figure(
                        label: l10n.loanMyTotalValue,
                        value: '₱${_money.format(loan.totalValue)}',
                        color: cs.onSurface,
                      ),
                    ),
                    Expanded(
                      child: _Figure(
                        label: l10n.loanMyRemaining,
                        value: '₱${_money.format(loan.remainingBalance)}',
                        color: accent,
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: loan.repaidPercent,
                    minHeight: 8,
                    backgroundColor: cs.outline.withValues(alpha: 0.18),
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: !loan.isPaid && loan.nextPaymentDate != null
                          ? Text(
                              l10n.loanMyNextPayment(
                                DateFormat('MMM d, yyyy').format(loan.nextPaymentDate!),
                                _money.format(payment),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 10.5, color: cs.onSurfaceVariant),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.loanMyRepaid((loan.repaidPercent * 100).round()),
                      style: GoogleFonts.inter(fontSize: 10.5, color: cs.outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool alignEnd;
  const _Figure({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: color),
          ),
        ),
      ],
    );
  }
}

/// One payment — the same row as Manager > Loan Details, with the loan it was
/// made on.
class FarmerPaymentRow extends StatelessWidget {
  final LoanModel loan;
  final LoanPaymentModel payment;

  const FarmerPaymentRow({super.key, required this.loan, required this.payment});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final note = (payment.notes ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(
              color: AppConstants.successGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppConstants.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('MMMM d, yyyy').format(payment.paymentDate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₱${_money.format(payment.amountPaid)}',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.successGreen,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.loanMyPaymentLoan(loan.referenceNo),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.loanDetailsBalanceAfter('₱${_money.format(payment.runningBalance)}'),
                      style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                if (note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      note,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant,
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
