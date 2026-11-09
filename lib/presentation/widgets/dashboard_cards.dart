import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/sagana_colors.dart';

/// The two card styles every Manager / Officer dashboard shares: the KPI cards of an Overview
/// section and the module cards of a Management section. The main Dashboard and the Marketplace
/// dashboard both use these, so they look the same and only the data and the labels differ.

// ─────────────────────────────────────────────────────────────────────────────
// KPI cards (an Overview strip)
// ─────────────────────────────────────────────────────────────────────────────

class DashboardKpiTile {
  final String label;
  final String value;
  /// The small caption under the value. Empty shows only the title and the value.
  final String sub;
  final Color color;
  final IconData icon;
  const DashboardKpiTile({
    required this.label,
    required this.value,
    this.sub = '',
    required this.color,
    required this.icon,
  });
}

/// A row of KPI cards that scrolls sideways.
class DashboardKpiStrip extends StatelessWidget {
  const DashboardKpiStrip({super.key, required this.tiles});

  final List<DashboardKpiTile> tiles;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => DashboardKpiCard(tile: tiles[i]),
      ),
    );
  }
}

/// Accent-tinted background and border, the icon in its own tinted badge, then the label, the
/// value and a small caption.
class DashboardKpiCard extends StatelessWidget {
  const DashboardKpiCard({super.key, required this.tile});

  final DashboardKpiTile tile;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 128,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tile.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: tile.color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: tile.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Icon(tile.icon, size: 12, color: tile.color),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  tile.label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            tile.value,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          if (tile.sub.isNotEmpty)
          Text(
            tile.sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Module cards (a Management section)
// ─────────────────────────────────────────────────────────────────────────────

class DashboardModuleItem {
  final IconData icon;
  final String title;
  final String subtitle;

  /// A small pill at the top right (a count, a status). Empty for none.
  final String badge;
  final VoidCallback onTap;
  final Key? key;
  const DashboardModuleItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = '',
    this.key,
  });
}

/// Height of a module card. Grows with the phone's font size, so a two-line
/// title fits instead of being cut short.
double dashboardModuleCardExtent(BuildContext context) {
  final textScale = MediaQuery.textScalerOf(
    context,
  ).scale(1).clamp(1.0, 1.4).toDouble();
  return 128 * textScale;
}

/// Two columns of module cards. It does not scroll itself: it sits inside the page's own scroll
/// view, so the page scrolls vertically as more cards are added.
class DashboardModuleGrid extends StatelessWidget {
  const DashboardModuleGrid({super.key, required this.items});

  final List<DashboardModuleItem> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      // No automatic status-bar padding: this list sits inside a bigger scroll view.
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: dashboardModuleCardExtent(context),
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => DashboardModuleCard(item: items[i]),
    );
  }
}

/// One row of the same module cards that scrolls sideways. Each card is the
/// size of a [DashboardModuleGrid] card (a little narrower, so the next card
/// peeks in from the right edge and shows there is more to scroll to).
class DashboardModuleStrip extends StatelessWidget {
  const DashboardModuleStrip({super.key, required this.items});

  final List<DashboardModuleItem> items;

  /// How much of the next card shows beside two full cards.
  static const double _peek = 28;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: dashboardModuleCardExtent(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = (constraints.maxWidth - _gap - _peek) / 2;
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: _gap),
            itemBuilder: (context, i) => SizedBox(
              width: cardWidth,
              child: DashboardModuleCard(item: items[i]),
            ),
          );
        },
      ),
    );
  }
}

/// A module card: icon badge, optional count pill, title and subtitle.
class DashboardModuleCard extends StatelessWidget {
  const DashboardModuleCard({super.key, required this.item});

  final DashboardModuleItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final m = item;
    return GestureDetector(
      key: m.key,
      onTap: m.onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Icon(m.icon, color: cs.primary, size: 20),
                ),
                if (m.badge.isNotEmpty)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
                      ),
                      child: Text(
                        m.badge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    m.title,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    m.subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
