import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/l10n/app_localizations.dart';
import 'management_modal.dart';

/// Step 1 of a Disapprove flow: the reason, which is required.
///
/// The standard management modal, the same one the Suspend flow uses: a header
/// with the title, the text box, and one footer row with Cancel and the main
/// action side by side. The main action stays off until a reason is typed.
/// Returns the trimmed reason, or null when cancelled or closed.
Future<String?> promptReason({
  required BuildContext context,
  required String title,
  required String hint,
  required String actionLabel,
}) {
  return showManagementModal<String>(
    context: context,
    builder: (ctx) => _ReasonModal(
      title: title,
      hint: hint,
      actionLabel: actionLabel,
    ),
  );
}

/// Owns the text controller, so it is disposed with the modal and not while the
/// closing animation is still showing the field.
class _ReasonModal extends StatefulWidget {
  final String title;
  final String hint;
  final String actionLabel;
  const _ReasonModal({
    required this.title,
    required this.hint,
    required this.actionLabel,
  });

  @override
  State<_ReasonModal> createState() => _ReasonModalState();
}

class _ReasonModalState extends State<_ReasonModal> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reason = _ctrl.text.trim();
    return ManagementModalShell(
      title: widget.title,
      body: TextField(
        controller: _ctrl,
        autofocus: true,
        minLines: 3,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
        ),
      ),
      footer: ManagementModalActions(
        cancelLabel: AppLocalizations.of(context).farmerMgmtCancel,
        primaryLabel: widget.actionLabel,
        onPrimary: reason.isEmpty ? null : () => Navigator.pop(context, reason),
      ),
    );
  }
}

/// Step 2: the summary to confirm. Back returns false and the main action true;
/// [danger] makes the main action red. Closing the modal returns null.
Future<bool?> confirmSummary({
  required BuildContext context,
  required String title,
  required List<String> lines,
  required String actionLabel,
  bool danger = false,
}) {
  return showManagementModal<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return ManagementModalShell(
        title: title,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  l,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
        footer: ManagementModalActions(
          cancelLabel: AppLocalizations.of(ctx).farmerMgmtBack,
          onCancel: () => Navigator.pop(ctx, false),
          primaryLabel: actionLabel,
          isDestructive: danger,
          onPrimary: () => Navigator.pop(ctx, true),
        ),
      );
    },
  );
}
