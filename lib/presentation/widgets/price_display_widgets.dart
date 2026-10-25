import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/app_utils.dart';
import '../../data/models/price_record_model.dart';
import 'skeleton.dart';

// Reference-price pieces shared by Buyer → Prices and Farmer → Market Rates, so
// the two screens read the same way: the same summary header, category headers,
// crop image, price column and price-trend panel. Only the data differs (a
// Buyer is sent Public Market prices; a Farmer both markets).

/// Groups [items] under their crop category: categories alphabetical, items
/// without a category last under [otherLabel]. Order inside a group is kept.
List<MapEntry<String, List<T>>> groupPricesByCategory<T>(
  Iterable<T> items,
  String? Function(T item) categoryOf,
  String otherLabel,
) {
  final groups = <String, List<T>>{};
  for (final item in items) {
    final c = categoryOf(item)?.trim();
    groups
        .putIfAbsent(c == null || c.isEmpty ? otherLabel : c, () => [])
        .add(item);
  }
  return groups.entries.toList()..sort((a, b) {
    if (a.key == otherLabel) return 1;
    if (b.key == otherLabel) return -1;
    return a.key.toLowerCase().compareTo(b.key.toLowerCase());
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// List header + category header
// ─────────────────────────────────────────────────────────────────────────────

/// Names the market the prices below belong to, says what they are, and gives
/// a quick count and freshness.
class PriceMarketHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int cropCount;
  final String updated;
  final Color accent;

  const PriceMarketHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.cropCount,
    required this.updated,
    this.accent = AppConstants.primaryGreen,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    Widget pill(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.14),
            accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Icon(Icons.storefront_rounded, size: 22, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
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
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.35,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              pill(Icons.eco_rounded, l10n.buyerPriceCropCount(cropCount)),
              pill(Icons.update_rounded, l10n.priceUpdatedPrefix(updated)),
            ],
          ),
        ],
      ),
    );
  }
}

class PriceCategoryHeader extends StatelessWidget {
  final String title;
  final int count;

  const PriceCategoryHeader({
    super.key,
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: cs.outline.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Divider(height: 1, color: cs.outline.withValues(alpha: 0.15)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Crop card pieces
// ─────────────────────────────────────────────────────────────────────────────

/// The crop's photo (from Crop Management; referenced only, never uploaded
/// here), or a tinted leaf when it has none.
class PriceCropThumb extends StatelessWidget {
  final String? imageUrl;
  final Color color;
  final double size;

  const PriceCropThumb({
    super.key,
    required this.imageUrl,
    required this.color,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final placeholder = Container(
      color: color.withValues(alpha: 0.12),
      child: Icon(Icons.eco_outlined, size: size * 0.4, color: color),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: SizedBox(
        width: size,
        height: size,
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
              )
            : placeholder,
      ),
    );
  }
}

/// The right-hand side of a price card: the price, its unit, and the change
/// since the previous entry (hidden when there is no previous entry).
class PriceAmountColumn extends StatelessWidget {
  final PriceRecordModel price;

  const PriceAmountColumn({super.key, required this.price});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deltaColor = price.isUp
        ? AppConstants.successGreen
        : price.isDown
        ? AppConstants.errorRed
        : AppConstants.outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '₱${price.price.toStringAsFixed(2)}',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppConstants.primaryGreen,
          ),
        ),
        Text(
          '/${price.unit}',
          style: GoogleFonts.inter(fontSize: 11, color: cs.outline),
        ),
        if (price.previousPrice != null) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                price.isUp
                    ? Icons.arrow_upward_rounded
                    : price.isDown
                    ? Icons.arrow_downward_rounded
                    : Icons.remove_rounded,
                size: 12,
                color: deltaColor,
              ),
              Text(
                '₱${price.priceDifference!.abs().toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: deltaColor,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Price trend
// ─────────────────────────────────────────────────────────────────────────────

/// The price trend of ONE crop in ONE market: a line over the entries
/// [trend] holds (oldest first), the dates it covers, and High / Low plus
/// either the current price or the average.
///
/// The chart is drawn only from two or more entries; with fewer it says so
/// instead of drawing a line that shows nothing. The caller is responsible for
/// passing entries of a single market, so two price lists are never drawn as
/// one line.
class PriceTrendPanel extends StatelessWidget {
  final List<PriceRecordModel> trend;
  final bool isLoading;

  /// The latest entry, shown as the "Current" figure.
  final PriceRecordModel current;

  /// Shows the average of the entries instead of the current price (for a
  /// screen that already shows the current price right above).
  final bool showAverage;

  /// Show High / Low / third figure even when there is no history to chart.
  final bool showStatsWithoutHistory;

  const PriceTrendPanel({
    super.key,
    required this.trend,
    required this.isLoading,
    required this.current,
    this.showAverage = false,
    this.showStatsWithoutHistory = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final prices = trend.map((p) => p.price).toList();
    final hasHistory = prices.length >= 2;

    final Widget chart = isLoading
        ? const SkeletonBlock(height: 100)
        : !hasHistory
        ? Center(
            child: Text(
              l10n.buyerPriceNoTrendHistory,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        : CustomPaint(
            painter: PriceSparklinePainter(
              prices: prices,
              color: AppConstants.primaryGreen,
            ),
            size: Size.infinite,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 100, width: double.infinity, child: chart),
        if (!isLoading && hasHistory) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppUtils.formatDate(trend.first.recordedAt, l10n.localeName),
                style: GoogleFonts.inter(fontSize: 10, color: cs.outline),
              ),
              Text(
                AppUtils.formatDate(trend.last.recordedAt, l10n.localeName),
                style: GoogleFonts.inter(fontSize: 10, color: cs.outline),
              ),
            ],
          ),
        ],
        if (!isLoading && (hasHistory || showStatsWithoutHistory)) ...[
          const SizedBox(height: 12),
          _stats(context, l10n, prices),
        ],
      ],
    );
  }

  Widget _stats(BuildContext context, AppLocalizations l10n, List<double> p) {
    final high = p.isEmpty ? current.price : p.reduce((a, b) => a > b ? a : b);
    final low = p.isEmpty ? current.price : p.reduce((a, b) => a < b ? a : b);
    final average = p.isEmpty
        ? current.price
        : p.reduce((a, b) => a + b) / p.length;

    return Row(
      children: [
        _stat(
          context,
          l10n.buyerPriceStatHigh,
          '₱${high.toStringAsFixed(2)}',
          AppConstants.successGreen,
        ),
        _stat(
          context,
          l10n.buyerPriceStatLow,
          '₱${low.toStringAsFixed(2)}',
          AppConstants.errorRed,
        ),
        if (showAverage)
          _stat(
            context,
            l10n.priceStatAverage,
            '₱${average.toStringAsFixed(2)}',
            AppConstants.primaryGreen,
          )
        else
          _stat(
            context,
            l10n.buyerPriceStatCurrent,
            current.formattedPrice,
            AppConstants.primaryGreen,
          ),
      ],
    );
  }

  // Three equal columns. A long figure (price with its unit) or a long label in
  // another language shrinks to fit instead of overflowing a narrow phone.
  Widget _stat(BuildContext context, String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal sparkline of price entries, oldest first. Points are spaced evenly
/// by entry, and the line is scaled between the lowest and highest price
/// shown. A small inset keeps the stroke from being clipped at the extremes.
class PriceSparklinePainter extends CustomPainter {
  final List<double> prices;
  final Color color;
  const PriceSparklinePainter({required this.prices, required this.color});

  static const double _inset = 4;

  @override
  void paint(Canvas canvas, Size size) {
    if (prices.length < 2) return;
    final min = prices.reduce((a, b) => a < b ? a : b);
    final max = prices.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs() < 0.01 ? 1.0 : max - min;
    final plotHeight = size.height - _inset * 2;

    final path = Path();
    final stepX = size.width / (prices.length - 1);
    for (int i = 0; i < prices.length; i++) {
      final x = i * stepX;
      final y = _inset + plotHeight - ((prices[i] - min) / range) * plotHeight;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.08));

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant PriceSparklinePainter oldDelegate) =>
      oldDelegate.prices != prices || oldDelegate.color != color;
}
