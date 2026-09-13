import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';

/// Shows a transient message inserted directly into the root [Overlay],
/// above every dialog opened via AppDialog.show()/showManagementModal() —
/// including nested ones.
///
/// Why not a plain ScaffoldMessenger SnackBar: a SnackBar attaches to the
/// nearest Scaffold, which sits BELOW any showGeneralDialog route (that's
/// how showManagementModal is built — see app_dialog.dart). So firing a
/// snackbar from an action taken inside a modal, while an outer modal is
/// still open (e.g. distributing a benefit from within the Members list),
/// renders it behind that outer modal instead of on top of it. Inserting
/// into the root overlay puts the message on the exact same layer dialogs
/// themselves use, so it's never behind one.
class AppToast {
  AppToast._();

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    var removed = false;
    void dismiss() {
      if (removed) return;
      removed = true;
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (_) => _ToastWidget(message: message, isError: isError),
    );
    overlay.insert(entry);
    Timer(duration, dismiss);
  }
}

class _ToastWidget extends StatelessWidget {
  final String message;
  final bool isError;

  const _ToastWidget({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isError ? AppConstants.errorRed : AppConstants.successGreen,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              message,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }
}
