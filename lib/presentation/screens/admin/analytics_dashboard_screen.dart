import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/admin_analytics_model.dart';
import '../../../data/models/admin_reports_model.dart';
import '../../../data/models/analytics_model.dart';
import '../../../data/repositories/admin_analytics_repository.dart';
import '../../../data/repositories/analytics_repository.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/planting_forecast_card.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/top_harvested_crops_chart.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sub_page_top_bar.dart';
import '../../widgets/cached_data_notice.dart';
import '../../../data/services/connectivity_service.dart';

/// Analytics Dashboard — Admin.
/// Pushed above the shell. Route: /admin/analytics
///
/// Deliberately does not duplicate the Operational Reports hub's KPI
/// summary — that surface already belongs to Reports. This screen focuses
/// on what is genuinely analytical: a cooperative snapshot, member
/// participation, loan repayment, a price snapshot, top harvested crops and
/// the planting forecast. Every figure comes from data already stored; nothing
/// here is estimated.
///
/// Planting Recommendations are read-only and framed the same honest way
/// as the farmer-facing screen (supply-trend only, not demand-informed) —
/// there is no override mechanism, since crop_planting_forecast is a
/// computed SQL view, not a table.
class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  final _analyticsRepo = AnalyticsRepository();
  final _adminAnalyticsRepo = AdminAnalyticsRepository();

  bool _isLoading = true;
  bool _isOnline = ConnectivityService.instance.isOnline;

  List<PlantingForecast> _forecasts = [];
  List<TopSellingCrop> _topCrops = [];
  List<CropPriceCard> _priceCards = [];
  MemberParticipationSummary _participation =
      MemberParticipationSummary.empty();

  // Scoped to Member Participation only — Top Harvested Crops and Planting
  // Forecast read from fixed-window SQL views (see
  // supabase_schema_top_harvested_crops.sql), and the loan figures are
  // deliberately all-time / current. The selector sits inside the
  // Participation card so it is clear what it controls.
  ReportPeriod _participationPeriod = ReportPeriod.thisMonth;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.onConnectivityChanged.listen((v) {
      if (mounted) setState(() => _isOnline = v);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _analyticsRepo.fetchPlantingForecasts(),
      _analyticsRepo.fetchTopSellingCrops(),
      _analyticsRepo.fetchPriceCards(),
      _adminAnalyticsRepo.fetchMemberParticipation(
        since: _participationPeriod.range().startDate,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _forecasts = results[0] as List<PlantingForecast>;
      _topCrops = results[1] as List<TopSellingCrop>;
      _priceCards = results[2] as List<CropPriceCard>;
      _participation = results[3] as MemberParticipationSummary;
      _isLoading = false;
    });
  }

  Future<void> _setParticipationPeriod(ReportPeriod period) async {
    setState(() => _participationPeriod = period);
    final participation = await _adminAnalyticsRepo.fetchMemberParticipation(
      since: period.range().startDate,
    );
    if (!mounted) return;
    setState(() => _participation = participation);
  }

  /// Price Snapshot shows the current price for up to 4 crops, movers
  /// (a recorded price change) sorted first — but never hides a card just
  /// because none of them have moved yet: a crop with only one price ever
  /// recorded is still real, on-file data.
  List<CropPriceCard> get _priceSnapshotCards {
    final sorted = [..._priceCards]
      ..sort((a, b) {
        final ad = a.priceDiff?.abs() ?? -1;
        final bd = b.priceDiff?.abs() ?? -1;
        return bd.compareTo(ad);
      });
    return sorted.take(4).toList();
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
          SubPageTopBar(
            title: l10n.reportsAnalyticsDashboard,
            onBack: () => context.pop(),
          ),
          CachedDataNotice(
            screen: 'analytics_price_cards',
            otherScreens: const [
              'analytics_top_crops',
              'analytics_planting_forecast',
            ],
            isOnline: _isOnline,
            offlineMessage: l10n.offlinePriceData,
          ),
          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonList(),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.spacingSafeH,
                        AppConstants.spacingGutter,
                        AppConstants.spacingSafeH,
                        32,
                      ),
                      children: [
                        _buildParticipationCard(l10n, cs),
                        const SizedBox(height: AppConstants.spacingSectionV),
                        _buildPriceSnapshot(context, l10n, cs, sagana),
                        if (_topCrops.isNotEmpty) ...[
                          const SizedBox(height: AppConstants.spacingSectionV),
                          TopHarvestedCropsChart(crops: _topCrops),
                        ],
                        const SizedBox(height: AppConstants.spacingSectionV),
                        const PlantingForecastSectionHeader(),
                        const SizedBox(height: AppConstants.spacingMd),
                        if (_forecasts.isEmpty)
                          ReportEmptyState(
                            message: l10n.analyticsNoForecastsYet,
                          )
                        else
                          ..._forecasts.map(
                            (f) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppConstants.spacingMd,
                              ),
                              child: PlantingForecastCard(forecast: f),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipationCard(AppLocalizations l10n, ColorScheme cs) {
    final p = _participation;
    final participated = p.activeHarvestedCount + p.activeListedCount;
    final rate = p.totalMembers > 0 ? participated / p.totalMembers * 100 : 0.0;

    return ReportSectionCard(
      title: l10n.analyticsMemberParticipation,
      icon: Icons.diversity_3_rounded,
      subtitle: l10n.rptParticipationHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPeriodSelector(l10n, cs),
          const SizedBox(height: AppConstants.spacingMd),
          Row(
            children: [
              Expanded(
                child: _tierStat(
                  l10n.analyticsActiveHarvested,
                  p.activeHarvestedCount,
                  AppConstants.successGreen,
                ),
              ),
              const SizedBox(width: AppConstants.spacingSm),
              Expanded(
                child: _tierStat(
                  l10n.analyticsActiveListed,
                  p.activeListedCount,
                  AppConstants.buyerBlue,
                ),
              ),
              const SizedBox(width: AppConstants.spacingSm),
              Expanded(
                child: _tierStat(
                  l10n.rptNoActivity,
                  p.inactiveCount,
                  AppConstants.warningAmber,
                ),
              ),
            ],
          ),
          if (p.totalMembers > 0) ...[
            const SizedBox(height: AppConstants.spacingMd),
            _proportionBar(p),
            const SizedBox(height: 6),
            Text(
              '${l10n.rptActiveMembersCount(p.totalMembers)} · '
              '${l10n.reportsParticipationRate}: ${rate.toStringAsFixed(0)}%',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The three tiers as one segmented bar, in proportion to member counts.
  Widget _proportionBar(MemberParticipationSummary p) {
    Widget segment(int count, Color color) => count == 0
        ? const SizedBox.shrink()
        : Expanded(
            flex: count,
            child: Container(height: 8, color: color),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      child: Row(
        children: [
          segment(p.activeHarvestedCount, AppConstants.successGreen),
          segment(p.activeListedCount, AppConstants.buyerBlue),
          segment(p.inactiveCount, AppConstants.warningAmber),
        ],
      ),
    );
  }

  /// Segmented-pill period selector, visually mirroring Farmer Analytics'
  /// own period selector — reuses the ReportPeriod enum every Admin report
  /// uses. Lives inside the Participation card, the only section it controls.
  Widget _buildPeriodSelector(AppLocalizations l10n, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppConstants.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        children: reportPeriodChipOrder.map((p) {
          final isActive = p == _participationPeriod;
          return Expanded(
            child: GestureDetector(
              onTap: () => _setParticipationPeriod(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 36,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppConstants.primaryGreen
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
                // Same height and width for every segment; the label shrinks
                // to fit rather than wrapping or being cut off.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    reportPeriodLabel(l10n, p),
                    maxLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isActive ? Colors.white : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _tierStat(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: color,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSnapshot(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    SaganaColors sagana,
  ) {
    final cards = _priceSnapshotCards;

    return ReportSectionCard(
      title: l10n.analyticsPriceSnapshot,
      icon: Icons.sell_rounded,
      subtitle: l10n.rptPriceSnapshotHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cards.isEmpty)
            Text(
              l10n.reportsNotEnoughTrendData,
              style: GoogleFonts.inter(fontSize: 12, color: cs.outline),
            )
          else
            // Card-style display matching Price Management's own price cards
            // (image with market-type badge, name, price, % change,
            // freshness), read-only, one horizontally scrolling row.
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cards.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) =>
                    _PriceSnapshotCard(price: cards[i], cs: cs, sagana: sagana),
              ),
            ),
          const SizedBox(height: AppConstants.spacingSm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.priceManagement),
              child: Text(
                l10n.analyticsViewFullPrices,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.primaryGreen,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Price Snapshot's card — same visual language as Price Management's own
/// _PriceCard (price_management_screen.dart: image top with market-type
/// badge overlay, name/price/% delta/freshness below), minus its edit
/// affordance since this snapshot is read-only. Deliberately duplicated
/// here rather than importing that private class — _PriceCard isn't
/// exported, and this card's data source (CropPriceCard, a lighter shape
/// than PriceManagementRepository's own PriceRecordModel) differs anyway.
class _PriceSnapshotCard extends StatelessWidget {
  final CropPriceCard price;
  final ColorScheme cs;
  final SaganaColors sagana;

  const _PriceSnapshotCard({
    required this.price,
    required this.cs,
    required this.sagana,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final marketColor = MarketTypeDisplay.color(context, price.priceType);
    final hasImage = price.imageUrl != null && price.imageUrl!.isNotEmpty;
    final delta = _delta();

    return Container(
      width: 130,
      decoration: BoxDecoration(
        color: sagana.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 64,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                hasImage
                    ? Image.network(
                        price.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.4,
                          ),
                          child: Icon(
                            Icons.eco_rounded,
                            size: 26,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : Container(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.4,
                        ),
                        child: Icon(
                          Icons.eco_rounded,
                          size: 26,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: marketColor,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      MarketTypeDisplay.label(l10n, price.priceType),
                      style: GoogleFonts.inter(
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  price.cropName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        '₱${price.currentPrice.toStringAsFixed(2)}',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    if (delta != null) ...[
                      const SizedBox(width: 4),
                      Icon(delta.icon, size: 11, color: delta.color),
                      Text(
                        delta.label,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: delta.color,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.priceUpdatedPrefix(_updatedLabel()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 8, color: cs.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ({IconData icon, String label, Color color})? _delta() {
    final diff = price.priceDiff;
    if (diff == null || price.previousPrice == null || price.previousPrice == 0)
      return null;
    final pct = (diff / price.previousPrice!) * 100;
    if (pct.abs() < 0.01) {
      return (
        icon: Icons.horizontal_rule_rounded,
        label: '0%',
        color: AppConstants.outline,
      );
    }
    return (
      icon: pct > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
      label: '${pct.abs().toStringAsFixed(1)}%',
      color: pct > 0 ? AppConstants.successGreen : AppConstants.errorRed,
    );
  }

  String _updatedLabel() {
    final dt = price.recordedAt;
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}
