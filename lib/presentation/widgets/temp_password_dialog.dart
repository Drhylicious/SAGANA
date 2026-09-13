import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import 'management_modal.dart';

/// Shown once, immediately after AccountManagementRepository.resetUserPassword()
/// succeeds. The temporary password is never retrievable again after this
/// dialog closes — the RPC returns it exactly once and nothing stores the
/// plaintext anywhere.
///
/// Routed through ManagementModalShell (not a bare AppDialog.show(), which
/// provides no centering/background of its own — see ChangePasswordDialog
/// for how that responsibility normally falls to the dialog's own build()).
/// This way it matches every other Admin modal in this module for free.
Future<void> showTempPasswordDialog({
  required BuildContext context,
  required String name,
  required String tempPassword,
}) {
  return showManagementModal(
    context: context,
    barrierDismissible: false, // must tap Done — this value is shown exactly once
    builder: (_) => ManagementModalShell(
      title: 'Temporary Password',
      subtitle: "For $name. Relay this to them now — it won't be shown again.",
      body: _TempPasswordBody(tempPassword: tempPassword),
      footer: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConstants.primaryGreen,
            foregroundColor: Colors.white,
          ),
          child: Text('Done', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        ),
      ),
    ),
  );
}

class _TempPasswordBody extends StatelessWidget {
  final String tempPassword;
  const _TempPasswordBody({required this.tempPassword});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: AppConstants.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              tempPassword,
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1.5),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20, color: AppConstants.primaryGreen),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: tempPassword));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
          ),
        ],
      ),
    );
  }
}