import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/admin_reports_model.dart'
    show ReportPeriod, ReportPeriodExt, reportPeriodChipOrder;
import 'listing_filter_modal.dart' show ListingStatusFilterChip;
import 'report_summary_widgets.dart';
import 'trend_chart_painter.dart';

/// Shared building blocks for the Reports UI/UX pass (Oct 2026): the period
/// filter, search box, filter chips, record card, bar row, trend card and
/// detail row that Sales, Harvest, Loan, Expense, Analytics and Export Center
/// all use. They live in their own file (not in report_summary_widgets.dart)
/// so the Member Contribution Report, which uses
/// that file, is not affected by anything here.

/// "Oct 1 – Oct 31, 2026" for a period, or "All dates" for All Time.
String reportPeriodRangeText(AppLocalizations l10n, ReportPeriod period) {
  final range = period.range();
  if (range.startDate == null || range.endDate == null) return l10n.rptAllDates;
  return '${DateFormat('MMM d').format(range.startDate!)} – '
      '${DateFormat('MMM d, yyyy').format(range.endDate!)}';
}

/// Month abbreviations for a trailing window of [count] months ending at the
/// current month — matches the dense, gap-filled trend lists the report
/// repositories return.
List<String> reportTrailingMonthLabels(int count) {
  final now = DateTime.now();
  return List.generate(count, (i) {
    final date = DateTime(now.year, now.month - (count - 1 - i), 1);
    return DateFormat('MMM').format(date);
  });
}

/// The period filter every report shares: the four period chips. The selected
/// chip already says which period is shown, so there is no extra dates line.
class ReportPeriodFilter extends StatelessWidget {
  final ReportPeriod period;
  final ValueChanged<ReportPeriod> onSelected;
  final Color accent;

  const ReportPeriodFilter({
    super.key,
    required this.period,
    required this.onSelected,
    this.accent = AppConstants.primaryGreen,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: reportPeriodChipOrder.map((p) {
              final active = period == p;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    reportPeriodLabel(l10n, p),
                    style: GoogleFonts.inter(fontSize: 12),
                  ),
                  selected: active,
                  onSelected: (_) => onSelected(p),
                  selectedColor: accent,
                  labelStyle: TextStyle(
                    color: active ? Colors.white : cs.onSurface,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// Search box with a clear button, used above every report's record list.
class ReportSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const ReportSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
          prefixIcon: Icon(Icons.search_rounded, color: cs.outline, size: 20),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close_rounded, color: cs.outline, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
        style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
      ),
    );
  }
}

class ReportFilterOption<T> {
  final T value;
  final String label;

  /// How many records the chip holds, shown as "Label (n)". Null shows the
  /// label alone.
  final int? count;
  const ReportFilterOption(this.value, this.label, {this.count});
}

/// The record filter chips of every report, in one horizontally scrolling row.
/// They are the standard SAGANA chip (ListingStatusFilterChip): the same
/// "Label (n)" format, height, spacing and selected state as every other
/// filter row in the app. (The period chips above a report are a different
/// control, ReportPeriodFilter, and are not changed by this.)
class ReportFilterChips<T> extends StatelessWidget {
  final List<ReportFilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  const ReportFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ListingStatusFilterChip(
          label: options[i].label,
          count: options[i].count,
          active: options[i].value == selected,
          color: cs.primary,
          onTap: () => onSelected(options[i].value),
          cs: cs,
        ),
      ),
    );
  }
}

/// The bordered card every report record (a sale, a harvest, an expense, a
/// loan) sits in. Tappable when [onTap] is given.
class ReportRecordCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? borderColor;

  const ReportRecordCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      child: Material(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: Ink(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: borderColor ?? cs.outline.withValues(alpha: 0.10),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Small rounded status label (ACTIVE, OVERDUE, COMMITTED …).
class ReportStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const ReportStatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// One labelled bar in a breakdown (yield by crop, expenses by category, stock
/// by crop …): label on the left, value on the right, a progress bar below,
/// and an optional caption such as "42% of total".
class ReportBarRow extends StatelessWidget {
  final String label;
  final String valueText;
  final double fraction;
  final Color color;
  final Widget? leading;
  final Widget? tag;
  final String? caption;

  const ReportBarRow({
    super.key,
    required this.label,
    required this.valueText,
    required this.fraction,
    this.color = AppConstants.primaryGreen,
    this.leading,
    this.tag,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: cs.onSurface),
                ),
              ),
              if (tag != null) ...[tag!, const SizedBox(width: 6)],
              Text(
                valueText,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: cs.outline.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 3),
            Text(
              caption!,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small "what does this mean" line with an info icon.
class ReportInfoNote extends StatelessWidget {
  final String text;

  const ReportInfoNote({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// A titled line chart card over a trailing six-month window. [values] must be
/// the dense, gap-filled list the report repositories return (one entry per
/// month, oldest first), so the month labels line up.
class ReportTrendCard extends StatelessWidget {
  final String title;
  final List<double> values;
  final String Function(double) valueFormatter;
  final IconData icon;
  // Replaces the default "Last 6 months…" line when a card needs to say more.
  final String? caption;
  final Widget? trailing;

  const ReportTrendCard({
    super.key,
    required this.title,
    required this.values,
    required this.valueFormatter,
    this.icon = Icons.show_chart_rounded,
    this.caption,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return ReportSectionCard(
      title: title,
      icon: icon,
      trailing: trailing,
      subtitle: caption ?? l10n.rptTrendCaption,
      child: SizedBox(
        height: 140,
        child: values.length < 2
            ? Center(
                child: Text(
                  l10n.reportsNotEnoughTrendData,
                  style: GoogleFonts.inter(fontSize: 12, color: cs.outline),
                ),
              )
            : CustomPaint(
                size: const Size(double.infinity, 140),
                painter: TrendChartPainter(
                  values: values,
                  lineColor: cs.primary,
                  gradientColor: cs.primary,
                  xLabels: reportTrailingMonthLabels(values.length),
                  yValueFormatter: valueFormatter,
                ),
              ),
      ),
    );
  }
}

/// Label/value row used by report detail sheets.
class ReportDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const ReportDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Year selector: the selected year in the centre, with `<` on the left and
/// `>` on the right, each shown only when another year can be opened.
///
/// [years] are the years that can be opened (any order). `>` never leads to a
/// year that has not started yet, whatever [years] holds, so in 2026 only 2026
/// shows (no `>`), and in 2027 the report can step between 2026 and 2027. The
/// arrow slots keep their width when hidden, so the year stays centred.
class YearNavigator extends StatelessWidget {
  final int selectedYear;
  final List<int> years;
  final ValueChanged<int> onChanged;
  final int? currentYear;

  const YearNavigator({
    super.key,
    required this.selectedYear,
    required this.years,
    required this.onChanged,
    this.currentYear,
  });

  int? get _previous {
    final earlier = years.where((y) => y < selectedYear).toList()..sort();
    return earlier.isEmpty ? null : earlier.last;
  }

  int? get _next {
    final latest = currentYear ?? DateTime.now().year;
    final later = years.where((y) => y > selectedYear && y <= latest).toList()
      ..sort();
    return later.isEmpty ? null : later.first;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final previous = _previous;
    final next = _next;

    Widget slot(int? target, IconData icon) => SizedBox(
      width: 44,
      height: 44,
      child: target == null
          ? null
          : IconButton(
              onPressed: () => onChanged(target),
              tooltip: '$target',
              icon: Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 26,
              ),
            ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          slot(previous, Icons.chevron_left_rounded),
          Expanded(
            child: Text(
              '$selectedYear',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: cs.onSurface,
              ),
            ),
          ),
          slot(next, Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
