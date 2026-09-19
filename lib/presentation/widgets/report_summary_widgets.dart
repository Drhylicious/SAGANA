import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/admin_reports_model.dart' show ReportPeriod;

/// Localized label for a [ReportPeriod] filter chip — kept here rather
/// than on the model (which has no BuildContext) so every report screen
/// that renders "This Month / This Quarter / This Year / All Time" chips
/// shares one translation instead of the model's hardcoded English.
String reportPeriodLabel(AppLocalizations l10n, ReportPeriod period) {
  switch (period) {
    case ReportPeriod.thisMonth:
      return l10n.loanHistoryThisMonth;
    case ReportPeriod.thisQuarter:
      return l10n.loanHistoryThisQuarter;
    case ReportPeriod.thisYear:
      return l10n.loanHistoryThisYear;
    case ReportPeriod.allTime:
      return l10n.loanHistoryAllTime;
  }
}

/// Shared building blocks for the Reports module. Extracted after finding
/// the same empty-state container, delta-badge logic, gradient hero card,
/// and plain KPI tile copy-pasted verbatim across all seven report
/// screens (Reports landing, Sales, Harvest, Cooperative Stock, Loan,
/// Expense, Member Contribution). Behavior and styling here are unchanged
/// from what already existed — this is a consolidation, not a redesign of
/// how any individual number looks.

/// Small icon-badged section header — the same "icon in a tinted rounded
/// square + bold title" row ReportHeroCard has always rendered above its
/// own stat grid (Harvest Report's "Harvest Overview", Loan Report's
/// "All-Time Loan Summary", Member Patronage's "Total Cooperative Sales
/// (year)"). Extracted as its own widget so Sales, Cooperative Stock,
/// Expense, and Analytics Dashboard — none of which use ReportHeroCard —
/// can carry the identical visual framing above their own KPI area,
/// without duplicating ReportHeroCard's internals or risking a change to
/// the 4 screens that already depend on it.
class ReportSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color accent;

  const ReportSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.accent = AppConstants.primaryGreen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          ),
          child: Icon(icon, size: 15, color: accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: cs.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared year selector — a compact dropdown pill (calendar icon + selected
/// year + chevron) that opens a popup menu listing [years]. Replaces the
/// original horizontal-scrolling year ChoiceChip row (still used by every
/// other period filter in Reports) specifically for Member Contribution
/// Report and Export Center, at the user's explicit request — a year
/// picker only ever has one active value at a time, so a dropdown reads
/// clearer than a scrollable chip row and takes far less vertical space.
///
/// [years] should be the real years that have data (plus the current
/// year) — never a blind "last N years" — so the list doesn't advertise
/// years with nothing to show. Falls back to a "last [count] years"
/// generated list only when the caller has no better source, so existing
/// callers aren't forced to fetch a year list before they can render.
class YearFilterSelector extends StatelessWidget {
  final int selectedYear;
  final ValueChanged<int> onYearSelected;
  final List<int>? years;
  final int count;
  final Color selectedColor;

  const YearFilterSelector({
    super.key,
    required this.selectedYear,
    required this.onYearSelected,
    this.years,
    this.count = 5,
    this.selectedColor = AppConstants.primaryGreen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final currentYear = DateTime.now().year;
    final years = this.years ?? List.generate(count, (i) => currentYear - i);

    return PopupMenuButton<int>(
      initialValue: selectedYear,
      onSelected: onYearSelected,
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      itemBuilder: (context) => years.map((y) {
        final active = y == selectedYear;
        return PopupMenuItem<int>(
          value: y,
          child: Row(
            children: [
              Icon(
                Icons.check_rounded,
                size: 16,
                color: active ? selectedColor : Colors.transparent,
              ),
              const SizedBox(width: 8),
              Text(
                '$y',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? selectedColor : cs.onSurface,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sagana.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: cs.outline.withValues(alpha: 0.20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_rounded, size: 16, color: selectedColor),
            const SizedBox(width: 6),
            Text(
              '$selectedYear',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

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
/// optional — omit both to show a value with no delta badge. [icon]/
/// [accent] are optional too — a screen that doesn't specify them gets a
/// sensible fallback so existing call sites keep compiling unchanged.
class ReportHeroStat {
  final String label;
  final String value;
  final double? current;
  final double? previous;
  final IconData? icon;
  final Color? accent;

  const ReportHeroStat({
    required this.label,
    required this.value,
    this.current,
    this.previous,
    this.icon,
    this.accent,
  });
}

/// The Reports module's shared "headline totals" card (Phase 16 redesign)
/// — previously a single solid green gradient block, repeatedly flagged
/// as feeling oversized with values that weren't fully visible, and
/// (surprisingly, on inspection) not even actually shared in 2 of its 4
/// real occurrences: Harvest Report and Loan Report had each
/// independently hand-built their own copy of the same gradient
/// Container rather than using this widget. This redesign changes the
/// visual language once, here, and both of those screens are migrated
/// onto this widget for the first time as part of the same phase,
/// closing that duplication alongside the visual fix.
///
/// New style: a plain card background (not a gradient) with each stat
/// rendered as its own small icon-badged, color-tinted tile in a grid —
/// directly addressing the "grid layout" and "white background with
/// accents" suggestions — so every value gets its own visual space
/// instead of being packed into one dense colored block.
///
/// [primaryStats] render first and slightly larger, for the 1-2 numbers
/// that matter most. [secondaryStats] follow, slightly smaller. A screen
/// with only one tier of equal-weight stats can pass everything as
/// [primaryStats] and leave [secondaryStats] empty.
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

  static const _fallbackAccents = [
    AppConstants.primaryGreen,
    AppConstants.buyerBlue,
    AppConstants.amber,
    AppConstants.warningAmber,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final allStats = [...primaryStats, ...secondaryStats];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: const Icon(Icons.bar_chart_rounded, size: 15, color: AppConstants.primaryGreen),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: cs.onSurface,
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
              child: Center(child: CircularProgressIndicator()),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppConstants.spacingSm,
              crossAxisSpacing: AppConstants.spacingSm,
              childAspectRatio: 1.7,
              children: [
                for (var i = 0; i < allStats.length; i++)
                  _heroStat(
                    allStats[i],
                    accent: allStats[i].accent ?? _fallbackAccents[i % _fallbackAccents.length],
                    valueFontSize: i < primaryStats.length ? 17 : 15,
                    cs: cs,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _heroStat(
    ReportHeroStat s, {
    required Color accent,
    required double valueFontSize,
    required ColorScheme cs,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingSm),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(s.icon ?? Icons.insights_rounded, size: 13, color: accent),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  s.label,
                  style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: Text(
                  s.value,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800,
                    fontSize: valueFontSize,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (s.current != null && s.previous != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ReportDeltaBadge(
                    current: s.current!,
                    previous: s.previous!,
                    period: period,
                  ),
                ),
            ],
          ),
        ],
      ),
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

/// The icon-badged, color-tinted stat tile — originally Sales Report's
/// private `_salesKpiTile` (Phase 13), extracted here once Cooperative
/// Stock Report and Harvest Report needed the identical visual language
/// for the same "consistency across all report KPI cards" reason every
/// other shared widget in this file was extracted for. Replaces the
/// older, plainer `ReportAccentStatCard` (colored dot + flat white card)
/// everywhere it was used.
class ReportIconStatCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final Widget? delta;

  const ReportIconStatCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.delta,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(
                child: Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (delta != null) Padding(padding: const EdgeInsets.only(left: 6), child: delta!),
            ],
          ),
        ],
      ),
    );
  }
}

/// The outer titled shell used by Report Landing's Executive Snapshot and
/// every other Report module (icon + section title row, then the grouped
/// KPI cards inside one bordered container) — extracted so any screen can
/// wrap its own [ReportIconStatCard] row/grid in the same structure without
/// duplicating ReportHeroCard's stat-specific rendering.
class ReportSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;
  final Widget? trailing;

  const ReportSectionCard({
    super.key,
    required this.title,
    required this.icon,
    this.accent = AppConstants.primaryGreen,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Icon(icon, size: 15, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          child,
        ],
      ),
    );
  }
}
