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
import '../../widgets/shared_widgets.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/app_toast.dart';

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
  double get _periodTotal =>
      _breakdown.fold(0.0, (sum, b) => sum + b.total);

  // Breakdown is already sorted descending by total (buildBreakdown()),
  // so the first entry with real spending is the top category. Purely
  // subsidy categories sit at total == 0 and are skipped.
  CategoryBreakdown? get _topCategory {
    for (final b in _breakdown) {
      if (b.total > 0) return b;
    }
    return null;
  }

  int get _subsidyCountThisPeriod =>
      _expenses.where((e) => e.isSubsidy).length;

  int get _entryCountThisPeriod => _expenses.length;

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
    showDialog(
      context: context,
      builder: (_) => _ExpenseDetailDialog(expense: expense),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Column(
        children: [
          if (!_isOnline)
            const OfflineBanner(message: "You're offline — new expenses are saved on your device and will sync automatically once you're reconnected."),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 64),
                    Expanded(
                child: RefreshIndicator(
                  color: AppConstants.primaryGreen,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                    children: [
                      // Summary cards
                      _SummaryCards(
                        periodTotal: _periodTotal,
                        topCategory: _topCategory,
                        entryCount: _entryCountThisPeriod,
                        isLoading: _isLoading,
                      ),
                      const SizedBox(height: 16),

                      // Period filter
                      _PeriodFilter(
                        active: _period,
                        onChanged: _onPeriodChanged,
                      ),
                      const SizedBox(height: 20),

                      // Category breakdown
                      if (!_isLoading && _breakdown.isNotEmpty) ...[
                        _CategoryBreakdownCard(breakdown: _breakdown),
                        const SizedBox(height: 16),
                      ],

                      // Subsidy banner — only shown when this period
                      // actually has subsidized entries, with a real
                      // count rather than static, crop-specific text.
                      if (!_isLoading && _subsidyCountThisPeriod > 0) ...[
                        _SubsidyBanner(count: _subsidyCountThisPeriod),
                        const SizedBox(height: 20),
                      ],

                      // Transactions
                      Text(
                        'Recent Transactions',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.charcoal,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (_isLoading)
                        ...List.generate(
                          3,
                          (_) => const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: _ExpenseShimmer(),
                          ),
                        )
                      else if (_expenses.isEmpty)
                        const _EmptyState()
                      else
                        ..._expenses.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GestureDetector(
                              onTap: () => _showExpenseDetail(e),
                              child: _ExpenseRow(expense: e),
                            ),
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
              title: 'My Expenses',
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 64),
        child: FloatingActionButton(
          onPressed: _showAddExpense,
          backgroundColor: AppConstants.primaryGreen,
          child: Icon(
            Icons.add_rounded,
            color: Theme.of(context).colorScheme.onPrimary,
            size: 32,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Cards — mirrors Admin Marketplace tab's _KpiStrip/_KpiTile pattern
// (marketplace_dashboard_screen.dart) exactly: fixed-width tinted tiles in a
// horizontal strip, icon badge + label + big value, consistent sizing.
// Replaces the old, always month/all-time-scoped "This Month" / "All Time"
// cards, which duplicated the period filter directly below them.
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCards extends StatelessWidget {
  final double periodTotal;
  final CategoryBreakdown? topCategory;
  final int entryCount;
  final bool isLoading;

  const _SummaryCards({
    required this.periodTotal,
    required this.topCategory,
    required this.entryCount,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _KpiTile(
        'Period Total',
        isLoading ? '—' : '₱${NumberFormat('#,##0').format(periodTotal)}',
        AppConstants.primaryGreen,
        Icons.payments_rounded,
      ),
      _KpiTile(
        'Top Category',
        isLoading ? '—' : (topCategory?.category ?? 'None yet'),
        topCategory != null ? categoryColor(topCategory!.category) : AppConstants.outline,
        topCategory != null ? categoryIcon(topCategory!.category) : Icons.category_outlined,
      ),
      _KpiTile(
        'Entries',
        isLoading ? '—' : '$entryCount',
        AppConstants.buyerBlue,
        Icons.receipt_long_rounded,
      ),
    ];

    return SizedBox(
      height: 98,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final t = tiles[i];
          return Container(
            width: 112,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: t.color.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: t.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  ),
                  child: Icon(t.icon, size: 14, color: t.color),
                ),
                const SizedBox(height: 6),
                Text(t.label,
                    style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant, height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(t.value,
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: AppConstants.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KpiTile {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _KpiTile(this.label, this.value, this.color, this.icon);
}

// ─────────────────────────────────────────────────────────────────────────────
// Period Filter
// ─────────────────────────────────────────────────────────────────────────────

class _PeriodFilter extends StatelessWidget {
  final ExpensePeriod active;
  final ValueChanged<ExpensePeriod> onChanged;

  const _PeriodFilter({required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ExpensePeriod.values.map((p) {
          final isActive = p == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppConstants.primaryContainer
                      : const Color(0xFFD5ECF8),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  p.label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? AppConstants.onPrimaryContainer
                        : AppConstants.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category Breakdown Card
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryBreakdownCard extends StatelessWidget {
  final List<CategoryBreakdown> breakdown;
  const _CategoryBreakdownCard({required this.breakdown});

  @override
  Widget build(BuildContext context) {
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
            'Category Breakdown',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppConstants.charcoal,
            ),
          ),
          const SizedBox(height: 14),
          ...breakdown.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        b.category,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppConstants.onSurfaceVariant,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            b.total > 0
                                ? '₱${NumberFormat('#,##0').format(b.total)}'
                                : '₱0.00',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (b.hasSubsidy && b.total == 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppConstants.successGreen.withValues(
                                  alpha: 0.10,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'SUBSIDY',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppConstants.successGreen,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: b.hasSubsidy && b.total == 0
                          ? 1.0
                          : b.percentOfMax,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFCFE6F2),
                      valueColor: AlwaysStoppedAnimation(
                        b.hasSubsidy && b.total == 0
                            ? AppConstants.successGreen
                            : categoryColor(b.category),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Subsidy Banner — now a real, period-scoped count instead of static,
// crop-specific text (which named Palay/Peanut/MAO/SP3 regardless of what
// the farmer actually grows, and showed no number at all).
// ─────────────────────────────────────────────────────────────────────────────

class _SubsidyBanner extends StatelessWidget {
  final int count;
  const _SubsidyBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppConstants.outline.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_rounded, color: AppConstants.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppConstants.onSurfaceVariant,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: 'Subsidized Inputs: ',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: AppConstants.onSurface,
                    ),
                  ),
                  TextSpan(
                    text: '$count subsidized ${count == 1 ? 'input' : 'inputs'} '
                        'this period — these do not affect your totals above.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expense Row
// ─────────────────────────────────────────────────────────────────────────────

class _ExpenseRow extends StatelessWidget {
  final ExpenseModel expense;
  const _ExpenseRow({required this.expense});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: expense.isSubsidy
            ? const BorderRadius.horizontal(
                right: Radius.circular(AppConstants.radiusLg),
              )
            : BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 8,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: expense.bgColor.withValues(alpha: 0.40),
                shape: BoxShape.circle,
              ),
              child: Icon(expense.icon, color: expense.color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          expense.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppConstants.onSurface,
                          ),
                        ),
                      ),
                      if (expense.isSubsidy) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppConstants.successGreen,
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusFull,
                            ),
                          ),
                          child: Text(
                            'SUBSIDY',
                            style: GoogleFonts.inter(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                      if (!expense.isSynced) ...[
                        const SizedBox(width: 8),
                        _SyncBadge(isSynced: expense.isSynced),
                      ],
                    ],
                  ),
                  Text(
                    '${expense.category} · ${expense.description}',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppConstants.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    DateFormat('MMM d, yyyy').format(expense.expenseDate),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppConstants.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '₱${NumberFormat('#,##0.00').format(expense.amount)}',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: expense.isSubsidy
                    ? AppConstants.successGreen
                    : AppConstants.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppConstants.outline),
          ],
        ),
      ),
    );

    if (!expense.isSubsidy) return SizedBox(width: double.infinity, child: card);

    // A single BoxDecoration can't mix a borderRadius with a non-uniform
    // Border (different colors per side) — Flutter throws "A borderRadius
    // can only be given on borders with uniform colors." at paint time.
    // The subsidy accent is drawn as a separate colored stripe instead,
    // with the card itself using a uniform border + right-only radius.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: const BoxDecoration(
              color: AppConstants.successGreen,
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(AppConstants.radiusLg),
              ),
            ),
          ),
          Expanded(child: card),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expense Detail Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ExpenseDetailDialog extends StatelessWidget {
  final ExpenseModel expense;
  const _ExpenseDetailDialog({required this.expense});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      title: Text(
        expense.displayName,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow(label: 'Category', value: expense.category),
          _DetailRow(label: 'Description', value: expense.description),
          _DetailRow(
            label: 'Amount',
            value: '₱${NumberFormat('#,##0.00').format(expense.amount)}',
          ),
          _DetailRow(
            label: 'Date',
            value: DateFormat('MMM d, yyyy').format(expense.expenseDate),
          ),
          _DetailRow(
            label: 'Covered by Subsidy',
            value: expense.isSubsidy ? 'Yes' : 'No',
          ),
          if (!expense.isSynced)
            const _DetailRow(label: 'Sync Status', value: 'Pending'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Close',
            style: GoogleFonts.poppins(color: AppConstants.primaryGreen),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppConstants.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppConstants.onSurface,
              ),
            ),
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
          AppToast.show(context, 'Saved offline — will sync once you\'re back online.');
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
      // width doesn't fit, which is what was happening here.
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
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
                    : const Text('Save Expense'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFFDBF1FE),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_outlined,
              size: 36,
              color: AppConstants.outline.withValues(alpha: 0.60),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No expenses recorded',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppConstants.charcoal,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the + button to add your first expense.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppConstants.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer
// ─────────────────────────────────────────────────────────────────────────────

class _ExpenseShimmer extends StatelessWidget {
  const _ExpenseShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sync Badge
// ─────────────────────────────────────────────────────────────────────────────
//
// Visually identical to harvest_hub_screen.dart's private _SyncBadge, so
// "Pending"/"Synced" reads the same way across both offline-capable
// features. Duplicated rather than shared because extracting it into
// shared_widgets.dart would mean modifying harvest_hub_screen.dart too —
// outside this phase's approved Profile Tab scope. Flagged below as a
// refactoring opportunity for whenever Harvest is next touched.

class _SyncBadge extends StatelessWidget {
  final bool isSynced;
  const _SyncBadge({required this.isSynced});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isSynced
            ? AppConstants.successGreen.withValues(alpha: 0.10)
            : AppConstants.warningAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSynced ? Icons.cloud_done_rounded : Icons.sync_rounded,
            size: 10,
            color: isSynced
                ? AppConstants.successGreen
                : AppConstants.warningAmber,
          ),
          const SizedBox(width: 3),
          Text(
            isSynced ? 'Synced' : 'Pending',
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: isSynced
                  ? AppConstants.successGreen
                  : AppConstants.warningAmber,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
