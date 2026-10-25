import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/export_model.dart';
import '../../../data/repositories/admin_reports_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/management_modal.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/report_ui_widgets.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';

/// Sales Report — Admin.
/// Pushed above the shell. Route: /admin/reports/sales
///
/// Unified across all four selling channels: Offer to Cooperative
/// (member_sales_transactions, any crop), Marketplace (completed orders),
/// Informal Sale (informal_sales) and DA-AMAD Market Linking
/// (market_linking_programs). Each channel card, and the channel chips above
/// the transaction list, filter the list below. Read-only.
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
  bool _isOnline = ConnectivityService.instance.isOnline;
  String _searchQuery = '';
  String? _channelFilter; // null = All Channels
  SalesReportData _data = SalesReportData.empty();
  SalesReportData _previousData = SalesReportData.empty();
  List<double> _revenueTrend = [];

  static final _money0 = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 0,
  );
  static final _money2 = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
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

  List<SalesTransactionRow> get _filteredTransactions {
    var list = _channelFilter == null
        ? _data.transactions
        : _data.transactions
              .where((t) => t.sellingType == _channelFilter)
              .toList();
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list
        .where(
          (t) =>
              t.farmerName.toLowerCase().contains(q) ||
              t.cropName.toLowerCase().contains(q) ||
              (t.referenceNo?.toLowerCase().contains(q) ?? false),
        )
        .toList();
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
            title: l10n.reportsSalesReport,
            onBack: () => context.pop(),
            trailing: IconButton(
              icon: Icon(Icons.file_download_outlined, color: cs.primary),
              onPressed: () => context.push(
                AppRoutes.exportCenter,
                extra: ExportCenterArgs(
                  preselectedModule: ReportModuleType.sales,
                  period: _period,
                ),
              ),
              tooltip: l10n.reportsExportCenter,
            ),
          ),
          CachedDataNotice(
            screen: AdminReportsRepository.salesCacheScreen(_period),
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
                  ReportPeriodFilter(period: _period, onSelected: _setPeriod),
                  const SizedBox(height: AppConstants.spacingGutter),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: SkeletonList(),
                    )
                  else ...[
                    _buildOverviewCard(l10n),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildChannelBreakdown(context, l10n, cs),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    ReportTrendCard(
                      title: l10n.reportsRevenueTrend,
                      values: _revenueTrend,
                      valueFormatter: (v) => '₱${v.toStringAsFixed(0)}',
                    ),
                    const SizedBox(height: AppConstants.spacingSectionV),
                    _buildTransactionsSection(context, l10n, cs),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(AppLocalizations l10n) {
    // A fixed absolute height per row, NOT a GridView childAspectRatio:
    // aspect ratio ties cell height to cell width, but this content (icon +
    // label + value, plus a delta row on Total Revenue) needs about the same
    // height on every device, so a narrow phone would overflow.
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

    return ReportSectionCard(
      title: l10n.reportsSalesOverview,
      icon: Icons.point_of_sale_rounded,
      subtitle: l10n.rptSalesOverviewHint,
      child: Column(
        children: [
          row(
            ReportIconStatCard(
              icon: Icons.payments_rounded,
              accent: AppConstants.primaryGreen,
              label: l10n.reportsTotalRevenue,
              value: _money0.format(_data.totalRevenue),
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
              label: l10n.rptAverageSale,
              value: _money0.format(_data.averageSaleAmount),
            ),
          ),
        ],
      ),
    );
  }

  static const _channelIcons = {
    'offer_to_cooperative': Icons.handshake_rounded,
    'marketplace': Icons.storefront_rounded,
    'informal_sale': Icons.people_alt_rounded,
    'da_amad_market_linking': Icons.local_shipping_rounded,
  };

  static const _channelColors = {
    'offer_to_cooperative': AppConstants.primaryGreen,
    'marketplace': AppConstants.buyerBlue,
    'informal_sale': AppConstants.amber,
    'da_amad_market_linking': AppConstants.warningAmber,
  };

  static String _channelLabel(AppLocalizations l10n, String type) {
    switch (type) {
      case 'offer_to_cooperative':
        return l10n.sellingTypeOfferToCooperative;
      case 'marketplace':
        return l10n.navMarketplace;
      case 'informal_sale':
        return l10n.sellingTypeInformalSale;
      case 'da_amad_market_linking':
        return l10n.sellingTypeDaAmadMarketLinking;
      default:
        return type;
    }
  }

  /// The four selling channels, each a distinct data source, with each
  /// channel's share of the period's revenue. Tapping a card filters the
  /// transaction list below.
  Widget _buildChannelBreakdown(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final totals = _data.channelTotals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.rptSalesBySellingChannel,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.reportsTapCardToFilter,
          style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppConstants.spacingMd),
        // Each row is as tall as its taller card (IntrinsicHeight), so a
        // two-line channel name never overflows and both cards in a row match.
        for (var i = 0; i < totals.length; i += 2)
          Padding(
            padding: EdgeInsets.only(
              bottom: i + 2 < totals.length ? AppConstants.spacingSm : 0,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _channelCard(totals[i], l10n, cs)),
                  if (i + 1 < totals.length) ...[
                    const SizedBox(width: AppConstants.spacingSm),
                    Expanded(child: _channelCard(totals[i + 1], l10n, cs)),
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
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final accent = _channelColors[channel.sellingType] ?? cs.primary;
    final active = _channelFilter == channel.sellingType;
    final icon =
        _channelIcons[channel.sellingType] ?? Icons.point_of_sale_rounded;
    final share = _data.totalRevenue > 0
        ? channel.amount / _data.totalRevenue * 100
        : 0.0;
    return GestureDetector(
      onTap: () => setState(() {
        _channelFilter = active ? null : channel.sellingType;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(AppConstants.spacingMd),
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
          border: Border.all(
            color: accent.withValues(alpha: active ? 0.6 : 0.2),
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon and channel name side by side, so the card stays short.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _channelLabel(l10n, channel.sellingType),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingSm),
            Text(
              _money0.format(channel.amount),
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: accent,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              l10n.reportsTransactionCount(channel.transactionCount),
              style: GoogleFonts.inter(
                fontSize: 10,
                color: cs.onSurfaceVariant,
              ),
            ),
            Text(
              l10n.rptSalesChannelShare(share.toStringAsFixed(0)),
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsSection(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final filtered = _filteredTransactions;
    final channelOptions = <ReportFilterOption<String?>>[
      ReportFilterOption<String?>(null, l10n.rptAllChannels),
      for (final c in _data.channelTotals)
        ReportFilterOption<String?>(
          c.sellingType,
          _channelLabel(l10n, c.sellingType),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.receipt_long_rounded,
              size: 16,
              color: AppConstants.primaryGreen,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.reportsTransactionDetails,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (_data.transactions.isNotEmpty)
              Text(
                l10n.rptShowingCount(filtered.length, _data.transactions.length),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingSm),
        if (_data.transactions.isNotEmpty) ...[
          ReportSearchField(
            controller: _searchController,
            hint: l10n.reportsSearchTransactions,
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          ReportFilterChips<String?>(
            options: channelOptions,
            selected: _channelFilter,
            onSelected: (v) => setState(() => _channelFilter = v),
          ),
          const SizedBox(height: AppConstants.spacingMd),
        ],
        if (_data.transactions.isEmpty)
          ReportEmptyState(message: l10n.rptSalesEmpty)
        else if (filtered.isEmpty)
          ReportEmptyState(message: l10n.rptNoMatches)
        else
          ...filtered.map((t) => _buildTransactionRow(t, cs, l10n)),
      ],
    );
  }

  Widget _buildTransactionRow(
    SalesTransactionRow t,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    final typeColor = _channelColors[t.sellingType] ?? cs.outline;
    return ReportRecordCard(
      onTap: () => _showTransactionDetails(context, t, l10n),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: ReportStatusPill(
                  label: _channelLabel(l10n, t.sellingType),
                  color: typeColor,
                ),
              ),
              if (t.marketType != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cs.outline.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      t.marketType!,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                _money2.format(t.amount),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${formatQuantityUnit(t.quantityKg, t.unit)} • '
            '${DateFormat('MMM d, yyyy').format(t.saleDate)}'
            '${t.referenceNo != null ? ' • ${t.referenceNo}' : ''}',
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showTransactionDetails(
    BuildContext context,
    SalesTransactionRow t,
    AppLocalizations l10n,
  ) {
    showManagementModal<void>(
      context: context,
      builder: (_) => ManagementModalShell(
        title: t.cropName,
        subtitle: _channelLabel(l10n, t.sellingType),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReportDetailRow(label: l10n.rptFarmer, value: t.farmerName),
            ReportDetailRow(
              label: l10n.rptSellingChannel,
              value: _channelLabel(l10n, t.sellingType),
            ),
            ReportDetailRow(
              label: l10n.rptQuantity,
              value: formatQuantityUnit(t.quantityKg, t.unit),
            ),
            ReportDetailRow(
              label: l10n.rptAmount,
              value: _money2.format(t.amount),
            ),
            ReportDetailRow(
              label: l10n.rptDate,
              value: DateFormat('MMM d, yyyy · h:mm a').format(t.saleDate),
            ),
            if (t.marketType != null)
              ReportDetailRow(label: l10n.rptMarketType, value: t.marketType!),
            if (t.referenceNo != null && t.referenceNo!.isNotEmpty)
              ReportDetailRow(
                label: l10n.rptReferenceNo,
                value: t.referenceNo!,
              ),
            if (t.orderStatus != null)
              ReportDetailRow(
                label: l10n.rptOrderStatus,
                value: t.orderStatus == 'completed'
                    ? l10n.rptStatusCompleted
                    : t.orderStatus!,
              ),
            if (t.buyerName != null && t.buyerName!.isNotEmpty)
              ReportDetailRow(
                label: l10n.rptSoldTo,
                value: t.buyerName!,
                isLast: true,
              ),
          ],
        ),
      ),
    );
  }
}
