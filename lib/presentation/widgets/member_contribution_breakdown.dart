import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/repositories/benefits_tracking_repository.dart';
import 'capital_share_credit_widgets.dart';
import 'management_modal.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/app_localizations.dart';
import '../../data/models/admin_reports_model.dart';

/// One member's year in the Member Contribution Report, laid out once for every
/// place that shows it (the report's member card and the Contribution section of
/// Farmer Details), so the two can never look or read differently.
///
/// Total Capital Share = Monthly Contribution + Cooperative Purchase + Offer to
/// Cooperative. Each block shows what that source ADDED to the Capital Share in
/// the year (the Total Capital Share itself is in the header above): the
/// Monthly Contribution with the year's months and whether each is paid, the
/// Cooperative Purchase with the purchases made, the program discount earned and
/// what was credited, and the Offer to Cooperative with the completed offers.
class MemberContributionBreakdown extends StatelessWidget {
  final MemberContributionRow row;
  final int year;

  const MemberContributionBreakdown({
    super.key,
    required this.row,
    required this.year,
  });

  static final _money = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  /// ₱2,000 for a whole peso amount, ₱1,250.50 otherwise.
  static String pesoShort(double v) => v == v.roundToDouble()
      ? '₱${NumberFormat('#,##0').format(v)}'
      : _money.format(v);

  // One colour per source, the same in the report summary and on every member.
  static const monthlyColor = AppConstants.amber;
  static const purchasesColor = AppConstants.buyerBlue;
  static const offersColor = AppConstants.primaryGreen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final r = row;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.patContributionsInYear(year),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: AppConstants.spacingMd),
        // 1. Monthly Contribution: everything the member paid in themselves.
        _SourceBlock(
          icon: Icons.calendar_month_rounded,
          color: monthlyColor,
          label: l10n.patSourceMonthly,
          value: r.memberPaidInYear,
          details: [
            ContributionEntryList(records: r.records, months: r.months),
          ],
        ),
        const SizedBox(height: AppConstants.spacingGutter),
        // 2. Cooperative Purchase: a percentage of the completed purchases of an
        // enrolled Product Sales member.
        _SourceBlock(
          icon: Icons.shopping_bag_rounded,
          color: purchasesColor,
          label: l10n.patSourcePurchases,
          value: r.purchaseCredited,
          details: [
            CreditGroupsView(
              isPurchase: true,
              farmerId: r.farmerId,
              made: r.programPurchasesAmount,
              discountEarned: r.programDiscountAmount,
              credited: r.purchaseCredited,
              creditedBase: r.purchaseShareBase,
              byVersion: r.purchaseByVersion,
              latestVersion: r.latestRateVersion,
              rateChanges: r.rateChanges,
              creditVersions: r.creditVersions,
              // The member's actual purchases, loaded when the card is opened.
              loadItems: () async => [
                for (final p in await BenefitsTrackingRepository().fetchPurchasesFor(r.farmerId, year))
                  creditItemFromPurchase(p, l10n),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingGutter),
        // 3. Offer to Cooperative: a percentage of the sale value of a successful,
        // completed offer.
        _SourceBlock(
          icon: Icons.handshake_rounded,
          color: offersColor,
          label: l10n.patSourceOffers,
          value: r.offersCredited,
          details: [
            CreditGroupsView(
              isPurchase: false,
              farmerId: r.farmerId,
              made: r.totalAmount,
              discountEarned: 0,
              credited: r.offersCredited,
              creditedBase: r.offerShareBase,
              byVersion: r.offerByVersion,
              latestVersion: r.latestRateVersion,
              rateChanges: r.rateChanges,
              creditVersions: r.creditVersions,
              loadItems: () async => [
                for (final t in await BenefitsTrackingRepository().fetchOffersFor(r.farmerId, year))
                  creditItemFromOffer(t),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Every contribution record of the year as its own plain line under Monthly
/// Contribution, newest first, nothing combined:
///   Paid – November 19, 2026 ........ ₱100.00
///   Starting Capital – March 5, 2025 . ₱2,000.00
///   Unpaid – December 2026 ........... ₱100.00
/// A new record is a new line. The five most recent show; older ones are in History.
class ContributionEntryList extends StatelessWidget {
  final List<MemberCapitalRecord> records;
  final List<MemberMonthStatus> months;

  const ContributionEntryList({
    super.key,
    required this.records,
    required this.months,
  });

  static const _limit = 5;
  static final _money = MemberContributionBreakdown._money;
  static final _day = DateFormat('MMMM d, y');
  static final _monthFmt = DateFormat('MMMM yyyy');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    final lines = <(DateTime, String, double?)>[];
    for (final r in records) {
      final label = r.isReversal
          ? l10n.patStatusCancelled
          : switch (r.source) {
              'member_payment' => l10n.monthlyStatusPaid,
              'opening_balance' => l10n.farmerDetailsSourceOpeningBalance,
              'manual_adjustment' => l10n.farmerDetailsSourceAdjustment,
              _ => l10n.farmerDetailsSourcePatronage,
            };
      lines.add((r.date, '$label – ${_day.format(r.date)}', r.amount));
    }
    // A month still owed: Unpaid / Overdue / Partial with what remains.
    for (final m in months) {
      if (m.status == 'paid') continue;
      final label = switch (m.status) {
        'partial' => l10n.monthlyStatusPartial,
        'overdue' => l10n.monthlyStatusOverdue,
        'waived' => l10n.monthlyStatusWaived,
        _ => l10n.monthlyStatusUnpaid,
      };
      final owed = m.status == 'waived'
          ? null
          : (m.status == 'partial' ? m.amountDue - m.paid : m.amountDue);
      lines.add((m.month, '$label – ${_monthFmt.format(m.month)}', owed));
    }
    lines.sort((a, b) => b.$1.compareTo(a.$1));
    if (lines.isEmpty) return const SizedBox.shrink();

    Widget line((DateTime, String, double?) l) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.$2,
              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l.$3 == null ? '—' : _money.format(l.$3),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: (l.$3 ?? 0) < 0 ? AppConstants.errorRed : cs.onSurface,
            ),
          ),
        ],
      ),
    );

    // The five most recent entries show; the rest are in History.
    final shown = lines.take(_limit).toList();
    final older = lines.skip(_limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in shown) line(l),
        if (older.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => showManagementModal<void>(
                context: context,
                builder: (_) => ManagementModalShell(
                  title: l10n.patMonthlyHistory,
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final l in older) line(l)],
                  ),
                ),
              ),
              child: Text(
                l10n.patMonthlyHistory,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One source: coloured icon, name, amount, and its plain details underneath.
class _SourceBlock extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final double value;
  final List<Widget> details;

  const _SourceBlock({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.details = const [],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: AppConstants.spacingMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    MemberContributionBreakdown._money.format(value),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              for (final d in details) ...[const SizedBox(height: 6), d],
            ],
          ),
        ),
      ],
    );
  }
}
