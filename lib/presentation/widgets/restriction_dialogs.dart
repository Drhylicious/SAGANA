import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/app_error_message.dart';
import '../../core/utils/app_utils.dart';
import '../../data/models/member_restriction.dart';
import '../../data/models/suspension_reasons.dart';
import '../../data/repositories/member_restriction_repository.dart';
import 'app_dialog.dart';
import 'app_dropdown_field.dart';
import 'app_toast.dart';
import 'feature_restriction_notice.dart';
import 'management_modal.dart';
import 'shared_widgets.dart';

/// What the Manager / Officer chose. Only returned once the second step is
/// confirmed, so nothing is written for a cancelled flow.
class RestrictionRequest {
  final Set<RestrictableFeature> features;
  final String reason;
  final DateTime? endsAt; // null = until lifted

  const RestrictionRequest({
    required this.features,
    required this.reason,
    this.endsAt,
  });
}

enum _Length { noEnd, days1, days3, days7, days15, days30, pickDate }

int? _daysFor(_Length length) => switch (length) {
  _Length.days1 => 1,
  _Length.days3 => 3,
  _Length.days7 => 7,
  _Length.days15 => 15,
  _Length.days30 => 30,
  _ => null,
};

class _StepOne {
  final Set<RestrictableFeature> features;
  final String reason;
  final DateTime? until;
  final String lengthText;

  const _StepOne({
    required this.features,
    required this.reason,
    required this.until,
    required this.lengthText,
  });
}

/// Two-step Restrict flow, the same shape as the suspension flow: step 1 picks
/// the features, the reason and the length; step 2 shows the summary. Returns
/// null when either step is cancelled.
Future<RestrictionRequest?> promptRestriction({
  required BuildContext context,
  required String displayName,
}) async {
  final first = await _stepOne(context, displayName);
  if (first == null || !context.mounted) return null;
  final confirmed = await _stepTwo(context, first, displayName);
  if (confirmed != true) return null;
  return RestrictionRequest(
    features: first.features,
    reason: first.reason,
    endsAt: first.until,
  );
}

Future<_StepOne?> _stepOne(BuildContext context, String displayName) {
  final l10n = AppLocalizations.of(context);
  final reasons = suspensionReasonsFor('farmer');
  final otherIndex = reasons.length; // "Other" is always the last choice
  final otherCtrl = TextEditingController();

  final chosen = <RestrictableFeature>{};
  int? selected;
  _Length length = _Length.noEnd;
  DateTime? pickedDate;

  String lengthLabel(_Length l, DateTime? date) {
    final days = _daysFor(l);
    if (days != null) return l10n.suspendDurationDays(days);
    if (l == _Length.pickDate) {
      return date == null
          ? l10n.suspendDurationPickDate
          : AppUtils.formatDate(date, l10n.localeName);
    }
    return l10n.restrictDurationNoEnd;
  }

  DateTime? untilFor(_Length l, DateTime? date) {
    final days = _daysFor(l);
    if (days != null) return DateTime.now().add(Duration(days: days));
    if (l == _Length.pickDate) return date;
    return null;
  }

  return showManagementModal<_StepOne>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final cs = Theme.of(ctx).colorScheme;
        final isOther = selected == otherIndex;
        final reasonOk =
            selected != null && (!isOther || otherCtrl.text.trim().isNotEmpty);
        final lengthOk = length != _Length.pickDate || pickedDate != null;
        final canConfirm = chosen.isNotEmpty && reasonOk && lengthOk;

        return ManagementModalShell(
          title: l10n.restrictFlowTitle(displayName),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.restrictFlowFeaturesLabel,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              // Two even columns instead of seven stacked rows.
              LayoutBuilder(
                builder: (context, box) {
                  const gap = 8.0;
                  final cell = (box.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final feature in RestrictableFeature.values)
                        SizedBox(
                          width: cell,
                          child: _FeatureTile(
                            key: ValueKey('restrict-feature-${feature.key}'),
                            label: feature.label(l10n),
                            selected: chosen.contains(feature),
                            onTap: () => setSheet(() {
                              if (!chosen.add(feature)) chosen.remove(feature);
                            }),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              AppDropdownField<int>(
                value: selected,
                hintText: l10n.suspendFlowSelectReason,
                labelText: l10n.suspendFlowReasonLabel,
                // The whole reason is shown, over as many lines as it needs.
                wrapText: true,
                menuMaxHeight: 380,
                items: [for (var i = 0; i <= otherIndex; i++) i],
                itemLabel: (i) => i == otherIndex
                    ? l10n.suspendReasonOther
                    : reasons[i].label(l10n),
                onChanged: (v) => setSheet(() => selected = v),
              ),
              if (isOther) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: otherCtrl,
                  maxLines: 2,
                  maxLength: 120,
                  onChanged: (_) => setSheet(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.suspendFlowOtherLabel,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              AppDropdownField<_Length>(
                value: length,
                hintText: l10n.addMemberSelectHint,
                labelText: l10n.restrictFlowDurationLabel,
                // Tall enough for all seven options (up to "Until a chosen date").
                menuMaxHeight: 380,
                items: _Length.values,
                itemLabel: (l) => lengthLabel(l, null),
                onChanged: (v) => setSheet(() {
                  length = v ?? _Length.noEnd;
                }),
              ),
              if (length == _Length.pickDate) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(
                    pickedDate == null
                        ? l10n.suspendFlowChooseDate
                        : AppUtils.formatDate(pickedDate!, l10n.localeName),
                  ),
                  onPressed: () async {
                    final now = DateTime.now();
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: now.add(const Duration(days: 1)),
                      firstDate: DateTime(
                        now.year,
                        now.month,
                        now.day,
                      ).add(const Duration(days: 1)),
                      lastDate: now.add(const Duration(days: 730)),
                    );
                    if (date != null) setSheet(() => pickedDate = date);
                  },
                ),
              ],
            ],
          ),
          footer: ManagementModalActions(
            cancelLabel: l10n.suspendFlowCancel,
            primaryLabel: l10n.suspendFlowConfirm,
            onPrimary: !canConfirm
                ? null
                : () {
                    final reason = isOther
                        ? otherCtrl.text.trim()
                        : reasons[selected!].text;
                    Navigator.pop(
                      ctx,
                      _StepOne(
                        features: Set.of(chosen),
                        reason: reason,
                        until: untilFor(length, pickedDate),
                        lengthText: lengthLabel(length, pickedDate),
                      ),
                    );
                  },
          ),
        );
      },
    ),
  ).whenComplete(otherCtrl.dispose);
}

/// One feature in the checklist: a bordered tile with a check box, two to a row.
class _FeatureTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FeatureTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppConstants.primaryGreen.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: selected
                ? AppConstants.primaryGreen
                : cs.outline.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 20,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : cs.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.25,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool?> _stepTwo(
  BuildContext context,
  _StepOne first,
  String displayName,
) {
  final l10n = AppLocalizations.of(context);
  return showManagementModal<bool>(
    context: context,
    builder: (ctx) => ManagementModalShell(
      title: l10n.restrictSummaryTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _summaryRow(ctx, l10n.restrictSummaryMember, displayName),
          _summaryRow(
            ctx,
            l10n.restrictSummaryFeatures,
            [
              for (final f in RestrictableFeature.values)
                if (first.features.contains(f)) f.label(l10n),
            ].join(', '),
          ),
          _summaryRow(
            ctx,
            l10n.suspendFlowSummaryReason,
            localizedSuspensionReason(l10n, first.reason),
          ),
          _summaryRow(ctx, l10n.suspendFlowSummaryDuration, first.lengthText),
          _summaryRow(
            ctx,
            l10n.restrictSummaryUntil,
            first.until == null
                ? l10n.restrictUntilLifted
                : AppUtils.formatDate(first.until!, l10n.localeName),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.restrictSummaryNote,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      footer: ManagementModalActions(
        cancelLabel: l10n.suspendFlowCancel,
        primaryLabel: l10n.restrictSummaryAction,
        onPrimary: () => Navigator.pop(ctx, true),
      ),
    ),
  );
}

Widget _summaryRow(BuildContext context, String label, String value) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ],
    ),
  );
}

/// The restrictions in force on one member, each with a Lift button. Returns true
/// when something was lifted (the caller reloads its list).
Future<bool?> showManageRestrictions({
  required BuildContext context,
  required String displayName,
  required String memberId,
  required MemberRestrictionRepository repo,
}) {
  final l10n = AppLocalizations.of(context);
  var changed = false;
  return showManagementModal<bool>(
    context: context,
    builder: (ctx) => _ManageRestrictionsSheet(
      title: '${l10n.restrictManageTitle} · $displayName',
      memberId: memberId,
      repo: repo,
      onChanged: () => changed = true,
    ),
  ).then((_) => changed);
}

class _ManageRestrictionsSheet extends StatefulWidget {
  final String title;
  final String memberId;
  final MemberRestrictionRepository repo;
  final VoidCallback onChanged;

  const _ManageRestrictionsSheet({
    required this.title,
    required this.memberId,
    required this.repo,
    required this.onChanged,
  });

  @override
  State<_ManageRestrictionsSheet> createState() =>
      _ManageRestrictionsSheetState();
}

class _ManageRestrictionsSheetState extends State<_ManageRestrictionsSheet> {
  List<MemberRestriction>? _items;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.repo.fetchActiveForMember(widget.memberId);
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  Future<void> _lift(MemberRestriction r) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.show<bool>(
      context: context,
      child: ConfirmDialog(
        title: l10n.restrictLiftConfirmTitle,
        message: l10n.restrictLiftConfirmBody(r.feature.label(l10n)),
        confirmLabel: l10n.restrictLift,
        cancelLabel: l10n.suspendFlowCancel,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyId = r.id);
    try {
      await widget.repo.liftRestriction(r.id);
      widget.onChanged();
      if (!mounted) return;
      AppToast.show(context, l10n.restrictLiftedToast);
      await _load();
    } catch (e, st) {
      if (!mounted) return;
      AppToast.show(
        context,
        friendlyError(l10n, e, st, l10n.restrictActionError),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final items = _items;

    return ManagementModalShell(
      title: widget.title,
      body: items == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          : items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                l10n.restrictManageEmpty,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in items) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.feature.label(l10n),
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              restrictionReasonText(l10n, r.reason),
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              restrictionUntilText(l10n, r.endsAt),
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        key: ValueKey('lift-restriction-${r.id}'),
                        onPressed: _busyId == null ? () => _lift(r) : null,
                        child: _busyId == r.id
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(l10n.restrictLift),
                      ),
                    ],
                  ),
                  if (r != items.last) ...[
                    const SizedBox(height: 10),
                    Divider(
                      height: 1,
                      color: cs.outline.withValues(alpha: 0.12),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
    );
  }
}
