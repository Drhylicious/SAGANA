import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/analytics_model.dart';

/// Shared forecast section header + card, extracted from
/// farmer_analytics_screen.dart's private _ForecastSectionHeader /
/// _ForecastCard once the Admin Analytics Dashboard needed the identical
/// presentation — same trend-based, supply-only framing on both sides of
/// the app, not two different representations of the same underlying view.
class PlantingForecastSectionHeader extends StatelessWidget {
  const PlantingForecastSectionHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Planting Forecast',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.charcoal,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'FORECAST BASED ON HARVEST HISTORY',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFDBF1FE).withValues(alpha: 0.50),
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
                  'Forecasts use a weighted average of cooperative-wide harvest volume over the last 3 thirty-day cycles. This reflects supply trends only, not buyer demand.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppConstants.onSurfaceVariant,
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
    final color = _trendColor();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
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
                          color: AppConstants.charcoal,
                        ),
                      ),
                      Text(
                        forecast.category.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppConstants.outline,
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
                      forecast.trendLabel.toUpperCase(),
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
                forecast.explanation,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppConstants.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (forecast.hasForecast) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ForecastFigure(
                        label: 'Last Cycle',
                        value:
                            '${forecast.mostRecentCycleKg.toStringAsFixed(0)} kg',
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: AppConstants.outline.withValues(alpha: 0.50),
                    ),
                    Expanded(
                      child: ForecastFigure(
                        label: 'Next Cycle (Forecast)',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 9, color: AppConstants.outline),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: highlight
                ? AppConstants.primaryGreen
                : AppConstants.onSurface,
          ),
        ),
      ],
    );
  }
}