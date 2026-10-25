import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/quantity_utils.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/models/analytics_model.dart';
import '../../../data/repositories/analytics_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/app_event_service.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/profile_state_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_routes.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/app_navigation_drawer.dart';
import '../../widgets/planting_forecast_card.dart';
import '../../widgets/report_summary_widgets.dart';
import '../../widgets/report_ui_widgets.dart';
import '../../widgets/shared_widgets.dart';
import '../../widgets/cached_data_notice.dart';
import '../../widgets/top_harvested_crops_chart.dart';
import '../../widgets/trend_chart_painter.dart';

/// Farmer → Analytics tab.
///
/// Visually follows the Manager's Analytics Dashboard: the same flat
/// [ReportSectionCard] sections, the same segmented period selector, the same
/// icon-badged stat tiles, bar rows and empty states, and the same shared
/// Top Harvested Crops and Planting Forecast widgets. The content stays the
/// farmer's own: their yield, revenue, expenses and recent sales, with the
/// cooperative's market prices and forecasts for context.
///
/// Every figure comes from data already stored — nothing here is estimated.
/// Money is shown to the centavo and quantities to their stored 2 decimals.

// Period labels live on AnalyticsPeriod as plain English
// (analytics_model.dart) since the model has no AppLocalizations access —
// same reasoning PlantingForecast's own trend label/explanation were moved
// out to their widget for (see planting_forecast_card.dart). Shared by the
// period selector pills and the Price History chart's period badge, so
// both sections can never show a differently-worded period label.
String _periodLabel(AppLocalizations l10n, AnalyticsPeriod p) {
  switch (p) {
    case AnalyticsPeriod.thisMonth:
      return l10n.farmerAnalyticsPeriodThisMonth;
    case AnalyticsPeriod.thisQuarter:
      return l10n.farmerAnalyticsPeriodThisQuarter;
    case AnalyticsPeriod.thisYear:
      return l10n.farmerAnalyticsPeriodThisYear;
    case AnalyticsPeriod.allTime:
      return l10n.farmerAnalyticsPeriodAllTime;
  }
}

final _pesoFormat = NumberFormat('#,##0.00');

/// `₱1,234.50` — always 2 decimals; a loss reads `-₱450.00`.
String _pesos(double value) =>
    '${value < 0 ? '-' : ''}₱${_pesoFormat.format(value.abs())}';

/// `1,250 kg` / `1,250.50 kg` — the stored 2 decimals, never rounded to whole.
String _kg(double value) {
  final v = roundQuantity(value);
  final format = NumberFormat(v == v.roundToDouble() ? '#,##0' : '#,##0.00');
  return '${format.format(v)} kg';
}

class FarmerAnalyticsScreen extends StatefulWidget {
  const FarmerAnalyticsScreen({super.key});

  @override
  State<FarmerAnalyticsScreen> createState() => _FarmerAnalyticsScreenState();
}

class _FarmerAnalyticsScreenState extends State<FarmerAnalyticsScreen> {
  final _repo = AnalyticsRepository();
  final _notifRepo = NotificationRepository();

  AnalyticsPeriod _period = AnalyticsPeriod.thisMonth;
  FarmPerformanceSummary _performance = FarmPerformanceSummary.empty;
  List<TransactionRecord> _transactions = [];
  List<CropPriceCard> _priceCards = [];
  List<PriceHistoryPoint> _priceHistory = [];
  List<PlantingForecast> _forecasts = [];
  List<TopSellingCrop> _topSelling = [];
  int _unreadCount = 0;

  CropPriceCard? _selectedPriceCard;

  /// True only until the first load finishes: a full-page skeleton, as the
  /// Manager's dashboard shows. Later refreshes keep the content on screen.
  bool _isLoading = true;

  /// A period change is in flight: the figures are dimmed and a thin bar
  /// shows, rather than the old numbers silently sitting under a new label.
  bool _isPeriodLoading = false;
  bool _isHistoryLoading = false;

  /// The whole load threw (the repositories normally absorb their own
  /// errors, so this is the safety net).
  bool _loadFailed = false;
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySubscription;

  // Sequence numbers: a slower, older response never overwrites a newer one
  // (tapping through the period chips quickly, or a refresh landing late).
  int _loadSeq = 0;
  int _periodSeq = 0;
  int _historySeq = 0;

  @override
  void initState() {
    super.initState();
    AppEventService.instance.addListener(_onDataChanged);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _isOnline = ConnectivityService.instance.isOnline;
    _connectivitySubscription = ConnectivityService
        .instance
        .onConnectivityChanged
        .listen((online) {
          if (mounted) setState(() => _isOnline = online);
        });
    _loadAll();
  }

  @override
  void dispose() {
    AppEventService.instance.removeListener(_onDataChanged);
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) _loadAll();
  }

  /// The two things the period selector controls (plus Price History, which
  /// is loaded separately): the farm performance totals and the recent
  /// transactions. Both take the same start date, so the list can never show
  /// a sale from outside the period under a revenue total that left it out.
  Future<(FarmPerformanceSummary, List<TransactionRecord>)> _fetchPeriodData(
    AnalyticsPeriod period,
  ) async {
    final results = await Future.wait([
      _repo.fetchFarmPerformance(period),
      _repo.fetchRecentTransactions(startDate: period.startDate),
    ]);
    return (
      results[0] as FarmPerformanceSummary,
      results[1] as List<TransactionRecord>,
    );
  }

  Future<void> _loadAll() async {
    final seq = ++_loadSeq;
    final periodSeq = ++_periodSeq;
    try {
      final results = await Future.wait([
        _fetchPeriodData(_period),
        _repo.fetchPriceCards(),
        _repo.fetchPlantingForecasts(),
        _repo.fetchTopSellingCrops(),
        _notifRepo.fetchUnreadCount(),
      ]);
      if (!mounted || seq != _loadSeq) return;

      final periodData =
          results[0] as (FarmPerformanceSummary, List<TransactionRecord>);
      final priceCards = results[1] as List<CropPriceCard>;

      // Keep the crop the farmer was looking at when it is still listed.
      CropPriceCard? selected;
      final previous = _selectedPriceCard;
      if (previous != null) {
        for (final c in priceCards) {
          if (c.cropName == previous.cropName &&
              c.priceType == previous.priceType) {
            selected = c;
          }
        }
      }
      selected ??= priceCards.isNotEmpty ? priceCards.first : null;

      setState(() {
        if (periodSeq == _periodSeq) {
          _performance = periodData.$1;
          _transactions = periodData.$2;
          _isPeriodLoading = false;
        }
        _priceCards = priceCards;
        _forecasts = results[2] as List<PlantingForecast>;
        _topSelling = results[3] as List<TopSellingCrop>;
        _unreadCount = results[4] as int;
        _selectedPriceCard = selected;
        _isLoading = false;
        _loadFailed = false;
      });

      if (selected != null) _loadPriceHistory(selected);
    } catch (_) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _isLoading = false;
        _isPeriodLoading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadPriceHistory(CropPriceCard card) async {
    final seq = ++_historySeq;
    setState(() {
      _selectedPriceCard = card;
      _isHistoryLoading = true;
    });
    final history = await _repo.fetchPriceHistory(
      card.cropName,
      priceType: card.priceType,
      startDate: _period.startDate,
    );
    if (!mounted || seq != _historySeq) return;
    setState(() {
      _priceHistory = history;
      _isHistoryLoading = false;
    });
  }

  Future<void> _onPeriodChanged(AnalyticsPeriod p) async {
    if (p == _period) return;
    final seq = ++_periodSeq;
    setState(() {
      _period = p;
      _isPeriodLoading = true;
    });
    // Price History follows the period as well (see the caption under the
    // selector), for whichever crop is currently selected.
    final card = _selectedPriceCard;
    if (card != null) unawaited(_loadPriceHistory(card));
    try {
      final data = await _fetchPeriodData(p);
      if (!mounted || seq != _periodSeq) return;
      setState(() {
        _performance = data.$1;
        _transactions = data.$2;
        _isPeriodLoading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted || seq != _periodSeq) return;
      setState(() {
        _isPeriodLoading = false;
        _loadFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: AnimatedBuilder(
        animation: FarmerProfileStateService.instance,
        builder: (context, _) {
          final profile = FarmerProfileStateService.instance.profile;
          return AppNavigationDrawer(
            photoUrl: profile?.profilePhotoUrl,
            displayName: profile?.fullName ?? 'Farmer',
            contactEmail: profile?.contactEmail,
            phoneNumber: profile?.phoneNumber,
            onEditProfile: () {
              Navigator.pop(context);
              context.pushRoute(AppRoutes.farmerEditProfile);
            },
            onEditFarmDetails: () {
              Navigator.pop(context);
              context.pushRoute(AppRoutes.editFarmDetails);
            },
            onMyAddresses: () {
              Navigator.pop(context);
              context.pushRoute(AppRoutes.myAddresses);
            },
            onSignOut: () => confirmFarmerSignOut(context),
            onAboutSagana: () => context.pushRoute(AppRoutes.aboutSagana),
            onAboutOrganization: () =>
                context.pushRoute(AppRoutes.aboutCooperative),
            onPrivacyPolicy: () => context.pushRoute(AppRoutes.privacyPolicy),
            onTermsOfUse: () => context.pushRoute(AppRoutes.termsOfUse),
          );
        },
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 72),
                    CachedDataNotice(
                      screen: AnalyticsRepository.farmPerformanceCacheScreen(
                        _period,
                      ),
                      otherScreens: [
                        ...AnalyticsRepository.farmPerformanceOtherCacheScreens(
                          _period,
                        ),
                        AnalyticsRepository.recentTransactionsCacheScreen(
                          startDate: _period.startDate,
                        ),
                        ...AnalyticsRepository.recentTransactionsOtherCacheScreens(
                          startDate: _period.startDate,
                        ),
                        'analytics_price_cards',
                        'analytics_planting_forecast',
                        'analytics_top_crops',
                        if (_selectedPriceCard != null)
                          AnalyticsRepository.priceHistoryCacheScreen(
                            _selectedPriceCard!.cropName,
                            priceType: _selectedPriceCard!.priceType,
                            startDate: _period.startDate,
                          ),
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
                              color: Theme.of(context).colorScheme.primary,
                              onRefresh: _loadAll,
                              child: _buildContent(),
                            ),
                    ),
                  ],
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FarmerTopBar(
                    title: l10n.navAnalytics,
                    unreadCount: _unreadCount,
                    hideProfileAvatar: true,
                    onProfileTap: () => context.goTab(AppRoutes.farmerProfile),
                    onNotificationTap: () =>
                        context.pushRoute(AppRoutes.farmerNotifications),
                    enableMenu: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return FarmerAnalyticsBody(
      period: _period,
      performance: _performance,
      transactions: _transactions,
      priceCards: _priceCards,
      selectedPriceCard: _selectedPriceCard,
      priceHistory: _priceHistory,
      forecasts: _forecasts,
      topCrops: _topSelling,
      isPeriodLoading: _isPeriodLoading,
      isHistoryLoading: _isHistoryLoading,
      loadFailed: _loadFailed,
      onPeriodChanged: _onPeriodChanged,
      onPriceCardSelected: _loadPriceHistory,
      onRetry: _loadAll,
    );
  }
}

/// The scrolling content of the Analytics tab, given plain data. The screen
/// above owns loading and state; this only lays it out, which is also what
/// lets the layout be checked at phone widths without a signed-in session.
@visibleForTesting
class FarmerAnalyticsBody extends StatelessWidget {
  final AnalyticsPeriod period;
  final FarmPerformanceSummary performance;
  final List<TransactionRecord> transactions;
  final List<CropPriceCard> priceCards;
  final CropPriceCard? selectedPriceCard;
  final List<PriceHistoryPoint> priceHistory;
  final List<PlantingForecast> forecasts;
  final List<TopSellingCrop> topCrops;
  final bool isPeriodLoading;
  final bool isHistoryLoading;
  final bool loadFailed;
  final ValueChanged<AnalyticsPeriod> onPeriodChanged;
  final ValueChanged<CropPriceCard> onPriceCardSelected;
  final VoidCallback onRetry;

  const FarmerAnalyticsBody({
    super.key,
    required this.period,
    required this.performance,
    required this.transactions,
    required this.priceCards,
    required this.selectedPriceCard,
    required this.priceHistory,
    required this.forecasts,
    required this.topCrops,
    this.isPeriodLoading = false,
    this.isHistoryLoading = false,
    this.loadFailed = false,
    required this.onPeriodChanged,
    required this.onPriceCardSelected,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const gap = SizedBox(height: AppConstants.spacingSectionV);
    return ListView(
      // Always scrollable, so pull-to-refresh works even on a short page.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingSafeH,
        AppConstants.spacingGutter,
        AppConstants.spacingSafeH,
        32,
      ),
      children: [
        _PerformanceCard(
          period: period,
          summary: performance,
          isRefreshing: isPeriodLoading,
          showLoadError: loadFailed || performance.hasLoadError,
          onPeriodChanged: onPeriodChanged,
          onRetry: onRetry,
        ),
        gap,
        _HarvestBreakdownCard(
          breakdown: performance.cropBreakdown,
          totalYieldKg: performance.totalYieldKg,
          otherUnitHarvestCount: performance.otherUnitHarvestCount,
        ),
        gap,
        _TransactionsCard(transactions: transactions),
        gap,

        // ── Price Monitoring ──────────────────────────────────────────────
        ReportSectionCard(
          title: l10n.farmerAnalyticsPriceMonitoringTitle,
          icon: Icons.sell_rounded,
          subtitle: l10n.farmerAnalyticsPriceFooterNote,
          child: priceCards.isEmpty
              ? ReportEmptyState(message: l10n.farmerAnalyticsNoPricesAvailable)
              : _PriceCardsRow(
                  cards: priceCards,
                  selected: selectedPriceCard,
                  onSelected: onPriceCardSelected,
                ),
        ),
        if (selectedPriceCard != null) ...[
          const SizedBox(height: AppConstants.spacingMd),
          _PriceHistoryCard(
            cropName: selectedPriceCard!.cropName,
            points: priceHistory,
            periodLabel: _periodLabel(l10n, period),
            isLoading: isHistoryLoading,
          ),
        ],
        gap,

        // ── Top Harvested Crops ───────────────────────────────────────────
        // Between Price Monitoring and Planting Forecast, the same order as
        // the Manager's dashboard. Shared with it, so both read identically.
        if (topCrops.isNotEmpty) ...[
          TopHarvestedCropsChart(
            crops: topCrops,
            title: l10n.farmerAnalyticsTopHarvestedCropsTitle,
          ),
          gap,
        ],

        // ── Planting Forecast ─────────────────────────────────────────────
        // PlantingForecastSectionHeader and PlantingForecastCard are shared
        // with the Manager's Analytics Dashboard.
        const PlantingForecastSectionHeader(),
        const SizedBox(height: AppConstants.spacingMd),
        if (forecasts.isEmpty)
          ReportEmptyState(message: l10n.analyticsNoForecastsYet)
        else
          ...forecasts.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingMd),
              child: PlantingForecastCard(forecast: f),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Farm Performance: period selector + the four headline figures
// ─────────────────────────────────────────────────────────────────────────────

class _PerformanceCard extends StatelessWidget {
  final AnalyticsPeriod period;
  final FarmPerformanceSummary summary;
  final bool isRefreshing;
  final bool showLoadError;
  final ValueChanged<AnalyticsPeriod> onPeriodChanged;
  final VoidCallback onRetry;

  const _PerformanceCard({
    required this.period,
    required this.summary,
    required this.isRefreshing,
    required this.showLoadError,
    required this.onPeriodChanged,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final loss = summary.netProfit < 0;

    return ReportSectionCard(
      title: l10n.farmerAnalyticsFarmPerformanceTitle,
      icon: Icons.agriculture_rounded,
      subtitle: l10n.farmerAnalyticsPeriodCaption,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PeriodSelector(active: period, onChanged: onPeriodChanged),
          // Reserves the bar's height so the layout does not jump.
          SizedBox(
            height: 6,
            child: isRefreshing
                ? const Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                : null,
          ),
          const SizedBox(height: AppConstants.spacingSm),
          if (showLoadError) ...[
            _LoadErrorBanner(onRetry: onRetry),
            const SizedBox(height: AppConstants.spacingMd),
          ],
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: isRefreshing ? 0.45 : 1,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ReportIconStatCard(
                        icon: Icons.grass_rounded,
                        accent: AppConstants.successGreen,
                        label: l10n.farmerAnalyticsTotalYield,
                        value: _kg(summary.totalYieldKg),
                        shrinkValueToFit: true,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingSm),
                    Expanded(
                      child: ReportIconStatCard(
                        icon: Icons.payments_rounded,
                        accent: cs.primary,
                        label: l10n.farmerAnalyticsTotalRevenue,
                        value: _pesos(summary.totalRevenue),
                        shrinkValueToFit: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingSm),
                Row(
                  children: [
                    Expanded(
                      child: ReportIconStatCard(
                        icon: Icons.receipt_long_rounded,
                        accent: AppConstants.errorRed,
                        label: l10n.farmerAnalyticsTotalExpenses,
                        value: _pesos(summary.totalExpenses),
                        shrinkValueToFit: true,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingSm),
                    Expanded(
                      child: ReportIconStatCard(
                        icon: loss
                            ? Icons.trending_down_rounded
                            : Icons.trending_up_rounded,
                        accent: loss
                            ? AppConstants.errorRed
                            : AppConstants.midGreen,
                        label: l10n.farmerAnalyticsNetProfit,
                        value: _pesos(summary.netProfit),
                        shrinkValueToFit: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          ReportInfoNote(text: l10n.farmerAnalyticsFarmPerformanceHint),
        ],
      ),
    );
  }
}

/// Segmented-pill period selector — the same control, size and colors as the
/// Manager's Analytics Dashboard. Every segment has the same width and height;
/// the label shrinks to fit rather than wrapping or being cut off.
class _PeriodSelector extends StatelessWidget {
  final AnalyticsPeriod active;
  final ValueChanged<AnalyticsPeriod> onChanged;

  const _PeriodSelector({required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppConstants.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Row(
        children: analyticsPeriodChipOrder.map((p) {
          final isActive = p == active;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(p),
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
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _periodLabel(l10n, p),
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
}

/// Shown when a figure could not be read and there is no saved copy: the
/// totals may be missing a source, and a zero here is not a real zero.
class _LoadErrorBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _LoadErrorBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    const accent = AppConstants.warningAmber;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.farmerAnalyticsLoadError,
              style: GoogleFonts.inter(fontSize: 11, color: cs.onSurface),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              l10n.farmerAnalyticsRetry,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppConstants.primaryGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Harvest by Crop
// ─────────────────────────────────────────────────────────────────────────────

class _HarvestBreakdownCard extends StatelessWidget {
  final List<CropYieldBreakdown> breakdown;
  final double totalYieldKg;
  final int otherUnitHarvestCount;

  const _HarvestBreakdownCard({
    required this.breakdown,
    required this.totalYieldKg,
    required this.otherUnitHarvestCount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ReportSectionCard(
      title: l10n.farmerAnalyticsHarvestByCropTitle,
      icon: Icons.grass_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (breakdown.isEmpty)
            ReportEmptyState(message: l10n.farmerAnalyticsNoHarvestData)
          else
            ...breakdown.map((b) {
              final share = totalYieldKg > 0
                  ? (b.quantityKg / totalYieldKg * 100).clamp(0, 100)
                  : null;
              return ReportBarRow(
                label: b.cropName,
                valueText: _kg(b.quantityKg),
                fraction: b.percentOfMax,
                color: AppConstants.successGreen,
                caption: share == null
                    ? null
                    : l10n.farmerAnalyticsShareOfYield(
                        share.toStringAsFixed(0),
                      ),
              );
            }),
          if (otherUnitHarvestCount > 0) ...[
            if (breakdown.isNotEmpty) const SizedBox(height: 4),
            ReportInfoNote(
              text: l10n.farmerAnalyticsOtherUnitsNote(otherUnitHarvestCount),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent Transactions
// ─────────────────────────────────────────────────────────────────────────────

class _TransactionsCard extends StatelessWidget {
  final List<TransactionRecord> transactions;
  const _TransactionsCard({required this.transactions});

  // Visual distinction between the four selling channels a transaction can
  // come from. Colors reuse tokens already meaningful elsewhere in this app:
  // buyerBlue for a Buyer marketplace order, primaryGreen for a cooperative
  // purchase (the cooperative's own brand color), gold for an informal
  // farm-gate sale, and purple for a DA-AMAD Market Linking round.
  static (IconData, Color) _sourceMeta(TransactionSource source) {
    switch (source) {
      case TransactionSource.marketplace:
        return (Icons.storefront_rounded, AppConstants.buyerBlue);
      case TransactionSource.cooperative:
        return (Icons.groups_rounded, AppConstants.primaryGreen);
      case TransactionSource.informal:
        return (Icons.handshake_rounded, AppConstants.gold);
      case TransactionSource.marketLinking:
        return (Icons.public_rounded, AppConstants.programPurple);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return ReportSectionCard(
      title: l10n.farmerAnalyticsRecentTransactionsTitle,
      icon: Icons.receipt_long_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (transactions.isEmpty)
            ReportEmptyState(message: l10n.farmerAnalyticsNoTransactions)
          else
            ...transactions.asMap().entries.map((entry) {
              final t = entry.value;
              final isLast = entry.key == transactions.length - 1;
              final (sourceIcon, sourceColor) = _sourceMeta(t.source);
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : Border(
                          bottom: BorderSide(
                            color: cs.outline.withValues(alpha: 0.10),
                          ),
                        ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: sourceColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(sourceIcon, size: 16, color: sourceColor),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.cropName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            l10n.farmerAnalyticsTransactionMeta(
                              DateFormat('MMM d, yyyy').format(t.date.toLocal()),
                              formatQuantityUnit(t.quantityKg, t.unit),
                              t.reference,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _pesos(t.totalAmount),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              );
            }),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.pushRoute(AppRoutes.myTransactionHistory),
              child: Text(
                l10n.farmerAnalyticsViewAllTransactions,
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

// ─────────────────────────────────────────────────────────────────────────────
// Price Cards Row
// ─────────────────────────────────────────────────────────────────────────────

class _PriceCardsRow extends StatelessWidget {
  final List<CropPriceCard> cards;
  final CropPriceCard? selected;
  final ValueChanged<CropPriceCard> onSelected;

  const _PriceCardsRow({
    required this.cards,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final sagana = context.saganaColors;
    // 170 fits the image (90) + name + price. Also has to clear
    // Container's own automatic border-width inset — BoxDecoration.border
    // adds implicit padding equal to its own width (so the active card's
    // 2px border quietly ate 4px of the Column's available height, and
    // even the inactive 1px border ate 2px), which is exactly why 160
    // overflowed by 2-4px depending on active state. The Margin/kg row
    // below adds its own height only when it renders — and today it never
    // does, since fetchPriceCards() never populates CropPriceCard.costPerKg
    // anywhere in the codebase, so marginPerKg is always null. If a future
    // cost-basis feature wires that field up, this fixed height will need
    // to grow back to fit that row too.
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final c = cards[i];
          final isActive =
              c.cropName == selected?.cropName &&
              c.priceType == selected?.priceType;
          final marketColor = MarketTypeDisplay.color(context, c.priceType);
          final hasImage = c.imageUrl != null && c.imageUrl!.isNotEmpty;
          // Same larger horizontal card layout as Home's Market Rates
          // carousel — image filling the card's upper portion with the
          // market-type badge overlaid top-left, crop identity and price
          // below. Surface and border follow the report cards' flat style.
          return GestureDetector(
            onTap: () => onSelected(c),
            child: Container(
              width: 180,
              decoration: BoxDecoration(
                color: sagana.cardBackground,
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                border: Border.all(
                  color: isActive
                      ? AppConstants.primaryGreen
                      : cs.outline.withValues(alpha: 0.20),
                  width: isActive ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 90,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        hasImage
                            ? Image.network(
                                c.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: marketColor.withValues(alpha: 0.12),
                                  child: Icon(
                                    Icons.eco_rounded,
                                    size: 32,
                                    color: marketColor,
                                  ),
                                ),
                              )
                            : Container(
                                color: marketColor.withValues(alpha: 0.12),
                                child: Icon(
                                  Icons.eco_rounded,
                                  size: 32,
                                  color: marketColor,
                                ),
                              ),
                        // Market-type badge: tells apart two cards of the
                        // same crop that have both a cooperative and an
                        // open-market price. Uses MarketTypeDisplay, the
                        // shared lookup Home and View Market also use.
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: marketColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              MarketTypeDisplay.label(l10n, c.priceType),
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        if (c.priceDiff != null)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (c.isUp
                                            ? AppConstants.successGreen
                                            : AppConstants.errorRed)
                                        .withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${c.isUp ? '↑' : '↓'} ₱${c.priceDiff!.abs().toStringAsFixed(2)}',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.cropName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? AppConstants.primaryGreen
                                : cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '₱${c.currentPrice.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '/kg',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        if (c.marginPerKg != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            height: 1,
                            color: cs.outline.withValues(alpha: 0.10),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l10n.farmerAnalyticsMarginPerKg,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '${c.hasPositiveMargin ? '+' : ''}₱${c.marginPerKg!.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: c.hasPositiveMargin
                                      ? AppConstants.successGreen
                                      : AppConstants.errorRed,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Price History
// ─────────────────────────────────────────────────────────────────────────────

class _PriceHistoryCard extends StatelessWidget {
  final String cropName;
  final List<PriceHistoryPoint> points;
  final String periodLabel;
  final bool isLoading;

  const _PriceHistoryCard({
    required this.cropName,
    required this.points,
    required this.periodLabel,
    required this.isLoading,
  });

  /// Axis labels are short on purpose (the gutter is narrow); the exact
  /// prices are in the Low / High / Latest row beneath the chart.
  static String _axisPrice(double v) =>
      v >= 100 ? '₱${v.round()}' : '₱${v.toStringAsFixed(1)}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final hasChart = points.length >= 2;
    final values = points.map((p) => p.price).toList();

    return ReportSectionCard(
      title: l10n.farmerAnalyticsPriceHistoryTitle(cropName),
      icon: Icons.show_chart_rounded,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppConstants.primaryGreen.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        child: Text(
          periodLabel,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppConstants.primaryGreen,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 150,
            width: double.infinity,
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : !hasChart
                ? Center(
                    child: Text(
                      l10n.farmerAnalyticsNoPriceHistory,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 150),
                    painter: TrendChartPainter(
                      values: values,
                      lineColor: cs.primary,
                      gradientColor: cs.primary,
                      // One label per point; the painter draws the first,
                      // middle and last, so the dates are the real ones.
                      xLabels: [
                        for (final p in points)
                          DateFormat('MMM d').format(p.date.toLocal()),
                      ],
                      yValueFormatter: _axisPrice,
                    ),
                  ),
          ),
          if (hasChart && !isLoading) ...[
            const SizedBox(height: AppConstants.spacingMd),
            Row(
              children: [
                Expanded(
                  child: _PriceStat(
                    label: l10n.farmerAnalyticsPriceLow,
                    value: formatPesos(values.reduce((a, b) => a < b ? a : b)),
                  ),
                ),
                Expanded(
                  child: _PriceStat(
                    label: l10n.farmerAnalyticsPriceHigh,
                    value: formatPesos(values.reduce((a, b) => a > b ? a : b)),
                  ),
                ),
                Expanded(
                  child: _PriceStat(
                    label: l10n.farmerAnalyticsPriceLatest,
                    value: formatPesos(values.last),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PriceStat extends StatelessWidget {
  final String label;
  final String value;
  const _PriceStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
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
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}
