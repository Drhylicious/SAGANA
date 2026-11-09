import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';

/// A dropdown that lets you tick several options — the multi-select sibling of
/// [AppDropdownField], with the same look: a bordered field with a separated
/// arrow box, and an opened panel with divider lines and a visible scrollbar.
/// The closed field lists what is chosen ("Seeds, Harvest Stock"); the panel
/// stays open while you tick, and closes when you tap outside it.
///
/// The options are whatever the caller passes in, so a list loaded from the
/// database shows new entries without any change here.
class AppMultiSelectField extends StatefulWidget {
  final List<String> values;
  final List<String> options;
  final String hintText;
  final String? labelText;
  final String? helperText;
  final String? errorText;
  final ValueChanged<List<String>> onChanged;
  final double menuMaxHeight;

  const AppMultiSelectField({
    super.key,
    required this.values,
    required this.options,
    required this.hintText,
    required this.onChanged,
    this.labelText,
    this.helperText,
    this.errorText,
    this.menuMaxHeight = 260,
  });

  @override
  State<AppMultiSelectField> createState() => _AppMultiSelectFieldState();
}

class _AppMultiSelectFieldState extends State<AppMultiSelectField> {
  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  final _scrollController = ScrollController();
  OverlayEntry? _overlay;
  bool _isOpen = false;
  late List<String> _values = [...widget.values];

  @override
  void didUpdateWidget(covariant AppMultiSelectField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _values = [...widget.values];
    // The open list is in the overlay, not under this widget: refresh it after this
    // frame (it cannot be marked dirty while the framework is building).
    if (_overlay != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _overlay?.markNeedsBuild());
    }
  }

  @override
  void dispose() {
    // Take the list down with the field, without touching state while disposing.
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
    _scrollController.dispose();
    super.dispose();
  }

  void _close() {
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
    if (_isOpen) {
      _isOpen = false;
      if (mounted) setState(() {});
    }
  }

  void _toggleOption(String option) {
    setState(() {
      if (_values.contains(option)) {
        _values.remove(option);
      } else {
        _values.add(option);
      }
    });
    _overlay?.markNeedsBuild();
    widget.onChanged([..._values]);
  }

  void _open() {
    final box = _fieldKey.currentContext!.findRenderObject() as RenderBox;
    final width = box.size.width;
    final height = box.size.height;
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final selectedBg = Theme.of(context).brightness == Brightness.dark
        ? Colors.blue.withValues(alpha: 0.28)
        : Colors.blue.withValues(alpha: 0.18);

    _overlay = OverlayEntry(
      builder: (overlayCtx) => Stack(
        children: [
          // Tapping outside the panel closes it.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _close,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, height + 4),
            child: Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                color: Colors.transparent,
                child: Container(
                  width: width,
                  constraints: BoxConstraints(maxHeight: widget.menuMaxHeight),
                  decoration: BoxDecoration(
                    color: sagana.cardBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: widget.options.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            AppLocalizations.of(context).noOptionsYet,
                            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
                          ),
                        )
                      : Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          thickness: 6,
                          radius: const Radius.circular(4),
                          child: ListView.separated(
                            controller: _scrollController,
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: widget.options.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              thickness: 1,
                              color: cs.outline.withValues(alpha: 0.15),
                            ),
                            itemBuilder: (_, i) {
                              final option = widget.options[i];
                              final selected = _values.contains(option);
                              return InkWell(
                                onTap: () => _toggleOption(option),
                                child: Container(
                                  color: selected ? selectedBg : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected
                                            ? Icons.check_box_rounded
                                            : Icons.check_box_outline_blank_rounded,
                                        size: 20,
                                        color: selected ? cs.primary : cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          option,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                            color: cs.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_overlay!);
    setState(() => _isOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasValue = _values.isNotEmpty;
    final borderColor = widget.errorText != null
        ? cs.error
        : _isOpen
            ? cs.primary
            : cs.outline.withValues(alpha: 0.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.labelText != null) ...[
          Text(
            widget.labelText!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
        ],
        CompositedTransformTarget(
          link: _layerLink,
          child: GestureDetector(
            key: _fieldKey,
            onTap: () => _isOpen ? _close() : _open(),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: _isOpen ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: Text(
                        hasValue ? _values.join(', ') : widget.hintText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: hasValue
                              ? cs.onSurface
                              : cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      border: Border(left: BorderSide(color: borderColor)),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(7),
                        bottomRight: Radius.circular(7),
                      ),
                    ),
                    child: Icon(
                      _isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 4),
          Text(widget.errorText!, style: GoogleFonts.inter(fontSize: 11.5, color: cs.error)),
        ] else if (widget.helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.helperText!,
            style: GoogleFonts.inter(fontSize: 11.5, height: 1.4, color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
