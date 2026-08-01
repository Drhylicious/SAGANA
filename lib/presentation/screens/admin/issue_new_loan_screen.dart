import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/bod_schedule_utils.dart';
import '../../../data/models/admin_loan_model.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/material_list_tile.dart';

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
  List<LoanCatalogItem> _loanCatalog = [];

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadFarmerRoster();
    _repo.fetchLoanEligibleItems().then((v) {
      if (mounted) setState(() => _loanCatalog = v);
    });
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

  void _recalculateSuggestedMonthlyPayment() {
    if (_monthlyPaymentManuallyEdited) return;
    _monthlyPaymentController.text = _suggestedMonthlyPayment.toStringAsFixed(
      0,
    );
  }

  // ─── Item CRUD ──────────────────────────────────────────────────────────

  void _openAddItemSheet({_LoanItemDraft? existing}) {
    showManagementModal(
      context: context,
      builder: (_) => _AddLoanItemModalBody(
        existing: existing,
        loanCatalog: _loanCatalog,
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

    final nextPaymentDate = BodSchedule.upcoming();
    final items = _items
        .map(
          (i) => {
            'itemName': i.itemName,
            'inventoryItemId': i.inventoryItemId,
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
    showManagementModal(
      context: context,
      builder: (_) => _FarmerPickerModalBody(
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
    final nextPayment = BodSchedule.upcoming();
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
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
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
  final String? inventoryItemId;
  String itemName;
  double quantity;
  String unit;
  double unitPrice;

  _LoanItemDraft({
    required this.id,
    this.inventoryItemId,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
  });

  double get lineTotal => quantity * unitPrice;
}

// ─── Farmer picker modal ────────────────────────────────────────────────────

class _FarmerPickerModalBody extends StatefulWidget {
  final List<FarmerPickerResult> roster;
  final AppLocalizations l10n;
  final ValueChanged<FarmerPickerResult> onSelected;

  const _FarmerPickerModalBody({
    required this.roster,
    required this.l10n,
    required this.onSelected,
  });

  @override
  State<_FarmerPickerModalBody> createState() => _FarmerPickerModalBodyState();
}

class _FarmerPickerModalBodyState extends State<_FarmerPickerModalBody> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _query.isEmpty
        ? widget.roster
        : widget.roster
              .where(
                (f) =>
                    f.fullName.toLowerCase().contains(_query.toLowerCase()) ||
                    f.memberId.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();

    return ManagementModalShell(
      title: widget.l10n.issueLoanSelectFarmer,
      bodyIsScrollable: true,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: TextField(
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
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      widget.l10n.issueLoanNoFarmerResults,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final farmer = filtered[index];
                      return MaterialListTile(
                        contentPadding: EdgeInsets.zero,
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
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Add / Edit Input Item modal ────────────────────────────────────────────
//
// Catalog-only design: items are selected from the loan-eligible inventory
// catalog (published via Inventory Management), never typed in freehand.
// This keeps itemName/unit/unitPrice always in sync with cooperative_inventory
// and lets us show live stock-on-hand + an insufficient-stock warning.

class _AddLoanItemModalBody extends StatefulWidget {
  final _LoanItemDraft? existing;
  final List<LoanCatalogItem> loanCatalog;
  final ValueChanged<_LoanItemDraft> onSave;

  const _AddLoanItemModalBody({
    this.existing,
    required this.loanCatalog,
    required this.onSave,
  });

  @override
  State<_AddLoanItemModalBody> createState() => _AddLoanItemModalBodyState();
}

class _AddLoanItemModalBodyState extends State<_AddLoanItemModalBody> {
  LoanCatalogItem? _selected;
  late final TextEditingController _qtyController;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(
      text: widget.existing != null
          ? (widget.existing!.quantity % 1 == 0
                ? widget.existing!.quantity.toStringAsFixed(0)
                : widget.existing!.quantity.toString())
          : '',
    );
    // When editing an existing line item, pre-select the matching catalog
    // entry (if it's still in the catalog — it may have been unpublished).
    if (widget.existing?.inventoryItemId != null) {
      for (final item in widget.loanCatalog) {
        if (item.inventoryItemId == widget.existing!.inventoryItemId) {
          _selected = item;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  double get _quantity => double.tryParse(_qtyController.text.trim()) ?? 0;
  bool get _insufficientStock =>
      _selected != null && _quantity > _selected!.quantityOnHand;

  void _confirm() {
    if (_selected == null || _quantity <= 0) return;
    widget.onSave(
      _LoanItemDraft(
        id:
            widget.existing?.id ??
            'item_${DateTime.now().millisecondsSinceEpoch}',
        inventoryItemId: _selected!.inventoryItemId,
        itemName: _selected!.itemName,
        quantity: _quantity,
        unit: _selected!.unit,
        unitPrice: _selected!.unitPrice,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    // Empty-catalog state — no loanable items exist yet. Without this, the
    // dropdown below would just sit there empty with no explanation.
    if (widget.loanCatalog.isEmpty) {
      return ManagementModalShell(
        title: l10n.issueLoanAddItem,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 40,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No loanable items yet',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Publish an item from Inventory Management before it can be selected here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        footer: ManagementModalActions(
          cancelLabel: 'Close',
          primaryLabel: 'Go to Inventory',
          onPrimary: () {
            Navigator.of(context).pop();
            context.push(AppRoutes.adminInventory);
          },
        ),
      );
    }

    return ManagementModalShell(
      title: l10n.issueLoanAddItem,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.issueLoanSelectItem,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<LoanCatalogItem>(
            initialValue: _selected,
            isExpanded: true,
            hint: const Text('Select a loanable item'),
            items: widget.loanCatalog
                .map(
                  (c) => DropdownMenuItem(
                    value: c,
                    child: Text('${c.itemName} (${c.unit})'),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selected = v),
          ),
          if (_selected != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.issueLoanUnitPrice,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  currency.format(_selected!.unitPrice),
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Available in stock',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${_selected!.quantityOnHand.toStringAsFixed(0)} ${_selected!.unit}',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qtyController,
              decoration: InputDecoration(
                labelText: l10n.issueLoanQuantity,
                suffixText: _selected!.unit,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              onChanged: (_) => setState(() {}),
            ),
            if (_insufficientStock) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppConstants.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: AppConstants.amber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_quantity.toStringAsFixed(0)} requested — only '
                        '${_selected!.quantityOnHand.toStringAsFixed(0)} ${_selected!.unit} available. '
                        'You can still proceed if the BOD has approved this.',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
      footer: ManagementModalActions(
        primaryLabel: l10n.issueLoanConfirmItem,
        onPrimary: _confirm,
      ),
    );
  }
}