import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/report_summary_widgets.dart';

/// Member Patronage Report — Admin.
/// Pushed above the shell. Route: /admin/reports/contributions
///
/// "Patronage" = how much produce each member sold TO the cooperative in a
/// year (member_sales_transactions), and their resulting share of total
/// coop sales — the basis for the Balik-Tangkilik patronage refund. This
/// is NOT the member's capital-share contribution (₱2,000/share, tracked
/// per member on the Members tab via capital_contribution_events).
///
/// Year-scoped (not Month/Quarter/Year/All-Time like the other reports).
/// Computed live from member_sales_transactions; deliberately does not
/// touch member_contributions' Balik-Tangkilik/interest fields — that
/// belongs to the Balik-Tangkilik Management module.
///
/// Internal identifiers (class name, route, l10n key) keep the historical
/// "contribution" wording; only the user-facing label changed.
class MemberContributionReportScreen extends StatefulWidget {
  const MemberContributionReportScreen({super.key});

  @override
  State<MemberContributionReportScreen> createState() => _MemberContributionReportScreenState();
}

class _MemberContributionReportScreenState extends State<MemberContributionReportScreen> {
  final _repo = AdminReportsRepository();
  final _searchController = TextEditingController();

  late int _year;
  bool _isLoading = true;
  String _searchQuery = '';
  MemberContributionReportData _data = MemberContributionReportData.empty(DateTime.now().year);

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
    _load();
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

  List<MemberContributionRow> get _filteredRows {
    if (_searchQuery.isEmpty) return _data.rows;
    final q = _searchQuery.toLowerCase();
    return _data.rows
        .where((r) => r.farmerName.toLowerCase().contains(q) || r.memberId.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildTopBar(context, l10n, cs, sagana),
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
                  _buildYearChips(cs),
                  const SizedBox(height: AppConstants.spacingGutter),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    _buildSummaryCard(context, l10n, cs),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildMembersSection(context, l10n, cs, sagana),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingSm),
          decoration: BoxDecoration(
            color: sagana.glassBackground,
            border: Border(bottom: BorderSide(color: sagana.glassBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  l10n.reportsMemberContributionReport,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: cs.primary),
                ),
              ),
              IconButton(
                icon: Icon(Icons.file_download_outlined, color: cs.primary),
                onPressed: () => context.push(
                  AppRoutes.exportCenter,
                  extra: ExportCenterArgs(
                    preselectedModule: ReportModuleType.memberContribution,
                    contributionYear: _year,
                  ),
                ),
                tooltip: l10n.reportsExportCenter,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildYearChips(ColorScheme cs) {
    final currentYear = DateTime.now().year;
    final years = List.generate(5, (i) => currentYear - i);

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: years.map((y) {
          final active = _year == y;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('$y', style: GoogleFonts.inter(fontSize: 12)),
              selected: active,
              onSelected: (_) => _setYear(y),
              selectedColor: AppConstants.primaryGreen,
              labelStyle: TextStyle(color: active ? Colors.white : cs.onSurface),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, AppLocalizations l10n, ColorScheme cs) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);

    return ReportHeroCard(
      title: l10n.reportsTotalCoopSalesLabel(_year),
      period: ReportPeriod.allTime,
      primaryStats: [
        ReportHeroStat(
          label: '',
          value: currency.format(_data.totalCoopSales),
        ),
      ],
      secondaryStats: [
        ReportHeroStat(
          label: l10n.reportsContributingMembers,
          value: '${_data.contributingMemberCount} / ${_data.memberCount}',
        ),
        ReportHeroStat(
          label: l10n.reportsParticipationRate,
          value: '${_data.participationPercent.toStringAsFixed(0)}%',
        ),
      ],
    );
  }

  Widget _buildMembersSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final filtered = _filteredRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.reportsMemberBreakdown, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
        const SizedBox(height: AppConstants.spacingSm),
        TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: l10n.reportsSearchMembers,
            hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
            prefixIcon: Icon(Icons.search_rounded, color: cs.outline, size: 20),
          ),
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        if (filtered.isEmpty)
          ReportEmptyState(message: l10n.reportsNoSearchResults)
        else
          ...filtered.map((row) => _buildMemberRow(context, row, l10n, cs, sagana)),
      ],
    );
  }

  Widget _buildMemberRow(
    BuildContext context,
    MemberContributionRow row,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);

    return GestureDetector(
      onTap: () => context.push(AppRoutes.farmerDetails, extra: row.farmerId),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: row.hasContributed
              ? sagana.cardBackground
              : cs.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.farmerName,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(row.memberId, style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currency.format(row.totalAmount),
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface),
                    ),
                    Text(
                      l10n.reportsSharePercent(row.sharePercent.toStringAsFixed(1)),
                      style: GoogleFonts.inter(fontSize: 11, color: AppConstants.primaryGreen),
                    ),
                  ],
                ),
              ],
            ),
            if (row.hasContributed) ...[
              const SizedBox(height: AppConstants.spacingSm),
              Row(
                children: [
                  _cropStat(l10n.reportsPalay, row.palayQtyKg, row.palayAmount, AppConstants.primaryGreen, cs),
                  const SizedBox(width: AppConstants.spacingGutter),
                  _cropStat(l10n.reportsPeanut, row.peanutQtyKg, row.peanutAmount, AppConstants.amber, cs),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: AppConstants.spacingSm),
                child: Text(
                  l10n.reportsNoContributionYet,
                  style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cropStat(String label, double qtyKg, double amount, Color color, ColorScheme cs) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    return Expanded(
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$label: ${qtyKg.toStringAsFixed(0)} kg (${currency.format(amount)})',
              style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}