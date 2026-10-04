import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/l10n/app_localizations.dart';

/// Shared suspend-reason prompt — the first step of the two-step suspend
/// flow used identically by Farmer Details, Buyer Management, and Buyer
/// Details. Extracted after the third near-identical copy so the same fix
/// only has to happen once: "Next" used to pop an empty reason silently
/// (the empty-check only happened after the dialog had already closed, in
/// the caller), which looked to the admin like tapping Next simply did
/// nothing. Next is now disabled until the reason field is non-empty, so
/// that "did nothing" confusion can't happen at this step for any role.
Future<String?> promptSuspendReason({
  required BuildContext context,
  required String title,
  required String hint,
}) {
  final ctrl = TextEditingController();
  final l10n = AppLocalizations.of(context);
  return showDialog<String>(
    context: context,
    builder: (dc) {
      final cs = Theme.of(dc).colorScheme;
      return StatefulBuilder(
        builder: (dc, setState) {
          final isEmpty = ctrl.text.trim().isEmpty;
          return AlertDialog(
            title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: GoogleFonts.inter(fontSize: 12, color: cs.outline),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dc),
                child: Text(l10n.farmerMgmtCancel),
              ),
              ElevatedButton(
                onPressed: isEmpty ? null : () => Navigator.pop(dc, ctrl.text.trim()),
                child: Text(l10n.farmerMgmtNext),
              ),
            ],
          );
        },
      );
    },
  );
}
