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
import '../../../routes/app_routes.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';

/// Loan Details — Admin (read-only).
/// Pushed above the shell. Route: /admin/loans/details, extra: String loanId
///
/// No Delete, no Edit — issued loans are append-only once created, per the
/// project's rule against hard-deleting financial records. The only write
/// action here is "Mark as Paid" (an administrative settlement, online-only).
/// Payment history is shown newest→oldest, matching LoanModel's default
/// sort — most recent payment is what an admin needs first during a
/// BOD meeting.
class LoanDetailsScreen extends StatefulWidget {
  final String loanId;

  const LoanDetailsScreen({super.key, required this.loanId});

  @override
  State<LoanDetailsScreen> createState() => _LoanDetailsScreenState();
}

class _LoanDetailsScreenState extends State<LoanDetailsScreen> {
  final _repo = AdminLoanRepository();

  bool _isOnline = true;
  bool _isLoading = true;
  bool _offlineUnavailable = false;
  bool _isMarkingPaid = false;

  AdminLoanDetail? _detail;
  Map<String, String> _adminNames = {};

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _offlineUnavailable = false;
    });

    if (!_isOnline) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _offlineUnavailable = true;
      });
      return;
    }

    final detail = await _repo.fetchLoanById(widget.loanId);
    if (!mounted) return;

    if (detail == null) {
      setState(() => _isLoading = false);
      return;
    }

    final adminIds = detail.loan.payments
        .map((p) => p.recordedBy)
        .whereType<String>()
        .toSet()
        .toList();
    final names = await _repo.fetchAdminNames(adminIds);

    if (!mounted) return;
    setState(() {
      _detail = detail;
      _adminNames = names;
      _isLoading = false;
    });
  }

  Future<void> _markAsPaid() async {
    final l10n = AppLocalizations.of(context);
    final reason = await AppDialog.show<String>(
      context: context,
      child: _MarkAsPaidDialog(l10n: l10n),
    );
    if (reason == null) return; // cancelled

    setState(() => _isMarkingPaid = true);
    try {
      await _repo.markLoanAsPaid(widget.loanId, reason: reason.isEmpty ? null : reason);
      if (!mounted) return;
      _showSnack(l10n.loanDetailsMarkPaidSuccess);
      await _load();
    } catch (_) {
      if (!mounted) return;
      _showSnack(l10n.loanDetailsMarkPaidError, isError: true);
    } finally {
      if (mounted) setState(() => _isMarkingPaid = false);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildTopBar(context, l10n, cs),
          Expanded(child: _buildBody(context, l10n, cs, sagana)),
        ],
      ),
      bottomNavigationBar: _detail != null && !_detail!.loan.isPaid
          ? _buildBottomBar(context, l10n)
          : null,
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
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  l10n.loanDetailsTitle,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: cs.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_offlineUnavailable) {
      return _buildMessageState(Icons.wifi_off_rounded, l10n.loanDetailsUnavailableOffline, cs);
    }
    if (_detail == null) {
      return _buildMessageState(Icons.search_off_rounded, l10n.loanDetailsNotFound, cs);
    }

    final detail = _detail!;
    final loan = detail.loan;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingSafeH,
          AppConstants.spacingGutter,
          AppConstants.spacingSafeH,
          32,
        ),
        children: [
          _buildFarmerRow(context, detail, cs, sagana),
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildSummaryCard(context, l10n, loan, cs),
          if (!loan.isPaid && _isOnline) ...[
            const SizedBox(height: AppConstants.spacingSm),
            _buildMarkAsPaidAction(context, l10n),
          ],
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildSectionTitle(l10n.issueLoanInputItems, cs),
          const SizedBox(height: AppConstants.spacingSm),
          ...loan.items.map((item) => _buildItemRow(item, cs, sagana)),
          if (!loan.isPaid) ...[
            const SizedBox(height: AppConstants.spacingSectionV),
            _buildSectionTitle(l10n.issueLoanPaymentSchedule, cs),
            const SizedBox(height: AppConstants.spacingSm),
            _buildScheduleCard(context, l10n, loan, cs, sagana),
          ],
          const SizedBox(height: AppConstants.spacingSectionV),
          _buildSectionTitle(l10n.loanDetailsPaymentHistory, cs),
          const SizedBox(height: AppConstants.spacingSm),
          if (loan.payments.isEmpty)
            _buildEmptyPayments(l10n, cs)
          else
            ...loan.payments.map((p) => _buildPaymentRow(p, l10n, cs, sagana)),
          if (loan.notes != null && loan.notes!.isNotEmpty) ...[
            const SizedBox(height: AppConstants.spacingSectionV),
            _buildSectionTitle(l10n.loanDetailsNotesLabel, cs),
            const SizedBox(height: AppConstants.spacingSm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              decoration: BoxDecoration(
                color: sagana.cardBackground,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
              ),
              child: Text(
                loan.notes!,
                style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageState(IconData icon, String message, ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingSectionV),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: AppConstants.spacingMd),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFarmerRow(
    BuildContext context,
    AdminLoanDetail detail,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.farmerDetails, extra: detail.loan.farmerId),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppConstants.primaryContainer,
              child: detail.farmerPhotoUrl != null
                  ? ClipOval(
                      child: Image.network(
                        detail.farmerPhotoUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white),
                      ),
                    )
                  : Text(
                      detail.farmerName.isNotEmpty ? detail.farmerName[0].toUpperCase() : '?',
                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
            ),
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.farmerName,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface),
                  ),
                  Text(
                    detail.memberId,
                    style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    AppLocalizations l10n,
    dynamic loan,
    ColorScheme cs,
  ) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
    final isOverdueLoan = loan.isOverdue as bool;
    final statusColor = loan.isPaid
        ? AppConstants.buyerBlue
        : isOverdueLoan
            ? AppConstants.errorRed
            : AppConstants.successGreen;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        gradient: isOverdueLoan
            ? LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [AppConstants.errorRed.withValues(alpha: 0.92), const Color(0xFFB71C1C)],
              )
            : AppConstants.primaryButtonGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                loan.referenceNo as String,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  (loan.status as String).toUpperCase(),
                  style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            currency.format(loan.totalValue),
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 26, color: Colors.white),
          ),
          Text(
            l10n.issueLoanTotalValue,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.loanDashPaid, style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
                    Text(
                      currency.format(loan.amountPaid),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.loanDashBalance, style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
                    Text(
                      currency.format(loan.remainingBalance as double),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: LinearProgressIndicator(
              value: loan.repaidPercent as double,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkAsPaidAction(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _isMarkingPaid ? null : _markAsPaid,
          icon: _isMarkingPaid
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppConstants.warningAmber),
                )
              : const Icon(Icons.fact_check_outlined, size: 18),
          label: Text(
            l10n.loanDetailsMarkPaid,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppConstants.warningAmber,
            side: const BorderSide(color: AppConstants.warningAmber),
            minimumSize: const Size(double.infinity, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.loanDetailsMarkPaidCaption,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme cs) {
    return Text(
      title,
      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface),
    );
  }

  Widget _buildItemRow(dynamic item, ColorScheme cs, SaganaColors sagana) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
    final qty = item.quantity as double;
    final qtyLabel = qty % 1 == 0 ? qty.toStringAsFixed(0) : qty.toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName as String,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface),
                ),
                Text(
                  '$qtyLabel ${item.unit} × ${currency.format(item.unitPrice)}',
                  style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            currency.format(item.lineTotal),
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(
    BuildContext context,
    AppLocalizations l10n,
    dynamic loan,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final nextDate = loan.nextPaymentDate as DateTime?;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.issueLoanNextPaymentDue, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
              Text(
                nextDate != null ? DateFormat('MMMM d, yyyy').format(nextDate) : '—',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.issueLoanMonthlyPayment, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
              Text(
                currency.format(loan.monthlyPayment),
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(l10n.issueLoanFrequency, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
          Text(l10n.issueLoanVenue, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildEmptyPayments(AppLocalizations l10n, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Text(
        l10n.loanDetailsNoPayments,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildPaymentRow(
    dynamic payment,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
    final recordedBy = payment.recordedBy as String?;
    final adminName = recordedBy != null ? _adminNames[recordedBy] : null;

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4),
            decoration: const BoxDecoration(color: AppConstants.successGreen, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppConstants.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('MMMM d, yyyy').format(payment.paymentDate as DateTime),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface),
                    ),
                    Text(
                      currency.format(payment.amountPaid),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: AppConstants.successGreen),
                    ),
                  ],
                ),
                Text(
                  l10n.loanDetailsBalanceAfter(currency.format(payment.runningBalance)),
                  style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                if (adminName != null)
                  Text(
                    l10n.loanDetailsPaidBy(adminName),
                    style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                if (payment.notes != null && (payment.notes as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      payment.notes as String,
                      style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, AppLocalizations l10n) {
    final sagana = context.saganaColors;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(top: BorderSide(color: sagana.glassBorder)),
          ),
          child: PrimaryButton(
            label: l10n.loanDashActionRecordPayment,
            onPressed: () {
              context.push(AppRoutes.recordPayment, extra: widget.loanId).then((_) => _load());
            },
          ),
        ),
      ),
    );
  }
}

// ─── Mark as Paid confirmation dialog ───────────────────────────────────────

class _MarkAsPaidDialog extends StatefulWidget {
  final AppLocalizations l10n;
  const _MarkAsPaidDialog({required this.l10n});

  @override
  State<_MarkAsPaidDialog> createState() => _MarkAsPaidDialogState();
}

class _MarkAsPaidDialogState extends State<_MarkAsPaidDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.l10n.loanDetailsMarkPaidTitle,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.l10n.loanDetailsMarkPaidMessage, style: GoogleFonts.inter(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            maxLines: 2,
            decoration: InputDecoration(hintText: widget.l10n.loanDetailsMarkPaidReasonHint),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.l10n.issueLoanCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_reasonController.text.trim()),
          child: Text(
            widget.l10n.loanDetailsMarkPaidConfirm,
            style: const TextStyle(color: AppConstants.primaryGreen),
          ),
        ),
      ],
    );
  }
}