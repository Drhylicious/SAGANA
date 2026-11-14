import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../core/utils/app_error_message.dart';
import '../../data/models/program_assistance_model.dart';
import '../../data/repositories/program_assistance_repository.dart';
import '../../data/services/staff_permission_service.dart';
import 'app_toast.dart';
import 'view_only_banner.dart';

/// One failed-program assistance request, shown in Loan Requests beside the
/// loan requests. It is NOT a loan: approving it deducts the stock and issues a
/// reference, and creates no debt, due date or repayment. It is reviewed with
/// its own function (review_assistance_request), never the loan one.
///
/// The card owns its Approve / Disapprove steps; [onChanged] tells the list to
/// reload once a decision was saved.
class AssistanceRequestCard extends StatefulWidget {
  final AssistanceRequest request;

  /// False while offline: deciding needs the server.
  final bool canDecide;
  final VoidCallback onChanged;

  const AssistanceRequestCard({
    super.key,
    required this.request,
    required this.canDecide,
    required this.onChanged,
  });

  @override
  State<AssistanceRequestCard> createState() => _AssistanceRequestCardState();
}

class _AssistanceRequestCardState extends State<AssistanceRequestCard> {
  final _repo = ProgramAssistanceRepository();
  bool _busy = false;

  String _qty(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String get _itemsText => widget.request.items
      .map((i) => '${_qty(i.quantity)} ${i.unit} ${i.itemName}')
      .join(', ');

  Future<void> _approve() async {
    if (!requireManage(context, StaffModule.loans)) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.assistApproveTitle),
        content: Text(l10n.assistApproveBody(_itemsText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.retCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.assistApprove),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final ref = await _repo.review(
        requestId: widget.request.id,
        approve: true,
      );
      if (!mounted) return;
      AppToast.show(context, l10n.assistApproved(ref ?? ''));
      widget.onChanged();
    } catch (e, st) {
      if (mounted) {
        AppToast.show(context, friendlyError(l10n, e, st), isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (!requireManage(context, StaffModule.loans)) return;
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    String? error;
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(l10n.assistRejectTitle),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            maxLength: 300,
            decoration: InputDecoration(
              labelText: l10n.assistRejectReason,
              errorText: error,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.retCancel),
            ),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isEmpty) {
                  setLocal(() => error = l10n.retReasonRequired);
                  return;
                }
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: Text(l10n.assistReject),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repo.review(
        requestId: widget.request.id,
        approve: false,
        note: note,
      );
      if (!mounted) return;
      AppToast.show(context, l10n.assistRejected);
      widget.onChanged();
    } catch (e, st) {
      if (mounted) {
        AppToast.show(context, friendlyError(l10n, e, st), isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final r = widget.request;
    final color = r.isApproved
        ? AppConstants.successGreen
        : r.isRejected
        ? AppConstants.errorRed
        : r.isPending
        ? AppConstants.warningAmber
        : cs.onSurfaceVariant;
    final canAct = widget.canDecide && !_busy;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.saganaColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: AppConstants.programPurple.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Not a loan: the badge says so.
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppConstants.programPurple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    l10n.assistBadge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.programPurple,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                switch (r.status) {
                  'approved' => l10n.assistStatusApproved,
                  'rejected' => l10n.assistStatusRejected,
                  'cancelled' => l10n.assistStatusCancelled,
                  _ => l10n.assistStatusPending,
                },
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            r.farmerName ?? '',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          Text(
            [
              r.requestNumber,
              if (r.assistanceReference != null) r.assistanceReference!,
            ].join('  ·  '),
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          // Where the request came from: Program Management, after a failed
          // program outcome.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.volunteer_activism_rounded,
                  size: 14,
                  color: AppConstants.programPurple,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  (r.programName ?? '').isEmpty
                      ? l10n.assistFromProgram
                      : l10n.assistFromProgramNamed(r.programName!),
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.programPurple,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _itemsText,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.35,
              color: cs.onSurface,
            ),
          ),
          if ((r.message ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.message!,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if ((r.reviewNote ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.reviewNote!,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (r.isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: canAct ? _reject : null,
                    child: Text(l10n.assistReject),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: canAct ? _approve : null,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(l10n.assistApprove),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
