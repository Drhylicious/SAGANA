import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/db_error_utils.dart';
import '../../core/utils/quantity_utils.dart';
import '../../data/models/loan_request_model.dart';
import '../../data/repositories/loan_repository.dart';
import 'app_toast.dart';
import 'management_modal.dart';

// Loan request pieces shared by the Farmer's "My Loan Requests" screen: the
// status colours, the request card, and the detail sheet (with Cancel while the
// request is still Pending).

({String label, Color color}) loanRequestStatusStyle(
  AppLocalizations l10n,
  LoanRequestModel r,
) {
  if (r.isApproved) {
    return (label: l10n.loanReqStatusApproved, color: AppConstants.successGreen);
  }
  if (r.isDisapproved) {
    return (label: l10n.loanReqStatusDisapproved, color: AppConstants.errorRed);
  }
  if (r.isCancelled) {
    return (label: l10n.loanReqStatusCancelled, color: AppConstants.outline);
  }
  return (label: l10n.loanReqStatusPending, color: AppConstants.warningAmber);
}

class LoanRequestCard extends StatelessWidget {
  final LoanRequestModel request;
  final VoidCallback onTap;
  const LoanRequestCard({super.key, required this.request, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final style = loanRequestStatusStyle(l10n, request);
    final names = request.items.map((i) => i.label).join(', ');

    return Material(
      color: Colors.white.withValues(alpha: 0.90),
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      request.requestNo,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: style.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      style.label,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: style.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                names,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.loanReqRequestedOn(
                        DateFormat('MMM d, yyyy').format(request.requestedAt),
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    '₱${NumberFormat('#,##0.00').format(request.totalValue)}',
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
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

class LoanRequestDetailSheet extends StatefulWidget {
  final LoanRequestModel request;
  final LoanRepository repo;
  const LoanRequestDetailSheet({super.key, required this.request, required this.repo});

  @override
  State<LoanRequestDetailSheet> createState() =>
      LoanRequestDetailSheetState();
}

class LoanRequestDetailSheetState extends State<LoanRequestDetailSheet> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _cancelling = true);
    try {
      await widget.repo.cancelLoanRequest(widget.request.id);
      if (!mounted) return;
      AppToast.show(context, l10n.loanReqCancelled);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      AppToast.show(
        context,
        readableDatabaseMessage(e) ?? l10n.loanReqCancelFailed,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final r = widget.request;
    final style = loanRequestStatusStyle(l10n, r);
    final money = NumberFormat('#,##0.00');
    final date = DateFormat('MMM d, yyyy');

    Widget note(String label, String text) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.4,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );

    return ManagementModalShell(
      title: l10n.loanReqDetailTitle,
      subtitle: r.requestNo,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  style.label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: style.color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.decidedAt != null && !r.isCancelled
                      ? l10n.loanReqDecidedOn(date.format(r.decidedAt!))
                      : l10n.loanReqRequestedOn(date.format(r.requestedAt)),
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final i in r.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i.itemName,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          '${formatQuantityUnit(i.quantity, i.unit)} × ${formatPricePerUnit(i.unitPrice, i.unit)}',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '₱${money.format(i.lineTotal)}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.loanReqTotal,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '₱${money.format(r.totalValue)}',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.primaryGreen,
                ),
              ),
            ],
          ),
          if ((r.notes ?? '').trim().isNotEmpty)
            note(l10n.loanReqYourNote, r.notes!.trim()),
          if (r.isPending) note('', l10n.loanReqWaiting),
          if (r.isDisapproved && (r.decisionNote ?? '').trim().isNotEmpty)
            note(l10n.loanReqDecisionReason, r.decisionNote!.trim()),
          if (r.isApproved && (r.loanReference ?? '').isNotEmpty)
            note('', l10n.loanReqLoanIssued(r.loanReference!)),
          if (r.isApproved && (r.decisionNote ?? '').trim().isNotEmpty)
            note(l10n.loanReqDecisionNote, r.decisionNote!.trim()),
          if (r.isPending) ...[
            const SizedBox(height: 14),
            Text(
              l10n.loanReqCancelBody,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      footer: r.isPending
          ? ManagementModalActions(
              cancelLabel: l10n.close,
              primaryLabel: l10n.loanReqCancel,
              isDestructive: true,
              isLoading: _cancelling,
              onPrimary: _cancel,
            )
          : null,
    );
  }
}
