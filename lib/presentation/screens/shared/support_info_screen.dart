import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';

/// Generic dedicated Support & Info screen — used for About the
/// Cooperative, Privacy Policy, and Terms of Use (Admin Profile &
/// Settings Phase 7). Replaces the ManagementModal/AlertDialog versions
/// each role's Settings screen previously showed, and the Navigation
/// Drawer's dialog-based versions from Phase 4. Same shared screen for
/// every role — none of this content is role-specific.
///
/// About SAGANA is NOT built on this widget — it needs role-aware body
/// text plus a developer grid, so it has its own screen.
class SupportInfoScreen extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  const SupportInfoScreen({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        leading: BackButton(onPressed: () => context.pop(), color: AppConstants.primaryGreen),
        title: Text(title,
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 8, AppConstants.spacingSafeH, 40),
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            body,
            textAlign: TextAlign.justify,
            style: GoogleFonts.inter(fontSize: 14, height: 1.6, color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}
