import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The selectable chip used across Manager > Loans: Loan History's status
/// filter (All / Active Loans / Overdue Loans / Paid), its Filter button, and
/// Record Payment's Monthly / Full Balance choice. One widget, so they look
/// and behave the same: a Material choice chip that turns [selectedColor] with
/// white text when selected.
///
/// Give it a [label], or an [icon] for an icon-only chip (the Filter button).
/// [showCheckmark] is left to the chip's own default unless set.
class LoanChoiceChip extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;
  final bool? showCheckmark;
  final String? tooltip;

  const LoanChoiceChip({
    super.key,
    this.label,
    this.icon,
    required this.selected,
    required this.onTap,
    required this.selectedColor,
    this.showCheckmark,
    this.tooltip,
  }) : assert(label != null || icon != null);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? Colors.white : cs.onSurface;

    final chip = ChoiceChip(
      label: label != null
          ? Text(label!, style: GoogleFonts.inter(fontSize: 12))
          : Icon(icon, size: 18, color: color),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: selectedColor,
      showCheckmark: showCheckmark,
      checkmarkColor: Colors.white,
      // No extra 48 px tap padding, so chips sit tight in a wrapping row.
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelStyle: TextStyle(color: color),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}
