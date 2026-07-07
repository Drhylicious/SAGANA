import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/expense_model.dart';
import '../../../data/repositories/expense_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/shared_widgets.dart';

class MyExpensesScreen extends StatefulWidget {
  const MyExpensesScreen({super.key});

  @override
  State<MyExpensesScreen> createState() => _MyExpensesScreenState();
}

class _MyExpensesScreenState extends State<MyExpensesScreen> {
  final _repo = ExpenseRepository();

  List<ExpenseModel> _expenses = [];
  List<CategoryBreakdown> _breakdown = [];
  double _thisMonthTotal = 0;
  double _allTimeTotal = 0;
  ExpensePeriod _period = ExpensePeriod.thisMonth;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchExpenses(_period),
      _repo.fetchThisMonthTotal(),
      _repo.fetchAllTimeTotal(),
    ]);
    if (!mounted) return;
    final expenses = results[0] as List<ExpenseModel>;
    setState(() {
      _expenses = expenses;
      _breakdown = _repo.buildBreakdown(expenses);
      _thisMonthTotal = results[1] as double;
      _allTimeTotal = results[2] as double;
      _isLoading = false;
    });
  }

  Future<void> _onPeriodChanged(ExpensePeriod p) async {
    setState(() => _period = p);
    await _loadData();
  }

  void _showAddExpense() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddExpenseSheet(
        onSaved: () {
          Navigator.pop(context);
          _loadData();
        },
        repo: _repo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.offWhite,
      body: Stack(
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
                        thisMonth: _thisMonthTotal,
                        allTime: _allTimeTotal,
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

                      // Subsidy banner
                      const _SubsidyBanner(),
                      const SizedBox(height: 20),

                      // Transactions
                      Text('Recent Transactions',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.charcoal)),
                      const SizedBox(height: 12),

                      if (_isLoading)
                        ...List.generate(3, (_) => const Padding(
                              padding: EdgeInsets.only(bottom: 10),
                              child: _ExpenseShimmer(),
                            ))
                      else if (_expenses.isEmpty)
                        const _EmptyState()
                      else
                        ..._expenses.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ExpenseRow(expense: e),
                            )),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: FarmerTopBar(title: 'My Expenses', onBack: () => Navigator.of(context).pop(), profilePhotoUrl: null, onProfileTap: () {}, onNotificationTap: () => context.pushRoute(AppRoutes.farmerNotifications), onSettingsTap: null,),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 64),
        child: FloatingActionButton(
          onPressed: _showAddExpense,
          backgroundColor: AppConstants.primaryGreen,
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top App Bar

// ─────────────────────────────────────────────────────────────────────────────
// Summary Cards
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCards extends StatelessWidget {
  final double thisMonth;
  final double allTime;
  final bool isLoading;

  const _SummaryCards({
    required this.thisMonth,
    required this.allTime,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            label: 'This Month',
            value: thisMonth,
            valueColor: AppConstants.primaryGreen,
            isLoading: isLoading,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            label: 'All Time',
            value: allTime,
            valueColor: AppConstants.charcoal,
            isLoading: isLoading,
            tinted: true,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final double value;
  final Color valueColor;
  final bool isLoading;
  final bool tinted;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.isLoading,
    this.tinted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tinted
            ? const Color(0xFFE6F6FF).withValues(alpha: 0.50)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF455A64).withValues(alpha: 0.05),
              blurRadius: 12)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppConstants.onSurfaceVariant)),
          const SizedBox(height: 6),
          isLoading
              ? Container(width: 100, height: 22, color: const Color(0xFFE8E8E8))
              : Text('₱${NumberFormat('#,##0.00').format(value)}',
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: valueColor)),
        ],
      ),
    );
  }
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppConstants.primaryContainer
                      : const Color(0xFFD5ECF8),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(p.label,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isActive
                            ? AppConstants.onPrimaryContainer
                            : AppConstants.onSurfaceVariant)),
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
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Category Breakdown',
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.charcoal)),
          const SizedBox(height: 14),
          ...breakdown.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(b.category,
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppConstants.onSurfaceVariant)),
                        Row(
                          children: [
                            Text(
                              b.total > 0
                                  ? '₱${NumberFormat('#,##0').format(b.total)}'
                                  : '₱0.00',
                              style: GoogleFonts.inter(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            if (b.hasSubsidy && b.total == 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppConstants.successGreen.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('SUBSIDY',
                                    style: GoogleFonts.inter(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: AppConstants.successGreen)),
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
                        value: b.hasSubsidy && b.total == 0 ? 1.0 : b.percentOfMax,
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
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subsidy Banner
// ─────────────────────────────────────────────────────────────────────────────

class _SubsidyBanner extends StatelessWidget {
  const _SubsidyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F6FF),
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
                    fontSize: 11, color: AppConstants.onSurfaceVariant, height: 1.4),
                children: [
                  TextSpan(
                      text: 'Subsidized Inputs: ',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700, color: AppConstants.onSurface)),
                  const TextSpan(
                      text: 'Seeds and fertilizer for Palay are covered by MAO. '
                          'Seeds for Peanut are provided by SP3. '
                          'These do not affect your totals.'),
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
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: expense.isSubsidy
            ? Border(
                left: const BorderSide(color: AppConstants.successGreen, width: 4),
                top: BorderSide(color: Colors.white.withValues(alpha: 0.40)),
                right: BorderSide(color: Colors.white.withValues(alpha: 0.40)),
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.40)),
              )
            : Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [BoxShadow(
            color: const Color(0xFF455A64).withValues(alpha: 0.05),
            blurRadius: 8)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
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
                      Text(expense.category,
                          style: GoogleFonts.poppins(
                              fontSize: 13, fontWeight: FontWeight.w500,
                              color: AppConstants.onSurface)),
                      if (expense.isSubsidy) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppConstants.successGreen,
                            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                          ),
                          child: Text('SUBSIDY',
                              style: GoogleFonts.inter(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.5)),
                        ),
                      ],
                    ],
                  ),
                  Text(expense.description,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppConstants.onSurfaceVariant)),
                  Text(DateFormat('MMM d, yyyy').format(expense.expenseDate),
                      style: GoogleFonts.inter(
                          fontSize: 10, color: AppConstants.outline)),
                ],
              ),
            ),
            Text(
              '₱${NumberFormat('#,##0.00').format(expense.amount)}',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: expense.isSubsidy
                      ? AppConstants.successGreen
                      : AppConstants.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Expense Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddExpenseSheet extends StatefulWidget {
  final VoidCallback onSaved;
  final ExpenseRepository repo;

  const _AddExpenseSheet({required this.onSaved, required this.repo});

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _descController = TextEditingController();
  final _amountController = TextEditingController(text: '0.00');

  String _category = 'Fertilizer';
  DateTime _date = DateTime.now();
  bool _isSubsidy = false;
  bool _isSaving = false;

  @override
  void dispose() {
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

  Future<void> _save() async {
    if (_descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a description.')));
      return;
    }
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (!_isSubsidy && amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid amount.')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.repo.addExpense(
        category: _category,
        description: _descController.text.trim(),
        amount: amount,
        expenseDate: _date,
        isSubsidy: _isSubsidy,
      );
      if (mounted) widget.onSaved();
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppConstants.offWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppConstants.outline.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Add New Expense',
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.primaryGreen)),
              const SizedBox(height: 20),

              // Category
              Text('Category',
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w500,
                      color: AppConstants.onSurfaceVariant)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  border: Border.all(color: AppConstants.outline.withValues(alpha: 0.20)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _category,
                    isExpanded: true,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    onChanged: (v) => setState(() => _category = v!),
                    items: expenseCategories
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Row(
                                children: [
                                  Icon(categoryIcon(c), size: 18, color: categoryColor(c)),
                                  const SizedBox(width: 10),
                                  Text(c, style: GoogleFonts.inter(fontSize: 14)),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Description
              Text('Description',
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w500,
                      color: AppConstants.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextField(
                controller: _descController,
                style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
                decoration: InputDecoration(
                  hintText: 'e.g. Hired help for harvesting',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 14, color: AppConstants.outline.withValues(alpha: 0.50)),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    borderSide: BorderSide(color: AppConstants.outline.withValues(alpha: 0.20)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    borderSide: BorderSide(color: AppConstants.outline.withValues(alpha: 0.20)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    borderSide: const BorderSide(color: AppConstants.primaryGreen, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 16),

              // Amount + Date row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Amount (₱)',
                            style: GoogleFonts.poppins(
                                fontSize: 13, fontWeight: FontWeight.w500,
                                color: AppConstants.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          enabled: !_isSubsidy,
                          style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface),
                          decoration: InputDecoration(
                            prefixText: '₱ ',
                            filled: true,
                            fillColor: _isSubsidy ? const Color(0xFFF1F5F9) : Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                              borderSide: BorderSide(color: AppConstants.outline.withValues(alpha: 0.20)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                              borderSide: BorderSide(color: AppConstants.outline.withValues(alpha: 0.20)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                              borderSide: const BorderSide(color: AppConstants.primaryGreen, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Date',
                            style: GoogleFonts.poppins(
                                fontSize: 13, fontWeight: FontWeight.w500,
                                color: AppConstants.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _pickDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                              border: Border.all(color: AppConstants.outline.withValues(alpha: 0.20)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(DateFormat('MMM d').format(_date),
                                    style: GoogleFonts.inter(fontSize: 14, color: AppConstants.onSurface)),
                                const Icon(Icons.calendar_today_rounded,
                                    size: 16, color: AppConstants.primaryGreen),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Subsidy toggle
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F6FF),
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Covered by Subsidy',
                              style: GoogleFonts.poppins(
                                  fontSize: 13, fontWeight: FontWeight.w500,
                                  color: AppConstants.onSurface)),
                          Text("This won't be added to your total.",
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: AppConstants.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isSubsidy,
                      activeColor: AppConstants.primaryGreen,
                      onChanged: (v) => setState(() {
                        _isSubsidy = v;
                        if (v) _amountController.text = '0.00';
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppConstants.primaryGreen.withValues(alpha: 0.60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                    ),
                    elevation: 2,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation(Colors.white)))
                      : Text('Save Expense',
                          style: GoogleFonts.poppins(
                              fontSize: 15, fontWeight: FontWeight.w500)),
                ),
              ),
            ],
          ),
        ),
      ),
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
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFDBF1FE),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_outlined,
                size: 36, color: AppConstants.outline.withValues(alpha: 0.60)),
          ),
          const SizedBox(height: 16),
          Text('No expenses recorded',
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  color: AppConstants.charcoal)),
          const SizedBox(height: 6),
          Text('Tap the + button to add your first expense.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppConstants.onSurfaceVariant)),
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

