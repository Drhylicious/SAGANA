import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/sagana_colors.dart';
import '../../data/models/admin_reports_model.dart';
import 'member_contribution_breakdown.dart';

/// A member's Capital Share and contributions for one year, on the Contribution
/// tab of Member Details.
///
/// Everything comes from this farmer's own row in the Member Contribution Report:
/// the same fetchMemberContributionReport() call builds that report, and the same
/// [MemberContributionBreakdown] draws the member's card there, so the two can
/// never disagree.
class MemberContributionCard extends StatelessWidget {
  final MemberContributionRow? row;
  final int year;
  final VoidCallback onViewFull;

  const MemberContributionCard({
    super.key,
    required this.row,
    required this.year,
    required this.onViewFull,
  });

  static final _money = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    final r = row;

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingGutter),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.paid_rounded, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.enhMemberPatronage(year.toString()),
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // The year in one figure, with the kilos sold under it.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spacingMd + 2),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.patTotalContributions,
                  style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  _money.format(r?.capitalBalance ?? 0),
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.patAddedInYearLine(year),
                        style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _money.format(r?.capitalAddedInYear ?? 0),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingGutter),

          if (r == null)
            Text(
              l10n.enhNoPatronageActivityRecordedFor(year.toString()),
              style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
            )
          else
            MemberContributionBreakdown(row: r, year: year),

          const SizedBox(height: AppConstants.spacingSm),
          InkWell(
            onTap: onViewFull,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      l10n.farmerDetailsViewPatronageReport,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: cs.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
