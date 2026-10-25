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
import '../../widgets/account_form_widgets.dart';
import '../../widgets/animated_pressable.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/farmer_pick_tile.dart';
import '../../widgets/loan_choice_chip.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

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
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();

  bool _isOnline = true;
  bool _isLoadingData = true;
  bool _isSubmitting = false;
  bool _directLoanMode = false;

  /// Whether the farmers with no active loan are listed under the ones who owe.
  bool _showNoLoanFarmers = false;

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
        await HiveService.cacheFarmerRoster(
          roster.map((f) => f.toMap()).toList(),
        );
        if (mounted) setState(() => _farmerRoster = roster);
        return;
      }
    }
    final cached = HiveService.getCachedFarmerRoster();
    if (mounted) {
      setState(
        () => _farmerRoster = cached.map(FarmerPickerResult.fromMap).toList(),
      );
    }
  }

  Future<void> _loadActiveLoans() async {
    if (_isOnline) {
      final loans = await _repo.fetchAllActiveAndOverdueLoans();
      if (loans.isNotEmpty) {
        await HiveService.cacheActiveLoans(
          loans.map((l) => l.toCacheMap()).toList(),
        );
        if (mounted) setState(() => _allActiveLoans = loans);
        return;
      }
    }
    final cached = HiveService.getCachedActiveLoans();
    if (mounted) {
      setState(
        () => _allActiveLoans = cached
            .map(AdminLoanSummary.fromCacheMap)
            .toList(),
      );
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
        () => FarmerPickerResult(id: loan.farmerId, fullName: loan.farmerName),
      );
    }
    return byId.values.toList();
  }

  double get _enteredAmount =>
      double.tryParse(_amountController.text.trim()) ?? 0;

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

    final farmer =
        _farmerRoster.where((f) => f.id == loan!.farmerId).firstOrNull ??
        FarmerPickerResult(id: loan.farmerId, fullName: loan.farmerName);

    setState(() {
      _selectedFarmer = farmer;
      _farmerLoans = [loan!];
      _selectedLoan = loan;
      _amountController.text = _defaultAmountFor(loan).toStringAsFixed(0);
    });
  }

  // ─── Farmer / loan selection ────────────────────────────────────────────

  void _selectFarmer(FarmerPickerResult farmer) {
    final loans = _allActiveLoans
        .where((l) => l.farmerId == farmer.id)
        .toList();
    setState(() {
      _selectedFarmer = farmer;
      _farmerLoans = loans;
      _selectedLoan = loans.length == 1 ? loans.first : null;
      if (_selectedLoan != null) {
        _amountController.text = _defaultAmountFor(
          _selectedLoan!,
        ).toStringAsFixed(0);
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

    // The amount field shows its own inline error (paymentErrorInvalidAmount).
    if (!(_formKey.currentState?.validate() ?? true)) return;
    final amount = _enteredAmount;
    if (amount <= 0) return;

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
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    try {
      // Offline, the repository keeps the payment on this device and Sync
      // sends it later (Batch 6). Online, it goes straight to the server.
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
        synced: result.sentToServer,
        confirmedFullyPaid:
            result.sentToServer ? result.isFullyPaid : null,
      );
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

    _showSnack(
      synced ? l10n.paymentSuccess(farmer.fullName) : l10n.paymentQueuedOffline,
    );

    if (_directLoanMode) {
      context.pop(true);
    } else {
      _resetForNextFarmer();
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: isError
            ? AppConstants.errorRed
            : AppConstants.midGreen,
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
            if (!_isOnline) const OfflineStatusCard(),
            Expanded(
              child: _isLoadingData
                  ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                  : _selectedFarmer == null
                      ? _buildSearchStep(context, l10n, cs, sagana)
                      : _buildPaymentStep(context, l10n, cs, sagana),
            ),
          ],
        ),
        // The action sits in the same bottom bar as Issue New Loan and the
        // Manager's account forms; it appears once a loan is chosen.
        bottomNavigationBar: (!_isLoadingData && _selectedLoan != null)
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: PrimaryButton(
                    label: _enteredAmount > 0
                        ? l10n.paymentSubmitWithAmount(
                            NumberFormat.currency(
                              locale: 'en_PH',
                              symbol: '₱',
                              decimalDigits: 2,
                            ).format(_enteredAmount),
                          )
                        : l10n.paymentSubmit,
                    isLoading: _isSubmitting,
                    onPressed: _isSubmitting ? null : _submit,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    // The farmer's name is on the card below; in the title a long name only
    // got cut off.
    return SubPageTopBar(title: l10n.paymentTitle, onBack: _handleBack);
  }

  // ─── Search step ────────────────────────────────────────────────────────

  Widget _buildSearchStep(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    final money = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );

    // Each matching farmer with what they owe. Farmers who owe something come
    // first, overdue ones at the top (they are who the Manager is collecting
    // from), then by the amount; farmers with nothing to pay follow by name.
    final rows = <({FarmerPickerResult farmer, int loans, int overdue, double balance})>[
      for (final f in _searchableFarmers)
        if (query.isEmpty || f.fullName.toLowerCase().contains(query))
          (
            farmer: f,
            loans: _allActiveLoans.where((l) => l.farmerId == f.id).length,
            overdue: _allActiveLoans
                .where((l) => l.farmerId == f.id && l.isOverdue)
                .length,
            balance: _outstandingFor(f),
          ),
    ];
    final owing = rows.where((r) => r.balance > 0).toList()
      ..sort((a, b) {
        if ((a.overdue > 0) != (b.overdue > 0)) return a.overdue > 0 ? -1 : 1;
        final byBalance = b.balance.compareTo(a.balance);
        return byBalance != 0
            ? byBalance
            : a.farmer.fullName.compareTo(b.farmer.fullName);
      });
    final settled = rows.where((r) => r.balance <= 0).toList()
      ..sort((a, b) => a.farmer.fullName.compareTo(b.farmer.fullName));

    // Farmers with no active loan cannot be paid, so they stay folded away
    // until asked for — or until a search names one, so the Manager still
    // learns why that farmer cannot be chosen.
    final showSettled = query.isNotEmpty || owing.isEmpty || _showNoLoanFarmers;

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
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: AppConstants.spacingSm),
              _buildSearchField(context, l10n, cs),
            ],
          ),
        ),
        if (_sessionPayments.isNotEmpty)
          _buildSessionSummary(context, l10n, cs, sagana),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_search_rounded,
                        size: 40,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(height: AppConstants.spacingSm),
                      Text(
                        l10n.paymentNoFarmersFound,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.spacingSafeH,
                    0,
                    AppConstants.spacingSafeH,
                    24,
                  ),
                  children: [
                    for (final r in owing)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppConstants.spacingSm,
                        ),
                        child: FarmerPickTile(
                          name: r.farmer.fullName,
                          photoUrl: r.farmer.profilePhotoUrl,
                          subtitle: [
                            l10n.paymentActiveLoansCount(r.loans),
                            if (r.overdue > 0)
                              l10n.paymentOverdueCount(r.overdue),
                          ].join(' · '),
                          subtitleColor: r.overdue > 0
                              ? AppConstants.errorRed
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                money.format(r.balance),
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: r.overdue > 0
                                      ? AppConstants.errorRed
                                      : AppConstants.primaryGreen,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                          onTap: () => _selectFarmer(r.farmer),
                        ),
                      ),
                    if (settled.isNotEmpty && owing.isNotEmpty && query.isEmpty)
                      InkWell(
                        onTap: () => setState(
                          () => _showNoLoanFarmers = !_showNoLoanFarmers,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.paymentNoLoanFarmersToggle(
                                    settled.length,
                                  ),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Icon(
                                _showNoLoanFarmers
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (showSettled)
                      for (final r in settled)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppConstants.spacingSm,
                          ),
                          child: FarmerPickTile(
                            name: r.farmer.fullName,
                            photoUrl: r.farmer.profilePhotoUrl,
                            subtitle: l10n.paymentNoActiveLoans,
                            dimmed: true,
                          ),
                        ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSearchField(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
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
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );
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
        border: Border.all(
          color: AppConstants.successGreen.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.paymentSessionSummary(
              _sessionPayments.length,
              currency.format(total),
            ),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: AppConstants.successGreen,
            ),
          ),
          const SizedBox(height: 4),
          ..._sessionPayments
              .take(3)
              .map(
                (p) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                        p.fullyPaid
                            ? Icons.celebration_rounded
                            : Icons.check_circle_outline_rounded,
                      size: 14,
                      color: AppConstants.successGreen,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${p.farmerName} — ${currency.format(p.amount)}${p.synced ? '' : ' (${l10n.paymentQueuedTag})'}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        overflow: TextOverflow.ellipsis,
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

  // ─── Payment step ───────────────────────────────────────────────────────

  Widget _buildPaymentStep(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingSafeH,
          AppConstants.spacingGutter,
          AppConstants.spacingSafeH,
          AppConstants.spacingSectionV,
        ),
        children: [
          _buildFarmerCard(context, l10n, cs, sagana),
          const SizedBox(height: AppConstants.spacingGutter),
          if (_farmerLoans.isEmpty)
            _buildEmptyLoansState(context, l10n, cs)
          else if (_farmerLoans.length > 1 && _selectedLoan == null)
            _buildLoanSelector(context, l10n, cs, sagana)
          else if (_selectedLoan != null)
            _buildPaymentForm(context, l10n, cs, sagana),
        ],
      ),
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
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
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
            child: Text(
              farmer.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyLoansState(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: cs.onSurfaceVariant,
            size: 22,
          ),
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

  /// Small rounded status pill ("OVERDUE"), same shape as the badges on the
  /// Loan Dashboard and Loan History rows.
  Widget _statusPill(String label, Color color, {Color? background}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildLoanSelector(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );
    return AccountFormSection(
      icon: Icons.receipt_long_rounded,
      title: l10n.paymentSelectLoan,
      cs: cs,
      sagana: sagana,
      children: [
        for (final loan in _farmerLoans)
          Padding(
            padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
            child: AnimatedPressable(
              onTap: () => _selectLoan(loan),
              child: Container(
                padding: const EdgeInsets.all(AppConstants.spacingMd),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(
                    color: loan.isOverdue
                        ? AppConstants.errorRed.withValues(alpha: 0.40)
                        : cs.outline.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
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
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${l10n.loanDashBalance}: ${currency.format(loan.remainingBalance)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          if (loan.nextPaymentDate != null)
                            Text(
                              '${l10n.issueLoanNextPaymentDue}: ${DateFormat('MMM d, yyyy').format(loan.nextPaymentDate!)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: loan.isOverdue
                                    ? AppConstants.errorRed
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (loan.isOverdue) ...[
                      const SizedBox(width: AppConstants.spacingSm),
                      _statusPill(
                        l10n.farmerMgmtOverdueBadge,
                        AppConstants.errorRed,
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// One label/value pair inside the loan summary banner.
  Widget _heroFact(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Loan banner: reference, status, balance, repayment progress and the four
  /// facts a Manager needs while taking a payment. Same gradients as Loan
  /// Details (green; red when overdue).
  Widget _buildLoanSummaryCard(
    AppLocalizations l10n,
    AdminLoanSummary loan,
  ) {
    final money = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    final whole = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );
    final due = loan.nextPaymentDate;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        gradient: loan.isOverdue
            ? LinearGradient(
                colors: [
                  AppConstants.errorRed.withValues(alpha: 0.92),
                  const Color(0xFFB71C1C),
                ],
              )
            : AppConstants.primaryButtonGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  loan.referenceNo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
              if (loan.isOverdue) ...[
                const SizedBox(width: 8),
                _statusPill(
                  l10n.farmerMgmtOverdueBadge,
                  Colors.white,
                  background: Colors.white.withValues(alpha: 0.2),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            l10n.loanDashBalance,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          Text(
            money.format(loan.remainingBalance),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 26,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: LinearProgressIndicator(
              value: loan.repaidPercent,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.paymentRepaidPercent(
              (loan.repaidPercent * 100).toStringAsFixed(0),
            ),
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          Divider(
            height: AppConstants.spacingSectionV,
            color: Colors.white.withValues(alpha: 0.25),
          ),
          Row(
            children: [
              _heroFact(l10n.paymentLoanValue, whole.format(loan.totalValue)),
              const SizedBox(width: AppConstants.spacingMd),
              _heroFact(l10n.paymentPaidSoFar, whole.format(loan.amountPaid)),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              _heroFact(
                l10n.issueLoanMonthlyPayment,
                whole.format(loan.monthlyPayment),
              ),
              const SizedBox(width: AppConstants.spacingMd),
              _heroFact(
                l10n.issueLoanNextPaymentDue,
                due == null ? '—' : DateFormat('MMM d, yyyy').format(due),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentForm(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final loan = _selectedLoan!;
    final money = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    final amount = _enteredAmount;
    final remainingAfter = (loan.remainingBalance - amount)
        .clamp(0, double.infinity)
        .toDouble();
    final isOverpayment = amount > loan.remainingBalance;
    final settlesLoan = amount > 0 && amount == loan.remainingBalance;

    // Quick amounts: this month's instalment (never more than what is owed) and
    // the whole balance. When they are the same number only one is offered.
    final monthly = _defaultAmountFor(loan);
    final full = loan.remainingBalance;
    final quickAmounts = <(String, double)>[
      if (loan.monthlyPayment > 0 && monthly > 0 && monthly != full)
        (l10n.paymentChipMonthly, monthly),
      if (full > 0) (l10n.paymentChipFullBalance, full),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLoanSummaryCard(l10n, loan),
        const SizedBox(height: AppConstants.spacingGutter),
        AccountFormSection(
          icon: Icons.payments_rounded,
          title: l10n.paymentDetailsSectionTitle,
          cs: cs,
          sagana: sagana,
          children: [
            AccountFieldLabel(label: l10n.paymentAmountLabel, cs: cs),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                // Pesos and centavos only: the amount is stored to 2 decimals.
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 22,
                color: cs.onSurface,
              ),
              decoration: const InputDecoration(
                prefixText: '₱ ',
                errorMaxLines: 2,
              ),
              validator: (v) => (double.tryParse((v ?? '').trim()) ?? 0) > 0
                  ? null
                  : l10n.paymentErrorInvalidAmount,
            ),
            if (quickAmounts.isNotEmpty) ...[
              const SizedBox(height: AppConstants.spacingMd),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // The same chip as Loan History's filters; a check mark
                  // shows which one is in the field.
                  for (final (label, value) in quickAmounts)
                    LoanChoiceChip(
                      label: label,
                      selected: amount == value,
                      showCheckmark: true,
                      selectedColor: AppConstants.primaryGreen,
                      onTap: () => setState(() {
                        _amountController.text = value
                            .toStringAsFixed(value % 1 == 0 ? 0 : 2);
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppConstants.spacingMd),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMd,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      l10n.paymentRemainingAfter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    money.format(remainingAfter),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: amount > 0 && remainingAfter == 0
                          ? AppConstants.successGreen
                          : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (isOverpayment)
              _paymentNotice(
                icon: Icons.warning_amber_rounded,
                color: AppConstants.warningAmber,
                message: l10n.paymentOverpaymentNotice,
                cs: cs,
              )
            else if (settlesLoan)
              _paymentNotice(
                icon: Icons.check_circle_outline_rounded,
                color: AppConstants.successGreen,
                message: l10n.paymentSettlesLoan,
                cs: cs,
              ),
            const SizedBox(height: AppConstants.spacingGutter),
            AccountFieldLabel(label: l10n.paymentDate, cs: cs),
            InkWell(
              onTap: _pickPaymentDate,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: InputDecorator(
                decoration: InputDecoration(
                  suffixIcon: Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                child: Text(
                  DateFormat('MMMM d, yyyy').format(_paymentDate),
                  style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingGutter),
            AccountFieldLabel(label: l10n.loanFormNotes, cs: cs),
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
              decoration: InputDecoration(hintText: l10n.paymentNotesHint),
            ),
          ],
        ),
      ],
    );
  }

  /// Inline notice under the amount (overpayment warning / settles-the-loan).
  Widget _paymentNotice({
    required IconData icon,
    required Color color,
    required String message,
    required ColorScheme cs,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppConstants.spacingSm),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
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
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    final excess = amount - remainingBalance;

    return AlertDialog(
      title: Text(
        l10n.paymentOverpaymentTitle,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16),
      ),
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
          child: Text(
            l10n.paymentOverpaymentConfirm,
            style: const TextStyle(color: AppConstants.primaryGreen),
          ),
        ),
      ],
    );
  }
}
