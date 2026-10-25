import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/admin_reports_model.dart';
import '../../data/models/contribution_model.dart';

/// A member's patronage for one year, on the Contribution tab of Member Details.
///
/// Two things, each from the source it always had:
/// - the year summary (volume sold to the cooperative and the estimated total
///   patronage), from this farmer's `member_contributions` row for the year;
/// - the breakdown (Palay, Peanut, Other Crops, Purchases and the share of each
///   side), from this farmer's own row in Member Patronage Report. The same
///   fetchMemberContributionReport() call builds that report, so the two can
///   never disagree.
///
/// Only the place changed: it used to be on the Profile tab.
class MemberPatronageCard extends StatelessWidget {
  final MemberContributionRow? row;
  final MemberContribution? contribution;
  final int year;
  final VoidCallback onViewFull;

  const MemberPatronageCard({
    super.key,
    required this.row,
    required this.contribution,
    required this.year,
    required this.onViewFull,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );
    final r = row;
    final c = contribution;
    final volumeKg = c == null
        ? null
        : c.palaySalesKg + c.peanutSalesKg + c.otherCropsQtyKg;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.paid_rounded,
                size: 18,
                color: AppConstants.primaryGreen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Member Patronage ($year)',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Year summary.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _summaryStat(
                    label: l10n.farmerDetailsEstBalikTangkilik,
                    value: c != null
                        ? '₱${c.estimatedTotal.toStringAsFixed(2)}'
                        : '₱0.00',
                    big: true,
                    color: cs.primary,
                    cs: cs,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _summaryStat(
                    label: l10n.farmerDetailsVolumeToSp3(year),
                    value: volumeKg != null
                        ? '${volumeKg.toStringAsFixed(0)}kg'
                        : l10n.farmerDetailsNoRecords,
                    big: false,
                    color: cs.onSurface,
                    cs: cs,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          if (r == null || !r.hasAnyActivity)
            Text(
              'No patronage activity recorded for $year.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            )
          else ...[
            // Mirrors Member Patronage Report's row design exactly (see
            // member_contribution_report_screen.dart's _buildMemberRow) —
            // a combined headline total, then each source's own share%
            // shown separately (never blended into one percentage), then
            // each source's own labeled detail section.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  currency.format(r.combinedTotalAmount),
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Total Patronage',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _sourceShareChip(
                    label: 'Sold to Co-op',
                    percent: r.sharePercent,
                    color: AppConstants.primaryGreen,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _sourceShareChip(
                    label: 'Bought from Co-op',
                    percent: r.purchaseSharePercent,
                    color: AppConstants.buyerBlue,
                  ),
                ),
              ],
            ),
            if (r.hasContributed) ...[
              const SizedBox(height: 10),
              _groupLabel('Selling to Cooperative', cs),
              const SizedBox(height: 4),
              Row(
                children: [
                  _patronageStat(
                    'Palay',
                    '${r.palayQtyKg.toStringAsFixed(0)} kg (${currency.format(r.palayAmount)})',
                    AppConstants.primaryGreen,
                    cs,
                  ),
                  const SizedBox(width: 16),
                  _patronageStat(
                    'Peanut',
                    '${r.peanutQtyKg.toStringAsFixed(0)} kg (${currency.format(r.peanutAmount)})',
                    AppConstants.amber,
                    cs,
                  ),
                ],
              ),
              if (r.otherCropsAmount > 0) ...[
                const SizedBox(height: 4),
                // _patronageStat() returns an Expanded: it must be a Row's
                // direct child, never a Column's.
                Row(
                  children: [
                    _patronageStat(
                      'Other Crops',
                      '${r.otherCropsQtyKg.toStringAsFixed(0)} kg (${currency.format(r.otherCropsAmount)})',
                      AppConstants.buyerBlue,
                      cs,
                    ),
                  ],
                ),
              ],
            ],
            if (r.programPurchasesAmount > 0) ...[
              const SizedBox(height: 10),
              _groupLabel('Buying from Cooperative', cs),
              const SizedBox(height: 4),
              Row(
                children: [
                  _patronageStat(
                    'Purchases',
                    currency.format(r.programPurchasesAmount),
                    AppConstants.buyerBlue,
                    cs,
                  ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onViewFull,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      l10n.farmerDetailsViewFullContribution,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: cs.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStat({
    required String label,
    required String value,
    required bool big,
    required Color color,
    required ColorScheme cs,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: big ? 18 : 14,
            fontWeight: big ? FontWeight.w700 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _groupLabel(String text, ColorScheme cs) => Text(
    text,
    style: GoogleFonts.inter(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      color: cs.onSurfaceVariant,
    ),
  );

  Widget _sourceShareChip({
    required String label,
    required double percent,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${percent.toStringAsFixed(1)}%',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _patronageStat(
    String label,
    String value,
    Color color,
    ColorScheme cs,
  ) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$label: $value',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
