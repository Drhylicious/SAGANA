import '../../../core/theme/sagana_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/app_error_message.dart';
import '../../../data/models/farmer_profile_model.dart';
import '../../../data/models/program_outcome_model.dart';
import '../../../data/repositories/farmer_program_repository.dart';
import '../../../data/services/outcome_evidence_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/outcome_photo_picker.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/top_bar_spacer.dart';

/// A Farmer reports the outcome of a program item they received: Successful or
/// Failed, with production information, an explanation and 1-5 photos (camera
/// or gallery). Staff then review it and an Officer verifies it in the field.
/// Pops with `true` once the report is filed.
class ReportOutcomeScreen extends StatefulWidget {
  final MyProgramEntry entry;

  /// The staff note from an earlier, returned report (shown at the top).
  final String? returnNote;

  const ReportOutcomeScreen({super.key, required this.entry, this.returnNote});

  @override
  State<ReportOutcomeScreen> createState() => _ReportOutcomeScreenState();
}

class _ReportOutcomeScreenState extends State<ReportOutcomeScreen> {
  final _repo = FarmerProgramRepository();
  final _formKey = GlobalKey<FormState>();
  final _quantityCtrl = TextEditingController();
  final _explanationCtrl = TextEditingController();
  final _causeCtrl = TextEditingController();

  String? _outcome; // 'successful' | 'failed'
  // The unit is not asked: it is the unit of what the Farmer returns (the produce for seeds), else the
  // unit of the item they were given, so the quantity is always in the unit the cooperative expects.
  late final String? _unit =
      widget.entry.returnUnitShown ?? widget.entry.itemUnit;
  DateTime? _plantedDate;
  DateTime? _harvestDate;
  DateTime? _failureDate;
  List<PickedPhoto> _photos = [];
  bool _saving = false;
  bool _outcomeError = false;
  bool _photoError = false;

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _explanationCtrl.dispose();
    _causeCtrl.dispose();
    super.dispose();
  }

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

  Future<DateTime?> _pickDate(DateTime? initial) => showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2020),
    lastDate: DateTime.now(),
  );

  Future<void> _submit() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final formOk = _formKey.currentState!.validate();
    final outcomeOk = _outcome != null;
    final photosOk = _photos.isNotEmpty;
    setState(() {
      _outcomeError = !outcomeOk;
      _photoError = !photosOk;
    });
    if (!formOk || !outcomeOk || !photosOk) return;
    if (_plantedDate != null &&
        _harvestDate != null &&
        _harvestDate!.isBefore(_plantedDate!)) {
      AppToast.show(context, l10n.outcHarvestBeforePlanting, isError: true);
      return;
    }

    if (_outcome == 'successful' && (_unit ?? '').trim().isEmpty) {
      // The item's unit is not known, so there is nothing to report the quantity in.
      AppToast.show(context, l10n.outcSubmitFailed, isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final successful = _outcome == 'successful';
      await _repo.submitOutcomeReport(
        programMemberId: widget.entry.id,
        outcome: _outcome!,
        explanation: _explanationCtrl.text.trim(),
        plantedDate: _plantedDate,
        harvestDate: successful ? _harvestDate : null,
        quantity: successful ? double.tryParse(_quantityCtrl.text) : null,
        unit: successful ? _unit : null,
        failureCause: successful ? null : _causeCtrl.text.trim(),
        failureDate: successful ? null : _failureDate,
        photos: _photos,
      );
      if (!mounted) return;
      AppToast.show(context, l10n.outcSubmitted);
      Navigator.of(context).pop(true);
    } on OutcomeActionException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, friendlyError(l10n, e), isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, l10n.outcSubmitFailed, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final e = widget.entry;
    final received =
        '${e.quantityGiven != null ? formatQuantity(e.quantityGiven!) : ''}'
        '${e.itemUnit != null ? ' ${e.itemUnit}' : ''}'
        '${e.itemName != null ? ' ${e.itemName}' : ''}';

    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Stack(
        children: [
          Column(
            children: [
              const TopBarSpacer(height: 64),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    children: [
                      Text(
                        e.programName,
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (e.isDistributed)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            l10n.outcReceivedLine(received.trim()),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (widget.returnNote != null &&
                          widget.returnNote!.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppConstants.errorRed.withValues(
                              alpha: 0.07,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusMd,
                            ),
                            border: Border.all(
                              color: AppConstants.errorRed.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.outcReturnedBanner,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppConstants.errorRed,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.returnNote!,
                                style: GoogleFonts.inter(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _label(l10n.outcWhatHappened),
                      const SizedBox(height: 8),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _OutcomeOption(
                                icon: Icons.trending_up_rounded,
                                title: l10n.outcSuccessful,
                                hint: l10n.outcSuccessfulHint,
                                color: AppConstants.successGreen,
                                selected: _outcome == 'successful',
                                onTap: () => setState(() {
                                  _outcome = 'successful';
                                  _outcomeError = false;
                                }),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _OutcomeOption(
                                icon: Icons.trending_down_rounded,
                                title: l10n.outcFailed,
                                hint: l10n.outcFailedHint,
                                color: AppConstants.errorRed,
                                selected: _outcome == 'failed',
                                onTap: () => setState(() {
                                  _outcome = 'failed';
                                  _outcomeError = false;
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_outcomeError)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            l10n.outcPickOutcome,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppConstants.errorRed,
                            ),
                          ),
                        ),
                      if (_outcome != null) ...[
                        const SizedBox(height: 20),
                        _label(l10n.outcProduction),
                        const SizedBox(height: 8),
                        if (_outcome == 'successful') ...[
                          // One full-width field in the same style as the others. The unit is shown after the
                          // number but is not chosen here.
                          _Labeled(
                            label: l10n.outcQtyHarvested,
                            child: TextFormField(
                              controller: _quantityCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: const [DecimalInputFormatter()],
                              decoration: InputDecoration(
                                hintText: '0.00',
                                suffixText: _unit,
                              ),
                              validator: (v) => (v ?? '').trim().isEmpty
                                  ? l10n.outcQtyRequired
                                  : quantityErrorText(v),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _DateFormField(
                            label: l10n.outcHarvestDate,
                            value: _harvestDate,
                            format: _fmt,
                            requiredMessage: l10n.outcDateRequired,
                            onPick: () async {
                              final d = await _pickDate(_harvestDate);
                              if (d != null) setState(() => _harvestDate = d);
                            },
                          ),
                        ] else ...[
                          _Labeled(
                            label: l10n.outcFailureCause,
                            child: TextFormField(
                              controller: _causeCtrl,
                              maxLines: 2,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: l10n.outcFailureCauseHint,
                              ),
                              validator: (v) => (v ?? '').trim().isEmpty
                                  ? l10n.outcCauseRequired
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _DateFormField(
                            label: l10n.outcFailureDate,
                            value: _failureDate,
                            format: _fmt,
                            requiredMessage: l10n.outcDateRequired,
                            onPick: () async {
                              final d = await _pickDate(_failureDate);
                              if (d != null) setState(() => _failureDate = d);
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        _DateFormField(
                          label: l10n.outcPlantedDate,
                          value: _plantedDate,
                          format: _fmt,
                          requiredMessage: l10n.outcDateRequired,
                          onPick: () async {
                            final d = await _pickDate(_plantedDate);
                            if (d != null) setState(() => _plantedDate = d);
                          },
                        ),
                        const SizedBox(height: 20),
                        _label(l10n.outcExplanation),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _explanationCtrl,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: _outcome == 'successful'
                                ? l10n.outcExplanationHintSuccess
                                : l10n.outcExplanationHintFail,
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? l10n.outcExplanationRequired
                              : null,
                        ),
                        const SizedBox(height: 20),
                        _label(l10n.outcEvidence),
                        const SizedBox(height: 2),
                        Text(
                          l10n.outcEvidenceHelp,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            height: 1.4,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutcomePhotoPicker(
                          photos: _photos,
                          hasError: _photoError,
                          onChanged: (p) => setState(() {
                            _photos = p;
                            if (p.isNotEmpty) _photoError = false;
                          }),
                        ),
                        if (_photoError)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              l10n.outcPhotoRequired,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppConstants.errorRed,
                              ),
                            ),
                          ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _submit,
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(l10n.outcSubmit),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.outcWhatNext,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            height: 1.4,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FarmerTopBar(
              title: l10n.outcReportTitle,
              onBack: () => Navigator.of(context).pop(),
              hideProfileAvatar: true,
              onProfileTap: () {},
              onNotificationTap: () {},
              showNotificationButton: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String s) => Text(
    s,
    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700),
  );
}

class _OutcomeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _OutcomeOption({
    required this.icon,
    required this.title,
    required this.hint,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.10)
              : context.saganaColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: selected
                ? color
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected
                    ? color
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              style: GoogleFonts.inter(
                fontSize: 11,
                height: 1.35,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small label above a field, the same pattern as the Quantity | Unit field.
class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labeled({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// A required date: label above, a full-width tappable box, and a message under
/// it when it is still empty on Submit (it takes part in the form's validation).
class _DateFormField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final String Function(DateTime) format;
  final String requiredMessage;
  final VoidCallback onPick;
  const _DateFormField({
    required this.label,
    required this.value,
    required this.format,
    required this.requiredMessage,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FormField<DateTime>(
      // Rebuilds with the chosen value, so the message clears once a date is set.
      key: ValueKey('date-$label-${value?.millisecondsSinceEpoch}'),
      initialValue: value,
      validator: (_) => value == null ? requiredMessage : null,
      builder: (state) => _Labeled(
        label: label,
        child: InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: InputDecorator(
            decoration: InputDecoration(
              errorText: state.errorText,
              suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
            ),
            child: Text(
              value == null ? '—' : format(value!),
              style: GoogleFonts.inter(
                fontSize: 14,
                color: value == null ? cs.onSurfaceVariant : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
