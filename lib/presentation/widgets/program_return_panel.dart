import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/app_error_message.dart';
import '../../data/models/program_return_model.dart';
import '../../data/repositories/program_repository.dart';
import '../../data/services/staff_permission_service.dart';
import '../../core/utils/quantity_utils.dart';
import 'app_toast.dart';
import 'labeled_text_field.dart';
import 'management_modal.dart';
import 'view_only_banner.dart';

// Staff side of Proposal 12: the Harvest Return for a Successful outcome and
// the resolution for a Failed one. Every action is a database function that
// re-checks the rules; these widgets only collect the input and explain the
// result in plain words.

String returnStatusLabel(AppLocalizations l10n, String status) => switch (status) {
      'partial' => l10n.retStatusPartial,
      'received' => l10n.retStatusReceived,
      'closed_short' => l10n.retStatusClosedShort,
      _ => l10n.retStatusPending,
    };

Color returnStatusColor(String status) => switch (status) {
      'received' => AppConstants.successGreen,
      'closed_short' => AppConstants.onSurfaceVariant,
      'partial' => AppConstants.warningAmber,
      _ => AppConstants.buyerBlue,
    };

String resolutionLabel(AppLocalizations l10n, String resolution) => switch (resolution) {
      FailedResolution.closedNoFurtherObligation => l10n.resClosed,
      FailedResolution.eligibleForReassessment => l10n.resReassess,
      FailedResolution.referredForLoanAssessment => l10n.resReferred,
      _ => l10n.resPending,
    };

/// A small pill with the return's status ("Harvest return pending", "Received in full"...).
class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: color),
        ),
      );
}

/// The compact block on a member's card for a Successful Harvest Return: the status, what has arrived
/// of what is due, a progress bar, and a full-width button that opens the return.
class ReturnSummaryBlock extends StatelessWidget {
  final ProgramReturn ret;
  final VoidCallback onManage;
  const ReturnSummaryBlock({super.key, required this.ret, required this.onManage});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = returnStatusColor(ret.status);
    final progress = ret.dueQuantity <= 0
        ? 0.0
        : (ret.receivedQuantity / ret.dueQuantity).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.assignment_return_outlined, size: 18, color: color),
              _StatusPill(label: returnStatusLabel(l10n, ret.status), color: color),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ret.cropName,
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.retProgressLine(
              formatReturnQuantity(ret.receivedQuantity),
              formatReturnQuantity(ret.dueQuantity),
              ret.unit,
            ),
            style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('manageReturnButton'),
              onPressed: onManage,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: Text(l10n.retManage),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The compact block for a Failed outcome: the current resolution.
class ResolutionSummaryBlock extends StatelessWidget {
  final FailedResolution? resolution;
  final VoidCallback onSet;
  const ResolutionSummaryBlock({super.key, required this.resolution, required this.onSet});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final res = resolution?.resolution ?? FailedResolution.pendingCooperativeDecision;
    final pending = res == FailedResolution.pendingCooperativeDecision;
    final color = pending ? AppConstants.warningAmber : AppConstants.programPurple;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // Beside the text when there is room; below it on a narrow card or at a large text
          // size, so the button never pushes the text off the card.
          final stacked = box.maxWidth / MediaQuery.textScalerOf(context).scale(1) < 250;
          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.gavel_rounded, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resolutionLabel(l10n, res),
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                    ),
                    if ((resolution?.note ?? '').isNotEmpty)
                      Text(
                        resolution!.note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ],
          );
          final button = TextButton(
            onPressed: onSet,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(pending ? l10n.resSet : l10n.resChange),
          );
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [info, Align(alignment: Alignment.centerRight, child: button)],
                )
              : Row(children: [Expanded(child: info), button]);
        },
      ),
    );
  }
}

// ── Return sheet ────────────────────────────────────────────────────────────

/// Opens the return in SAGANA's centered management modal (the same one Inventory, Programs and Loans use).
Future<bool?> showProgramReturnSheet(
  BuildContext context, {
  required ProgramRepository repo,
  required ProgramReturn ret,
}) {
  return showManagementModal<bool>(
    context: context,
    builder: (_) => _ReturnSheet(repo: repo, ret: ret),
  );
}

enum _ReturnMode { none, receive, adjust, close }

class _ReturnSheet extends StatefulWidget {
  final ProgramRepository repo;
  final ProgramReturn ret;
  const _ReturnSheet({required this.repo, required this.ret});

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  _ReturnMode _mode = _ReturnMode.none;
  final _qty = TextEditingController();
  final _text = TextEditingController(); // note (receipt) or reason (adjust / close)
  bool _saving = false;
  String? _error;

  ProgramReturn get r => widget.ret;

  @override
  void dispose() {
    _qty.dispose();
    _text.dispose();
    super.dispose();
  }

  void _open(_ReturnMode m) {
    setState(() {
      _mode = m;
      _error = null;
      _text.clear();
      _qty.text = m == _ReturnMode.receive
          ? formatReturnQuantity(r.remaining)
          : m == _ReturnMode.adjust
              ? formatReturnQuantity(r.dueQuantity)
              : '';
    });
  }

  Future<void> _submit() async {
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    final qty = double.tryParse(_qty.text.trim().replaceAll(',', ''));
    final text = _text.text.trim();

    String? problem;
    switch (_mode) {
      case _ReturnMode.receive:
        if (qty == null || qty <= 0) {
          problem = l10n.retQtyInvalid;
        } else if (qty > r.remaining + 0.0001) {
          problem = l10n.retQtyTooMuch;
        } else if (text.isEmpty) {
          problem = l10n.retNoteRequired;
        }
      case _ReturnMode.adjust:
        if (qty == null || qty <= 0) {
          problem = l10n.retQtyInvalid;
        } else if (qty < r.receivedQuantity) {
          problem = l10n.retQtyBelowReceived;
        } else if (text.isEmpty) {
          problem = l10n.retReasonRequired;
        }
      case _ReturnMode.close:
        if (text.isEmpty) problem = l10n.retReasonRequired;
      case _ReturnMode.none:
        return;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      switch (_mode) {
        case _ReturnMode.receive:
          await widget.repo.recordReturnReceipt(
            returnId: r.id,
            quantity: qty!,
            note: text,
          );
        case _ReturnMode.adjust:
          await widget.repo.adjustReturn(returnId: r.id, newQuantity: qty!, reason: text);
        case _ReturnMode.close:
          await widget.repo.closeReturn(returnId: r.id, reason: text);
        case _ReturnMode.none:
          break;
      }
      if (!mounted) return;
      AppToast.show(
        context,
        switch (_mode) {
          _ReturnMode.receive => l10n.retReceiptSaved,
          _ReturnMode.adjust => l10n.retAdjustSaved,
          _ => l10n.retClosedSaved,
        },
      );
      Navigator.of(context).pop(true);
    } catch (e, st) {
      if (!mounted) return;
      AppToast.show(context, friendlyError(l10n, e, st), isError: true);
      setState(() => _saving = false);
    }
  }

  String get _modeTitle {
    final l10n = AppLocalizations.of(context);
    return switch (_mode) {
      _ReturnMode.receive => l10n.retActionReceive,
      _ReturnMode.adjust => l10n.retActionAdjust,
      _ => l10n.retActionClose,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editing = r.isOpen && _mode != _ReturnMode.none;
    return ManagementModalShell(
      title: l10n.retSheetTitle,
      subtitle: [if (r.farmerName != null) r.farmerName!, if (r.programName != null) r.programName!]
          .join(' · '),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summary(l10n),
          if (r.isOpen) ...[
            const SizedBox(height: 16),
            if (_mode == _ReturnMode.none) _actions(l10n) else _form(l10n),
          ],
          const SizedBox(height: 20),
          _history(l10n),
        ],
      ),
      // The Cancel / Confirm row appears only while an action is being filled in.
      footer: editing
          ? ManagementModalActions(
              cancelLabel: l10n.retCancel,
              primaryLabel: l10n.retConfirm,
              isLoading: _saving,
              onCancel: () => setState(() => _mode = _ReturnMode.none),
              onPrimary: _saving ? null : _submit,
            )
          : null,
    );
  }

  /// What is due, what has arrived and what is left, as three figures and a progress bar.
  Widget _summary(AppLocalizations l10n) {
    final color = returnStatusColor(r.status);
    final progress =
        r.dueQuantity <= 0 ? 0.0 : (r.receivedQuantity / r.dueQuantity).clamp(0.0, 1.0);
    Widget stat(String label, double value, {bool emphasize = false}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(
                '${formatReturnQuantity(value)} ${r.unit}',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: emphasize ? color : AppConstants.onSurface,
                ),
              ),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(r.cropName,
                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
              _StatusPill(label: returnStatusLabel(l10n, r.status), color: color),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              stat(l10n.retStatDue, r.dueQuantity),
              stat(l10n.retStatReceived, r.receivedQuantity),
              stat(l10n.retStatRemaining, r.isOpen ? r.remaining : 0, emphasize: r.isOpen),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
          if (r.wasAdjusted) ...[
            const SizedBox(height: 8),
            Text(
              l10n.retOriginallyDue(formatReturnQuantity(r.originalQuantity), r.unit),
              style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant),
            ),
          ],
          if ((r.closedReason ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.closedReason!,
                style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  /// One clear main action, the two lesser ones beneath it, and where the stock goes. All three buttons
  /// share one text style and one height, so nothing shrinks or looks different from its neighbour.
  Widget _actions(AppLocalizations l10n) {
    final label = GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600);
    final secondary = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: label,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const Key('recordReceiptButton'),
            onPressed: () => _open(_ReturnMode.receive),
            icon: const Icon(Icons.add_task_rounded, size: 18),
            label: Text(l10n.retActionReceive),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48), textStyle: label),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.retReceiveInfo(r.cropName),
          style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: AppConstants.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: secondary,
                onPressed: () => _open(_ReturnMode.adjust),
                child: Text(l10n.retActionAdjust, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                style: secondary,
                onPressed: () => _open(_ReturnMode.close),
                child: Text(l10n.retActionClose, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _form(AppLocalizations l10n) {
    final isReceive = _mode == _ReturnMode.receive;
    final isClose = _mode == _ReturnMode.close;
    final info = isReceive
        ? l10n.retReceiveInfo(r.cropName)
        : (isClose ? l10n.retCloseInfo : l10n.retAdjustInfo);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_modeTitle, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          info,
          style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: AppConstants.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        if (!isClose) ...[
          LabeledTextField(
            controller: _qty,
            label: '${isReceive ? l10n.retQtyReceived(r.unit) : l10n.retNewQtyDue(r.unit)} *',
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // Numbers only (one point, at most 2 decimals). A receipt can never be typed above what is
            // still due; the database refuses it too.
            inputFormatters: [
              DecimalInputFormatter(max: isReceive ? r.remaining : null),
            ],
            suffixText: r.unit,
          ),
          const SizedBox(height: 14),
        ],
        LabeledTextField(
          controller: _text,
          label: isReceive ? l10n.retNoteLabel : l10n.retReasonLabel,
          hint: '',
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed)),
          ),
      ],
    );
  }

  /// The history as a timeline: a dot and a thin line per entry, newest first.
  Widget _history(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final events = r.events.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.retHistory,
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (events.isEmpty)
          Text(l10n.retNoHistory,
              style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant))
        else
          for (var i = 0; i < events.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 18,
                    child: Column(
                      children: [
                        const SizedBox(height: 5),
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: AppConstants.primaryGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        if (i < events.length - 1)
                          Expanded(
                            child: Container(width: 1.5, color: cs.outline.withValues(alpha: 0.25)),
                          ),
                      ],
                    ),
                  ),
                  Expanded(child: _eventTile(l10n, events[i])),
                ],
              ),
            ),
      ],
    );
  }

  Widget _eventTile(AppLocalizations l10n, ProgramReturnEvent e) {
    final qty = formatReturnQuantity;
    final text = switch (e.type) {
      'created' => l10n.retEventCreated(qty(e.quantityAfter ?? 0), r.unit),
      'adjusted' =>
        l10n.retEventAdjusted(qty(e.quantityBefore ?? 0), qty(e.quantityAfter ?? 0), r.unit),
      'receipt' => l10n.retEventReceipt(qty(e.quantity ?? 0), r.unit),
      'closed' => l10n.retEventClosed(qty(e.quantityAfter ?? 0), qty(e.quantityBefore ?? 0), r.unit),
      _ => e.type,
    };
    final d = e.at;
    final when =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
          if ((e.reason ?? '').isNotEmpty)
            Text(e.reason!, style: GoogleFonts.inter(fontSize: 11, color: AppConstants.onSurfaceVariant)),
          Text(
            [when, if ((e.actorName ?? '').isNotEmpty) l10n.retBy(e.actorName!)].join(' · '),
            style: GoogleFonts.inter(fontSize: 10, color: AppConstants.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Resolution sheet ────────────────────────────────────────────────────────

Future<bool?> showFailedResolutionSheet(
  BuildContext context, {
  required ProgramRepository repo,
  required String programMemberId,
  required String farmerName,
  FailedResolution? current,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ResolutionSheet(
      repo: repo,
      programMemberId: programMemberId,
      farmerName: farmerName,
      current: current,
    ),
  );
}

class _ResolutionSheet extends StatefulWidget {
  final ProgramRepository repo;
  final String programMemberId;
  final String farmerName;
  final FailedResolution? current;
  const _ResolutionSheet({
    required this.repo,
    required this.programMemberId,
    required this.farmerName,
    this.current,
  });

  @override
  State<_ResolutionSheet> createState() => _ResolutionSheetState();
}

class _ResolutionSheetState extends State<_ResolutionSheet> {
  late String _choice =
      widget.current?.resolution ?? FailedResolution.pendingCooperativeDecision;
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    // A note is required for the three decisions; optional while still pending.
    if (_note.text.trim().isEmpty && _choice != FailedResolution.pendingCooperativeDecision) {
      setState(() => _error = l10n.resNoteRequired);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.recordFailedResolution(
        programMemberId: widget.programMemberId,
        resolution: _choice,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      AppToast.show(context, l10n.resSaved);
      Navigator.of(context).pop(true);
    } catch (e, st) {
      if (!mounted) return;
      AppToast.show(context, friendlyError(l10n, e, st), isError: true);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + inset),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.resTitle,
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(widget.farmerName,
                style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 10),
            Text(l10n.resInfo,
                style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: AppConstants.onSurfaceVariant)),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _choice,
              onChanged: (v) {
                if (!_saving && v != null) setState(() => _choice = v);
              },
              child: Column(
                children: [
                  for (final res in FailedResolution.all)
                    RadioListTile<String>(
                      value: res,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(resolutionLabel(l10n, res),
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              enabled: !_saving,
              maxLines: 3,
              maxLength: 400,
              decoration: InputDecoration(
                labelText: _choice == FailedResolution.pendingCooperativeDecision
                    ? l10n.outcDecisionNoteLabel
                    : l10n.resNoteLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: GoogleFonts.inter(fontSize: 12, color: AppConstants.errorRed)),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(l10n.resSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
