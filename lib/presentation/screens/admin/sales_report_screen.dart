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
import '../../widgets/trend_chart_painter.dart';
import '../../widgets/report_summary_widgets.dart';

/// Sales Report — Admin.
/// Pushed above the shell. Route: /admin/reports/sales
///
/// Unified across all four real Selling Types (Phase 10 redesign): Offer
/// to Cooperative (member_sales_transactions, any crop as of Phase 9),
/// Marketplace (orders), Informal Sale (informal_sales), and DA-AMAD
/// Market Linking (market_linking_programs). Each channel card is
/// tappable as a filter for the Transaction Details list below. Read-only.
class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  final _repo = AdminReportsRepository();
  final _searchController = TextEditingController();

  ReportPeriod _period = ReportPeriod.thisMonth;
  bool _isLoading = true;
  String _searchQuery = '';
  String? _sellingTypeFilter; // null = All
  SalesReportData _data = SalesReportData.empty();
  SalesReportData _previousData = SalesReportData.empty();
  List<double> _revenueTrend = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _repo.fetchSalesReport(_period),
      _repo.fetchPreviousSalesReport(_period),
      _repo.fetchSalesTrend(),
    ]);
    if (!mounted) return;
    setState(() {
      _data = results[0] as SalesReportData;
      _previousData = results[1] as SalesReportData;
      _revenueTrend = results[2] as List<double>;
      _isLoading = false;
    });
  }

  void _setPeriod(ReportPeriod period) {
    setState(() => _period = period);
    _load();
  }

  /// Month abbreviations for fetchSalesTrend()'s trailing window — safe to
  /// compute client-side without touching the repository, since that
  /// method always returns a fixed "last [count] months ending at the
  /// current month" window by construction (see its own doc comment).
  List<String> _trailingMonthLabels(int count) {
    final now = DateTime.now();
    return List.generate(count, (i) {
      final offset = count - 1 - i;
      final date = DateTime(now.year, now.month - offset, 1);
      return DateFormat('MMM').format(date);
    });
  }

  List<SalesTransactionRow> get _filteredTransactions {
    var list = _sellingTypeFilter == null
        ? _data.transactions
        : _data.transactions.where((t) => t.sellingType == _sellingTypeFilter).toList();
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list
        .where(
          (t) =>
              t.farmerName.toLowerCase().contains(q) ||
              t.memberId.toLowerCase().contains(q) ||
              t.cropName.toLowerCase().contains(q) ||
              (t.referenceNo?.toLowerCase().contains(q) ?? false),
        )
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
                  _buildPeriodChips(l10n, cs),
                  const SizedBox(height: AppConstants.spacingGutter),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    // The 4 headline KPIs (Total Revenue, Total Volume,
                    // Transactions, Avg. Sale) lead the screen, with the
                    // Selling Type breakdown below them.
                    _buildOverviewCard(context, l10n, cs, sagana),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildChannelBreakdown(context, cs, sagana),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildTrendChart(context, l10n, cs, sagana),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildTransactionsSection(context, l10n, cs, sagana),
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingSm,
          ),
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
                  l10n.reportsSalesReport,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: cs.primary,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.file_download_outlined,
                  color: cs.primary,
                ),
                onPressed: () => context.push(
                  AppRoutes.exportCenter,
                  extra: ExportCenterArgs(
                    preselectedModule: ReportModuleType.sales,
                    period: _period,
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

  Widget _buildPeriodChips(AppLocalizations l10n, ColorScheme cs) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: reportPeriodChipOrder.map((p) {
          final active = _period == p;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(reportPeriodLabel(l10n, p), style: GoogleFonts.inter(fontSize: 12)),
              selected: active,
              onSelected: (_) => _setPeriod(p),
              selectedColor: AppConstants.primaryGreen,
              labelStyle: TextStyle(
                color: active ? Colors.white : cs.onSurface,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Header + KPI grid together in one bordered, padded card — matching
  /// the breathing room Harvest/Loan/Member Patronage's ReportHeroCard-
  /// based headers already have, rather than a bare header row sitting
  /// directly on the page background with only a small gap to the tiles.
  Widget _buildOverviewCard(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
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
          ReportSectionHeader(
            icon: Icons.point_of_sale_rounded,
            title: l10n.reportsSalesOverview,
          ),
          const SizedBox(height: AppConstants.spacingMd),
          _buildSummaryStats(context, l10n, cs, sagana),
        ],
      ),
    );
  }

  Widget _buildSummaryStats(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    );
    // A fixed absolute height per row, NOT a GridView childAspectRatio —
    // aspect ratio ties cell height to cell width, but this card's
    // content (icon + label + value, plus a delta row on Total Revenue)
    // needs roughly the same height regardless of how narrow the device
    // is. A narrow-phone aspect-ratio cell can shrink its height right
    // when the delta badge or a wrapping label needs MORE height,
    // overflowing — confirmed happening on 2 different aspect ratios
    // (1.6, then 1.3) before switching to this fixed-height approach.
    Widget row(ReportIconStatCard a, ReportIconStatCard b) => SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: a),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(child: b),
        ],
      ),
    );

    return Column(
      children: [
        row(
          ReportIconStatCard(
            icon: Icons.payments_rounded,
            accent: AppConstants.primaryGreen,
            label: l10n.reportsTotalRevenue,
            value: currency.format(_data.totalRevenue),
            delta: ReportDeltaBadge(
              current: _data.totalRevenue,
              previous: _previousData.totalRevenue,
              period: _period,
            ),
          ),
          ReportIconStatCard(
            icon: Icons.scale_rounded,
            accent: AppConstants.buyerBlue,
            label: l10n.reportsTotalVolume,
            value: '${_data.totalQuantityKg.toStringAsFixed(0)} kg',
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        row(
          ReportIconStatCard(
            icon: Icons.receipt_long_rounded,
            accent: AppConstants.amber,
            label: l10n.reportsTransactions,
            value: '${_data.transactionCount}',
          ),
          ReportIconStatCard(
            icon: Icons.trending_up_rounded,
            accent: AppConstants.warningAmber,
            label: l10n.reportsAvgSale,
            value: currency.format(_data.averageSaleAmount),
          ),
        ),
      ],
    );
  }

  static const _channelIcons = {
    'offer_to_cooperative': Icons.handshake_rounded,
    'marketplace': Icons.storefront_rounded,
    'informal_sale': Icons.people_alt_rounded,
    'da_amad_market_linking': Icons.local_shipping_rounded,
  };

  /// The four real Selling Types (Phase 10) — Offer to Cooperative,
  /// Marketplace, Informal Sale, DA-AMAD Market Linking — each a distinct
  /// data source. This is the screen's centerpiece (Phase 13): shown
  /// first, largest, and in full color, per feedback that it previously
  /// felt small and buried below generic KPIs.
  Widget _buildChannelBreakdown(
    BuildContext context,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final l10n = AppLocalizations.of(context);
    final colors = [
      AppConstants.primaryGreen,
      AppConstants.buyerBlue,
      AppConstants.amber,
      AppConstants.warningAmber,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.reportsSalesBySellingType,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onSurface),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.reportsTapCardToFilter,
          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppConstants.spacingMd),
        // A fixed absolute height per row, NOT a GridView childAspectRatio
        // — see the identical fix/reasoning in _buildSummaryStats(). Set
        // generously (computed from worst-case content: 32 padding + 34
        // icon + 2-line label (~31) + 25 amount + 14 txn-count ≈ 142,
        // plus margin for larger text-scale settings) after 132 still
        // wasn't enough for "DA-AMAD Market Linking" wrapped to 2 lines.
        for (var i = 0; i < _data.channelTotals.length; i += 2)
          Padding(
            padding: EdgeInsets.only(
              bottom: i + 2 < _data.channelTotals.length ? AppConstants.spacingMd : 0,
            ),
            child: SizedBox(
              height: 172,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _channelCard(_data.channelTotals[i], colors[i % colors.length], cs, sagana, l10n),
                  ),
                  if (i + 1 < _data.channelTotals.length) ...[
                    const SizedBox(width: AppConstants.spacingMd),
                    Expanded(
                      child: _channelCard(
                        _data.channelTotals[i + 1],
                        colors[(i + 1) % colors.length],
                        cs,
                        sagana,
                        l10n,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _channelCard(
    SalesChannelTotal channel,
    Color accent,
    ColorScheme cs,
    SaganaColors sagana,
    AppLocalizations l10n,
  ) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
    final active = _sellingTypeFilter == channel.sellingType;
    final icon = _channelIcons[channel.sellingType] ?? Icons.point_of_sale_rounded;
    return GestureDetector(
      onTap: () => setState(() {
        _sellingTypeFilter = active ? null : channel.sellingType;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(AppConstants.spacingGutter),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: active ? 0.22 : 0.10),
              accent.withValues(alpha: active ? 0.10 : 0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          border: Border.all(color: accent.withValues(alpha: active ? 0.6 : 0.2), width: active ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const Spacer(),
            Text(
              _sellingTypeLabel(l10n, channel.sellingType),
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            const SizedBox(height: 4),
            Text(
              currency.format(channel.amount),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 20, color: accent),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              l10n.reportsTransactionCount(channel.transactionCount),
              style: GoogleFonts.inter(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendChart(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
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
          Row(
            children: [
              const Icon(Icons.show_chart_rounded, size: 15, color: AppConstants.primaryGreen),
              const SizedBox(width: 6),
              Text(
                l10n.reportsRevenueTrend,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSm),
          SizedBox(
            height: 120,
            child: _revenueTrend.length < 2
                ? Center(
                    child: Text(
                      l10n.reportsNotEnoughTrendData,
                      style: GoogleFonts.inter(fontSize: 12, color: cs.outline),
                    ),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 120),
                    painter: TrendChartPainter(
                      values: _revenueTrend,
                      lineColor: cs.primary,
                      gradientColor: cs.primary,
                      xLabels: _trailingMonthLabels(_revenueTrend.length),
                      yValueFormatter: (v) => '₱${v.toStringAsFixed(0)}',
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final filtered = _filteredTransactions;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.receipt_long_rounded, size: 16, color: AppConstants.primaryGreen),
            const SizedBox(width: 6),
            Text(
              l10n.reportsTransactionDetails,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
            if (_sellingTypeFilter != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _sellingTypeFilter = null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryGreen.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _sellingTypeLabel(l10n, _sellingTypeFilter!),
                        style: GoogleFonts.inter(fontSize: 10, color: AppConstants.primaryGreen),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.close_rounded, size: 12, color: AppConstants.primaryGreen),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_data.transactions.isNotEmpty)
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: l10n.reportsSearchTransactions,
              hintStyle: GoogleFonts.inter(fontSize: 13, color: cs.outline),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: cs.outline,
                size: 20,
              ),
            ),
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
          ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_data.transactions.isEmpty)
          ReportEmptyState(message: l10n.reportsNoSalesRecorded)
        else if (filtered.isEmpty)
          ReportEmptyState(message: l10n.reportsNoSearchResults)
        else
          ...filtered.map((t) => _buildTransactionRow(t, currency, cs, sagana, l10n)),
      ],
    );
  }

  static String _sellingTypeLabel(AppLocalizations l10n, String type) {
    switch (type) {
      case 'offer_to_cooperative': return l10n.sellingTypeOfferToCooperative;
      case 'marketplace': return l10n.navMarketplace;
      case 'informal_sale': return l10n.sellingTypeInformalSale;
      case 'da_amad_market_linking': return l10n.sellingTypeDaAmadMarketLinking;
      default: return type;
    }
  }

  static const _sellingTypeColors = {
    'offer_to_cooperative': AppConstants.primaryGreen,
    'marketplace': AppConstants.buyerBlue,
    'informal_sale': AppConstants.amber,
    'da_amad_market_linking': AppConstants.warningAmber,
  };

  Widget _buildTransactionRow(
    SalesTransactionRow t,
    NumberFormat currency,
    ColorScheme cs,
    SaganaColors sagana,
    AppLocalizations l10n,
  ) {
    final typeColor = _sellingTypeColors[t.sellingType] ?? cs.outline;
    final typeLabel = _sellingTypeLabel(l10n, t.sellingType);

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                child: Text(
                  typeLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: typeColor,
                  ),
                ),
              ),
              if (t.marketType != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.outline.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                  ),
                  child: Text(
                    t.marketType!,
                    style: GoogleFonts.inter(fontSize: 9, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                currency.format(t.amount),
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            '${t.cropName} • ${t.farmerName}',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: cs.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${t.memberId} • ${t.quantityKg.toStringAsFixed(0)} kg • ${DateFormat('MMM d, yyyy').format(t.saleDate)}'
            '${t.referenceNo != null ? ' • ${t.referenceNo}' : ''}',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: cs.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}