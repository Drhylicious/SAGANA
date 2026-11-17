import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/member_contribution_breakdown.dart';
import '../../widgets/report_ui_widgets.dart';
import '../../../core/utils/member_access.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../data/services/connectivity_service.dart';

/// Member Contribution Report — Admin.
/// Pushed above the shell. Route: /admin/reports/contributions
///
/// The members' Capital Share and what was added to it in a year. This tracks
/// Capital Share, not business volume: Total Capital Share is the real balance
/// (the capital ledger, the same figure Farmer Details shows). The three sources
/// show what each ADDED to it in the year, each from its own record:
///   1. Monthly Contributions: the payments received (capital ledger,
///      source member_payment). Unpaid obligations are shown, never counted.
///   2. Cooperative Product Purchases: the member-price discount credited to the
///      Capital Share (ledger source purchase_discount). The purchase itself is
///      shown for reference only.
///   3. Offers to the Cooperative: completed offers (member_sales_transactions).
///      Nothing is credited to the Capital Share for them today, so they add 0;
///      the sale value is shown for reference only.
/// Year-scoped.
class MemberContributionReportScreen extends StatefulWidget {
  const MemberContributionReportScreen({super.key});

  @override
  State<MemberContributionReportScreen> createState() =>
      _MemberContributionReportScreenState();
}

enum _MemberFilter {
  all,
  contributed,
  none,
  monthly,
  purchases,
  offers,
  overdue,
  withShares,
}

bool _matches(_MemberFilter f, MemberContributionRow r) {
  switch (f) {
    case _MemberFilter.all:
      return true;
    case _MemberFilter.contributed:
      return r.hasContributed;
    case _MemberFilter.none:
      return !r.hasContributed;
    case _MemberFilter.monthly:
      return r.monthlyContributions > 0;
    case _MemberFilter.purchases:
      return r.programPurchasesAmount > 0;
    case _MemberFilter.offers:
      return r.totalAmount > 0;
    case _MemberFilter.overdue:
      return r.monthsOverdue > 0;
    case _MemberFilter.withShares:
      return r.capitalShares > 0;
  }
}

class _MemberContributionReportScreenState
    extends State<MemberContributionReportScreen> {
  final _repo = AdminReportsRepository();
  final _searchController = TextEditingController();

  late int _year;
  bool _isLoading = true;
  bool _isOnline = ConnectivityService.instance.isOnline;
  String _searchQuery = '';
  _MemberFilter _filter = _MemberFilter.all;
  // The members whose card is open. Every card starts closed.
  final Set<String> _expandedIds = {};
  MemberContributionReportData _data = MemberContributionReportData.empty(
    DateTime.now().year,
  );
  List<int> _availableYears = [DateTime.now().year];

  static final _money = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  // One colour per source, used in the summary and on every member.
  static const _monthlyColor = AppConstants.amber;
  static const _purchasesColor = AppConstants.buyerBlue;
  static const _offersColor = AppConstants.primaryGreen;

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _loadAvailableYears();
    _load();
  }

  Future<void> _loadAvailableYears() async {
    final years = await _repo.fetchAvailableContributionYears();
    if (!mounted) return;
    setState(() => _availableYears = years);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await _repo.fetchMemberContributionReport(_year);
    if (!mounted) return;
    setState(() {
      _data = data;
      _isLoading = false;
    });
  }

  void _setYear(int year) {
    setState(() => _year = year);
    _load();
  }

  /// How many members each filter holds, whatever is typed in the search box.
  int _count(_MemberFilter f) => _data.rows.where((r) => _matches(f, r)).length;

  static String _filterName(AppLocalizations l10n, _MemberFilter f) {
    switch (f) {
      case _MemberFilter.all:
        return l10n.reportsAll;
      case _MemberFilter.contributed:
        return l10n.patFilterContributed;
      case _MemberFilter.none:
        return l10n.patFilterNone;
      case _MemberFilter.monthly:
        return l10n.patShortMonthly;
      case _MemberFilter.purchases:
        return l10n.patShortPurchases;
      case _MemberFilter.offers:
        return l10n.patShortOffers;
      case _MemberFilter.overdue:
        return l10n.patFilterOverdue;
      case _MemberFilter.withShares:
        return l10n.patFilterWithShares;
    }
  }

  List<MemberContributionRow> get _filteredRows {
    var list = _data.rows.where((r) => _matches(_filter, r)).toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((r) => r.farmerName.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SubPageTopBar(
            title: l10n.reportsMemberContributionReport,
            onBack: () => context.pop(),
            // The Capital Share percentages (Cooperative Purchase, Offer to Cooperative).
            trailing: IconButton(
              icon: Icon(Icons.settings_outlined, color: cs.primary),
              onPressed: () => context.push(AppRoutes.capitalShareSettings),
              tooltip: l10n.capSettingsTitle,
            ),
          ),
          CachedDataNotice(
            screen: AdminReportsRepository.memberContributionCacheScreen(_year),
            isOnline: _isOnline,
            offlineMessage: l10n.offlineStaffBody,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingSafeH,
                  AppConstants.spacingGutter,
                  AppConstants.spacingSafeH,
                  32,
                ),
                children: [
                  YearNavigator(
                    selectedYear: _year,
                    years: _availableYears,
                    onChanged: _setYear,
                  ),
                  const SizedBox(height: AppConstants.spacingSectionV),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: SkeletonList(),
                    )
                  else ...[
                    _buildContributionsCard(l10n, cs),
                    const SizedBox(height: AppConstants.spacingGutter + 4),
                    _buildMembersSection(l10n, cs),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Summary: the three sources ───────────────────────────────────────────

  Widget _buildContributionsCard(AppLocalizations l10n, ColorScheme cs) {
    final added = _data.totalCapitalAdded;
    double fraction(double v) => added > 0 ? (v / added).clamp(0.0, 1.0) : 0;
    String share(double v) =>
        l10n.rptShareOfTotal((fraction(v) * 100).toStringAsFixed(0));

    Widget tile(String label, String value, {Color? color}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              value,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: color ?? cs.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );

    return ReportSectionCard(
      title: l10n.patTitleContributions(_year),
      icon: Icons.paid_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.patTotalContributions,
            style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            _money.format(_data.totalCapital),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 28,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.patMembersLine(
              _data.contributingMemberCount,
              _data.memberCount,
            ),
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          _summaryLine(
            l10n.patAddedInYearLine(_year),
            _money.format(added),
            cs,
          ),
          const SizedBox(height: AppConstants.spacingSectionV),
          Text(
            l10n.patContributionsInYear(_year),
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          // Total Capital Share = Monthly Contribution + Cooperative Purchase +
          // Offer to Cooperative: the three always add up to what was added.
          ReportBarRow(
            label: l10n.patSourceMonthly,
            valueText: _money.format(_data.totalMemberPaid),
            fraction: fraction(_data.totalMemberPaid),
            color: _monthlyColor,
            leading: const Icon(
              Icons.calendar_month_rounded,
              size: 16,
              color: _monthlyColor,
            ),
            caption: share(_data.totalMemberPaid),
          ),
          ReportBarRow(
            label: l10n.patSourcePurchases,
            valueText: _money.format(_data.totalPurchaseCredited),
            fraction: fraction(_data.totalPurchaseCredited),
            color: _purchasesColor,
            leading: const Icon(
              Icons.shopping_bag_rounded,
              size: 16,
              color: _purchasesColor,
            ),
            caption: share(_data.totalPurchaseCredited),
          ),
          ReportBarRow(
            label: l10n.patSourceOffers,
            valueText: _money.format(_data.totalOffersCredited),
            fraction: fraction(_data.totalOffersCredited),
            color: _offersColor,
            leading: const Icon(
              Icons.handshake_rounded,
              size: 16,
              color: _offersColor,
            ),
            caption: share(_data.totalOffersCredited),
          ),
          // The monthly obligation, as three plain figures. Shown, never counted.
          if (_data.totalMonthlyDue > 0) ...[
            const SizedBox(height: AppConstants.spacingSm),
            Text(
              l10n.patObligationHeader,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tile(l10n.patSummaryMonthlyDue, _money.format(_data.totalMonthlyDue)),
                  const SizedBox(width: AppConstants.spacingSm),
                  tile(
                    l10n.patSummaryNotYetPaid,
                    _money.format(_data.totalMonthlyBalance),
                    color: _data.totalMonthlyBalance > 0 ? AppConstants.warningAmber : null,
                  ),
                  const SizedBox(width: AppConstants.spacingSm),
                  tile(
                    l10n.patSummaryOverdueMonths,
                    '${_data.totalMonthsOverdue}',
                    color: _data.totalMonthsOverdue > 0 ? AppConstants.errorRed : null,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryLine(String label, String value, ColorScheme cs) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        value,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: cs.onSurface,
        ),
      ),
    ],
  );

  // ─── Members ──────────────────────────────────────────────────────────────

  Widget _buildMembersSection(AppLocalizations l10n, ColorScheme cs) {
    final filtered = _filteredRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                l10n.patMembersTitle,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (_data.rows.isNotEmpty)
              Text(
                l10n.rptShowingCount(filtered.length, _data.rows.length),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingMd),
        ReportSearchField(
          controller: _searchController,
          hint: l10n.reportsSearchMembers,
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
        const SizedBox(height: AppConstants.spacingMd),
        ReportFilterChips<_MemberFilter>(
          options: [
            for (final f in _MemberFilter.values)
              ReportFilterOption(f, '${_filterName(l10n, f)} (${_count(f)})'),
          ],
          selected: _filter,
          onSelected: (f) => setState(() => _filter = f),
        ),
        const SizedBox(height: AppConstants.spacingGutter),
        if (_data.rows.isEmpty || filtered.isEmpty)
          ReportEmptyState(message: l10n.rptNoMatches)
        else
          ...filtered.map((row) => _buildMemberRow(row, l10n, cs)),
      ],
    );
  }

  Widget _buildMemberRow(
    MemberContributionRow row,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final sagana = context.saganaColors;
    final expanded = _expandedIds.contains(row.farmerId);

    void toggle() => setState(() {
      expanded ? _expandedIds.remove(row.farmerId) : _expandedIds.add(row.farmerId);
    });

    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingMd),
      child: Material(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: InkWell(
          // The whole card opens and closes it. Collapsed, it is only the name
          // and Total Capital Share, so a long member list stays short.
          onTap: toggle,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          child: Ink(
            padding: const EdgeInsets.all(AppConstants.spacingGutter),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        row.farmerName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _money.format(row.capitalBalance),
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          l10n.patTotalContributions,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 26,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: AppConstants.spacingMd),
                            Divider(height: 1, color: cs.outline.withValues(alpha: 0.10)),
                            const SizedBox(height: AppConstants.spacingGutter),
                            // The same breakdown Farmer Details shows for this member.
                            MemberContributionBreakdown(row: row, year: _year),
                            // The member's Contribution tab: their monthly history and ledger.
                            if (membersAccessAllowed) ...[
                              const SizedBox(height: AppConstants.spacingSm),
                              Center(
                                child: TextButton(
                                  onPressed: () =>
                                      pushFarmerDetails(context, row.farmerId, tab: 3),
                                  child: Text(
                                    l10n.patViewFarmerProfile,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
