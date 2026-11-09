import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import 'management_modal.dart';

/// One choice of a filter: the value it stands for and the words shown.
class FilterChoice<T> {
  final T value;
  final String label;
  const FilterChoice(this.value, this.label);
}

/// What the filter modal returns. A dismissed modal returns null (nothing changed); a chosen
/// value, including "all" (whose value may itself be null), comes back wrapped so the two are
/// never confused.
class FilterChoiceResult<T> {
  final T value;
  const FilterChoiceResult(this.value);
}

/// The ONE filter modal for a single choice, in the same design as the Members filter: a
/// management modal, the options as chips under a small section label, and Reset / Apply at the
/// foot. Use it for any list with one filter to pick (Order Management's source, and so on).
Future<FilterChoiceResult<T>?> showChoiceFilterModal<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required String sectionLabel,
  required List<FilterChoice<T>> choices,
  required T selected,
  required T resetTo,
}) {
  return showManagementModal<FilterChoiceResult<T>>(
    context: context,
    builder: (_) => _ChoiceFilterSheet<T>(
      title: title,
      subtitle: subtitle,
      sectionLabel: sectionLabel,
      choices: choices,
      selected: selected,
      resetTo: resetTo,
    ),
  );
}

class _ChoiceFilterSheet<T> extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String sectionLabel;
  final List<FilterChoice<T>> choices;
  final T selected;
  final T resetTo;

  const _ChoiceFilterSheet({
    required this.title,
    required this.subtitle,
    required this.sectionLabel,
    required this.choices,
    required this.selected,
    required this.resetTo,
  });

  @override
  State<_ChoiceFilterSheet<T>> createState() => _ChoiceFilterSheetState<T>();
}

class _ChoiceFilterSheetState<T> extends State<_ChoiceFilterSheet<T>> {
  late T _value = widget.selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return ManagementModalShell(
      title: widget.title,
      subtitle: widget.subtitle,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              widget.sectionLabel.toUpperCase(),
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: cs.outline),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in widget.choices)
                GestureDetector(
                  key: Key('filterChoice_${c.value}'),
                  onTap: () => setState(() => _value = c.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: _value == c.value ? cs.primary : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    ),
                    child: Text(
                      c.label,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: _value == c.value ? FontWeight.w700 : FontWeight.w500,
                        color: _value == c.value ? Colors.white : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('filterReset'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: cs.outline.withValues(alpha: 0.30)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
              ),
              onPressed: () => setState(() => _value = widget.resetTo),
              child: Text(l10n.farmerMgmtResetAll, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: cs.onSurface)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              key: const Key('filterApply'),
              onPressed: () => Navigator.of(context).pop(FilterChoiceResult<T>(_value)),
              child: Text(l10n.farmerMgmtApplyFilters, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
