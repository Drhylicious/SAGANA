import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../widgets/animated_pressable.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/shared_widgets.dart';

/// Record Payment — BOD Meeting Mode.
/// Pushed above the shell (has a back button). Route: /admin/loans/payment
///
/// Two entry modes:
///  - No loanId (Dashboard quick action / BOD banner): search step first.
///  - loanId provided (a loan card's pay icon, or Loan Details): skips
///    straight to the payment form for that loan.
///
/// Offline behavior: farmer roster and the full active/overdue loan list
/// are cached to Hive whenever this screen loads online, and used as a
/// fallback when offline, so the admin can still look up a farmer and their
/// balance during a signal-less BOD meeting. A payment made offline is
/// queued and synced automatically once connectivity returns.
class RecordPaymentScreen extends StatefulWidget {
  final String? loanId;

  const RecordPaymentScreen({super.key, this.loanId});

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  final _repo = AdminLoanRepository();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();

  bool _isOnline = true;
  bool _isLoadingData = true;
  bool _isSubmitting = false;
  bool _directLoanMode = false;

  List<FarmerPickerResult> _farmerRoster = [];
  List<AdminLoanSummary> _allActiveLoans = [];
  String _searchQuery = '';

  FarmerPickerResult? _selectedFarmer;
  List<AdminLoanSummary> _farmerLoans = [];
  AdminLoanSummary? _selectedLoan;

  DateTime _paymentDate = DateTime.now();
  final List<_SessionPaymentEntry> _sessionPayments = [];

  @override
  void initState() {
    super.initState();
    _directLoanMode = widget.loanId != null;
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ─── Data loading ───────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    setState(() => _isLoadingData = true);
    await Future.wait([_loadFarmerRoster(), _loadActiveLoans()]);

    if (_directLoanMode) {
      await _resolveDirectLoan();
    }

    if (!mounted) return;
    setState(() => _isLoadingData = false);
  }

  Future<void> _loadFarmerRoster() async {
    if (_isOnline) {
      final roster = await _repo.fetchFarmerRoster();
      if (roster.isNotEmpty) {
        await HiveService.cacheFarmerRoster(roster.map((f) => f.toMap()).toList());
        if (mounted) setState(() => _farmerRoster = roster);
        return;
      }
    }
    final cached = HiveService.getCachedFarmerRoster();
    if (mounted) {
      setState(() => _farmerRoster = cached.map(FarmerPickerResult.fromMap).toList());
    }
  }

  Future<void> _loadActiveLoans() async {
    if (_isOnline) {
      final loans = await _repo.fetchAllActiveAndOverdueLoans();
      if (loans.isNotEmpty) {
        await HiveService.cacheActiveLoans(loans.map((l) => l.toCacheMap()).toList());
        if (mounted) setState(() => _allActiveLoans = loans);
        return;
      }
    }
    final cached = HiveService.getCachedActiveLoans();
    if (mounted) {
      setState(() => _allActiveLoans = cached.map(AdminLoanSummary.fromCacheMap).toList());
    }
  }

  /// The active-member roster, plus any farmer who no longer qualifies as
  /// active but still has a real, outstanding loan on record (Admin-Loan
  /// Issue 1.3). fetchFarmerRoster() only returns active members, which is
  /// correct for who a NEW loan can be issued to — but an existing debt
  /// must stay collectible even if the borrower's status changed after
  /// issuance, so anyone appearing in _allActiveLoans is always searchable
  /// here regardless of their current membership status. This also keeps a
  /// rejected/draft/suspended non-member (who was never issued a loan) out
  /// of the payment-recording directory entirely, instead of merely
  /// greyed-out the way the full unfiltered roster used to leave them.
  List<FarmerPickerResult> get _searchableFarmers {
    final byId = {for (final f in _farmerRoster) f.id: f};
    for (final loan in _allActiveLoans) {
      byId.putIfAbsent(
        loan.farmerId,
        () => FarmerPickerResult(
          id: loan.farmerId,
          fullName: loan.farmerName,
          memberId: loan.memberId,
        ),
      );
    }
    return byId.values.toList();
  }

  double _defaultAmountFor(AdminLoanSummary loan) =>
      loan.monthlyPayment > loan.remainingBalance
          ? loan.remainingBalance
          : loan.monthlyPayment;

  Future<void> _resolveDirectLoan() async {
    AdminLoanSummary? loan;
    if (_isOnline) {
      loan = await _repo.fetchLoanSummaryById(widget.loanId!);
    }
    loan ??= _allActiveLoans.where((l) => l.id == widget.loanId).firstOrNull;

    if (loan == null) return;

    final farmer = _farmerRoster.where((f) => f.id == loan!.farmerId).firstOrNull ??
        FarmerPickerResult(id: loan.farmerId, fullName: loan.farmerName, memberId: loan.memberId);

    setState(() {
      _selectedFarmer = farmer;
      _farmerLoans = [loan!];
      _selectedLoan = loan;
      _amountController.text = _defaultAmountFor(loan).toStringAsFixed(0);
    });
  }

  // ─── Farmer / loan selection ────────────────────────────────────────────

  void _selectFarmer(FarmerPickerResult farmer) {
    final loans = _allActiveLoans.where((l) => l.farmerId == farmer.id).toList();
    setState(() {
      _selectedFarmer = farmer;
      _farmerLoans = loans;
      _selectedLoan = loans.length == 1 ? loans.first : null;
      if (_selectedLoan != null) {
        _amountController.text = _defaultAmountFor(_selectedLoan!).toStringAsFixed(0);
      }
    });
  }

  void _selectLoan(AdminLoanSummary loan) {
    setState(() {
      _selectedLoan = loan;
      _amountController.text = _defaultAmountFor(loan).toStringAsFixed(0);
    });
  }

  // ─── Back navigation ────────────────────────────────────────────────────
  //
  // Admin-Loan Issue 1.4/1.5: the screen used to only ever exit outright
  // (context.pop()) from the top-bar back button, with a separate "Switch
  // Farmer" button as the only way back to search — and no way at all back
  // to the loan list once a specific loan was selected. This makes the
  // back button step back one level within the flow instead, so a single
  // control handles all "go back" cases:
  //   payment form (reached via a multi-loan selector) -> loan selector
  //   payment form (farmer had exactly one loan, no selector shown),
  //   loan selector, or the empty-loans state                -> search
  //   search, or direct-loan mode (opened for one specific loan) -> exit

  /// Whether the back button (top bar or system back gesture) should just
  /// exit the screen — true only when there is no internal step left to
  /// unwind.
  bool get _backExitsScreen => _directLoanMode || _selectedFarmer == null;

  void _handleBack() {
    if (_backExitsScreen) {
      context.pop();
      return;
    }
    if (_selectedLoan != null && _farmerLoans.length > 1) {
      // A real loan-selector step was shown for this farmer — step back to
      // it rather than all the way to search.
      setState(() => _selectedLoan = null);
      return;
    }
    // Loan selector, empty-loans state, or a payment form reached with no
    // selector step (the farmer only had one loan) — one level up is search.
    _resetForNextFarmer();
  }

  void _resetForNextFarmer() {
    setState(() {
      _selectedFarmer = null;
      _farmerLoans = [];
      _selectedLoan = null;
      _amountController.clear();
      _notesController.clear();
      _searchController.clear();
      _searchQuery = '';
      _paymentDate = DateTime.now();
    });
    _loadActiveLoans(); // refresh balances for the next lookup
  }

  double _outstandingFor(FarmerPickerResult farmer) {
    return _allActiveLoans
        .where((l) => l.farmerId == farmer.id)
        .fold<double>(0, (sum, l) => sum + l.remainingBalance);
  }

  // ─── Submit ─────────────────────────────────────────────────────────────

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _paymentDate = picked);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final loan = _selectedLoan;
    final farmer = _selectedFarmer;

    if (farmer == null || loan == null) return;

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      _showSnack(l10n.paymentErrorInvalidAmount, isError: true);
      return;
    }

    // Payments never record more than what's actually owed — the excess is
    // change the admin hands back at the BOD meeting, not additional debt
    // reduction. Confirming the dialog acknowledges the overpayment; it does
    // not change what gets written to farmer_loans.amount_paid.
    var recordedAmount = amount;
    if (amount > loan.remainingBalance) {
      final confirmed = await AppDialog.show<bool>(
        context: context,
        child: _OverpaymentDialog(
          amount: amount,
          remainingBalance: loan.remainingBalance,
          l10n: l10n,
        ),
      );
      if (confirmed != true) return;
      recordedAmount = loan.remainingBalance;
    }

    setState(() => _isSubmitting = true);
    final notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();

    try {
      if (_isOnline) {
        final result = await _repo.recordPayment(
          loanId: loan.id,
          amount: recordedAmount,
          paymentDate: _paymentDate,
          notes: notes,
        );
        _onPaymentRecorded(
          farmer,
          recordedAmount,
          loan,
          synced: true,
          confirmedFullyPaid: result.isFullyPaid,
        );
      } else {
        await HiveService.savePendingLoanPayment({
          'loanId': loan.id,
          'amount': recordedAmount,
          'paymentDate': _paymentDate.toIso8601String(),
          'notes': notes,
        });
        _onPaymentRecorded(farmer, recordedAmount, loan, synced: false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showSnack(l10n.paymentErrorGeneric, isError: true);
    }
  }

  void _onPaymentRecorded(
    FarmerPickerResult farmer,
    double amount,
    AdminLoanSummary loan, {
    required bool synced,
    bool? confirmedFullyPaid,
  }) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    // Online payments get the RPC's authoritative is_fully_paid. Offline-
    // queued payments have no server round-trip yet at this point, so
    // this stays an estimate against the last-known cached balance until
    // sync confirms it — same limitation as before, now scoped to only
    // the offline case instead of both.
    final fullyPaid = confirmedFullyPaid ?? (amount >= loan.remainingBalance);

    setState(() {
      _isSubmitting = false;
      _sessionPayments.insert(
        0,
        _SessionPaymentEntry(
          farmerName: farmer.fullName,
          amount: amount,
          referenceNo: loan.referenceNo,
          fullyPaid: fullyPaid,
          synced: synced,
        ),
      );
    });

    _showSnack(synced ? l10n.paymentSuccess(farmer.fullName) : l10n.paymentQueuedOffline);

    if (_directLoanMode) {
      context.pop(true);
    } else {
      _resetForNextFarmer();
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: isError ? AppConstants.errorRed : AppConstants.successGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
    ));
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return PopScope(
      canPop: _backExitsScreen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          children: [
            _buildTopBar(context, l10n, cs),
            if (!_isOnline) const OfflineBanner(),
            Expanded(
              child: _isLoadingData
                  ? const Center(child: CircularProgressIndicator())
                  : _selectedFarmer == null
                      ? _buildSearchStep(context, l10n, cs, sagana)
                      : _buildPaymentStep(context, l10n, cs, sagana),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    final sagana = context.saganaColors;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSm),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: _handleBack,
              ),
              Expanded(
                child: Text(
                  _selectedFarmer != null
                      ? l10n.paymentContextualTitle(_selectedFarmer!.fullName)
                      : l10n.paymentTitle,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: cs.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Search step ────────────────────────────────────────────────────────

  Widget _buildSearchStep(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final roster = _searchableFarmers;
    final filtered = _searchQuery.isEmpty
        ? roster
        : roster
            .where((f) =>
                f.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                f.memberId.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spacingSafeH,
            AppConstants.spacingGutter,
            AppConstants.spacingSafeH,
            AppConstants.spacingSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.issueLoanSelectFarmer,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface),
              ),
              const SizedBox(height: AppConstants.spacingSm),
              _buildSearchField(context, l10n, cs),
            ],
          ),
        ),
        if (_sessionPayments.isNotEmpty) _buildSessionSummary(context, l10n, cs, sagana),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    l10n.paymentNoFarmersFound,
                    style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.spacingSafeH,
                    0,
                    AppConstants.spacingSafeH,
                    24,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final farmer = filtered[index];
                    final outstanding = _outstandingFor(farmer);
                    final hasActiveLoans = outstanding > 0;

                    final row = Container(
                      padding: const EdgeInsets.all(AppConstants.spacingMd),
                      decoration: BoxDecoration(
                        color: sagana.cardBackground,
                        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
                      ),
                      child: Opacity(
                        opacity: hasActiveLoans ? 1.0 : 0.55,
                        child: Row(
                          children: [
                            ProfileAvatar(
                              photoUrl: farmer.profilePhotoUrl,
                              displayName: farmer.fullName,
                              radius: 18,
                            ),
                            const SizedBox(width: AppConstants.spacingMd),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    farmer.fullName,
                                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface),
                                  ),
                                  Text(
                                    farmer.memberId,
                                    style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            hasActiveLoans
                                ? Text(
                                    currency.format(outstanding),
                                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: AppConstants.primaryGreen),
                                  )
                                : Text(
                                    l10n.paymentNoActiveLoans,
                                    style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                                  ),
                          ],
                        ),
                      ),
                    );

                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
                      child: hasActiveLoans
                          ? AnimatedPressable(onTap: () => _selectFarmer(farmer), child: row)
                          : row,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    return TextField(
      controller: _searchController,
      autofocus: true,
      onChanged: (v) => setState(() => _searchQuery = v),
      decoration: InputDecoration(
        hintText: l10n.paymentSearchHint,
        hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
        prefixIcon: Icon(Icons.search_rounded, color: cs.outline, size: 22),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.close_rounded, color: cs.outline, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
      ),
      style: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
    );
  }

  Widget _buildSessionSummary(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final total = _sessionPayments.fold<double>(0, (sum, p) => sum + p.amount);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppConstants.spacingSafeH,
        0,
        AppConstants.spacingSafeH,
        AppConstants.spacingSm,
      ),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: AppConstants.successGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppConstants.successGreen.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.paymentSessionSummary(_sessionPayments.length, currency.format(total)),
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12, color: AppConstants.successGreen),
          ),
          const SizedBox(height: 4),
          ..._sessionPayments.take(3).map((p) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      p.fullyPaid ? Icons.celebration_rounded : Icons.check_circle_outline_rounded,
                      size: 14,
                      color: AppConstants.successGreen,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${p.farmerName} — ${currency.format(p.amount)}${p.synced ? '' : ' (${l10n.paymentQueuedTag})'}',
                        style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ─── Payment step ───────────────────────────────────────────────────────

  Widget _buildPaymentStep(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingSafeH,
        AppConstants.spacingGutter,
        AppConstants.spacingSafeH,
        AppConstants.spacingSafeH,
      ),
      children: [
        _buildFarmerCard(context, l10n, cs, sagana),
        const SizedBox(height: AppConstants.spacingSectionV),
        if (_farmerLoans.isEmpty)
          _buildEmptyLoansState(context, l10n, cs)
        else if (_farmerLoans.length > 1 && _selectedLoan == null)
          _buildLoanSelector(context, l10n, cs, sagana)
        else if (_selectedLoan != null)
          _buildPaymentForm(context, l10n, cs, sagana),
      ],
    );
  }

  Widget _buildFarmerCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final farmer = _selectedFarmer!;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
      ),
      child: Row(
        children: [
          ProfileAvatar(
            photoUrl: farmer.profilePhotoUrl,
            displayName: farmer.fullName,
            radius: 22,
          ),
          const SizedBox(width: AppConstants.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  farmer.fullName,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface),
                ),
                Text(
                  farmer.memberId,
                  style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyLoansState(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        children: [
          Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant, size: 22),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            l10n.paymentNoActiveLoans,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildLoanSelector(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.paymentSelectLoan,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        ..._farmerLoans.map((loan) => Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
              child: AnimatedPressable(
                onTap: () => _selectLoan(loan),
                child: Container(
                  padding: const EdgeInsets.all(AppConstants.spacingMd),
                  decoration: BoxDecoration(
                    color: sagana.cardBackground,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    border: Border.all(
                      color: loan.isOverdue ? AppConstants.errorRed.withValues(alpha: 0.4) : cs.outline.withValues(alpha: 0.10),
                    ),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loan.referenceNo,
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface),
                            ),
                            Text(
                              '${l10n.loanDashBalance}: ${currency.format(loan.remainingBalance)}',
                              style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (loan.isOverdue)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppConstants.errorRed.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                          ),
                          child: Text(
                            'OVERDUE',
                            style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: AppConstants.errorRed),
                          ),
                        ),
                      const SizedBox(width: AppConstants.spacingSm),
                      Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildPaymentForm(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final loan = _selectedLoan!;
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final remainingAfter = (loan.remainingBalance - amount).clamp(0, double.infinity);
    final isOverpayment = amount > loan.remainingBalance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppConstants.spacingGutter),
          decoration: BoxDecoration(
            gradient: AppConstants.primaryButtonGradient,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(loan.referenceNo, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                  if (loan.isOverdue)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(AppConstants.radiusFull)),
                      child: Text('OVERDUE', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${l10n.loanDashBalance}: ${currency.format(loan.remainingBalance)}',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingSectionV),
        Container(
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
                l10n.paymentDetailsSectionTitle,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface),
              ),
              const SizedBox(height: AppConstants.spacingMd),
              Text(l10n.paymentAmountReceived, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 22, color: cs.onSurface),
                decoration: const InputDecoration(prefixText: '₱ '),
              ),
              if (isOverpayment) ...[
                const SizedBox(height: AppConstants.spacingSm),
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: AppConstants.warningAmber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.paymentOverpaymentNotice,
                        style: GoogleFonts.inter(fontSize: 11, color: AppConstants.warningAmber),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppConstants.spacingMd),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.paymentRemainingAfter, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
                  Text(
                    currency.format(remainingAfter),
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface),
                  ),
                ],
              ),
              Divider(height: AppConstants.spacingSectionV * 1.5, color: cs.outline.withValues(alpha: 0.10)),
              GestureDetector(
                onTap: _pickPaymentDate,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.paymentDate, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
                    Row(
                      children: [
                        Text(
                          DateFormat('MMMM d, yyyy').format(_paymentDate),
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.calendar_today_rounded, size: 14, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingSectionV),
        Text(l10n.paymentNotes, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        TextField(
          controller: _notesController,
          maxLines: 2,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
          decoration: InputDecoration(
            filled: true,
            fillColor: sagana.cardBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
          ),
        ),
        const SizedBox(height: AppConstants.spacingSectionV),
        PrimaryButton(
          label: amount > 0
              ? l10n.paymentSubmitWithAmount(currency.format(amount))
              : l10n.paymentSubmit,
          isLoading: _isSubmitting,
          onPressed: amount > 0 ? _submit : null,
        ),
      ],
    );
  }
}

// ─── Session summary entry (in-memory only, not persisted) ─────────────────

class _SessionPaymentEntry {
  final String farmerName;
  final double amount;
  final String referenceNo;
  final bool fullyPaid;
  final bool synced;

  const _SessionPaymentEntry({
    required this.farmerName,
    required this.amount,
    required this.referenceNo,
    required this.fullyPaid,
    required this.synced,
  });
}

// ─── Overpayment confirmation dialog ────────────────────────────────────────

class _OverpaymentDialog extends StatelessWidget {
  final double amount;
  final double remainingBalance;
  final AppLocalizations l10n;

  const _OverpaymentDialog({
    required this.amount,
    required this.remainingBalance,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
    final excess = amount - remainingBalance;

    return AlertDialog(
      title: Text(l10n.paymentOverpaymentTitle, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
      content: Text(
        l10n.paymentOverpaymentMessage(currency.format(excess)),
        style: GoogleFonts.inter(fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.issueLoanCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.paymentOverpaymentConfirm, style: const TextStyle(color: AppConstants.primaryGreen)),
        ),
      ],
    );
  }
}