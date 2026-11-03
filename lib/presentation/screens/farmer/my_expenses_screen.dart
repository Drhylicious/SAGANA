import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/input_validation_utils.dart';
import '../../../data/models/expense_model.dart';
import '../../../data/repositories/expense_repository.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/top_bar_spacer.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/loan_choice_chip.dart';
import '../../widgets/management_modal.dart';
import '../../../core/l10n/app_localizations.dart';

/// My Expenses — a simple record of what the Farmer spent.
///
/// An expense is text and a number (name, category, description, amount, date,
/// "covered by subsidy"). It carries no photo or attachment: the category icon
/// is the only picture, so the screen stays quick to fill in and to read.
class MyExpensesScreen extends StatefulWidget {
  const MyExpensesScreen({super.key});

  @override
  State<MyExpensesScreen> createState() => _MyExpensesScreenState();
}

class _MyExpensesScreenState extends State<MyExpensesScreen> {
  final _repo = ExpenseRepository();
  final _categoryRepo = CategoryRepository();

  List<ExpenseModel> _expenses = [];
  List<CategoryBreakdown> _breakdown = [];
  List<String> _categories = [];
  ExpensePeriod _period = ExpensePeriod.thisMonth;
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
    ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
    _loadData();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories = await _categoryRepo.fetchExpenseCategories();
    if (!mounted) return;
    setState(() => _categories = categories);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final expenses = await _repo.fetchExpenses(_period);
    if (!mounted) return;
    setState(() {
      _expenses = expenses;
      _breakdown = _repo.buildBreakdown(expenses);
      _isLoading = false;
    });
  }

  Future<void> _onPeriodChanged(ExpensePeriod p) async {
    setState(() => _period = p);
    await _loadData();
  }

  // Period total is the sum of every non-subsidy category's total for the
  // currently selected period — the same figure the Category Breakdown
  // card already shows per-category, just summed. No separate query.
  double get _periodTotal => _breakdown.fold(0.0, (sum, b) => sum + b.total);

  // Breakdown is already sorted descending by total (buildBreakdown()),
  // so the first entry with real spending is the top category. Purely
  // subsidy categories sit at total == 0 and are skipped.
  CategoryBreakdown? get _topCategory {
    for (final b in _breakdown) {
      if (b.total > 0) return b;
    }
    return null;
  }

  int get _subsidyCountThisPeriod => _expenses.where((e) => e.isSubsidy).length;

  int get _entryCountThisPeriod => _expenses.length;

  String _periodLabel(AppLocalizations l10n, ExpensePeriod p) {
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

  void _showAddExpense() {
    showDialog(
      context: context,
      builder: (_) => _AddExpenseDialog(
        repo: _repo,
        categoryRepo: _categoryRepo,
        categories: _categories,
        onCategoriesChanged: (updated) => setState(() => _categories = updated),
        onSaved: () {
          Navigator.pop(context);
          _loadData();
        },
      ),
    );
  }

  void _showExpenseDetail(ExpenseModel expense) {
    showManagementModal<void>(
      context: context,
      builder: (_) => _ExpenseDetailSheet(expense: expense),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              CachedDataNotice(
                screen: 'expenses_${_period.name}',
                isOnline: _isOnline,
                offlineMessage: l10n.offlineExpensesSave,
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                    children: [
                      _TotalCard(
                        periodLabel: _periodLabel(l10n, _period),
                        total: _periodTotal,
                        entryCount: _entryCountThisPeriod,
                        topCategory: _topCategory,
                        isLoading: _isLoading,
                      ),
                      const SizedBox(height: 14),
                      _PeriodChips(
                        active: _period,
                        labelOf: (p) => _periodLabel(l10n, p),
                        onChanged: _onPeriodChanged,
                      ),
                      const SizedBox(height: 18),
                      if (!_isLoading && _breakdown.isNotEmpty) ...[
                        _CategoryBreakdownCard(
                          breakdown: _breakdown,
                          total: _periodTotal,
                        ),
                        const SizedBox(height: 14),
                      ],
                      // Only when this period really has subsidized entries,
                      // with the real count.
                      if (!_isLoading && _subsidyCountThisPeriod > 0) ...[
                        _SubsidyNote(count: _subsidyCountThisPeriod),
                        const SizedBox(height: 14),
                      ],
                      _SectionHeader(
                        title: l10n.expnListTitle,
                        trailing: _isLoading
                            ? null
                            : l10n.expnEntryCount(_entryCountThisPeriod),
                      ),
                      const SizedBox(height: 10),
                      if (_isLoading)
                        ...List.generate(
                          3,
                          (_) => const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: SkeletonBlock(height: 76),
                          ),
                        )
                      else if (_expenses.isEmpty)
                        const _EmptyState()
                      else
                        for (final e in _expenses)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ExpenseCard(
                              expense: e,
                              onTap: () => _showExpenseDetail(e),
                            ),
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
              title: l10n.expnScreenTitle,
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
        onPressed: _showAddExpense,
        tooltip: l10n.expnAddTooltip,
        backgroundColor: AppConstants.primaryGreen,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded, size: 30),
      ),
    );
  }
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
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
              color: Colors.white.withValues(alpha: 0.12),
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
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _HeroStat(
                    icon: top != null
                        ? categoryIcon(top.category)
                        : Icons.category_outlined,
                    label: l10n.expnTopCategory,
                    value: isLoading ? '—' : (top?.category ?? l10n.expnNoneYet),
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
  const _HeroStat({required this.icon, required this.label, required this.value});

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
              color: AppConstants.charcoal,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: GoogleFonts.inter(fontSize: 12, color: AppConstants.outline),
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
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45),
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
              color: AppConstants.charcoal,
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
  const _BreakdownRow({required this.item, required this.share, required this.money});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final subsidyOnly = item.hasSubsidy && item.total == 0;
    final color = subsidyOnly ? AppConstants.successGreen : categoryColor(item.category);
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
                      item.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '₱${money.format(item.total)}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.onSurface,
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
                  color: subsidyOnly ? AppConstants.successGreen : AppConstants.outline,
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
        border: Border.all(color: AppConstants.successGreen.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.volunteer_activism_rounded, size: 18, color: AppConstants.successGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).expnSubsidyNote(count),
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.4,
                color: AppConstants.onSurfaceVariant,
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
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45),
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
                        color: AppConstants.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      e.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: AppConstants.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${e.category} · ${DateFormat('MMM d, yyyy').format(e.expenseDate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 10.5, color: AppConstants.outline),
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
                      color: e.isSubsidy ? AppConstants.successGreen : AppConstants.onSurface,
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
      MapEntry(l10n.expnDetailDate, DateFormat('MMMM d, yyyy').format(e.expenseDate)),
      MapEntry(
        l10n.expnDetailSubsidy,
        e.isSubsidy ? l10n.expnSubsidyYes : l10n.expnSubsidyNo,
      ),
      if (!e.isSynced) MapEntry(l10n.expnDetailSync, l10n.expnWaitingToSync),
    ];

    return ManagementModalShell(
      title: e.displayName,
      subtitle: e.category,
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
                    color: e.isSubsidy ? AppConstants.successGreen : cs.onSurface,
                  ),
                ),
                if (e.isSubsidy)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _Pill(label: l10n.expnSubsidyTag, color: AppConstants.successGreen),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      rows[i].key,
                      style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
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
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
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
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 34,
              color: AppConstants.primaryGreen,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.expnEmptyTitle,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppConstants.charcoal,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.expnEmptyBody,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Expense Dialog (was a bottom sheet — converted to a dialog per
// explicit request, an intentional exception to this codebase's usual
// bottom-sheet-first modal convention for this one screen)
// ─────────────────────────────────────────────────────────────────────────────

class _AddExpenseDialog extends StatefulWidget {
  final VoidCallback onSaved;
  final ExpenseRepository repo;
  final CategoryRepository categoryRepo;
  final List<String> categories;
  final ValueChanged<List<String>> onCategoriesChanged;

  const _AddExpenseDialog({
    required this.onSaved,
    required this.repo,
    required this.categoryRepo,
    required this.categories,
    required this.onCategoriesChanged,
  });

  @override
  State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _amountController = TextEditingController(text: '0.00');

  late List<String> _categories;
  String? _category;
  DateTime _date = DateTime.now();
  bool _isSubsidy = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _categories = widget.categories;
    _category = _categories.isNotEmpty ? _categories.first : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppConstants.primaryGreen,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<String?> _addNewCategory() async {
    final name = await promptForNewOptionName(
      context,
      title: 'Add Expense Category',
      hintText: 'e.g. Livestock Feed',
    );
    if (name == null) return null;
    final added = await widget.categoryRepo.addExpenseCategory(name);
    if (added == null) return null;
    if (!_categories.contains(added)) {
      setState(() => _categories = [..._categories, added]);
      widget.onCategoriesChanged(_categories);
    }
    return added;
  }

  Future<void> _save() async {
    if (_category == null) {
      AppToast.show(context, 'Please select a category.', isError: true);
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      AppToast.show(context, 'Please enter a name.', isError: true);
      return;
    }
    if (_descController.text.trim().isEmpty) {
      AppToast.show(context, 'Please enter a description.', isError: true);
      return;
    }
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText) ?? 0;
    if (!_isSubsidy && (!isValidCurrencyValue(amountText) || amount <= 0)) {
      AppToast.show(context, 'Please enter a valid amount.', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final result = await widget.repo.addExpense(
        name: _nameController.text.trim(),
        category: _category!,
        description: _descController.text.trim(),
        amount: amount,
        expenseDate: _date,
        isSubsidy: _isSubsidy,
      );
      if (mounted) {
        // Shown on the dialog's own context before it's popped by
        // widget.onSaved() below — so the farmer knows this was queued,
        // not lost (Phase 2 / U2, closes the gap where an offline
        // expense used to just fail with no queuing). AppToast (not a
        // ScaffoldMessenger SnackBar) since a SnackBar fired from inside
        // a dialog's own context renders behind the dialog, not in front
        // of it — see app_toast.dart's doc comment.
        if (!result.isSynced) {
          AppToast.show(context, AppLocalizations.of(context).offlineSavedWillSync);
        }
        // Broadcasts to Profile (and any other listening screen) so the
        // "This month's expenses" tile doesn't go stale after adding an
        // expense here and navigating back — mirrors what
        // harvest_entry_form_screen.dart already does after a harvest
        // submission (Final Verification, item 1).
        AppEventService.instance.notify();
        widget.onSaved();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppToast.show(context, 'Failed to save. Please try again.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // A little wider on a phone: the form fields and the two action buttons
      // need the room (the default inset leaves ~40px each side).
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      title: Text(
        'Add New Expense',
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppConstants.primaryGreen,
        ),
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Category
              AppDropdownField<String>(
                value: _category,
                hintText: 'Select a category',
                labelText: 'Category',
                items: _categories,
                itemLabel: (c) => c,
                onChanged: (v) => setState(() => _category = v),
                addNewLabel: 'Add New Category',
                onAddNew: _addNewCategory,
              ),
              const SizedBox(height: 16),

              // Name
              Text(
                'Name',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Urea Fertilizer',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Description
              Text(
                'Description',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descController,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Hired help for harvesting',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Amount
              Text(
                'Amount (₱)',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                enabled: !_isSubsidy,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  prefixText: '₱ ',
                  filled: _isSubsidy,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Date
              Text(
                'Date',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppConstants.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    border: Border.all(
                      color: AppConstants.outline.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('MMM d, yyyy').format(_date),
                        style: GoogleFonts.inter(fontSize: 14),
                      ),
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: AppConstants.primaryGreen,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Subsidy toggle
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F6FF),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Covered by Subsidy',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppConstants.onSurface,
                            ),
                          ),
                          Text(
                            "This won't be added to your total.",
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppConstants.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isSubsidy,
                      activeThumbColor: AppConstants.primaryGreen,
                      onChanged: (v) => setState(() {
                        _isSubsidy = v;
                        if (v) _amountController.text = '0.00';
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      // A single Row action (rather than two separate `actions` entries)
      // so Cancel/Save always render side by side — AlertDialog's default
      // OverflowBar stacks its actions vertically once their combined
      // width doesn't fit.
      //
      // Both buttons get an equal share, a tight horizontal padding and a
      // one-line, shrink-to-fit label. Cancel used to get only a third of the
      // row (flex 1 vs 2) while keeping the button's default 24px side padding,
      // which on a narrow phone left almost no room for the text, so it wrapped
      // one letter per line ("ca / nc / el").
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    AppLocalizations.of(context).cancel,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  backgroundColor: AppConstants.primaryGreen,
                  foregroundColor: Colors.white,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Save Expense',
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

