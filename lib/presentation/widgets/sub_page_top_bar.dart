import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/sagana_colors.dart';

/// The shared back button for secondary screens: a 40x40 circle with a
/// primary-tinted border. Drop it into any existing header's leading slot so
/// every role's sub-screens share the same back control.
class SubPageBackButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String? tooltip;

  const SubPageBackButton({super.key, required this.onPressed, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final button = GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          shape: BoxShape.circle,
          border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
        ),
        child: Icon(Icons.arrow_back_rounded, color: cs.primary),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Shared header for secondary (detail and feature) screens. Matches the
/// Farmer top bar's back button — a 40x40 circle with a primary-tinted border
/// — and its bottom divider, so every role's sub-screens look the same.
class SubPageTopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  const SubPageTopBar({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 12),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        border: Border(bottom: BorderSide(color: cs.outline.withValues(alpha: 0.20))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: sagana.cardBackground,
                shape: BoxShape.circle,
                border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
              ),
              child: Icon(Icons.arrow_back_rounded, color: cs.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
