import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../widgets/view_only_banner.dart';
import '../../../data/models/program_return_model.dart';
import '../../widgets/program_return_panel.dart' show resolutionLabel;
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../data/models/program_outcome_model.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/services/outcome_evidence_service.dart';
import '../../../data/services/staff_permission_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/outcome_photo_picker.dart';
import '../../widgets/program_history_sheet.dart';
import '../../widgets/request_card.dart';
import '../../widgets/sub_page_top_bar.dart';

/// One outcome report, as a full page: the Farmer's report and photos, then the
/// three steps — evidence review (Manager or Officer), field verification
/// (Officer only) and the final decision. The reviewer and the verifier must be
/// two different people; the database enforces that, and this page explains it
/// instead of offering an action that would be refused.
/// Route: /admin/programs/outcomes/detail
class ProgramOutcomeDetailScreen extends StatefulWidget {
  final OutcomeReport report;
  const ProgramOutcomeDetailScreen({super.key, required this.report});

  @override
  State<ProgramOutcomeDetailScreen> createState() =>
      _ProgramOutcomeDetailScreenState();
}

class _ProgramOutcomeDetailScreenState
    extends State<ProgramOutcomeDetailScreen> {
  final _repo = ProgramRepository();
  late OutcomeReport _r = widget.report;
  Map<String, String> _urls = {};
  bool _busy = false;

  // Evidence review
  bool? _validate;
  final _reviewNote = TextEditingController();
  String? _reviewError;

  // Field verification
  bool? _confirms;
  DateTime _visitDate = DateTime.now();
  final _measuredQty = TextEditingController();
  String? _measuredUnit;
  final _verifyNote = TextEditingController();
  List<PickedPhoto> _fieldPhotos = [];
  String? _verifyError;

  // Final decision
  bool? _finalSuccessful;
  // The cooperative's current decision on a Failed outcome, and the choice staff make while it is still pending.
  FailedResolution? _resolution;
  String? _newDecision;
  final _newDecisionNote = TextEditingController();
  String? _newDecisionError;
  final _finalNote = TextEditingController();
  String? _finalError;
  // Successful (Harvest Return): what the Farmer must return, decided by the
  // reviewer after the field verification.
  final _returnQty = TextEditingController();
  String? _returnUnit;
  // Failed: one of the four cooperative decisions, with a note.
  String? _decision;
  final _decisionNote = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The measured quantity is in the unit of the item that was given (the Inventory
    // item's unit) and that unit is not chosen here. Only an old record whose item is
    // unknown falls back to the unit the Farmer reported.
    _measuredUnit = unitOrDefault(_r.itemUnit ?? _r.quantityUnit);
    // The return is added back to the item that was given, so it uses that item's unit.
    _returnUnit = _r.itemUnit;
    // Pre-filled with what was agreed for this Farmer (member, else the program default); staff confirm or change it.
    final agreed = _r.agreedReturnQuantity;
    if (agreed != null) {
      _returnQty.text = agreed == agreed.roundToDouble()
          ? agreed.toStringAsFixed(0)
          : agreed.toStringAsFixed(2);
    }
    _loadUrls();
    _reload(silent: true);
    _loadResolution();
  }

  @override
  void dispose() {
    _newDecisionNote.dispose();
    _reviewNote.dispose();
    _measuredQty.dispose();
    _verifyNote.dispose();
    _finalNote.dispose();
    _returnQty.dispose();
    _decisionNote.dispose();
    super.dispose();
  }

  Future<void> _loadUrls() async {
    final urls = await _repo.evidenceUrls(
      _r.photos.map((p) => p.path).toList(),
    );
    if (mounted) setState(() => _urls = urls);
  }

  Future<void> _reload({bool silent = false}) async {
    try {
      final all = await _repo.fetchOutcomeReports(programId: _r.programId);
      final fresh = all.where((x) => x.id == _r.id).firstOrNull;
      if (fresh != null && mounted) {
        setState(() => _r = fresh);
        _loadUrls();
      }
    } catch (_) {
      if (!silent && mounted) {
        AppToast.show(
          context,
          AppLocalizations.of(context).outcLoadFailed,
          isError: true,
        );
      }
    }
  }

  /// Runs a staff action: guarded by the module permission, one at a time, with
  /// the database's own reason shown if it refuses.
  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    if (!requireManage(context, StaffModule.dashboard)) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      AppToast.show(context, success);
      await _reload();
    } on OutcomeActionException catch (e) {
      if (mounted) {
        AppToast.show(context, friendlyError(l10n, e), isError: true);
      }
    } catch (_) {
      if (mounted) AppToast.show(context, l10n.outcActionFailed, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _submitReview() async {
    final l10n = AppLocalizations.of(context);
    if (_validate == null) {
      setState(() => _reviewError = l10n.outcChooseDecision);
      return;
    }
    // The note is required either way: why it is validated, or what the Farmer must fix.
    if (_reviewNote.text.trim().isEmpty) {
      setState(
        () => _reviewError = _validate!
            ? l10n.outcReviewNoteRequired
            : l10n.outcReturnNoteRequired,
      );
      return;
    }
    setState(() => _reviewError = null);
    await _run(
      () => _repo.reviewOutcome(
        reportId: _r.id,
        validate: _validate!,
        note: _reviewNote.text.trim(),
      ),
      _validate! ? l10n.outcReviewValidated : l10n.outcReviewReturned,
    );
  }

  Future<void> _submitVerification() async {
    final l10n = AppLocalizations.of(context);
    if (_confirms == null) {
      setState(() => _verifyError = l10n.outcChooseFinding);
      return;
    }
    final qty = double.tryParse(_measuredQty.text.trim());
    if (_r.isSuccessfulReport &&
        (qty == null || qty <= 0 || _measuredUnit == null)) {
      setState(() => _verifyError = l10n.outcMeasuredRequired);
      return;
    }
    if (_verifyNote.text.trim().isEmpty) {
      setState(() => _verifyError = l10n.outcVerifyNoteRequired);
      return;
    }
    if (_fieldPhotos.isEmpty) {
      setState(() => _verifyError = l10n.outcFieldPhotosRequired);
      return;
    }
    setState(() => _verifyError = null);
    await _run(
      () => _repo.verifyOutcome(
        reportId: _r.id,
        confirms: _confirms!,
        measuredQuantity: _r.isSuccessfulReport ? qty : null,
        measuredUnit: _r.isSuccessfulReport ? _measuredUnit : null,
        fieldVisitDate: _visitDate,
        note: _verifyNote.text.trim(),
        photos: _fieldPhotos,
      ),
      l10n.outcVerified,
    );
  }

  /// The final outcome the field verification already decides, or null when the Manager chooses:
  ///   confirmed                        -> what the Farmer reported
  ///   disputed, reported Failed        -> Successful (it did not fail)
  ///   disputed, reported Successful    -> the Manager chooses (less than claimed, or nothing there)
  bool? _lockedFinalOutcome(OutcomeReport r) {
    if (!r.disputed) return r.isSuccessfulReport;
    if (!r.isSuccessfulReport) return true;
    return null;
  }

  bool _finalIsSuccessful(OutcomeReport r) =>
      _lockedFinalOutcome(r) ?? _finalSuccessful ?? r.isSuccessfulReport;

  Future<void> _submitFinal() async {
    final l10n = AppLocalizations.of(context);
    final successful = _finalIsSuccessful(_r);
    if (_finalNote.text.trim().isEmpty) {
      setState(() => _finalError = l10n.outcFinalNoteRequired);
      return;
    }
    // The quantity to return (Successful) or the decision (Failed) is entered
    // here, after the verification. Nothing is filled in for the reviewer.
    final qty = double.tryParse(_returnQty.text.trim());
    if (successful && _r.isHarvestReturn) {
      if (qty == null || qty <= 0 || _returnUnit == null) {
        setState(() => _finalError = l10n.outcReturnQtyRequired);
        return;
      }
    }
    if (!successful) {
      if (_decision == null) {
        setState(() => _finalError = l10n.outcDecisionRequired);
        return;
      }
      if (_decisionNote.text.trim().isEmpty) {
        setState(() => _finalError = l10n.outcDecisionNoteRequired);
        return;
      }
    }
    setState(() => _finalError = null);
    await _run(
      () async {
        await _repo.finalizeOutcome(
          reportId: _r.id,
          successful: successful,
          note: _finalNote.text.trim(),
          returnQuantity: successful && _r.isHarvestReturn ? qty : null,
          returnUnit: successful && _r.isHarvestReturn ? _returnUnit : null,
          resolution: successful ? null : _decision,
          resolutionNote: _decisionNote.text.trim().isEmpty
              ? null
              : _decisionNote.text.trim(),
        );
        // The decision was recorded together with the outcome; read it back so the screen shows it now
        // (it was only read when the screen opened, so it kept showing "Pending Cooperative Decision").
        if (!successful) await _loadResolution();
      },
      successful && _r.isHarvestReturn
          ? l10n.outcFinalizedReturnDue
          : l10n.outcFinalized,
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  String _fmt(DateTime d) {
    final m = [
      AppLocalizations.of(context).enhJan,
      AppLocalizations.of(context).enhFeb,
      AppLocalizations.of(context).enhMar,
      AppLocalizations.of(context).enhApr,
      AppLocalizations.of(context).adminCalMonthMay,
      AppLocalizations.of(context).enhJun,
      AppLocalizations.of(context).enhJul,
      AppLocalizations.of(context).enhAug,
      AppLocalizations.of(context).enhSep,
      AppLocalizations.of(context).enhOct,
      AppLocalizations.of(context).enhNov,
      AppLocalizations.of(context).enhDec,
    ];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String _by(AppLocalizations l10n, String? name, String? role, DateTime? at) {
    final who = (name == null || name.trim().isEmpty)
        ? l10n.programHistActorUnrecorded
        : '$name${role == null ? '' : ' (${ProgramHistoryText.roleLabel(l10n, role)})'}';
    return at == null ? who : '$who · ${_fmt(at)}';
  }

  Widget _card(
    String title,
    IconData icon,
    List<Widget> children, {
    Color? accent,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = accent ?? AppConstants.primaryGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _notice(
    String text, {
    Color? color,
    IconData icon = Icons.info_outline_rounded,
  }) {
    final c = color ?? AppConstants.buyerBlue;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photos(List<OutcomePhoto> photos) {
    if (photos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in photos)
            GestureDetector(
              onTap: _urls[p.path] == null
                  ? null
                  : () => _viewPhoto(_urls[p.path]!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: _urls[p.path] == null
                      ? Container(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_outlined,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Image.network(
                          _urls[p.path]!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _viewPhoto(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            InteractiveViewer(child: Center(child: Image.network(url))),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choice(
    String label,
    bool selected,
    Color color,
    VoidCallback? onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: selected
                  ? color
                  : Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.3),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected
                  ? color
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _error(String? e) => e == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            e,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppConstants.errorRed,
            ),
          ),
        );

  Widget _submitButton(String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _busy ? null : onTap,
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    ),
  );

  // ─── Sections ────────────────────────────────────────────────────────────

  // Labels carry a required-field star on the Farmer's form; not when displayed.
  String _plain(String s) => s.replaceAll(RegExp(r'\s*\*$'), '');

  Widget _reportCard(AppLocalizations l10n) {
    final r = _r;
    final item = r.itemName == null
        ? null
        : '${r.quantityGiven == null ? '' : '${_num(r.quantityGiven!)} '}${r.itemName}';
    return _card(l10n.outcFarmerReport, Icons.assignment_outlined, [
      RequestDetailRow(label: l10n.reqFarmer, value: r.farmerName),
      RequestDetailRow(label: l10n.reqProgram, value: r.programName),
      if (item != null) RequestDetailRow(label: l10n.reqReceived, value: item),
      RequestDetailRow(
        label: l10n.outcReportedOutcome,
        value: r.isSuccessfulReport
            ? l10n.outcStatusSuccessful
            : l10n.outcStatusFailed,
        valueColor: r.isSuccessfulReport
            ? AppConstants.successGreen
            : AppConstants.errorRed,
      ),
      RequestDetailRow(label: l10n.outcSubmittedOn, value: _fmt(r.submittedAt)),
      if (r.plantedDate != null)
        RequestDetailRow(
          label: _plain(l10n.outcPlantedDate),
          value: _fmt(r.plantedDate!),
        ),
      if (r.isSuccessfulReport) ...[
        if (r.quantityHarvested != null)
          RequestDetailRow(
            label: _plain(l10n.outcQtyHarvested),
            value: '${_num(r.quantityHarvested!)} ${r.quantityUnit ?? ''}'
                .trim(),
            emphasize: true,
          ),
        if (r.harvestDate != null)
          RequestDetailRow(
            label: _plain(l10n.outcHarvestDate),
            value: _fmt(r.harvestDate!),
          ),
      ] else ...[
        if (r.failureCause != null)
          RequestDetailRow(
            label: _plain(l10n.outcFailureCause),
            value: r.failureCause!,
          ),
        if (r.failureDate != null)
          RequestDetailRow(
            label: _plain(l10n.outcFailureDate),
            value: _fmt(r.failureDate!),
          ),
      ],
      if (r.areaPlanted != null)
        RequestDetailRow(
          label: l10n.outcAreaPlanted,
          value:
              '${_num(r.areaPlanted!)} ${r.areaUnit == 'hectare' ? l10n.outcAreaUnitHa : l10n.outcAreaUnitSqm}',
        ),
      const SizedBox(height: 8),
      Text(
        _plain(l10n.outcExplanation),
        style: GoogleFonts.inter(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 2),
      Text(r.explanation, style: GoogleFonts.inter(fontSize: 13, height: 1.4)),
      const SizedBox(height: 10),
      Text(
        _plain(l10n.outcEvidence),
        style: GoogleFonts.inter(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      _photos(r.farmerPhotos),
    ]);
  }

  Widget _reviewCard(AppLocalizations l10n) {
    final r = _r;
    final children = <Widget>[];
    if (r.reviewDecision != null) {
      final ok = r.isReviewed;
      children.addAll([
        RequestDetailRow(
          label: l10n.outcDecision,
          value: ok ? l10n.outcDecisionValidated : l10n.outcDecisionReturned,
          valueColor: ok ? AppConstants.successGreen : AppConstants.errorRed,
        ),
        RequestDetailRow(
          label: l10n.outcDoneBy,
          value: _by(l10n, r.reviewedByName, r.reviewedByRole, r.reviewedAt),
        ),
        if (r.reviewNote != null && r.reviewNote!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '"${r.reviewNote}"',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ]);
    } else if (!r.isPending) {
      children.add(_notice(l10n.outcNotAvailable));
    } else {
      children.addAll([
        Text(
          l10n.outcReviewHelp,
          style: GoogleFonts.inter(
            fontSize: 12,
            height: 1.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _choice(
              l10n.outcValidate,
              _validate == true,
              AppConstants.successGreen,
              _busy
                  ? null
                  : () => setState(() {
                      _validate = true;
                      _reviewError = null;
                    }),
            ),
            const SizedBox(width: 10),
            _choice(
              l10n.outcReturnToFarmer,
              _validate == false,
              AppConstants.errorRed,
              _busy
                  ? null
                  : () => setState(() {
                      _validate = false;
                      _reviewError = null;
                    }),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _reviewNote,
          maxLines: 2,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: _validate == false
                ? l10n.outcReturnNoteLabel
                : l10n.outcReviewNoteLabel,
          ),
        ),
        _error(_reviewError),
        _submitButton(l10n.outcSaveReview, _submitReview),
      ]);
    }
    return _card(
      l10n.outcStepReview,
      Icons.rule_rounded,
      children,
      accent: r.isReviewed ? AppConstants.successGreen : AppConstants.buyerBlue,
    );
  }

  Widget _verificationCard(AppLocalizations l10n) {
    final r = _r;
    final children = <Widget>[];
    if (r.isVerified) {
      children.addAll([
        RequestDetailRow(
          label: l10n.outcFinding,
          value: r.disputed
              ? l10n.outcFindingDisputes
              : l10n.outcFindingConfirms,
          valueColor: r.disputed
              ? AppConstants.errorRed
              : AppConstants.successGreen,
        ),
        RequestDetailRow(
          label: l10n.outcDoneBy,
          value: _by(l10n, r.verifiedByName, r.verifiedByRole, r.verifiedAt),
        ),
        if (r.fieldVisitDate != null)
          RequestDetailRow(
            label: l10n.outcVisitDate,
            value: _fmt(r.fieldVisitDate!),
          ),
        if (r.verifiedQuantity != null) ...[
          RequestDetailRow(
            label: l10n.outcMeasured,
            value: '${_num(r.verifiedQuantity!)} ${r.verifiedUnit ?? ''}'
                .trim(),
            emphasize: true,
          ),
          if (r.quantityHarvested != null)
            RequestDetailRow(
              label: l10n.outcFarmerReported,
              value: '${_num(r.quantityHarvested!)} ${r.quantityUnit ?? ''}'
                  .trim(),
            ),
        ],
        if (r.verificationNote != null && r.verificationNote!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '"${r.verificationNote}"',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        _photos(r.fieldPhotos),
      ]);
    } else if (!r.isPending) {
      children.add(_notice(l10n.outcNotAvailable));
    } else if (!r.isReviewed) {
      // One order: the evidence review is submitted first; only then does the field verification open.
      children.add(_notice(l10n.outcVerifyAfterReview));
    } else {
      children.addAll([
        Text(
          l10n.outcVerifyHelp,
          style: GoogleFonts.inter(
            fontSize: 12,
            height: 1.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _choice(
              l10n.outcFindingConfirms,
              _confirms == true,
              AppConstants.successGreen,
              _busy
                  ? null
                  : () => setState(() {
                      _confirms = true;
                      _verifyError = null;
                    }),
            ),
            const SizedBox(width: 10),
            _choice(
              l10n.outcFindingDisputes,
              _confirms == false,
              AppConstants.errorRed,
              _busy
                  ? null
                  : () => setState(() {
                      _confirms = false;
                      _verifyError = null;
                    }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _busy
              ? null
              : () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _visitDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _visitDate = d);
                },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.outcVisitDate,
              suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
            ),
            child: Text(
              _fmt(_visitDate),
              style: GoogleFonts.inter(fontSize: 14),
            ),
          ),
        ),
        if (r.isSuccessfulReport) ...[
          const SizedBox(height: 12),
          Text(
            l10n.outcMeasuredHint,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          // Only the quantity is entered. The unit is the item's and is shown beside it.
          TextField(
            key: const Key('measuredQuantityField'),
            controller: _measuredQty,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [DecimalInputFormatter()],
            decoration: InputDecoration(
              labelText: l10n.outcMeasuredLabel,
              hintText: '0.00',
              suffixText: _measuredUnit,
            ),
          ),
          if (r.quantityHarvested != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.outcFarmerReportedLine(
                  '${_num(r.quantityHarvested!)} ${r.quantityUnit ?? ''}'
                      .trim(),
                ),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _verifyNote,
          maxLines: 3,
          enabled: !_busy,
          decoration: InputDecoration(labelText: l10n.outcVerifyNoteLabel),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.outcFieldPhotos,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        OutcomePhotoPicker(
          photos: _fieldPhotos,
          onChanged: (p) => setState(() => _fieldPhotos = p),
        ),
        _error(_verifyError),
        _submitButton(l10n.outcSaveVerification, _submitVerification),
      ]);
    }
    return _card(
      l10n.outcStepVerify,
      Icons.agriculture_outlined,
      children,
      accent: r.isVerified ? AppConstants.successGreen : AppConstants.buyerBlue,
    );
  }

  // Successful Harvest Return: the reviewer decides what the Farmer returns.
  List<Widget> _returnInputs(AppLocalizations l10n) => [
    Text(
      l10n.outcReturnSection,
      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 4),
    Text(
      l10n.outcReturnSectionHelp(_r.returnItemName ?? ''),
      style: GoogleFonts.inter(
        fontSize: 12,
        height: 1.4,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: 10),
    // Only the quantity is entered. The unit is the returned item's own (the one set when it was
    // distributed) and is shown beside the number, not chosen.
    TextField(
      key: const Key('returnQuantityField'),
      controller: _returnQty,
      enabled: !_busy,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [DecimalInputFormatter()],
      decoration: InputDecoration(
        labelText: l10n.outcReturnQtyLabel,
        hintText: '0.00',
        suffixText: _returnUnit,
      ),
    ),
    const SizedBox(height: 12),
  ];

  // Failed: the four cooperative decisions. None is chosen for the reviewer.
  List<Widget> _decisionInputs(AppLocalizations l10n) => [
    Text(
      l10n.outcDecisionSection,
      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 4),
    Text(
      l10n.outcDecisionHelp,
      style: GoogleFonts.inter(
        fontSize: 12,
        height: 1.4,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
    RadioGroup<String>(
      groupValue: _decision,
      onChanged: (v) {
        if (!_busy && v != null) setState(() => _decision = v);
      },
      // The card around these rows has a background colour, which would hide the rows' own ink and
      // background (Flutter's "ListTile background color or ink splashes may be invisible"). Giving them
      // their own transparent Material layer fixes that.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final res in FailedResolution.all)
              RadioListTile<String>(
                value: res,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  resolutionLabel(l10n, res),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    TextField(
      controller: _decisionNote,
      maxLines: 2,
      enabled: !_busy,
      decoration: InputDecoration(labelText: '${l10n.outcDecisionNoteLabel} *'),
    ),
    const SizedBox(height: 12),
  ];

  // ─── Cooperative decision on a Failed outcome ────────────────────────────

  Future<void> _loadResolution() async {
    try {
      final all = await _repo.fetchResolutions(programId: _r.programId);
      final mine = all.where((x) => x.programMemberId == _r.programMemberId).firstOrNull;
      if (mounted) setState(() => _resolution = mine);
    } catch (_) {
      // The decision line is simply left out if it cannot be read.
    }
  }

  Future<void> _submitNewDecision() async {
    final l10n = AppLocalizations.of(context);
    if (_newDecision == null) {
      setState(() => _newDecisionError = l10n.outcDecisionRequired);
      return;
    }
    if (_newDecisionNote.text.trim().isEmpty) {
      setState(() => _newDecisionError = l10n.outcDecisionNoteRequired);
      return;
    }
    setState(() => _newDecisionError = null);
    final chosen = _newDecision!;
    final note = _newDecisionNote.text.trim();
    await _run(() async {
      await _repo.recordFailedResolution(
        programMemberId: _r.programMemberId,
        resolution: chosen,
        note: note,
      );
      _newDecision = null;
      _newDecisionNote.clear();
      await _loadResolution();
    }, l10n.resSaved);
  }

  /// The current cooperative decision, and, while it is still "Pending Cooperative Decision", the other three
  /// options so staff can make the decision when the cooperative is ready.
  List<Widget> _resolutionSection(AppLocalizations l10n) {
    final res = _resolution?.resolution ?? FailedResolution.pendingCooperativeDecision;
    final pending = res == FailedResolution.pendingCooperativeDecision;
    final cs = Theme.of(context).colorScheme;
    final options = [
      FailedResolution.closedNoFurtherObligation,
      FailedResolution.eligibleForReassessment,
      FailedResolution.referredForLoanAssessment,
    ];
    return [
      RequestDetailRow(
        label: l10n.outcDecisionSection,
        value: resolutionLabel(l10n, res),
        valueColor: pending ? AppConstants.warningAmber : AppConstants.programPurple,
      ),
      if ((_resolution?.note ?? '').trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '"${_resolution!.note}"',
            style: GoogleFonts.inter(fontSize: 13, fontStyle: FontStyle.italic),
          ),
        ),
      if (pending) ...[
        const SizedBox(height: 14),
        Text(
          l10n.outcPendingChoose,
          style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
        ),
        RadioGroup<String>(
          groupValue: _newDecision,
          onChanged: (v) {
            if (!_busy && v != null) setState(() => _newDecision = v);
          },
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (final o in options)
                  RadioListTile<String>(
                    value: o,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      resolutionLabel(l10n, o),
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ),
        TextField(
          controller: _newDecisionNote,
          maxLines: 2,
          enabled: !_busy,
          decoration: InputDecoration(labelText: '${l10n.outcDecisionNoteLabel} *'),
        ),
        _error(_newDecisionError),
        _submitButton(l10n.resSave, _submitNewDecision),
      ],
    ];
  }

  Widget _finalCard(AppLocalizations l10n) {
    final r = _r;
    final children = <Widget>[];
    if (r.isFinalized) {
      final failed = r.finalOutcome == 'failed';
      children.addAll([
        RequestDetailRow(
          label: l10n.outcFinalOutcome,
          value: failed ? l10n.outcStatusFailed : l10n.outcStatusSuccessful,
          valueColor: failed
              ? AppConstants.errorRed
              : AppConstants.successGreen,
          emphasize: true,
        ),
        RequestDetailRow(
          label: l10n.outcDoneBy,
          value: _by(l10n, r.finalizedByName, r.finalizedByRole, r.finalizedAt),
        ),
        if (r.finalNote != null && r.finalNote!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '"${r.finalNote}"',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (failed) ...[
          const SizedBox(height: 10),
          ..._resolutionSection(l10n),
        ],
      ]);
    } else if (r.isReturned) {
      children.add(
        _notice(l10n.outcReturnedInfo, color: AppConstants.errorRed),
      );
    } else if (r.stage != OutcomeStage.readyToFinalize) {
      children.add(_notice(l10n.outcFinalWaiting));
    } else {
      final locked = _lockedFinalOutcome(r);
      final successful = _finalIsSuccessful(r);
      children.addAll([
        if (r.disputed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _notice(
              l10n.outcDisputedInfo,
              color: AppConstants.warningAmber,
            ),
          ),
        if (locked == null)
          // Disputed success: the Manager chooses.
          Row(
            children: [
              _choice(
                l10n.outcStatusSuccessful,
                successful,
                AppConstants.successGreen,
                _busy ? null : () => setState(() => _finalSuccessful = true),
              ),
              const SizedBox(width: 10),
              _choice(
                l10n.outcStatusFailed,
                !successful,
                AppConstants.errorRed,
                _busy ? null : () => setState(() => _finalSuccessful = false),
              ),
            ],
          )
        else
          // Already decided by the field verification: no buttons, just the result and why.
          RequestDetailRow(
            key: const Key('lockedFinalOutcome'),
            label: l10n.outcFinalOutcome,
            value: successful
                ? l10n.outcStatusSuccessful
                : l10n.outcStatusFailed,
            valueColor: successful
                ? AppConstants.successGreen
                : AppConstants.errorRed,
            emphasize: true,
          ),
        if (locked != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              r.disputed
                  ? l10n.outcFinalLockedDisputed
                  : l10n.outcFinalLockedConfirmed,
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 10),
        if (successful && r.isHarvestReturn) ..._returnInputs(l10n),
        if (!successful) ..._decisionInputs(l10n),
        TextField(
          controller: _finalNote,
          maxLines: 2,
          enabled: !_busy,
          decoration: InputDecoration(labelText: l10n.outcFinalNoteLabel),
        ),
        _error(_finalError),
        _notice(l10n.outcFinalNoLoan),
        _submitButton(l10n.outcFinalize, _submitFinal),
      ]);
    }
    return _card(
      l10n.outcStepFinal,
      Icons.flag_outlined,
      children,
      accent: r.isFinalized
          ? AppConstants.successGreen
          : AppConstants.buyerBlue,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            SubPageTopBar(
              title: l10n.outcDetailTitle,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
                  children: [
                    _reportCard(l10n),
                    _reviewCard(l10n),
                    _verificationCard(l10n),
                    _finalCard(l10n),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
