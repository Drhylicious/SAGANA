import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import 'sub_page_top_bar.dart';

// Shared building blocks for the Support & Info screens reached from the
// navigation drawer: About SAGANA, About the Cooperative, Privacy Policy and
// Terms of Use. Every colour comes from the theme (ColorScheme / SaganaColors) so
// the screens follow light and dark mode.

/// The page frame: the sub-page top bar and a scrolling column.
class SupportScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final ScrollController? controller;

  const SupportScaffold({
    super.key,
    required this.title,
    required this.children,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.saganaColors.scaffoldBackground,
      body: Column(
        children: [
          SubPageTopBar(title: title, onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingSafeH,
                16,
                AppConstants.spacingSafeH,
                40,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The gradient header at the top of each screen.
class SupportHero extends StatelessWidget {
  /// Shown in a translucent circle. Ignored when [leading] is given.
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? detail;
  final String? meta;

  const SupportHero({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.detail,
    this.meta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: BoxDecoration(
        gradient: AppConstants.primaryButtonGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primaryGreen.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          leading ??
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 32),
              ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ),
          ],
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ],
          if (meta != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              child: Text(
                meta!,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A heading above a group of cards.
class SupportGroupTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const SupportGroupTitle({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 28, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The standard rounded card.
class SupportCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;

  const SupportCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: accent == null
            ? sagana.cardBackground
            : Color.alphaBlend(
                accent!.withValues(alpha: 0.07),
                sagana.cardBackground,
              ),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: (accent ?? cs.outline).withValues(
            alpha: accent == null ? 0.12 : 0.28,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A small tinted square holding an icon.
class SupportIconChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const SupportIconChip({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

/// A row with an icon, a bold title and a description (used for feature lists).
class SupportFeatureRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const SupportFeatureRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SupportIconChip(icon: icon, color: color),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One fact: a small caption above a value.
class SupportFact extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const SupportFact({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SupportIconChip(
          icon: icon,
          color: AppConstants.primaryGreen,
          size: 36,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A thin line between rows inside one card.
class SupportDivider extends StatelessWidget {
  const SupportDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Divider(
      height: 1,
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.14),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Document content (Privacy Policy, Terms of Use, About the Cooperative)
// ─────────────────────────────────────────────────────────────────────────────

enum _BlockKind { paragraph, bullets, labeled, note }

/// One piece of a section's body.
class SupportBlock {
  final _BlockKind _kind;
  final String? _text;
  final List<String> _items;
  final List<(String, String)> _labeled;

  const SupportBlock._(this._kind, this._text, this._items, this._labeled);

  /// A plain paragraph.
  const SupportBlock.paragraph(String text)
    : this._(_BlockKind.paragraph, text, const [], const []);

  /// A bulleted list.
  const SupportBlock.bullets(List<String> items)
    : this._(_BlockKind.bullets, null, items, const []);

  /// A list whose items start with a bold label (for example a role name).
  const SupportBlock.labeled(List<(String, String)> items)
    : this._(_BlockKind.labeled, null, const [], items);

  /// A highlighted callout.
  const SupportBlock.note(String text)
    : this._(_BlockKind.note, text, const [], const []);
}

/// A numbered section of a document: an icon, a title and its blocks.
class SupportSection {
  final IconData icon;
  final String title;
  final List<SupportBlock> blocks;

  const SupportSection({
    required this.icon,
    required this.title,
    required this.blocks,
  });
}

/// A document page body: an "In short" card, a jump-to-section strip and the
/// sections, each in its own card.
class SupportDocumentBody extends StatefulWidget {
  final Color accent;
  final List<String> inShort;
  final List<SupportSection> sections;
  final bool numbered;

  const SupportDocumentBody({
    super.key,
    required this.accent,
    required this.inShort,
    required this.sections,
    this.numbered = true,
  });

  @override
  State<SupportDocumentBody> createState() => _SupportDocumentBodyState();
}

class _SupportDocumentBodyState extends State<SupportDocumentBody> {
  late final List<GlobalKey> _keys = [
    for (final _ in widget.sections) GlobalKey(),
  ];

  void _jumpTo(int i) {
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        SupportCard(
          accent: widget.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, color: widget.accent, size: 20),
                  const SizedBox(width: 8),
                  Flexible(child: Text(
                    l10n.supportInShort,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  )),
                ],
              ),
              const SizedBox(height: 12),
              for (final line in widget.inShort)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: widget.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          line,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            height: 1.5,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SupportGroupTitle(title: l10n.supportInThisDocument),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: widget.sections.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final s = widget.sections[i];
              return ActionChip(
                onPressed: () => _jumpTo(i),
                avatar: widget.numbered
                    ? null
                    : Icon(s.icon, size: 16, color: widget.accent),
                label: Text(
                  widget.numbered ? '${i + 1}. ${s.title}' : s.title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                backgroundColor: widget.accent.withValues(alpha: 0.08),
                side: BorderSide(color: widget.accent.withValues(alpha: 0.25)),
                shape: const StadiumBorder(),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < widget.sections.length; i++) ...[
          KeyedSubtree(
            key: _keys[i],
            child: SupportDocumentSectionCard(
              index: widget.numbered ? i + 1 : null,
              section: widget.sections[i],
              accent: widget.accent,
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

/// One section of a document in its own card; [index] adds the section number.
class SupportDocumentSectionCard extends StatelessWidget {
  final int? index;
  final SupportSection section;
  final Color accent;

  const SupportDocumentSectionCard({
    super.key,
    this.index,
    required this.section,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SupportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (index != null)
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$index',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                SupportIconChip(icon: section.icon, color: accent, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  section.title,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    height: 1.25,
                  ),
                ),
              ),
              if (index != null)
                Icon(section.icon, size: 20, color: accent.withValues(alpha: 0.7)),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < section.blocks.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _BlockView(block: section.blocks[i], accent: accent),
          ],
        ],
      ),
    );
  }
}

class _BlockView extends StatelessWidget {
  final SupportBlock block;
  final Color accent;

  const _BlockView({required this.block, required this.accent});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = GoogleFonts.inter(
      fontSize: 13.5,
      height: 1.6,
      color: cs.onSurface,
    );

    switch (block._kind) {
      case _BlockKind.paragraph:
        return Text(block._text!, style: body);
      case _BlockKind.bullets:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in block._items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _Bullet(accent: accent, child: Text(item, style: body)),
              ),
          ],
        );
      case _BlockKind.labeled:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, text) in block._labeled)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _Bullet(
                  accent: accent,
                  child: Text.rich(
                    TextSpan(
                      style: body,
                      children: [
                        TextSpan(
                          text: '$label: ',
                          style: body.copyWith(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: text),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      case _BlockKind.note:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  block._text!,
                  style: body.copyWith(fontSize: 12.5, height: 1.5),
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _Bullet extends StatelessWidget {
  final Color accent;
  final Widget child;

  const _Bullet({required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    );
  }
}
