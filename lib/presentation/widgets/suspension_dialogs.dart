import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/app_utils.dart';
import '../../data/models/suspension_notice.dart';
import '../../data/models/suspension_reasons.dart';
import 'app_dialog.dart';
import 'app_dropdown_field.dart';
import 'management_modal.dart';
import 'web_safe_blur_container.dart';

/// What the admin chose. Only returned once the second step is confirmed, so
/// nothing is written to the account for a cancelled flow.
class SuspensionRequest {
  final String reason;
  final DateTime? suspendedUntil; // null = until an admin reactivates

  const SuspensionRequest({required this.reason, this.suspendedUntil});
}

/// Two-step suspend flow shared by every admin screen that suspends a farmer
/// or buyer. Step 1 collects reason, length and date. Step 2 shows the
/// summary. Returns null when either step is cancelled.
Future<SuspensionRequest?> promptSuspension({
  required BuildContext context,
  required String role, // 'farmer' | 'buyer'
  required String displayName,
}) async {
  final first = await _stepOne(context, role, displayName);
  if (first == null || !context.mounted) return null;
  final confirmed = await _stepTwo(context, first, displayName);
  if (confirmed != true) return null;
  return SuspensionRequest(reason: first.reason, suspendedUntil: first.until);
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
  final String reason;
  final DateTime? until;
  final String lengthText;

  const _StepOne({
    required this.reason,
    required this.until,
    required this.lengthText,
  });
}

Future<_StepOne?> _stepOne(
  BuildContext context,
  String role,
  String displayName,
) {
  final l10n = AppLocalizations.of(context);
  final reasons = suspensionReasonsFor(role);
  final otherIndex = reasons.length; // "Other" is always the last choice
  final otherCtrl = TextEditingController();

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
    return l10n.suspendDurationNoEnd;
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
        final isOther = selected == otherIndex;
        final reasonOk = selected != null &&
            (!isOther || otherCtrl.text.trim().isNotEmpty);
        final lengthOk = length != _Length.pickDate || pickedDate != null;
        final canConfirm = reasonOk && lengthOk;

        return ManagementModalShell(
          title: l10n.suspendFlowTitle(displayName),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppDropdownField<int>(
                value: selected,
                hintText: l10n.suspendFlowSelectReason,
                labelText: l10n.suspendFlowReasonLabel,
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
                  onChanged: (_) => setSheet(() {}),
                  decoration: InputDecoration(
                      labelText: l10n.suspendFlowOtherLabel),
                ),
              ],
              const SizedBox(height: 16),
              AppDropdownField<_Length>(
                value: length,
                hintText: l10n.addMemberSelectHint,
                labelText: l10n.suspendFlowDurationLabel,
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
                  label: Text(pickedDate == null
                      ? l10n.suspendFlowChooseDate
                      : AppUtils.formatDate(pickedDate!, l10n.localeName)),
                  onPressed: () async {
                    final now = DateTime.now();
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: now.add(const Duration(days: 1)),
                      firstDate: DateTime(now.year, now.month, now.day)
                          .add(const Duration(days: 1)),
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
            isDestructive: true,
            onPrimary: !canConfirm
                ? null
                : () {
                    final reason = isOther
                        ? otherCtrl.text.trim()
                        : reasons[selected!].text;
                    Navigator.pop(
                      ctx,
                      _StepOne(
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

Future<bool?> _stepTwo(
  BuildContext context,
  _StepOne first,
  String displayName,
) {
  final l10n = AppLocalizations.of(context);
  return showManagementModal<bool>(
    context: context,
    builder: (ctx) => ManagementModalShell(
      title: l10n.suspendFlowSummaryTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _summaryRow(ctx, l10n.suspendFlowSummaryAccount, displayName),
          _summaryRow(ctx, l10n.suspendFlowSummaryReason, first.reason),
          _summaryRow(ctx, l10n.suspendFlowSummaryDuration, first.lengthText),
          _summaryRow(
            ctx,
            l10n.suspendFlowSummaryUntil,
            first.until == null
                ? l10n.suspendNoticeIndefinite
                : AppUtils.formatDate(first.until!, l10n.localeName),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.suspendFlowSummaryWarning,
            style: GoogleFonts.inter(
                fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      footer: ManagementModalActions(
        cancelLabel: l10n.suspendFlowCancel,
        primaryLabel: l10n.suspendFlowSummaryAction,
        isDestructive: true,
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
        Text(label,
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
        Text(value,
            style: GoogleFonts.inter(
                fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
      ],
    ),
  );
}

/// The red glass-style notice: shown when a suspension is applied to a
/// signed-in user, and when a suspended account tries to log in. It cannot be
/// dismissed by tapping outside; the single OK button is the only way out.
Future<void> showSuspensionNotice({
  required BuildContext context,
  required SuspensionNotice notice,
  bool signedOut = false,
}) {
  final l10n = AppLocalizations.of(context);
  final reason = (notice.reason == null || notice.reason!.trim().isEmpty)
      ? l10n.suspendNoticeNoReason
      : localizedSuspensionReason(l10n, notice.reason!.trim());
  final until = notice.suspendedUntil == null
      ? l10n.suspendNoticeIndefinite
      : AppUtils.formatDate(notice.suspendedUntil!, l10n.localeName);

  return AppDialog.show<void>(
    context: context,
    barrierDismissible: false,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: WebSafeBlurContainer(
            blurSigma: 18,
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: AppConstants.errorRed.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(AppConstants.radiusXl),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.block_rounded,
                          color: Colors.white, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.suspendNoticeTitle,
                          style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _noticeLine(l10n.suspendNoticeReason, reason),
                  const SizedBox(height: 10),
                  _noticeLine(l10n.suspendNoticeUntil, until),
                  if (signedOut) ...[
                    const SizedBox(height: 14),
                    Text(l10n.suspendNoticeSignedOut,
                        style: GoogleFonts.inter(
                            fontSize: 12.5, color: Colors.white)),
                  ],
                  const SizedBox(height: 14),
                  Text(l10n.suspendNoticeContact,
                      style: GoogleFonts.inter(
                          fontSize: 12.5, color: Colors.white)),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppConstants.errorRed,
                      ),
                      child: Text(l10n.suspendNoticeOk),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _noticeLine(String label, String value) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: GoogleFonts.inter(
              fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
      Text(value,
          style: GoogleFonts.inter(
              fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
    ],
  );
}
