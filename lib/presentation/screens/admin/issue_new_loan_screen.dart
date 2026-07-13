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
import '../../../data/services/hive_service.dart';
import '../../widgets/shared_widgets.dart';

/// Issue New Loan — Admin.
/// Pushed above the shell (has a back button). Route: /admin/loans/issue
///
/// Offline behavior: if offline at submit time, the loan is queued to Hive
/// (no reference number assigned yet) and synced automatically by
/// SyncService once connectivity returns. The farmer picker falls back to
/// a cached roster when offline; the outstanding-balance check is skipped
/// entirely offline (shown as "unavailable" rather than guessed).
class IssueNewLoanScreen extends StatefulWidget {
  const IssueNewLoanScreen({super.key});

  @override
  State<IssueNewLoanScreen> createState() => _IssueNewLoanScreenState();
}

class _IssueNewLoanScreenState extends State<IssueNewLoanScreen> {
  final _repo = AdminLoanRepository();
  final _notesController = TextEditingController();
  final _monthlyPaymentController = TextEditingController();

  bool _isOnline = true;
  bool _isLoadingRoster = true;
  bool _isSubmitting = false;
  bool _monthlyPaymentManuallyEdited = false;

  List<FarmerPickerResult> _farmerRoster = [];
  FarmerPickerResult? _selectedFarmer;
  FarmerLoanStanding? _farmerStanding;
  bool _standingCheckedOnline = false;

  DateTime _issuedDate = DateTime.now();
  final List<_LoanItemDraft> _items = [];

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadFarmerRoster();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _monthlyPaymentController.dispose();
    super.dispose();
  }

  // ─── Data loading ───────────────────────────────────────────────────────

  Future<void> _loadFarmerRoster() async {
    setState(() => _isLoadingRoster = true);

    if (_isOnline) {
      final roster = await _repo.fetchFarmerRoster();
      if (roster.isNotEmpty) {
        await HiveService.cacheFarmerRoster(
          roster.map((f) => f.toMap()).toList(),
        );
        if (!mounted) return;
        setState(() {
          _farmerRoster = roster;
          _isLoadingRoster = false;
        });
        return;
      }
    }

    // Offline, or the live fetch returned nothing — fall back to cache.
    final cached = HiveService.getCachedFarmerRoster();
    if (!mounted) return;
    setState(() {
      _farmerRoster = cached.map(FarmerPickerResult.fromMap).toList();
      _isLoadingRoster = false;
    });
  }

  Future<void> _onFarmerSelected(FarmerPickerResult farmer) async {
    setState(() {
      _selectedFarmer = farmer;
      _farmerStanding = null;
      _standingCheckedOnline = false;
    });
    if (_isOnline) {
      final standing = await _repo.fetchFarmerLoanStanding(farmer.id);
      if (!mounted || _selectedFarmer?.id != farmer.id) return;
      setState(() {
        _farmerStanding = standing;
        _standingCheckedOnline = true;
      });
    }
  }

  // ─── Derived values ─────────────────────────────────────────────────────

  double get _totalValue =>
      _items.fold<double>(0, (sum, i) => sum + i.lineTotal);

  double get _suggestedMonthlyPayment =>
      _totalValue > 0 ? (_totalValue / 12) : 0;

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

  void _recalculateSuggestedMonthlyPayment() {
    if (_monthlyPaymentManuallyEdited) return;
    _monthlyPaymentController.text = _suggestedMonthlyPayment.toStringAsFixed(
      0,
    );
  }

  // ─── Item CRUD ──────────────────────────────────────────────────────────

  void _openAddItemSheet({_LoanItemDraft? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddLoanItemSheet(
        existing: existing,
        onSave: (draft) {
          setState(() {
            if (existing != null) {
              final idx = _items.indexWhere((i) => i.id == existing.id);
              if (idx != -1) _items[idx] = draft;
            } else {
              _items.add(draft);
            }
            _recalculateSuggestedMonthlyPayment();
          });
        },
      ),
    );
  }

  void _deleteItem(String id) {
    setState(() {
      _items.removeWhere((i) => i.id == id);
      _recalculateSuggestedMonthlyPayment();
    });
  }

  // ─── Submit ─────────────────────────────────────────────────────────────

  Future<void> _pickIssuedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _issuedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _issuedDate = picked);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);

    if (_selectedFarmer == null) {
      _showSnack(l10n.issueLoanErrorNoFarmer, isError: true);
      return;
    }
    if (_items.isEmpty) {
      _showSnack(l10n.issueLoanErrorNoItems, isError: true);
      return;
    }
    final monthlyPayment =
        double.tryParse(_monthlyPaymentController.text.trim()) ?? 0;
    if (monthlyPayment <= 0) {
      _showSnack(l10n.issueLoanErrorInvalidMonthly, isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    final nextPaymentDate = _nextBodSaturday();
    final items = _items
        .map(
          (i) => {
            'itemName': i.itemName,
            'quantity': i.quantity,
            'unit': i.unit,
            'unitPrice': i.unitPrice,
            'lineTotal': i.lineTotal,
          },
        )
        .toList();

    try {
      if (_isOnline) {
        final result = await _repo.issueLoan(
          farmerId: _selectedFarmer!.id,
          items: items,
          issuedDate: _issuedDate,
          monthlyPayment: monthlyPayment,
          nextPaymentDate: nextPaymentDate,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
        if (!mounted) return;
        _showSnack(l10n.issueLoanSuccess(result.referenceNo));
        context.pop(true);
      } else {
        await HiveService.savePendingLoanIssuance({
          'farmerId': _selectedFarmer!.id,
          'items': items,
          'issuedDate': _issuedDate.toIso8601String(),
          'monthlyPayment': monthlyPayment,
          'nextPaymentDate': nextPaymentDate.toIso8601String(),
          'notes': _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        });
        if (!mounted) return;
        _showSnack(l10n.issueLoanQueuedOffline);
        context.pop(true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showSnack(l10n.issueLoanErrorGeneric, isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: isError
            ? AppConstants.errorRed
            : AppConstants.successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

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
            child: _isLoadingRoster
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.spacingSafeH,
                      AppConstants.spacingGutter,
                      AppConstants.spacingSafeH,
                      100,
                    ),
                    children: [
                      _buildFarmerSection(context, l10n, cs, sagana),
                      const SizedBox(height: AppConstants.spacingSectionV),
                      _buildItemsSection(context, l10n, cs, sagana),
                      const SizedBox(height: AppConstants.spacingSectionV),
                      _buildTotalCard(context, l10n, cs),
                      const SizedBox(height: AppConstants.spacingSectionV),
                      _buildPaymentScheduleSection(context, l10n, cs, sagana),
                      const SizedBox(height: AppConstants.spacingSectionV),
                      _buildNotesSection(context, l10n, cs, sagana),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context, l10n),
    );
  }

  // ─── Top bar ────────────────────────────────────────────────────────────

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
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingSm,
          ),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  l10n.issueLoanTitle,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Farmer section ─────────────────────────────────────────────────────

  Widget _buildFarmerSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.issueLoanSelectFarmer,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        GestureDetector(
          onTap: () => _openFarmerPicker(context, l10n, cs, sagana),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            decoration: BoxDecoration(
              color: sagana.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppConstants.primaryContainer,
                  child: Icon(
                    _selectedFarmer == null
                        ? Icons.person_search_rounded
                        : Icons.person_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingMd),
                Expanded(
                  child: _selectedFarmer == null
                      ? Text(
                          l10n.issueLoanNoFarmerSelected,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedFarmer!.fullName,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              _selectedFarmer!.memberId,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
        if (_selectedFarmer != null) ...[
          const SizedBox(height: AppConstants.spacingSm),
          _buildStandingBanner(context, l10n, cs),
        ],
      ],
    );
  }

  Widget _buildStandingBanner(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    if (!_isOnline || !_standingCheckedOnline) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Text(
          l10n.issueLoanStandingUnavailableOffline,
          style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      );
    }

    final standing = _farmerStanding;
    if (standing == null) return const SizedBox.shrink();

    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );
    final color = standing.hasOverdueLoan
        ? AppConstants.errorRed
        : AppConstants.buyerBlue;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            standing.hasOverdueLoan
                ? Icons.warning_amber_rounded
                : Icons.info_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.issueLoanOutstandingBalance}: ${currency.format(standing.outstandingBalance)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                if (standing.hasOverdueLoan)
                  Text(
                    l10n.issueLoanOverdueWarning,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppConstants.errorRed,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openFarmerPicker(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FarmerPickerSheet(
        roster: _farmerRoster,
        l10n: l10n,
        onSelected: (farmer) {
          Navigator.of(context).pop();
          _onFarmerSelected(farmer);
        },
      ),
    );
  }

  // ─── Items section ──────────────────────────────────────────────────────

  Widget _buildItemsSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.issueLoanInputItems,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
            TextButton.icon(
              onPressed: () => _openAddItemSheet(),
              icon: const Icon(
                Icons.add_rounded,
                size: 18,
                color: AppConstants.primaryGreen,
              ),
              label: Text(
                l10n.issueLoanAddItem,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: AppConstants.primaryGreen,
                ),
              ),
            ),
          ],
        ),
        if (_items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spacingGutter),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Text(
              l10n.issueLoanNoItemsYet,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          ..._items.map(
            (item) => _buildItemRow(context, item, l10n, cs, sagana),
          ),
      ],
    );
  }

  Widget _buildItemRow(
    BuildContext context,
    _LoanItemDraft item,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    final qtyLabel = item.quantity % 1 == 0
        ? item.quantity.toStringAsFixed(0)
        : item.quantity.toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(top: AppConstants.spacingMd),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  '$qtyLabel ${item.unit} × ${currency.format(item.unitPrice)}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            currency.format(item.lineTotal),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: cs.onSurface,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: cs.onSurfaceVariant,
            onPressed: () => _openAddItemSheet(existing: item),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            color: AppConstants.errorRed,
            onPressed: () => _deleteItem(item.id),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        gradient: AppConstants.primaryButtonGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l10n.issueLoanTotalValue,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.white,
            ),
          ),
          Text(
            currency.format(_totalValue),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Payment schedule section ───────────────────────────────────────────

  Widget _buildPaymentScheduleSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final nextPayment = _nextBodSaturday();
    if (_monthlyPaymentController.text.isEmpty &&
        !_monthlyPaymentManuallyEdited) {
      _monthlyPaymentController.text = _suggestedMonthlyPayment.toStringAsFixed(
        0,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.issueLoanPaymentSchedule,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          GestureDetector(
            onTap: _pickIssuedDate,
            child: _fieldRow(
              label: l10n.issueLoanIssuedDate,
              value: DateFormat('MMMM d, yyyy').format(_issuedDate),
              cs: cs,
              trailing: Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: AppConstants.spacingSectionV),
          Text(
            l10n.issueLoanMonthlyPayment,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _monthlyPaymentController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) =>
                setState(() => _monthlyPaymentManuallyEdited = true),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: cs.onSurface,
            ),
            decoration: InputDecoration(
              prefixText: '₱ ',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          _fieldRow(
            label: l10n.issueLoanNextPaymentDue,
            value: DateFormat('MMMM d, yyyy').format(nextPayment),
            cs: cs,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.issueLoanFrequency,
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          Text(
            l10n.issueLoanVenue,
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow({
    required String label,
    required String value,
    required ColorScheme cs,
    Widget? trailing,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        Row(
          children: [
            Text(
              value,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: cs.onSurface,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing],
          ],
        ),
      ],
    );
  }

  // ─── Notes section ──────────────────────────────────────────────────────

  Widget _buildNotesSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.issueLoanNotes,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        TextField(
          controller: _notesController,
          maxLines: 3,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
          decoration: InputDecoration(
            filled: true,
            fillColor: sagana.cardBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Bottom bar ─────────────────────────────────────────────────────────

  Widget _buildBottomBar(BuildContext context, AppLocalizations l10n) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).padding.bottom + 12,
          ),
          decoration: BoxDecoration(
            color: context.saganaColors.glassBackground,
            border: Border(
              top: BorderSide(color: context.saganaColors.glassBorder),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      l10n.issueLoanSubmit,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Local draft model (form state only, not persisted directly) ──────────

class _LoanItemDraft {
  final String id;
  String itemName;
  double quantity;
  String unit;
  double unitPrice;

  _LoanItemDraft({
    required this.id,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
  });

  double get lineTotal => quantity * unitPrice;
}

// ─── Farmer picker bottom sheet ─────────────────────────────────────────────

class _FarmerPickerSheet extends StatefulWidget {
  final List<FarmerPickerResult> roster;
  final AppLocalizations l10n;
  final ValueChanged<FarmerPickerResult> onSelected;

  const _FarmerPickerSheet({
    required this.roster,
    required this.l10n,
    required this.onSelected,
  });

  @override
  State<_FarmerPickerSheet> createState() => _FarmerPickerSheetState();
}

class _FarmerPickerSheetState extends State<_FarmerPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final filtered = _query.isEmpty
        ? widget.roster
        : widget.roster
              .where(
                (f) =>
                    f.fullName.toLowerCase().contains(_query.toLowerCase()) ||
                    f.memberId.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.l10n.issueLoanSelectFarmer,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: AppConstants.spacingMd),
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: widget.l10n.issueLoanSearchFarmerHint,
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingMd),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        widget.l10n.issueLoanNoItemsYet,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final farmer = filtered[index];
                        return Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppConstants.primaryContainer,
                              child: Text(
                                farmer.fullName.isNotEmpty
                                    ? farmer.fullName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(
                              farmer.fullName,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              farmer.memberId,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            onTap: () => widget.onSelected(farmer),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add / Edit Input Item bottom sheet ─────────────────────────────────────

class _AddLoanItemSheet extends StatefulWidget {
  final _LoanItemDraft? existing;
  final ValueChanged<_LoanItemDraft> onSave;

  const _AddLoanItemSheet({this.existing, required this.onSave});

  @override
  State<_AddLoanItemSheet> createState() => _AddLoanItemSheetState();
}

class _AddLoanItemSheetState extends State<_AddLoanItemSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _qtyController;
  late final TextEditingController _priceController;
  late String _unit;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existing?.itemName ?? '',
    );
    _qtyController = TextEditingController(
      text: widget.existing != null
          ? (widget.existing!.quantity % 1 == 0
                ? widget.existing!.quantity.toStringAsFixed(0)
                : widget.existing!.quantity.toString())
          : '',
    );
    _priceController = TextEditingController(
      text: widget.existing != null
          ? widget.existing!.unitPrice.toStringAsFixed(2)
          : '',
    );
    _unit = widget.existing?.unit ?? AppConstants.loanItemUnits.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  double get _quantity => double.tryParse(_qtyController.text.trim()) ?? 0;
  double get _unitPrice => double.tryParse(_priceController.text.trim()) ?? 0;
  double get _lineTotal => _quantity * _unitPrice;

  void _confirm() {
    final l10n = AppLocalizations.of(context);
    if (_nameController.text.trim().isEmpty ||
        _quantity <= 0 ||
        _unitPrice < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.issueLoanErrorGeneric,
            style: GoogleFonts.inter(fontSize: 13),
          ),
          backgroundColor: AppConstants.errorRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    widget.onSave(
      _LoanItemDraft(
        id:
            widget.existing?.id ??
            'item_${DateTime.now().millisecondsSinceEpoch}',
        itemName: _nameController.text.trim(),
        quantity: _quantity,
        unit: _unit,
        unitPrice: _unitPrice,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    return Container(
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.issueLoanAddItem,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: AppConstants.spacingMd),
            Wrap(
              spacing: 8,
              children: AppConstants.loanInputCategories
                  .map(
                    (c) => ActionChip(
                      label: Text(c, style: GoogleFonts.inter(fontSize: 12)),
                      onPressed: () => setState(() => _nameController.text = c),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppConstants.spacingMd),
            Text(
              l10n.issueLoanItemName,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingMd),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.issueLoanQuantity,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _qtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusSm,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppConstants.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.issueLoanUnit,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _unit,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusSm,
                            ),
                          ),
                        ),
                        items: AppConstants.loanItemUnits
                            .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _unit = v ?? _unit),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingMd),
            Text(
              l10n.issueLoanUnitPrice,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixText: '₱ ',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingMd),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.issueLoanLineTotal,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  currency.format(_lineTotal),
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingSectionV),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.issueLoanCancel),
                  ),
                ),
                const SizedBox(width: AppConstants.spacingMd),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryGreen,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(l10n.issueLoanConfirmItem),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
