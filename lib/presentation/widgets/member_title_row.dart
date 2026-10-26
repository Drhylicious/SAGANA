import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The top line of a member card: the name on the left, the status badge toward
/// the right, and the three-dot menu at the far right edge, all on one line and
/// vertically centred together.
///
///   Ellen Angela Rosal            PENDING   ⋮
///
/// A long name wraps (two lines at most, then an ellipsis) inside its own space,
/// so it can never run under the badge or the menu. The badge keeps its natural
/// compact width, and is capped so an unusually long label cannot crowd the name.
class MemberTitleRow extends StatelessWidget {
  final String name;
  final Widget badge;
  final Widget menu;

  const MemberTitleRow({
    super.key,
    required this.name,
    required this.badge,
    required this.menu,
  });

  /// As tall as the menu's tap target, so the row never jumps between cards.
  static const double rowHeight = 36;

  /// The widest a badge may grow before its text is cut with an ellipsis.
  static const double maxBadgeWidth = 96;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: rowHeight),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              name,
              key: const ValueKey('member-card-name'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            key: const ValueKey('member-card-badge'),
            constraints: const BoxConstraints(maxWidth: maxBadgeWidth),
            child: badge,
          ),
          const SizedBox(width: 2),
          KeyedSubtree(key: const ValueKey('member-card-menu'), child: menu),
        ],
      ),
    );
  }
}
