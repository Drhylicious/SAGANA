import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import 'management_modal.dart';

/// One "label: value" line of a read-only details view.
class DetailRow {
  final String label;
  final String value;

  /// Draws the value in this colour (a status, a warning). Null = normal text.
  final Color? valueColor;
  const DetailRow(this.label, this.value, {this.valueColor});
}

/// A titled group of lines, optionally followed by a custom widget (a list of
/// members, a shelf-life line).
class DetailSection {
  final String? title;
  final List<DetailRow> rows;
  final Widget? child;
  const DetailSection({this.title, this.rows = const [], this.child});
}

/// The ONE read-only details view: opened by tapping an item, a crop, a
/// program or a Reference Price. It only shows information; editing stays a
/// separate action (the Edit button or icon of the screen, or [footer] here).
Future<T?> showRecordDetails<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? imageUrl,
  IconData placeholderIcon = Icons.inventory_2_outlined,
  bool showImage = true,
  required List<DetailSection> sections,
  Widget Function(BuildContext sheetContext)? footer,
}) {
  return showManagementModal<T>(
    context: context,
    builder: (ctx) => ManagementModalShell(
      title: title,
      subtitle: subtitle,
      body: RecordDetailsBody(
        imageUrl: imageUrl,
        placeholderIcon: placeholderIcon,
        showImage: showImage,
        sections: sections,
      ),
      footer: footer?.call(ctx),
    ),
  );
}

class RecordDetailsBody extends StatelessWidget {
  final String? imageUrl;
  final IconData placeholderIcon;
  final bool showImage;
  final List<DetailSection> sections;

  const RecordDetailsBody({
    super.key,
    required this.sections,
    this.imageUrl,
    this.placeholderIcon = Icons.inventory_2_outlined,
    this.showImage = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final placeholder = Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      alignment: Alignment.center,
      child: Icon(
        placeholderIcon,
        size: 40,
        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showImage) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            child: SizedBox(
              height: 150,
              width: double.infinity,
              child: hasImage
                  ? Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => placeholder,
                    )
                  : placeholder,
            ),
          ),
          const SizedBox(height: 16),
        ],
        for (int s = 0; s < sections.length; s++) ...[
          if (s > 0) const SizedBox(height: 16),
          if (sections[s].title != null) ...[
            Text(
              sections[s].title!.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: cs.outline,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (sections[s].rows.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
              ),
              child: Column(
                children: [
                  for (int r = 0; r < sections[s].rows.length; r++) ...[
                    if (r > 0)
                      Divider(
                        height: 1,
                        color: cs.outline.withValues(alpha: 0.10),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              sections[s].rows[r].label,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 6,
                            child: Text(
                              sections[s].rows[r].value,
                              textAlign: TextAlign.right,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color:
                                    sections[s].rows[r].valueColor ??
                                    cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (sections[s].child != null) ...[
            if (sections[s].rows.isNotEmpty) const SizedBox(height: 8),
            sections[s].child!,
          ],
        ],
      ],
    );
  }
}

/// A section of a details view that opens and closes when its header is
/// tapped (a chevron shows which). Its content scrolls inside [maxHeight], so
/// a long list never stretches the view.
class CollapsibleDetailSection extends StatefulWidget {
  final String title;
  final Widget child;
  final double maxHeight;
  final bool initiallyExpanded;

  const CollapsibleDetailSection({
    super.key,
    required this.title,
    required this.child,
    this.maxHeight = 240,
    this.initiallyExpanded = true,
  });

  @override
  State<CollapsibleDetailSection> createState() =>
      _CollapsibleDetailSectionState();
}

class _CollapsibleDetailSectionState extends State<CollapsibleDetailSection> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: cs.outline,
                    ),
                  ),
                ),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 22,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: Scrollbar(
              child: SingleChildScrollView(child: widget.child),
            ),
          ),
        ],
      ],
    );
  }
}

/// A date as the details views show it: "Nov 13, 2026".
String detailDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = d.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}
