import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/admin_reports_model.dart' show ReportPeriod;

/// Shared building blocks for the Reports module. Extracted after finding
/// the same empty-state container, delta-badge logic, gradient hero card,
/// and plain KPI tile copy-pasted verbatim across all seven report
/// screens (Reports landing, Sales, Harvest, Cooperative Stock, Loan,
/// Expense, Member Contribution). Behavior and styling here are unchanged
/// from what already existed — this is a consolidation, not a redesign of
/// how any individual number looks.

/// Percent-change indicator. Hidden for All Time (no prior period to
/// compare against) or when the previous value is exactly zero (a
/// percentage against zero is undefined, not "-100%" or "+100%").
class ReportDeltaBadge extends StatelessWidget {
  final double current;
  final double previous;
  final ReportPeriod period;

  const ReportDeltaBadge({
    super.key,
    required this.current,
    required this.previous,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    if (period == ReportPeriod.allTime || previous == 0) {
      return const SizedBox.shrink();
    }
    final change = (current - previous) / previous * 100;
    final isUp = change >= 0;
    final color = isUp ? AppConstants.successGreen : AppConstants.errorRed;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: 10,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          '${change.abs().toStringAsFixed(0)}%',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// A single stat inside a [ReportHeroCard]. [current]/[previous] are
/// optional — omit both to show a value with no delta badge.
class ReportHeroStat {
  final String label;
  final String value;
  final double? current;
  final double? previous;

  const ReportHeroStat({
    required this.label,
    required this.value,
    this.current,
    this.previous,
  });
}

/// The gradient "headline totals" card — previously duplicated across
/// the Reports landing page, Harvest's Activity tab, Loan Report's
/// All-Time Summary, Member Contribution's yearly total, and
/// Balik-Tangkilik's payout estimate.
///
/// [primaryStats] render larger, for the 1-2 numbers that matter most on
/// a given screen. [secondaryStats] render smaller, in a two-column grid,
/// for supporting figures. A screen with only one tier of equal-weight
/// stats can pass everything as [primaryStats] and leave
/// [secondaryStats] empty.
class ReportHeroCard extends StatelessWidget {
  final String title;
  final List<ReportHeroStat> primaryStats;
  final List<ReportHeroStat> secondaryStats;
  final ReportPeriod period;
  final bool isLoading;
  final Widget? trailing;

  const ReportHeroCard({
    super.key,
    required this.title,
    required this.primaryStats,
    this.secondaryStats = const [],
    required this.period,
    this.isLoading = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        gradient: AppConstants.primaryButtonGradient,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          else ...[
            if (primaryStats.isNotEmpty)
              Row(
                children: [
                  for (var i = 0; i < primaryStats.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppConstants.spacingMd),
                    Expanded(
                      child: _heroStat(primaryStats[i], valueFontSize: 20),
                    ),
                  ],
                ],
              ),
            if (secondaryStats.isNotEmpty) ...[
              if (primaryStats.isNotEmpty)
                const SizedBox(height: AppConstants.spacingMd),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppConstants.spacingMd,
                crossAxisSpacing: AppConstants.spacingMd,
                childAspectRatio: 2.2,
                children: secondaryStats
                    .map((s) => _heroStat(s, valueFontSize: 14))
                    .toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _heroStat(ReportHeroStat s, {required double valueFontSize}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          s.label,
          style: GoogleFonts.inter(fontSize: 10, color: Colors.white70),
        ),
        Row(
          children: [
            Text(
              s.value,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: valueFontSize,
                color: Colors.white,
              ),
            ),
            if (s.current != null && s.previous != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ReportDeltaBadge(
                  current: s.current!,
                  previous: s.previous!,
                  period: period,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The plain white/surface stat tile — previously duplicated across
/// Sales, Expense, and Cooperative Stock report screens' 2x2 KPI grids.
class ReportKpiTile extends StatelessWidget {
  final String label;
  final String value;
  final Widget? delta;

  const ReportKpiTile({
    super.key,
    required this.label,
    required this.value,
    this.delta,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: cs.onSurface,
            ),
          ),
          if (delta != null) delta!,
        ],
      ),
    );
  }
}

/// The "no data for this period" placeholder — identical (aside from
/// incidental whitespace) across all seven report screens.
class ReportEmptyState extends StatelessWidget {
  final String message;

  const ReportEmptyState({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// The accent-dot stat tile — duplicated identically between Cooperative
/// Stock Report and Harvest Report (both tabs), found while
/// consolidating the individual report screens.
class ReportAccentStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final double valueFontSize;

  const ReportAccentStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
    this.valueFontSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: valueFontSize,
              color: cs.onSurface,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
