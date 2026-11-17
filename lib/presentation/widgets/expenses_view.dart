import '../../core/l10n/localized_labels.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/expense_model.dart';
import 'loan_choice_chip.dart';
import 'management_modal.dart';
import 'skeleton.dart';

/// The Farmer's expenses as they read on screen: the period total, the period
/// chips, the category breakdown, the subsidy note and the list of entries, each
/// opening a read-only detail sheet.
///
/// ONE implementation for both sides. The Farmer's My Expenses screen and the
/// Manager / Officer's Farmer Details > Expenses tab build their lists from
/// [expensesViewChildren], so a change to this design reaches both. The Farmer
/// screen adds its own "add" button; the Manager side has no way to change a
/// record, and nothing here can.

String expensePeriodLabel(AppLocalizations l10n, ExpensePeriod p) {
  switch (p) {
    case ExpensePeriod.allTime:
      return l10n.loanHistoryAllTime;
    case ExpensePeriod.thisMonth:
      return l10n.loanHistoryThisMonth;
    case ExpensePeriod.thisQuarter:
      return l10n.loanHistoryThisQuarter;
    case ExpensePeriod.thisYear:
      return l10n.loanHistoryThisYear;
  }
}

/// The children of the expenses list, top to bottom. [expenses] are the entries of
/// the chosen [period] (newest first); [breakdown] is built from them with
/// buildExpenseBreakdown.
List<Widget> expensesViewChildren(
  BuildContext context, {
  required ExpensePeriod period,
  required ValueChanged<ExpensePeriod> onPeriodChanged,
  required List<ExpenseModel> expenses,
  required List<CategoryBreakdown> breakdown,
  required bool isLoading,
}) {
  final l10n = AppLocalizations.of(context);
  // The period total is the sum of every non-subsidy category's total: the same
  // figure the Category Breakdown card shows per category, summed.
  final total = breakdown.fold<double>(0, (sum, b) => sum + b.total);
  // The breakdown is sorted biggest first, so the first entry with real spending
  // is the top category (subsidy-only categories sit at 0 and are skipped).
  CategoryBreakdown? top;
  for (final b in breakdown) {
    if (b.total > 0) {
      top = b;
      break;
    }
  }
  final subsidyCount = expenses.where((e) => e.isSubsidy).length;

  return [
    _TotalCard(
      periodLabel: expensePeriodLabel(l10n, period),
      total: total,
      entryCount: expenses.length,
      topCategory: top,
      isLoading: isLoading,
    ),
    const SizedBox(height: 14),
    _PeriodChips(
      active: period,
      labelOf: (p) => expensePeriodLabel(l10n, p),
      onChanged: onPeriodChanged,
    ),
    const SizedBox(height: 18),
    if (!isLoading && breakdown.isNotEmpty) ...[
      _CategoryBreakdownCard(breakdown: breakdown, total: total),
      const SizedBox(height: 14),
    ],
    // Only when this period really has subsidized entries, with the real count.
    if (!isLoading && subsidyCount > 0) ...[
      _SubsidyNote(count: subsidyCount),
      const SizedBox(height: 14),
    ],
    _SectionHeader(
      title: l10n.expnListTitle,
      trailing: isLoading ? null : l10n.expnEntryCount(expenses.length),
    ),
    const SizedBox(height: 10),
    if (isLoading)
      ...List.generate(
        3,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: SkeletonBlock(height: 76),
        ),
      )
    else if (expenses.isEmpty)
      const _EmptyState()
    else
      for (final e in expenses)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _ExpenseCard(
            expense: e,
            onTap: () => showManagementModal<void>(
              context: context,
              builder: (_) => _ExpenseDetailSheet(expense: e),
            ),
          ),
        ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Total card — what was spent in the chosen period, at a glance.
// ─────────────────────────────────────────────────────────────────────────────

class _TotalCard extends StatelessWidget {
  final String periodLabel;
  final double total;
  final int entryCount;
  final CategoryBreakdown? topCategory;
  final bool isLoading;

  const _TotalCard({
    required this.periodLabel,
    required this.total,
    required this.entryCount,
    required this.topCategory,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final top = topCategory;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppConstants.primaryButtonGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primaryGreen.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.expnTotalSpent,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: context.saganaColors.cardBackground.withValues(
                    alpha: 0.16,
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  periodLabel,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              isLoading ? '—' : '₱${NumberFormat('#,##0.00').format(total)}',
              style: GoogleFonts.poppins(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.saganaColors.cardBackground.withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    icon: Icons.receipt_long_rounded,
                    label: l10n.expnEntries,
                    value: isLoading ? '—' : '$entryCount',
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: context.saganaColors.cardBackground.withValues(
                    alpha: 0.2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _HeroStat(
                    icon: top != null
                        ? categoryIcon(top.category)
                        : Icons.category_outlined,
                    label: l10n.expnTopCategory,
                    value: isLoading
                        ? '—'
                        : (top?.category ?? l10n.expnNoneYet),
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

class _HeroStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _HeroStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.9)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Period chips — the same chip as Manager > Loans.
// ─────────────────────────────────────────────────────────────────────────────

class _PeriodChips extends StatelessWidget {
  final ExpensePeriod active;
  final String Function(ExpensePeriod) labelOf;
  final ValueChanged<ExpensePeriod> onChanged;

  const _PeriodChips({
    required this.active,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ExpensePeriod.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = ExpensePeriod.values[i];
          return Center(
            child: LoanChoiceChip(
              label: labelOf(p),
              selected: p == active,
              showCheckmark: false,
              selectedColor: AppConstants.primaryGreen,
              onTap: () => onChanged(p),
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category breakdown — each category with its icon, amount and share.
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryBreakdownCard extends StatelessWidget {
  final List<CategoryBreakdown> breakdown;
  final double total;
  const _CategoryBreakdownCard({required this.breakdown, required this.total});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final money = NumberFormat('#,##0.00');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.expnByCategory,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < breakdown.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _BreakdownRow(
              item: breakdown[i],
              share: total > 0 ? breakdown[i].total / total : 0,
              money: money,
            ),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final CategoryBreakdown item;
  final double share;
  final NumberFormat money;
  const _BreakdownRow({
    required this.item,
    required this.share,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final subsidyOnly = item.hasSubsidy && item.total == 0;
    final color = subsidyOnly
        ? AppConstants.successGreen
        : categoryColor(item.category);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _CategoryTile(category: item.category, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      localizeBuiltinLabel(
                        AppLocalizations.of(context),
                        item.category,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '₱${money.format(item.total)}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: subsidyOnly ? 1.0 : item.percentOfMax,
                  minHeight: 6,
                  backgroundColor: color.withValues(alpha: 0.14),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subsidyOnly
                    ? l10n.expnSubsidyTag
                    : l10n.expnSharePercent((share * 100).round()),
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: subsidyOnly ? FontWeight.w700 : FontWeight.w500,
                  color: subsidyOnly
                      ? AppConstants.successGreen
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The category's icon on a soft tinted rounded square — the one visual every
/// expense has (no photos).
class _CategoryTile extends StatelessWidget {
  final String category;
  final double size;
  const _CategoryTile({required this.category, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: categoryBgColor(category).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        categoryIcon(category),
        color: categoryColor(category),
        size: size * 0.5,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subsidy note — a real, period-scoped count.
// ─────────────────────────────────────────────────────────────────────────────

class _SubsidyNote extends StatelessWidget {
  final int count;
  const _SubsidyNote({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.successGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: AppConstants.successGreen.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.volunteer_activism_rounded,
            size: 18,
            color: AppConstants.successGreen,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).expnSubsidyNote(count),
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expense card
// ─────────────────────────────────────────────────────────────────────────────

class _ExpenseCard extends StatelessWidget {
  final ExpenseModel expense;
  final VoidCallback onTap;
  const _ExpenseCard({required this.expense, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final e = expense;
    return Material(
      color: context.saganaColors.cardBackground,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.04),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _CategoryTile(category: e.category),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      e.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${e.category} · ${DateFormat('MMM d, yyyy').format(e.expenseDate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₱${NumberFormat('#,##0.00').format(e.amount)}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: e.isSubsidy
                          ? AppConstants.successGreen
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (e.isSubsidy || !e.isSynced) const SizedBox(height: 4),
                  if (e.isSubsidy)
                    _Pill(
                      label: l10n.expnSubsidyTag,
                      color: AppConstants.successGreen,
                    ),
                  if (!e.isSynced)
                    Padding(
                      padding: EdgeInsets.only(top: e.isSubsidy ? 3 : 0),
                      child: _Pill(
                        label: l10n.expnPendingSync,
                        color: AppConstants.warningAmber,
                        icon: Icons.sync_rounded,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const _Pill({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expense detail — opened by tapping an expense. Read-only, no photo.
// ─────────────────────────────────────────────────────────────────────────────

class _ExpenseDetailSheet extends StatelessWidget {
  final ExpenseModel expense;
  const _ExpenseDetailSheet({required this.expense});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final e = expense;

    final rows = <MapEntry<String, String>>[
      MapEntry(l10n.expnDetailCategory, e.category),
      MapEntry(l10n.expnDetailDescription, e.description),
      MapEntry(
        l10n.expnDetailDate,
        DateFormat('MMMM d, yyyy').format(e.expenseDate),
      ),
      MapEntry(
        l10n.expnDetailSubsidy,
        e.isSubsidy ? l10n.expnSubsidyYes : l10n.expnSubsidyNo,
      ),
      if (!e.isSynced) MapEntry(l10n.expnDetailSync, l10n.expnWaitingToSync),
    ];

    return ManagementModalShell(
      title: e.displayName,
      subtitle: localizeBuiltinLabel(AppLocalizations.of(context), e.category),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: categoryBgColor(e.category).withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            ),
            child: Column(
              children: [
                _CategoryTile(category: e.category, size: 52),
                const SizedBox(height: 10),
                Text(
                  '₱${NumberFormat('#,##0.00').format(e.amount)}',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: e.isSubsidy
                        ? AppConstants.successGreen
                        : cs.onSurface,
                  ),
                ),
                if (e.isSubsidy)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _Pill(
                      label: l10n.expnSubsidyTag,
                      color: AppConstants.successGreen,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      rows[i].key,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rows[i].value,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      footer: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
          ),
          child: Text(l10n.close),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppConstants.primaryGreen.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              size: 34,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.expnEmptyTitle,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.expnEmptyBody,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

