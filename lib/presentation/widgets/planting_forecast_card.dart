import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/analytics_model.dart';

String forecastTrendLabel(AppLocalizations l10n, String trend) {
  switch (trend) {
    case 'trending_up': return l10n.forecastTrendingUp;
    case 'trending_down': return l10n.forecastTrendingDown;
    case 'stable': return l10n.forecastStable;
    default: return l10n.forecastNotEnoughData;
  }
}

String forecastExplanation(AppLocalizations l10n, PlantingForecast forecast) {
  if (!forecast.hasForecast) {
    return l10n.forecastNotEnoughDataExplanation;
  }
  final diff = forecast.forecastNextCycleKg! - forecast.mostRecentCycleKg;
  final diffAbs = diff.abs().toStringAsFixed(0);
  switch (forecast.trend) {
    case 'trending_up': return l10n.forecastIncreaseExplanation(diffAbs);
    case 'trending_down': return l10n.forecastDecreaseExplanation(diffAbs);
    default: return l10n.forecastStableExplanation;
  }
}

/// Shared forecast section header + card, extracted from
/// farmer_analytics_screen.dart's private _ForecastSectionHeader /
/// _ForecastCard once the Admin Analytics Dashboard needed the identical
/// presentation — same trend-based, supply-only framing on both sides of
/// the app, not two different representations of the same underlying view.
class PlantingForecastSectionHeader extends StatelessWidget {
  const PlantingForecastSectionHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.plantingForecastTitle,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        // On its own line below the title (rather than sharing a Row with
        // it) so the title never has to compete with this badge for width
        // and truncate on narrow phone screens.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppConstants.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            l10n.plantingForecastBasedOnHistory,
            style: GoogleFonts.inter(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: AppConstants.primaryGreen.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppConstants.primaryGreen,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.plantingForecastInfoBody,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class PlantingForecastCard extends StatelessWidget {
  final PlantingForecast forecast;
  const PlantingForecastCard({super.key, required this.forecast});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final l10n = AppLocalizations.of(context);
    final color = _trendColor();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border(left: BorderSide(color: color, width: 4)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF455A64).withValues(alpha: 0.05),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        forecast.cropName,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        forecast.category.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: cs.outline,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      forecastTrendLabel(l10n, forecast.trend).toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                forecastExplanation(l10n, forecast),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (forecast.hasForecast) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ForecastFigure(
                        label: l10n.plantingForecastLastCycle,
                        value:
                            '${forecast.mostRecentCycleKg.toStringAsFixed(0)} kg',
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: cs.outline.withValues(alpha: 0.50),
                    ),
                    Expanded(
                      child: ForecastFigure(
                        label: l10n.plantingForecastNextCycle,
                        value:
                            '${forecast.forecastNextCycleKg!.toStringAsFixed(0)} kg',
                        highlight: true,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _trendColor() {
    switch (forecast.trend) {
      case 'trending_up':
        return AppConstants.successGreen;
      case 'trending_down':
        return AppConstants.errorRed;
      case 'stable':
        return AppConstants.warningAmber;
      default:
        return AppConstants.outline;
    }
  }
}

class ForecastFigure extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const ForecastFigure({
    super.key,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 9, color: cs.outline),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: highlight
                ? AppConstants.primaryGreen
                : cs.onSurface,
          ),
        ),
      ],
    );
  }
}