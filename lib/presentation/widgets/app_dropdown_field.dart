import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Custom compact dropdown matching the requested reference design —
/// a bordered field with a visually separated arrow box on the right, and
/// an opened panel with divider lines between rows, a blue selected
/// highlight, and an always-visible scrollbar, capped to a fixed height.
///
/// Flutter's own DropdownButtonFormField can't produce this: its popup
/// route has no hook for row dividers, a persistent (not just
/// during-scroll) scrollbar, or a two-zone closed-field layout. This
/// builds the whole thing directly — a bordered field via
/// CompositedTransformTarget, and an OverlayEntry (following that target)
/// for the panel — rather than working around DropdownButtonFormField's
/// popup route.
///
/// Built as a FormField<T> so it keeps working with the existing
/// Form + GlobalKey<FormState>.validate() pattern used everywhere a
/// required dropdown blocks submission.
class AppDropdownField<T> extends FormField<T> {
  AppDropdownField({
    super.key,
    required T? value,
    required String hintText,
    String? labelText,
    String? helperText,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
    String? Function(T?)? validator,
    double menuMaxHeight = 260,
    // Optional inline "add new" row pinned below the option list — e.g.
    // admin-managed categories, where the addition itself (prompting for a
    // name, inserting it, returning the new value) is the caller's
    // responsibility. Only shown when both are provided.
    String? addNewLabel,
    Future<T?> Function()? onAddNew,
  }) : super(
          initialValue: value,
          validator: validator,
          builder: (field) {
            return _DropdownFieldBody<T>(
              value: field.value,
              hintText: hintText,
              labelText: labelText,
              helperText: helperText,
              errorText: field.errorText,
              items: items,
              itemLabel: itemLabel,
              maxMenuHeight: menuMaxHeight,
              addNewLabel: addNewLabel,
              onAddNew: onAddNew,
              onChanged: (v) {
                field.didChange(v);
                onChanged(v);
              },
            );
          },
        );
}

class _DropdownFieldBody<T> extends StatefulWidget {
  final T? value;
  final String hintText;
  final String? labelText;
  final String? helperText;
  final String? errorText;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final double maxMenuHeight;
  final String? addNewLabel;
  final Future<T?> Function()? onAddNew;

  const _DropdownFieldBody({
    super.key,
    required this.value,
    required this.hintText,
    this.labelText,
    this.helperText,
    this.errorText,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    required this.maxMenuHeight,
    this.addNewLabel,
    this.onAddNew,
  });

  @override
  State<_DropdownFieldBody<T>> createState() => _DropdownFieldBodyState<T>();
}

class _DropdownFieldBodyState<T> extends State<_DropdownFieldBody<T>> {
  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _removeOverlay();
    _scrollController.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
    if (_isOpen) {
      // Guard setState after dispose during teardown.
      if (mounted) setState(() => _isOpen = false);
      _isOpen = false;
    }
  }

  void _toggleMenu() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    final renderBox = _fieldKey.currentContext!.findRenderObject() as RenderBox;
    final fieldWidth = renderBox.size.width;
    final fieldHeight = renderBox.size.height;
    final cs = Theme.of(context).colorScheme;

    _overlayEntry = OverlayEntry(
      builder: (overlayCtx) {
        return Stack(
          children: [
            // Full-screen transparent barrier — tapping outside the panel
            // closes it, matching standard dropdown/select behavior.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0, fieldHeight + 4),
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.transparent,
                  child: Container(
                    width: fieldWidth,
                    constraints: BoxConstraints(maxHeight: widget.maxMenuHeight),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: widget.items.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 14),
                                  child: Text(
                                    'No options yet',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: cs.onSurfaceVariant,
                                    ),
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
                                    itemCount: widget.items.length,
                                    separatorBuilder: (_, __) => Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: cs.outline.withValues(alpha: 0.15),
                                    ),
                                    itemBuilder: (_, i) {
                                      final item = widget.items[i];
                                      final selected = item == widget.value;
                                      return InkWell(
                                        onTap: () {
                                          widget.onChanged(item);
                                          _removeOverlay();
                                        },
                                        child: Container(
                                          width: double.infinity,
                                          color: selected
                                              ? Colors.blue.withValues(alpha: 0.18)
                                              : Colors.transparent,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 12),
                                          child: Text(
                                            widget.itemLabel(item),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: selected
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: selected
                                                  ? Colors.blue.shade900
                                                  : cs.onSurface,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                        if (widget.onAddNew != null) ...[
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: cs.outline.withValues(alpha: 0.15),
                          ),
                          InkWell(
                            onTap: () async {
                              _removeOverlay();
                              final newItem = await widget.onAddNew!();
                              if (newItem != null) widget.onChanged(newItem);
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_circle_outline_rounded,
                                      size: 18, color: cs.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    widget.addNewLabel ?? 'Add new',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasValue = widget.value != null;
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
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
        ],
        CompositedTransformTarget(
          link: _layerLink,
          child: GestureDetector(
            key: _fieldKey,
            onTap: _toggleMenu,
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
                        hasValue ? widget.itemLabel(widget.value as T) : widget.hintText,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: hasValue
                              ? cs.onSurface
                              : cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                  // The separated arrow box — its own background and a
                  // dividing edge, rounded only on the outer corners so it
                  // reads as one continuous field with two zones.
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
          Text(
            widget.errorText!,
            style: GoogleFonts.inter(fontSize: 11.5, color: cs.error),
          ),
        ] else if (widget.helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.helperText!,
            style: GoogleFonts.inter(fontSize: 11.5, color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Small reusable "type a name" prompt for AppDropdownField's inline
/// "add new" affordance (e.g. adding a new inventory/crop category without
/// leaving the dropdown). Returns the trimmed name, or null if cancelled
/// or left blank.
Future<String?> promptForNewOptionName(
  BuildContext context, {
  required String title,
  String hintText = 'Name',
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hintText),
        textCapitalization: TextCapitalization.words,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, controller.text.trim()),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  return (result == null || result.isEmpty) ? null : result;
}
