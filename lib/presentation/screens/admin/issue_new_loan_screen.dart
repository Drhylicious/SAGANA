import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/utils/bod_schedule_utils.dart';
import '../../../data/models/admin_loan_model.dart';
import '../../../data/repositories/admin_loan_repository.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/account_form_widgets.dart';
import '../../widgets/farmer_pick_tile.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/app_dropdown_field.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

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
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _monthlyPaymentController = TextEditingController();

  bool _isOnline = true;
  bool _isLoadingRoster = true;
  bool _isSubmitting = false;

  /// Set when the Manager taps Issue Loan: only then do the farmer and items
  /// show their "required" errors, so an untouched form is not covered in red.
  bool _submitAttempted = false;

  List<FarmerPickerResult> _farmerRoster = [];
  FarmerPickerResult? _selectedFarmer;
  FarmerLoanStanding? _farmerStanding;
  bool _standingCheckedOnline = false;

  DateTime _issuedDate = DateTime.now();
  final List<LoanItemDraft> _items = [];
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

  /// Whether the selected farmer clears the capital-share minimum. Only
  /// blocks the Issue button when we have a fresh online standing read
  /// AND a policy minimum > 0; otherwise stays permissive (issue_loan()
  /// enforces the rule hard server-side either way).
  bool get _capitalEligible {
    final standing = _farmerStanding;
    if (!_standingCheckedOnline || standing == null) return true;
    if (standing.minimumCapitalRequired <= 0) return true;
    return standing.meetsCapitalEligibility;
  }

  /// Sum of the line totals, each already rounded to centavos, so the total
  /// shown is exactly what the lines add up to and what is saved.
  double get _totalValue =>
      _roundCents(_items.fold<double>(0, (sum, i) => sum + i.lineTotal));

  double get _enteredMonthlyPayment =>
      double.tryParse(_monthlyPaymentController.text.trim()) ?? 0;

  // ─── Item CRUD ──────────────────────────────────────────────────────────

  void _openAddItemSheet({LoanItemDraft? existing}) {
    showManagementModal(
      context: context,
      builder: (_) => AddLoanItemModalBody(
        existing: existing,
        // An item can be on a loan only once: the picker offers the loanable
        // items this loan does not have yet (plus the one being edited).
        loanCatalog: _loanCatalog,
        takenInventoryIds: {
          for (final i in _items)
            if (i.id != existing?.id && i.inventoryItemId != null)
              i.inventoryItemId!,
        },
        onSave: (draft) {
          setState(() {
            if (existing != null) {
              final idx = _items.indexWhere((i) => i.id == existing.id);
              if (idx != -1) _items[idx] = draft;
            } else {
              _items.add(draft);
            }
          });
        },
      ),
    );
  }

  void _deleteItem(String id) {
    setState(() => _items.removeWhere((i) => i.id == id));
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

    // Missing farmer / items / monthly payment are shown inline, on the field
    // that needs fixing (issueLoanErrorNoFarmer, ...NoItems, ...InvalidMonthly),
    // not as a Snackbar. The monthly field reports through the form.
    setState(() => _submitAttempted = true);
    final formValid = _formKey.currentState?.validate() ?? true;
    if (_selectedFarmer == null || _items.isEmpty || !formValid) return;
    final monthlyPayment = _enteredMonthlyPayment;
    if (monthlyPayment <= 0) return;

    // Capital-share eligibility — UI hard-stop (Issue 4d). Only enforced
    // when we actually have a fresh online standing read; issue_loan()
    // re-checks server-side regardless.
    final standing = _farmerStanding;
    if (_standingCheckedOnline &&
        standing != null &&
        standing.minimumCapitalRequired > 0 &&
        !standing.meetsCapitalEligibility) {
      _showSnack(
        l10n.issueLoanCapitalBlocked(
          NumberFormat.currency(
            locale: 'en_PH',
            symbol: '₱',
            decimalDigits: 0,
          ).format(standing.minimumCapitalRequired),
        ),
        isError: true,
      );
      return;
    }

    // Loan issuance is decided by the server (stock and reference numbers),
    // so it is never kept on the device.
    if (!_isOnline) {
      _showSnack(l10n.serverOnlyOffline, isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    final nextPaymentDate = BodSchedule.upcoming(_issuedDate);
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
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showSnack(_describeIssueLoanError(e), isError: true);
    }
  }

  /// issueLoan() throws on failure by design (see AdminLoanRepository's
  /// class doc comment — financial writes must not fail silently). The
  /// issue_loan() RPC raises specific, useful exceptions (e.g. "Insufficient
  /// stock for X: Y on hand, Z requested" or "Inventory item ... no longer
  /// exists") — surfacing that text instead of a generic message tells the
  /// admin exactly what to fix, rather than leaving them stuck after being
  /// told at item-entry time that a shortfall could still "proceed."
  /// Falls back to the generic message for anything that isn't a
  /// recognizable business-rule failure (e.g. a network/timeout error),
  /// since those don't have a useful specific message to show.
  String _describeIssueLoanError(Object error) {
    final l10n = AppLocalizations.of(context);
    if (error is PostgrestException && error.message.isNotEmpty) {
      return error.message;
    }
    return l10n.issueLoanErrorGeneric;
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

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.issueLoanTitle,
            onBack: () => context.pop(),
          ),
          if (!_isOnline) const OfflineStatusCard(),
          Expanded(
            child: _isLoadingRoster
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.spacingSafeH,
                        AppConstants.spacingGutter,
                        AppConstants.spacingSafeH,
                        AppConstants.spacingSectionV,
                      ),
                      children: [
                        _buildBorrowerSection(context, l10n, cs, sagana),
                        const SizedBox(height: AppConstants.spacingGutter),
                        _buildItemsSection(context, l10n, cs, sagana),
                        const SizedBox(height: AppConstants.spacingGutter),
                        _buildTermsSection(context, l10n, cs, sagana),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context, l10n),
    );
  }

  // ─── Shared field pieces ────────────────────────────────────────────────

  /// A tappable field that looks like the form's text inputs (a picker for a
  /// farmer or a date): same border, fill, error style and label spacing.
  Widget _pickerField({
    required VoidCallback onTap,
    required Widget child,
    required Widget suffix,
    String? errorText,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: InputDecorator(
        decoration: InputDecoration(
          errorText: errorText,
          errorMaxLines: 2,
          suffixIcon: suffix,
        ),
        child: child,
      ),
    );
  }

  // ─── Borrower section ───────────────────────────────────────────────────

  Widget _buildBorrowerSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final farmer = _selectedFarmer;
    return AccountFormSection(
      icon: Icons.person_rounded,
      title: l10n.issueLoanSectionBorrower,
      cs: cs,
      sagana: sagana,
      children: [
        AccountFieldLabel(label: '${l10n.issueLoanSelectFarmer} *', cs: cs),
        _pickerField(
          onTap: () => _openFarmerPicker(context, l10n, cs, sagana),
          errorText: (_submitAttempted && farmer == null)
              ? l10n.issueLoanErrorNoFarmer
              : null,
          suffix: Icon(Icons.unfold_more_rounded, color: cs.onSurfaceVariant),
          child: Row(
            children: [
              if (farmer != null) ...[
                ProfileAvatar(
                  photoUrl: farmer.profilePhotoUrl,
                  displayName: farmer.fullName,
                  radius: 12,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  farmer?.fullName ?? l10n.issueLoanNoFarmerSelected,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: farmer == null
                      ? GoogleFonts.inter(fontSize: 13, color: cs.outline)
                      : GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: cs.onSurface,
                        ),
                ),
              ),
            ],
          ),
        ),
        if (farmer != null) ...[
          const SizedBox(height: AppConstants.spacingMd),
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
    if (!_isOnline) {
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

    // Online but the standing check for this farmer hasn't resolved yet —
    // a brief, genuine loading state, not an offline one. Showing the
    // "unavailable while offline" text here (the previous behavior) was
    // simply the wrong message for this case, and it flashed on screen for
    // the duration of the network round-trip every time a farmer was
    // selected while online.
    if (!_standingCheckedOnline) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppConstants.spacingSm),
            Text(
              l10n.issueLoanStandingLoading,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
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
                if (!standing.meetsCapitalEligibility &&
                    standing.minimumCapitalRequired > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      standing.showsCapitalAmount
                          ? l10n.issueLoanCapitalIneligible(
                              currency.format(standing.capitalContribution),
                              currency.format(standing.minimumCapitalRequired),
                            )
                          : l10n.issueLoanCapitalIneligibleNoAmount(
                              currency.format(standing.minimumCapitalRequired),
                            ),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.errorRed,
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
        selectedId: _selectedFarmer?.id,
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
    final showItemsError = _submitAttempted && _items.isEmpty;
    return AccountFormSection(
      icon: Icons.inventory_2_rounded,
      title: l10n.issueLoanInputItems,
      cs: cs,
      sagana: sagana,
      trailing: _items.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text(
                l10n.issueLoanItemsCount(_items.length),
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ),
      children: [
        if (_items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spacingGutter),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: showItemsError
                  ? Border.all(color: AppConstants.errorRed)
                  : null,
            ),
            child: Column(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 28,
                  color: showItemsError
                      ? AppConstants.errorRed
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                Text(
                  showItemsError
                      ? l10n.issueLoanErrorNoItems
                      : l10n.issueLoanNoItemsYet,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: showItemsError
                        ? AppConstants.errorRed
                        : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          for (final item in _items) _buildItemRow(context, item, l10n, cs),
        const SizedBox(height: AppConstants.spacingMd),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openAddItemSheet(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(
              l10n.issueLoanAddItem,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemRow(
    BuildContext context,
    LoanItemDraft item,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    final qtyLabel = _quantityText(item.quantity);

    Widget photoPlaceholder() => Container(
      color: cs.surfaceContainerHighest,
      child: Icon(
        Icons.inventory_2_outlined,
        size: 20,
        color: cs.outline.withValues(alpha: 0.4),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          // The item's own Inventory Management photo — selected from the
          // Loan Item Catalog, never uploaded here directly.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            child: SizedBox(
              width: 44,
              height: 44,
              child: (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                  ? Image.network(
                      item.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => photoPlaceholder(),
                    )
                  : photoPlaceholder(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
          const SizedBox(width: 8),
          // Price above the two actions; visualDensity.compact trims the
          // IconButtons' own hit-target padding so they sit close together.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currency.format(item.lineTotal),
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: cs.onSurfaceVariant,
                    onPressed: () => _openAddItemSheet(existing: item),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: AppConstants.errorRed,
                    onPressed: () => _deleteItem(item.id),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Repayment terms section ────────────────────────────────────────────

  Widget _buildTermsSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    // The date shown is the one that will be sent: the first BOD Saturday on
    // or after the chosen issue date (see _submit).
    final nextPayment = BodSchedule.upcoming(_issuedDate);

    return AccountFormSection(
      icon: Icons.event_note_rounded,
      title: l10n.issueLoanSectionTerms,
      cs: cs,
      sagana: sagana,
      children: [
        AccountFieldLabel(label: l10n.issueLoanIssuedDate, cs: cs),
        _pickerField(
          onTap: _pickIssuedDate,
          suffix: Icon(
            Icons.calendar_today_rounded,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          child: Text(
            DateFormat('MMMM d, yyyy').format(_issuedDate),
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
          ),
        ),
        const SizedBox(height: AppConstants.spacingGutter),
        AccountFieldLabel(label: l10n.issueLoanMonthlyPaymentLabel, cs: cs),
        TextFormField(
          controller: _monthlyPaymentController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            // Pesos and centavos only: the amount is stored to 2 decimals.
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: cs.onSurface,
          ),
          decoration: InputDecoration(
            prefixText: '₱ ',
            hintText: '0.00',
            // No loan term is set anywhere in SAGANA: the Manager sets the
            // monthly amount and the loan runs until the balance is paid. So
            // this only states what follows from the numbers entered, instead
            // of assuming a repayment period.
            helperText: (_totalValue > 0 && _enteredMonthlyPayment > 0)
                ? l10n.issueLoanMonthlyEstimate(
                    (_totalValue / _enteredMonthlyPayment).ceil(),
                  )
                : l10n.issueLoanMonthlyHelp,
            helperMaxLines: 2,
            errorMaxLines: 2,
          ),
          validator: (v) {
            final text = (v ?? '').trim();
            if (text.isEmpty) return l10n.issueLoanMonthlyRequired;
            if ((double.tryParse(text) ?? 0) <= 0) {
              return l10n.issueLoanErrorInvalidMonthly;
            }
            return null;
          },
        ),
        const SizedBox(height: AppConstants.spacingGutter),
        AccountFieldLabel(label: l10n.issueLoanNextPaymentDue, cs: cs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_available_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      DateFormat('MMMM d, yyyy').format(nextPayment),
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l10n.issueLoanFrequency,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                l10n.issueLoanVenue,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // Notes is the last field of the loan's terms, so it sits with them in
        // the same card instead of in a card of its own.
        const SizedBox(height: AppConstants.spacingGutter),
        AccountFieldLabel(label: l10n.loanFormNotes, cs: cs),
        TextFormField(
          controller: _notesController,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
        ),
      ],
    );
  }

  // ─── Bottom bar ─────────────────────────────────────────────────────────

  /// The loan total stays in view next to the action, instead of a banner at
  /// the end of a long form.
  Widget _buildBottomBar(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    return Container(
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        border: Border(
          top: BorderSide(color: cs.outline.withValues(alpha: 0.15)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.issueLoanTotalValue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        currency.format(_totalValue),
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
              const SizedBox(width: AppConstants.spacingMd),
              PrimaryButton(
                label: l10n.issueLoanSubmit,
                expand: false,
                isLoading: _isSubmitting,
                onPressed: (_isSubmitting || !_capitalEligible || !_isOnline)
                    ? null
                    : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Money and quantity helpers ─────────────────────────────────────────────

/// Rounds to centavos. Line totals and the loan total are kept at 2 decimals,
/// the way the database stores them, so what is shown, what is added up and what
/// is saved are the same number (0.1 x 3 is 0.3, not 0.30000000000000004).
double _roundCents(double value) => (value * 100).round() / 100;

/// A quantity as typed: up to 2 decimals, no trailing zeros (2, 2.5, 2.25).
String _quantityText(double quantity) {
  final text = quantity.toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

// ─── Local draft model (form state only, not persisted directly) ──────────

/// One item line on the loan being built (form state only).
class LoanItemDraft {
  final String id;
  final String? inventoryItemId;
  String itemName;
  double quantity;
  String unit;
  double unitPrice;
  String? imageUrl;

  LoanItemDraft({
    required this.id,
    this.inventoryItemId,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    this.imageUrl,
  });

  double get lineTotal => _roundCents(quantity * unitPrice);
}

// ─── Farmer picker modal ────────────────────────────────────────────────────

class _FarmerPickerModalBody extends StatefulWidget {
  final List<FarmerPickerResult> roster;
  final String? selectedId;
  final AppLocalizations l10n;
  final ValueChanged<FarmerPickerResult> onSelected;

  const _FarmerPickerModalBody({
    required this.roster,
    required this.selectedId,
    required this.l10n,
    required this.onSelected,
  });

  @override
  State<_FarmerPickerModalBody> createState() => _FarmerPickerModalBodyState();
}

class _FarmerPickerModalBodyState extends State<_FarmerPickerModalBody> {
  String _query = '';

  // A to Z, so a farmer is where the Manager expects to find them.
  late final List<FarmerPickerResult> _sorted = [...widget.roster]
    ..sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _sorted
        : _sorted.where((f) => f.fullName.toLowerCase().contains(query)).toList();

    // The dialog hugs the list instead of always filling most of the screen,
    // up to the shell's usual 62%. It is sized from the whole roster, not the
    // search result, so it does not change size while the Manager types.
    final screenHeight = MediaQuery.of(context).size.height;
    final fraction = ((170 + 64 * widget.roster.length.clamp(1, 8)) / screenHeight)
        .clamp(0.30, 0.62)
        .toDouble();

    return ManagementModalShell(
      title: widget.l10n.issueLoanSelectFarmer,
      bodyIsScrollable: true,
      listHeightFraction: fraction,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.l10n.issueLoanFarmerCount(filtered.length),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_search_rounded,
                          size: 36,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.l10n.issueLoanNoFarmerResults,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final farmer = filtered[index];
                      return FarmerPickTile(
                        name: farmer.fullName,
                        photoUrl: farmer.profilePhotoUrl,
                        selected: farmer.id == widget.selectedId,
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
//
// A loan holds several different items, each at most once: [takenInventoryIds]
// are the items already on the loan, which the picker leaves out. To change an
// item's quantity, edit its line.

class AddLoanItemModalBody extends StatefulWidget {
  final LoanItemDraft? existing;
  final List<LoanCatalogItem> loanCatalog;
  final Set<String> takenInventoryIds;
  final ValueChanged<LoanItemDraft> onSave;

  const AddLoanItemModalBody({
    super.key,
    this.existing,
    required this.loanCatalog,
    this.takenInventoryIds = const {},
    required this.onSave,
  });

  @override
  State<AddLoanItemModalBody> createState() => _AddLoanItemModalBodyState();
}

class _AddLoanItemModalBodyState extends State<AddLoanItemModalBody> {
  final _formKey = GlobalKey<FormState>();
  LoanCatalogItem? _selected;
  late final TextEditingController _qtyController;

  /// The loanable items this loan does not have yet (plus the one being edited).
  late final List<LoanCatalogItem> _available = widget.loanCatalog
      .where((c) => !widget.takenInventoryIds.contains(c.inventoryItemId))
      .toList();

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(
      text: widget.existing != null
          ? _quantityText(widget.existing!.quantity)
          : '',
    );
    // When editing an existing line item, pre-select the matching catalog
    // entry (if it's still in the catalog — it may have been unpublished).
    if (widget.existing?.inventoryItemId != null) {
      for (final item in _available) {
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

  void _confirm() {
    // The item and the quantity show their own inline errors.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onSave(
      LoanItemDraft(
        id:
            widget.existing?.id ??
            'item_${DateTime.now().millisecondsSinceEpoch}',
        inventoryItemId: _selected!.inventoryItemId,
        itemName: _selected!.itemName,
        quantity: _roundCents(_quantity),
        unit: _selected!.unit,
        unitPrice: _selected!.unitPrice,
        imageUrl: _selected!.imageUrl,
      ),
    );
    Navigator.of(context).pop();
  }

  /// A message-only state: nothing to add (an empty catalog, or every loanable
  /// item is already on this loan).
  Widget _messageState(
    AppLocalizations l10n,
    ColorScheme cs, {
    required String title,
    required String hint,
    required Widget footer,
  }) {
    return ManagementModalShell(
      title: l10n.issueLoanAddItem,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: cs.onSurface,
            ),
          ),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      footer: footer,
    );
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
      return _messageState(
        l10n,
        cs,
        title: l10n.loanItemNoItemsYet,
        hint: l10n.issueLoanPublishFirstHint,
        footer: ManagementModalActions(
          cancelLabel: l10n.close,
          primaryLabel: l10n.issueLoanGoToInventory,
          onPrimary: () {
            Navigator.of(context).pop();
            context.push(AppRoutes.adminInventory);
          },
        ),
      );
    }

    // Every loanable item is already on this loan.
    if (_available.isEmpty) {
      return _messageState(
        l10n,
        cs,
        title: l10n.issueLoanAllItemsAdded,
        hint: '',
        footer: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              l10n.close,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    return ManagementModalShell(
      title: l10n.issueLoanAddItem,
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AccountFieldLabel(label: '${l10n.issueLoanSelectItem} *', cs: cs),
            AppDropdownField<LoanCatalogItem>(
              value: _selected,
              hintText: l10n.issueLoanSelectItemHint,
              items: _available,
              itemLabel: (c) => '${c.itemName} (${c.unit})',
              validator: (v) => v == null ? l10n.issueLoanErrorSelectItem : null,
              onChanged: (v) {
                setState(() => _selected = v);
                // The stock limit depends on the item: re-check a quantity
                // that is already typed.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _qtyController.text.isNotEmpty) {
                    _formKey.currentState?.validate();
                  }
                });
              },
            ),
            if (_selected != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      l10n.issueLoanUnitPrice,
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
                    currency.format(_selected!.unitPrice),
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      l10n.loanItemAvailableInStock,
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
                    '${_quantityText(_selected!.quantityOnHand)} ${_selected!.unit}',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            AccountFieldLabel(label: '${l10n.issueLoanQuantity} *', cs: cs),
            TextFormField(
              controller: _qtyController,
              decoration: InputDecoration(
                hintText: '0',
                suffixText: _selected?.unit,
                errorMaxLines: 4,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                // Quantities are stored to 2 decimals.
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.isEmpty) return l10n.issueLoanErrorQuantityRequired;
                final quantity = double.tryParse(text) ?? 0;
                if (quantity <= 0) return l10n.issueLoanErrorQuantityInvalid;
                final item = _selected;
                if (item != null && quantity > item.quantityOnHand) {
                  return l10n.issueLoanInsufficientStock(
                    _quantityText(quantity),
                    _quantityText(item.quantityOnHand),
                    item.unit,
                  );
                }
                return null;
              },
            ),
            if (_selected != null && _quantity > 0) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      l10n.issueLoanLineTotal,
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
                    currency.format(_roundCents(_quantity * _selected!.unitPrice)),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      // Local footer, not ManagementModalActions — that shared widget's
      // Cancel button sits in a narrower flex:1 box than its flex:2 Confirm
      // button and both use FittedBox(fit: scaleDown), so "Cancel" shrinks
      // more than the longer Confirm label does at this dialog's width.
      // Fixed here to both buttons' text at an explicit, equal size instead
      // of leaving it to that scaling — scoped to this dialog only.
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                l10n.cancel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _confirm,
              child: Text(
                l10n.issueLoanConfirmItem,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
