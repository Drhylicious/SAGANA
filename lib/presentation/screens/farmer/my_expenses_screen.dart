import '../../../core/l10n/localized_labels.dart';
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
import '../../widgets/expenses_view.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/app_toast.dart';
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
                  color: Theme.of(context).colorScheme.primary,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                    children: expensesViewChildren(
                      context,
                      period: _period,
                      onPeriodChanged: _onPeriodChanged,
                      expenses: _expenses,
                      breakdown: _breakdown,
                      isLoading: _isLoading,
                    ),
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
        heroTag: null, onPressed: _showAddExpense,
        tooltip: l10n.expnAddTooltip,
        backgroundColor: AppConstants.primaryGreen,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded, size: 30),
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
    // A new category is shared with the whole cooperative, so it is created on
    // the server. The built-in and saved categories still work offline.
    if (!ConnectivityService.instance.isOnline) {
      AppToast.show(
        context,
        AppLocalizations.of(context).errOffline,
        isError: true,
      );
      return null;
    }
    final name = await promptForNewOptionName(
      context,
      title: AppLocalizations.of(context).enhAddExpenseCategory,
      hintText: AppLocalizations.of(context).enhEGLivestockFeed,
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
      AppToast.show(
        context,
        AppLocalizations.of(context).enhPleaseSelectACategory,
        isError: true,
      );
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      AppToast.show(
        context,
        AppLocalizations.of(context).enhPleaseEnterAName,
        isError: true,
      );
      return;
    }
    if (_descController.text.trim().isEmpty) {
      AppToast.show(
        context,
        AppLocalizations.of(context).enhPleaseEnterADescription,
        isError: true,
      );
      return;
    }
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText) ?? 0;
    if (!_isSubsidy && (!isValidCurrencyValue(amountText) || amount <= 0)) {
      AppToast.show(
        context,
        AppLocalizations.of(context).enhPleaseEnterAValidAmount,
        isError: true,
      );
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
          AppToast.show(
            context,
            AppLocalizations.of(context).offlineSavedWillSync,
          );
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
        AppToast.show(
          context,
          AppLocalizations.of(context).adminProfileSaveError,
          isError: true,
        );
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
        AppLocalizations.of(context).enhAddNewExpense,
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
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
                hintText: AppLocalizations.of(context).commonSelectCategory,
                labelText: AppLocalizations.of(context).buyerListingCategory,
                items: _categories,
                itemLabel: (c) =>
                    localizeBuiltinLabel(AppLocalizations.of(context), c),
                onChanged: (v) => setState(() => _category = v),
                addNewLabel: AppLocalizations.of(context).enhAddNewCategory,
                onAddNew: _addNewCategory,
              ),
              const SizedBox(height: 16),

              // Name
              Text(
                AppLocalizations.of(context).programMgmtFieldName,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).enhEGUreaFertilizer,
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
                AppLocalizations.of(context).programMgmtFieldDescription,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descController,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(
                    context,
                  ).enhEGHiredHelpForHarvesting,
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
                AppLocalizations.of(context).farmerDetailsAmountLabel,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                enabled: !_isSubsidy,
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  prefixText: '₱ ',
                  filled: _isSubsidy,
                  fillColor: context.adaptiveSurface(const Color(0xFFF1F5F9)),
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
                AppLocalizations.of(context).rptDate,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('MMM d, yyyy').format(_date),
                        style: GoogleFonts.inter(fontSize: 14),
                      ),
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
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
                  color: context.adaptiveSurface(const Color(0xFFE6F6FF)),
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
                            AppLocalizations.of(context).enhCoveredBySubsidy,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            AppLocalizations.of(
                              context,
                            ).enhThisWonTBeAddedToYourTotal,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
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
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          AppLocalizations.of(context).enhSaveExpense,
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
